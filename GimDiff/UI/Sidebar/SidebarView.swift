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
            // The tree, not the recent list, while a first scan runs: it names the folder
            // being read, so the click that opened it visibly did something.
            if state.currentProject == nil, !state.isLoading {
                RecentProjectsView()
            } else {
                SnapshotTreeView()
            }
        }
        .navigationTitle("Snapshots")
        .toolbar {
            // A collapsed sidebar's toolbar items stay in the window's toolbar, where the
            // canvas toolbar now offers the same buttons. Dropping them here while the
            // sidebar is hidden is what keeps each one on screen once.
            if state.isSidebarVisible {
                ToolbarItem(placement: .primaryAction) {
                    OpenPullRequestButton(state: state)
                }

                ToolbarItem(placement: .primaryAction) {
                    PasteFromClipboardButton(state: state)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Rescan the project for snapshots (⇧⌘R)")
                .disabled(state.currentProject == nil)
            }
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
