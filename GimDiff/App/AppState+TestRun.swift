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
    /// The snapshots one of the project's test runs failed on — the newest, unless another
    /// was picked from the history.
    case testRun
}

/// The failures of one of the project's test runs, as a second view of the project.
///
/// ``TestRunModel`` finds and reads the runs; this is what a run does to the window: the
/// view switch, the selection and the canvas when results arrive, and the canvas methods
/// that compare a failing snapshot with what its test rendered.
///
/// Every run Xcode still keeps is offered, newest first, and the newest is the one shown
/// until somebody picks another. A picked run stays on screen when a newer one arrives;
/// following the newest again is a matter of picking it.
///
/// Nothing is read until the user switches to it: a project opens on its own status, and
/// reading a run exports images through `xcresulttool`, which is not free. Once read, the
/// results stay until a new run is written, so switching back and forth is instant. A
/// failing snapshot opens against the image its test rendered, so accepting that image is
/// re-recording the snapshot without running the test again.
extension AppState {
    // MARK: - Switching

    /// Whether there is a project on disk to have run the tests of, as opposed to nothing
    /// open or a pull request under review.
    private var isProjectOnDisk: Bool {
        currentProject != nil && !isReviewingPullRequest
    }

    /// Whether the sidebar can offer a test run: the project is on disk and Xcode has a run
    /// of it.
    var canShowTestRun: Bool {
        isProjectOnDisk && !testRuns.bundles.isEmpty
    }

    /// Whether the Project / Test Run switch is on screen.
    ///
    /// Only when there is a run to switch to — a control with one usable side is noise — but
    /// kept while the run is up, so a run that disappears from under it still has a way back.
    var showsSidebarSourcePicker: Bool {
        canShowTestRun || (isProjectOnDisk && sidebarSource == .testRun)
    }

    /// Looks for the runs of the open project, without reading any of them.
    func locateTestRun() {
        testRuns.locate(project: isProjectOnDisk ? currentProject : nil)
    }

    /// Whether the run's view has no rows to show, only a state: being read, unreadable, or
    /// failing on nothing.
    var isShowingTestRunPlaceholder: Bool {
        guard sidebarSource == .testRun else { return false }
        return (testRuns.isReading && testRuns.results == nil)
            || testRuns.error != nil
            || testRuns.results?.isEmpty == true
    }

    /// Lists what the selected test run failed on, reading it first if it has not been read.
    func showTestRun() {
        guard canShowTestRun, sidebarSource != .testRun else { return }
        sidebarSource = .testRun
        // The filters describe the project's status, not the run's failures.
        clearFilters()

        if testRuns.results == nil {
            refreshTestRun()
        } else {
            settleSelectionAfterSwitch()
        }
    }

    /// Lists what the run in `bundle` failed on, in place of whichever run was read.
    func showTestRun(from bundle: URL) {
        guard isProjectOnDisk, testRuns.bundles.contains(where: { $0.url == bundle }) else { return }
        testRuns.pick(bundle)
        guard testRuns.results?.bundleURL != bundle else {
            showTestRun()
            return
        }

        discardTestRun()
        // The candidate on the canvas was a copy out of the run just discarded.
        if case .testRunFailure = canvas.preview { canvas.close() }
        if sidebarSource == .testRun {
            refreshTestRun()
        } else {
            showTestRun()
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
        if selectedRow == nil { canvas.close() }
    }

    // MARK: - Reading

    /// Reads the selected run of the open project, and puts what it failed on in the tree.
    ///
    /// - Parameter settling: Whether to wait for the result folder to go quiet first, for a
    ///   refresh set off by a run that may still be writing.
    func refreshTestRun(settling: Bool = false) {
        guard isProjectOnDisk, let project = currentProject else {
            discardTestRun()
            return
        }

        testRuns.read(
            project: project,
            settling: settling,
            deliver: { [weak self] results in
                guard let self, isProjectOnDisk, currentProject?.rootURL == project.rootURL else { return false }
                replaceTestRun(with: results)
                return true
            },
            forget: { [weak self] in self?.discardTestRun() }
        )
    }

    private func replaceTestRun(with results: TestRunResults) {
        let hadResults = testRuns.results != nil
        let rowsBefore = visibleRows
        testRuns.replaceResults(with: results)

        guard sidebarSource == .testRun else { return }
        guard hadResults else {
            settleSelectionAfterSwitch()
            return
        }

        // A newer run can take away the row under the selection.
        let rows = visibleRows
        if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectedRowID = Self.survivor(of: selected, among: rowsBefore, in: rows)
        }

        // The canvas follows a snapshot whose standing changed, but only if it is on one.
        guard let shownID = canvas.preview?.snapshotID else { return }
        if TestRunModel.isAttachment(snapshotID: shownID) {
            if !rows.contains(where: { $0.snapshot?.id == shownID }) { canvas.close() }
        } else if let snapshot = projectSnapshot(withID: shownID), previewFollowsTestRun(snapshot) {
            showSnapshot(snapshot, withGitDiff: true)
        }
    }

