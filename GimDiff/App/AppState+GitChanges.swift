//
//  AppState+GitChanges.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Throwing away what the working tree changed in a snapshot, so it holds `HEAD` again.
///
/// Unlike Reject, this needs no comparison on screen: it acts on rows of the tree, and on a
/// whole suite at once. Only a *modified* snapshot qualifies. An untracked one has nothing
/// at `HEAD` to go back to — discarding it would mean deleting it, which Delete already
/// does, and through the Trash.
extension AppState {
    /// Whether the snapshot carries a change Git can put back to `HEAD`.
    func canDiscardGitChanges(of snapshot: SnapshotItem) -> Bool {
        !isReviewingPullRequest
            && currentProject?.gitRootURL != nil
            && snapshot.gitStatus == .modified
            && !TestRunModel.isAttachment(snapshotID: snapshot.id)
    }

    /// The snapshots of `suite` that ``discardGitChanges(of:)`` would restore.
    func discardableSnapshots(in suite: SnapshotSuite) -> [SnapshotItem] {
        suite.snapshots.filter(canDiscardGitChanges(of:))
    }

    /// What the selection would discard: its snapshot, or every changed snapshot of its suite.
    var discardableSelection: [SnapshotItem] {
        switch selectedRow {
        case let .snapshot(snapshot, _): canDiscardGitChanges(of: snapshot) ? [snapshot] : []
        case let .suite(suite, _, _): discardableSnapshots(in: suite)
        case nil: []
        }
    }

    func discardSelectionGitChanges() {
        discardGitChanges(of: discardableSelection)
    }

    /// Whether Discard All can be asked for: a project under Git, in the project's own view.
    ///
    /// Not under the test run's view: that view lists failures, not changes, so a button
    /// over it would act on rows nobody can see. Not conditional on a row showing a change
    /// either, because a snapshot deleted from disk has no row and still differs from `HEAD`.
    var canDiscardAllGitChanges: Bool {
        sidebarSource == .project && !isReviewingPullRequest && currentProject?.gitRootURL != nil
    }

    /// Whether a snapshot on disk differs from `HEAD`, which is when the filter bar offers
    /// Discard All beside its chips.
    var projectHasGitChanges: Bool {
        canDiscardAllGitChanges && currentProject?.suites.contains(where: \.hasGitDiff) == true
    }

    /// Asks before ``discardAllGitChanges()``, which every route to it goes through.
    ///
    /// Git's status is read first, so the question can say how many snapshots come back and
    /// how many go to the Trash. Git keeps no copy of a change that was never staged, so
    /// nothing would bring back what a stray click threw away.
    func requestDiscardAllGitChanges() {
        guard canDiscardAllGitChanges, let project = currentProject, let gitRoot = project.gitRootURL else { return }

        discardTask?.cancel()
        discardTask = Task { [gitService] in
            let plan: HEADRestorePlan
            do {
                plan = HEADRestorePlan(
                    suites: project.suites,
                    statuses: try await gitService.status(repositoryRoot: gitRoot)
                )
            } catch {
                report(error)
                return
            }
            guard !Task.isCancelled, currentProject?.rootURL == project.rootURL else { return }
            guard !plan.isEmpty else {
                report(String(localized: "Every snapshot already matches the committed version."))
                return
            }
            headRestorePlan = plan
            isConfirmingDiscardAllGitChanges = true
        }
    }

    /// Puts every snapshot of the project back to what `HEAD` holds.
    ///
    /// Modified and deleted snapshots, and a rename's old name, are restored. Snapshots
    /// `HEAD` does not have — added, untracked, a rename's new name — go to the Trash. The
    /// status is read again rather than taken from the question: a test run may have written
    /// since it was asked.
    func discardAllGitChanges() {
        isConfirmingDiscardAllGitChanges = false
        headRestorePlan = nil
        guard canDiscardAllGitChanges, let project = currentProject, let gitRoot = project.gitRootURL else { return }

        discardTask?.cancel()
        discardTask = Task { [gitService] in
            let plan: HEADRestorePlan
            do {
                plan = HEADRestorePlan(
                    suites: project.suites,
                    statuses: try await gitService.status(repositoryRoot: gitRoot)
                )
            } catch {
                report(error)
                return
            }
            guard !Task.isCancelled, currentProject?.rootURL == project.rootURL, !plan.isEmpty else { return }
            await restoreToHEAD(plan, repositoryRoot: gitRoot)
        }
    }

    /// Carries out `plan`: the Trash first, then one `git restore` over everything else.
    ///
    /// The order is what keeps a staged snapshot: `git restore --source=HEAD` deletes a path
    /// `HEAD` does not have, so it must already be in the Trash. A file that cannot be
    /// trashed therefore stops the whole restore before git runs.
    private func restoreToHEAD(_ plan: HEADRestorePlan, repositoryRoot: URL) async {
        let actionName = String(localized: "Discard All Changes")
        // Saved before anything moves: a change that was never staged exists nowhere else.
        let saved = saveForUndo(plan.committedURLs)

        var trashed: [(original: URL, location: URL)] = []
        for url in plan.trashedURLs {
            do {
                if let location = try filesystem.trashFile(at: url) {
                    trashed.append((url, location))
                }
            } catch {
                registerHEADRestoreUndo(saved: [], trashed: trashed, actionName: actionName)
                discardSaved(saved)
                report(error)
                rescanAfterOwnEdit()
                return
            }
        }

        do {
            try await gitService.discardChanges(to: plan.restoredURLs, repositoryRoot: repositoryRoot)
        } catch {
            // What reached the Trash stays undoable; git changed nothing.
            registerHEADRestoreUndo(saved: [], trashed: trashed, actionName: actionName)
            discardSaved(saved)
            report(error)
            rescanAfterOwnEdit()
            return
        }

        registerHEADRestoreUndo(saved: saved, trashed: trashed, actionName: actionName)
        finishRestoringToHEAD(plan)
    }

