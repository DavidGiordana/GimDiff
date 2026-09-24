//
//  GimDiffUITests.swift
//  GimDiffUITests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import XCTest

@MainActor
final class GimDiffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsASingleWindow() {
        let app = launchApp()

        XCTAssertEqual(app.windows.count, 1, "GimDiff is a single-instance utility.")
    }

    /// Reopening the app must raise the existing window rather than spawn another one.
    func testReopeningDoesNotOpenASecondWindow() {
        let app = launchApp()

        app.activate()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.count, 1)
    }

    /// Doubles as the guard on the sidebar being visible at launch: its empty state is only
    /// in the accessibility tree while the sidebar column is showing, so a regression that
    /// collapses it fails here rather than shipping an app with no visible navigation.
    func testSidebarExplainsTheEmptyState() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["No Snapshots"].waitForExistence(timeout: 10))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "The window never appeared.")
        return app
    }
}
