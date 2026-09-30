//
//  AppState+TestRun.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What the sidebar lists.
enum SidebarSource: Hashable, Sendable {
    /// The project as it stands on disk, against its working tree.
    case project
    /// The snapshots the project's last test run failed on.
    case testRun
}

/// The failures of the project's last test run, as a second view of the project.
///
/// Nothing is read until the user switches to it: a project opens on its own status, and
/// reading a run exports images through `xcresulttool`, which is not free. Once read, the
/// results stay until a new run is written, so switching back and forth is instant. A
/// failing snapshot opens against the image its test rendered, so accepting that image is
/// re-recording the snapshot without running the test again.
extension AppState {
    /// Identifier of the suite holding the images the run attached that belong to no
    /// snapshot of the project.
    static let testRunSuiteID = "test-run:attachments"
    /// How long the result folder has to stay quiet before a new bundle is read.
    ///
    /// A run writes its bundle for as long as it lasts, and a bundle read halfway through
    /// fails or says too little. Every new event restarts the wait.
    static let testRunSettleDelay = Duration.seconds(1)

    // MARK: - Switching

    /// Whether there is a project on disk to have run the tests of, as opposed to nothing
    /// open or a pull request under review.
    private var isProjectOnDisk: Bool {
        currentProject != nil && !isReviewingPullRequest
    }

    /// Whether the sidebar can offer the last test run: the project is on disk and Xcode
    /// has a run of it.
    var canShowTestRun: Bool {
        isProjectOnDisk && latestTestRunBundle != nil
    }

    /// Whether the Project / Last Test Run switch is on screen.
    ///
    /// Only when there is a run to switch to — a control with one usable side is noise — but
    /// kept while the run is up, so a run that disappears from under it still has a way back.
    var showsSidebarSourcePicker: Bool {
        canShowTestRun || (isProjectOnDisk && sidebarSource == .testRun)
    }

    // MARK: - Locating

    /// Looks for a run of the open project, without reading it.
    ///
    /// Cheap enough to do on every load — one property list per workspace Xcode has built —
    /// and all the switch needs to know whether to appear.
    func locateTestRun() {
        testRunLocateTask?.cancel()
        guard isProjectOnDisk, let project = currentProject else {
            latestTestRunBundle = nil
            return
        }

        testRunLocateTask = Task { [testResultLocator] in
            let bundle = await Self.latestBundle(of: project, locator: testResultLocator)
            guard !Task.isCancelled, currentProject?.rootURL == project.rootURL else { return }
            latestTestRunBundle = bundle
        }
    }

    /// The search in flight, if any, so a caller can wait for it.
    var currentTestRunLocate: Task<Void, Never>? { testRunLocateTask }

    /// Whether the run's view has no rows to show, only a state: being read, unreadable, or
    /// failing on nothing.
    var isShowingTestRunPlaceholder: Bool {
        guard sidebarSource == .testRun else { return false }
        return (isReadingTestRun && testRun == nil) || testRunError != nil || testRun?.isEmpty == true
    }

    /// Lists what the last test run failed on, reading it first if it has not been read.
    func showTestRun() {
        guard canShowTestRun, sidebarSource != .testRun else { return }
        sidebarSource = .testRun
        // The filters describe the project's status, not the run's failures.
        clearFilters()

        if testRun == nil {
            refreshTestRun()
        } else {
            settleSelectionAfterSwitch()
        }
    }

    /// Goes back to listing the project as it stands. The run stays read.
    func showProjectStatus() {
        guard sidebarSource != .project else { return }
        sidebarSource = .project
        clearFilters()
        settleSelectionAfterSwitch()
    }

    /// Puts the selection and the canvas where the view just switched to can show them.
    ///
    /// A snapshot still listed stays selected and is shown again, because what the canvas
    /// compares it with depends on the view. Otherwise the run's view selects its first
    /// failure, which is what switching to it was for, and the project's keeps a suite row.
    private func settleSelectionAfterSwitch() {
        if sidebarSource == .testRun {
            // Every suite with a failure opens: the run is read to see what failed.
            let failing = visibleRows.compactMap { row -> String? in
                guard case let .suite(suite, _, childCount) = row, childCount > 0 else { return nil }
                return suite.id
            }
            expandSuites(failing)
        }

        let rows = visibleRows
        if let snapshot = selectedRow?.snapshot {
            showSnapshot(snapshot, withGitDiff: true)
            return
        }
        if selectedRow != nil, sidebarSource == .project { return }

        selectRow(withID: rows.first(where: \.isSnapshot)?.id ?? rows.first?.id)
        if selectedRow == nil { closePreview() }
    }

    // MARK: - Reading

