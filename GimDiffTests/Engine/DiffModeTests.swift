//
//  DiffModeTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Testing
@testable import GimDiff

@Suite("Diff modes")
struct DiffModeTests {
    @Test("Every mode carries a title and a symbol for the toolbar")
    func everyModeIsPresentable() {
        for mode in DiffMode.allCases {
            #expect(!mode.title.isEmpty)
            #expect(!mode.symbolName.isEmpty)
        }
    }

    @Test("Raw values are stable, so a stored preference survives a relaunch")
    func rawValuesAreStable() {
        #expect(DiffMode.allCases.map(\.rawValue) == [
            "sideBySide", "curtain", "onionSkin", "difference",
        ])
    }
}
