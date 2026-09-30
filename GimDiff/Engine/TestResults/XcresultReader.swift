//
//  XcresultReader.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Reads a result bundle through `xcresulttool`.
///
/// Only the structure Xcode records is relied on: the outcome of each test, the steps a
/// test went through, and the files each step attached. Nothing is inferred from what a
/// step or an attachment is called, and whether an attachment is an image is read from its
/// bytes — so a snapshot library GimDiff has never heard of is read the same way as one it
/// has.
struct XcresultReader: TestResultReading {
    /// How `xcresulttool` spells the two values the reader has to recognise.
    static let testCaseNodeType = "Test Case"
    static let failedResult = "Failed"

    private let runner: any CommandRunning
    private let filesystem: any FilesystemService
    private let temporaryRoot: URL

    /// - Parameter temporaryRoot: Folder each report creates its own scratch folder in.
    init(
        runner: any CommandRunning,
        filesystem: any FilesystemService,
        temporaryRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("com.davidgiordana.GimDiff.TestRuns", isDirectory: true)
    ) {
        self.runner = runner
        self.filesystem = filesystem
        self.temporaryRoot = temporaryRoot
    }

    func report(forBundleAt bundle: URL) async throws -> TestRunReport {
        let bundle = bundle.standardizedFileURL
        let tree: TestTree = try await decode(
            XcresultCommand.tests(in: bundle),
            named: "xcresulttool get test-results tests",
            from: bundle
        )

        // A test plan with several configurations lists a test once under each of them,
        // and its activities already cover every run.
        var seen: Set<String> = []
        let failedTests = tree.testNodes
            .flatMap(\.failedTestCases)
            .filter { seen.insert($0.reference).inserted }

        let scratch = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // A run with nothing failed has nothing to date.
        let startedAt = failedTests.isEmpty ? nil : await runStart(of: bundle)

        do {
            var failures: [TestRunFailure] = []
            for (index, test) in failedTests.enumerated() {
                try Task.checkCancellation()
                failures.append(
                    try await failure(
                        of: test,
                        in: bundle,
                        exportingTo: scratch.appendingPathComponent(String(index), isDirectory: true)
                    )
                )
            }
            return TestRunReport(
                bundleURL: bundle,
                scratchDirectory: scratch,
                startedAt: startedAt,
                failures: failures
            )
        } catch {
            try? filesystem.removeItem(at: scratch)
            throw error
        }
    }

    /// When the run started, or `nil` when the summary cannot be read.
    ///
    /// Never an error: the date only lets stale results be recognised, and a report
    /// without one is still a report.
    private func runStart(of bundle: URL) async -> Date? {
        let summary: Summary? = try? await decode(
            XcresultCommand.summary(of: bundle),
            named: "xcresulttool get test-results summary",
            from: bundle
        )
        return summary?.startTime.map(Date.init(timeIntervalSince1970:))
    }

    // MARK: - One test

