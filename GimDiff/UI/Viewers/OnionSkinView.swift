//
//  OnionSkinView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The onion skin: the candidate drawn over the baseline, faded by a slider.
///
/// At a fixed opacity a change shows up as a faint double image, which is easy to miss. With
/// the fade under the user's hand, sweeping from one end to the other makes whatever changed
/// move, appear, or vanish while everything that matches stays still.
struct OnionSkinView: View {

    let baseline: SnapshotPane
    let candidate: SnapshotPane
    let reloadToken: Int
    let matte: Color?

    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale

    @State private var baselineImage: CanvasImage?
    @State private var candidateImage: CanvasImage?

    var body: some View {
        VStack(spacing: 0) {
            // Both images are laid down whole in the same box, so a pixel of one sits exactly
            // over the same pixel of the other: any offset between them would invent a
            // difference of its own.
            GeometryReader { proxy in
                let layout = layout
                ZStack(alignment: .topLeading) {
                    layer(baselineImage, matte: matte, at: layout.rect(layout.leftRect, fittedIn: proxy.size), in: proxy.size)
                    layer(candidateImage, matte: nil, at: layout.rect(layout.rightRect, fittedIn: proxy.size), in: proxy.size)
                        .opacity(state.canvas.onionOpacity)
                }
            }
            .padding(12)

            Divider()

            footer
        }
        .task(id: ReloadKey(baseline: baseline.fileURL.path, candidate: candidate.fileURL.path, token: reloadToken)) {
            await loadImages()
        }
    }

    // MARK: - Pieces

    /// How the two images sit over each other: at one pixel to one pixel from the top-left
    /// corner, as the diff mask measures them, so whatever the fade reveals is a real change.
    ///
    /// One image alone, while the other is still loading, is laid out on its own.
    private var layout: ComparisonImageRenderer.Layout {
        let sizes = [baselineImage, candidateImage].map { image -> CGSize? in
            guard case let .loaded(decoded) = image else { return nil }
            return decoded.pixelSize
        }
        let below = sizes[0] ?? sizes[1] ?? .zero
        let above = sizes[1] ?? sizes[0] ?? .zero
        return ComparisonImageRenderer.layout(left: below, right: above)
    }

    @ViewBuilder
    private func layer(_ image: CanvasImage?, matte: Color?, at rect: CGRect, in size: CGSize) -> some View {
        switch image {
        case let .loaded(decoded):
            Image(decorative: decoded.cgImage, scale: displayScale, orientation: .up)
                .resizable()
                .background(matte ?? .clear)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .unavailable, nil:
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var footer: some View {
        @Bindable var canvas = state.canvas
        HStack(spacing: 10) {
            Text(state.canvas.sideTitle(for: baseline))
                .font(.callout)
                .foregroundStyle(.secondary)

            Slider(value: $canvas.onionOpacity, in: 0...1)
                .frame(maxWidth: 280)
                .accessibilityLabel("\(state.canvas.sideTitle(for: candidate)) Opacity")
                .accessibilityValue("\(Int((state.canvas.onionOpacity * 100).rounded())) percent")

            Text(state.canvas.sideTitle(for: candidate))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(state.canvas.onionOpacity.formatted(.percent.precision(.fractionLength(0))))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Button("Reset") {
                state.canvas.onionOpacity = CanvasModel.defaultOnionOpacity
            }
            .buttonStyle(.borderless)
            .disabled(state.canvas.onionOpacity == CanvasModel.defaultOnionOpacity)
            .help("Show both images at equal strength again")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .help("Fade from the baseline to the candidate. Whatever moves while you drag is what changed")
    }

    private func loadImages() async {
        let baselineURL = baseline.fileURL
        let candidateURL = candidate.fileURL

        async let below = Task.detached(priority: .userInitiated) {
            SnapshotImageLoader.load(baselineURL)
        }.value
        async let above = Task.detached(priority: .userInitiated) {
            SnapshotImageLoader.load(candidateURL)
        }.value

        let loaded = await (below, above)
        guard !Task.isCancelled else { return }
        baselineImage = loaded.0
        candidateImage = loaded.1
    }

    private struct ReloadKey: Hashable {
        let baseline: String
        let candidate: String
        let token: Int
    }
}