    /// Reads the newest run of the open project.
    ///
    /// - Parameter settling: Whether to wait for the result folder to go quiet first, for a
    ///   refresh set off by a run that may still be writing.
    func refreshTestRun(settling: Bool = false) {
        testRunTask?.cancel()
        guard isProjectOnDisk, let project = currentProject else {
            discardTestRun()
            return
        }

        isReadingTestRun = true
        testRunError = nil
        testRunTask = Task { [testResults, testResultLocator, filesystem] in
            if settling {
                do {
                    try await Task.sleep(for: Self.testRunSettleDelay)
                } catch {
                    return
                }
            }

            let bundle = await Self.latestBundle(of: project, locator: testResultLocator)
            if !Task.isCancelled { latestTestRunBundle = bundle }
            guard let bundle else {
                guard !Task.isCancelled else { return }
                // The run the tree was showing has gone with its derived data.
                discardTestRun()
                testRunError = "Xcode has no test results for this project. Run its tests, then try again."
                return
            }

            let results: TestRunResults
            do {
                results = try await Self.results(of: bundle, in: project, reader: testResults, filesystem: filesystem)
            } catch {
                guard !Task.isCancelled else { return }
                isReadingTestRun = false
                // A bundle that cannot be read may still be being written; results already on
                // screen stay there until it can be.
                if testRun == nil { testRunError = error.localizedDescription }
                return
            }

            guard !Task.isCancelled,
                  isProjectOnDisk,
                  currentProject?.rootURL == project.rootURL
            else {
                Self.removeScratch(of: results, filesystem: filesystem)
                return
            }
            isReadingTestRun = false
            replaceTestRun(with: results)
        }
    }

    /// The read in flight, if any, so a caller can wait for it.
    var currentTestRunRefresh: Task<Void, Never>? { testRunTask }

    /// Off the main actor: finding the bundle reads a property list per workspace Xcode has
    /// ever built.
    @concurrent
    private static func latestBundle(
        of project: ProjectBundle,
        locator: any TestResultLocating
    ) async -> URL? {
        locator.latestResultBundle(forProjectAt: project.rootURL, gitRootURL: project.gitRootURL)
    }

    /// Off the main actor as well: matching reads the attached images and every snapshot
    /// of the same length.
    @concurrent
    private static func results(
        of bundle: URL,
        in project: ProjectBundle,
        reader: any TestResultReading,
        filesystem: any FilesystemService
    ) async throws -> TestRunResults {
        let report = try await reader.report(forBundleAt: bundle)
        do {
            let differences = try TestRunMatcher(filesystem: filesystem)
                .differences(in: report, against: project)
            return TestRunResults(report: report, differences: differences)
        } catch {
            try? filesystem.removeItem(at: report.scratchDirectory)
            throw error
        }
    }

    private func replaceTestRun(with results: TestRunResults) {
        let previous = testRun
        let rowsBefore = visibleRows
        setTestRun(results)
        if let previous { Self.removeScratch(of: previous, filesystem: filesystem) }
        // A run with nothing to show has no images worth keeping on disk.
        if results.isEmpty { Self.removeScratch(of: results, filesystem: filesystem) }

        guard sidebarSource == .testRun else { return }
        guard previous != nil else {
            settleSelectionAfterSwitch()
            return
        }

        // A newer run can take away the row under the selection.
        let rows = visibleRows
        if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectedRowID = Self.survivor(of: selected, among: rowsBefore, in: rows)
        }

