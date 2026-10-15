//
//  TestRunModel.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The open project's test runs: which ones Xcode keeps, which one is picked, and what the
/// one read failed on.
///
/// Owns the reading and nothing about the window. What a new run does to the tree, the
/// selection, and the canvas is ``AppState``'s to decide, so a read hands its results back
/// rather than putting them in place itself; see ``read(project:settling:deliver:)``.
@MainActor
@Observable
final class TestRunModel {
    /// Identifier of the suite holding the images the run attached that belong to no
    /// snapshot of the project.
    static let attachmentsSuiteID = "test-run:attachments"
    /// How long the result folder has to stay quiet before a new bundle is read.
    ///
    /// A run writes its bundle for as long as it lasts, and a bundle read halfway through
    /// fails or says too little. Every new event restarts the wait.
    static let settleDelay = Duration.seconds(1)

    /// Every result bundle Xcode keeps for the open project, newest first.
    private(set) var bundles: [TestRunBundle] = []
    /// The run picked from the history, when it is not the newest. `nil` follows the newest.
    private(set) var pinnedBundleURL: URL?
    /// What the run read failed on; `nil` until it is read.
    private(set) var results: TestRunResults?
    /// Whether a read is in flight, so the sidebar can say so rather than look empty.
    private(set) var isReading = false
    /// Why the last read gave nothing, shown in place of the rows.
    private(set) var error: String?
    /// The folders Xcode writes the project's bundles into, as standardised paths, for the
    /// watcher to report on.
    private(set) var resultDirectories: [String] = []

    @ObservationIgnored private let reader: any TestResultReading
    @ObservationIgnored private let locator: any TestResultLocating
    @ObservationIgnored private let filesystem: any FilesystemService
    @ObservationIgnored private var locateTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?

    init(
        reader: any TestResultReading,
        locator: any TestResultLocating,
        filesystem: any FilesystemService
    ) {
        self.reader = reader
        self.locator = locator
        self.filesystem = filesystem
    }

    // MARK: - Bundles

    /// The newest result bundle; `nil` when the project has never been tested.
    var latestBundle: URL? {
        bundles.first?.url
    }

    /// The run the test run view shows, or would show if switched to: the one picked from
    /// the history while it still exists, the newest otherwise.
    var selectedBundle: TestRunBundle? {
        if let pinnedBundleURL, let bundle = bundles.first(where: { $0.url == pinnedBundleURL }) {
            return bundle
        }
        return bundles.first
    }

    /// Picks the run in `bundle`. Picking the newest is not pinning it: the view then
    /// follows the newest again, so the next run Xcode writes replaces it as it always did.
    func pick(_ bundle: URL) {
        pinnedBundleURL = bundle == latestBundle ? nil : bundle
    }

    /// Looks for the runs of `project`, without reading any of them, or forgets them all
    /// when there is no project on disk.
    ///
    /// Cheap enough to do on every load — one property list per workspace Xcode has built,
    /// and one per run — and all the switch and the run picker need to know.
    func locate(project: ProjectBundle?) {
        locateTask?.cancel()
        guard let project else {
            bundles = []
            return
        }

        locateTask = Task { [locator] in
            let bundles = await Self.bundles(of: project, locator: locator)
            guard !Task.isCancelled else { return }
            self.bundles = bundles
        }
    }

    /// The search in flight, if any, so a caller can wait for it.
    var currentLocate: Task<Void, Never>? { locateTask }

    /// Finds where Xcode writes `project`'s bundles, for the watcher, or forgets them.
    func updateResultDirectories(for project: ProjectBundle?) {
        resultDirectories = project.map { project in
            locator.resultDirectories(for: project).map(\.standardizedFileURL.path)
        } ?? []
    }

