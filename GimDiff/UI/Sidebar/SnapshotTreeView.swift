//
//  SnapshotTreeView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The snapshot tree: a flat `List` over ``AppState/visibleRows``, driven entirely by keys.
///
/// Every level of the hierarchy is a sibling row in one array, so ↑ and ↓ move through the
/// whole tree natively and → and ← are the only keys that have to know about nesting.
struct SnapshotTreeView: View {
    /// How far a snapshot row is inset under its suite.
    private static let childIndent: CGFloat = 16

    @Environment(AppState.self) private var state
    @Environment(\.controlActiveState) private var controlActiveState

    @FocusState private var focus: SidebarFocus?

    var body: some View {
        let rows = state.visibleRows

        VStack(spacing: 0) {
            if let session = state.pullRequestSession {
                PullRequestHeader(session: session, close: state.closePullRequestReview)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            } else if let project = state.currentProject {
                ProjectHeader(rootURL: project.rootURL, close: state.closeProject)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            if state.currentProject != nil {
                SnapshotFilterBar(focus: $focus)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }

            Divider()

            if state.isLoading {
                ProgressView("Scanning…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = state.pullRequestSession, session.suites.isEmpty {
                SidebarEmptyStateView.noSnapshotChanges(
                    prNumber: session.prNumber,
                    close: state.closePullRequestReview
                )
            } else if state.currentProject?.suites.isEmpty == true {
                SidebarEmptyStateView.noSnapshotsDiscovered(reload: state.reload)
            } else if rows.isEmpty {
                SidebarEmptyStateView.noMatches(clearFilters: state.clearFilters)
            } else {
                List(rows, selection: userSelection) { row in
                    TreeRowView(item: row)
                        .padding(.leading, row.isSnapshot ? Self.childIndent : 0)
                        .contextMenu {
                            TreeItemContextMenu(item: row)
                        }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("SnapshotTree")
                .focused($focus, equals: .tree)
                .onKeyPress(phases: .down, action: handle)
            }
        }
        // Focus is claimed when the window becomes key, not when the view appears. An
        // assignment made before the window is key is discarded, and the app then launches
        // with a selected row the arrow keys cannot move — the tree has to be clicked once
        // before any of the shortcuts below are reachable. Both hooks are needed because
        // either order is possible: the window may already be key by the time the sidebar
        // appears, or become key afterwards.
        .onAppear(perform: claimFocusIfIdle)
        .onChange(of: controlActiveState) { claimFocusIfIdle() }
        .onChange(of: state.filterFocusRequests) { claimFilterFocus() }
        .onChange(of: state.treeFocusRequests) { focus = .tree }
        // A freshly scanned project replaces every row, so focus is claimed again rather
        // than left on whatever the last project had.
        .onChange(of: state.currentProject?.rootURL) { focus = .tree }
    }

    /// The list's selection, routed through ``AppState/selectRow(withID:)`` so that
    /// ↑, ↓, and clicks show the snapshot they land on.
    ///
    /// A binding rather than `onChange(of: selectedRowID)`: the observer would also fire
    /// for the selection a deletion moves, and reopen the pane that deletion just closed.
    private var userSelection: Binding<String?> {
        Binding(
            get: { state.selectedRowID },
            set: { state.selectRow(withID: $0) }
        )
    }

    /// Moves focus into the search box, retrying while the sidebar is still coming back.
    ///
    /// ⌘F on a collapsed sidebar reopens it in the same update, and a `@FocusState`
    /// assignment to a field that is not on screen yet is dropped without a word. So the
    /// assignment is repeated for a few frames until the focus system takes it, rather than
    /// guessing how long the column's animation runs.
    private func claimFilterFocus() {
        Task { @MainActor in
            for _ in 0..<20 {
                focus = .filter
                try? await Task.sleep(for: .milliseconds(25))
                if focus == .filter { return }
            }
        }
    }

    /// Puts focus on the rows, unless the sidebar already has it somewhere.
    ///
    /// Guarded so returning to the window does not yank focus out of the search box the
    /// user left it in, and deferred by one turn of the main actor: assigned inside the
    /// update that made the window key, the focus system has not engaged yet and drops it.
    private func claimFocusIfIdle() {
        guard controlActiveState != .inactive, focus == nil else { return }
        Task { @MainActor in
            guard focus == nil else { return }
            focus = .tree
        }
    }

    /// The tree's unmodified keys, with everything else passed back to the `List`.
    ///
    /// ↑ and ↓ are deliberately absent: `List` already moves its selection through the
    /// flattened array, and intercepting them would only reimplement it worse. Returning
    /// `.ignored` for an unclaimed key is what keeps type-to-select working too.
    ///
    /// Only unmodified keys are read here. AppKit offers a ⌘-modified key to
    /// `performKeyEquivalent(with:)` — the menu bar — and never to `keyDown(with:)`, which
    /// is what `onKeyPress` observes, so ⌘⌫ and ⌘↩ are menu commands in ``AppCommands``
    /// instead. The rule runs the other way for keys without ⌘: a menu item bound to a bare
    /// Space or ↩ would fire while the user was typing in the search box, so those stay
    /// here, where nothing reads them unless the rows have focus.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Arrow keys arrive carrying `.numericPad`, so the flags are masked down to the
        // modifiers that actually distinguish one shortcut from another.
        guard press.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
            return .ignored
        }

        switch press.key {
        case .rightArrow:
            return state.expandOrDescend() ? .handled : .ignored

        case .leftArrow:
            return state.collapseOrAscend() ? .handled : .ignored

        case .space:
            state.togglePreview()
            return .handled

        case .return:
            state.openTestSource()
            return .handled

        case KeyEquivalent("/"):
            focus = .filter
            return .handled

        default:
            return .ignored
        }
    }
}
/// Names the open project and offers the way out of it.
private struct ProjectHeader: View {
    let rootURL: URL
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.tint)

