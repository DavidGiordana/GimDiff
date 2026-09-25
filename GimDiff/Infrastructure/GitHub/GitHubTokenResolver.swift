//
//  GitHubTokenResolver.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Why the GitHub CLI could not supply a token.
enum GitHubCLIAuthError: Error, Equatable {
    /// `gh` is not installed anywhere GimDiff looks for it.
    case notInstalled
    /// `gh` is installed but not logged in to `github.com`.
    case notAuthenticated
}

extension GitHubCLIAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            """
            The GitHub CLI (gh) is not installed. Install it with 'brew install gh', then run \
            'gh auth login' in Terminal to review GitHub PRs.
            """
        case .notAuthenticated:
            "Please run 'gh auth login' in terminal to review GitHub PRs"
        }
    }
}

/// Borrows the token the GitHub CLI is logged in with, by running `gh auth token`.
struct GitHubTokenResolver: GitHubTokenProviding {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/env")
    /// Where Homebrew and the official installer put `gh`.
    ///
    /// An app started from the Finder inherits launchd's `PATH`, which is only the system
    /// directories, so `env` would not find a Homebrew `gh` that every terminal finds.
    static let additionalSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
    /// What `env` exits with when it cannot find the program it was asked to run.
    static let commandNotFoundStatus: Int32 = 127

    private let runner: any CommandRunning
    private let environmentPath: String

    init(
        runner: any CommandRunning = SystemCommandRunner(),
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.runner = runner
        self.environmentPath = environmentPath
    }

    /// `env PATH=… gh auth token --hostname github.com`
    ///
    /// The search path is handed to `env` as an assignment argument rather than through a
    /// shell, so nothing in it is ever interpreted. The hostname is pinned so a machine also
    /// logged in to an Enterprise host still answers with its `github.com` token.
    var command: Command {
        Command(
            executableURL: Self.executableURL,
            arguments: [
                "PATH=\(searchPath)",
                "gh", "auth", "token",
                "--hostname", GitHubPRURLParser.host,
            ]
        )
    }

    func token() async throws -> String {
        let result: CommandResult
        do {
            result = try await runner.run(command)
        } catch {
            throw GitHubCLIAuthError.notInstalled
        }

        if result.exitCode == Self.commandNotFoundStatus {
            throw GitHubCLIAuthError.notInstalled
        }
        guard result.isSuccess, !result.trimmedOutput.isEmpty else {
            throw GitHubCLIAuthError.notAuthenticated
        }
        return result.trimmedOutput
    }

    private var searchPath: String {
        var directories = environmentPath.split(separator: ":").map(String.init)
        for directory in Self.additionalSearchPaths where !directories.contains(directory) {
            directories.append(directory)
        }
        return directories.joined(separator: ":")
    }
}
