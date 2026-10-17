//
//  AppState.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import Observation

/// State shared by every view in the single GimDiff window.
///
/// Also the composition root: `Engine` types name only protocols, so the concrete
/// `Infrastructure` services are chosen here and nowhere deeper.
@MainActor
@Observable
final class AppState {
    /// `UserDefaults` key the recent project list is persisted under.
    static let recentProjectsKey = "recent_projects"
    /// How many messages Window ▸ Recent Messages keeps.
    static let recentMessagesLimit = 10
    /// How many folders the recent list keeps before it starts forgetting the oldest.
    static let recentProjectsLimit = 12

    // MARK: - Project

    /// The folder a scan in flight is reading, so both columns can say what is on its way
    /// before the first open has a project to name.
    private(set) var loadingProjectURL: URL?
    /// Whether a scan is in flight. The sidebar shows a spinner rather than an empty tree.
    var isLoading: Bool { loadingProjectURL != nil }
    private(set) var currentProject: ProjectBundle?
    private(set) var recentProjects: [URL] = []

    // MARK: - Sidebar

    /// ``TreeRowItem/id`` of the selected row, which is what `List` binds its selection to.
    var selectedRowID: String?
    var filterText = ""
    var showGitModifiedOnly = false
    var showWarningsOnly = false
    /// Suites whose snapshots follow them in ``visibleRows``.
    private(set) var expandedSuiteIDs: Set<String> = []

    // MARK: - Detail

    /// The pair on screen and how it is compared. Which image a row puts there is decided
    /// here, in ``showSnapshot(_:withGitDiff:)``.
    let canvas: CanvasModel
    var isSidebarVisible = true
    /// The window's undo manager, which every file GimDiff writes registers its way back on.
    ///
    /// The window's rather than one of GimDiff's own, so Edit ▸ Undo, ⌘Z, and the filter
    /// field's typing share the one stack a Mac user expects. Handed over by ``RootView``.
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The copies the undo stack holds, deleted with it by ``forgetFileUndo()``: once the
    /// steps that would read them are gone, nothing else knows they exist.
    @ObservationIgnored var undoCopies: Set<URL> = []
    /// The message on screen, under the canvas, if any.
    private(set) var currentMessage: AppMessage?
    /// The last few messages, newest first, so one that closed itself or was replaced can
    /// still be read. Window ▸ Recent Messages lists them.
    private(set) var recentMessages: [AppMessage] = []
    /// How long a notice stays before it closes itself. Shortened by tests.
    @ObservationIgnored var noticeLifetime = Duration.seconds(6)
    @ObservationIgnored private var messageDismissTask: Task<Void, Never>?
    /// Whether the pointer rests on the message, which keeps a notice from closing.
    @ObservationIgnored private var isMessageHeld = false

    /// The text of the message on screen, for callers that only need to know what it says.
    var lastError: String? { currentMessage?.text }

    /// Bumped whenever something outside the sidebar asks it to move keyboard focus.
    ///
    /// A counter rather than a flag: the menu's Find command has to be able to pull focus
    /// back to the filter field a second time without anything having reset it in between.
    private(set) var filterFocusRequests = 0
    private(set) var treeFocusRequests = 0

    // MARK: - Pull request review

    /// The pull request under review, and the sheet that fetches it. What a review does to
    /// the tree is decided here, below.
    let pullRequestReview: PullRequestReviewModel
    /// Whether the help sheet is up.
    ///
    /// The window holds one sheet at a time, so the Open PR sheet takes precedence: a pull
    /// request arriving by URL or paste puts the help away rather than waiting behind it.
    var isHelpPresented = false
    /// Whether the window is asking before every failure of the run is accepted.
    var isConfirmingAcceptAllTestRunFailures = false
    /// Whether the window is asking before every changed snapshot of the project is restored.
    var isConfirmingDiscardAllGitChanges = false
    /// What that question is about: how many snapshots come back and how many go to the
    /// Trash. Set when the question is raised, cleared when it is answered.
    var headRestorePlan: HEADRestorePlan?

    // MARK: - Test run

    /// What the sidebar lists: the project as it stands, or what its last test run failed
    /// on. Changed through ``showProjectStatus()`` and ``showTestRun()``.
    var sidebarSource: SidebarSource = .project
    /// The open project's test runs and what the one read failed on. What a run does to the
    /// tree and the canvas is decided here, in `AppState+TestRun`.
    let testRuns: TestRunModel

    let filesystem: any FilesystemService
    let gitService: any GitService
    let imageDiff: any ImageDiffService
    let scanner: ProjectScanner
    let watcher: any ProjectWatching
    let changeClassifier: ProjectChangeClassifier
    private let ingestion: any IngestionService
    private let clipboard: ClipboardService
    private let workspace: WorkspaceService
    private let defaults: UserDefaults
    private var scanTask: Task<Void, Never>?
    var gitStatusTask: Task<Void, Never>?
    /// The `git restore` in flight, so a caller can wait for it.
    var discardTask: Task<Void, Never>?
    /// The loop reading the watcher's events. Kept out of observation so it stays a plain
    /// stored property, which is what lets `deinit` reach it.
    @ObservationIgnored var watchTask: Task<Void, Never>?
    /// The one refresh working through ``pendingChange``; see ``schedule(_:)``.
    var backgroundRefreshTask: Task<Void, Never>?
    /// What the watcher has reported that no refresh has picked up yet.
    var pendingChange = ProjectChange()
    /// Counts the prunings ``currentProject`` has had in memory, so a background scan can
    /// tell that the tree moved under it while it was walking the disk.
    private(set) var projectEdits = 0

