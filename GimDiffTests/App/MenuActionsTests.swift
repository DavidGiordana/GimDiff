//
//  MenuActionsTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The selection-driven state the Snapshot menu enables its items and names them from.
@Suite("Menu bar actions")
@MainActor
struct MenuActionsTests {
    @Test("A suite row names the suite and has no snapshot")
    func suiteSelection() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("BetaTests")

        #expect(fixture.state.selectedRowName == "BetaTests")
        #expect(fixture.state.selectedSnapshot == nil)
        #expect(fixture.state.selectedSuite?.name == "BetaTests")
    }

    @Test("A snapshot row names the snapshot and resolves its suite")
    func snapshotSelection() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")

        #expect(fixture.state.selectedRowName == "footer")
        #expect(fixture.state.selectedSnapshot?.name == "footer")
        #expect(fixture.state.selectedSuite?.name == "AlphaTests")
    }

    @Test("Nothing selected leaves every selection property empty")
    func noSelection() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        // Loading a project selects its first row, so the empty selection is made by hand.
        fixture.state.selectedRowID = nil

        #expect(fixture.state.selectedRowName == nil)
        #expect(fixture.state.selectedSnapshot == nil)
        #expect(fixture.state.selectedSuite == nil)
        #expect(fixture.state.isShowingSelectedSnapshot == false)
    }

    @Test("Showing the selected snapshot puts it on the canvas, which flips Show to Hide")
    func showsTheSelectedSnapshot() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")
        #expect(fixture.state.isShowingSelectedSnapshot == false)

        fixture.state.showSelectedSnapshot(withGitDiff: false)

        #expect(fixture.state.canvas.preview?.snapshotID == fixture.state.selectedSnapshot?.id)
        #expect(fixture.state.isShowingSelectedSnapshot)
    }

    @Test("Showing with a suite selected leaves the canvas alone")
    func showIgnoresSuites() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("AlphaTests")

        fixture.state.showSelectedSnapshot(withGitDiff: true)

        #expect(fixture.state.canvas.preview == nil)
    }

    @Test("The project view names the show actions after the Git diff")
    func showActionTitles() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")

        #expect(fixture.state.compareActionTitle(for: fixture.state.selectedSnapshot) == "Show Snapshot with Git Diff")
        #expect(fixture.state.showAloneActionTitle == "Show Snapshot without Git Diff")
    }

    @Test("Zoom commands apply only while an image is on screen")
    func zoomNeedsAnImage() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")
        #expect(fixture.state.canvas.hasZoomableImages == false)

        fixture.state.showSelectedSnapshot(withGitDiff: false)

        #expect(fixture.state.canvas.hasZoomableImages)
        #expect(fixture.state.canvas.showsOnionSkin == false)
    }

    @Test("Repeating a canvas command is still a new request")
    func canvasRequestsAreNumbered() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.canvas.requestView(.zoomIn)
        let first = try #require(fixture.state.canvas.viewRequest)
        fixture.state.canvas.requestView(.zoomIn)
        let second = try #require(fixture.state.canvas.viewRequest)

        #expect(first.command == .zoomIn)
        #expect(second.command == .zoomIn)
        #expect(first != second)
    }
}
