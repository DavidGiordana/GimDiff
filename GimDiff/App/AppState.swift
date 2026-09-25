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
    /// How many folders the recent list keeps before it starts forgetting the oldest.
    static let recentProjectsLimit = 12
    /// Commit-ish a snapshot is compared against when its Git diff is shown.
    static let comparisonGitRef = "HEAD"

    // MARK: - Project

    /// Whether a scan is in flight. The sidebar shows a spinner rather than an empty tree.
    var isLoading = false
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
    /// Bumped to make the canvas read its images off disk again.
    ///
    /// A counter rather than a flag because the file name never changes: nothing about the
    /// URL tells a view that the bytes behind it were rewritten by a test run.
    private(set) var imageReloadToken = 0
    /// The most recent failure, shown as a banner until it is dismissed.
    private(set) var lastError: String?

    /// Bumped whenever something outside the sidebar asks it to move keyboard focus.
    ///
    /// A counter rather than a flag: the menu's Find command has to be able to pull focus
    /// back to the filter field a second time without anything having reset it in between.
    private(set) var filterFocusRequests = 0
    private(set) var treeFocusRequests = 0

    let filesystem: any FilesystemService
    let gitService: any GitService
    let imageDiff: any ImageDiffService
    private let scanner: ProjectScanner
    private let ingestion: any IngestionService
    private let clipboard: ClipboardService
    private let workspace: WorkspaceService
    private let defaults: UserDefaults
    private var scanTask: Task<Void, Never>?
    private var gitDiffTask: Task<Void, Never>?
    /// Held so a second diff request supersedes the first rather than racing it.
    var diffTask: Task<Void, Never>?
    var gitStatusTask: Task<Void, Never>?

    init(
        filesystem: any FilesystemService = DefaultFilesystemService(),
        gitService: (any GitService)? = nil,
        imageDiff: (any ImageDiffService)? = nil,
        scanner: ProjectScanner? = nil,
        ingestion: any IngestionService = DefaultIngestionService(),
        clipboard: ClipboardService = ClipboardService(),
        workspace: WorkspaceService = WorkspaceService(),
        defaults: UserDefaults = .standard
    ) {
        let git = gitService ?? DefaultGitService(filesystem: filesystem)
        self.filesystem = filesystem
        self.gitService = git
        self.imageDiff = imageDiff ?? DefaultImageDiffService(filesystem: filesystem)
        self.scanner = scanner ?? ProjectScanner(filesystem: filesystem, gitService: git)
        self.ingestion = ingestion
        self.clipboard = clipboard
        self.workspace = workspace
        self.defaults = defaults
        recentProjects = Self.loadRecentProjects(from: defaults)
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
                showComparison(reference: reference, failure: failure)
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

        showComparison(reference: images[0], failure: images[1])
    }

    /// Scans `url` and replaces whatever the window was showing.
    func openProject(at url: URL) {
        let root = url.resolvingSymlinksInPath()
        guard filesystem.isDirectory(at: root) else {
            lastError = "“\(url.path)” is not a folder."
            return
        }

        // A newer open supersedes the one in flight: scanning a large repository takes long
        // enough that two overlapping scans would race to publish their results.
        scanTask?.cancel()
        isLoading = true
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
                // Superseded by a newer scan, which owns `isLoading` now.
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Rescans the open project, picking up snapshots a test run has written since.
    func reload() {
        guard let root = currentProject?.rootURL else { return }
        openProject(at: root)
    }

    /// Puts the window back to the recent project list.
    ///
    /// The folder stays in ``recentProjects``, so closing is a way back to the list rather
    /// than a way to forget where the project was.
    func closeProject() {
        scanTask?.cancel()
        closePreview()
        currentProject = nil
        selectedRowID = nil
        expandedSuiteIDs = []
        isLoading = false
        lastError = nil
        // The filters described the project that has just gone; carrying them into the next
        // one would hide most of it for no reason the user could see.
        clearFilters()
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
        currentProject = bundle
        isLoading = false
        setPreview(nil)
        // A project with one suite is a suite, so there is nothing to be gained by making
        // the user open it. Several suites start closed, which is the useful overview.
        expandedSuiteIDs = bundle.suites.count == 1 ? Set(bundle.suites.map(\.id)) : []
        selectedRowID = visibleRows.first?.id
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

    /// Resets the search field and both filter chips.
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
        guard let suites = currentProject?.suites else { return [] }

        let query = trimmedFilterText.lowercased()
        var rows: [TreeRowItem] = []

        for suite in suites where !showWarningsOnly || suite.isMissingSourceCode {
            var children = showGitModifiedOnly ? suite.snapshots.filter(\.hasGitDiff) : suite.snapshots
            let suiteMatches = query.isEmpty || suite.name.lowercased().contains(query)

            if suiteMatches {
                // The chip, unlike the query, is a statement about snapshots: a suite with
                // nothing modified under it has nothing to say while it is on.
                guard !showGitModifiedOnly || !children.isEmpty else { continue }
            } else {
                children = children.filter { $0.displayName.lowercased().contains(query) }
                guard !children.isEmpty else { continue }
            }

            let isExpanded = expandedSuiteIDs.contains(suite.id) || !query.isEmpty
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

    func toggleExpansion(ofSuiteWithID id: String) {
        if expandedSuiteIDs.remove(id) == nil {
            expandedSuiteIDs.insert(id)
        }
    }

    /// Moves the selection to the first row currently visible.
    func selectFirstVisibleRow() {
        selectedRowID = visibleRows.first?.id
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
        selectedRowID = rows[index + 1].id
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
    func openTestSource() {
        guard let suite = selectedRow.flatMap(suite(for:)) else { return }
        openTestSource(for: suite)
    }

    /// Command-Return: reveals the selected snapshot, or its suite's folder, in the Finder.
    func revealSelectionInFinder() {
        switch selectedRow {
        case let .snapshot(snapshot, _):
            workspace.revealInFinder(snapshot.fileURL)
        case let .suite(suite, _, _):
            workspace.revealInFinder(suite.snapshotsFolderURL)
        case nil:
            break
        }
    }

    func focusFilter() {
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

    /// Shows two loose images side by side, from a drop, the clipboard, or a URL.
    func showComparison(reference: URL, failure: URL) {
        gitDiffTask?.cancel()
        setPreview(.comparison(
            SnapshotPair(reference: reference, failure: failure),
            snapshotID: nil,
            title: failure.deletingPathExtension().lastPathComponent,
            baselineOrigin: .workingTree
        ))
    }

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

    /// Reads a comparison out of whatever is on the pasteboard.
    func pasteFromClipboard() {
        let fileURLs = clipboard.fileURLs()
        guard fileURLs.isEmpty else {
            openPaths(fileURLs)
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

        showComparison(reference: baseline, failure: payload.candidateURL)
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
        let rowID = TreeRowItem.snapshotRowID(snapshot.id, parentSuiteID: suiteID)
        let replacement = selection(surviving: [rowID])

        guard trash(snapshot.fileURL) else { return }

        // Pruned in memory rather than rescanned: the scan that found this snapshot walked
        // the whole project, and nothing about deleting one file needs that repeated.
        guard let index = currentProject?.suites.firstIndex(where: { $0.id == suiteID }) else { return }
        currentProject?.suites[index].snapshots.removeAll { $0.id == snapshot.id }

        finishDeletion(replacement: replacement, removedSnapshotIDs: [snapshot.id])
    }

    func delete(suite: SnapshotSuite) {
        var removedRowIDs: Set<String> = [TreeRowItem.suiteRowID(suite.id)]
        for snapshot in suite.snapshots {
            removedRowIDs.insert(TreeRowItem.snapshotRowID(snapshot.id, parentSuiteID: suite.id))
        }
        let replacement = selection(surviving: removedRowIDs)

        guard trash(suite.snapshotsFolderURL) else { return }

        currentProject?.suites.removeAll { $0.id == suite.id }
        expandedSuiteIDs.remove(suite.id)

        finishDeletion(replacement: replacement, removedSnapshotIDs: Set(suite.snapshots.map(\.id)))
    }

    private func trash(_ url: URL) -> Bool {
        do {
            try filesystem.trashFile(at: url)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func finishDeletion(replacement: String?, removedSnapshotIDs: Set<String>) {
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