    init(
        filesystem: any FilesystemService = DefaultFilesystemService(),
        gitService: (any GitService)? = nil,
        imageDiff: (any ImageDiffService)? = nil,
        scanner: ProjectScanner? = nil,
        watcher: any ProjectWatching = FSEventsProjectWatcher(),
        ingestion: any IngestionService = DefaultIngestionService(),
        clipboard: ClipboardService = ClipboardService(),
        workspace: WorkspaceService = WorkspaceService(),
        pullRequests: (any GitHubPRService)? = nil,
        testResults: (any TestResultReading)? = nil,
        testResultLocator: (any TestResultLocating)? = nil,
        defaults: UserDefaults = .standard
    ) {
        let git = gitService ?? DefaultGitService(filesystem: filesystem)
        self.filesystem = filesystem
        self.gitService = git
        self.imageDiff = imageDiff ?? DefaultImageDiffService(filesystem: filesystem)
        self.scanner = scanner ?? ProjectScanner(filesystem: filesystem, gitService: git)
        self.watcher = watcher
        changeClassifier = ProjectChangeClassifier(filesystem: filesystem)
        self.ingestion = ingestion
        self.clipboard = clipboard
        self.workspace = workspace
        pullRequestReview = PullRequestReviewModel(
            service: pullRequests ?? DefaultGitHubPRService(
                http: URLSessionHTTPClient(),
                tokens: GitHubTokenResolver(),
                filesystem: filesystem,
                temporaryRoot: Self.scratchFolder("PullRequests")
            ),
            resolver: GitHubPRReferenceResolver(gitService: git),
            filesystem: filesystem
        )
        testRuns = TestRunModel(
            reader: testResults ?? CombinedTestResultReader(
                xcode: XcresultReader(
                    runner: SystemCommandRunner(),
                    filesystem: filesystem,
                    temporaryRoot: Self.scratchFolder("TestRuns")
                ),
                paparazzi: PaparazziFailureReader(filesystem: filesystem, temporaryRoot: Self.scratchFolder("TestRuns"))
            ),
            locator: testResultLocator ?? CombinedTestResultLocator([
                DerivedDataLocator(),
                PaparazziFailureLocator(filesystem: filesystem),
            ]),
            filesystem: filesystem
        )
        self.defaults = defaults
        recentProjects = Self.loadRecentProjects(from: defaults)
        canvas = CanvasModel(imageDiff: self.imageDiff, gitService: git, filesystem: filesystem, defaults: defaults)
        pullRequestReview.reportError = { [weak self] error in self?.report(error) }
        canvas.reportError = { [weak self] error in self?.report(error) }
    }

    deinit {
        watchTask?.cancel()
    }

    /// A folder inside this process's scratch folder, which the app deletes on its way out
    /// and a later launch deletes when it never got there.
    private static func scratchFolder(_ name: String) -> URL {
        DefaultFilesystemService.sessionDirectory.appendingPathComponent(name, isDirectory: true)
    }

    // MARK: - Opening

    /// Acts on a `gimdiff://` URL delivered by the system.
    func handle(_ url: URL) {
        guard url.isFileURL == false else {
            openPath(url)
            return
        }

        do {
            switch try GimDiffURLCommand(url: url) {
            case let .open(folder):
                openProject(at: folder)
            case let .compare(reference, failure):
                // A link can come from any web page, and the pair it opens offers to write one
                // file over the other: anything but two images on disk is refused here.
                if let unusable = [reference, failure].first(where: { !isOpenableImage($0) }) {
                    report(String(localized: "“\(unusable.path)” is not an image file GimDiff can compare, so the link was not opened."))
                    return
                }
                canvas.showComparison(reference: reference, failure: failure, certainty: .stated)
            case let .openPullRequest(input):
                openPullRequest(input)
            }
        } catch {
            report(error)
        }
    }

    /// Whether `url` names an image file on disk: one GimDiff can show, and the only kind
    /// Accept, Reject, and the Keep choices may write over.
    func isOpenableImage(_ url: URL) -> Bool {
        filesystem.fileExists(at: url) && !filesystem.isDirectory(at: url) && Self.hasImageExtension(url)
    }

    /// Whether the name of `url` is that of an image GimDiff reads.
    static func hasImageExtension(_ url: URL) -> Bool {
        url.isImageFile || ImageFormat(url: url).isRecognized
    }

    /// Opens whatever a path turns out to be: a project folder, or a single image.
    func openPath(_ url: URL) {
        if filesystem.isDirectory(at: url) {
            openProject(at: url)
        } else if url.isImageFile {
            canvas.show(.single(Self.looseSnapshot(at: url)))
        } else {
            report(String(localized: "“\(url.lastPathComponent)” is neither a folder nor an image GimDiff can open."))
        }
    }

    /// Opens a batch of paths — a Finder drag, a multiple selection, or a drop.
    ///
    /// Two images become one comparison rather than two unrelated previews, in the order
    /// they arrived: a drag reports the files in the order the user selected them, so the
    /// first is read as the reference and the second as the failure.
    func openPaths(_ urls: [URL]) {
        guard let first = urls.first else { return }

        let images = urls.filter(\.isImageFile)
        guard images.count >= 2 else {
            openPath(first)
            return
        }

        // A drop carries no labels, only the order the files were selected in.
        showLooseComparison(baseline: images[0], candidate: images[1], rolesAreStated: false)
    }

    /// Scans `url` and replaces whatever the window was showing.
    func openProject(at url: URL) {
        let root = url.resolvingSymlinksInPath()
        guard filesystem.isDirectory(at: root) else {
            report(String(localized: "“\(url.path)” is not a folder."))
            return
        }

        // Opening a project is a way out of a review as much as closing it is; the project
        // the review replaced is not coming back, because the user just chose another.
        pullRequestReview.abandon()

        // A newer open supersedes the one in flight: scanning a large repository takes long
        // enough that two overlapping scans would race to publish their results.
        scanTask?.cancel()
        // The scan about to start reads everything a background refresh would have.
        cancelBackgroundRefresh()
        loadingProjectURL = root
        dismissMessage()
        addRecentProject(root)

        // A structured `Task`, never `Task.detached`. The scan suspends the main actor and
        // resumes on it, so every mutation below lands where `@Observable` expects it and
        // the task is still cancelled by the `scanTask?.cancel()` above.
        scanTask = Task { [scanner] in
            do {
                let bundle = try await scanner.scan(projectRoot: root)
                guard !Task.isCancelled else { return }
                load(bundle)
            } catch is CancellationError {
                // Superseded by a newer scan, which owns `loadingProjectURL` now.
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
                loadingProjectURL = nil
            }
        }
    }

    /// Rescans the open project, picking up snapshots a test run has written since.
    ///
    /// Under review, the pull request is fetched again instead: new commits are what would
    /// have changed, and there is no folder of GimDiff's own worth rescanning.
    func reload() {
        if let session = pullRequestReview.session {
            openPullRequest(session.reference.webURL.absoluteString)
            return
        }
        guard let root = currentProject?.rootURL else { return }
        openProject(at: root)
    }

    /// Puts the window back to the recent project list.
    ///
    /// The folder stays in ``recentProjects``, so closing is a way back to the list rather
    /// than a way to forget where the project was.
    func closeProject() {
        forgetFileUndo()
        pullRequestReview.abandon()
        scanTask?.cancel()
        stopWatching()
        discardTestRun()
        testRuns.reset()
        canvas.close()
        currentProject = nil
        selectedRowID = nil
        expandedSuiteIDs = []
        loadingProjectURL = nil
        dismissMessage()
        // The filters described the project that has just gone; carrying them into the next
        // one would hide most of it for no reason the user could see.
        clearFilters()
    }

