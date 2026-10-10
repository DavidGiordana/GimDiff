//
//  StubGitService.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
@testable import GimDiff

/// A `GitService` double that answers from canned values instead of spawning git.
struct StubGitService: GitService {
    /// Root returned for any folder, or `nil` to act as though nothing is under version control.
    var repositoryRoot: URL?
    /// Statuses returned by ``status(repositoryRoot:)``.
    var statuses: [URL: GitFileStatus] = [:]
    /// When true, reading status fails the way an unreadable repository would.
    var statusFails = false
    /// URL returned for every remote, or `nil` to act as though the repository has none.
    var remoteURL: String?
    /// Files ``isTracked(_:repositoryRoot:)`` answers `true` for.
    var trackedFiles: Set<URL> = []
    /// When true, ``isTracked(_:repositoryRoot:)`` cannot answer, as when git fails to run.
    var trackingFails = false

    func isTracked(_ fileURL: URL, repositoryRoot: URL) async -> Bool? {
        guard !trackingFails else { return nil }
        return trackedFiles.contains(fileURL.standardizedFileURL)
    }

    func findRepositoryRoot(for folderURL: URL) async -> URL? {
        repositoryRoot
    }

    func status(repositoryRoot: URL) async throws -> [URL: GitFileStatus] {
        if statusFails { throw GimDiffError.notARepository(repositoryRoot) }
        return statuses
    }

    func extractCommittedVersion(
        ofFileAt relativePath: String,
        repositoryRoot: URL,
        gitRef: String
    ) async throws -> URL {
        throw GimDiffError.commandFailed(
            command: "git show",
            exitCode: 128,
            message: "StubGitService does not extract files"
        )
    }

    func remoteURL(named name: String, repositoryRoot: URL) async throws -> String {
        guard let remoteURL else {
            throw GimDiffError.commandFailed(
                command: "git remote get-url",
                exitCode: 2,
                message: "error: No such remote '\(name)'"
            )
        }
        return remoteURL
    }
}
