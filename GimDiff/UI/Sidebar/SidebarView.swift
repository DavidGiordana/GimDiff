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
                    // The pull glyph is a single thin stroke, which at toolbar size reads as
                    // a stray mark beside the filled icons around it. Weight, scale, and the
                    // accent colour give it the presence the other buttons get from their shape.
                    Label {
                        Text("Open PR")
                    } icon: {
                        Image(systemName: "arrow.triangle.pull")
                            .fontWeight(.bold)
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                    }
                }
                // Titled as well as iconed: no SF Symbol says "pull request" on its own.
                .labelStyle(.titleAndIcon)
                .help("Review GitHub PR - ⌘⇧O")
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