    /// Abandons the scan in flight and leaves the window showing what it showed before.
    ///
    /// Unlike ``closeProject()``, a rescan cancelled this way keeps the project it was
    /// refreshing: the rows on screen are only as old as they were a moment ago.
    func cancelProjectLoading() {
        scanTask?.cancel()
        loadingProjectURL = nil
    }

    /// Asks the user for a folder and opens it.
    func promptForProject() {
        guard let url = workspace.chooseProjectFolder() else { return }
        openProject(at: url)
    }

    /// The scan in flight, if any.
    ///
    /// Exposed so a caller that needs the window settled — a test, or a future command
    /// that opens a project and then acts on it — can wait for the scan it started.
    var currentScan: Task<Void, Never>? { scanTask }

    /// Makes `bundle` the open project, resetting everything that described the last one.
    ///
    /// The single point where a bundle becomes what the window is showing; ``openProject(at:)``
    /// is this plus the scan that produced it.
    func load(_ bundle: ProjectBundle) {
        forgetFileUndo()
        currentProject = bundle
        loadingProjectURL = nil
        canvas.show(nil)
        // A project with one suite is a suite, so there is nothing to be gained by making
        // the user open it. Several suites start closed, which is the useful overview.
        expandedSuiteIDs = bundle.suites.count == 1 ? Set(bundle.suites.map(\.id)) : []
        // Whatever the last project's run failed on says nothing about this one, and a
        // project always opens on its own status: the run is read when it is asked for.
        discardTestRun()
        sidebarSource = .project
        selectedRowID = visibleRows.first?.id
        restartWatching()
        testRuns.reset()
        locateTestRun()
    }

    /// Swaps in a fresh scan of the project already open, leaving the window where it was.
    ///
    /// ``load(_:)`` is for a project somebody asked for and resets everything that described
    /// the last one. This is for a scan nobody asked for: the open suites, the filters, and
    /// the canvas all stay, and the selection moves only when the row under it is gone —
    /// to the neighbour a deletion would have picked, for the same reason.
    func merge(_ bundle: ProjectBundle) {
        guard bundle != currentProject else { return }
        let rowsBefore = visibleRows

        // The scan read the working tree's status itself, and more recently.
        gitStatusTask?.cancel()
        currentProject = bundle
        expandedSuiteIDs.formIntersection(bundle.suites.map(\.id) + [TestRunModel.attachmentsSuiteID])

        let rows = visibleRows
        if rowsBefore.isEmpty {
            // A tree that had nothing to select now does, and the keyboard needs a row.
            selectedRowID = selectedRowID ?? rows.first?.id
        } else if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectedRowID = Self.survivor(of: selected, among: rowsBefore, in: rows)
        }

