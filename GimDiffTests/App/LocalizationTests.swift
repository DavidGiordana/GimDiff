//
//  LocalizationTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The English the string catalog gives back for text that depends on a count.
///
/// Each of these used to be two literals picked with `count == 1 ?`. They are one key each
/// now, with the singular in the catalog, so a translation can supply as many forms as its
/// language needs; these check the English forms survived the move.
@Suite("Localization")
struct LocalizationTests {
    @Test("A count of one reads in the singular, any other in the plural")
    func pluralForms() {
        #expect(String(localized: "Discard Changes to \(1) Snapshots") == "Discard Changes to 1 Snapshot")
        #expect(String(localized: "Discard Changes to \(3) Snapshots") == "Discard Changes to 3 Snapshots")
        #expect(String(localized: "Accept all \(1) failing snapshots?") == "Accept the failing snapshot?")
        #expect(String(localized: "Accept all \(4) failing snapshots?") == "Accept all 4 failing snapshots?")
        #expect(String(localized: "\(1) snapshots failed in the test run") == "1 snapshot failed in the test run")
        #expect(String(localized: "\(1) snapshots are restored from the last commit.")
            == "1 snapshot is restored from the last commit.")
        #expect(String(localized: "\(2) snapshots the last commit does not have are moved to the Trash.")
            == "2 snapshots the last commit does not have are moved to the Trash.")
        #expect(String(localized: "\(1) snapshots the last commit does not have are moved to the Trash.")
            == "1 snapshot the last commit does not have is moved to the Trash.")
    }

    @Test("The project summary agrees with each of its two counts separately")
    func summaryWithTwoCounts() {
        #expect(String(localized: "\(1) test cases · \(5) snapshots") == "1 test case · 5 snapshots")
        #expect(String(localized: "\(2) test cases · \(1) snapshots") == "2 test cases · 1 snapshot")
    }
}
