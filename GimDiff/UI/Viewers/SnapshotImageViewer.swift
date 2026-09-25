//
//  SnapshotImageViewer.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// How one image is fitted into the room the canvas has for it.
enum CanvasDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// Scaled down until the whole image is on screen.
    case fit
    /// Drawn at the point size it was recorded at, scrollable in both directions.
    case actualSize
    /// Whatever the pinch and the drag have made of it.
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: "Fit"
        case .actualSize: "Actual Size (1:1)"
        case .free: "Free"
        }
    }
}

/// One image on the canvas, with the controls that decide how it is drawn.
///
/// The viewer owns its display mode and its transform, so the two panes of a comparison can
/// be inspected independently — one held at 1:1 on a detail while the other stays fitted.
struct SnapshotImageViewer<Accessory: View>: View {
    /// How far in and out a free-mode zoom may go.
    static var scaleRange: ClosedRange<CGFloat> { 0.1...10.0 }
    /// How much one press of `+` or `−` moves the scale.
    static var zoomStep: CGFloat { 0.25 }

    @Environment(\.displayScale) private var displayScale

    let fileURL: URL
    /// Bumped by ``AppState/invalidateLoadedImages()`` to force a re-read off disk.
    let reloadToken: Int
    /// Painted directly behind the image, so a transparent snapshot can be read.
    let matte: Color?
    @ViewBuilder let accessory: () -> Accessory

    @State private var image: CanvasImage?
    @State private var displayMode: CanvasDisplayMode = .fit
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    /// Where the transform stood when the current gesture began.
    @State private var anchoredScale: CGFloat = 1.0
    @State private var anchoredOffset: CGSize = .zero
    @State private var scaleText = "1.00"

    var body: some View {
        VStack(spacing: 0) {
            imageArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            Divider()

            footer
        }
        // Keyed on the token as well as the path: a promotion rewrites the bytes behind a
        // name that has not changed, and nothing about the URL alone would say so.
        .task(id: ReloadKey(path: fileURL.path, token: reloadToken)) {
            await loadImage()
        }
        // A new file at the old transform would open somewhere off screen, so the pan and
        // the zoom belong to the image that was being looked at, not to the pane. The old
        // bitmap goes with them: held until the new one decodes, it would spend a frame
        // claiming to be a file it is not.
        .onChange(of: fileURL) {
            image = nil
            resetTransform(animated: false)
        }
        .onChange(of: displayMode) { resetTransform(animated: false) }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageArea: some View {
        switch image {
        case let .loaded(decoded):
            decodedContent(decoded)
        case .unavailable:
            MissingImageView(fileURL: fileURL)
        case nil:
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func decodedContent(_ decoded: DecodedSnapshotImage) -> some View {
        switch displayMode {
        case .fit:
            fittedImage(decoded)
                .padding(12)

        case .actualSize:
            // Scaled by the density the snapshot was recorded at, not the display's: no Mac is
            // @3x, so pixel-for-pixel would draw an iPhone snapshot up to three times the size
            // the simulator showed it.
            ScrollView([.horizontal, .vertical]) {
                matted(
                    Image(decorative: decoded.cgImage, scale: decoded.recordedScale, orientation: .up)
                )
                .padding(12)
            }

        case .free:
            fittedImage(decoded)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(SimultaneousGesture(magnifyGesture, panGesture))
                .background(ScrollWheelReader(onScroll: zoom(with:)))
        }
    }

    private func fittedImage(_ decoded: DecodedSnapshotImage) -> some View {
        matted(
            Image(decorative: decoded.cgImage, scale: displayScale, orientation: .up)
                .resizable()
                .scaledToFit()
        )
    }

    /// Puts the matte colour behind the image itself rather than behind the pane.
    ///
    /// That is the whole point of the control: a dark-mode icon on a dark panel is invisible
    /// until something opaque sits in the transparent parts of the *image*, exactly where
    /// the image is and nowhere else.
    private func matted(_ image: some View) -> some View {
        image.background(matte ?? .clear)
    }

    private func loadImage() async {
        let url = fileURL
        let decoded = await Task.detached(priority: .userInitiated) {
            SnapshotImageLoader.load(url)
        }.value

        guard !Task.isCancelled else { return }
        image = decoded
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = Self.clamped(anchoredScale * value.magnification)
                syncScaleText()
            }
            .onEnded { _ in anchoredScale = scale }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: anchoredOffset.width + value.translation.width,
                    height: anchoredOffset.height + value.translation.height
                )
            }
            .onEnded { _ in anchoredOffset = offset }
    }

