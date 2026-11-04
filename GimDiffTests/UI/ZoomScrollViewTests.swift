//
//  ZoomScrollViewTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import Testing
@testable import GimDiff

/// The pane's scroll view, laid out in a window that is never shown.
@Suite("Zoom scroll view")
@MainActor
struct ZoomScrollViewTests {
    /// A phone-shaped snapshot recorded at @2x: 390 × 844 points.
    private let image = Self.makeImage(width: 780, height: 1_688)
    private let viewportSize = CGSize(width: 600, height: 500)

    private static func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    /// The scroll view in a window of its own, laid out, showing the image.
    private func makeView() -> (ZoomScrollView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewportSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        // Released by ARC, not by closing: a window that frees itself on close is freed twice.
        window.isReleasedWhenClosed = false
        let view = ZoomScrollView()
        view.animatesZoom = false
        view.scrollerStyle = .overlay
        window.contentView = view
        view.show(image, recordedScale: 2, matte: nil)
        view.layoutSubtreeIfNeeded()
        view.tile()
        return (view, window)
    }

    private var fit: CGFloat {
        CanvasZoom.fitMagnification(imageSize: CGSize(width: 390, height: 844), viewportSize: viewportSize)
    }

    @Test("A pane opens fitted, with the image in its middle")
    func opensFitted() {
        let (view, window) = makeView()
        defer { window.close() }

        #expect(view.viewport.isFitting)
        #expect(abs(view.magnification - fit) < 0.000_1)
        #expect(abs(view.viewport.center.x - 195) < 0.5)
        #expect(abs(view.viewport.center.y - 422) < 0.5)
        #expect(!view.canPan)
    }

    @Test("Actual size is measured in the points the image was recorded at")
    func actualSize() {
        let (view, window) = makeView()
        defer { window.close() }

        view.perform(.actualSize)

        #expect(view.viewport.isActualSize)
        #expect(view.canPan)
    }

    @Test("A centre too near an edge is moved in until the image fills the pane")
    func adoptedCentreIsClamped() {
        let (view, window) = makeView()
        defer { window.close() }

        view.perform(.adopt(PaneViewport(isFitting: false, magnification: 2, center: CGPoint(x: 0, y: 0))))

        // 600 × 500 at 2× is 300 × 250 points of image, so its middle can come no nearer
        // the corner than half of that.
        #expect(abs(view.viewport.center.x - 150) < 0.5)
        #expect(abs(view.viewport.center.y - 125) < 0.5)
    }

    @Test("Following a link takes its zoom and centre, and leaves Fit")
    func adoptsALink() {
        let (view, window) = makeView()
        defer { window.close() }

        view.perform(.adopt(PaneViewport(isFitting: false, magnification: 2, center: CGPoint(x: 200, y: 300))))

        #expect(!view.viewport.isFitting)
        #expect(abs(view.magnification - 2) < 0.000_1)
        #expect(abs(view.viewport.center.x - 200) < 0.5)
        #expect(abs(view.viewport.center.y - 300) < 0.5)
    }

    @Test("Panning stops at the image's edges, and a narrower image stays centred")
    func panIsBounded() {
        let (view, window) = makeView()
        defer { window.close() }
        view.perform(.actualSize)

        // 390 points wide in a 600-point pane: centred across, whatever the drag says.
        view.pan(to: CGPoint(x: -1_000, y: -1_000))
        #expect(abs(view.contentView.bounds.midX - 195) < 0.5)
        #expect(abs(view.contentView.bounds.minY) < 0.5)

        view.pan(to: CGPoint(x: 10_000, y: 10_000))
        #expect(abs(view.contentView.bounds.midX - 195) < 0.5)
        #expect(abs(view.contentView.bounds.maxY - 844) < 0.5)
    }

    @Test("Double-clicking goes to actual size, and from there back to Fit")
    func doubleClickToggles() {
        let (view, window) = makeView()
        defer { window.close() }

        view.toggleActualSize(at: CGPoint(x: 195, y: 100))
        #expect(view.viewport.isActualSize)

        view.toggleActualSize(at: CGPoint(x: 195, y: 100))
        #expect(view.viewport.isFitting)
        #expect(abs(view.magnification - fit) < 0.000_1)
    }

    @Test("A request made before the pane is laid out is applied once it is")
    func requestWaitsForLayout() {
        let view = ZoomScrollView()
        view.animatesZoom = false
        view.show(image, recordedScale: 2, matte: nil)
        view.perform(.actualSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewportSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        // Released by ARC, not by closing: a window that frees itself on close is freed twice.
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.tile()

        #expect(view.viewport.isActualSize)
    }
}
