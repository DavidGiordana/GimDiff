//
//  PaparazziFailuresTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Paparazzi failures as a test run")
struct PaparazziFailuresTests {
    private let filesystem = DefaultFilesystemService()
    private let now = Date()

    /// Two modules: `app` verified by Paparazzi 2 into a variant folder, `feature` by 1.3
    /// straight into `failures`, an hour earlier. Every image holds different bytes, so a
    /// match can only be the right one.
    private func failingProject() throws -> ProjectFixture {
        let fixture = try ProjectFixture()
        let images = "app/src/test/snapshots/images/"
        let failures = "app/build/paparazzi/failures/debug/"

        try fixture.write("app/src/test/kotlin/com/example/LaunchViewTest.kt", contents: "// tests")
        try write(images + "com.example_LaunchViewTest_pixel5.png", "recorded pixel5", in: fixture, at: -120)
        try write(images + "com.example_LaunchViewTest_dark.png", "recorded dark", in: fixture, at: -120)
        try write(failures + "com.example_LaunchViewTest_pixel5.png", "rendered pixel5", in: fixture, at: 0)
        try write(failures + "delta-com.example_LaunchViewTest_pixel5.png", "delta", in: fixture, at: 0)
        try write(failures + "com.example_LaunchViewTest_brandNew.png", "rendered new", in: fixture, at: 0)

        try write(
            "feature/src/test/snapshots/images/com.example.feature_CardTest_card.png",
            "recorded card",
            in: fixture,
            at: -7200
        )
        try write(
            "feature/build/paparazzi/failures/com.example.feature_CardTest_card.png",
            "rendered card",
            in: fixture,
            at: -3600
        )
        return fixture
    }