    /// Registers the Trash and the restore as one step, which is how the question asked
    /// about them.
    private func registerHEADRestoreUndo(
        saved: [SavedFile],
        trashed: [(original: URL, location: URL)],
        actionName: String
    ) {
        let needsGroup = undoManager.map { $0.groupingLevel == 0 } ?? false
        if needsGroup { undoManager?.beginUndoGrouping() }
        defer { if needsGroup { undoManager?.endUndoGrouping() } }

        for item in trashed {
            registerUndoOfTrash(original: item.original, trashed: item.location, actionName: actionName)
        }
        registerUndo(restoring: saved, actionName: actionName)
    }

    /// Takes the trashed snapshots out of the tree and clears the restored ones' badges.
    ///
    /// A deleted snapshot git put back has no row yet, so when there is one the project is
    /// rescanned to list it.
    private func finishRestoringToHEAD(_ plan: HEADRestorePlan) {
        let trashedPaths = Set(plan.trashedURLs.map(\.path))
        let committedPaths = Set(plan.committedURLs.map(\.path))
        let snapshots = currentProject?.suites.flatMap(\.snapshots) ?? []
        let trashedIDs = Set(snapshots.filter { trashedPaths.contains($0.fileURL.standardizedFileURL.path) }.map(\.id))
        let restoredIDs = Set(snapshots.filter { committedPaths.contains($0.fileURL.standardizedFileURL.path) }.map(\.id))

        let rowsBefore = visibleRows
        removeSnapshots(trashedIDs)
        if let selected = selectedRowID, !visibleRows.contains(where: { $0.id == selected }) {
            selectedRowID = Self.survivor(of: selected, among: rowsBefore, in: visibleRows)
        }
        if let shown = canvas.preview?.snapshotID, trashedIDs.contains(shown) {
            canvas.close()
        }

        finishDiscarding(restoredIDs)
        let listedPaths = Set(snapshots.map(\.fileURL.standardizedFileURL.path))
        if !committedPaths.isSubset(of: listedPaths) {
            rescanAfterOwnEdit()
        }
    }

    /// Restores `snapshots` to what `HEAD` holds, dropping staged and unstaged changes alike.
    ///
    /// The badges are cleared in memory as soon as git succeeds, rather than on the status
    /// read that follows: with *Show Only Modified Snapshots* on, the rows leave the tree,
    /// and the selection has to move to a neighbour in the same step.
    func discardGitChanges(of snapshots: [SnapshotItem]) {
        let snapshots = snapshots.filter(canDiscardGitChanges(of:))
        guard !snapshots.isEmpty, let gitRoot = currentProject?.gitRootURL else { return }

        // Saved before git runs: a change that was never staged exists nowhere else.
        let saved = saveForUndo(snapshots.map(\.fileURL))

        discardTask?.cancel()
        discardTask = Task { [gitService] in
            do {
                try await gitService.discardChanges(to: snapshots.map(\.fileURL), repositoryRoot: gitRoot)
            } catch {
                discardSaved(saved)
                report(error)
                return
            }
            registerUndo(
                restoring: saved,
                actionName: snapshots.count == 1
                    ? String(localized: "Discard Changes")
                    : String(localized: "Discard Changes to \(snapshots.count) Snapshots")
            )
            finishDiscarding(Set(snapshots.map(\.id)))
        }
    }

    /// The discard in flight, if any, so a caller can wait for it.
    var currentDiscard: Task<Void, Never>? { discardTask }

    private func finishDiscarding(_ snapshotIDs: Set<String>) {
        let rowsBefore = visibleRows

        markUnmodified(snapshotIDs)

        let rows = visibleRows
        if let selected = selectedRowID, !rows.contains(where: { $0.id == selected }) {
            selectedRowID = Self.survivor(of: selected, among: rowsBefore, in: rows)
        }

        // A comparison against `HEAD` would now hold two identical images.
        if let shown = canvas.preview?.snapshotID, snapshotIDs.contains(shown),
           canvas.preview?.baseline?.origin == .committedVersion,
           let snapshot = currentProject?.suites.lazy.flatMap(\.snapshots).first(where: { $0.id == shown }) {
            canvas.show(.single(snapshot))
        }

        rereadTestRunAfterDiscarding()
        canvas.invalidateLoadedImages()
        refreshGitStatus()
    }

    /// Forgets the run read so far, so the failures an accept settled can come back.
    ///
    /// Accepting takes a failure out of the run in memory, and nothing short of reading the
    /// bundle again puts it back. Under the project's view the read waits for the next
    /// switch, as it does when a new run arrives.
    func rereadTestRunAfterDiscarding() {
        guard testRuns.results != nil else { return }
        discardTestRun()
        // The candidate on the canvas was a copy out of the run just discarded.
        if case .testRunFailure = canvas.preview { canvas.close() }
        if sidebarSource == .testRun { refreshTestRun() }
    }
}
