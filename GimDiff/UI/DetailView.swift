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
            preview: state.preview,
            panelBackground: panelBackground,
            imageMatte: imageMatte
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
        .onChange(of: state.diffMode) { state.updateDiffReport() }
        .onChange(of: state.preview) { state.updateDiffReport() }
    }
}

#Preview {
    DetailView()
        .environment(AppState())
}
