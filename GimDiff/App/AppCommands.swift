//
//  AppCommands.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// GimDiff's menu bar, and with it every shortcut that has to work whatever is focused.
struct AppCommands: Commands {
    let state: AppState
    let delegate: AppDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = registerWindowOpener()

        CommandGroup(replacing: .appInfo) {
            Button("About GimDiff") {
                delegate.showAboutPanel()
            }
        }

        // GimDiff shows one window, so there is nothing for File ▸ New to make.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .newItem) {
            Button("Open Project…") {
                state.promptForProject()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Pull Request…") {
                state.presentPullRequestSheet()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            // ⌘R refreshes the canvas rather than the project. A snapshot is looked at far
            // more often than a folder is rescanned, and rereading two images is the cheap
            // half of the pair, so the bare shortcut goes to the one used every minute.
            Button("Refresh Images") {
                state.refreshPreviewImages()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Reload Project") {
                state.reload()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            // Deliberately unshortcut'd: every spelling near ⌘W is already the window's, and
            // closing the project is not closing the window. The sidebar header carries the
            // button this mirrors.
            if state.isReviewingPullRequest {
                Button("Close Pull Request Review") {
                    state.closePullRequestReview()
                }
            } else {
                Button("Close Project") {
                    state.closeProject()
                }
            }

            Button("Clear Recent Projects") {
                state.clearRecentProjects()
            }
            .disabled(state.recentProjects.isEmpty)
        }

        // Replaced rather than added to: an extra item bound to ⌘V would shadow the filter
        // field's paste, because AppKit matches key equivalents against the menu bar before
        // the first responder sees the event. `pasteCommand()` offers the key to the field
        // first and ingests the clipboard only when nothing took it.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { state.performEditAction(.cut) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { state.performEditAction(.copy) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste from Clipboard") { state.pasteCommand() }
                .keyboardShortcut("v", modifiers: .command)
            Button("Select All") { state.performEditAction(.selectAll) }
                .keyboardShortcut("a", modifiers: .command)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Expand Sidebar") {
                state.expandSidebar()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Collapse Sidebar") {
                state.collapseSidebar()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Toggle("Show Only Modified Snapshots", isOn: binding(\.showGitModifiedOnly))
            Toggle("Show Only Suites with Warnings", isOn: binding(\.showWarningsOnly))

            Divider()

            // The toolbar's Compare and Diff Mask toggles, spelled out as the one choice they
            // are: both write ``AppState/diffMode``, so a picker over it is the same control.
            Picker("Comparison", selection: binding(\.diffMode)) {
                Text("Side by Side").tag(DiffMode.sideBySide)
                Text("Compare").tag(DiffMode.curtain)
                Text("Diff Mask").tag(DiffMode.difference)
            }
            .pickerStyle(.inline)
            .disabled(state.preview?.isComparison != true)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find") {
                state.focusFilter()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Clear Filters") {
                state.clearFilters()
            }
            .disabled(!state.isFiltering)
        }

        // The ⌘-modified half of the tree's keyboard. AppKit offers a ⌘ shortcut to the
        // menu bar and never to the focused view's `keyDown(with:)`, so these cannot sit
        // beside the arrow keys in the sidebar's `onKeyPress` — and being menu items makes
        // them discoverable, which a bare key is not.
        //
        // The tree's bare keys — Space for the preview, ↩ for the test file — have items here
        // too, but without a shortcut: a menu item bound to a bare key is matched before the
        // first responder sees it, so it would fire while the user typed in the search box.
        CommandMenu("Snapshot") {
            Button(state.isShowingSelectedSnapshot ? "Hide Snapshot" : "Show Snapshot") {
                state.togglePreview()
            }
            .disabled(state.selectedSnapshot == nil)

            Button(
                state.isReviewingPullRequest ? "Compare with Base Branch" : "Show Snapshot with Git Diff"
            ) {
                state.showSelectedSnapshot(withGitDiff: true)
            }
            .disabled(state.selectedSnapshot == nil)

            Button(
                state.isReviewingPullRequest
                    ? "Show Pull Request Version Only"
                    : "Show Snapshot without Git Diff"
            ) {
                state.showSelectedSnapshot(withGitDiff: false)
            }
            .disabled(state.selectedSnapshot == nil)

            Divider()

            Button("Copy Name") {
                state.copySelectedRowName()
            }
            .disabled(state.selectedRowName == nil)

            Divider()

            Button("Open Test File in Xcode") {
                state.openTestSource()
            }
            .disabled(state.isReviewingPullRequest || state.selectedSuite?.sourceCodeURL == nil)

            Button("Open in Preview") {
                state.openSelectedSnapshotInPreviewApp()
            }
            .disabled(state.isReviewingPullRequest || state.selectedSnapshot == nil)

            Button("Reveal in Finder") {
                state.revealSelectionInFinder()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state.isReviewingPullRequest || state.selectedRow == nil)

            Button("Open Snapshots Folder") {
                state.openSnapshotsFolderForSelection()
            }
            .disabled(state.isReviewingPullRequest || state.selectedSuite == nil)

            Divider()

            Button("Accept Candidate / Overwrite Baseline") {
                state.promoteCandidateToBaseline()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!state.canPromoteCandidate)

            Button("Revert to Baseline") {
                state.revertCandidateToBaseline()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(!state.canRevertToBaseline)

            Divider()

            Button("Clear Canvas") {
                state.closePreview()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(state.preview == nil)

            Divider()

            Button(state.selectedSnapshot == nil ? "Move Snapshots Folder to Trash" : "Move Snapshot to Trash") {
                state.deleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        // Replaced so the item opens GimDiff's own help sheet instead of the system's
        // "Help isn't available" alert. AppKit still adds its menu search field above it.
        CommandGroup(replacing: .help) {
            Button("GimDiff Help") {
                state.presentHelp()
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    /// A binding onto one of the state's properties, which `Commands` cannot take with `$`.
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppState, Value>) -> Binding<Value> {
        let state = state
        return Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0 }
        )
    }

    /// Hands `openWindow` to the app delegate, which AppKit calls outside any view.
    ///
    /// Done from the menu bar because the point is a launch with no window: when GimDiff is
    /// started to open a folder, SwiftUI treats it as a document launch and presents no
    /// scene, so no view exists to read the environment from. The menu bar is built either
    /// way. A `Commands` of its own would not do: one that contributes no items is never
    /// evaluated.
    private func registerWindowOpener() {
        let openWindow = openWindow
        delegate.openMainWindow = { openWindow(id: GimDiffApp.mainWindowID) }
    }
}