    private func failure(
        of test: FailedTest,
        in bundle: URL,
        exportingTo directory: URL
    ) async throws -> TestRunFailure {
        let recorded: Activities = try await decode(
            XcresultCommand.activities(ofTest: test.reference, in: bundle),
            named: "xcresulttool get test-results activities",
            from: bundle
        )

        let steps = recorded.testRuns.enumerated().flatMap { run, testRun in
            var claimed: Set<String> = []
            return Self.steps(in: testRun.activities, under: "\(test.identifier)#\(run)", claimed: &claimed)
        }
        guard !steps.isEmpty else {
            return TestRunFailure(id: test.identifier, name: test.name, groups: [])
        }

        _ = try await succeeding(
            XcresultCommand.exportAttachments(ofTest: test.reference, in: bundle, to: directory),
            named: "xcresulttool export attachments"
        )

        // The tool names each exported file after the attachment's identifier, with an
        // extension only when it could tell the type.
        let exported = Dictionary(
            ((try? filesystem.contentsOfDirectory(at: directory)) ?? []).map {
                ($0.deletingPathExtension().lastPathComponent, $0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var kept: Set<String> = []
        let groups = steps.compactMap { step -> TestRunImageGroup? in
            let images = step.attachments.compactMap { attachment -> TestRunImage? in
                guard let file = exported[attachment.uuid], let image = stagedImage(at: file) else {
                    return nil
                }
                kept.insert(image.path)
                return TestRunImage(id: attachment.uuid, name: attachment.name, fileURL: image)
            }
            guard !images.isEmpty else { return nil }
            return TestRunImageGroup(id: step.id, title: step.title, images: images)
        }

        // A UI test attaches screen recordings and event logs too. None of it is shown, and
        // a recording is large enough to be worth not keeping until the report is closed.
        for file in (try? filesystem.contentsOfDirectory(at: directory)) ?? [] where !kept.contains(file.path) {
            try? filesystem.removeItem(at: file)
        }

        return TestRunFailure(id: test.identifier, name: test.name, groups: groups)
    }

    /// The file to show for an exported attachment, or `nil` when it is not an image.
    ///
    /// The rest of GimDiff tells an image by its extension, and an exported attachment
    /// often has none, so an image whose name does not say what it is gets a copy that does.
    private func stagedImage(at file: URL) -> URL? {
        guard let data = try? filesystem.readFile(at: file),
              let format = ImageFormat(sniffing: data)
        else { return nil }
        guard ImageFormat(url: file) != format else { return file }

        let named = file.deletingPathExtension().appendingPathExtension(format.fileExtension)
        guard (try? filesystem.writeFile(at: named, data: data)) != nil else { return nil }
        return named
    }

    // MARK: - Steps

    /// A step of a test that attached something.
    private struct Step {
        var id: String
        var title: String
        var attachments: [(uuid: String, name: String)]
    }

    /// Every step under `activities` with attachments of its own, in the order they ran.
    ///
    /// Xcode repeats an attachment on each step enclosing the one that recorded it. The
    /// innermost step is the one that attached it, so the children are read first and a
    /// parent keeps only what none of them claimed.
    private static func steps(
        in activities: [Activity],
        under path: String,
        claimed: inout Set<String>
    ) -> [Step] {
        var steps: [Step] = []

        for (index, activity) in activities.enumerated() {
            let id = "\(path)/\(index)"
            let nested = Self.steps(in: activity.childActivities ?? [], under: id, claimed: &claimed)

            let own = (activity.attachments ?? []).compactMap { attachment -> (uuid: String, name: String)? in
                guard let uuid = attachment.uuid, claimed.insert(uuid).inserted else { return nil }
                return (uuid, attachment.name ?? uuid)
            }
            if !own.isEmpty {
                steps.append(Step(id: id, title: activity.title ?? "", attachments: own))
            }
            steps.append(contentsOf: nested)
        }

        return steps
    }

    // MARK: - Running the tool

    private func decode<Value: Decodable>(
        _ command: Command,
        named name: String,
        from bundle: URL
    ) async throws -> Value {
        let result = try await succeeding(command, named: name)
        do {
            return try JSONDecoder().decode(Value.self, from: Data(result.standardOutput.utf8))
        } catch {
            throw GimDiffError.unreadableTestResults(bundle)
        }
    }

    /// Runs `command`, turning a non-zero exit into an error carrying the tool's own message.
    private func succeeding(_ command: Command, named name: String) async throws -> CommandResult {
        let result = try await runner.run(command)
        guard result.isSuccess else {
            throw GimDiffError.commandFailed(
                command: name,
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }
}

// MARK: - What xcresulttool prints

/// A failed test, and what to hand `--test-id` to ask about it.
private struct FailedTest {
    var identifier: String
    var name: String
    var reference: String
}

private struct Summary: Decodable {
    /// Seconds since 1970.
    var startTime: Double?
}

private struct TestTree: Decodable {
    var testNodes: [TestNode]
}

private struct TestNode: Decodable {
    var name: String?
    var nodeType: String?
    var result: String?
    var nodeIdentifier: String?
    var nodeIdentifierURL: String?
    var children: [TestNode]?

    /// The test cases at or beneath this node that failed.
    ///
    /// The walk stops at a test case: what sits beneath one is its runs and its failure
    /// messages, and those are read from the activities instead.
    var failedTestCases: [FailedTest] {
        guard nodeType == XcresultReader.testCaseNodeType else {
            return (children ?? []).flatMap(\.failedTestCases)
        }
        guard result == XcresultReader.failedResult,
              let reference = nodeIdentifierURL ?? nodeIdentifier
        else { return [] }

        return [
            FailedTest(
                identifier: nodeIdentifier ?? reference,
                name: name ?? nodeIdentifier ?? reference,
                reference: reference
            ),
        ]
    }
}

private struct Activities: Decodable {
    var testRuns: [TestRun]

    struct TestRun: Decodable {
        var activities: [Activity]
    }
}

private struct Activity: Decodable {
    var title: String?
    var attachments: [Attachment]?
    var childActivities: [Activity]?

    struct Attachment: Decodable {
        var name: String?
        var uuid: String?
    }
}
