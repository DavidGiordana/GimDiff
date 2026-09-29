//
//  VisibleTreeTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Flattened visible tree")
@MainActor
struct VisibleTreeTests {
    @Test("A closed project has no rows")
    func hasNoRowsWithoutAProject() {
        let fixture = AppStateFixture()

        #expect(fixture.state.visibleRows.isEmpty)
    }

    @Test("Suites start closed, showing one row each")
    func showsOnlySuitesWhileClosed() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        #expect(fixture.rowDescriptions == ["AlphaTests", "BetaTests"])
    }

    @Test("An expanded suite's snapshots follow it immediately")
    func interleavesChildrenAfterTheirSuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.expand("AlphaTests")

        #expect(fixture.rowDescriptions == [
            "AlphaTests",
            "AlphaTests/header",
            "AlphaTests/footer",
            "AlphaTests/sidebar",
            "BetaTests",
        ])
    }

    @Test("A single suite is opened on load, because opening it reveals nothing")
    func opensALoneSuite() {
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

        #expect(fixture.rowDescriptions == ["OnlyTests", "OnlyTests/one"])
    }

    @Test("Row identifiers are namespaced by kind and by parent suite")
    func namespacesRowIdentifiers() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")

        let ids = fixture.state.visibleRows.map(\.id)

        #expect(ids[0].hasPrefix("suite:"))
        #expect(ids[1].hasPrefix("snapshot:\(fixture.suiteID("AlphaTests")):"))
        #expect(Set(ids).count == ids.count)
    }

    @Test("A suite reports how many snapshots survived the filters")
    func reportsTheFilteredChildCount() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.showGitModifiedOnly = true

        let counts = fixture.state.visibleRows.compactMap { row -> Int? in
            guard case let .suite(_, _, childCount) = row else { return nil }
            return childCount
        }

        #expect(counts == [1, 1])
    }

    // MARK: - Filtering

    @Test("A query opens the suites that hold a match, without touching the expanded set")
    func aQueryRevealsMatchesWithoutExpanding() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.filterText = "toolbar"

        #expect(fixture.rowDescriptions == ["BetaTests", "BetaTests/toolbar"])
        #expect(fixture.state.expandedSuiteIDs.isEmpty)
    }

    @Test("A query matching a suite name keeps all of that suite's snapshots")
    func aSuiteNameMatchKeepsEveryChild() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.filterText = "alpha"

        #expect(fixture.rowDescriptions == [
            "AlphaTests",
            "AlphaTests/header",
            "AlphaTests/footer",
            "AlphaTests/sidebar",
        ])
    }

    @Test("Matching is case-insensitive and ignores surrounding whitespace")
    func matchesLoosely() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.filterText = "  HEADER "

        #expect(fixture.rowDescriptions == ["AlphaTests", "AlphaTests/header"])
    }

    @Test("The modified filter drops unchanged snapshots and the suites left empty")
    func showsOnlyModifiedSnapshots() {
        let bundle = ProjectBundle(
            rootURL: AppStateFixture.root,
            suites: AppStateFixture.twoSuites().suites + [
                AppStateFixture.suite(
                    named: "GammaTests",
                    hasSourceCode: true,
                    snapshots: [("clean", .unmodified)]
                ),
            ]
        )
        let fixture = AppStateFixture(bundle: bundle)

        fixture.state.showGitModifiedOnly = true
        fixture.expand("AlphaTests")

        #expect(fixture.rowDescriptions == ["AlphaTests", "AlphaTests/header", "BetaTests"])
    }

    @Test("The warnings filter keeps only suites whose test source is missing")
    func showsOnlySuitesWithWarnings() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.showWarningsOnly = true

        #expect(fixture.rowDescriptions == ["BetaTests"])
    }

    @Test("Status filters and the query narrow together")
    func combinesTheQueryWithTheStatusFilters() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        fixture.state.showGitModifiedOnly = true
        fixture.state.filterText = "menu"

        #expect(fixture.rowDescriptions.isEmpty)
        #expect(fixture.state.isFiltering)
    }

    @Test("Both status filters are offered when the project has something for each to keep")
    func offersApplicableFilters() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())

        #expect(fixture.state.canFilterByGitChanges)
        #expect(fixture.state.canFilterByWarnings)
    }

    @Test("A clean project with every source found offers neither status filter")
    func hidesFiltersWithNothingToKeep() {
        let bundle = ProjectBundle(
            rootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(
                    named: "AlphaTests",
                    hasSourceCode: true,
                    snapshots: [("header", .unmodified)]
                ),
            ]
        )
        let fixture = AppStateFixture(bundle: bundle)

        #expect(fixture.state.canFilterByGitChanges == false)
        #expect(fixture.state.canFilterByWarnings == false)
    }

    @Test("A status filter that is on stays offered, so it can be turned off")
    func keepsAnActiveFilterOffered() {
        let bundle = ProjectBundle(
            rootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(
                    named: "AlphaTests",
                    hasSourceCode: true,
                    snapshots: [("header", .unmodified)]
                ),
            ]
        )
        let fixture = AppStateFixture(bundle: bundle)

        fixture.state.showGitModifiedOnly = true
        fixture.state.showWarningsOnly = true

        #expect(fixture.state.canFilterByGitChanges)
        #expect(fixture.state.canFilterByWarnings)
    }

    @Test("Clearing the filters restores every row")
    func clearingFiltersRestoresTheTree() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.state.filterText = "nothing matches this"
        fixture.state.showGitModifiedOnly = true
        fixture.state.showWarningsOnly = true

        fixture.state.clearFilters()

        #expect(fixture.state.isFiltering == false)
        #expect(fixture.rowDescriptions == ["AlphaTests", "BetaTests"])
    }
}
