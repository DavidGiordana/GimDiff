//
//  LinkedPanesTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import Testing
@testable import GimDiff

/// What two linked panes share, and the setting that links them.
@Suite("Linked panes")
@MainActor
struct LinkedPanesTests {
    private let base = PaneViewport(
        isFitting: false,
        magnification: 2,
        center: CGPoint(x: 120, y: 340)
    )

    @Test("Rounding from a round trip through two panes is not a change")
    func roundingIsClose() {
        var rounded = base
        rounded.center.x += 0.001
        rounded.magnification += 0.000_01

        #expect(base.isClose(to: rounded))
    }

    @Test("A real move, zoom, or return to Fit is a change")
    func realChangesAreNotClose() {
        var moved = base
        moved.center.y += 1
        var zoomed = base
        zoomed.magnification = 2.25
        var refitted = base
        refitted.isFitting = true

        #expect(!base.isClose(to: moved))
        #expect(!base.isClose(to: zoomed))
        #expect(!base.isClose(to: refitted))
    }

    @Test("Two fitted panes agree whatever their numbers, since each fits its own image")
    func fittedPanesAreClose() {
        let first = PaneViewport(isFitting: true, magnification: 0.4, center: CGPoint(x: 10, y: 10))
        let second = PaneViewport(isFitting: true, magnification: 0.7, center: CGPoint(x: 90, y: 30))

        #expect(first.isClose(to: second))
    }

    @Test("Only an unfitted 100% is the actual size")
    func actualSize() {
        let fittedAtOne = PaneViewport(isFitting: true, magnification: 1, center: .zero)
        let actual = PaneViewport(isFitting: false, magnification: 1, center: .zero)

        #expect(!fittedAtOne.isActualSize)
        #expect(actual.isActualSize)
        #expect(!base.isActualSize)
    }

    @Test("Link Panes is off until turned on, and then remembered")
    func linkIsRemembered() {
        let defaults = TemporaryDefaults()
        let first = AppState(watcher: StubProjectWatcher(), defaults: defaults.defaults)
        #expect(first.canvas.linksPanes == false)

        first.canvas.linksPanes = true

        let second = AppState(watcher: StubProjectWatcher(), defaults: defaults.defaults)
        #expect(second.canvas.linksPanes)
    }
}
