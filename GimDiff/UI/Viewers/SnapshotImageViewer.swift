//
//  SnapshotImageViewer.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// One image on the canvas, with the zoom controls under it.
///
/// There is one zoom, not a choice of modes: Fit and 1:1 are places the zoom can be put, and
/// scrolling pans, pinching or ⌘-scrolling zooms, whichever of them was last asked for. Each
/// viewer owns its zoom, so the two panes of a comparison can be inspected independently —
/// one held at 1:1 on a detail while the other stays fitted. Given a ``link``, it mirrors its
/// zoom into it and follows it, so two panes move as one.
struct SnapshotImageViewer<Accessory: View>: View {
    @Environment(AppState.self) private var state

    let fileURL: URL
    /// Bumped by ``AppState/invalidateLoadedImages()`` to force a re-read off disk.
    let reloadToken: Int
    /// Painted directly behind the image, so a transparent snapshot can be read.
    let matte: Color?
    /// Shared with the other pane while Link Panes is on, `nil` otherwise.
    var link: Binding<PaneViewport?>?
    /// Whether this pane's zoom becomes the shared one when linking starts. One pane must
    /// win, or turning the link on would leave the two fighting over whose zoom it is.
    var seedsLink = false
    @ViewBuilder let accessory: () -> Accessory

