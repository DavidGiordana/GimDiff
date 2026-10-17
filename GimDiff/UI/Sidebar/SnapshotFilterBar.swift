//
//  SnapshotFilterBar.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Where the sidebar's keyboard focus sits.
///
/// Shared between the filter field and the tree because focus moves between them under the
/// keyboard's control: ↓ and ⏎ hand it down into the rows, ⎋ hands it back.
enum SidebarFocus: Hashable {
    case filter
    case tree
}

/// Search field and filter chips above the snapshot tree.
struct SnapshotFilterBar: View {
    @Environment(AppState.self) private var state

    @FocusState.Binding var focus: SidebarFocus?

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Filter snapshots", text: $state.filterText)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .filter)
                    // ⏎ and ↓ both mean "I am done typing, take me to the results".
                    .onSubmit(handOffToTree)
                    .onKeyPress(.downArrow) {
                        handOffToTree()
                        return .handled
                    }
                    // ⎋ abandons the search rather than only unfocusing it: a field left
                    // holding a query the user has walked away from hides the whole tree.
                    //
                    // Read as a key press rather than through `onExitCommand`, which a
                    // focused `TextField` never forwards: AppKit turns ⎋ into the field's
                    // own `cancelOperation(_:)` and stops there.
                    .onKeyPress(.escape) {
                        state.clearFilters()
                        handOffToTree()
                        return .handled
                    }

                if !state.filterText.isEmpty {
                    Button {
                        state.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the filter")
                    .accessibilityLabel("Clear the filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))

            // Each chip appears only when the project has something it would keep, and the
            // row goes with them: a filter that can only empty the tree is noise.
            if state.canFilterByGitChanges || state.canFilterByWarnings {
                HStack(spacing: 6) {
                    Text("Filters")
                        .foregroundStyle(.secondary)

                    if state.canFilterByGitChanges {
                        Toggle(isOn: $state.showGitModifiedOnly) {
                            Label("Modified", systemImage: "arrow.triangle.branch")
                        }
                        .help("Show only snapshots that differ from the committed version")
                    }

                    if state.canFilterByWarnings {
                        Toggle(isOn: $state.showWarningsOnly) {
                            Label("Warnings", systemImage: "exclamationmark.triangle")
                        }
                        .help("Show only suites whose test source could not be found")
                    }

                    Spacer()

                    if state.projectHasGitChanges {
                        Button("Discard All…") {
                            state.requestDiscardAllGitChanges()
                        }
                        .help("Put every snapshot of the project back to the committed version")
                        .accessibilityIdentifier("DiscardAllGitChanges")
                    }
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .font(.caption)
            }
        }
    }

    /// Moves focus into the rows and puts the selection on the first one the filter left.
    private func handOffToTree() {
        state.selectFirstVisibleRow()
        focus = .tree
    }
}
