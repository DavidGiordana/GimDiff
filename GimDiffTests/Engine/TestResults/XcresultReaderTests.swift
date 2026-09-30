//
//  XcresultReaderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Result bundle reading")
struct XcresultReaderTests {
    private let bundle = URL(fileURLWithPath: "/DerivedData/App-hash/Logs/Test/Run.xcresult")
    private let temporaryRoot = URL(fileURLWithPath: "/scratch", isDirectory: true)

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x02])

    private static let tests = """
    {"testNodes":[{"name":"Plan","nodeType":"Test Plan","result":"Failed","children":[
      {"name":"AppTests","nodeType":"Unit test bundle","result":"Failed","children":[
        {"name":"CardsTests","nodeType":"Test Suite","result":"Failed","children":[
          {"name":"testArtwork()","nodeType":"Test Case","result":"Failed",
           "nodeIdentifier":"CardsTests/testArtwork()",
           "nodeIdentifierURL":"test://com.apple.xcode/App/AppTests/CardsTests/testArtwork",
           "children":[{"name":"failed","nodeType":"Failure Message","result":"Failed"}]},
          {"name":"testPasses()","nodeType":"Test Case","result":"Passed",
           "nodeIdentifier":"CardsTests/testPasses()",
           "nodeIdentifierURL":"test://com.apple.xcode/App/AppTests/CardsTests/testPasses"}
        ]}
      ]}
    ]}]}
    """

    /// Two steps that each attach three files, a failure that attaches only text, and one
    /// attachment repeated on the step enclosing the one that recorded it.
    private static let activities = """
    {"testIdentifier":"CardsTests/testArtwork()","testName":"testArtwork()","testRuns":[{"activities":[
      {"title":"First","attachments":[
        {"name":"expected","uuid":"A1"},{"name":"got","uuid":"A2"},{"name":"notes","uuid":"A3"}]},
      {"title":"It failed","attachments":[{"name":"Description.txt","uuid":"T1"}]},
      {"title":"Outer","attachments":[{"name":"screen","uuid":"B1"}],"childActivities":[
        {"title":"Inner","attachments":[{"name":"screen","uuid":"B1"}]}]}
    ]}]}
    """

    private func makeReader(
        filesystem: MockFilesystemService,
        exporting files: [String: Data],
        tests: String = XcresultReaderTests.tests,
        activities: String = XcresultReaderTests.activities
    ) -> (XcresultReader, StubCommandRunner) {
        let runner = StubCommandRunner { command in
            if command.arguments.contains("tests") {
                return .success(tests)
            }
            if command.arguments.contains("activities") {
                return .success(activities)
            }
            if command.arguments.contains("summary") {
                return .success(#"{"startTime":1790782828.5,"result":"Failed"}"#)
            }
            // The real tool writes into the folder it is given; the stub does the same.
            if let flag = command.arguments.firstIndex(of: "--output-path") {
                let directory = URL(fileURLWithPath: command.arguments[flag + 1], isDirectory: true)
                for (name, data) in files {
                    filesystem.stub(directory.appendingPathComponent(name), data: data)
                }
            }
            return .success("")
        }
        let reader = XcresultReader(runner: runner, filesystem: filesystem, temporaryRoot: temporaryRoot)
        return (reader, runner)
    }

    @Test("Asks xcresulttool through xcrun with discrete arguments")
    func buildsCommands() async throws {
        let filesystem = MockFilesystemService()
        let (reader, runner) = makeReader(filesystem: filesystem, exporting: ["A1": Self.png])

        let report = try await reader.report(forBundleAt: bundle)
        let commands = runner.recordedCommands
        let testID = "test://com.apple.xcode/App/AppTests/CardsTests/testArtwork"

        #expect(commands.allSatisfy { $0.executableURL.path == "/usr/bin/xcrun" })
        #expect(commands.map(\.arguments) == [
            ["xcresulttool", "get", "test-results", "tests", "--path", bundle.path, "--compact"],
            ["xcresulttool", "get", "test-results", "summary", "--path", bundle.path, "--compact"],
            [
                "xcresulttool", "get", "test-results", "activities",
                "--path", bundle.path, "--test-id", testID, "--compact",
            ],
            [
                "xcresulttool", "export", "attachments",
                "--path", bundle.path,
                "--output-path", report.scratchDirectory.appendingPathComponent("0").path,
                "--test-id", testID,
            ],
        ])
    }

    @Test("Only failed test cases are reported")
    func reportsFailedTestsOnly() async throws {
        let filesystem = MockFilesystemService()
        let (reader, _) = makeReader(filesystem: filesystem, exporting: ["A1": Self.png])

        let report = try await reader.report(forBundleAt: bundle)

        #expect(report.bundleURL == bundle)
        #expect(report.failures.map(\.id) == ["CardsTests/testArtwork()"])
        #expect(report.failures.map(\.name) == ["testArtwork()"])
    }

    @Test("The report is dated by when the run started")
    func readsRunStart() async throws {
        let filesystem = MockFilesystemService()
        let (reader, _) = makeReader(filesystem: filesystem, exporting: ["A1": Self.png])

        let report = try await reader.report(forBundleAt: bundle)

        #expect(report.startedAt == Date(timeIntervalSince1970: 1_790_782_828.5))
    }

    @Test("A summary that cannot be read leaves the report undated rather than failing it")
    func toleratesUnreadableSummary() async throws {
        let filesystem = MockFilesystemService()
        let runner = StubCommandRunner { command in
            if command.arguments.contains("tests") { return .success(Self.tests) }
            if command.arguments.contains("activities") { return .success(Self.activities) }
            if command.arguments.contains("summary") {
                return CommandResult(exitCode: 1, standardOutput: "", standardError: "unsupported")
            }
            return .success("")
        }
        let reader = XcresultReader(runner: runner, filesystem: filesystem, temporaryRoot: temporaryRoot)

        let report = try await reader.report(forBundleAt: bundle)

        #expect(report.startedAt == nil)
        #expect(report.failures.count == 1)
    }

    @Test("Images are grouped by the step that attached them, under the names they were given")
    func groupsImagesByStep() async throws {
        let filesystem = MockFilesystemService()
        let (reader, _) = makeReader(
            filesystem: filesystem,
            exporting: ["A1": Self.png, "A2": Self.jpeg, "A3.txt": Data("notes".utf8), "B1": Self.png]
        )

        let groups = try #require(try await reader.report(forBundleAt: bundle).failures.first).groups

        #expect(groups.map(\.title) == ["First", "Inner"])
        #expect(groups.map { $0.images.map(\.name) } == [["expected", "got"], ["screen"]])
        #expect(groups.map { $0.images.map(\.id) } == [["A1", "A2"], ["B1"]])
    }

    @Test("An image is told by its bytes and given the extension its name lacked")
    func namesImagesByContent() async throws {
        let filesystem = MockFilesystemService()
        let (reader, _) = makeReader(
            filesystem: filesystem,
            exporting: ["A1": Self.png, "A2.dat": Self.jpeg, "A3.png": Data("not an image".utf8)]
        )

        let report = try await reader.report(forBundleAt: bundle)
        let images = try #require(report.failures.first?.groups.first).images
        let directory = report.scratchDirectory.appendingPathComponent("0")

        #expect(images.map(\.fileURL.lastPathComponent) == ["A1.png", "A2.jpg"])
        #expect(try filesystem.readFile(at: directory.appendingPathComponent("A1.png")) == Self.png)
        #expect(try filesystem.readFile(at: directory.appendingPathComponent("A2.jpg")) == Self.jpeg)
    }

    @Test("Nothing but the images stays in the scratch folder")
    func removesEverythingElse() async throws {
        let filesystem = MockFilesystemService()
        let (reader, _) = makeReader(
            filesystem: filesystem,
            exporting: [
                "A1": Self.png,
                "A2.png": Self.png,
                "T1.txt": Data("failed".utf8),
                "manifest.json": Data("[]".utf8),
            ]
        )

        let report = try await reader.report(forBundleAt: bundle)
        let directory = report.scratchDirectory.appendingPathComponent("0")

        #expect(try filesystem.contentsOfDirectory(at: directory).map(\.lastPathComponent) == ["A1.png", "A2.png"])
    }

    @Test("A failed test with no attachments is reported without exporting anything")
    func skipsExportWithoutAttachments() async throws {
        let filesystem = MockFilesystemService()
        let (reader, runner) = makeReader(
            filesystem: filesystem,
            exporting: [:],
            activities: #"{"testRuns":[{"activities":[{"title":"XCTAssertEqual failed"}]}]}"#
        )

        let report = try await reader.report(forBundleAt: bundle)

        #expect(report.failures.map(\.groups) == [[]])
        #expect(!runner.recordedCommands.contains { $0.arguments.contains("export") })
    }

    @Test("A run with nothing failed reads as an empty report")
    func reportsNothingForPassingRun() async throws {
        let filesystem = MockFilesystemService()
        let (reader, runner) = makeReader(
            filesystem: filesystem,
            exporting: [:],
            tests: #"{"testNodes":[{"name":"testPasses()","nodeType":"Test Case","result":"Passed"}]}"#
        )

        #expect(try await reader.report(forBundleAt: bundle).failures.isEmpty)
        #expect(runner.recordedCommands.count == 1)
    }

    @Test("Surfaces the tool's own message when it fails")
    func reportsToolFailure() async {
        let runner = StubCommandRunner { _ in
            CommandResult(exitCode: 1, standardOutput: "", standardError: "Error: not a result bundle\n")
        }
        let reader = XcresultReader(runner: runner, filesystem: MockFilesystemService(), temporaryRoot: temporaryRoot)

        await #expect(throws: GimDiffError.commandFailed(
            command: "xcresulttool get test-results tests",
            exitCode: 1,
            message: "Error: not a result bundle"
        )) {
            try await reader.report(forBundleAt: bundle)
        }
    }

    @Test("Output that is not the expected report is an unreadable bundle")
    func rejectsUnexpectedOutput() async {
        let runner = StubCommandRunner { _ in .success("<html>") }
        let reader = XcresultReader(runner: runner, filesystem: MockFilesystemService(), temporaryRoot: temporaryRoot)

        await #expect(throws: GimDiffError.unreadableTestResults(bundle)) {
            try await reader.report(forBundleAt: bundle)
        }
    }

    @Test("A failure part-way through leaves no scratch folder behind")
    func cleansUpAfterFailure() async {
        let filesystem = MockFilesystemService()
        let runner = StubCommandRunner { command in
            if command.arguments.contains("tests") { return .success(Self.tests) }
            if command.arguments.contains("activities") { return .success(Self.activities) }
            if let flag = command.arguments.firstIndex(of: "--output-path") {
                let directory = URL(fileURLWithPath: command.arguments[flag + 1], isDirectory: true)
                filesystem.stub(directory.appendingPathComponent("A1"), data: Self.png)
            }
            return CommandResult(exitCode: 1, standardOutput: "", standardError: "disk full")
        }
        let reader = XcresultReader(runner: runner, filesystem: filesystem, temporaryRoot: temporaryRoot)

        await #expect(throws: GimDiffError.self) {
            try await reader.report(forBundleAt: bundle)
        }
        #expect(filesystem.removedPaths.count == 1)
        #expect(filesystem.files.isEmpty)
    }
}

private final class StubCommandRunner: CommandRunning, @unchecked Sendable {
    private let respond: @Sendable (Command) -> CommandResult
    private let lock = NSLock()
    private var commands: [Command] = []

    init(respond: @escaping @Sendable (Command) -> CommandResult) {
        self.respond = respond
    }

    var recordedCommands: [Command] {
        lock.withLock { commands }
    }

    func run(_ command: Command) async throws -> CommandResult {
        lock.withLock { commands.append(command) }
        return respond(command)
    }
}

private extension CommandResult {
    static func success(_ output: String) -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: output, standardError: "")
    }
}
