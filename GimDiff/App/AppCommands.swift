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

        // GimDiff shows one window, so there is nothing for File ▸ New to make.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .newItem) {
            Button("Open Project…") {
                state.promptForProject()
            }
            .keyboardShortcut("o", modifiers: .command)

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
            Button("Close Project") {
                state.closeProject()
            }
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
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find") {
                state.focusFilter()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // The ⌘-modified half of the tree's keyboard. AppKit offers a ⌘ shortcut to the
        // menu bar and never to the focused view's `keyDown(with:)`, so these cannot sit
        // beside the arrow keys in the sidebar's `onKeyPress` — and being menu items makes
        // them discoverable, which a bare key is not.
        CommandMenu("Snapshot") {
            Button("Reveal in Finder") {
                state.revealSelectionInFinder()
            }
            .keyboardShortcut(.return, modifiers: .command)

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

            Button("Move Snapshot to Trash") {
                state.deleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
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
