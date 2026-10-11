//
//  CanvasToolbarContent.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The canvas toolbar: how the images are drawn, and how they are put back.
///
/// The comparison picker is a binding over ``AppState/diffMode`` rather than a set of flags.
/// The modes are mutually exclusive by construction that way — a split over a difference
/// mask would show neither — and the mode the canvas switches on stays the one thing that
/// decides what is on screen.
struct CanvasToolbarContent: ToolbarContent {
    let state: AppState
    @Binding var panelBackground: Color?
    @Binding var imageMatte: Color?

    var body: some ToolbarContent {
        // The sidebar's toolbar carries the ways in, and it goes with the sidebar when ⌘0
        // collapses it. Repeating them here only while it is hidden keeps a snapshot one
        // click away without showing every button twice.
        if !state.isSidebarVisible {
            ToolbarItemGroup(placement: .navigation) {
                OpenProjectButton(state: state)
                OpenPullRequestButton(state: state)
                PasteFromClipboardButton(state: state)
            }
        }

        ToolbarItemGroup(placement: .principal) {
            BackdropColorButton(
                title: "Panel Background",
                systemImage: "rectangle.inset.filled",
                help: "Colour behind the image panes",
                color: $panelBackground
            )

            BackdropColorButton(
                title: "Image Matte",
                systemImage: "photo",
                help: "Colour painted behind the image itself, for reading a transparent snapshot",
                color: $imageMatte
            )

            // The picker needs two images to act on, so it is absent rather than disabled
            // while one snapshot is on screen: a control that can never apply is noise in a
            // toolbar this narrow.
            if hasBothImages {
                Picker("Comparison", selection: comparison) {
                    Text("Side by Side").tag(DiffMode.sideBySide)
                    Text("Split View").tag(DiffMode.curtain)
                    Text("Onion Skin").tag(DiffMode.onionSkin)
                    Text("Diff Mask").tag(DiffMode.difference)
                }
                .pickerStyle(.segmented)
                .help("How the two images are compared: next to each other, under a draggable split, faded one over the other, or with every changed pixel painted magenta")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.refreshPreviewImages()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.canvas.preview == nil)
            .help("Read the images on screen off disk again (⌘R)")

            Button {
                state.canvas.close()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .disabled(state.canvas.preview == nil)
            .help("Clear the canvas (⌘L)")
        }
    }

    private var hasBothImages: Bool {
        state.canvas.preview?.isComparison == true
    }

    private var comparison: Binding<DiffMode> {
        Binding(
            get: { state.canvas.diffMode },
            set: { state.canvas.diffMode = $0 }
        )
    }
}
