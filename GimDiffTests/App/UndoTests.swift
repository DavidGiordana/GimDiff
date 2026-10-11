//
//  UndoTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// Undo and Redo for every action that writes a snapshot.
@Suite("Undoing file actions")
@MainActor
struct UndoTests {
    /// An undo manager the state can use, grouped by hand: there is no event loop in a test
    /// to open a group per event.
    private func undoManager(for state: AppState) -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        state.undoManager = undoManager
        return undoManager
    }

    private func snapshot(_ name: String, in fixture: AppStateFixture) throws -> SnapshotItem {
        try #require(fixture.state.currentProject?.suites.flatMap(\.snapshots).first { $0.name == name })
    }

    // MARK: - Discard

    @Test("Undoing a discard puts back the change git threw away, and Redo throws it away again")
    func undoesADiscard() async throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let undo = undoManager(for: fixture.state)
        let header = try snapshot("header", in: fixture)
        fixture.filesystem.stub(header.fileURL, contents: "working change")

        fixture.state.discardGitChanges(of: [header])
        await fixture.state.currentDiscard?.value
        // What `git restore` would leave behind; the stub does not touch the file.
        fixture.filesystem.stub(header.fileURL, contents: "committed")

        #expect(undo.canUndo)
        #expect(undo.undoActionName == "Discard Changes")
        undo.undo()
        #expect(fixture.filesystem.contents(of: header.fileURL) == "working change")

        #expect(undo.canRedo)
        undo.redo()
        #expect(fixture.filesystem.contents(of: header.fileURL) == "committed")
    }

    @Test("A discard git refuses leaves nothing to undo")
    func failedDiscardIsNotUndoable() async throws {
        var git = StubGitService()
        git.discardError = .commandFailed(command: "git restore", exitCode: 128, message: "fatal: nope")
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites(), gitService: git)
        let undo = undoManager(for: fixture.state)
        let header = try snapshot("header", in: fixture)

        fixture.state.discardGitChanges(of: [header])
        await fixture.state.currentDiscard?.value

        #expect(!undo.canUndo)
    }

    // MARK: - Trash

    @Test("Undoing a deletion brings the snapshot back out of the Trash, and Redo trashes it again")
    func undoesATrashedSnapshot() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let undo = undoManager(for: fixture.state)
        let footer = try snapshot("footer", in: fixture)
        let suiteID = fixture.suiteID("AlphaTests")

        fixture.state.delete(snapshot: footer, in: suiteID)
        #expect(!fixture.filesystem.fileExists(at: footer.fileURL))
        #expect(undo.undoActionName == "Move Snapshot to Trash")

        undo.undo()
        #expect(fixture.filesystem.contents(of: footer.fileURL) == "png")

        undo.redo()
        #expect(!fixture.filesystem.fileExists(at: footer.fileURL))
    }

    @Test("Undoing a trashed suite brings back the folder and everything in it")
    func undoesATrashedSuite() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let undo = undoManager(for: fixture.state)
        let suite = try #require(fixture.state.currentProject?.suites.first { $0.name == "AlphaTests" })

        fixture.state.delete(suite: suite)
        #expect(suite.snapshots.allSatisfy { !fixture.filesystem.fileExists(at: $0.fileURL) })

        undo.undo()
        #expect(suite.snapshots.allSatisfy { fixture.filesystem.contents(of: $0.fileURL) == "png" })
    }

    // MARK: - Stack

    @Test("Opening another project forgets what could be undone in the last one")
    func loadingForgetsFileUndo() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let undo = undoManager(for: fixture.state)
        let footer = try snapshot("footer", in: fixture)

        fixture.state.delete(snapshot: footer, in: fixture.suiteID("AlphaTests"))
        #expect(undo.canUndo)

        fixture.state.load(AppStateFixture.twoSuites())
        #expect(!undo.canUndo)
    }

    @Test("Without an undo manager nothing is copied aside")
    func noUndoManagerSavesNothing() throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let footer = try snapshot("footer", in: fixture)

        #expect(fixture.state.saveForUndo([footer.fileURL]).isEmpty)
    }

    @Test("A file the action is about to create is remembered as absent")
    func absentFilesAreRemembered() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        // Held, because the state only borrows it.
        let undo = undoManager(for: fixture.state)
        let missing = AppStateFixture.root.appendingPathComponent("Snapshots/New/new.png")

        let saved = withExtendedLifetime(undo) { fixture.state.saveForUndo([missing]) }

        #expect(saved.count == 1)
        #expect(saved.first?.copy == nil)
    }
}
