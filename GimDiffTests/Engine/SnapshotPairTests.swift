//
//  SnapshotPairTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Snapshot pairing")
struct SnapshotPairTests {
    @Test("Matches references to failures by file name across different folders")
    func matchesAcrossFolders() {
        let pairs = SnapshotPair.matching(
            references: [
                URL(fileURLWithPath: "/tmp/__Snapshots__/home.png"),
                URL(fileURLWithPath: "/tmp/__Snapshots__/settings.png"),
            ],
            failures: [URL(fileURLWithPath: "/tmp/__Failures__/settings.png")]
        )

        #expect(pairs.count == 1)
        #expect(pairs.first?.name == "settings")
        #expect(pairs.first?.failure.url.path == "/tmp/__Failures__/settings.png")
    }

    @Test("Drops references that have no failure image")
    func dropsUnmatchedReferences() {
        let pairs = SnapshotPair.matching(
            references: [URL(fileURLWithPath: "/tmp/refs/home.png")],
            failures: []
        )

        #expect(pairs.isEmpty)
    }

    @Test("Drops failures that have no reference image")
    func dropsUnmatchedFailures() {
        let pairs = SnapshotPair.matching(
            references: [],
            failures: [URL(fileURLWithPath: "/tmp/fails/home.png")]
        )

        #expect(pairs.isEmpty)
    }

    @Test("Preserves the order the references were given in")
    func preservesReferenceOrder() {
        let names = ["c.png", "a.png", "b.png"]

        let pairs = SnapshotPair.matching(
            references: names.map { URL(fileURLWithPath: "/tmp/refs/\($0)") },
            failures: names.map { URL(fileURLWithPath: "/tmp/fails/\($0)") }
        )

        #expect(pairs.map(\.name) == ["c", "a", "b"])
    }

    @Test("Tags each side of the pair with its role")
    func tagsEachSide() {
        let pair = SnapshotPair(
            reference: URL(fileURLWithPath: "/tmp/refs/home.png"),
            failure: URL(fileURLWithPath: "/tmp/fails/home.png")
        )

        #expect(pair.reference.kind == .reference)
        #expect(pair.failure.kind == .failure)
    }
}
