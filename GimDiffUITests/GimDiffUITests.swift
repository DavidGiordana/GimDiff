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

        XCTAssertTrue(app.staticTexts["No Recent Projects"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open Project…"].exists)
    }

    /// The detail column explains itself too, so a window with nothing open is never blank.
    func testDetailPaneExplainsTheEmptyState() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["No Snapshot Selected"].waitForExistence(timeout: 10))
    }

    /// Launched with the state reset, so a project opened by hand on the developer's own
    /// machine cannot decide which empty state the assertions above are looking at.
    ///
    /// A defaults override rather than a bare word: AppKit reads a non-flag launch argument
    /// as a file to open, and one that names no file leaves the app running with no window.
    ///
    /// Window restoration is switched off for the same reason. A window last left in full
    /// screen is restored into a Space of its own, which only comes forward if the launch
    /// happens to win activation — so the window "never appears" on some runs and not others.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GimDiffResetState", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "The window never appeared.")
        return app
    }
}
