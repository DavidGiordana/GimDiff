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

    /// Whether the row is one of the images the last test run attached, which are copies
    /// with no test file behind them and nothing in the project to delete.
    private var isTestRunAttachment: Bool {
        item.suiteID == TestRunModel.attachmentsSuiteID
    }

    @ViewBuilder
    private func suiteMenu(_ suite: SnapshotSuite) -> some View {
        Button {
            state.copyToClipboard(suite.name)
        } label: {
            Label("Copy Name", systemImage: "paperclip")
        }

        // A pull request under review is a set of downloaded copies: there is no test file
        // on disk to open, and nothing deleting a copy would change.
        if !state.isReviewingPullRequest, !isTestRunAttachment {
            Button {
                state.openTestSource(for: suite)
            } label: {
                Label("Open Test File in Xcode", systemImage: "ellipsis.curlybraces")
            }
        }

        if !state.isReviewingPullRequest, !isTestRunAttachment {
            Button {
                state.openSnapshotsFolder(for: suite)
            } label: {
                Label("Open Snapshots Folder", systemImage: "folder")
            }

            Divider()

            let discardable = state.discardableSnapshots(in: suite)
            if !discardable.isEmpty {
                Button(role: .destructive) {
                    state.discardGitChanges(of: discardable)
                } label: {
                    Label(
                        discardable.count == 1
                            ? "Discard Changes to 1 Snapshot"
                            : "Discard Changes to \(discardable.count) Snapshots",
                        systemImage: "arrow.uturn.backward"
                    )
                }
            }

            Button(role: .destructive) {
                state.delete(suite: suite)
            } label: {
                Label("Move Snapshots Folder to Trash", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func snapshotMenu(_ snapshot: SnapshotItem, parentSuiteID: String) -> some View {
        Button {
            state.copyToClipboard(snapshot.displayName)
        } label: {
            Label("Copy Name", systemImage: "paperclip")
        }

        Button {
            state.showSnapshot(snapshot, withGitDiff: true)
        } label: {
            Label(state.compareActionTitle(for: snapshot), systemImage: "eye")
        }

        Button {
            state.showSnapshot(snapshot, withGitDiff: false)
        } label: {
            Label(state.showAloneActionTitle, systemImage: "rectangle.portrait.split.2x1.slash")
        }

        // Everything below acts on a file on disk. Under pull request review the files are
        // scratch copies deleted when the review ends, so none of it is offered.
        if !state.isReviewingPullRequest {
            Divider()

            Button {
                state.openInPreviewApp(snapshot.fileURL)
            } label: {
                Label("Open in Preview", systemImage: "doc")
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
                    Label("Open Test File in Xcode", systemImage: "ellipsis.curlybraces")
                }
            }

            if !isTestRunAttachment {
                Divider()

                if state.canDiscardGitChanges(of: snapshot) {
                    Button(role: .destructive) {
                        state.discardGitChanges(of: [snapshot])
                    } label: {
                        Label("Discard Changes", systemImage: "arrow.uturn.backward")
                    }
                }

                Button(role: .destructive) {
                    state.delete(snapshot: snapshot, in: parentSuiteID)
                } label: {
                    Label("Move Snapshot to Trash", systemImage: "trash")
                }
            }
        }
    }
}
