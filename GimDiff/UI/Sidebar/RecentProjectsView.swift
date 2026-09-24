//
//  RecentProjectsView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The sidebar before a project is open: somewhere to get back to yesterday's work.
struct RecentProjectsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.recentProjects.isEmpty {
            ContentUnavailableView {
                Label("No Recent Projects", systemImage: "folder.badge.plus")
            } description: {
                Text("Open a project folder or drag a folder here")
            } actions: {
                Button("Open Project…") {
                    state.promptForProject()
                }
            }
        } else {
            VStack(spacing: 0) {
                List {
                    Section("Recent Projects") {
                        ForEach(state.recentProjects, id: \.path) { url in
                            RecentProjectRow(url: url)
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button {
                        state.clearRecentProjects()
                    } label: {
                        Label("Clear all recent folders", systemImage: "trash")
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Spacer(minLength: 8)

                    Button {
                        state.promptForProject()
                    } label: {
                        Label("Open Project", systemImage: "folder.badge.plus")
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }
}

/// One remembered folder, with a hover-revealed way to forget it.
private struct RecentProjectRow: View {
    @Environment(AppState.self) private var state

    let url: URL

    @State private var isHovering = false

    var body: some View {
        Button {
            state.openProject(at: url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Text(abbreviatedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)

                // Shown on hover rather than always: a delete button beside every row
                // reads as the primary action, and opening the project is.
                if isHovering {
                    Button {
                        state.removeRecentProject(url)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove “\(url.lastPathComponent)” from the recent list")
                    .accessibilityLabel("Remove \(url.lastPathComponent) from the recent list")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(url.path)
        .contextMenu {
            Button {
                state.revealInFinder(url)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button(role: .destructive) {
                state.removeRecentProject(url)
            } label: {
                Label("Remove from Recents", systemImage: "trash")
            }
        }
    }

    /// The folder's path with the home directory folded back into `~`.
    private var abbreviatedPath: String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

#Preview {
    RecentProjectsView()
        .environment(AppState())
}
