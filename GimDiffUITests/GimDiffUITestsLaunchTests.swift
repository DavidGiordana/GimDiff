//
//  GimDiffUITestsLaunchTests.swift
//  GimDiffUITests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import XCTest

@MainActor
final class GimDiffUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Captures the launch appearance so regressions in the window chrome are visible in the report.
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