    @State private var image: CanvasImage?
    /// Where the zoom last stood, as the scroll view reported it.
    @State private var viewport = PaneViewport.fitted
    @State private var zoomRequest: ZoomRequest?
    /// What this pane last wrote into the link. Seen coming back, it is this pane's own
    /// zoom, perhaps a frame behind; following it would pull an animating zoom back.
    @State private var publishedViewport: PaneViewport?
    @State private var zoomText = CanvasZoom.percentText(1)

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
        // The zoom belongs to the image that was being looked at, not to the pane, so a new
        // file opens fitted. The old bitmap goes with it: held until the new one decodes, it
        // would spend a frame claiming to be a file it is not. Dropping it also replaces the
        // scroll view, and the request is dropped so the new one does not replay it.
        .onChange(of: fileURL) {
            image = nil
            zoomRequest = nil
            viewport = .fitted
            zoomText = CanvasZoom.percentText(viewport.magnification)
            followLink()
        }
        .onChange(of: state.canvas.viewRequest) { _, request in
            if let request { perform(request.command) }
        }
        .onChange(of: link != nil) { followLink() }
        .onChange(of: link?.wrappedValue, initial: true) { followLink() }
    }

    // MARK: - Zoom

    private func request(_ action: ZoomAction) {
        zoomRequest = ZoomRequest(serial: (zoomRequest?.serial ?? 0) + 1, action: action)
    }

    /// Carries out a View menu command, which reaches every pane on screen at once.
    ///
    /// Two linked panes would each carry it out and then follow each other halfway through,
    /// so only the pane that seeds the link does; the other follows it.
    private func perform(_ command: CanvasViewCommand) {
        if link != nil, !seedsLink { return }
        switch command {
        case .fit: request(.fit)
        case .actualSize: request(.actualSize)
        case .zoomIn: request(.zoomIn)
        case .zoomOut: request(.zoomOut)
        case .fadeOnionSkin: break
        }
    }

    private func viewportChanged(_ new: PaneViewport, isUserInitiated: Bool) {
        viewport = new
        zoomText = CanvasZoom.percentText(new.magnification)
        guard isUserInitiated, let link else { return }
        if let shared = link.wrappedValue, shared.isClose(to: new) { return }
        publishedViewport = new
        link.wrappedValue = new
    }

    // MARK: - Linking

    /// Takes the shared zoom, or offers this pane's when there is none yet and it seeds.
    private func followLink() {
        guard let link else { return }
        if let shared = link.wrappedValue {
            guard shared != publishedViewport else { return }
            if !shared.isClose(to: viewport) { request(.adopt(shared)) }
        } else if seedsLink {
            publishedViewport = viewport
            link.wrappedValue = viewport
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageArea: some View {
        switch image {
        case let .loaded(decoded):
            ZoomableImageView(
                image: decoded,
                matte: matte,
                request: zoomRequest,
                onChange: viewportChanged(_:isUserInitiated:)
            )
        case .unavailable:
            MissingImageView(fileURL: fileURL)
        case nil:
            ProgressView()
                .controlSize(.small)
        }
    }

    private func loadImage() async {
        let url = fileURL
        let decoded = await Task.detached(priority: .userInitiated) {
            SnapshotImageLoader.load(url)
        }.value

        guard !Task.isCancelled else { return }
        image = decoded
    }

    // MARK: - Footer

    /// The pane's controls, giving up what matters least as the pane narrows: the image
    /// size first, then the zoom's step buttons.
    ///
    /// Two panes side by side share whatever the sidebar leaves, and a row that cannot
    /// shrink does not stay inside its pane — it widens the whole split view past the
    /// window, which then cuts off the sidebar's leading edge and the decision bar's
    /// trailing one. Whatever still does not fit is clipped here, at the pane's own edge.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(showsImageSize: true, showsStepButtons: true)
            footerRow(showsImageSize: false, showsStepButtons: true)
            footerRow(showsImageSize: false, showsStepButtons: false)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func footerRow(showsImageSize: Bool, showsStepButtons: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ZoomPresetButton(title: "Fit", isOn: viewport.isFitting) {
                    request(.fit)
                }
                .help("Fit the whole image in the pane, and keep it fitted as the pane changes size")

                ZoomPresetButton(title: "1:1", isOn: viewport.isActualSize) {
                    request(.actualSize)
                }
                .help("Show the image at the size it was recorded at. Double-click the image to switch between this and Fit")
                .accessibilityLabel("Actual Size")
            }

            zoomControls(showsStepButtons: showsStepButtons)

            if showsImageSize, case let .loaded(decoded) = image {
                imageSizeLabel(decoded)
            }

            Spacer(minLength: 0)

            accessory()
        }
        .padding(.horizontal, 10)
    }

    /// The stored size in pixels, with the density it was recorded at when that is not 1x,
    /// so two panes that differ only in dimensions say so without a diff.
    private func imageSizeLabel(_ decoded: DecodedSnapshotImage) -> some View {
        let size = decoded.pixelSize
        var text = "\(Int(size.width)) × \(Int(size.height)) px"
        if decoded.recordedScale != 1 {
            text += " @\(decoded.recordedScale.formatted())x"
        }

        return Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .help("Image size in pixels")
    }

    private func zoomControls(showsStepButtons: Bool) -> some View {
        HStack(spacing: 6) {
            if showsStepButtons {
                Button {
                    request(.zoomOut)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Zoom Out")
                .accessibilityLabel("Zoom Out")
            }

            // Drawn by hand rather than with `.roundedBorder`: on the translucent bar the
            // system field's fill all but disappears, and the digits with it.
            TextField("Zoom", text: $zoomText)
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
                .onSubmit(commitZoomText)
                .help("Zoom, as a percentage of the image's actual size. Pinch or ⌘-scroll over the image to zoom around the pointer, and scroll or drag to move it")
                .accessibilityLabel("Zoom")

            if showsStepButtons {
                Button {
                    request(.zoomIn)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Zoom In")
                .accessibilityLabel("Zoom In")
            }
        }
    }

    /// Reads the typed percentage back, and puts the field straight when it was not one.
    private func commitZoomText() {
        guard let typed = CanvasZoom.magnification(fromPercentText: zoomText) else {
            zoomText = CanvasZoom.percentText(viewport.magnification)
            return
        }
        request(.set(typed))
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

/// Fit or 1:1 in the footer: a button, shown pressed in while the zoom stands there.
///
/// A toggle in button style rather than a plain button, because the state is the point — it
/// says at a glance whether the pane is fitted. Clicking one that is already on asks again
/// rather than turning it off: there is no "not fitted" to go to.
private struct ZoomPresetButton: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() }))
            .toggleStyle(.button)
            .controlSize(.small)
            .fixedSize()
    }
}
