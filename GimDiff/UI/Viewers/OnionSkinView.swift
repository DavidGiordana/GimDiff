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
    /// Where the slider starts: both images at equal strength.
    static let defaultOpacity = 0.5

    let baseline: SnapshotPane
    let candidate: SnapshotPane
    let reloadToken: Int
    let matte: Color?

    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale

    /// How much of the candidate shows: 0 is the baseline alone, 1 the candidate alone.
    @State private var candidateOpacity = Self.defaultOpacity
    @State private var baselineImage: CanvasImage?
    @State private var candidateImage: CanvasImage?

    var body: some View {
        VStack(spacing: 0) {
            // Both images are laid down whole in the same box, so a pixel of one sits exactly
            // over the same pixel of the other: any offset between them would invent a
            // difference of its own.
            GeometryReader { proxy in
                ZStack {
                    layer(baselineImage, matte: matte, in: proxy.size)
                    layer(candidateImage, matte: nil, in: proxy.size)
                        .opacity(candidateOpacity)
                }
            }
            .padding(12)

            Divider()

            footer
        }
        .task(id: ReloadKey(baseline: baseline.fileURL.path, candidate: candidate.fileURL.path, token: reloadToken)) {
            await loadImages()
        }
        .onChange(of: state.canvasViewRequest) { _, request in
            if case let .fadeOnionSkin(opacity)? = request?.command {
                candidateOpacity = opacity
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func layer(_ image: CanvasImage?, matte: Color?, in size: CGSize) -> some View {
        switch image {
        case let .loaded(decoded):
            Image(decorative: decoded.cgImage, scale: displayScale, orientation: .up)
                .resizable()
                .scaledToFit()
                .background(matte ?? .clear)
                .frame(width: size.width, height: size.height)
        case .unavailable, nil:
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(state.sideTitle(for: baseline))
                .font(.callout)
                .foregroundStyle(.secondary)

            Slider(value: $candidateOpacity, in: 0...1)
                .frame(maxWidth: 280)
                .accessibilityLabel("\(state.sideTitle(for: candidate)) Opacity")
                .accessibilityValue("\(Int((candidateOpacity * 100).rounded())) percent")

            Text(state.sideTitle(for: candidate))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("\(Int((candidateOpacity * 100).rounded()))%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Button("Reset") {
                candidateOpacity = Self.defaultOpacity
            }
            .buttonStyle(.borderless)
            .disabled(candidateOpacity == Self.defaultOpacity)
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
