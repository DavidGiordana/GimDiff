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
    private let base = LinkedPaneTransform(
        displayMode: .free,
        scale: 2,
        offset: CGSize(width: 0.25, height: -0.1)
    )

    @Test("Rounding from a round trip through two panes is not a change")
    func roundingIsClose() {
        var rounded = base
        rounded.offset.width += 0.000_01
        rounded.scale += 0.000_01

        #expect(base.isClose(to: rounded))
    }

    @Test("A real move, zoom, or mode change is a change")
    func realChangesAreNotClose() {
        var moved = base
        moved.offset.height += 0.01
        var zoomed = base
        zoomed.scale = 2.25
        var refitted = base
        refitted.displayMode = .fit

        #expect(!base.isClose(to: moved))
        #expect(!base.isClose(to: zoomed))
        #expect(!base.isClose(to: refitted))
    }

    @Test("Link Panes is off until turned on, and then remembered")
    func linkIsRemembered() {
        let defaults = TemporaryDefaults()
        let first = AppState(watcher: StubProjectWatcher(), defaults: defaults.defaults)
        #expect(first.linksPanes == false)

        first.linksPanes = true

        let second = AppState(watcher: StubProjectWatcher(), defaults: defaults.defaults)
        #expect(second.linksPanes)
    }
}
