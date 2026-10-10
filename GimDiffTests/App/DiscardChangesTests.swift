//
//  DiscardChangesTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// Putting a changed snapshot back to `HEAD` from the tree, and what the tree does after.
@Suite("Discarding Git changes")
@MainActor
struct DiscardChangesTests {
    private func snapshot(_ name: String, in fixture: AppStateFixture) throws -> SnapshotItem {
        try #require(fixture.state.currentProject?.suites.flatMap(\.snapshots).first { $0.name == name })
    }

    @Test("A modified snapshot is restored through git and loses its badge")
    func discardsAModifiedSnapshot() async throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let header = try snapshot("header", in: fixture)

        #expect(fixture.state.canDiscardGitChanges(of: header))
        fixture.state.discardGitChanges(of: [header])
        await fixture.state.currentDiscard?.value

        #expect(fixture.gitService.discarded.recorded == [header.fileURL])
        #expect(try snapshot("header", in: fixture).gitStatus == .unmodified)
        #expect(fixture.state.lastError == nil)
    }

    @Test("An untracked snapshot has nothing at HEAD to go back to, and is not offered")
    func leavesUntrackedSnapshotsAlone() async throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let toolbar = try snapshot("toolbar", in: fixture)

        #expect(!fixture.state.canDiscardGitChanges(of: toolbar))
        fixture.state.discardGitChanges(of: [toolbar])
        await fixture.state.currentDiscard?.value

        #expect(fixture.gitService.discarded.recorded.isEmpty)
        #expect(try snapshot("toolbar", in: fixture).gitStatus == .untracked)
    }

    @Test("A suite offers only its modified snapshots")
    func discardsASuite() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let alpha = try #require(fixture.state.currentProject?.suites.first { $0.name == "AlphaTests" })
        let beta = try #require(fixture.state.currentProject?.suites.first { $0.name == "BetaTests" })

        #expect(fixture.state.discardableSnapshots(in: alpha).map(\.name) == ["header"])
        #expect(fixture.state.discardableSnapshots(in: beta).isEmpty)

        fixture.select("AlphaTests")
        #expect(fixture.state.discardableSelection.map(\.name) == ["header"])
    }

    @Test("A failing git leaves the badge in place and says why")
    func reportsAFailure() async throws {
        var git = StubGitService()
        git.discardError = .commandFailed(command: "git restore", exitCode: 128, message: "fatal: nope")
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites(), gitService: git)
        let header = try snapshot("header", in: fixture)

        fixture.state.discardGitChanges(of: [header])
        await fixture.state.currentDiscard?.value

        #expect(try snapshot("header", in: fixture).gitStatus == .modified)
        #expect(fixture.state.lastError != nil)
    }

    @Test("With only modified snapshots shown, the selection moves to the neighbour")
    func movesTheSelectionWhenTheRowLeaves() async throws {
        let bundle = AppStateFixture.twoSuites()
        // The status read that follows the discard must still see the untracked snapshot.
        let toolbar = try #require(bundle.suites.flatMap(\.snapshots).first { $0.name == "toolbar" })
        var git = StubGitService()
        git.statuses = [toolbar.fileURL.standardizedFileURL: .untracked]
        let fixture = AppStateFixture(bundle: bundle, gitService: git)
        fixture.state.showGitModifiedOnly = true
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/header")

        fixture.state.discardSelectionGitChanges()
        await fixture.state.currentDiscard?.value
        await fixture.state.currentGitStatusRefresh?.value

        #expect(fixture.rowDescriptions == ["BetaTests"])
        #expect(fixture.selectedRowDescription == "BetaTests")
    }

    // MARK: - The whole project

    /// Changes in both suites: `header` and `menu` modified, `toolbar` untracked.
    private static func changesInBothSuites() -> ProjectBundle {
        ProjectBundle(
            rootURL: AppStateFixture.root,
            gitRootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(
                    named: "AlphaTests",
                    hasSourceCode: true,
                    snapshots: [("header", .modified), ("footer", .unmodified)]
                ),
                AppStateFixture.suite(
                    named: "BetaTests",
                    hasSourceCode: true,
                    snapshots: [("toolbar", .untracked), ("menu", .modified)]
                ),
            ]
        )
    }

    @Test("Discarding all asks first, then restores every modified snapshot of the project")
    func discardsTheWholeProject() async throws {
        let bundle = Self.changesInBothSuites()
        // The status read that follows the discard must still see the untracked snapshot.
        let toolbar = try #require(bundle.suites.flatMap(\.snapshots).first { $0.name == "toolbar" })
        var git = StubGitService()
        git.statuses = [toolbar.fileURL.standardizedFileURL: .untracked]
        let fixture = AppStateFixture(bundle: bundle, gitService: git)
        let header = try snapshot("header", in: fixture)
        let menu = try snapshot("menu", in: fixture)
        #expect(fixture.state.discardableProjectSnapshots.map(\.name) == ["header", "menu"])

        fixture.state.requestDiscardAllGitChanges()

        #expect(fixture.state.isConfirmingDiscardAllGitChanges)
        #expect(fixture.gitService.discarded.recorded.isEmpty)

        fixture.state.discardAllGitChanges()
        await fixture.state.currentDiscard?.value
        await fixture.state.currentGitStatusRefresh?.value

        #expect(!fixture.state.isConfirmingDiscardAllGitChanges)
        #expect(Set(fixture.gitService.discarded.recorded) == [header.fileURL, menu.fileURL])
        #expect(try snapshot("header", in: fixture).gitStatus == .unmodified)
        #expect(try snapshot("menu", in: fixture).gitStatus == .unmodified)
        #expect(try snapshot("toolbar", in: fixture).gitStatus == .untracked)
        #expect(fixture.state.discardableProjectSnapshots.isEmpty)
    }

    @Test("Nothing modified means nothing to confirm")
    func discardAllNeedsAChange() throws {
        let untrackedOnly = ProjectBundle(
            rootURL: AppStateFixture.root,
            gitRootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(named: "BetaTests", hasSourceCode: true, snapshots: [("toolbar", .untracked)]),
            ]
        )
        let fixture = AppStateFixture(bundle: untrackedOnly)

        fixture.state.requestDiscardAllGitChanges()

        #expect(fixture.state.discardableProjectSnapshots.isEmpty)
        #expect(!fixture.state.isConfirmingDiscardAllGitChanges)
    }
}
