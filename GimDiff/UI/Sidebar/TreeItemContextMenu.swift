//
//  TreeItemContextMenu.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Right-click menu for one row of the snapshot tree.
///
/// Every item here also exists as a key, and both go through ``AppState`` rather than
/// reaching for `NSWorkspace`: the menu and the keyboard must not be able to disagree about
/// what "reveal in Finder" does.
struct TreeItemContextMenu: View {
    @Environment(AppState.self) private var state

    let item: TreeRowItem

    var body: some View {
        switch item {
        case let .suite(suite, _, _):
            suiteMenu(suite)
        case let .snapshot(snapshot, parentSuiteID):
            snapshotMenu(snapshot, parentSuiteID: parentSuiteID)
        }
    }

    @ViewBuilder
    private func suiteMenu(_ suite: SnapshotSuite) -> some View {
        Button {
            state.copyToClipboard(suite.name)
        } label: {
            Label("Copy TestCase name", systemImage: "paperclip")
        }

        Button {
            state.openTestSource(for: suite)
        } label: {
            Label("Open Test file in Xcode", systemImage: "ellipsis.curlybraces")
        }

        Button {
            state.openSnapshotsFolder(for: suite)
        } label: {
            Label("Open Snapshots Folder in Finder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            state.delete(suite: suite)
        } label: {
            Label("Delete Snapshots Folder", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func snapshotMenu(_ snapshot: SnapshotItem, parentSuiteID: String) -> some View {
        Button {
            state.copyToClipboard(snapshot.displayName)
        } label: {
            Label("Copy Snapshot name", systemImage: "paperclip")
        }

        Button {
            state.showSnapshot(snapshot, withGitDiff: true)
        } label: {
            Label("Show Snapshot (with Git diff)", systemImage: "eye")
        }

        Button {
            state.showSnapshot(snapshot, withGitDiff: false)
        } label: {
            Label(
                "Show Snapshot without Git diff",
                systemImage: "rectangle.portrait.split.2x1.slash"
            )
        }

        Divider()

        Button {
            state.openInPreviewApp(snapshot.fileURL)
        } label: {
            Label("Open in Preview.app", systemImage: "doc")
        }

        Button {
            state.revealInFinder(snapshot.fileURL)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        if let suite = state.suite(for: item) {
            Button {
                state.openTestSource(for: suite)
            } label: {
                Label("Open Test file in Xcode", systemImage: "ellipsis.curlybraces")
            }
        }

        Divider()

        Button(role: .destructive) {
            state.delete(snapshot: snapshot, in: parentSuiteID)
        } label: {
            Label("Delete Snapshot", systemImage: "trash")
        }
    }
}
