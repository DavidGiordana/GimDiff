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
            // The space above the divider belongs to the block, not to whichever control
            // happens to be last: the filter bar is hidden while a run is read, and the
            // divider would otherwise close up under the run picker.
            VStack(spacing: 0) {
                if let session = state.pullRequestReview.session {
                    PullRequestHeader(session: session, close: state.closePullRequestReview)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                } else if let rootURL = state.currentProject?.rootURL ?? state.loadingProjectURL {
                    ProjectHeader(rootURL: rootURL, project: state.currentProject, close: state.closeProject)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }

                if state.showsSidebarSourcePicker {
                    SidebarSourcePicker()
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }

                if state.sidebarSource == .testRun, state.canShowTestRun {
                    TestRunHistoryPicker()
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }

                if state.currentProject != nil, !state.isShowingTestRunPlaceholder {
                    SnapshotFilterBar(focus: $focus)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 10)

            Divider()

            if state.isLoading {
                ProgressView("Scanning…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = state.pullRequestReview.session, session.suites.isEmpty {
                SidebarEmptyStateView.noSnapshotChanges(
                    prNumber: session.prNumber,
                    close: state.closePullRequestReview
                )
            } else if state.isShowingTestRunPlaceholder {
                testRunPlaceholder
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
        // Switching views swaps every row; the keyboard stays with the tree.
        .onChange(of: state.sidebarSource) { claimTreeFocus() }
        // A freshly scanned project replaces every row, so focus is claimed again rather
        // than left on whatever the last project had. The first scan lands in the same
        // update that swaps the spinner for the `List`, so the claim has to wait for the
        // focus system to see the new view.
        .onChange(of: state.currentProject?.rootURL) { claimTreeFocus() }
    }

    /// What stands in for the rows while the run is read, when it could not be, or when it
    /// failed on nothing.
    @ViewBuilder
    private var testRunPlaceholder: some View {
        if state.testRuns.isReading, state.testRuns.results == nil {
            ProgressView("Reading test results…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.testRuns.error {
            SidebarEmptyStateView.testRunUnavailable(message: error, showProject: state.showProjectStatus)
        } else {
            SidebarEmptyStateView.noTestFailures(showProject: state.showProjectStatus)
        }
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
    /// user left it in.
    private func claimFocusIfIdle() {
        guard controlActiveState != .inactive, focus == nil else { return }
        claimTreeFocus(unlessFocused: true)
    }

    /// Moves focus onto the rows, retrying until the focus system takes it.
    ///
    /// Deferred, because an assignment inside the update that made the window key or put
    /// the `List` on screen is dropped. One turn of the main actor is not always enough
    /// either: when the first scan lands, the `List` can still be unseen by the focus system
    /// a turn later, and the app launches with rows the arrow keys cannot move. So the claim
    /// is repeated for a few frames, as ``claimFilterFocus()`` does, and stops as soon as
    /// focus is anywhere at all, so a click into the search box in the meantime stands.
    private func claimTreeFocus(unlessFocused: Bool = false) {
        Task { @MainActor in
            if unlessFocused, focus != nil { return }
            for _ in 0..<20 {
                focus = .tree
                try? await Task.sleep(for: .milliseconds(25))
                guard focus == nil else { return }
            }
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
/// Names the open project, says how much it holds, and offers the way out of it.
private struct ProjectHeader: View {
    @Environment(AppState.self) private var state

    let rootURL: URL
    /// Absent while the first scan is still reading `rootURL`, when there is nothing to count.
    let project: ProjectBundle?
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(rootURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rootURL.path)

                if let project {
                    // Whole-project totals: the pills on each suite row already count what the
                    // filters leave, so this line is what says how big the project really is.
                    Text(summary(of: project))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("ProjectSummary")
                }
            }

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

    private func summary(of project: ProjectBundle) -> String {
        let snapshots = project.snapshotsCount
        let totals = String(localized: "\(project.suites.count) test cases · \(snapshots) snapshots")
        guard state.sidebarSource == .testRun, let run = state.testRuns.results else { return totals }

        // Under the run, the line says which run and how much of the project it failed on.
        let failed = String(localized: "\(run.failedSnapshotsCount) of \(snapshots) failed")
        guard let startedAt = run.startedAt else { return failed }
        return String(localized: "\(failed) · run \(startedAt.formatted(.relative(presentation: .named)))")
    }
}

/// Switches the tree between the project as it stands and what a test run failed on.
private struct SidebarSourcePicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        FullWidthSegmentedPicker(
            options: [
                PickerOption(title: String(localized: "Project"), value: SidebarSource.project),
                PickerOption(title: String(localized: "Test Run"), value: SidebarSource.testRun),
            ],
            selection: source,
            help: String(localized: "Show the project's snapshots, or the ones a test run failed on"),
            accessibilityIdentifier: "SidebarSource"
        )
    }

    /// Goes through ``AppState/showTestRun()`` rather than assigning: switching also reads
    /// the run the first time, and moves the selection to something the new view lists.
    private var source: Binding<SidebarSource> {
        Binding(
            get: { state.sidebarSource },
            set: { $0 == .testRun ? state.showTestRun() : state.showProjectStatus() }
        )
    }
}

/// Picks which of the project's test runs the tree lists, newest first.
private struct TestRunHistoryPicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 6) {
            Text("Run")
                .font(.caption)
                .foregroundStyle(.secondary)

            FullWidthPopUpPicker(
                options: state.testRuns.bundles.map { bundle in
                    PickerOption(
                        title: TestRunBundleLabel.title(of: bundle, among: state.testRuns.bundles),
                        value: bundle.url
                    )
                },
                selection: bundle,
                help: String(localized: "Choose which of this project's test runs to show"),
                accessibilityLabel: String(localized: "Run"),
                accessibilityIdentifier: "TestRunHistory"
            )

            Button("Accept All…") {
                state.requestAcceptAllTestRunFailures()
            }
            .controlSize(.small)
            .disabled(state.acceptableTestRunFailuresCount == 0)
            .help("Record what the run rendered as the baseline of every snapshot it failed on")
            .accessibilityIdentifier("AcceptAllTestRunFailures")
        }
    }

    /// Goes through ``AppState/showTestRun(from:)``, which reads the run picked and decides
    /// whether it is pinned or the newest is followed.
    private var bundle: Binding<URL?> {
        Binding(
            get: { state.testRuns.selectedBundle?.url },
            set: { url in url.map(state.showTestRun(from:)) }
        )
    }
}

