//
//  SubtreePruningTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Deletion and subtree pruning")
@MainActor
struct SubtreePruningTests {
    @Test("Deleting a snapshot trashes the file and prunes it from memory")
    func deletesOneSnapshot() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")
        let deleted = try #require(fixture.state.selectedRow?.snapshot)

        fixture.state.deleteSelection()

        #expect(fixture.filesystem.trashedPaths == [deleted.fileURL.path])
        #expect(fixture.rowDescriptions == [
            "AlphaTests",
            "AlphaTests/header",
            "AlphaTests/sidebar",
            "BetaTests",
        ])
        #expect(fixture.state.lastError == nil)
    }

    @Test("The selection moves to the row below the deleted one")
    func movesSelectionDown() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/header")

        fixture.state.deleteSelection()

        #expect(fixture.selectedRowDescription == "AlphaTests/footer")
    }

    @Test("Deleting the last row falls back to the row above it")
    func fallsBackToTheRowAbove() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("BetaTests")
        fixture.select("BetaTests/menu")

        fixture.state.deleteSelection()

        #expect(fixture.selectedRowDescription == "BetaTests/toolbar")
    }

    @Test("Deleting a suite removes its whole subtree in one step")
    func deletesAWholeSuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests")
        let folder = fixture.state.currentProject?.suites.first?.snapshotsFolderURL

        fixture.state.deleteSelection()

        #expect(fixture.filesystem.trashedPaths == [folder?.path].compactMap { $0 })
        #expect(fixture.rowDescriptions == ["BetaTests"])
        #expect(fixture.selectedRowDescription == "BetaTests")
        #expect(fixture.state.expandedSuiteIDs.isEmpty)
    }

    @Test("Deleting the only suite leaves the tree empty and nothing selected")
    func emptiesTheTree() {
        let bundle = ProjectBundle(
            rootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(
                    named: "OnlyTests",
                    hasSourceCode: true,
                    snapshots: [("one", .unmodified)]
                ),
            ]
        )
        let fixture = AppStateFixture(bundle: bundle)
        fixture.select("OnlyTests")

        fixture.state.deleteSelection()

        #expect(fixture.state.visibleRows.isEmpty)
        #expect(fixture.state.selectedRowID == nil)
        #expect(fixture.state.currentProject?.suites.isEmpty == true)
    }

    @Test("Deleting the previewed snapshot closes the preview pane")
    func closesThePreviewOfADeletedSnapshot() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")
        fixture.state.togglePreview()
        #expect(fixture.state.preview != nil)

        fixture.state.deleteSelection()

        #expect(fixture.state.preview == nil)
    }

    @Test("Deleting a suite closes a preview standing on any of its snapshots")
    func closesThePreviewOfADeletedSuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/sidebar")
        fixture.state.togglePreview()

        fixture.select("AlphaTests")
        fixture.state.deleteSelection()

        #expect(fixture.state.preview == nil)
    }

    @Test("A preview of another snapshot survives the deletion")
    func keepsAnUnrelatedPreview() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/header")
        fixture.state.togglePreview()

        fixture.select("AlphaTests/footer")
        fixture.state.deleteSelection()

        #expect(fixture.state.preview?.title == "header")
    }

    @Test("A deletion that fails reports the error and changes nothing")
    func reportsAFailedDeletion() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/footer")
        // Removed behind the state's back, so trashing it fails the way a file someone else
        // has already deleted would.
        let snapshot = try #require(fixture.state.selectedRow?.snapshot)
        try fixture.filesystem.trashFile(at: snapshot.fileURL)

        fixture.state.deleteSelection()

        #expect(fixture.state.lastError != nil)
        #expect(fixture.rowDescriptions.contains("AlphaTests/footer"))
        #expect(fixture.selectedRowDescription == "AlphaTests/footer")
    }

    @Test("A snapshot hidden by a filter is still pruned from the project")
    func prunesRegardlessOfTheFilter() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.showGitModifiedOnly = true
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/header")

        fixture.state.deleteSelection()

        #expect(fixture.state.currentProject?.suites.first?.snapshots.count == 2)
        #expect(fixture.rowDescriptions == ["BetaTests"])
    }
}
