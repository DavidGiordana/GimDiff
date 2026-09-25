//
//  KeyboardNavigationUITests.swift
//  GimDiffUITests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import XCTest

/// Drives the snapshot tree with nothing but the keyboard.
///
/// The projection and the arrow-key rules are unit tested against `AppState`; what only a
/// running app can show is the wiring — that the list takes focus at launch, that
/// `.onKeyPress` is reached before the list swallows the key, and that a row really
/// disappears when ⌘⌫ says so.
@MainActor
final class KeyboardNavigationUITests: XCTestCase {
    private var project: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        project = try Self.makeProject()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: project)
    }

    /// The project is handed over in `argv`, which is the path `open -a GimDiff <path>` and
    /// a Finder double-click both end up on: `application(_:openFiles:)`.
    func testOpeningAProjectFromTheCommandLineFillsTheTree() {
        let app = launch()

        XCTAssertEqual(app.windows.count, 1, "GimDiff is a single-instance utility.")
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BetaTests"].exists)
        XCTAssertFalse(app.staticTexts["header"].exists, "Suites start closed.")
    }

    /// → opens a suite, → again steps into it, ← walks back out, and ← again closes it.
    func testArrowKeysWalkTheTree() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["header"].waitForExistence(timeout: 5),
            "→ on a closed suite must open it."
        )

        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.leftArrow, modifierFlags: [])

        // Read off the tree alone: stepping into `header` put it on the canvas too, and the
        // canvas keeps showing its name after the suite closes over it.
        let tree = app.descendants(matching: .any)["SnapshotTree"]
        XCTAssertFalse(tree.staticTexts["header"].exists, "← must close the suite again.")
        XCTAssertTrue(tree.staticTexts["AlphaTests"].exists)
    }

    /// ⌘⌫ deletes the selected snapshot and leaves the tree with a selection to move from.
    func testCommandDeleteRemovesTheSelectedSnapshotAndKeepsFocus() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["footer"].waitForExistence(timeout: 5))

        // Into the suite, onto its first snapshot, then delete it.
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.delete, modifierFlags: .command)

        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["footer"]),
            "⌘⌫ must remove the snapshot from the tree."
        )

        // Focus survived the deletion, so the very next key still moves the selection: the
        // neighbouring row is selected, and ← walks it back up to its suite.
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["header"]),
            "The selection was lost: ← no longer reaches the suite row."
        )
    }

    /// ⌘F and ⌘1/⌘0 reach the sidebar from the menu bar, whatever holds focus.
    func testSidebarShortcutsCollapseAndRestoreTheSidebar() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["AlphaTests"]),
            "⌘0 must collapse the sidebar."
        )

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(
            app.staticTexts["AlphaTests"].waitForExistence(timeout: 5),
            "⌘1 must bring it back."
        )
    }

    /// ⌘F reopens a collapsed sidebar and lands in its search box, ready for a query.
    func testFindReopensTheSidebarIntoTheSearchBox() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["AlphaTests"]))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("toolbar")

        XCTAssertTrue(
            app.staticTexts["toolbar"].waitForExistence(timeout: 5),
            "⌘F must bring the sidebar back with the query typed into its search box."
        )
    }

    /// Typing a query and pressing ↓ hands focus to the tree with the first match selected.
    func testFilteringNarrowsTheTreeAndHandsFocusBack() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("toolbar")

        XCTAssertTrue(app.staticTexts["toolbar"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["AlphaTests"]),
            "A query must hide the suites that hold no match."
        )

        // ⎋ is the search box's key, so it is pressed while the box still has focus.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["AlphaTests"].waitForExistence(timeout: 5),
            "⎋ must clear the query and restore the whole tree."
        )

        // Focus came back to the tree with it, so → is read by the rows again.
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["header"].waitForExistence(timeout: 5),
            "⎋ must return focus to the tree, not leave it in the search box."
        )
    }

    /// ↓ in the search box hands focus to the rows with the first match selected.
    func testDownArrowInTheSearchBoxHandsFocusToTheTree() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("Beta")
        XCTAssertTrue(app.staticTexts["BetaTests"].waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        // The first match is selected and focus is on it, so → steps into the suite rather
        // than moving a cursor through the text that is still in the box.
        app.typeKey(.rightArrow, modifierFlags: [])

        XCTAssertTrue(app.staticTexts["menu"].waitForExistence(timeout: 5))
    }

    /// Both filter chips at once empty the tree, and the empty state must not drag the
    /// search field into the middle of the sidebar with it.
    func testFilteringToNothingKeepsTheSearchFieldAtTheTop() {
        let app = launch()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        let restingTop = search.frame.minY

        filterChip("Modified", in: app).click()
        filterChip("Warnings", in: app).click()

        XCTAssertTrue(app.staticTexts["No Matching Snapshots"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            search.frame.minY,
            restingTop,
            accuracy: 1,
            "The empty state must fill the column instead of re-centring the sidebar."
        )

        app.buttons["Clear Filters"].click()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 5))
    }

    /// The sidebar header closes the project and hands the column back to the recent list.
    func testClosingTheProjectFromTheSidebar() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["AlphaTests"].waitForExistence(timeout: 10))

        app.buttons["Close Project"].click()

        XCTAssertTrue(app.staticTexts["Recent Projects"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["AlphaTests"]),
            "Closing the project must clear the tree."
        )
        XCTAssertEqual(app.windows.count, 1, "Closing a project is not closing the window.")
    }

    // MARK: - Helpers

    /// Restoration is off so a window left in full screen cannot hide in its own Space; see
    /// `GimDiffUITests.launchApp()`.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-GimDiffResetState", "YES",
            "-ApplePersistenceIgnoreState", "YES",
            project.path,
        ]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "The window never appeared.")
        app.activate()
        return app
    }

    /// A filter chip, whichever element type SwiftUI gave a button-styled `Toggle`.
    private func filterChip(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let checkBox = app.checkBoxes[label]
        return checkBox.exists ? checkBox : app.buttons[label]
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// A two-suite project, built at run time: the images only have to be files on disk for
    /// discovery to find them, and the tree is what these tests navigate.
    private static func makeProject() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffUITests-\(UUID().uuidString)")

        let layout = [
            "Package.swift": "// swift-tools-version:6.0",
            "Tests/AlphaTests.swift": "// AlphaTests",
            "Snapshots/AlphaTests/footer.png": "image",
            "Snapshots/AlphaTests/header.png": "image",
            "Snapshots/BetaTests/menu.png": "image",
            "Snapshots/BetaTests/toolbar.png": "image",
        ]

        for (relativePath, contents) in layout {
            let file = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }

        return root
    }
}
