//
//  PromotionIntegrationTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The promotion actions against a real working tree, a real `git`, and a real volume.
///
/// The unit tests cover the rules; these cover the seam the rules run over. A promotion that
/// leaves the right bytes in the mock and the wrong ones on disk is exactly the failure a
/// double cannot show.
@Suite("Promotion against a real working tree")
@MainActor
struct PromotionIntegrationTests {
    private static let snapshotPath = "Snapshots/HomeTests/home.png"
    private static let committedBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let modifiedBytes = Data(repeating: 0x42, count: 512)

    /// A repository holding one committed snapshot that has since been changed.
    private func repositoryWithAModifiedSnapshot() throws -> (GitFixture, SnapshotItem) {
        let repository = try GitFixture()
        try repository.write(Self.snapshotPath, data: Self.committedBytes)
        try repository.commit()
        try repository.write(Self.snapshotPath, data: Self.modifiedBytes)

        let item = SnapshotItem(
            name: "home",
            fileURL: repository.url.appendingPathComponent(Self.snapshotPath),
            gitStatus: .modified
        )
        return (repository, item)
    }

    private func state(for repository: GitFixture, item: SnapshotItem, defaults: TemporaryDefaults)
        -> AppState
    {
        let state = AppState(watcher: StubProjectWatcher(), defaults: defaults.defaults)
        state.load(ProjectBundle(
            rootURL: repository.url,
            gitRootURL: repository.url,
            suites: [SnapshotSuite(
                name: "HomeTests",
                snapshotsFolderURL: item.fileURL.deletingLastPathComponent(),
                snapshots: [item],
                providerId: "test"
            )]
        ))
        return state
    }

    @Test("Reverting puts the committed bytes back on disk and clears the badge")
    func revertsAModifiedSnapshot() async throws {
        let (repository, item) = try repositoryWithAModifiedSnapshot()
        let defaults = TemporaryDefaults()
        let state = state(for: repository, item: item, defaults: defaults)

        state.showSnapshot(item, withGitDiff: true)
        await state.currentGitDiff?.value

        #expect(state.preview?.isComparison == true)
        #expect(state.preview?.baseline?.origin == .committedVersion)
        // Nothing on disk answers to "the baseline" here, so the promotion is refused.
        #expect(state.canPromoteCandidate == false)

        state.revertCandidateToBaseline()

        #expect(try Data(contentsOf: item.fileURL) == Self.committedBytes)
        #expect(state.lastError == nil)

        await state.currentGitStatusRefresh?.value
        #expect(state.currentProject?.hasGitDiff == false)
    }

    @Test("Discarding puts HEAD back, staged change included, and leaves the image on its own")
    func discardsAModifiedSnapshot() async throws {
        let (repository, item) = try repositoryWithAModifiedSnapshot()
        try repository.stage(Self.snapshotPath)
        try repository.write(Self.snapshotPath, data: Data(repeating: 0x43, count: 256))
        let defaults = TemporaryDefaults()
        let state = state(for: repository, item: item, defaults: defaults)

        state.showSnapshot(item, withGitDiff: true)
        await state.currentGitDiff?.value
        #expect(state.preview?.isComparison == true)

        state.discardGitChanges(of: [item])
        await state.currentDiscard?.value

        #expect(try Data(contentsOf: item.fileURL) == Self.committedBytes)
        #expect(state.lastError == nil)
        #expect(state.preview?.isComparison == false)
        #expect(state.preview?.snapshotID == item.id)

        await state.currentGitStatusRefresh?.value
        #expect(state.currentProject?.hasGitDiff == false)
    }

    @Test("Accepting a candidate overwrites the recorded baseline and keeps both files")
    func promotesOntoARecordedBaseline() throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/home.png", data: Self.committedBytes)
        try repository.write("failures/home.png", data: Self.modifiedBytes)

        let baseline = repository.url.appendingPathComponent("Snapshots/home.png")
        let candidate = repository.url.appendingPathComponent("failures/home.png")

        let defaults = TemporaryDefaults()
        let state = AppState(defaults: defaults.defaults)
        state.showComparison(reference: baseline, failure: candidate)

        #expect(state.canPromoteCandidate)
        state.promoteCandidateToBaseline()

        #expect(try Data(contentsOf: baseline) == Self.modifiedBytes)
        // `replaceFile` consumes its source, so the staging copy is what it was handed.
        #expect(try Data(contentsOf: candidate) == Self.modifiedBytes)
        #expect(state.lastError == nil)
    }
}
