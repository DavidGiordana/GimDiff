//
//  SidebarView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The sidebar column: the snapshot tree, or the recent project list before one is open.
struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.currentProject == nil {
                RecentProjectsView()
            } else {
                SnapshotTreeView()
            }
        }
        .navigationTitle("Snapshots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.presentPullRequestSheet()
                } label: {
                    Label("Open PR", systemImage: "arrow.triangle.pull")
                }
                // Titled as well as iconed: no SF Symbol says "pull request" on its own.
                .labelStyle(.titleAndIcon)
                .help("Review GitHub PR - ⌘⇧O")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Straight to the clipboard, not through `pasteCommand()`: clicking a
                    // toolbar button leaves the filter field first responder, and forwarding
                    // would drop the log into the search box instead of opening it.
                    state.pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                // Titled like Open PR, and styled the same so neither outranks the other:
                // the clipboard glyph alone does not say that a failure log, files, or a
                // pull request link will be opened.
                .labelStyle(.titleAndIcon)
                .help("Open the snapshots named on the clipboard: a failure log, copied files, or a pull request link (⌘V)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Rescan the project for snapshots (⌘R)")
                .disabled(state.currentProject == nil)
            }
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
