//
//  TestRunResultsTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Test run results")
struct TestRunResultsTests {
    private let scratch = URL(fileURLWithPath: "/scratch/run")

    private func image(_ id: String) -> TestRunImage {
        TestRunImage(id: id, name: "attachment \(id)", fileURL: scratch.appendingPathComponent("\(id).png"))
    }

    private func difference(
        _ id: String,
        snapshotID: String?,
        candidates: [TestRunImage]
    ) -> TestRunDifference {
        TestRunDifference(
            id: id,
            testIdentifier: "CardsTests/testArtwork()",
            testName: "testArtwork()",
            title: "Step",
            baseline: snapshotID.map {
                TestRunDifference.Baseline(suiteID: "cards", snapshotID: $0, fileURL: URL(fileURLWithPath: $0))
            },
            candidates: candidates
        )
    }

    private func results(_ differences: [TestRunDifference]) -> TestRunResults {
        TestRunResults(bundleURL: URL(fileURLWithPath: "/Run.xcresult"), scratchDirectory: scratch, differences: differences)
    }

    @Test("Looks up the candidates of a failing snapshot, and nothing for any other")
    func looksUpCandidates() {
        let results = results([difference("a", snapshotID: "/active.png", candidates: [image("X"), image("D")])])

        #expect(results.candidates(forSnapshotID: "/active.png").map(\.id) == ["X", "D"])
        #expect(results.isFailing(snapshotID: "/active.png"))
        #expect(!results.isFailing(snapshotID: "/frozen.png"))
        #expect(results.candidates(forSnapshotID: "/frozen.png").isEmpty)
        #expect(results.failedSnapshotsCount == 1)
    }

    @Test("A snapshot asserted twice offers the images of both steps, each once")
    func mergesRepeatedSnapshot() {
        let results = results([
            difference("a", snapshotID: "/active.png", candidates: [image("X")]),
            difference("b", snapshotID: "/active.png", candidates: [image("Y"), image("X")]),
        ])

        #expect(results.candidates(forSnapshotID: "/active.png").map(\.id) == ["X", "Y"])
        #expect(results.failedSnapshotsCount == 1)
    }

    @Test("Differences about no snapshot are kept apart")
    func separatesUnmatched() {
        let results = results([
            difference("a", snapshotID: "/active.png", candidates: [image("X")]),
            difference("b", snapshotID: nil, candidates: [image("N")]),
        ])

        #expect(results.unmatched.map(\.id) == ["b"])
        #expect(results.failedSnapshotsCount == 1)
        #expect(results.image(at: scratch.appendingPathComponent("N.png"))?.name == "attachment N")
    }

    @Test("Resolving a snapshot forgets its failure and nothing else")
    func resolvesOneSnapshot() {
        var results = results([
            difference("a", snapshotID: "/active.png", candidates: [image("X")]),
            difference("b", snapshotID: "/frozen.png", candidates: [image("Y")]),
            difference("c", snapshotID: nil, candidates: [image("N")]),
        ])

        results.resolve(snapshotID: "/active.png")

        #expect(!results.isFailing(snapshotID: "/active.png"))
        #expect(results.isFailing(snapshotID: "/frozen.png"))
        #expect(results.differences.map(\.id) == ["b", "c"])
        #expect(!results.isEmpty)
    }
}
