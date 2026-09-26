//
//  OpenSourceButtons.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Toolbar button that opens a project folder.
struct OpenProjectButton: View {
    let state: AppState

    var body: some View {
        Button {
            state.promptForProject()
        } label: {
            Label("Open Project", systemImage: "folder.badge.plus")
        }
        .help("Open a project folder (⌘O)")
    }
}

/// Toolbar button that presents the Open PR sheet.
struct OpenPullRequestButton: View {
    let state: AppState

    var body: some View {
        Button {
            state.presentPullRequestSheet()
        } label: {
            Label("Open PR", systemImage: "arrow.triangle.pull")
        }
        // Titled as well as iconed: no SF Symbol says "pull request" on its own.
        .labelStyle(.titleAndIcon)
        .help("Review GitHub PR - ⌘⇧O")
    }
}

/// Toolbar button that opens whatever the clipboard names.
struct PasteFromClipboardButton: View {
    let state: AppState

    var body: some View {
        Button {
            // Straight to the clipboard, not through `pasteCommand()`: clicking a toolbar
            // button leaves the filter field first responder, and forwarding would drop the
            // log into the search box instead of opening it.
            state.pasteFromClipboard()
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        // Titled like Open PR, and styled the same so neither outranks the other: the
        // clipboard glyph alone does not say that a failure log, files, or a pull request
        // link will be opened.
        .labelStyle(.titleAndIcon)
        .help("Open the snapshots named on the clipboard: a failure log, copied files, or a pull request link (⌘V)")
    }
}