/// One row of the tree, drawn from the flattened item rather than from the hierarchy.
private struct TreeRowView: View {
    @Environment(AppState.self) private var state

    /// How far the chevron's hit area reaches past the glyph on every side. Wide enough to
    /// catch the gap to the folder icon, short of taking that icon's clicks.
    private static let chevronHitSlop: CGFloat = 6

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
                    // A plain button is hit only where its label is, and a caption-sized
                    // glyph is a target the pointer has to be aimed at. The padding grows
                    // the hit area; the negative padding below gives the space back, so
                    // the row lays out exactly as it did.
                    .padding(.horizontal, Self.chevronHitSlop)
                    .padding(.vertical, Self.chevronHitSlop)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -Self.chevronHitSlop)
            .padding(.vertical, -Self.chevronHitSlop)
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

            let failing = state.sidebarSource == .testRun ? state.failingSnapshotsCount(in: suite) : 0
            if failing > 0, suite.id != TestRunModel.attachmentsSuiteID {
                TestFailureBadge(count: failing)
            }

            // A pull request's suites never have a source file on disk, so the warning would
            // sit on every row and say nothing.
            if state.hasSourceWarning(suite), !state.isReviewingPullRequest {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("GimDiff could not find the test source for this suite")
                    .accessibilityLabel("Test source missing")
            }
        }
    }

    private func snapshotRow(_ snapshot: SnapshotItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: TestRunModel.isAttachment(snapshotID: snapshot.id) ? "paperclip" : "function")
                .foregroundStyle(.secondary)

            Text(snapshot.displayName)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if let change = state.pullRequestReview.change(forSnapshotID: snapshot.id) {
                ChangeKindBadge(kind: change.kind)
            } else {
                if state.sidebarSource == .testRun, state.testRuns.results?.isFailing(snapshotID: snapshot.id) == true {
                    TestFailureBadge()
                }
                if snapshot.hasGitDiff {
                    GitDiffBadge()
                }
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

/// Marks a snapshot the test run failed on, or a suite holding some.
private struct TestFailureBadge: View {
    /// How many failed, on a suite row; `nil` on the snapshot itself.
    var count: Int?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "xmark.octagon.fill")
            if let count {
                Text(count.formatted())
                    .font(.caption2.monospacedDigit())
            }
        }
        .foregroundStyle(.red)
        .help(explanation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(explanation)
    }

    private var explanation: String {
        guard let count else { return String(localized: "Failed in the test run") }
        return String(localized: "\(count) snapshots failed in the test run")
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