    /// Whether the preview of `snapshot` no longer says what the run did to it: it shows a
    /// failure the run no longer has, or none where it now has one.
    private func previewFollowsTestRun(_ snapshot: SnapshotItem) -> Bool {
        let candidates = testRuns.results?.candidates(forSnapshotID: snapshot.id) ?? []
        switch canvas.preview {
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

    /// Forgets the run's results and deletes their images, closing the canvas when it shows
    /// one of them.
    func discardTestRun() {
        guard testRuns.forgetResults() else { return }
        if let shown = canvas.preview?.snapshotID, TestRunModel.isAttachment(snapshotID: shown) {
            canvas.close()
        }
    }

    /// Answers a change where Xcode writes the project's result bundles.
    ///
    /// On screen, the new run replaces the old one once it is written, unless an older run
    /// was picked from the history, which stays. Off screen, the old one is only forgotten,
    /// so the next switch reads the new one without paying for a read nobody may ask for.
    func testResultsChanged() {
        // A first run, or derived data deleted, is what shows or hides the switch.
        locateTestRun()
        if sidebarSource == .testRun {
            refreshTestRun(settling: true)
        } else {
            discardTestRun()
        }
    }

    // MARK: - Rows

    /// Whether a suite row carries the missing-source warning.
    ///
    /// Never the run's attachments: they belong to no test file, and that is not a fault
    /// anybody can fix.
    func hasSourceWarning(_ suite: SnapshotSuite) -> Bool {
        suite.isMissingSourceCode && suite.id != TestRunModel.attachmentsSuiteID
    }

    /// How many snapshots under `suite` the last run failed on.
    func failingSnapshotsCount(in suite: SnapshotSuite) -> Int {
        suite.snapshots.filter(testRuns.isFailing).count
    }

    /// Refuses to delete an image the run attached, saying why.
    func refusesDeletionOfTestRunAttachments(in suiteID: String) -> Bool {
        guard suiteID == TestRunModel.attachmentsSuiteID else { return false }
        report(String(localized: "These images were copied out of a test run; there is nothing in the project to delete."))
        return true
    }

    // MARK: - Canvas

    /// Shows `snapshot` against one of the images its test attached.
    func showTestRunCandidate(_ candidate: TestRunImage, against snapshot: SnapshotItem) {
        canvas.show(.testRunFailure(
            SnapshotPair(reference: snapshot.fileURL, failure: candidate.fileURL),
            snapshotID: snapshot.id,
            title: snapshot.displayName
        ))
    }

    /// Every image the snapshot on screen was attached with, for the candidate pane to
    /// switch between.
    var testRunCandidatesOnScreen: [TestRunImage] {
        guard case let .testRunFailure(_, snapshotID, _) = canvas.preview else { return [] }
        return testRuns.results?.candidates(forSnapshotID: snapshotID) ?? []
    }

    /// Puts another of the attached images in the candidate pane.
    func selectTestRunCandidate(_ candidate: TestRunImage) {
        guard case let .testRunFailure(pair, snapshotID, title) = canvas.preview else { return }
        canvas.show(.testRunFailure(
            SnapshotPair(reference: pair.reference.url, failure: candidate.fileURL),
            snapshotID: snapshotID,
            title: title
        ))
    }

    /// Takes a snapshot out of the run's failures once its candidate has been accepted.
    ///
    /// The snapshot is settled and leaves the run's list, so the selection moves on — to the
    /// next failure, which is where somebody accepting them one by one is going.
    func resolveTestRunFailure(snapshotID: String) {
        resolveTestRunFailures(snapshotIDs: [snapshotID])
    }

    /// Takes several snapshots out of the run's failures at once, moving the selection and
    /// the canvas a single time rather than once per snapshot.
    func resolveTestRunFailures(snapshotIDs: Set<String>) {
        let rowsBefore = visibleRows
        testRuns.resolve(snapshotIDs: snapshotIDs)

        let rows = visibleRows
        if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectRow(withID: Self.survivor(of: selected, among: rowsBefore, in: rows))
        }

        // The canvas must not stay on the failure just settled: its candidate is a copy in
        // the run's scratch folder, which is deleted once the run has nothing left to show.
        guard case let .testRunFailure(_, shownID, _) = canvas.preview, snapshotIDs.contains(shownID) else { return }
        if !isShowingTestRunPlaceholder, let snapshot = projectSnapshot(withID: shownID) {
            canvas.show(.single(snapshot))
        } else {
            canvas.close()
        }
    }
}
