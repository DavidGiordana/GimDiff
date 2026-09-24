//
//  DetailView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The detail column: the preview pane, and the toolbar that acts on it.
struct DetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        SnapshotCanvasView(preview: state.preview)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Diff Mode", selection: $state.diffMode) {
                        ForEach(DiffMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .disabled(state.preview?.isComparison != true)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        state.closePreview()
                    } label: {
                        Label("Close Preview", systemImage: "xmark")
                    }
                    .help("Close the preview pane (Space)")
                    .disabled(state.preview == nil)
                }
            }
    }
}

#Preview {
    DetailView()
        .environment(AppState())
}
