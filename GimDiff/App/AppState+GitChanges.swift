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
            && !Self.isTestRunAttachment(snapshotID: snapshot.id)
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

    /// Every snapshot of the project Discard All would restore, listed once each.
    ///
    /// Empty under the test run's view: that view lists failures, not changes, so a button
    /// over it would act on rows nobody can see.
    var discardableProjectSnapshots: [SnapshotItem] {
        guard sidebarSource == .project else { return [] }
        var seen: Set<SnapshotItem.ID> = []
        return (currentProject?.suites ?? [])
            .flatMap(discardableSnapshots(in:))
            .filter { seen.insert($0.id).inserted }
    }

    /// Asks before ``discardAllGitChanges()``, which every route to it goes through.
    ///
    /// Git keeps no copy of a change that was never staged, so nothing would bring back what
    /// a stray click threw away.
    func requestDiscardAllGitChanges() {
        guard !discardableProjectSnapshots.isEmpty else { return }
        isConfirmingDiscardAllGitChanges = true
    }

    /// Restores every modified snapshot of the project to what `HEAD` holds.
    func discardAllGitChanges() {
        isConfirmingDiscardAllGitChanges = false
        discardGitChanges(of: discardableProjectSnapshots)
    }

    /// Restores `snapshots` to what `HEAD` holds, dropping staged and unstaged changes alike.
    ///
    /// The badges are cleared in memory as soon as git succeeds, rather than on the status
    /// read that follows: with *Show Only Modified Snapshots* on, the rows leave the tree,
    /// and the selection has to move to a neighbour in the same step.
    func discardGitChanges(of snapshots: [SnapshotItem]) {
        let snapshots = snapshots.filter(canDiscardGitChanges(of:))
        guard !snapshots.isEmpty, let gitRoot = currentProject?.gitRootURL else { return }

        discardTask?.cancel()
        discardTask = Task { [gitService] in
            do {
                try await gitService.discardChanges(to: snapshots.map(\.fileURL), repositoryRoot: gitRoot)
            } catch {
                report(error)
                return
            }
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
        if let shown = preview?.snapshotID, snapshotIDs.contains(shown),
           preview?.baseline?.origin == .committedVersion,
           let snapshot = currentProject?.suites.lazy.flatMap(\.snapshots).first(where: { $0.id == shown }) {
            setPreview(.single(snapshot))
        }

        invalidateLoadedImages()
        refreshGitStatus()
    }
}