    private func write(_ path: String, _ contents: String, in fixture: ProjectFixture, at offset: TimeInterval) throws {
        let url = try fixture.write(path, contents: contents)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(offset)], ofItemAtPath: url.path)
    }

    private func project(of fixture: ProjectFixture) async throws -> ProjectBundle {
        let suites = try await PaparazziProvider().discoverSuites(in: fixture.url, filesystem: filesystem)
        return ProjectBundle(rootURL: fixture.url, suites: suites)
    }

    private func reader(scratch: TemporaryDirectory) -> PaparazziFailureReader {
        PaparazziFailureReader(filesystem: filesystem, temporaryRoot: scratch.url)
    }

    private func contents(of url: URL) throws -> String {
        String(decoding: try filesystem.readFile(at: url), as: UTF8.self)
    }

    // MARK: - Locating

    @Test("Every module's failures, in any variant, are one run dated by its newest rendering")
    func locatesOneRun() async throws {
        let fixture = try failingProject()
        let project = try await project(of: fixture)

        let bundles = PaparazziFailureLocator(filesystem: filesystem).resultBundles(for: project)

        let bundle = try #require(bundles.first)
        #expect(bundles.count == 1)
        #expect(bundle.workspaceName == "Paparazzi")
        // Resolved, because a listed folder can come back spelled through /private.
        #expect(bundle.failureFolders.map { $0.resolvingSymlinksInPath().path }.sorted() == [
            fixture.fileURL("app/build/paparazzi/failures/debug").resolvingSymlinksInPath().path,
            fixture.fileURL("feature/build/paparazzi/failures").resolvingSymlinksInPath().path,
        ])
        let newest = try #require(bundle.createdAt)
        #expect(abs(newest.timeIntervalSince(now)) < 1)
    }

    @Test("A project whose failures hold only deltas, or nothing, has no run")
    func noRenderingsNoRun() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("app/src/test/snapshots/images/com.example_LaunchViewTest_pixel5.png")
        try fixture.write("app/build/paparazzi/failures/delta-com.example_LaunchViewTest_pixel5.png")
        try fixture.write("app/build/paparazzi/failures/debug/.keep")
        let project = try await project(of: fixture)

        #expect(PaparazziFailureLocator(filesystem: filesystem).resultBundles(for: project).isEmpty)
    }

    @Test("Watches each module's Paparazzi output, or its build folder until there is one")
    func watchesOutputFolders() async throws {
        let fixture = try failingProject()
        try fixture.write("third/src/test/snapshots/images/com.example_ThirdTest_one.png")
        try fixture.write("third/build/tmp/marker")
        try fixture.write("fourth/src/test/snapshots/images/com.example_FourthTest_one.png")
        let project = try await project(of: fixture)

        let directories = PaparazziFailureLocator(filesystem: filesystem).resultDirectories(for: project)

        #expect(directories.map(\.standardizedFileURL.path).sorted() == [
            fixture.fileURL("app/build/paparazzi").path,
            fixture.fileURL("feature/build/paparazzi").path,
            fixture.fileURL("third/build").path,
        ])
    }

    // MARK: - Reading and matching

    @Test("Each rendering is the candidate of the snapshot it was compared with")
    func pairsRenderingsWithSnapshots() async throws {
        let fixture = try failingProject()
        let project = try await project(of: fixture)
        let scratch = try TemporaryDirectory()
        let bundle = try #require(PaparazziFailureLocator(filesystem: filesystem).resultBundles(for: project).first)

        let report = try await reader(scratch: scratch).report(for: bundle)
        let differences = try TestRunMatcher(filesystem: filesystem).differences(in: report, against: project)

        let matched = differences.filter { $0.baseline != nil }
        #expect(Set(matched.compactMap(\.baseline?.fileURL.lastPathComponent)) == [
            "com.example_LaunchViewTest_pixel5.png",
            "com.example.feature_CardTest_card.png",
        ])
        let pixel5 = try #require(matched.first { $0.baseline?.fileURL.lastPathComponent.contains("pixel5") == true })
        #expect(pixel5.candidates.count == 1)
        #expect(try contents(of: pixel5.candidates[0].fileURL) == "rendered pixel5")
        #expect(pixel5.candidates[0].fileURL.path.hasPrefix(scratch.url.path))
        #expect(pixel5.testName == "LaunchViewTest.pixel5")
    }

    @Test("A rendering with no recorded snapshot is listed on its own")
    func listsUnrecordedRenderings() async throws {
        let fixture = try failingProject()
        let project = try await project(of: fixture)
        let scratch = try TemporaryDirectory()
        let bundle = try #require(PaparazziFailureLocator(filesystem: filesystem).resultBundles(for: project).first)

        let report = try await reader(scratch: scratch).report(for: bundle)
        let results = TestRunResults(
            report: report,
            differences: try TestRunMatcher(filesystem: filesystem).differences(in: report, against: project)
        )

        #expect(results.unmatched.flatMap(\.candidates).map(\.name) == ["Rendered"])
        #expect(try results.unmatched.flatMap(\.candidates).map { try contents(of: $0.fileURL) } == ["rendered new"])
    }

    @Test("A snapshot recorded again after its rendering is no longer offered")
    func dropsSnapshotsRecordedSince() async throws {
        let fixture = try failingProject()
        try write(
            "app/src/test/snapshots/images/com.example_LaunchViewTest_pixel5.png",
            "recorded pixel5",
            in: fixture,
            at: 60
        )
        let project = try await project(of: fixture)
        let scratch = try TemporaryDirectory()
        let bundle = try #require(PaparazziFailureLocator(filesystem: filesystem).resultBundles(for: project).first)

        let report = try await reader(scratch: scratch).report(for: bundle)
        let differences = try TestRunMatcher(filesystem: filesystem).differences(in: report, against: project)

        // The card's module was verified an hour before the app's snapshot was recorded,
        // and still counts: each failure is dated by its own rendering.
        #expect(differences.compactMap(\.baseline?.fileURL.lastPathComponent) == ["com.example.feature_CardTest_card.png"])
    }

    @Test("A failures folder passed by path is read with its variant folders")
    func readsAFolderByPath() async throws {
        let fixture = try failingProject()
        let scratch = try TemporaryDirectory()

        let report = try await reader(scratch: scratch)
            .report(forBundleAt: fixture.fileURL("app/build/paparazzi/failures"))

        #expect(report.failures.map(\.name).sorted() == ["LaunchViewTest.brandNew", "LaunchViewTest.pixel5"])
    }

    // MARK: - Combined sources

    @Test("Runs of both kinds are offered together, newest first")
    func combinesLocatorsNewestFirst() {
        let older = TestRunBundle(url: URL(fileURLWithPath: "/a.xcresult"), createdAt: now.addingTimeInterval(-60), workspaceName: "App")
        let newer = TestRunBundle(
            url: URL(fileURLWithPath: "/project"),
            createdAt: now,
            workspaceName: "Paparazzi",
            failureFolders: [URL(fileURLWithPath: "/project/app/build/paparazzi/failures")]
        )
        let undated = TestRunBundle(url: URL(fileURLWithPath: "/b.xcresult"), createdAt: nil, workspaceName: "App")
        let locator = CombinedTestResultLocator([
            FixedLocator(bundles: [undated, older]),
            FixedLocator(bundles: [newer]),
        ])

        let bundles = locator.resultBundles(for: ProjectBundle(rootURL: URL(fileURLWithPath: "/project")))

        #expect(bundles.map(\.url) == [newer.url, older.url, undated.url])
    }

    @Test("A run is read by the reader that understands it")
    func routesReads() async throws {
        let reader = CombinedTestResultReader(xcode: NamedReader(name: "xcode"), paparazzi: NamedReader(name: "paparazzi"))
        let xcresult = URL(fileURLWithPath: "/Run.xcresult")
        let failures = URL(fileURLWithPath: "/app/build/paparazzi/failures")

        #expect(try await reader.report(forBundleAt: xcresult).failures.first?.id == "xcode")
        #expect(try await reader.report(forBundleAt: failures).failures.first?.id == "paparazzi")
        #expect(try await reader.report(
            for: TestRunBundle(url: URL(fileURLWithPath: "/project"), createdAt: nil, workspaceName: "Paparazzi", failureFolders: [failures])
        ).failures.first?.id == "paparazzi")
        #expect(try await reader.report(
            for: TestRunBundle(url: xcresult, createdAt: nil, workspaceName: "App")
        ).failures.first?.id == "xcode")
    }
}

private struct FixedLocator: TestResultLocating {
    let bundles: [TestRunBundle]

    func resultBundles(forProjectAt rootURL: URL, gitRootURL: URL?) -> [TestRunBundle] { bundles }
    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] { [] }
}

/// Answers with a single failure named after itself, so a test can tell who was asked.
private struct NamedReader: TestResultReading {
    let name: String

    func report(forBundleAt bundle: URL) async throws -> TestRunReport {
        TestRunReport(
            bundleURL: bundle,
            scratchDirectory: bundle,
            failures: [TestRunFailure(id: name, name: name, groups: [])]
        )
    }
}
