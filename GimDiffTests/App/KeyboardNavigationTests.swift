//
//  KeyboardNavigationTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Keyboard navigation")
@MainActor
struct KeyboardNavigationTests {
    @Test("Right arrow opens a closed suite")
    func rightArrowExpands() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("AlphaTests")

        #expect(fixture.state.expandOrDescend())

        #expect(fixture.state.isExpanded(suiteWithID: fixture.suiteID("AlphaTests")))
        #expect(fixture.selectedRowDescription == "AlphaTests")
    }

    @Test("Right arrow on an open suite steps into its first snapshot")
    func rightArrowDescends() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests")

        #expect(fixture.state.expandOrDescend())

        #expect(fixture.selectedRowDescription == "AlphaTests/header")
    }

    @Test("Right arrow on a snapshot is passed back to the list")
    func rightArrowIgnoresSnapshots() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/header")

        #expect(fixture.state.expandOrDescend() == false)
    }

    @Test("Right arrow on an open but empty suite does nothing")
    func rightArrowStopsAtAnEmptySuite() {
        let bundle = ProjectBundle(
            rootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(named: "EmptyTests", hasSourceCode: true, snapshots: []),
                AppStateFixture.suite(
                    named: "OtherTests",
                    hasSourceCode: true,
                    snapshots: [("one", .unmodified)]
                ),
            ]
        )
        let fixture = AppStateFixture(bundle: bundle)
        fixture.expand("EmptyTests")
        fixture.select("EmptyTests")

        #expect(fixture.state.expandOrDescend() == false)
        #expect(fixture.selectedRowDescription == "EmptyTests")
    }

    @Test("Left arrow jumps a snapshot up to its suite")
    func leftArrowAscends() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/sidebar")

        #expect(fixture.state.collapseOrAscend())

        #expect(fixture.selectedRowDescription == "AlphaTests")
    }

    @Test("Left arrow closes an open suite")
    func leftArrowCollapses() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests")

        #expect(fixture.state.collapseOrAscend())

        #expect(fixture.state.isExpanded(suiteWithID: fixture.suiteID("AlphaTests")) == false)
        #expect(fixture.rowDescriptions == ["AlphaTests", "BetaTests"])
    }

    @Test("Left arrow on a closed suite is passed back to the list")
    func leftArrowIgnoresAClosedSuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("AlphaTests")

        #expect(fixture.state.collapseOrAscend() == false)
    }

    @Test("Both arrows do nothing when nothing is selected")
    func arrowsNeedASelection() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.selectedRowID = nil

        #expect(fixture.state.expandOrDescend() == false)
        #expect(fixture.state.collapseOrAscend() == false)
    }

    @Test("Walking down and back up returns to the suite it started from")
    func descendingAndAscendingAreSymmetric() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("BetaTests")

        fixture.state.expandOrDescend()
        fixture.state.expandOrDescend()
        #expect(fixture.selectedRowDescription == "BetaTests/toolbar")

        fixture.state.collapseOrAscend()
        fixture.state.collapseOrAscend()

        #expect(fixture.selectedRowDescription == "BetaTests")
        #expect(fixture.rowDescriptions == ["AlphaTests", "BetaTests"])
    }

    @Test("Space previews the selected snapshot, and closes the pane on a second press")
    func spaceTogglesThePreview() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")

        fixture.state.togglePreview()
        #expect(fixture.state.canvas.preview?.snapshotID != nil)
        #expect(fixture.state.canvas.preview?.title == "footer")

        fixture.state.togglePreview()
        #expect(fixture.state.canvas.preview == nil)
    }

    @Test("Moving the selection onto a snapshot shows it")
    func selectingASnapshotPreviewsIt() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        let rowID = fixture.rowID("AlphaTests/footer")

        fixture.state.selectRow(withID: rowID)

        #expect(fixture.selectedRowDescription == "AlphaTests/footer")
        #expect(fixture.state.canvas.preview?.title == "footer")
    }

    @Test("Moving the selection onto a suite leaves the canvas alone")
    func selectingASuiteKeepsThePreview() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/footer"))

        fixture.state.selectRow(withID: fixture.rowID("BetaTests"))

        #expect(fixture.state.canvas.preview?.title == "footer")
    }

    @Test("Right arrow into a snapshot shows it")
    func descendingPreviewsTheSnapshot() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("BetaTests")
        fixture.select("BetaTests")

        fixture.state.expandOrDescend()

        #expect(fixture.state.canvas.preview?.title == "toolbar")
    }

    @Test("Space on a suite row opens and closes the suite instead")
    func spaceTogglesASuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("AlphaTests")

        fixture.state.togglePreview()
        #expect(fixture.rowDescriptions.contains("AlphaTests/header"))

        fixture.state.togglePreview()
        #expect(fixture.rowDescriptions == ["AlphaTests", "BetaTests"])
    }

    @Test("Return reports the suites whose test source could not be found")
    func returnExplainsAMissingTestSource() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.select("BetaTests")

        fixture.state.openTestSource()

        #expect(fixture.state.lastError?.contains("BetaTests") == true)
    }

    @Test("Focus requests are counted, so asking twice moves focus twice")
    func focusRequestsAccumulate() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.focusFilter()
        fixture.state.focusFilter()
        fixture.state.focusTree()

        #expect(fixture.state.filterFocusRequests == 2)
        #expect(fixture.state.treeFocusRequests == 1)
    }

    @Test("Handing focus to the tree selects the first row the filter left")
    func selectsTheFirstMatchOnHandoff() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.filterText = "toolbar"

        fixture.state.selectFirstVisibleRow()

        #expect(fixture.selectedRowDescription == "BetaTests")
    }

    @Test("Find brings a collapsed sidebar back, so the search box is there to type in")
    func findReopensTheSidebar() {
        let fixture = AppStateFixture()
        fixture.state.collapseSidebar()

        fixture.state.focusFilter()

        #expect(fixture.state.isSidebarVisible)
        #expect(fixture.state.filterFocusRequests == 1)
    }

    @Test("The sidebar commands drive its visibility")
    func sidebarCommandsToggleVisibility() {
        let fixture = AppStateFixture()

        fixture.state.collapseSidebar()
        #expect(fixture.state.isSidebarVisible == false)

        fixture.state.expandSidebar()
        #expect(fixture.state.isSidebarVisible)
    }

    // MARK: - Stepping through changes

    @Test("Next Change opens a closed suite and lands on its changed snapshot")
    func nextChangeOpensTheSuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        #expect(fixture.selectedRowDescription == "AlphaTests")

        fixture.state.selectNextChange()

        #expect(fixture.selectedRowDescription == "AlphaTests/header")
        #expect(fixture.state.isExpanded(suiteWithID: fixture.suiteID("AlphaTests")))
        #expect(fixture.state.canvas.preview?.snapshotID == fixture.state.selectedSnapshot?.id)
    }

    @Test("Next Change skips unchanged snapshots and wraps round at the bottom")
    func nextChangeWraps() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.selectNextChange()
        fixture.state.selectNextChange()
        #expect(fixture.selectedRowDescription == "BetaTests/toolbar")

        fixture.state.selectNextChange()
        #expect(fixture.selectedRowDescription == "AlphaTests/header")
    }

    @Test("Previous Change from the top wraps round to the last change")
    func previousChangeWraps() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.selectPreviousChange()
        #expect(fixture.selectedRowDescription == "BetaTests/toolbar")

        fixture.state.selectPreviousChange()
        #expect(fixture.selectedRowDescription == "AlphaTests/header")
    }

    @Test("Stepping keeps to what the filter field shows")
    func steppingFollowsTheQuery() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.filterText = "tool"

        fixture.state.selectNextChange()
        fixture.state.selectNextChange()

        #expect(fixture.selectedRowDescription == "BetaTests/toolbar")
    }

    @Test("A project with no changes has nothing to step to")
    func nothingToStepTo() {
        let fixture = AppStateFixture(bundle: ProjectBundle(
            rootURL: AppStateFixture.root,
            gitRootURL: AppStateFixture.root,
            suites: [AppStateFixture.suite(named: "CleanTests", hasSourceCode: true, snapshots: [
                ("one", .unmodified), ("two", .unmodified),
            ])]
        ))
        let before = fixture.state.selectedRowID

        #expect(!fixture.state.canStepThroughChanges)
        fixture.state.selectNextChange()
        #expect(fixture.state.selectedRowID == before)
    }

    @Test("A single change already selected leaves nothing to step to")
    func onlyChangeSelected() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.filterText = "header"
        fixture.state.selectNextChange()

        #expect(fixture.selectedRowDescription == "AlphaTests/header")
        #expect(!fixture.state.canStepThroughChanges)
    }
}