        // The canvas follows a snapshot whose standing changed, but only if it is on one.
        guard let shownID = preview?.snapshotID else { return }
        if Self.isTestRunAttachment(snapshotID: shownID) {
            if !rows.contains(where: { $0.snapshot?.id == shownID }) { closePreview() }
        } else if let snapshot = projectSnapshot(withID: shownID), previewFollowsTestRun(snapshot) {
            showSnapshot(snapshot, withGitDiff: true)
        }
    }

    /// Whether the preview of `snapshot` no longer says what the run did to it: it shows a
    /// failure the run no longer has, or none where it now has one.
    private func previewFollowsTestRun(_ snapshot: SnapshotItem) -> Bool {
        let candidates = testRun?.candidates(forSnapshotID: snapshot.id) ?? []
        switch preview {
        case let .testRunFailure(pair, _, _):
            return !candidates.contains { $0.fileURL == pair.failure.url }
        case .single:
            return !candidates.isEmpty
        default:
            return false
        }
    }

    private func projectSnapshot(withID id: String) -> SnapshotItem? {
        currentProject?.suites.lazy.flatMap(\.snapshots).first { $0.id == id }
    }

    /// Forgets the run's results and deletes their images.
    func discardTestRun() {
        testRunTask?.cancel()
        testRunTask = nil
        isReadingTestRun = false
        testRunError = nil
        guard let testRun else { return }
        setTestRun(nil)
        Self.removeScratch(of: testRun, filesystem: filesystem)
        if let shown = preview?.snapshotID, Self.isTestRunAttachment(snapshotID: shown) {
            closePreview()
        }
    }

    /// Deletes the images of the results on screen, for the app to call on its way out.
    func discardTestRunFiles() {
        testRunTask?.cancel()
        guard let testRun else { return }
        Self.removeScratch(of: testRun, filesystem: filesystem)
    }

    private static func removeScratch(of results: TestRunResults, filesystem: any FilesystemService) {
        guard filesystem.fileExists(at: results.scratchDirectory) else { return }
        try? filesystem.removeItem(at: results.scratchDirectory)
    }

    /// Answers a change where Xcode writes the project's result bundles.
    ///
    /// On screen, the new run replaces the old one once it is written. Off screen, the old
    /// one is only forgotten, so the next switch reads the new one without paying for a read
    /// nobody may ask for.
    func testResultsChanged() {
        // A first run, or derived data deleted, is what shows or hides the switch.
        locateTestRun()
        if sidebarSource == .testRun {
            refreshTestRun(settling: true)
        } else {
            discardTestRun()
        }
    }

    // MARK: - Watching

    /// Whether any of `events` happened where Xcode writes the project's result bundles.
    func touchesTestResults(_ events: [ProjectFileEvent]) -> Bool {
        guard !testResultDirectories.isEmpty else { return false }
        return events.contains { event in
            let path = event.url.standardizedFileURL.path
            return testResultDirectories.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    // MARK: - Rows

    /// Whether the last run failed on `snapshot`, or attached it.
    func isFailingInTestRun(_ snapshot: SnapshotItem) -> Bool {
        Self.isTestRunAttachment(snapshotID: snapshot.id) || testRun?.isFailing(snapshotID: snapshot.id) == true
    }

    /// Whether a suite row carries the missing-source warning.
    ///
    /// Never the run's attachments: they belong to no test file, and that is not a fault
    /// anybody can fix.
    func hasSourceWarning(_ suite: SnapshotSuite) -> Bool {
        suite.isMissingSourceCode && suite.id != Self.testRunSuiteID
    }

    /// How many snapshots under `suite` the last run failed on.
    func failingSnapshotsCount(in suite: SnapshotSuite) -> Int {
        suite.snapshots.filter(isFailingInTestRun).count
    }

    static func isTestRunAttachment(snapshotID: String) -> Bool {
        snapshotID.hasPrefix(testRunSuiteID + ":")
    }

    /// The images the run attached that belong to no snapshot, as a suite of their own.
    ///
    /// Kept rather than dropped: an image that matches nothing is a snapshot recorded for
    /// the first time, or one whose baseline has been replaced since, and both are worth
    /// seeing. Each image is its own row, named after the test and the attachment.
    var testRunAttachmentsSuite: SnapshotSuite? {
        guard let testRun else { return nil }
        let items = testRun.unmatched.flatMap { difference in
            difference.candidates.map { image in
                SnapshotItem(
                    id: "\(Self.testRunSuiteID):\(difference.id):\(image.id)",
                    name: "\(difference.testName) · \(image.name)",
                    fileURL: image.fileURL
                )
            }
        }
        guard !items.isEmpty else { return nil }

        return SnapshotSuite(
            id: Self.testRunSuiteID,
            name: "Unmatched Test Run Attachments",
            snapshotsFolderURL: testRun.scratchDirectory,
            snapshots: items,
            providerId: Self.testRunSuiteID
        )
    }

    /// Refuses to delete an image the run attached, saying why.
    func refusesDeletionOfTestRunAttachments(in suiteID: String) -> Bool {
        guard suiteID == Self.testRunSuiteID else { return false }
        report("These images were copied out of the last test run; there is nothing in the project to delete.")
        return true
    }

    // MARK: - Canvas

    /// Shows `snapshot` against one of the images its test attached.
    func showTestRunCandidate(_ candidate: TestRunImage, against snapshot: SnapshotItem) {
        setPreview(.testRunFailure(
            SnapshotPair(reference: snapshot.fileURL, failure: candidate.fileURL),
            snapshotID: snapshot.id,
            title: snapshot.displayName
        ))
    }

    /// Every image the snapshot on screen was attached with, for the candidate pane to
    /// switch between.
    var testRunCandidatesOnScreen: [TestRunImage] {
        guard case let .testRunFailure(_, snapshotID, _) = preview else { return [] }
        return testRun?.candidates(forSnapshotID: snapshotID) ?? []
    }

    /// Puts another of the attached images in the candidate pane.
    func selectTestRunCandidate(_ candidate: TestRunImage) {
        guard case let .testRunFailure(pair, snapshotID, title) = preview else { return }
        setPreview(.testRunFailure(
            SnapshotPair(reference: pair.reference.url, failure: candidate.fileURL),
            snapshotID: snapshotID,
            title: title
        ))
    }

    /// The name the image at `url` was attached under, when it came from the run.
    func testRunImageName(at url: URL) -> String? {
        testRun?.image(at: url)?.name
    }

    /// Takes a snapshot out of the run's failures once its candidate has been accepted.
    ///
    /// The snapshot is settled and leaves the run's list, so the selection moves on — to the
    /// next failure, which is where somebody accepting them one by one is going.
    func resolveTestRunFailure(snapshotID: String) {
        let rowsBefore = visibleRows
        if var updated = testRun {
            updated.resolve(snapshotID: snapshotID)
            setTestRun(updated)
            if updated.isEmpty { Self.removeScratch(of: updated, filesystem: filesystem) }
        }

        let rows = visibleRows
        if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectRow(withID: Self.survivor(of: selected, among: rowsBefore, in: rows))
        } else if let snapshot = projectSnapshot(withID: snapshotID) {
            setPreview(.single(snapshot))
        }
    }
}
