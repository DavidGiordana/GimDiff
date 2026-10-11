//
//  DetailView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The detail column: the canvas, and the toolbar that acts on it.
///
/// The two canvas colours live here rather than in ``AppState``. Nothing outside this column
/// reads them, they describe how the window is being looked at rather than what it holds,
/// and keeping them out keeps `AppState` free of SwiftUI.
struct DetailView: View {
    @Environment(AppState.self) private var state

    @State private var panelBackground: Color?
    @State private var imageMatte: Color?

    var body: some View {
        SnapshotCanvasView(
            preview: state.canvas.preview,
            panelBackground: panelBackground,
            imageMatte: imageMatte
        )
        // Scene-wide rather than tied to focus: the View menu sets these whether the
        // sidebar or the canvas has the keyboard.
        .focusedSceneValue(
            \.canvasBackdrop,
            CanvasBackdrop(panelBackground: $panelBackground, imageMatte: $imageMatte)
        )
        .toolbar {
            CanvasToolbarContent(
                state: state,
                panelBackground: $panelBackground,
                imageMatte: $imageMatte
            )
        }
        // The mask is measured when it is asked for and not before: the comparison decodes
        // both images in full, which is not something to spend on every selection.
        .onChange(of: state.canvas.diffMode) { state.canvas.updateDiffReport() }
        .onChange(of: state.canvas.preview) { state.canvas.updateDiffReport() }
    }
}

/// The canvas colours, handed to the menu bar, which has no other way to reach view state.
struct CanvasBackdrop {
    let panelBackground: Binding<Color?>
    let imageMatte: Binding<Color?>
}

private struct CanvasBackdropKey: FocusedValueKey {
    typealias Value = CanvasBackdrop
}

extension FocusedValues {
    var canvasBackdrop: CanvasBackdrop? {
        get { self[CanvasBackdropKey.self] }
        set { self[CanvasBackdropKey.self] = newValue }
    }
}

#Preview {
    DetailView()
        .environment(AppState())
}
