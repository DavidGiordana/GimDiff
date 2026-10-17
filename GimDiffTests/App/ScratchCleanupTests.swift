//
//  ScratchCleanupTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import Testing
@testable import GimDiff

/// An `ImageDiffService` double that draws a fresh mask for every comparison, as the real
/// one does, so a test can see the last one deleted.
private struct FreshMaskImageDiffService: ImageDiffService {
    let filesystem: MockFilesystemService

    func compare(
        candidateURL: URL,
        baselineURL: URL,
        diffColor: CGColor,
        tolerance: DiffTolerance
    ) async throws -> ImageDiffReport {
        let mask = filesystem.createTemporaryFile(prefix: "mask", extension: "png")
        filesystem.stub(mask, contents: "mask")
        return ImageDiffReport(
            candidateSize: CGSize(width: 10, height: 10),
            baselineSize: CGSize(width: 10, height: 10),
            hasIdenticalDimensions: true,
            differentPixelCount: 1,
            totalPixelCount: 100,
            diffPercentage: 1,
            diffMaskURL: mask
        )
    }
}

/// The scratch files the window stops needing are deleted as it stops needing them.
@Suite("Scratch cleanup during a session")
@MainActor
struct ScratchCleanupTests {
    @Test("A new measurement deletes the mask of the one it replaces, and leaving the pair deletes the last")
    func deletesReplacedMasks() async throws {
        let defaults = TemporaryDefaults()
        let filesystem = MockFilesystemService()
        let candidate = URL(fileURLWithPath: "/Projects/Demo/failures/header.png")
        let baseline = URL(fileURLWithPath: "/Projects/Demo/Snapshots/header.png")
        filesystem.stub(candidate, contents: "candidate")
        filesystem.stub(baseline, contents: "baseline")
        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            imageDiff: FreshMaskImageDiffService(filesystem: filesystem),
            watcher: StubProjectWatcher(),
            defaults: defaults.defaults
        )
        state.canvas.showComparison(reference: baseline, failure: candidate)
        state.canvas.diffMode = .difference

        state.canvas.updateDiffReport()
        await state.canvas.currentDiffComparison?.value
        let first = try #require(state.canvas.diffReport?.diffMaskURL)

        state.canvas.diffTolerance = DiffTolerance(maximumDeltaE: 5)
        await state.canvas.currentDiffComparison?.value
        let second = try #require(state.canvas.diffReport?.diffMaskURL)

        #expect(first != second)
        #expect(!filesystem.fileExists(at: first))
        #expect(filesystem.fileExists(at: second))

        state.canvas.close()
        #expect(!filesystem.fileExists(at: second))
    }

    @Test("The committed version of a snapshot is deleted once the canvas moves on")
    func deletesTheCommittedVersion() async throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/home.png", data: Data([0x01]))
        try repository.commit()
        try repository.write("Snapshots/home.png", data: Data([0x02]))
        let defaults = TemporaryDefaults()
        let canvas = CanvasModel(
            imageDiff: StubImageDiffService(),
            gitService: DefaultGitService(),
            filesystem: DefaultFilesystemService(),
            defaults: defaults.defaults
        )
        let snapshot = SnapshotItem(
            name: "home",
            fileURL: repository.url.appendingPathComponent("Snapshots/home.png"),
            gitStatus: .modified
        )

        canvas.showWithCommittedVersion(snapshot, gitRoot: repository.url)
        await canvas.currentGitDiff?.value
        let committed = try #require(canvas.preview?.baseline?.fileURL)
        #expect(canvas.preview?.baseline?.origin == .committedVersion)
        #expect(FileManager.default.fileExists(atPath: committed.path))

        canvas.close()

        #expect(!FileManager.default.fileExists(atPath: committed.path))
        // The working file is the user's, never the canvas's to delete.
        #expect(FileManager.default.fileExists(atPath: snapshot.fileURL.path))
    }

    @Test("Undo copies are deleted when the undo stack that would read them is dropped")
    func deletesUndoCopies() async throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let undo = UndoManager()
        undo.groupsByEvent = false
        fixture.state.undoManager = undo
        let header = try #require(fixture.state.currentProject?.suites.flatMap(\.snapshots).first { $0.name == "header" })
        fixture.filesystem.stub(header.fileURL, contents: "header edited")

        fixture.state.discardGitChanges(of: [header])
        await fixture.state.currentDiscard?.value
        let copies = fixture.state.undoCopies
        #expect(copies.count == 1)
        #expect(copies.allSatisfy(fixture.filesystem.fileExists(at:)))

        fixture.state.forgetFileUndo()

        #expect(fixture.state.undoCopies.isEmpty)
        #expect(!copies.contains(where: fixture.filesystem.fileExists(at:)))
        #expect(fixture.filesystem.fileExists(at: header.fileURL))
    }
}