    /// Whether any of `events` happened where Xcode writes the project's result bundles.
    func touchesResults(_ events: [ProjectFileEvent]) -> Bool {
        guard !resultDirectories.isEmpty else { return false }
        return events.contains { event in
            let path = event.url.standardizedFileURL.path
            return resultDirectories.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    // MARK: - Reading

    /// Reads the selected run of `project`: the one picked from the history, or the newest
    /// when none was or the one picked has since been deleted.
    ///
    /// - Parameters:
    ///   - settling: Whether to wait for the result folder to go quiet first, for a read
    ///     set off by a run that may still be writing.
    ///   - deliver: Puts results that were read in place, and answers whether they were
    ///     wanted. Results it turns down have their images deleted.
    ///   - forget: Forgets the results read so far, when the run they came from is gone.
    ///     Defaults to ``forgetResults()``; the caller passes its own when forgetting has
    ///     to reach further, as closing a canvas that shows one of the run's images.
    func read(
        project: ProjectBundle,
        settling: Bool = false,
        deliver: @escaping @MainActor (TestRunResults) -> Bool,
        forget: (@MainActor () -> Void)? = nil
    ) {
        readTask?.cancel()
        isReading = true
        error = nil
        readTask = Task { [reader, locator, filesystem] in
            if settling {
                do {
                    try await Task.sleep(for: Self.settleDelay)
                } catch {
                    return
                }
            }

            let bundles = await Self.bundles(of: project, locator: locator)
            guard !Task.isCancelled else { return }
            self.bundles = bundles
            if let pinned = pinnedBundleURL, !bundles.contains(where: { $0.url == pinned }) {
                pinnedBundleURL = nil
            }
            guard let bundle = selectedBundle else {
                // The run the tree was showing has gone with its derived data or build folder.
                if let forget { forget() } else { forgetResults() }
                error = String(localized: "There are no test results for this project. Run its tests, then try again.")
                return
            }
            // A run picked from the history is finished; only the newest can still be growing.
            if pinnedBundleURL != nil, results?.bundleURL == bundle.url {
                isReading = false
                return
            }

            let read: TestRunResults
            do {
                read = try await Self.results(of: bundle, in: project, reader: reader, filesystem: filesystem)
            } catch {
                guard !Task.isCancelled else { return }
                isReading = false
                // A bundle that cannot be read may still be being written; results already on
                // screen stay there until it can be.
                if results == nil { self.error = error.localizedDescription }
                return
            }

            guard !Task.isCancelled else {
                removeScratch(of: read)
                return
            }
            isReading = false
            if !deliver(read) { removeScratch(of: read) }
        }
    }

    /// The read in flight, if any, so a caller can wait for it.
    var currentRead: Task<Void, Never>? { readTask }

    /// Off the main actor: finding the bundles reads a property list per workspace Xcode
    /// has ever built, and one per bundle, and lists every module's Paparazzi failures.
    @concurrent
    private static func bundles(
        of project: ProjectBundle,
        locator: any TestResultLocating
    ) async -> [TestRunBundle] {
        locator.resultBundles(for: project)
    }

    /// Off the main actor as well: matching reads the attached images and every snapshot
    /// of the same length.
    @concurrent
    private static func results(
        of bundle: TestRunBundle,
        in project: ProjectBundle,
        reader: any TestResultReading,
        filesystem: any FilesystemService
    ) async throws -> TestRunResults {
        let report = try await reader.report(for: bundle)
        do {
            let differences = try TestRunMatcher(filesystem: filesystem)
                .differences(in: report, against: project)
            return TestRunResults(report: report, differences: differences)
        } catch {
            try? filesystem.removeItem(at: report.scratchDirectory)
            throw error
        }
    }

    // MARK: - Results

    /// Puts `newResults` in place of the run read so far, deleting the old one's images, and
    /// the new one's too when it has nothing to show.
    func replaceResults(with newResults: TestRunResults) {
        if let results { removeScratch(of: results) }
        results = newResults
        if newResults.isEmpty { removeScratch(of: newResults) }
    }

    /// Takes `snapshotIDs` out of the failures, once their candidates have been accepted.
    func resolve(snapshotIDs: Set<String>) {
        guard var updated = results else { return }
        updated.resolve(snapshotIDs: snapshotIDs)
        results = updated
        if updated.isEmpty { removeScratch(of: updated) }
    }

    /// Forgets the run's results and deletes their images, and stops any read.
    ///
    /// - Returns: Whether there were results to forget.
    @discardableResult
    func forgetResults() -> Bool {
        readTask?.cancel()
        readTask = nil
        isReading = false
        error = nil
        guard let results else { return false }
        self.results = nil
        removeScratch(of: results)
        return true
    }

    /// Forgets everything about the last project's runs: the results, the bundles, and the
    /// run picked.
    func reset() {
        forgetResults()
        locateTask?.cancel()
        bundles = []
        pinnedBundleURL = nil
    }

    /// Deletes the images of the results on screen, for the app to call on its way out.
    func discardFiles() {
        readTask?.cancel()
        guard let results else { return }
        removeScratch(of: results)
    }

    private func removeScratch(of results: TestRunResults) {
        guard filesystem.fileExists(at: results.scratchDirectory) else { return }
        try? filesystem.removeItem(at: results.scratchDirectory)
    }

    // MARK: - Lookups

    static func isAttachment(snapshotID: String) -> Bool {
        snapshotID.hasPrefix(attachmentsSuiteID + ":")
    }

    /// Whether the run failed on `snapshot`, or attached it.
    func isFailing(_ snapshot: SnapshotItem) -> Bool {
        Self.isAttachment(snapshotID: snapshot.id) || results?.isFailing(snapshotID: snapshot.id) == true
    }

    /// The name the image at `url` was attached under, when it came from the run.
    func imageName(at url: URL) -> String? {
        results?.image(at: url)?.name
    }

    /// The images the run attached that belong to no snapshot, as a suite of their own.
    ///
    /// Kept rather than dropped: an image that matches nothing is a snapshot recorded for
    /// the first time, or one whose baseline has been replaced since, and both are worth
    /// seeing. Each image is its own row, named after the test and the attachment.
    var attachmentsSuite: SnapshotSuite? {
        guard let results else { return nil }
        let items = results.unmatched.flatMap { difference in
            difference.candidates.map { image in
                SnapshotItem(
                    id: "\(Self.attachmentsSuiteID):\(difference.id):\(image.id)",
                    name: "\(difference.testName) · \(image.name)",
                    fileURL: image.fileURL
                )
            }
        }
        guard !items.isEmpty else { return nil }

        return SnapshotSuite(
            id: Self.attachmentsSuiteID,
            name: String(localized: "Unmatched Test Run Attachments"),
            snapshotsFolderURL: results.scratchDirectory,
            snapshots: items,
            providerId: Self.attachmentsSuiteID
        )
    }
}
