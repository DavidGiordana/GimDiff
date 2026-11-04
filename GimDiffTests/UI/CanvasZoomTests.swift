//
//  CanvasZoomTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import Testing
@testable import GimDiff

/// The arithmetic behind a pane's zoom: fitting, stepping, the wheel, and the typed value.
@Suite("Canvas zoom")
struct CanvasZoomTests {
    @Test("Fit leaves the margin on the side that runs out first")
    func fitKeepsTheMargin() {
        let fit = CanvasZoom.fitMagnification(
            imageSize: CGSize(width: 400, height: 800),
            viewportSize: CGSize(width: 1_000, height: 424)
        )

        #expect(abs(fit - 0.5) < 0.000_1)
    }

    @Test("A small image is enlarged to fit")
    func fitEnlarges() {
        let fit = CanvasZoom.fitMagnification(
            imageSize: CGSize(width: 20, height: 20),
            viewportSize: CGSize(width: 424, height: 424)
        )

        #expect(abs(fit - 20) < 0.000_1)
    }

    @Test("An empty image fits at its actual size")
    func emptyImage() {
        #expect(CanvasZoom.fitMagnification(imageSize: .zero, viewportSize: CGSize(width: 100, height: 100)) == 1)
    }

    @Test("The range widens to take in a fit beyond the fixed limits")
    func rangeIncludesFit() {
        #expect(CanvasZoom.range(fit: 0.5) == 0.1...16)
        #expect(CanvasZoom.range(fit: 0.02) == 0.02...16)
        #expect(CanvasZoom.range(fit: 20) == 0.1...20)
    }

    @Test("Stepping from between two stops lands on the next one")
    func steppingFromBetweenStops() {
        #expect(CanvasZoom.stepped(from: 0.43, zoomingIn: true, fit: 0.43) == 0.5)
        #expect(CanvasZoom.stepped(from: 0.43, zoomingIn: false, fit: 0.43) == 1.0 / 3)
    }

    @Test("Stepping from a stop moves to its neighbour, not to itself")
    func steppingFromAStop() {
        #expect(CanvasZoom.stepped(from: 1, zoomingIn: true, fit: 0.5) == 1.5)
        #expect(CanvasZoom.stepped(from: 1.000_000_1, zoomingIn: false, fit: 0.5) == 0.75)
    }

    @Test("Stepping past the last stop stops at the end of the range")
    func steppingPastTheEnds() {
        #expect(CanvasZoom.stepped(from: 16, zoomingIn: true, fit: 0.5) == 16)
        #expect(CanvasZoom.stepped(from: 16, zoomingIn: true, fit: 20) == 20)
        #expect(CanvasZoom.stepped(from: 0.1, zoomingIn: false, fit: 0.5) == 0.1)
        #expect(CanvasZoom.stepped(from: 0.1, zoomingIn: false, fit: 0.05) == 0.05)
    }

    @Test("A notch in and a notch out land back where they started")
    func wheelIsSymmetric() {
        let zoomedIn = CanvasZoom.wheeled(from: 0.8, delta: 3, isPrecise: false)
        let back = CanvasZoom.wheeled(from: zoomedIn, delta: -3, isPrecise: false)

        #expect(zoomedIn > 0.8)
        #expect(abs(back - 0.8) < 0.000_1)
    }

    @Test("A typed zoom is read as a percentage, with or without the sign")
    func typedPercentages() {
        #expect(CanvasZoom.magnification(fromPercentText: "150") == 1.5)
        #expect(CanvasZoom.magnification(fromPercentText: "150%") == 1.5)
        #expect(CanvasZoom.magnification(fromPercentText: " 50 % ") == 0.5)
        #expect(CanvasZoom.magnification(fromPercentText: "12,5") == 0.125)
    }

    @Test("A typed zoom that is not a positive number is refused")
    func refusedPercentages() {
        #expect(CanvasZoom.magnification(fromPercentText: "") == nil)
        #expect(CanvasZoom.magnification(fromPercentText: "big") == nil)
        #expect(CanvasZoom.magnification(fromPercentText: "0") == nil)
        #expect(CanvasZoom.magnification(fromPercentText: "-50") == nil)
    }
}
