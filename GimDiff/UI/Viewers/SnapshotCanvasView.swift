//
//  SnapshotCanvasView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Renders whatever the preview pane is holding, or an empty state when it is closed.
struct SnapshotCanvasView: View {
    @Environment(AppState.self) private var state

    let preview: SnapshotPreview?

    var body: some View {
        switch preview {
        case let .comparison(pair, _, title):
            HStack(spacing: 1) {
                SnapshotImageView(url: pair.reference.url, caption: "Reference")
                SnapshotImageView(url: pair.failure.url, caption: "Failure")
            }
            .background(.quaternary)
            .navigationTitle(title)
            .navigationSubtitle(state.diffMode.title)

        case let .single(snapshot):
            SnapshotImageView(url: snapshot.fileURL, caption: caption(for: snapshot))
                .background(.quaternary)
                .navigationTitle(snapshot.displayName)

        case nil:
            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "rectangle.split.2x1",
                description: Text("Choose a snapshot from the sidebar, or press Space to preview it.")
            )
        }
    }

    /// Says why only one image is on screen, since a changed snapshot normally shows two.
    private func caption(for snapshot: SnapshotItem) -> String {
        switch snapshot.gitStatus {
        case .untracked: "Untracked — nothing committed to compare against"
        case .deleted: "Deleted from the working tree"
        case .modified, .unmodified: "Recorded"
        }
    }
}

/// A single snapshot image with its role as a caption.
private struct SnapshotImageView: View {
    let url: URL
    let caption: String

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    ContentUnavailableView(
                        "Unreadable Image",
                        systemImage: "exclamationmark.triangle",
                        description: Text(url.lastPathComponent)
                    )
                case .empty:
                    ProgressView()
                @unknown default:
                    ProgressView()
                }
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.background)
    }
}

#Preview {
    SnapshotCanvasView(preview: nil)
        .environment(AppState())
}