    /// Zooms around the pointer, so whatever is under it stays under it.
    ///
    /// The step is exponential in the distance scrolled, which makes a wheel notch in and a
    /// notch out land back where they started, at any scale.
    private func zoom(with tick: ScrollWheelTick) {
        let sensitivity: CGFloat = tick.isPrecise ? 0.01 : 0.1
        let newScale = Self.clamped(scale * exp(tick.delta * sensitivity))
        guard newScale != scale else { return }

        // The image is scaled about the pane's centre and then offset, so a pointer at `p`
        // is over the image point `(p - offset) / scale`. Keeping that point under the
        // pointer at the new scale fixes the offset.
        let ratio = newScale / scale
        let pointer = tick.locationFromCenter
        offset = CGSize(
            width: pointer.x - (pointer.x - offset.width) * ratio,
            height: pointer.y - (pointer.y - offset.height) * ratio
        )
        scale = newScale
        anchoredScale = scale
        anchoredOffset = offset
        syncScaleText()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Picker("Display Mode", selection: $displayMode) {
                ForEach(CanvasDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 148)
            .help("How the image is fitted into the pane")

            if displayMode == .free {
                zoomControls
            }

            Spacer(minLength: 0)

            accessory()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// The zoom row, shown only in free mode: it is the only mode the numbers can move in.
    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                resetTransform(animated: true)
            } label: {
                Image(systemName: "dot.scope")
            }
            .buttonStyle(.borderless)
            .help("Centre the image and reset the zoom to 1.0")
            .accessibilityLabel("Centre and Reset Focus")

            Button {
                step(by: -Self.zoomStep)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(scale <= Self.scaleRange.lowerBound)
            .accessibilityLabel("Zoom Out")

            // Drawn by hand rather than with `.roundedBorder`: on the translucent bar the
            // system field's fill all but disappears, and the digits with it.
            TextField("Scale", text: $scaleText)
                .textFieldStyle(.plain)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: 58)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: .rect(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor))
                )
                .onSubmit(commitScaleText)
                .help("Zoom factor, between 0.1 and 10.0. Scroll over the image to zoom around the pointer")
                .accessibilityLabel("Zoom Factor")

            Button {
                step(by: Self.zoomStep)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(scale >= Self.scaleRange.upperBound)
            .accessibilityLabel("Zoom In")
        }
    }

    // MARK: - Transform

    private func step(by delta: CGFloat) {
        withAnimation(.easeOut(duration: 0.15)) {
            scale = Self.clamped(scale + delta)
        }
        anchoredScale = scale
        syncScaleText()
    }

    /// Reads the typed number back, and puts the field straight when it was not one.
    private func commitScaleText() {
        guard let typed = Double(scaleText.trimmingCharacters(in: .whitespaces)) else {
            syncScaleText()
            return
        }

        withAnimation(.easeOut(duration: 0.15)) {
            scale = Self.clamped(CGFloat(typed))
        }
        anchoredScale = scale
        syncScaleText()
    }

    private func resetTransform(animated: Bool) {
        withAnimation(animated ? .easeInOut(duration: 0.25) : nil) {
            scale = 1.0
            offset = .zero
        }
        anchoredScale = 1.0
        anchoredOffset = .zero
        syncScaleText()
    }

    private func syncScaleText() {
        scaleText = String(format: "%.2f", scale)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// Identity of one load, so a refresh of the same path counts as a different read.
    private struct ReloadKey: Hashable {
        let path: String
        let token: Int
    }
}

extension SnapshotImageViewer where Accessory == EmptyView {
    init(fileURL: URL, reloadToken: Int, matte: Color?) {
        self.init(fileURL: fileURL, reloadToken: reloadToken, matte: matte) { EmptyView() }
    }
}
