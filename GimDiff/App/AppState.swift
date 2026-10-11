//
//  AppState.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

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
    /// `UserDefaults` key the diff mask's tolerance is remembered under, as a ΔE.
    static let diffToleranceKey = "diff_tolerance_delta_e"
    /// `UserDefaults` key Link Panes is remembered under.
    static let linksPanesKey = "links_panes"
    /// How many folders the recent list keeps before it starts forgetting the oldest.
    static let recentProjectsLimit = 12
    /// Commit-ish a snapshot is compared against when its Git diff is shown.
    static let comparisonGitRef = "HEAD"

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

    private(set) var preview: SnapshotPreview?
    var diffMode: DiffMode = .sideBySide
    var isSidebarVisible = true
    /// Pixel comparison of the two panes, recomputed whenever the diff mask is on.
    private(set) var diffReport: ImageDiffReport?
    /// Whether that comparison is in flight, so the footer can say so rather than go blank.
    private(set) var isComputingDiff = false
    /// How far apart two pixels may be before the diff mask paints them.
    ///
    /// Remembered across launches: it describes the renderer a project's tests run on,
    /// which does not change from one snapshot to the next.
    var diffTolerance: DiffTolerance = .exact {
        didSet {
            guard diffTolerance != oldValue else { return }
            defaults.set(diffTolerance.maximumDeltaE, forKey: Self.diffToleranceKey)
            updateDiffReport()
        }
    }
    /// Whether the two side-by-side panes zoom and pan together.
    ///
    /// Off by default, because the panes' independence is the point when one is held at 1:1
    /// on a detail while the other stays fitted. Remembered once turned on, as a way of
    /// working rather than a property of one comparison.
    var linksPanes = false {
        didSet { defaults.set(linksPanes, forKey: Self.linksPanesKey) }
    }
    /// How the sides of a loose pair were chosen, while one is on screen.
    ///
    /// `nil` for anything else: a snapshot's own comparison has sides the project gave it.
    private(set) var looseRoleCertainty: LooseRoleCertainty?
    /// Bumped to make the canvas read its images off disk again.
    ///
    /// A counter rather than a flag because the file name never changes: nothing about the
    /// URL tells a view that the bytes behind it were rewritten by a test run.
    private(set) var imageReloadToken = 0
    /// The last View menu command addressed to the canvas's own controls.
    ///
    /// Display mode, zoom, and the onion skin's fade belong to the views that draw them, so
    /// the menu cannot set them directly; it posts a request each of those views carries
    /// out. The serial makes the same command twice in a row two requests.
    private(set) var canvasViewRequest: CanvasViewRequest?
    /// The window's undo manager, which every file GimDiff writes registers its way back on.
    ///
    /// The window's rather than one of GimDiff's own, so Edit ▸ Undo, ⌘Z, and the filter
    /// field's typing share the one stack a Mac user expects. Handed over by ``RootView``.
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The most recent failure, shown as a banner until it is dismissed.
    private(set) var lastError: String?

    /// Bumped whenever something outside the sidebar asks it to move keyboard focus.
    ///
    /// A counter rather than a flag: the menu's Find command has to be able to pull focus
    /// back to the filter field a second time without anything having reset it in between.
    private(set) var filterFocusRequests = 0
    private(set) var treeFocusRequests = 0

    // MARK: - Pull request review

    /// The pull request the sidebar is showing in place of a project, if any.
    private(set) var pullRequestSession: PRReviewSession?
    /// Whether the Open PR sheet is up.
    ///
    /// Every route into a review — the menu, a paste, a `gimdiff://open-pr` URL — goes
    /// through the sheet, so a fetch that takes a while has one place to show progress and
    /// a failure has one place to be read.
    var isPullRequestSheetPresented = false
    /// Whether the help sheet is up.
    ///
    /// The window holds one sheet at a time, so the Open PR sheet takes precedence: a pull
    /// request arriving by URL or paste puts the help away rather than waiting behind it.
    var isHelpPresented = false
    /// Whether the window is asking before every failure of the run is accepted.
    var isConfirmingAcceptAllTestRunFailures = false
    /// Whether the window is asking before every changed snapshot of the project is restored.
    var isConfirmingDiscardAllGitChanges = false
    /// What the sheet's field holds: a link, `owner/repo#123`, or a number.
    var pullRequestInput = ""
    private(set) var isFetchingPullRequest = false
    /// Why the last fetch failed, shown in the sheet rather than on the window's banner.
    private(set) var pullRequestError: String?
    /// The project the review replaced, put back when the review closes.
    private var projectBeforePullRequest: ProjectBundle?
    private var pullRequestTask: Task<Void, Never>?

    // MARK: - Test run

    /// What the sidebar lists: the project as it stands, or what its last test run failed
    /// on. Changed through ``showProjectStatus()`` and ``showTestRun()``.
    var sidebarSource: SidebarSource = .project
    /// What the chosen test run of the open project failed on, or `nil` until somebody asks
    /// for it. See `AppState+TestRun`.
    private(set) var testRun: TestRunResults?
    /// Every result bundle Xcode has for the open project, newest first, found without
    /// reading any of them; empty when the project has never been tested.
    var testRunBundles: [TestRunBundle] = []
    /// The run somebody picked from the history, or `nil` to follow the newest one — which
    /// is what a project opens on, and what keeps a fresh run replacing the one on screen.
    var pinnedTestRunBundleURL: URL?
    var testRunLocateTask: Task<Void, Never>?
    /// Whether the run is being read, so the sidebar can say so rather than stand empty.
    var isReadingTestRun = false
    /// Why the run could not be shown, in place of the rows.
    var testRunError: String?
    let testResults: any TestResultReading
    let testResultLocator: any TestResultLocating
    /// The read in flight, so a newer run supersedes it rather than racing it.
    var testRunTask: Task<Void, Never>?
    /// Where Xcode writes the project's result bundles, as handed to the watcher.
    var testResultDirectories: [String] = []

    let filesystem: any FilesystemService
    let gitService: any GitService
    let imageDiff: any ImageDiffService
    let scanner: ProjectScanner
    let watcher: any ProjectWatching
    let changeClassifier: ProjectChangeClassifier
    private let ingestion: any IngestionService
    private let clipboard: ClipboardService
    private let workspace: WorkspaceService
    private let pullRequests: any GitHubPRService
    private let pullRequestResolver: GitHubPRReferenceResolver
    private let defaults: UserDefaults
    private var scanTask: Task<Void, Never>?
    private var gitDiffTask: Task<Void, Never>?
    /// Held so a second diff request supersedes the first rather than racing it.
    var diffTask: Task<Void, Never>?
    var gitStatusTask: Task<Void, Never>?
    /// The `git restore` in flight, so a caller can wait for it.
    var discardTask: Task<Void, Never>?
    /// Deciding the sides of a pasted or dropped pair, before it is shown.
    private var looseRoleTask: Task<Void, Never>?
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
        testResultLocator: any TestResultLocating = DerivedDataLocator(),
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
        self.pullRequests = pullRequests ?? DefaultGitHubPRService(
            http: URLSessionHTTPClient(),
            tokens: GitHubTokenResolver(),
            filesystem: filesystem
        )
        pullRequestResolver = GitHubPRReferenceResolver(gitService: git)
        self.testResults = testResults ?? XcresultReader(runner: SystemCommandRunner(), filesystem: filesystem)
        self.testResultLocator = testResultLocator
        self.defaults = defaults
        recentProjects = Self.loadRecentProjects(from: defaults)
        diffTolerance = DiffTolerance(maximumDeltaE: defaults.double(forKey: Self.diffToleranceKey))
        linksPanes = defaults.bool(forKey: Self.linksPanesKey)
    }

    deinit {
        watchTask?.cancel()
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
                showComparison(reference: reference, failure: failure, certainty: .stated)
            case let .openPullRequest(input):
                openPullRequest(input)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Opens whatever a path turns out to be: a project folder, or a single image.
    func openPath(_ url: URL) {
        if filesystem.isDirectory(at: url) {
            openProject(at: url)
        } else if url.isImageFile {
            setPreview(.single(Self.looseSnapshot(at: url)))
        } else {
            lastError = "“\(url.lastPathComponent)” is neither a folder nor an image GimDiff can open."
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
            lastError = "“\(url.path)” is not a folder."
            return
        }

        // Opening a project is a way out of a review as much as closing it is; the project
        // the review replaced is not coming back, because the user just chose another.
        abandonPullRequestReview()

        // A newer open supersedes the one in flight: scanning a large repository takes long
        // enough that two overlapping scans would race to publish their results.
        scanTask?.cancel()
        // The scan about to start reads everything a background refresh would have.
        cancelBackgroundRefresh()
        loadingProjectURL = root
        lastError = nil
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
                lastError = error.localizedDescription
                loadingProjectURL = nil
            }
        }
    }

    /// Rescans the open project, picking up snapshots a test run has written since.
    ///
    /// Under review, the pull request is fetched again instead: new commits are what would
    /// have changed, and there is no folder of GimDiff's own worth rescanning.
    func reload() {
        if let session = pullRequestSession {
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
        abandonPullRequestReview()
        scanTask?.cancel()
        stopWatching()
        discardTestRun()
        testRunLocateTask?.cancel()
        testRunBundles = []
        pinnedTestRunBundleURL = nil
        closePreview()
        currentProject = nil
        selectedRowID = nil
        expandedSuiteIDs = []
        loadingProjectURL = nil
        lastError = nil
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
        setPreview(nil)
        // A project with one suite is a suite, so there is nothing to be gained by making
        // the user open it. Several suites start closed, which is the useful overview.
        expandedSuiteIDs = bundle.suites.count == 1 ? Set(bundle.suites.map(\.id)) : []
        // Whatever the last project's run failed on says nothing about this one, and a
        // project always opens on its own status: the run is read when it is asked for.
        discardTestRun()
        sidebarSource = .project
        selectedRowID = visibleRows.first?.id
        restartWatching()
        testRunBundles = []
        pinnedTestRunBundleURL = nil
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
        expandedSuiteIDs.formIntersection(bundle.suites.map(\.id) + [Self.testRunSuiteID])

        let rows = visibleRows
        if rowsBefore.isEmpty {
            // A tree that had nothing to select now does, and the keyboard needs a row.
            selectedRowID = selectedRowID ?? rows.first?.id
        } else if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectedRowID = Self.survivor(of: selected, among: rowsBefore, in: rows)
        }

        // An attachment of the test run was never in the scan, and is not gone for that.
        if let shown = preview?.snapshotID,
           !Self.isTestRunAttachment(snapshotID: shown),
           !bundle.suites.contains(where: { $0.snapshots.contains { $0.id == shown } }) {
            closePreview()
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
            guard testRun != nil else { return [] }
            // Last, below everything the project itself holds: these are images the run
            // attached that belong to none of it.
            if let attachments = testRunAttachmentsSuite { suites.append(attachments) }
        }

        let query = trimmedFilterText.lowercased()
        var rows: [TreeRowItem] = []

        for suite in suites where !showWarningsOnly || hasSourceWarning(suite) {
            var children = showGitModifiedOnly ? suite.snapshots.filter(\.hasGitDiff) : suite.snapshots
            if isShowingTestRun {
                children = children.filter { isFailingInTestRun($0) }
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
              preview?.snapshotID != snapshot.id
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
            if preview?.snapshotID == snapshot.id {
                preview = nil
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

    /// Shows one snapshot, against its committed version when it has one.
    ///
    /// The image is put on screen immediately and upgraded to a comparison once git has
    /// written the committed file out: extracting it spawns a process, and waiting for that
    /// before drawing anything would make every selection feel slow.
    func showSnapshot(_ snapshot: SnapshotItem, withGitDiff: Bool) {
        gitDiffTask?.cancel()

        if let change = pullRequestSession?.changes[snapshot.id] {
            showPullRequestChange(change, of: snapshot, withBaseline: withGitDiff)
            return
        }

        guard !Self.isTestRunAttachment(snapshotID: snapshot.id) else {
            setPreview(.testRunAttachment(snapshot))
            return
        }

        // What the last run rendered says more than what the last commit held: the failure
        // is why the snapshot is being looked at.
        if withGitDiff, sidebarSource == .testRun,
           let candidate = testRun?.candidates(forSnapshotID: snapshot.id).first {
            showTestRunCandidate(candidate, against: snapshot)
            return
        }

        setPreview(.single(snapshot))

        guard withGitDiff,
              snapshot.gitStatus == .modified,
              let gitRoot = currentProject?.gitRootURL,
              let relativePath = Self.relativePath(of: snapshot.fileURL, under: gitRoot)
        else { return }

        gitDiffTask = Task { [gitService] in
            // An untracked or newly added snapshot has nothing at HEAD to compare with, so
            // a failure here is ordinary: the image stays on screen on its own.
            guard let committed = try? await gitService.extractCommittedVersion(
                ofFileAt: relativePath,
                repositoryRoot: gitRoot,
                gitRef: Self.comparisonGitRef
            ) else { return }

            guard !Task.isCancelled, preview?.snapshotID == snapshot.id else { return }
            setPreview(.comparison(
                SnapshotPair(reference: committed, failure: snapshot.fileURL),
                snapshotID: snapshot.id,
                title: snapshot.displayName,
                baselineOrigin: .committedVersion
            ))
        }
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
            setPreview(.comparison(
                SnapshotPair(reference: baseline, failure: candidate),
                snapshotID: snapshot.id,
                title: snapshot.displayName,
                baselineOrigin: .pullRequest
            ))
        case let (candidate?, _):
            var head = snapshot
            head.fileURL = candidate
            setPreview(.pullRequestSide(head, role: .candidate))
        case let (nil, baseline?):
            var base = snapshot
            base.fileURL = baseline
            setPreview(.pullRequestSide(base, role: .baseline))
        case (nil, nil):
            setPreview(nil)
        }
    }

    /// Shows two loose images side by side, from a drop, the clipboard, or a URL.
    ///
    /// - Parameter certainty: How the sides were chosen. A caller that named them — a
    ///   `gimdiff://compare` URL — leaves the default.
    func showComparison(reference: URL, failure: URL, certainty: LooseRoleCertainty = .stated) {
        gitDiffTask?.cancel()
        setPreview(.comparison(
            SnapshotPair(reference: reference, failure: failure),
            snapshotID: nil,
            title: failure.deletingPathExtension().lastPathComponent,
            baselineOrigin: .workingTree
        ))
        looseRoleCertainty = certainty
    }

    /// Shows a pasted or dropped pair once ``LooseRoleResolver`` has looked at the files.
    ///
    /// The pair is shown only after: drawing it in the source's order first and swapping
    /// it a moment later would put a baseline label on the wrong image, however briefly.
    func showLooseComparison(baseline: URL, candidate: URL, rolesAreStated: Bool) {
        looseRoleTask?.cancel()
        let resolver = LooseRoleResolver(gitService: gitService)
        let projectRoot = currentProject?.rootURL
        looseRoleTask = Task {
            let resolution = await resolver.resolve(
                baseline: baseline,
                candidate: candidate,
                rolesAreStated: rolesAreStated,
                projectRoot: projectRoot
            )
            guard !Task.isCancelled else { return }
            showComparison(
                reference: resolution.baselineURL,
                failure: resolution.candidateURL,
                certainty: resolution.certainty
            )
        }
    }

    /// The side decision in flight for a pasted or dropped pair, if any.
    var currentLooseRoleResolution: Task<Void, Never>? { looseRoleTask }

    func closePreview() {
        gitDiffTask?.cancel()
        setPreview(nil)
    }

    // MARK: - Mutation seams

    /// Replaces what the canvas is showing, dropping anything measured about the last pair.
    ///
    /// Every route into ``preview`` runs through here, including the ones in
    /// `AppState+FileActions`: a report left over from the previous pair would otherwise
    /// keep describing it under the new one's images.
    ///
    /// ``diffMode`` deliberately survives. Stepping through a folder of snapshots in curtain
    /// mode should stay in curtain mode; the canvas falls back to a single pane on its own
    /// when the new preview has only one image.
    func setPreview(_ newValue: SnapshotPreview?) {
        diffTask?.cancel()
        // Whatever the canvas shows next, a pair still being decided is no longer wanted.
        looseRoleTask?.cancel()
        looseRoleCertainty = nil
        preview = newValue
        diffReport = nil
        isComputingDiff = false
    }

    /// Publishes the result of a pixel comparison, or that one is under way.
    func setDiffReport(_ report: ImageDiffReport?, isComputing: Bool = false) {
        diffReport = report
        isComputingDiff = isComputing
    }

    /// Makes every view holding a decoded image read it off disk again.
    func invalidateLoadedImages() {
        imageReloadToken += 1
    }

    /// Replaces what the last test run is known to have failed on.
    func setTestRun(_ newValue: TestRunResults?) {
        testRun = newValue
    }

    func report(_ error: any Error) {
        lastError = error.localizedDescription
    }

    func report(_ message: String) {
        lastError = message
    }

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

    /// The committed-version extraction in flight, if any, so a caller can wait for it.
    var currentGitDiff: Task<Void, Never>? { gitDiffTask }

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
            lastError = "The clipboard holds no snapshot path GimDiff recognises."
            return
        }

        guard let baseline = payload.baselineURL else {
            setPreview(.single(Self.looseSnapshot(at: payload.candidateURL)))
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

    func dismissError() {
        lastError = nil
    }

    // MARK: - Context menu actions

    func copyToClipboard(_ text: String) {
        clipboard.copy(text)
    }

    func openTestSource(for suite: SnapshotSuite) {
        guard let sourceCodeURL = suite.sourceCodeURL else {
            lastError = "GimDiff could not find the test source for “\(suite.name)”."
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
        return preview?.snapshotID == snapshot.id
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

    /// What showing `snapshot` with its diff is called, in the menu bar and on the row alike.
    func compareActionTitle(for snapshot: SnapshotItem?) -> String {
        if isReviewingPullRequest { return "Compare with Base Branch" }
        if let snapshot, sidebarSource == .testRun, testRun?.isFailing(snapshotID: snapshot.id) == true {
            return "Compare with Test Run"
        }
        return "Show Snapshot with Git Diff"
    }

    /// What showing a snapshot on its own is called, in the menu bar and on the row alike.
    var showAloneActionTitle: String {
        isReviewingPullRequest ? "Show Pull Request Version Only" : "Show Snapshot without Git Diff"
    }

    // MARK: - Canvas view commands

    /// Whether anything on screen has the display mode and zoom the View menu drives: a
    /// single image, a side-by-side pair, or the diff mask. The curtain and the onion skin
    /// draw both images in one fixed frame.
    var canvasHasZoomableImages: Bool {
        guard let preview else { return false }
        guard preview.isComparison else { return true }
        return diffMode == .sideBySide || diffMode == .difference
    }

    /// Whether the onion skin is on screen for the View menu's fade commands to reach.
    var canvasShowsOnionSkin: Bool {
        preview?.isComparison == true && diffMode == .onionSkin
    }

    /// Hands `command` to whichever canvas views it applies to.
    func requestCanvasView(_ command: CanvasViewCommand) {
        canvasViewRequest = CanvasViewRequest(
            serial: (canvasViewRequest?.serial ?? 0) + 1,
            command: command
        )
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

        guard trash(snapshot.fileURL, actionName: "Move Snapshot to Trash") else { return }

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

        guard trash(suite.snapshotsFolderURL, actionName: "Move Snapshots Folder to Trash") else { return }

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
        lastError = "Snapshots in a pull request review are read-only; there is nothing on disk to delete."
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
            lastError = error.localizedDescription
            return false
        }
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
        if let shown = preview?.snapshotID, removedSnapshotIDs.contains(shown) {
            closePreview()
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
    var isReviewingPullRequest: Bool { pullRequestSession != nil }

    /// What the pull request under review does to a snapshot, or `nil` outside a review.
    func pullRequestChange(forSnapshotID id: String?) -> PRSnapshotChange? {
        guard let id else { return nil }
        return pullRequestSession?.changes[id]
    }

    /// ⌘⇧O: raises the Open PR sheet, filled in from the clipboard when it holds a link.
    func presentPullRequestSheet() {
        if !isFetchingPullRequest {
            pullRequestError = nil
            if pullRequestInput.isEmpty,
               let text = clipboard.string(),
               let reference = ingestion.parsePullRequest(text) {
                pullRequestInput = reference.webURL.absoluteString
            }
        }
        isHelpPresented = false
        isPullRequestSheetPresented = true
    }

    /// ⌘?: raises the help sheet, unless the Open PR sheet already covers the window.
    func presentHelp() {
        guard !isPullRequestSheetPresented else { return }
        isHelpPresented = true
    }

    func dismissHelp() {
        isHelpPresented = false
    }

    /// Puts the sheet away, abandoning a fetch still in flight.
    func dismissPullRequestSheet() {
        pullRequestTask?.cancel()
        pullRequestTask = nil
        isFetchingPullRequest = false
        pullRequestError = nil
        isPullRequestSheetPresented = false
    }

    /// Fetches the pull request `input` names and, once its snapshots are downloaded,
    /// shows them in place of the open project.
    func openPullRequest(_ input: String) {
        pullRequestInput = input
        pullRequestError = nil
        isHelpPresented = false
        isPullRequestSheetPresented = true

        pullRequestTask?.cancel()
        isFetchingPullRequest = true

        let root = currentProject?.gitRootURL
        let preferred = pullRequestSession?.reference.repository
        pullRequestTask = Task { [pullRequests, pullRequestResolver] in
            do {
                let reference = try await pullRequestResolver.reference(
                    for: input,
                    repositoryRoot: root,
                    preferredRepository: preferred
                )
                let session = try await pullRequests.fetchPRSession(reference: reference)
                guard !Task.isCancelled else {
                    discardFiles(of: session)
                    return
                }
                beginPullRequestReview(session)
            } catch {
                // A cancelled download reports itself as a `URLError`, not as a
                // `CancellationError`, so the task is asked rather than the error.
                guard !Task.isCancelled else { return }
                isFetchingPullRequest = false
                pullRequestError = error.localizedDescription
            }
        }
    }

    /// The fetch in flight, if any, so a caller can wait for it.
    var currentPullRequestFetch: Task<Void, Never>? { pullRequestTask }

    /// Ends the review, deleting what it downloaded, and puts back the project it replaced.
    func closePullRequestReview() {
        guard pullRequestSession != nil else { return }
        let previous = projectBeforePullRequest
        abandonPullRequestReview()
        clearFilters()

        guard let previous else {
            closeProject()
            return
        }
        load(previous)
        // The project sat unwatched for the length of the review; its files may have moved.
        refreshGitStatus()
    }

    /// Deletes the downloaded snapshots of the review in progress, for the app to call on
    /// its way out.
    func discardPullRequestFiles() {
        pullRequestTask?.cancel()
        guard let session = pullRequestSession else { return }
        discardFiles(of: session)
    }

    private func beginPullRequestReview(_ session: PRReviewSession) {
        if let current = pullRequestSession {
            // A second review replaces the first, but the project behind both stays the one
            // to go back to.
            discardFiles(of: current)
        } else {
            projectBeforePullRequest = currentProject
        }

        scanTask?.cancel()
        clearFilters()
        pullRequestSession = session
        load(ProjectBundle(rootURL: session.tempDirectoryURL, suites: session.suites))
        // A pull request is read to see what it changed, so every change starts on show.
        expandedSuiteIDs = Set(session.suites.map(\.id))
        // Land on the first change itself, not the suite above it, so the canvas has
        // something to show the moment the sheet goes away.
        selectRow(withID: visibleRows.first(where: \.isSnapshot)?.id ?? visibleRows.first?.id)

        isFetchingPullRequest = false
        isPullRequestSheetPresented = false
        pullRequestInput = ""
    }

    /// Leaves the review without restoring anything, for a caller about to replace it.
    private func abandonPullRequestReview() {
        pullRequestTask?.cancel()
        pullRequestTask = nil
        isFetchingPullRequest = false
        guard let session = pullRequestSession else { return }
        discardFiles(of: session)
        pullRequestSession = nil
        projectBeforePullRequest = nil
    }

    private func discardFiles(of session: PRReviewSession) {
        guard filesystem.fileExists(at: session.tempDirectoryURL) else { return }
        do {
            try filesystem.removeItem(at: session.tempDirectoryURL)
        } catch {
            lastError = error.localizedDescription
        }
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
