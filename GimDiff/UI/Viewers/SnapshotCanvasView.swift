//
//  SnapshotCanvasView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Renders the selected comparison, or an empty state when nothing is selected.
struct SnapshotCanvasView: View {
    @Environment(AppState.self) private var state

    let pair: SnapshotPair?

    var body: some View {
        if let pair {
            HStack(spacing: 1) {
                SnapshotImageView(snapshot: pair.reference)
                SnapshotImageView(snapshot: pair.failure)
            }
            .background(.quaternary)
            .navigationTitle(pair.name)
            .navigationSubtitle(state.diffMode.title)
        } else {
            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "rectangle.split.2x1",
                description: Text("Choose a snapshot from the sidebar.")
            )
        }
    }
}

/// A single snapshot image with its role as a caption.
private struct SnapshotImageView: View {
    let snapshot: SnapshotReference

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: snapshot.url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
            }

            Text(snapshot.kind.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.background)
    }
}

#Preview {
    SnapshotCanvasView(pair: nil)
        .environment(AppState())
}
