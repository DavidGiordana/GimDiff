//
//  ZoomableImageView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import SwiftUI

/// Something a pane's footer or the View menu asks of the image's zoom.
enum ZoomAction: Equatable {
    case fit
    case actualSize
    case zoomIn
    case zoomOut
    case set(CGFloat)
    /// Takes the other linked pane's zoom. Never published back to the link, or two panes
    /// whose images clamp differently would push each other about.
    case adopt(PaneViewport)
}

/// One ``ZoomAction``, numbered so that asking twice is still a change.
struct ZoomRequest: Equatable {
    let serial: Int
    let action: ZoomAction
}

/// One image in a magnifying scroll view: scroll to pan, pinch or ⌘-scroll to zoom.
///
/// The gestures are AppKit's own rather than drawn by hand, so they behave as in every other
/// Mac app — momentum and elastic edges on a trackpad, two-finger double-tap, scroll bars —
/// and an image smaller than the pane stays in its middle.
struct ZoomableImageView: NSViewRepresentable {
    let image: DecodedSnapshotImage
    let matte: Color?
    let request: ZoomRequest?
    /// Called once per change, after it has settled. The flag says whether the user caused
    /// it, rather than the pane following its link or refitting itself to a new size.
    let onChange: (PaneViewport, _ isUserInitiated: Bool) -> Void

    func makeNSView(context: Context) -> ZoomScrollView {
        ZoomScrollView()
    }

    func updateNSView(_ view: ZoomScrollView, context: Context) {
        view.onChange = onChange
        view.show(image.cgImage, recordedScale: image.recordedScale, matte: matte.map { NSColor($0) })
        if let request, request.serial != view.handledRequestSerial {
            view.handledRequestSerial = request.serial
            view.perform(request.action)
        }
    }
}

/// The scroll view behind ``ZoomableImageView``.
final class ZoomScrollView: NSScrollView {
    var onChange: (PaneViewport, Bool) -> Void = { _, _ in }
    var handledRequestSerial = 0
    /// Off in tests, which read the zoom straight after asking for it.
    var animatesZoom = true

    private let canvas = ZoomImageCanvas()
    /// Whether the image is refitted as the pane changes size. Cleared by any zoom the user
    /// makes, set again only by Fit.
    private var isFitting = true {
        didSet { if isFitting != oldValue { scheduleReport() } }
    }
    /// An action that arrived before the pane had a size to apply it to.
    private var pendingAction: (action: ZoomAction, isUserInitiated: Bool)?
    /// True while the pane moves on its own account rather than the user's.
    private var isFollowing = false
    private var laidOutSize: CGSize = .zero
    private var reportIsScheduled = false
    private var reportIsUserInitiated = false

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        documentView = canvas
        drawsBackground = false
        contentView.drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        allowsMagnification = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Content

    func show(_ image: CGImage, recordedScale: CGFloat, matte: NSColor?) {
        canvas.matte = matte
        guard canvas.cgImage !== image || canvas.recordedScale != recordedScale else { return }

        // Drawn at the density it was recorded at, not the display's: no Mac is @3x, so pixel
        // for pixel would draw an iPhone snapshot up to three times the size the simulator
        // showed it.
        let size = CGSize(
            width: CGFloat(image.width) / max(recordedScale, 1),
            height: CGFloat(image.height) / max(recordedScale, 1)
        )
        canvas.setImage(image, recordedScale: recordedScale, pointSize: size)
        guard size != canvas.frame.size else { return }
        canvas.setFrameSize(size)
        following {
            updateMagnificationRange()
            if isFitting { magnification = fitMagnification }
        }
    }

    // MARK: - Zooming

    func perform(_ action: ZoomAction) {
        let isUserInitiated = if case .adopt = action { false } else { true }
        guard laidOutSize != .zero else {
            pendingAction = (action, isUserInitiated)
            return
        }
        apply(action, isUserInitiated: isUserInitiated)
    }

    /// Double-click and two-finger double-tap: actual size at the point, or back to Fit.
    func toggleActualSize(at point: CGPoint) {
        if !isFitting, abs(magnification - 1) < 0.000_1 {
            fit(animated: true)
        } else {
            zoom(to: 1, around: point, animated: true)
        }
    }