            Text(rootURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(rootURL.path)

            Spacer(minLength: 0)

            // Always visible rather than revealed on hover: this is the only way back to the
            // recent list, and a control nobody can find is not one.
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close the project and go back to the recent list")
            .accessibilityLabel("Close Project")
        }
    }
}

/// One row of the tree, drawn from the flattened item rather than from the hierarchy.
private struct TreeRowView: View {
    @Environment(AppState.self) private var state

    let item: TreeRowItem

    var body: some View {
        switch item {
        case let .suite(suite, isExpanded, childCount):
            suiteRow(suite, isExpanded: isExpanded, childCount: childCount)
        case let .snapshot(snapshot, _):
            snapshotRow(snapshot)
        }
    }

    private func suiteRow(_ suite: SnapshotSuite, isExpanded: Bool, childCount: Int) -> some View {
        HStack(spacing: 6) {
            // The chevron is the mouse's way in; → and ← are the keyboard's. Both end up
            // in the same place, `AppState.expandedSuiteIDs`.
            Button {
                state.toggleExpansion(ofSuiteWithID: suite.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(suite.name)" : "Expand \(suite.name)")

            Image(systemName: isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(.tint)

            Text(suite.name)
                .lineLimit(1)
                .truncationMode(.middle)

            CountPill(count: childCount)

            Spacer(minLength: 0)

            // Under review every snapshot is a change, so the badge would sit on every suite
            // and say nothing; each snapshot names its own change instead.
            if suite.hasGitDiff, !state.isReviewingPullRequest {
                GitDiffBadge()
            }

            // A pull request's suites never have a source file on disk, so the warning would
            // sit on every row and say nothing.
            if suite.isMissingSourceCode, !state.isReviewingPullRequest {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("GimDiff could not find the test source for this suite")
                    .accessibilityLabel("Test source missing")
            }
        }
    }

    private func snapshotRow(_ snapshot: SnapshotItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "function")
                .foregroundStyle(.secondary)

            Text(snapshot.displayName)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if let change = state.pullRequestChange(forSnapshotID: snapshot.id) {
                ChangeKindBadge(kind: change.kind)
            } else if snapshot.hasGitDiff {
                GitDiffBadge()
            }
        }
    }
}

/// How many snapshots a suite holds, after the filters.
private struct CountPill: View {
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
            .accessibilityLabel("\(count) snapshots")
    }
}

/// Marks a row whose file differs from what the repository has committed.
private struct GitDiffBadge: View {
    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .foregroundStyle(.orange)
            .help("Changed since the last commit")
            .accessibilityLabel("Changed since the last commit")
    }
}

#Preview {
    SnapshotTreeView()
        .environment(AppState())
}