        // An attachment of the test run was never in the scan, and is not gone for that.
        if let shown = canvas.preview?.snapshotID,
           !TestRunModel.isAttachment(snapshotID: shown),
           !bundle.suites.contains(where: { $0.snapshots.contains { $0.id == shown } }) {
            canvas.close()
        }
    }

    /// The row that takes the place of one a rescan no longer has.
    ///
    /// The nearest row below it in the old order that is still there, or failing that the
    /// nearest above: the same neighbour ``selection(surviving:)`` picks for a deletion.
    static func survivor(
        of rowID: String,
        among rowsBefore: [TreeRowItem],
        in rows: [TreeRowItem]
    ) -> String? {
        let remaining = Set(rows.map(\.id))
        guard let index = rowsBefore.firstIndex(where: { $0.id == rowID }) else {
            return rows.first?.id
        }

        if let below = rowsBefore[index...].first(where: { remaining.contains($0.id) }) {
            return below.id
        }
        return rowsBefore[..<index].last(where: { remaining.contains($0.id) })?.id ?? rows.first?.id
    }

    // MARK: - Recent projects

    func addRecentProject(_ url: URL) {
        var updated = recentProjects.filter { $0.path != url.path }
        updated.insert(url, at: 0)
        recentProjects = Array(updated.prefix(Self.recentProjectsLimit))
        persistRecentProjects()
    }

    func removeRecentProject(_ url: URL) {
        recentProjects.removeAll { $0.path == url.path }
        persistRecentProjects()
    }

    func clearRecentProjects() {
        recentProjects = []
        persistRecentProjects()
    }

    private func persistRecentProjects() {
        defaults.set(recentProjects.map(\.path), forKey: Self.recentProjectsKey)
    }

    /// Reads the stored paths back, dropping any folder that has since been moved away.
    private static func loadRecentProjects(from defaults: UserDefaults) -> [URL] {
        (defaults.stringArray(forKey: recentProjectsKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: - Filtering

    /// Whether any filter is narrowing the tree, which is what the empty state keys off.
    var isFiltering: Bool {
        !trimmedFilterText.isEmpty || showGitModifiedOnly || showWarningsOnly
    }

    /// Whether the Modified filter has anything to narrow the tree to.
    ///
    /// Stays true while the filter is on, so a rescan that clears the last change cannot
    /// strand an empty tree behind a control that is no longer shown. Under review every
    /// snapshot is a change, so the filter would keep all of them.
    var canFilterByGitChanges: Bool {
        showGitModifiedOnly
            || (isShowingProjectStatus && currentProject?.suites.contains(where: \.hasGitDiff) == true)
    }

    /// Whether the Warnings filter has anything to narrow the tree to; see
    /// ``canFilterByGitChanges`` for why an active filter always counts.
    var canFilterByWarnings: Bool {
        showWarningsOnly
            || (isShowingProjectStatus && currentProject?.suites.contains(where: \.isMissingSourceCode) == true)
    }

    /// Whether the sidebar lists the project on disk, as opposed to a pull request or a
    /// test run — the only view the Modified and Warnings chips have anything to say about.
    private var isShowingProjectStatus: Bool {
        !isReviewingPullRequest && sidebarSource == .project
    }

    /// Resets the search field and both filters.
    func clearFilters() {
        filterText = ""
        showGitModifiedOnly = false
        showWarningsOnly = false
    }

    private var trimmedFilterText: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Flattened visible tree

    /// The sidebar's rows, suites and their snapshots interleaved into one flat array.
    ///
    /// A suite's snapshots follow it immediately when the suite is open, or whenever a
    /// search query is active: a query that matches a method name has to show the match,
    /// not the closed folder holding it.
    var visibleRows: [TreeRowItem] {
        treeRows(expandingAll: false)
    }

    /// ``visibleRows``, or the same rows with every suite open, for walking snapshots the
    /// tree is hiding under a closed suite but would show once it was opened.
    private func treeRows(expandingAll: Bool) -> [TreeRowItem] {
        guard var suites = currentProject?.suites else { return [] }
        let isShowingTestRun = sidebarSource == .testRun
        if isShowingTestRun {
            guard testRuns.results != nil else { return [] }
            // Last, below everything the project itself holds: these are images the run
            // attached that belong to none of it.
            if let attachments = testRuns.attachmentsSuite { suites.append(attachments) }
        }

        let query = trimmedFilterText.lowercased()
        var rows: [TreeRowItem] = []

        for suite in suites where !showWarningsOnly || hasSourceWarning(suite) {
            var children = showGitModifiedOnly ? suite.snapshots.filter(\.hasGitDiff) : suite.snapshots
            if isShowingTestRun {
                children = children.filter { testRuns.isFailing($0) }
            }
            let suiteMatches = query.isEmpty || suite.name.lowercased().contains(query)

            if suiteMatches {
                // A filter, unlike the query, is a statement about snapshots: a suite with
                // nothing it keeps under it has nothing to say while it is on.
                guard !(showGitModifiedOnly || isShowingTestRun) || !children.isEmpty else { continue }
            } else {
                children = children.filter { $0.displayName.lowercased().contains(query) }
                guard !children.isEmpty else { continue }
            }

            let isExpanded = expandingAll || expandedSuiteIDs.contains(suite.id) || !query.isEmpty
            rows.append(.suite(suite, isExpanded: isExpanded, childCount: children.count))
            guard isExpanded else { continue }
            rows.append(contentsOf: children.map { .snapshot($0, parentSuiteID: suite.id) })
        }

        return rows
    }

    /// The row ``selectedRowID`` names, or `nil` when the selection has nothing under it.
    var selectedRow: TreeRowItem? {
        guard let selectedRowID else { return nil }
        return visibleRows.first { $0.id == selectedRowID }
    }

    func isExpanded(suiteWithID id: String) -> Bool {
        expandedSuiteIDs.contains(id)
    }

    func expandSuites(_ ids: some Sequence<String>) {
        expandedSuiteIDs.formUnion(ids)
    }

    func toggleExpansion(ofSuiteWithID id: String) {
        if expandedSuiteIDs.remove(id) == nil {
            expandedSuiteIDs.insert(id)
        }
    }

    /// Moves the selection to the first row currently visible.
    func selectFirstVisibleRow() {
        selectedRowID = visibleRows.first?.id
    }

    /// Moves the selection where the user put it, and shows the snapshot it lands on.
    ///
    /// This is the route for ↑, ↓, and clicks, so the canvas follows the tree without a
    /// Space per row. Selection changes made on the user's behalf — a deletion picking the
    /// neighbour, ← jumping up to a suite — assign ``selectedRowID`` directly instead, so a
    /// pane that was just closed is not reopened under them. A suite row leaves the canvas
    /// alone: there is no single image to show, and blanking the pane on the way past one
    /// would make stepping between suites flicker.
    func selectRow(withID id: String?) {
        selectedRowID = id
        previewSelectedSnapshot()
    }

    /// Shows the selected snapshot, unless the canvas is already standing on it.
    ///
    /// Re-showing the same snapshot would drop the committed-version comparison back to a
    /// single image while git extracts it again.
    private func previewSelectedSnapshot() {
        guard case let .snapshot(snapshot, _) = selectedRow,
              canvas.preview?.snapshotID != snapshot.id
        else { return }
        showSnapshot(snapshot, withGitDiff: true)
    }

    // MARK: - Stepping through changes

    /// Selects the next changed snapshot below the selection, opening its suite on the way
    /// and wrapping round from the bottom. Snapshot ▸ Next Change, ⌥↓.
    func selectNextChange() {
        stepToChange(forward: true)
    }

    /// Selects the previous changed snapshot above the selection. Snapshot ▸ Previous
    /// Change, ⌥↑.
    func selectPreviousChange() {
        stepToChange(forward: false)
    }

    /// Whether there is a change to step to other than the one already selected.
    var canStepThroughChanges: Bool {
        let changes = changedRows(in: treeRows(expandingAll: true))
        return changes.count > 1 || (changes.count == 1 && changes[0].id != selectedRowID)
    }

    /// The rows that count as a change in the view the sidebar is showing.
    ///
    /// In the project, a snapshot git reports modified or untracked: exactly what the
    /// Modified chip would keep, without hiding the rest. Under the test run every row is a
    /// failure, and under a pull request every row is something it changed, so there every
    /// snapshot counts.
    private func changedRows(in rows: [TreeRowItem]) -> [TreeRowItem] {
        let everySnapshotIsAChange = isReviewingPullRequest || sidebarSource == .testRun
        return rows.filter { row in
            guard let snapshot = row.snapshot else { return false }
            return everySnapshotIsAChange || snapshot.hasGitDiff
        }
    }

    /// Walks the tree as if every suite were open, so a change under a closed suite is
    /// found, and then opens that suite so the row it lands on can be seen.
    private func stepToChange(forward: Bool) {
        let rows = treeRows(expandingAll: true)
        let changes = Set(changedRows(in: rows).map(\.id))
        guard !changes.isEmpty else { return }

        // From the selection, or from just outside the tree when nothing is selected, so the
        // first step lands on the first change in either direction.
        let start = rows.firstIndex { $0.id == selectedRowID } ?? (forward ? -1 : rows.count)
        let order = forward
            ? Array(rows.indices.dropFirst(start + 1)) + Array(rows.indices.prefix(max(start + 1, 0)))
            : Array(rows.indices.prefix(max(start, 0)).reversed()) + Array(rows.indices.dropFirst(start).reversed())
        guard let index = order.first(where: { changes.contains(rows[$0].id) }) else { return }

        let target = rows[index]
        expandedSuiteIDs.insert(target.suiteID)
        selectRow(withID: target.id)
    }

    // MARK: - Keyboard navigation

    /// Right arrow: opens a closed suite, or steps down into the first child of an open one.
    ///
    /// - Returns: Whether the key did anything, so the caller can pass it on when it did not.
    @discardableResult
    func expandOrDescend() -> Bool {
        let rows = visibleRows
        guard let index = rows.firstIndex(where: { $0.id == selectedRowID }),
              case let .suite(suite, isExpanded, childCount) = rows[index]
        else { return false }

        guard isExpanded else {
            expandedSuiteIDs.insert(suite.id)
            return true
        }

        guard childCount > 0, rows.indices.contains(index + 1) else { return false }
        selectRow(withID: rows[index + 1].id)
        return true
    }

    /// Left arrow: jumps a snapshot up to its suite, or closes an open suite.
    @discardableResult
    func collapseOrAscend() -> Bool {
        switch selectedRow {
        case let .snapshot(_, parentSuiteID):
            selectedRowID = TreeRowItem.suiteRowID(parentSuiteID)
            return true
        case let .suite(suite, _, _):
            return expandedSuiteIDs.remove(suite.id) != nil
        case nil:
            return false
        }
    }

    /// Space: shows the selected snapshot, or closes the pane when it is already on it.
    ///
    /// On a suite row there is nothing to preview, so the key opens and closes the suite —
    /// the same thing space does in a Finder list.
    func togglePreview() {
        switch selectedRow {
        case let .snapshot(snapshot, _):
            if canvas.preview?.snapshotID == snapshot.id {
                canvas.show(nil)
            } else {
                showSnapshot(snapshot, withGitDiff: true)
            }
        case let .suite(suite, _, _):
            toggleExpansion(ofSuiteWithID: suite.id)
        case nil:
            break
        }
    }

    /// Return: opens the test source that records the selected suite.
    ///
    /// Does nothing under pull request review, where no suite has a source file on disk
    /// and the key would only ever produce an error.
    func openTestSource() {
        guard !isReviewingPullRequest, let suite = selectedSuite else { return }
        openTestSource(for: suite)
    }

    /// Command-Return: reveals the selected snapshot, or its suite's folder, in the Finder.
    ///
    /// Not under pull request review: the files there are scratch copies GimDiff deletes
    /// when the review ends, and a Finder window onto them invites keeping one.
    func revealSelectionInFinder() {
        guard !isReviewingPullRequest else { return }
        switch selectedRow {
        case let .snapshot(snapshot, _):
            workspace.revealInFinder(snapshot.fileURL)
        case let .suite(suite, _, _):
            workspace.revealInFinder(suite.snapshotsFolderURL)
        case nil:
            break
        }
    }

    /// ⌘F: puts the cursor in the sidebar's search box, opening the sidebar if it is closed.
    ///
    /// A search box the user cannot see is not somewhere a query can be typed, so the
    /// sidebar comes back with the request rather than the key doing nothing.
    func focusFilter() {
        isSidebarVisible = true
        filterFocusRequests += 1
    }

    func focusTree() {
        treeFocusRequests += 1
    }

    func expandSidebar() {
        isSidebarVisible = true
    }

    func collapseSidebar() {
        isSidebarVisible = false
    }

    // MARK: - Preview pane

    /// Shows one snapshot: what a pull request did to it, what a test run rendered for it,
    /// or the file against its committed version when it has one.
    func showSnapshot(_ snapshot: SnapshotItem, withGitDiff: Bool) {
        canvas.cancelCommittedVersion()

        if let change = pullRequestReview.change(forSnapshotID: snapshot.id) {
            showPullRequestChange(change, of: snapshot, withBaseline: withGitDiff)
            return
        }

        guard !TestRunModel.isAttachment(snapshotID: snapshot.id) else {
            canvas.show(.testRunAttachment(snapshot))
            return
        }

        // What the last run rendered says more than what the last commit held: the failure
        // is why the snapshot is being looked at.
        if withGitDiff, sidebarSource == .testRun,
           let candidate = testRuns.results?.candidates(forSnapshotID: snapshot.id).first {
            showTestRunCandidate(candidate, against: snapshot)
            return
        }

        canvas.showWithCommittedVersion(snapshot, gitRoot: withGitDiff ? currentProject?.gitRootURL : nil)
    }

    /// Shows what a pull request did to one snapshot.
    ///
    /// Both versions were downloaded with the session, so the comparison is ready at once
    /// and git has nothing to add. A snapshot the pull request adds or deletes has only one
    /// version, which is shown on its own under the side it belongs to.
    private func showPullRequestChange(
        _ change: PRSnapshotChange,
        of snapshot: SnapshotItem,
        withBaseline: Bool
    ) {
        switch (change.candidateURL, change.baselineURL) {
        case let (candidate?, baseline?) where withBaseline:
            canvas.show(.comparison(
                SnapshotPair(reference: baseline, failure: candidate),
                snapshotID: snapshot.id,
                title: snapshot.displayName,
                baselineOrigin: .pullRequest
            ))
        case let (candidate?, _):
            var head = snapshot
            head.fileURL = candidate
            canvas.show(.pullRequestSide(head, role: .candidate))
        case let (nil, baseline?):
            var base = snapshot
            base.fileURL = baseline
            canvas.show(.pullRequestSide(base, role: .baseline))
        case (nil, nil):
            canvas.show(nil)
        }
    }

    /// Shows a pasted or dropped pair once its sides are decided, with the open project as
    /// one of the clues to which file is the recorded snapshot.
    func showLooseComparison(baseline: URL, candidate: URL, rolesAreStated: Bool) {
        canvas.showLooseComparison(
            baseline: baseline,
            candidate: candidate,
            rolesAreStated: rolesAreStated,
            projectRoot: currentProject?.rootURL
        )
    }

    /// Shows a failure: something GimDiff was asked to do did not happen. It stays until
    /// it is dismissed, because whatever failed may need doing again.
    func report(_ error: any Error) {
        post(AppMessage(text: error.localizedDescription, kind: .failure))
    }

    /// Shows an explanation — why an action is unavailable, or what GimDiff could not make
    /// of something it was handed. It closes itself, since nothing is left undone.
    func report(_ message: String) {
        post(AppMessage(text: message, kind: .notice))
    }

    /// Puts the message away.
    func dismissMessage() {
        messageDismissTask?.cancel()
        messageDismissTask = nil
        isMessageHeld = false
        currentMessage = nil
    }

    /// Keeps a notice on screen while the pointer is on it, and starts its time again when
    /// the pointer leaves, so a message being read never closes under the reader.
    func holdMessage(_ isHeld: Bool) {
        isMessageHeld = isHeld
        if isHeld {
            messageDismissTask?.cancel()
        } else {
            scheduleDismissal()
        }
    }

    func clearRecentMessages() {
        recentMessages = []
    }

    private func post(_ message: AppMessage) {
        currentMessage = message
        recentMessages.insert(message, at: 0)
        if recentMessages.count > Self.recentMessagesLimit {
            recentMessages.removeLast(recentMessages.count - Self.recentMessagesLimit)
        }
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        messageDismissTask?.cancel()
        guard let message = currentMessage, message.kind == .notice, !isMessageHeld else { return }
        messageDismissTask = Task { [noticeLifetime] in
            try? await Task.sleep(for: noticeLifetime)
            guard !Task.isCancelled, currentMessage?.id == message.id else { return }
            currentMessage = nil
        }
    }

    /// The notice's countdown, if one is running, so a test can wait for it.
    var currentMessageDismissal: Task<Void, Never>? { messageDismissTask }

    // MARK: - Git status

    /// Re-reads Git's view of the open project and re-annotates every snapshot.
    ///
    /// Cheaper than a rescan and enough after a promotion: the files are where they were,
    /// it is only their standing against `HEAD` that changed.
    func refreshGitStatus() {
        guard let gitRoot = currentProject?.gitRootURL else { return }

        gitStatusTask?.cancel()
        gitStatusTask = Task { [gitService] in
            // A repository that cannot be read leaves the last annotation in place rather
            // than blanking the sidebar's badges over a transient failure.
            guard let statuses = try? await gitService.status(repositoryRoot: gitRoot),
                  !Task.isCancelled
            else { return }

            applyGitStatuses(statuses)
        }
    }

    /// The Git status task in flight, if any, so a caller can wait for it.
    var currentGitStatusRefresh: Task<Void, Never>? { gitStatusTask }

    func applyGitStatuses(_ statuses: [URL: GitFileStatus]) {
        guard let suites = currentProject?.suites else { return }
        currentProject?.suites = ProviderRegistry.annotate(suites, with: statuses)
    }

    /// Records that Git has nothing against these snapshots any more, ahead of the status
    /// read that will say so.
    func markUnmodified(_ snapshotIDs: Set<String>) {
        guard var suites = currentProject?.suites else { return }
        for suiteIndex in suites.indices {
            for snapshotIndex in suites[suiteIndex].snapshots.indices
            where snapshotIDs.contains(suites[suiteIndex].snapshots[snapshotIndex].id) {
                suites[suiteIndex].snapshots[snapshotIndex].gitStatus = .unmodified
            }
        }
        currentProject?.suites = suites
    }

    /// Takes snapshots GimDiff moved to the Trash out of the tree, without a rescan.
    func removeSnapshots(_ snapshotIDs: Set<String>) {
        guard !snapshotIDs.isEmpty, var suites = currentProject?.suites else { return }
        for index in suites.indices {
            suites[index].snapshots.removeAll { snapshotIDs.contains($0.id) }
        }
        currentProject?.suites = suites
        projectEdits += 1
    }

    /// Reads a comparison out of whatever is on the pasteboard.
    func pasteFromClipboard() {
        let fileURLs = clipboard.fileURLs()
        guard fileURLs.isEmpty else {
            openPaths(fileURLs)
            return
        }

        // A pull request link is checked for first: it is never a failure log, while a
        // message carrying a link can mention a path in passing.
        if let text = clipboard.string(), let reference = ingestion.parsePullRequest(text) {
            openPullRequest(reference.webURL.absoluteString)
            return
        }

        guard let text = clipboard.string(), let payload = ingestion.parseClipboardText(text) else {
            report(String(localized: "The clipboard holds no snapshot path GimDiff recognises."))
            return
        }

        guard let baseline = payload.baselineURL else {
            canvas.show(.single(Self.looseSnapshot(at: payload.candidateURL)))
            return
        }

        showLooseComparison(
            baseline: baseline,
            candidate: payload.candidateURL,
            rolesAreStated: payload.rolesAreStated
        )
    }

    /// Command-V: pastes into the focused text field when there is one, and ingests the
    /// clipboard otherwise.
    ///
    /// One shortcut does both because it has to: a second menu item bound to ⌘V would
    /// shadow the filter field's own paste, since AppKit matches key equivalents against
    /// the menu bar before the first responder ever sees the event.
    func pasteCommand() {
        guard !workspace.forwardPasteToFocusedField() else { return }
        pasteFromClipboard()
    }

    /// Forwards an Edit-menu action GimDiff replaced but does not itself implement.
    func performEditAction(_ action: WorkspaceService.EditAction) {
        workspace.perform(action)
    }

    // MARK: - Context menu actions

    func copyToClipboard(_ text: String) {
        clipboard.copy(text)
    }

    func openTestSource(for suite: SnapshotSuite) {
        guard let sourceCodeURL = suite.sourceCodeURL else {
            report(String(localized: "GimDiff could not find the test source for “\(suite.name)”."))
            return
        }
        workspace.open(sourceCodeURL)
    }

    /// The suite the row belongs to, whether the row *is* the suite or one of its snapshots.
    func suite(for row: TreeRowItem) -> SnapshotSuite? {
        currentProject?.suites.first { $0.id == row.suiteID }
    }

    func openSnapshotsFolder(for suite: SnapshotSuite) {
        workspace.open(suite.snapshotsFolderURL)
    }

    func openInPreviewApp(_ url: URL) {
        workspace.openInPreview(url)
    }

    func revealInFinder(_ url: URL) {
        workspace.revealInFinder(url)
    }

    // MARK: - Menu bar actions on the selection

    /// The snapshot on the selected row, absent when the selection is a suite or nothing.
    var selectedSnapshot: SnapshotItem? {
        selectedRow?.snapshot
    }

    /// The suite the selection belongs to, whether the row is the suite or one of its snapshots.
    var selectedSuite: SnapshotSuite? {
        selectedRow.flatMap(suite(for:))
    }

    /// Whether the canvas already shows the selected snapshot, so Space would close it.
    var isShowingSelectedSnapshot: Bool {
        guard let snapshot = selectedSnapshot else { return false }
        return canvas.preview?.snapshotID == snapshot.id
    }

    /// What Copy Name puts on the clipboard: the suite's name or the snapshot's, as the row reads.
    var selectedRowName: String? {
        switch selectedRow {
        case let .suite(suite, _, _): suite.name
        case let .snapshot(snapshot, _): snapshot.displayName
        case nil: nil
        }
    }

    func copySelectedRowName() {
        guard let name = selectedRowName else { return }
        copyToClipboard(name)
    }

    /// Snapshot ▸ Copy Comparison Image: puts the split or the onion skin on the clipboard
    /// as one picture, cut or faded exactly where the canvas has it.
    ///
    /// - Parameters:
    ///   - backdrop: The panel colour behind the images, when one is chosen.
    ///   - matte: The colour behind the images themselves, when one is chosen.
    func copyComparisonImage(backdrop: CGColor?, matte: CGColor?) {
        guard canvas.canCopyComparisonImage,
              let preview = canvas.preview,
              let baseline = preview.baseline,
              let candidate = preview.candidate
        else { return }
        guard let below = ComparisonImageRenderer.image(at: baseline.fileURL),
              let above = ComparisonImageRenderer.image(at: candidate.fileURL)
        else {
            report(String(localized: "One of the two images could not be read, so there is nothing to copy."))
            return
        }

        let left = canvas.sideTitle(for: baseline)
        let right = canvas.sideTitle(for: candidate)
        let rendered: CGImage?
        if canvas.diffMode == .curtain {
            rendered = ComparisonImageRenderer.split(
                left: below,
                right: above,
                position: canvas.splitPosition,
                backdrop: backdrop,
                matte: matte,
                caption: ComparisonCaption(
                    leftTitle: left,
                    rightTitle: right,
                    detail: String(localized: "\(preview.title) · split at \(Self.percent(canvas.splitPosition))")
                )
            )
        } else {
            rendered = ComparisonImageRenderer.onionSkin(
                under: below,
                over: above,
                rightOpacity: canvas.onionOpacity,
                backdrop: backdrop,
                matte: matte,
                caption: ComparisonCaption(
                    leftTitle: left,
                    rightTitle: right,
                    detail: String(localized: "\(preview.title) · \(right) at \(Self.percent(canvas.onionOpacity))")
                )
            )
        }

        guard let rendered, let png = ComparisonImageRenderer.pngData(rendered) else {
            report(String(localized: "The comparison could not be drawn."))
            return
        }
        clipboard.copy(pngData: png)
    }

    /// Formatted for the reader's locale, which puts the sign and the space where it goes.
    private static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// What showing `snapshot` with its diff is called, in the menu bar and on the row alike.
    func compareActionTitle(for snapshot: SnapshotItem?) -> String {
        if isReviewingPullRequest { return String(localized: "Compare with Base Branch") }
        if let snapshot, sidebarSource == .testRun, testRuns.results?.isFailing(snapshotID: snapshot.id) == true {
            return String(localized: "Compare with Test Run")
        }
        return String(localized: "Show Snapshot with Git Diff")
    }

    /// What showing a snapshot on its own is called, in the menu bar and on the row alike.
    var showAloneActionTitle: String {
        isReviewingPullRequest ? String(localized: "Show Pull Request Version Only") : String(localized: "Show Snapshot without Git Diff")
    }

    func showSelectedSnapshot(withGitDiff: Bool) {
        guard let snapshot = selectedSnapshot else { return }
        showSnapshot(snapshot, withGitDiff: withGitDiff)
    }

    /// Not under pull request review, for the reason ``revealSelectionInFinder()`` gives.
    func openSelectedSnapshotInPreviewApp() {
        guard !isReviewingPullRequest, let snapshot = selectedSnapshot else { return }
        openInPreviewApp(snapshot.fileURL)
    }

    func openSnapshotsFolderForSelection() {
        guard !isReviewingPullRequest, let suite = selectedSuite else { return }
        openSnapshotsFolder(for: suite)
    }

    // MARK: - Deletion

    /// Deletes what the selection is on, moving it to the Trash.
    func deleteSelection() {
        guard let row = selectedRow else { return }
        delete(row)
    }

    /// Deletes one row's snapshot, or one row's whole suite folder.
    ///
    /// The replacement selection is worked out from the rows *as they still stand*, before
    /// anything is removed: the row that takes the deleted one's place is its neighbour in
    /// the current list, and once the array has changed that neighbour is no longer
    /// identifiable. Getting this order wrong is what leaves the tree with no selection and
    /// the keyboard with nothing to move.
    func delete(_ row: TreeRowItem) {
        switch row {
        case let .snapshot(snapshot, parentSuiteID):
            delete(snapshot: snapshot, in: parentSuiteID)
        case let .suite(suite, _, _):
            delete(suite: suite)
        }
    }

    func delete(snapshot: SnapshotItem, in suiteID: String) {
        guard !refusesDeletionUnderReview(), !refusesDeletionOfTestRunAttachments(in: suiteID) else { return }
        let rowID = TreeRowItem.snapshotRowID(snapshot.id, parentSuiteID: suiteID)
        let replacement = selection(surviving: [rowID])

        guard trash(snapshot.fileURL, actionName: String(localized: "Move Snapshot to Trash")) else { return }

        // Pruned in memory rather than rescanned: the scan that found this snapshot walked
        // the whole project, and nothing about deleting one file needs that repeated.
        guard let index = currentProject?.suites.firstIndex(where: { $0.id == suiteID }) else { return }
        currentProject?.suites[index].snapshots.removeAll { $0.id == snapshot.id }

        finishDeletion(replacement: replacement, removedSnapshotIDs: [snapshot.id])
    }

    func delete(suite: SnapshotSuite) {
        guard !refusesDeletionUnderReview(), !refusesDeletionOfTestRunAttachments(in: suite.id) else { return }
        var removedRowIDs: Set<String> = [TreeRowItem.suiteRowID(suite.id)]
        for snapshot in suite.snapshots {
            removedRowIDs.insert(TreeRowItem.snapshotRowID(snapshot.id, parentSuiteID: suite.id))
        }
        let replacement = selection(surviving: removedRowIDs)

        // A folder other suites record into is left standing; only this suite's files go.
        let trashed = suite.sharesFolder
            ? trash(suite.snapshots.map(\.fileURL), actionName: String(localized: "Move Snapshots to Trash"))
            : trash(suite.snapshotsFolderURL, actionName: String(localized: "Move Snapshots Folder to Trash"))
        guard trashed else { return }

        currentProject?.suites.removeAll { $0.id == suite.id }
        expandedSuiteIDs.remove(suite.id)

        finishDeletion(replacement: replacement, removedSnapshotIDs: Set(suite.snapshots.map(\.id)))
    }

    /// Refuses a deletion while a pull request is under review, saying why.
    ///
    /// The rows are downloaded copies: trashing one would remove nothing from the pull
    /// request and only make the review lie about what it changes.
    private func refusesDeletionUnderReview() -> Bool {
        guard isReviewingPullRequest else { return false }
        report(String(localized: "Snapshots in a pull request review are read-only; there is nothing on disk to delete."))
        return true
    }

    private func trash(_ url: URL, actionName: String) -> Bool {
        do {
            let trashed = try filesystem.trashFile(at: url)
            if let trashed {
                registerUndoOfTrash(original: url, trashed: trashed, actionName: actionName)
            }
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Trashes each of `urls` as a single step of the undo stack.
    ///
    /// Stops at the first file that cannot be trashed. Those before it are already in the
    /// Trash, so the project is rescanned to show what is left rather than what was meant.
    private func trash(_ urls: [URL], actionName: String) -> Bool {
        let needsGroup = undoManager.map { $0.groupingLevel == 0 } ?? false
        if needsGroup { undoManager?.beginUndoGrouping() }
        defer { if needsGroup { undoManager?.endUndoGrouping() } }

        for (index, url) in urls.enumerated() where !trash(url, actionName: actionName) {
            if index > 0 { rescanAfterOwnEdit() }
            return false
        }
        return true
    }

    /// Rescans the project after GimDiff itself put files back or took them away again.
    ///
    /// The watcher ignores GimDiff's own writes, so nothing else would notice. Counted as an
    /// edit first, so a scan already walking the disk is thrown away rather than merged.
    func rescanAfterOwnEdit() {
        projectEdits += 1
        var change = ProjectChange()
        change.needsRescan = true
        schedule(change)
    }

    private func finishDeletion(replacement: String?, removedSnapshotIDs: Set<String>) {
        projectEdits += 1
        selectedRowID = replacement
        if let shown = canvas.preview?.snapshotID, removedSnapshotIDs.contains(shown) {
            canvas.close()
        }
    }

    /// The row the selection should land on once `removedRowIDs` are gone.
    ///
    /// The row below the deleted block, or the one above it when the block ran to the end
    /// of the list. `nil` only when the deletion empties the tree.
    private func selection(surviving removedRowIDs: Set<String>) -> String? {
        let rows = visibleRows
        guard let first = rows.firstIndex(where: { removedRowIDs.contains($0.id) }) else {
            return selectedRowID
        }

        if let below = rows[first...].first(where: { !removedRowIDs.contains($0.id) }) {
            return below.id
        }
        return rows[..<first].last(where: { !removedRowIDs.contains($0.id) })?.id
    }

    // MARK: - Pull request review

    /// Whether the sidebar is showing a pull request rather than a project on disk.
    var isReviewingPullRequest: Bool { pullRequestReview.isReviewing }

    /// ⌘⇧O: raises the Open PR sheet, filled in from the clipboard when it holds a link.
    func presentPullRequestSheet() {
        pullRequestReview.presentSheet { [clipboard, ingestion] in
            clipboard.string().flatMap(ingestion.parsePullRequest)?.webURL.absoluteString
        }
        isHelpPresented = false
    }

    /// ⌘?: raises the help sheet, unless the Open PR sheet already covers the window.
    func presentHelp() {
        guard !pullRequestReview.isSheetPresented else { return }
        isHelpPresented = true
    }

    func dismissHelp() {
        isHelpPresented = false
    }

    /// Puts the sheet away, abandoning a fetch still in flight.
    func dismissPullRequestSheet() {
        pullRequestReview.dismissSheet()
    }

    /// Fetches the pull request `input` names and, once its snapshots are downloaded,
    /// shows them in place of the open project.
    func openPullRequest(_ input: String) {
        isHelpPresented = false
        pullRequestReview.fetch(input, repositoryRoot: currentProject?.gitRootURL) { [weak self] session in
            self?.beginPullRequestReview(session)
        }
    }

    /// Ends the review, deleting what it downloaded, and puts back the project it replaced.
    func closePullRequestReview() {
        guard pullRequestReview.isReviewing else { return }
        let previous = pullRequestReview.projectBeforeReview
        pullRequestReview.abandon()
        clearFilters()

        guard let previous else {
            closeProject()
            return
        }
        load(previous)
        // The project sat unwatched for the length of the review; its files may have moved.
        refreshGitStatus()
    }

    private func beginPullRequestReview(_ session: PRReviewSession) {
        pullRequestReview.begin(session, replacing: currentProject)

        scanTask?.cancel()
        clearFilters()
        load(ProjectBundle(rootURL: session.tempDirectoryURL, suites: session.suites))
        // A pull request is read to see what it changed, so every change starts on show.
        expandedSuiteIDs = Set(session.suites.map(\.id))
        // Land on the first change itself, not the suite above it, so the canvas has
        // something to show the moment the sheet goes away.
        selectRow(withID: visibleRows.first(where: \.isSnapshot)?.id ?? visibleRows.first?.id)

        pullRequestReview.finishFetch()
        // A review that looks complete when it is not is worse than none: said as it opens,
        // and kept in the review's header for as long as it is up.
        if let notice = Self.unlistedFilesNotice(for: session) {
            report(notice)
        }
    }

    /// Why a review lacks some of its snapshots, or `nil` when GitHub listed every file.
    static func unlistedFilesNotice(for session: PRReviewSession) -> String? {
        guard session.unlistedFileCount > 0, let total = session.reportedChangedFileCount else { return nil }
        return String(localized: """
            GitHub lists only the first \(session.changedFileCount) of the \(total) files this pull \
            request changes, so snapshots among the rest are not shown.
            """)
    }

    // MARK: - Paths

    /// A stand-in item for an image GimDiff was handed rather than discovered.
    private static func looseSnapshot(at url: URL) -> SnapshotItem {
        SnapshotItem(name: url.deletingPathExtension().lastPathComponent, fileURL: url)
    }

    /// `url` expressed relative to `root`, which is the form git names a file in.
    ///
    /// - Returns: `nil` when `url` is not inside `root`.
    static func relativePath(of url: URL, under root: URL) -> String? {
        let filePath = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}

/// Something the View menu asks of the canvas's own controls.
enum CanvasViewCommand: Equatable, Sendable {
    case fit
    case actualSize
    case free
    case zoomIn
    case zoomOut
    case resetZoom
    /// Sets the onion skin's fade: 0 is the baseline alone, 1 the candidate alone.
    case fadeOnionSkin(to: Double)
}

/// One ``CanvasViewCommand``, numbered so that repeating it is still a change.
struct CanvasViewRequest: Equatable, Sendable {
    let serial: Int
    let command: CanvasViewCommand
}

/// One thing GimDiff has to tell the user, shown under the canvas.
struct AppMessage: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        /// Something asked for did not happen. Stays until dismissed.
        case failure
        /// Why something is unavailable, or what could not be made of an input. Closes
        /// itself.
        case notice
    }

    let id = UUID()
    let text: String
    let kind: Kind
    let date = Date()
}
