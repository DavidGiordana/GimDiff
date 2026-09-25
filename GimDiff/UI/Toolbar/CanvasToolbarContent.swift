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
/// The two comparison toggles write to ``AppState/diffMode`` rather than carrying flags of
/// their own. They are mutually exclusive by construction that way — a curtain over a
/// difference mask would show neither — and the mode the canvas switches on stays the one
/// thing that decides what is on screen.
struct CanvasToolbarContent: ToolbarContent {
    let state: AppState
    @Binding var panelBackground: Color?
    @Binding var imageMatte: Color?

    var body: some ToolbarContent {
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

            // Both toggles need two images to act on, so they are absent rather than
            // disabled while one snapshot is on screen: a control that can never apply is
            // noise in a toolbar this narrow.
            if hasBothImages {
                Toggle(isOn: isCurtain) {
                    Label("Compare", systemImage: DiffMode.curtain.symbolName)
                }
                .toggleStyle(.button)
                .help("Draw both images in one frame under a draggable split")

                Toggle(isOn: isDiffMask) {
                    Label("Diff Mask", systemImage: DiffMode.difference.symbolName)
                }
                .toggleStyle(.button)
                .help("Paint every changed pixel in neon magenta")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.refreshPreviewImages()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(state.preview == nil)
            .help("Read the images on screen off disk again (⌘R)")

            Button {
                state.closePreview()
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .disabled(state.preview == nil)
            .help("Clear the canvas (⌘L)")
        }
    }

    private var hasBothImages: Bool {
        state.preview?.isComparison == true
    }

    private var isCurtain: Binding<Bool> {
        mode(.curtain)
    }

    private var isDiffMask: Binding<Bool> {
        mode(.difference)
    }

    /// A toggle over one value of ``DiffMode``, falling back to side by side when switched off.
    private func mode(_ wanted: DiffMode) -> Binding<Bool> {
        Binding(
            get: { state.diffMode == wanted },
            set: { state.diffMode = $0 ? wanted : .sideBySide }
        )
    }
}
