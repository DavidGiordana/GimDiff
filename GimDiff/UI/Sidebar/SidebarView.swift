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
