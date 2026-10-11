//
//  AppState+Watching.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Keeping the open project in step with the disk without being asked.
///
/// A test run rewrites snapshots while GimDiff sits behind the editor, so nothing here may
/// depend on the window being key or on anybody pressing ⌘R. The watcher reports what
/// moved, ``ProjectChangeClassifier`` says what that means, and the cheapest refresh that
/// covers it runs — never ``load(_:)``, which would take the selection, the open suites,
/// and the canvas away from whoever comes back to the window.
extension AppState {
    // MARK: - Lifecycle

    /// Starts watching the project now on screen, in place of whatever was watched before.
    ///
    /// A pull request review is left unwatched: its files are scratch copies nothing but
    /// GimDiff writes to.
    func restartWatching() {
        stopWatching()
        guard !isReviewingPullRequest, let project = currentProject else { return }

        var roots = [project.rootURL]
        // A project opened below the top of its repository does not have the Git directory
        // under it, and a commit made there changes badges without touching a snapshot.
        if let gitDirectory = ProjectChangeClassifier.gitDirectory(of: project),
           Self.relativePath(of: gitDirectory, under: project.rootURL) == nil,
           filesystem.isDirectory(at: gitDirectory) {
            roots.append(gitDirectory)
        }

        // Where Xcode writes the next run's results, which is outside the project entirely.
        testRuns.updateResultDirectories(for: project)
        roots += testRuns.resultDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) }

        let batches = watcher.changes(under: roots)
        // Weakly held: the loop only ends when the stream does, and a strong reference
        // would keep the state alive to go on feeding a window that is gone.
        watchTask = Task { [weak self] in
            for await events in batches {
                await self?.projectFilesChanged(events)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        testRuns.updateResultDirectories(for: nil)
        cancelBackgroundRefresh()
    }

    /// Drops whatever refresh was pending or under way, for a caller about to do better.
    func cancelBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        pendingChange = ProjectChange()
    }

    /// The background refresh in flight, if any, so a caller can wait for it.
    var currentBackgroundRefresh: Task<Void, Never>? { backgroundRefreshTask }

    // MARK: - Events

    /// Works out what a batch of file events means and queues the refresh it calls for.
    func projectFilesChanged(_ events: [ProjectFileEvent]) async {
        guard !isReviewingPullRequest, let project = currentProject else { return }

        // A result bundle being written is a test run under way, and says nothing about the
        // snapshots until it is finished.
        if testRuns.touchesResults(events) {
            testResultsChanged()
        }

        let change = await Self.classify(events, in: project, with: changeClassifier)
        // The project can have been replaced while the batch was being read.
        guard !Task.isCancelled,
              !isReviewingPullRequest,
              currentProject?.rootURL == project.rootURL
        else { return }

        schedule(change)
    }

    /// Off the main actor: a build inside the project reports thousands of paths a second,
    /// and reading them must not be what makes the window stutter.
    @concurrent
    private static func classify(
        _ events: [ProjectFileEvent],
        in project: ProjectBundle,
        with classifier: ProjectChangeClassifier
    ) async -> ProjectChange {
        classifier.classify(events, in: project)
    }

    /// Folds `change` into what is waiting and makes sure something is working through it.
    ///
    /// One refresh runs at a time. Events that arrive while a rescan is walking the project
    /// accumulate into a single follow-up rather than a rescan each, which is what keeps a
    /// test run that writes for a minute from queueing a minute of scans behind it.
    func schedule(_ change: ProjectChange) {
        guard !change.isEmpty else { return }
        pendingChange.formUnion(change)
        guard backgroundRefreshTask == nil else { return }

        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled, let self, let change = takePendingChange() {
                await perform(change)
            }
            // A cancelled task has already been replaced; the slot is no longer its own.
            if !Task.isCancelled { self?.backgroundRefreshTask = nil }
        }
    }

    private func takePendingChange() -> ProjectChange? {
        guard !pendingChange.isEmpty else { return nil }
        defer { pendingChange = ProjectChange() }
        return pendingChange
    }

    // MARK: - Refreshing

    private func perform(_ change: ProjectChange) async {
        if change.needsRescan {
            await rescanInBackground()
        } else if change.needsGitStatus {
            refreshGitStatus()
        }
        guard !Task.isCancelled else { return }

        // Only the images on screen are read again, and only when they are among the ones
        // rewritten: a run that re-records five hundred snapshots should not redraw the
        // one being looked at five hundred times.
        let isShowingRewrittenImage = canvas.preview?.panes.contains { pane in
            pane.isWritable
                && change.rewrittenSnapshotPaths.contains(pane.fileURL.standardizedFileURL.path)
        } ?? false
        guard isShowingRewrittenImage else { return }

        canvas.invalidateLoadedImages()
        canvas.updateDiffReport()
    }

    /// Scans the open project again and merges the result in, without the loading state.
    private func rescanInBackground() async {
        // A scan the user asked for is already on its way and will land on top of this one.
        guard !isLoading, let root = currentProject?.rootURL else { return }

        let edits = projectEdits
        let scanned = try? await scanner.scan(projectRoot: root)
        guard !Task.isCancelled,
              !isLoading,
              !isReviewingPullRequest,
              currentProject?.rootURL == root
        else { return }

        // A deletion made while the scan was walking may have been listed before the file
        // went, and merging that would put the row back. The scan is thrown away and run
        // again, because GimDiff's own writes are not reported for a later batch to fix.
        guard edits == projectEdits else {
            pendingChange.needsRescan = true
            return
        }

        guard let scanned else {
            // A project that cannot be read right now keeps the tree it had; the badges
            // can still be brought up to date.
            refreshGitStatus()
            return
        }
        merge(scanned)
    }
}
