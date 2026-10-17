//
//  SystemCommandRunnerTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Process execution")
struct SystemCommandRunnerTests {
    private let runner = SystemCommandRunner()

    @Test("Captures standard output and a success status")
    func capturesStandardOutput() async throws {
        let result = try await runner.run(Command(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        ))

        #expect(result.isSuccess)
        #expect(result.trimmedOutput == "hello")
    }

    @Test("Captures standard error and a non-zero status separately")
    func capturesStandardError() async throws {
        let result = try await runner.run(Command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo oops >&2; exit 3"]
        ))

        #expect(result.exitCode == 3)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines) == "oops")
    }

    @Test("Arguments reach the process verbatim, with no shell interpretation")
    func argumentsAreNotInterpretedByAShell() async throws {
        // A shell would expand these; passed as discrete arguments they arrive untouched.
        let hostile = "$(whoami); rm -rf * && echo 'quoted'"

        let result = try await runner.run(Command(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: [hostile]
        ))

        #expect(result.trimmedOutput == hostile)
    }

    @Test("Runs in the requested working directory")
    func honoursWorkingDirectory() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL

        let result = try await runner.run(Command(
            executableURL: URL(fileURLWithPath: "/bin/pwd"),
            arguments: [],
            workingDirectory: directory
        ))

        #expect(URL(fileURLWithPath: result.trimmedOutput).standardizedFileURL == directory)
    }

    @Test("Cancelling the task terminates the process instead of waiting it out",
          .timeLimit(.minutes(1)))
    func cancellationTerminatesTheProcess() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let run = Task {
            try await runner.run(Command(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]))
        }
        try await Task.sleep(for: .milliseconds(300))

        run.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await run.value
        }
        #expect(clock.now - start < .seconds(10))
    }

    @Test("A task cancelled before its command starts never starts it")
    func cancellationBeforeLaunchStartsNothing() async throws {
        // A marker the process would create if it ran at all.
        let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gimdiff-never-\(UUID().uuidString)")
        let run = Task {
            try await runner.run(Command(executableURL: URL(fileURLWithPath: "/usr/bin/touch"), arguments: [marker.path]))
        }
        run.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await run.value
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("A command that cannot be launched fails instead of hanging", .timeLimit(.minutes(1)))
    func failedLaunchThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await runner.run(Command(executableURL: URL(fileURLWithPath: "/nonexistent/tool")))
        }
    }

    @Test("Output larger than a pipe buffer is read in full without deadlocking",
          .timeLimit(.minutes(1)))
    func readsOutputLargerThanThePipeBuffer() async throws {
        // Both pipes must be drained concurrently; 256 KB on each comfortably exceeds the
        // 64 KB kernel buffer that would otherwise stall the child process.
        let result = try await runner.run(Command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes 0123456789 | head -c 262144; yes abcdefghij | head -c 262144 >&2"]
        ))

        #expect(result.isSuccess)
        #expect(result.standardOutput.count == 262_144)
        #expect(result.standardError.count == 262_144)
    }

    @Test("Reports a failure when the executable does not exist")
    func reportsMissingExecutable() async {
        await #expect(throws: (any Error).self) {
            try await runner.run(Command(
                executableURL: URL(fileURLWithPath: "/nonexistent/gimdiff-not-a-tool"),
                arguments: []
            ))
        }
    }
}
