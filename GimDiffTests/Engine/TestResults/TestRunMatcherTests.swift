//
//  TestRunMatcherTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Matching a test run against the project")
struct TestRunMatcherTests {
    private let project = URL(fileURLWithPath: "/repo")
    private let scratch = URL(fileURLWithPath: "/scratch/run/0")
    private let filesystem = MockFilesystemService()

    // MARK: - Fixtures

    /// Stubs a snapshot in the project and returns the suite holding it.
    private func suite(_ name: String, snapshots: [String: String]) -> SnapshotSuite {
        let folder = project.appendingPathComponent("Tests/__Snapshots__/\(name)")
        let items = snapshots.keys.sorted().map { file -> SnapshotItem in
            let url = folder.appendingPathComponent(file)
            filesystem.stub(url, contents: snapshots[file] ?? "")
            return SnapshotItem(name: file, fileURL: url)
        }
        return SnapshotSuite(name: name, snapshotsFolderURL: folder, snapshots: items, providerId: "test")
    }

    /// Stubs an exported attachment. Its name is deliberately unlike anything a snapshot
    /// library writes: nothing the matcher does may depend on it.
    private func image(_ id: String, contents: String) -> TestRunImage {
        let url = scratch.appendingPathComponent("\(id).png")
        filesystem.stub(url, contents: contents)
        return TestRunImage(id: id, name: "attachment \(id)", fileURL: url)
    }

    private func report(
        test: String = "CardsTests/testArtwork()",
        startedAt: Date? = nil,
        groups: [[TestRunImage]]
    ) -> TestRunReport {
        TestRunReport(
            bundleURL: URL(fileURLWithPath: "/Run.xcresult"),
            scratchDirectory: scratch,
            startedAt: startedAt,
            failures: [
                TestRunFailure(
                    id: test,
                    name: "testArtwork()",
                    groups: groups.enumerated().map { index, images in
                        TestRunImageGroup(id: "\(test)#0/\(index)", title: "Step \(index)", images: images)
                    }
                ),
            ]
        )
    }

    private func differences(_ report: TestRunReport, suites: [SnapshotSuite]) throws -> [TestRunDifference] {
        try TestRunMatcher(filesystem: filesystem)
            .differences(in: report, against: ProjectBundle(rootURL: project, suites: suites))
    }

    // MARK: - Tests

