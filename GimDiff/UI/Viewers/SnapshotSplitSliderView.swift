//
//  SnapshotSplitSliderView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The curtain: two images drawn in the same place, revealed by a draggable split.
///
/// Side by side, a two-pixel shift has to be found by looking back and forth between two
/// rectangles. Stacked in one set of coordinates with a curtain over them, the same shift is
/// a jump under the handle, which is why this mode exists at all.
struct SnapshotSplitSliderView: View {
    /// Below this the "BEFORE" badge has no image left to sit on.
    static let badgeVisibilityMargin: CGFloat = 0.15
    static let handleDiameter: CGFloat = 26
    static let dividerWidth: CGFloat = 3

    /// Drawn on the left of the split.
    let leading: SnapshotPane
    /// Drawn on the right of the split.
    let trailing: SnapshotPane
    let reloadToken: Int
    let matte: Color?

    @Environment(\.displayScale) private var displayScale

    @State private var splitPosition: CGFloat = 0.5
    @State private var leadingImage: CanvasImage?
    @State private var trailingImage: CanvasImage?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let splitX = width * splitPosition

            ZStack(alignment: .topLeading) {
                // The trailing image is laid down whole and then masked from the right, so
                // both halves are the same fit into the same box: a curtain that moved the
                // image even a point as it opened would invent differences of its own.
                curtainImage(trailingImage, in: proxy.size)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: max(0, width - splitX))
                    }

                curtainImage(leadingImage, in: proxy.size)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, splitX))
                    }

                badge(leading.roleTitle.uppercased(), alignment: .topLeading, in: proxy.size)
                    .opacity(splitPosition < Self.badgeVisibilityMargin ? 0 : 1)

                badge(trailing.roleTitle.uppercased(), alignment: .topTrailing, in: proxy.size)
                    .opacity(splitPosition > 1 - Self.badgeVisibilityMargin ? 0 : 1)

                Rectangle()
                    .fill(.white)
                    .frame(width: Self.dividerWidth, height: proxy.size.height)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .position(x: splitX, y: proxy.size.height / 2)

                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.blue, lineWidth: 3))
                    .frame(width: Self.handleDiameter, height: Self.handleDiameter)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .position(x: splitX, y: proxy.size.height / 2)
                    .accessibilityLabel("Comparison split")
                    .accessibilityValue("\(Int((splitPosition * 100).rounded())) percent")
            }
            .frame(width: width, height: proxy.size.height)
            // The whole surface drags, not just the handle: at a 3pt divider the handle is
            // a target the mouse has to be aimed at, and the gesture is the point of the
            // mode rather than an embellishment on it.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        splitPosition = min(max(value.location.x / width, 0), 1)
                    }
            )
        }
        .task(id: ReloadKey(leading: leading.fileURL.path, trailing: trailing.fileURL.path, token: reloadToken)) {
            await loadImages()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func curtainImage(_ image: CanvasImage?, in size: CGSize) -> some View {
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

    private func badge(_ text: String, alignment: Alignment, in size: CGSize) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .kerning(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: .capsule)
            .padding(12)
            .frame(width: size.width, height: size.height, alignment: alignment)
            .allowsHitTesting(false)
    }

    private func loadImages() async {
        let leadingURL = leading.fileURL
        let trailingURL = trailing.fileURL

        async let left = Task.detached(priority: .userInitiated) {
            SnapshotImageLoader.load(leadingURL)
        }.value
        async let right = Task.detached(priority: .userInitiated) {
            SnapshotImageLoader.load(trailingURL)
        }.value

        let loaded = await (left, right)
        guard !Task.isCancelled else { return }
        leadingImage = loaded.0
        trailingImage = loaded.1
    }

    private struct ReloadKey: Hashable {
        let leading: String
        let trailing: String
        let token: Int
    }
}
