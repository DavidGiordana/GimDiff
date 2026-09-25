//
//  GitHubTokenResolverTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("GitHub CLI token resolution")
struct GitHubTokenResolverTests {
    @Test("Runs gh through env with discrete arguments, never through a shell")
    func buildsCommand() {
        let resolver = GitHubTokenResolver(
            runner: CannedCommandRunner(result: .success(output: "")),
            environmentPath: "/usr/bin:/bin"
        )

        #expect(resolver.command.executableURL.path == "/usr/bin/env")
        #expect(resolver.command.arguments == [
            "PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin",
            "gh", "auth", "token",
            "--hostname", "github.com",
        ])
    }

    @Test("Search paths already present are not repeated")
    func doesNotRepeatSearchPaths() {
        let resolver = GitHubTokenResolver(
            runner: CannedCommandRunner(result: .success(output: "")),
            environmentPath: "/opt/homebrew/bin:/usr/bin"
        )

        #expect(resolver.command.arguments.first == "PATH=/opt/homebrew/bin:/usr/bin:/usr/local/bin")
    }

    @Test("Returns the token gh prints, without its trailing newline")
    func returnsTrimmedToken() async throws {
        let resolver = GitHubTokenResolver(runner: CannedCommandRunner(result: .success(output: "gho_abc123\n")))

        #expect(try await resolver.token() == "gho_abc123")
    }

    @Test("A gh that is not logged in asks for gh auth login")
    func reportsNotAuthenticated() async {
        let resolver = GitHubTokenResolver(runner: CannedCommandRunner(result: CommandResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "no oauth token found for github.com"
        )))

        await #expect(throws: GitHubCLIAuthError.notAuthenticated) {
            try await resolver.token()
        }
        #expect(
            GitHubCLIAuthError.notAuthenticated.localizedDescription
                == "Please run 'gh auth login' in terminal to review GitHub PRs"
        )
    }

    @Test("Empty output is not a token")
    func rejectsEmptyOutput() async {
        let resolver = GitHubTokenResolver(runner: CannedCommandRunner(result: .success(output: "  \n")))

        await #expect(throws: GitHubCLIAuthError.notAuthenticated) {
            try await resolver.token()
        }
    }

    @Test("env's command-not-found status is reported as gh missing")
    func reportsNotInstalled() async {
        let resolver = GitHubTokenResolver(runner: CannedCommandRunner(result: CommandResult(
            exitCode: 127,
            standardOutput: "",
            standardError: "env: gh: No such file or directory"
        )))

        await #expect(throws: GitHubCLIAuthError.notInstalled) {
            try await resolver.token()
        }
    }
}

/// A `CommandRunning` double that answers every command with the same result.
private struct CannedCommandRunner: CommandRunning {
    let result: CommandResult

    func run(_ command: Command) async throws -> CommandResult {
        result
    }
}

private extension CommandResult {
    static func success(output: String) -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: output, standardError: "")
    }
}
