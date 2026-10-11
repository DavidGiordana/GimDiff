//
//  TestRunExportTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// Flattening a read test run into the entries `gimdiff test-run` reports and writes.
@Suite("Test run export")
@MainActor
struct TestRunExportTests {
    private let scratch = URL(fileURLWithPath: "/mock-tmp/run", isDirectory: true)

    private func results(_ differences: [TestRunDifference]) -> TestRunResults {
        TestRunResults(
            bundleURL: URL(fileURLWithPath: "/runs/Test.xcresult"),
            scratchDirectory: scratch,
            differences: differences
        )
    }

    private func image(_ id: String, named name: String) -> TestRunImage {
        TestRunImage(id: id, name: name, fileURL: scratch.appendingPathComponent("\(id).png"))
    }

    private func failure(
        of snapshotName: String,
        in suiteName: String,
        project: ProjectBundle,
        rendered: [TestRunImage]
    ) throws -> TestRunDifference {
        let suite = try #require(project.suites.first { $0.name == suiteName })
        let snapshot = try #require(suite.snapshots.first { $0.name == snapshotName })
        return TestRunDifference(
            id: "\(suiteName)/\(snapshotName)/\(rendered.first?.id ?? "")",
            testIdentifier: "\(suiteName)/test\(snapshotName.capitalized)()",
            testName: "test\(snapshotName.capitalized)()",
            title: "Attached",
            baseline: .init(suiteID: suite.id, snapshotID: snapshot.id, fileURL: snapshot.fileURL),
            candidates: rendered
        )
    }

    @Test("A failure names its suite and snapshot and pairs the snapshot with the rendering")
    func failureEntry() throws {
        let project = AppStateFixture.twoSuites()
        let header = try failure(of: "header", in: "AlphaTests", project: project, rendered: [image("X", named: "failure")])

        let entries = TestRunExport.entries(for: results([header]), in: project)

        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.kind == .failure)
        #expect(entry.suiteName == "AlphaTests")
        #expect(entry.snapshotName == "header")
        #expect(entry.baselineURL == header.baseline?.fileURL)
        #expect(entry.candidateURL == scratch.appendingPathComponent("X.png"))
        #expect(entry.fileStem == "AlphaTests.header")
    }

    @Test("An unmatched step lists every image it attached, named after the test")
    func unmatchedEntries() {
        let difference = TestRunDifference(
            id: "group",
            testIdentifier: "BetaTests/testNew()",
            testName: "testNew()",
            title: "Attached",
            baseline: nil,
            candidates: [image("N1", named: "new screen"), image("N2", named: "new screen dark")]
        )

        let entries = TestRunExport.entries(for: results([difference]), in: AppStateFixture.twoSuites())

        #expect(entries.map(\.kind) == [.unmatched, .unmatched])
        #expect(entries.map(\.fileStem) == ["testNew.new_screen", "testNew.new_screen_dark"])
        #expect(entries.allSatisfy { $0.baselineURL == nil })
    }

    @Test("A snapshot failed twice gets a second set of names rather than overwriting the first")
    func repeatedStemsAreNumbered() throws {
        let project = AppStateFixture.twoSuites()
        let first = try failure(of: "header", in: "AlphaTests", project: project, rendered: [image("X", named: "a")])
        let second = try failure(of: "header", in: "AlphaTests", project: project, rendered: [image("Y", named: "b")])

        let entries = TestRunExport.entries(for: results([first, second]), in: project)

        #expect(entries.map(\.fileStem) == ["AlphaTests.header", "AlphaTests.header-2"])
    }

    @Test("Names differing only in case are told apart, as the volume would not")
    func stemsIgnoreCase() {
        let differences = ["Shot", "shot"].enumerated().map { index, name in
            TestRunDifference(
                id: "g\(index)",
                testIdentifier: "T/test()",
                testName: "test()",
                title: "Attached",
                baseline: nil,
                candidates: [image("I\(index)", named: name)]
            )
        }

        let entries = TestRunExport.entries(for: results(differences), in: AppStateFixture.twoSuites())

        #expect(entries.map(\.fileStem) == ["test.Shot", "test.shot-2"])
    }

    @Test("A file name keeps letters, digits, dashes, and underscores, and nothing else")
    func fileStemsAreSafe() {
        #expect(TestRunExport.fileStem("My Tests", "test/with: (odd) chars") == "My_Tests.test_with_odd_chars")
        #expect(TestRunExport.fileStem("ünïcode-ok_1") == "ünïcode-ok_1")
        #expect(TestRunExport.fileStem("///", "") == "snapshot")
    }

    @Test("A run that failed on nothing exports nothing")
    func emptyRun() {
        #expect(TestRunExport.entries(for: results([]), in: AppStateFixture.twoSuites()).isEmpty)
    }
}