    private func apply(_ action: ZoomAction, isUserInitiated: Bool) {
        guard isUserInitiated else {
            following { apply(action) }
            return
        }
        apply(action)
    }

    private func apply(_ action: ZoomAction) {
        switch action {
        case .fit:
            fit(animated: true)
        case .actualSize:
            zoom(to: 1, around: visibleCenter, animated: true)
        case .zoomIn, .zoomOut:
            let target = CanvasZoom.stepped(
                from: magnification,
                zoomingIn: action == .zoomIn,
                fit: fitMagnification
            )
            zoom(to: target, around: visibleCenter, animated: true)
        case let .set(value):
            zoom(to: value, around: visibleCenter, animated: true)
        case let .adopt(viewport):
            if viewport.isFitting {
                fit(animated: false)
            } else {
                isFitting = false
                magnification = viewport.magnification
                scroll(centeringOn: viewport.center)
            }
        }
    }

    private func fit(animated: Bool) {
        isFitting = true
        let target = fitMagnification
        if animated, animatesZoom {
            animate { self.animator().magnification = target }
        } else {
            magnification = target
        }
    }

    private func zoom(to target: CGFloat, around point: CGPoint, animated: Bool) {
        isFitting = false
        if animated, animatesZoom {
            animate { self.animator().setMagnification(target, centeredAt: point) }
        } else {
            setMagnification(target, centeredAt: point)
        }
    }

    /// Runs `body` as a short animation, and reports where the zoom ended once it has.
    ///
    /// The report that the change schedules goes out on the next turn of the main actor,
    /// while the animation has barely started; without one at the end, the footer would
    /// keep the magnification the animation left from, and neither Fit nor 1:1 would be lit.
    private func animate(_ body: () -> Void) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.2
        NSAnimationContext.current.completionHandler = { [weak self] in
            Task { @MainActor in self?.scheduleReport() }
        }
        body()
        NSAnimationContext.endGrouping()
    }

    private var fitMagnification: CGFloat {
        CanvasZoom.fitMagnification(imageSize: canvas.frame.size, viewportSize: contentView.frame.size)
    }

    private func updateMagnificationRange() {
        let range = CanvasZoom.range(fit: fitMagnification)
        minMagnification = range.lowerBound
        maxMagnification = range.upperBound
    }

    /// Where the zoom stands now.
    var viewport: PaneViewport {
        PaneViewport(isFitting: isFitting, magnification: magnification, center: visibleCenter)
    }

    /// The image point in the middle of what is visible.
    private var visibleCenter: CGPoint {
        CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }

    // MARK: - Panning

    /// Whether there is more of the image than fits, for a drag to move.
    var canPan: Bool {
        canvas.frame.width > contentView.bounds.width + 0.5
            || canvas.frame.height > contentView.bounds.height + 0.5
    }

    /// Moves the visible area to `origin`, as far as the image's edges allow.
    func pan(to origin: CGPoint) {
        let proposed = NSRect(origin: origin, size: contentView.bounds.size)
        contentView.setBoundsOrigin(contentView.constrainBoundsRect(proposed).origin)
        reflectScrolledClipView(contentView)
    }

    private func scroll(centeringOn point: CGPoint) {
        let size = contentView.bounds.size
        pan(to: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    // MARK: - Events

    override func scrollWheel(with event: NSEvent) {
        // A plain scroll pans, as everywhere else on the Mac. Only ⌘ turns it into a zoom,
        // for a mouse that has no pinch.
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        // Inertia after a flick would keep zooming well past where the fingers stopped.
        guard event.momentumPhase.isEmpty, event.scrollingDeltaY != 0 else { return }

        // Corrected for natural scrolling, so the same physical motion zooms the same way
        // whatever the system preference says.
        let raw = event.scrollingDeltaY
        let delta = event.isDirectionInvertedFromDevice ? -raw : raw
        let target = CanvasZoom.wheeled(from: magnification, delta: delta, isPrecise: event.hasPreciseScrollingDeltas)
        zoom(to: target, around: canvas.convert(event.locationInWindow, from: nil), animated: false)
    }

    override func magnify(with event: NSEvent) {
        isFitting = false
        super.magnify(with: event)
    }

    override func smartMagnify(with event: NSEvent) {
        toggleActualSize(at: canvas.convert(event.locationInWindow, from: nil))
    }

    override func tile() {
        super.tile()
        let size = contentView.frame.size
        guard size.width > 0, size.height > 0, size != laidOutSize else { return }
        laidOutSize = size

        following {
            updateMagnificationRange()
            if isFitting, pendingAction == nil { magnification = fitMagnification }
        }
        if let pending = pendingAction {
            pendingAction = nil
            apply(pending.action, isUserInitiated: pending.isUserInitiated)
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        canvas.updateFilters(magnification: magnification, backingScale: window?.backingScaleFactor ?? 2)
        scheduleReport()
    }

    // MARK: - Reporting

    private func following(_ body: () -> Void) {
        let wasFollowing = isFollowing
        isFollowing = true
        body()
        isFollowing = wasFollowing
    }

    /// Reports the change on the next turn of the main actor, once for however many bounds
    /// changes a gesture makes in between — and outside the SwiftUI update that may have
    /// caused it, where changing the viewer's state is not allowed.
    private func scheduleReport() {
        if !isFollowing { reportIsUserInitiated = true }
        guard !reportIsScheduled else { return }
        reportIsScheduled = true
        Task { @MainActor [weak self] in self?.report() }
    }

    private func report() {
        reportIsScheduled = false
        let isUserInitiated = reportIsUserInitiated
        reportIsUserInitiated = false
        onChange(viewport, isUserInitiated)
    }
}

/// Keeps an image smaller than the pane in the pane's middle, rather than in its corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let content = documentView.frame
        if rect.width > content.width {
            rect.origin.x = content.midX - rect.width / 2
        }
        if rect.height > content.height {
            rect.origin.y = content.midY - rect.height / 2
        }
        return rect
    }
}