    @Test("The image with a snapshot's bytes is its baseline, and the next one attached is the candidate")
    func matchesBaselineByContent() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded", "testOther.png": "other"])
        let images = [
            image("X", contents: "rendered"),
            image("Y", contents: "recorded"),
            image("Z", contents: "drawn difference"),
        ]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.count == 1)
        #expect(found.first?.baseline?.fileURL == cards.snapshots[0].fileURL)
        #expect(found.first?.baseline?.suiteID == cards.id)
        #expect(found.first?.baseline?.snapshotID == cards.snapshots[0].id)
        // Z, attached after the rendering, is a picture of the difference the canvas draws
        // for itself.
        #expect(found.first?.candidates.map(\.id) == ["X"])
        #expect(found.first?.testIdentifier == "CardsTests/testArtwork()")
        #expect(found.first?.title == "Step 0")
    }

    @Test("Every step of a test is its own difference")
    func reportsEveryStep() throws {
        let cards = suite(
            "CardsTests",
            snapshots: ["testArtwork.active.png": "active", "testArtwork.frozen.png": "frozen"]
        )
        let first = [image("A1", contents: "frozen"), image("A2", contents: "frozen, redrawn")]
        let second = [image("B1", contents: "active"), image("B2", contents: "active, redrawn")]

        let found = try differences(report(groups: [first, second]), suites: [cards])

        #expect(
            found.map(\.baseline?.fileURL.lastPathComponent)
                == ["testArtwork.frozen.png", "testArtwork.active.png"]
        )
        #expect(found.map { $0.candidates.map(\.id) } == [["A2"], ["B2"]])
        #expect(Set(found.map(\.id)).count == 2)
    }

    @Test("A step matching nothing in the project is kept, with every image a candidate")
    func keepsUnmatchedStep() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded since the run"])
        let images = [image("X", contents: "stale reference"), image("Y", contents: "rendered")]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.count == 1)
        #expect(found.first?.baseline == nil)
        #expect(found.first?.candidates.map(\.id) == ["X", "Y"])
    }

    @Test("A step that attached the reference alone has nothing to show")
    func dropsBaselineWithNothingToCompare() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded"])

        let found = try differences(report(groups: [[image("X", contents: "recorded")]]), suites: [cards])

        #expect(found.isEmpty)
    }

    @Test("A snapshot of the same length with other contents is not a match")
    func comparesContentsNotLength() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded"])
        let images = [image("X", contents: "rendered"), image("Y", contents: "RECORDED")]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.map(\.baseline) == [nil])
    }

    @Test("A snapshot that has gone from disk is passed over")
    func toleratesMissingSnapshot() throws {
        var cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded"])
        cards.snapshots.append(
            SnapshotItem(name: "deleted", fileURL: project.appendingPathComponent("deleted.png"))
        )
        let images = [image("X", contents: "recorded"), image("Y", contents: "rendered")]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.map(\.baseline?.fileURL) == [cards.snapshots[0].fileURL])
    }

    @Test("Identical snapshots in two suites are told apart by the test that failed")
    func prefersSnapshotNamedAfterTheTest() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "empty state"])
        let settings = suite("SettingsTests", snapshots: ["testSettings.png": "empty state"])
        let images = [image("X", contents: "empty state"), image("Y", contents: "rendered")]

        let found = try differences(report(groups: [images]), suites: [settings, cards])

        #expect(found.map(\.baseline?.suiteID) == [cards.id])
    }

    @Test("Identical snapshots nothing tells apart are all reported")
    func keepsEveryEquallyLikelySnapshot() throws {
        let cards = suite("CardsTests", snapshots: ["light.png": "same", "dark.png": "same"])
        let images = [image("X", contents: "same"), image("Y", contents: "rendered")]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.map(\.baseline?.fileURL.lastPathComponent) == ["dark.png", "light.png"])
        #expect(found.allSatisfy { $0.candidates.map(\.id) == ["Y"] })
        #expect(Set(found.map(\.id)).count == 2)
    }

    @Test("A rendering that equals some other snapshot is still a candidate")
    func keepsCandidateThatEqualsAnotherSnapshot() throws {
        let cards = suite(
            "CardsTests",
            snapshots: ["testArtwork.png": "dark rendering", "testLight.png": "light rendering"]
        )
        // The test for the dark card rendered the light one: both of its images are files
        // the project holds.
        let images = [image("X", contents: "dark rendering"), image("Y", contents: "light rendering")]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.map(\.baseline?.fileURL.lastPathComponent) == ["testArtwork.png"])
        #expect(found.first?.candidates.map(\.id) == ["Y"])
    }

    @Test("A failed test with no images contributes nothing")
    func ignoresTestsWithoutImages() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded"])

        #expect(try differences(report(groups: []), suites: [cards]).isEmpty)
    }

    // MARK: - Staleness

    private static let runStart = Date(timeIntervalSince1970: 10_000)

    @Test("A snapshot unchanged since the run began is matched")
    func matchesSnapshotOlderThanRun() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded"])
        filesystem.setModificationDate(Self.runStart.addingTimeInterval(-60), at: cards.snapshots[0].fileURL)
        let images = [image("X", contents: "recorded"), image("Y", contents: "rendered")]

        let found = try differences(report(startedAt: Self.runStart, groups: [images]), suites: [cards])

        #expect(found.map(\.baseline?.fileURL) == [cards.snapshots[0].fileURL])
    }

    @Test("A step about a snapshot written since the run began has nothing left to say")
    func dropsStepOvertakenByAcceptance() throws {
        // The candidate was accepted: the snapshot now holds what the run rendered, and
        // the run's reference would otherwise come back as the candidate.
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "rendered"])
        filesystem.setModificationDate(Self.runStart.addingTimeInterval(60), at: cards.snapshots[0].fileURL)
        let images = [image("X", contents: "recorded"), image("Y", contents: "rendered")]

        let found = try differences(report(startedAt: Self.runStart, groups: [images]), suites: [cards])

        #expect(found.isEmpty)
    }

    @Test("Without a date for the run, nothing is taken as stale")
    func keepsEverythingWithoutRunDate() throws {
        let cards = suite("CardsTests", snapshots: ["testArtwork.png": "recorded"])
        filesystem.setModificationDate(Self.runStart.addingTimeInterval(60), at: cards.snapshots[0].fileURL)
        let images = [image("X", contents: "recorded"), image("Y", contents: "rendered")]

        let found = try differences(report(groups: [images]), suites: [cards])

        #expect(found.count == 1)
    }
}
