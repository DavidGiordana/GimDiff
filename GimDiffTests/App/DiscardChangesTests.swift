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

    @Test("An added snapshot is not at HEAD either, and is not offered")
    func leavesAddedSnapshotsAlone() async throws {
        var bundle = AppStateFixture.twoSuites()
        let suiteIndex = try #require(bundle.suites.firstIndex { $0.snapshots.contains { $0.name == "toolbar" } })
        let snapshotIndex = try #require(bundle.suites[suiteIndex].snapshots.firstIndex { $0.name == "toolbar" })
        bundle.suites[suiteIndex].snapshots[snapshotIndex].gitStatus = .added
        let fixture = AppStateFixture(bundle: bundle)
        let toolbar = try snapshot("toolbar", in: fixture)

        #expect(toolbar.hasGitDiff)
        #expect(!fixture.state.canDiscardGitChanges(of: toolbar))
        fixture.state.discardGitChanges(of: [toolbar])
        await fixture.state.currentDiscard?.value

        #expect(fixture.gitService.discarded.recorded.isEmpty)
        #expect(try snapshot("toolbar", in: fixture).gitStatus == .added)
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

    /// A fixture whose stub git reports the project's changes, with every file on disk.
    private func projectWithChanges(statuses extra: [URL: GitFileStatus] = [:]) -> AppStateFixture {
        let bundle = Self.changesInBothSuites()
        var git = StubGitService()
        for snapshot in bundle.suites.flatMap(\.snapshots) where snapshot.gitStatus != .unmodified {
            git.statuses[snapshot.fileURL.standardizedFileURL] = snapshot.gitStatus
        }
        git.statuses.merge(extra) { _, new in new }
        let fixture = AppStateFixture(bundle: bundle, gitService: git)
        for snapshot in bundle.suites.flatMap(\.snapshots) {
            fixture.filesystem.stub(snapshot.fileURL, contents: "\(snapshot.name) on disk")
        }
        return fixture
    }

    private static var deletedSnapshot: URL {
        AppStateFixture.root.appendingPathComponent("Snapshots/BetaTests/gone.png")
    }

    @Test("Discarding all asks first, saying what comes back and what goes to the Trash")
    func asksWithTheCounts() async throws {
        let fixture = projectWithChanges(statuses: [Self.deletedSnapshot: .deleted])

        fixture.state.requestDiscardAllGitChanges()
        await fixture.state.currentDiscard?.value

        #expect(fixture.state.isConfirmingDiscardAllGitChanges)
        #expect(fixture.state.headRestorePlan?.committedURLs.count == 3)
        #expect(fixture.state.headRestorePlan?.trashedURLs.count == 1)
        #expect(fixture.gitService.discarded.recorded.isEmpty)
    }

    @Test("Discarding all leaves every snapshot as HEAD holds it")
    func restoresTheWholeProject() async throws {
        let fixture = projectWithChanges(statuses: [Self.deletedSnapshot: .deleted])
        let header = try snapshot("header", in: fixture)
        let menu = try snapshot("menu", in: fixture)
        let toolbar = try snapshot("toolbar", in: fixture)

        fixture.state.discardAllGitChanges()
        await fixture.state.currentDiscard?.value

        #expect(!fixture.state.isConfirmingDiscardAllGitChanges)
        #expect(Set(fixture.gitService.discarded.recorded) == [header.fileURL, menu.fileURL, Self.deletedSnapshot])
        #expect(!fixture.filesystem.fileExists(at: toolbar.fileURL))
        #expect(!fixture.state.currentProject!.suites.flatMap(\.snapshots).contains { $0.id == toolbar.id })
        #expect(fixture.state.lastError == nil)
    }

    @Test("A staged snapshot is trashed before git restores, never deleted by it")
    func trashesStagedSnapshots() async throws {
        let staged = AppStateFixture.root.appendingPathComponent("Snapshots/BetaTests/toolbar.png")
        let fixture = projectWithChanges(statuses: [staged: .added])

        fixture.state.discardAllGitChanges()
        await fixture.state.currentDiscard?.value

        #expect(!fixture.filesystem.fileExists(at: staged))
        #expect(fixture.filesystem.trashedPaths.contains(staged.standardizedFileURL.path))
        // Handed to git as well, which takes it out of the index.
        #expect(fixture.gitService.discarded.recorded.contains(staged))
    }

    @Test("Discard All is undone in one step")
    func undoesInOneStep() async throws {
        let fixture = projectWithChanges(statuses: [Self.deletedSnapshot: .deleted])
        let undo = UndoManager()
        undo.groupsByEvent = false
        fixture.state.undoManager = undo
        let header = try snapshot("header", in: fixture)
        let toolbar = try snapshot("toolbar", in: fixture)

        fixture.state.discardAllGitChanges()
        await fixture.state.currentDiscard?.value
        // What `git restore` would leave behind.
        fixture.filesystem.stub(header.fileURL, contents: "header committed")
        fixture.filesystem.stub(Self.deletedSnapshot, contents: "gone committed")

        #expect(undo.canUndo)
        undo.undo()

        #expect(fixture.filesystem.fileExists(at: toolbar.fileURL))
        #expect(try fixture.filesystem.readFile(at: header.fileURL) == Data("header on disk".utf8))
        #expect(!fixture.filesystem.fileExists(at: Self.deletedSnapshot))
        #expect(!undo.canUndo)
    }

    @Test("A file that cannot be trashed stops the restore before git runs")
    func stopsWhenTheTrashFails() async throws {
        let fixture = projectWithChanges()
        // Gone from disk, so the untracked snapshot cannot be moved to the Trash.
        try fixture.filesystem.removeItem(at: try snapshot("toolbar", in: fixture).fileURL)

        fixture.state.discardAllGitChanges()
        await fixture.state.currentDiscard?.value

        #expect(fixture.gitService.discarded.recorded.isEmpty)
        #expect(fixture.state.lastError != nil)
    }

    @Test("A project matching HEAD has nothing to confirm")
    func discardAllNeedsAChange() async throws {
        let clean = ProjectBundle(
            rootURL: AppStateFixture.root,
            gitRootURL: AppStateFixture.root,
            suites: [
                AppStateFixture.suite(named: "BetaTests", hasSourceCode: true, snapshots: [("toolbar", .unmodified)]),
            ]
        )
        let fixture = AppStateFixture(bundle: clean)

        #expect(!fixture.state.projectHasGitChanges)
        fixture.state.requestDiscardAllGitChanges()
        await fixture.state.currentDiscard?.value

        #expect(!fixture.state.isConfirmingDiscardAllGitChanges)
        #expect(fixture.state.lastError == String(localized: "Every snapshot already matches the committed version."))
    }
}