/// The image itself. An image view rather than a layer's contents, so the image is drawn
/// the right way up in a flipped document, and layer-backed so that zooming is a GPU scale
/// rather than a redraw.
private final class ZoomImageCanvas: NSImageView {
    private(set) var cgImage: CGImage?
    private(set) var recordedScale: CGFloat = 1
    /// Painted behind the image only, so the transparent parts of a snapshot can be read.
    var matte: NSColor? {
        didSet { if matte != oldValue { applyMatte() } }
    }
    private var dragStart: (pointer: CGPoint, origin: CGPoint)?
    private var pushedCursor = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageScaling = .scaleAxesIndependently
        imageFrameStyle = .none
        isEditable = false
        animates = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// A document measured down from its top, so a tall image opens at its top.
    override var isFlipped: Bool { true }

    func setImage(_ image: CGImage, recordedScale: CGFloat, pointSize: CGSize) {
        cgImage = image
        self.recordedScale = recordedScale
        self.image = NSImage(cgImage: image, size: pointSize)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyMatte()
    }

    private func applyMatte() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = matte?.cgColor
        }
    }

    /// Smooth while the image is shown at about its size or smaller; hard-edged pixels once
    /// each one covers several on screen, which is what zooming in on a difference is for.
    func updateFilters(magnification: CGFloat, backingScale: CGFloat) {
        guard let layer else { return }
        let screenPixelsPerImagePixel = magnification * backingScale / max(recordedScale, 1)
        let filter: CALayerContentsFilter = screenPixelsPerImagePixel >= 2 ? .nearest : .linear
        if layer.magnificationFilter != filter { layer.magnificationFilter = filter }
        if layer.minificationFilter != .trilinear { layer.minificationFilter = .trilinear }
    }

    // MARK: - Dragging

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let scrollView = enclosingScrollView as? ZoomScrollView else { return }
        if event.clickCount == 2 {
            dragStart = nil
            scrollView.toggleActualSize(at: convert(event.locationInWindow, from: nil))
            return
        }
        dragStart = (event.locationInWindow, scrollView.contentView.bounds.origin)
        if scrollView.canPan {
            NSCursor.closedHand.push()
            pushedCursor = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let scrollView = enclosingScrollView as? ZoomScrollView else { return }
        // The window measures up from the bottom and the image down from the top, so the
        // vertical distance is added where the horizontal one is taken away.
        let scale = scrollView.magnification
        scrollView.pan(to: CGPoint(
            x: start.origin.x - (event.locationInWindow.x - start.pointer.x) / scale,
            y: start.origin.y + (event.locationInWindow.y - start.pointer.y) / scale
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
    }
}
