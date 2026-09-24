//
//  GitRepositoryTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Git repository reads")
struct GitRepositoryTests {
    private let directory = URL(fileURLWithPath: "/tmp/repo/Snapshots")

    @Test("Reports the branch reported by git, without surrounding whitespace")
    func readsCurrentBranch() async throws {
        let runner = StubCommandRunner(standardOutput: "feature/curtain-view\n")
        let repository = GitRepository(directory: directory, runner: runner)

        #expect(try await repository.currentBranch() == "feature/curtain-view")
    }

    @Test("Resolves status entries against the working tree root")
    func resolvesChangedPathsAgainstRoot() async throws {
        let runner = StubCommandRunner { command in
            command.arguments.contains("--show-toplevel")
                ? CommandResult(exitCode: 0, standardOutput: "/tmp/repo\n", standardError: "")
                : CommandResult(
                    exitCode: 0,
                    standardOutput: " M Snapshots/home.png\n?? Snapshots/new.png\n",
                    standardError: ""
                )
        }
        let repository = GitRepository(directory: directory, runner: runner)

        let paths = try await repository.changedPaths().map(\.path)

        #expect(paths == ["/tmp/repo/Snapshots/home.png", "/tmp/repo/Snapshots/new.png"])
    }

    @Test("Surfaces git's own message when a command fails")
    func reportsFailureMessage() async throws {
        let runner = StubCommandRunner(
            result: CommandResult(exitCode: 128, standardOutput: "", standardError: "fatal: bad object\n")
        )
        let repository = GitRepository(directory: directory, runner: runner)

        await #expect(throws: GimDiffError.commandFailed(
            command: "git rev-parse",
            exitCode: 128,
            message: "fatal: bad object"
        )) {
            try await repository.currentBranch()
        }
    }

    @Test("A non-zero rev-parse means the folder is outside a repository")
    func reportsMissingRepository() async throws {
        let runner = StubCommandRunner(result: CommandResult(exitCode: 128, standardOutput: "", standardError: ""))
        let repository = GitRepository(directory: directory, runner: runner)

        await #expect(throws: GimDiffError.notARepository(directory)) {
            try await repository.toplevel()
        }
    }

    @Test("Restoring nothing runs no command at all")
    func restoringNothingIsANoOp() async throws {
        let runner = StubCommandRunner(standardOutput: "")
        let repository = GitRepository(directory: directory, runner: runner)

        try await repository.restore(paths: [])

        #expect(runner.recordedCommands.isEmpty)
    }
}

/// A `CommandRunning` double that records what it was asked to run.
private final class StubCommandRunner: CommandRunning, @unchecked Sendable {
    private let respond: @Sendable (Command) -> CommandResult
    private let lock = NSLock()
    private var commands: [Command] = []

    init(respond: @escaping @Sendable (Command) -> CommandResult) {
        self.respond = respond
    }

    convenience init(result: CommandResult) {
        self.init { _ in result }
    }

    convenience init(standardOutput: String) {
        self.init(result: CommandResult(exitCode: 0, standardOutput: standardOutput, standardError: ""))
    }

    var recordedCommands: [Command] {
        lock.withLock { commands }
    }

    func run(_ command: Command) async throws -> CommandResult {
        lock.withLock { commands.append(command) }
        return respond(command)
    }
}
