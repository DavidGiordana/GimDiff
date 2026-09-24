//
//  GitService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The Git queries GimDiff needs to tell a changed snapshot from a committed one.
protocol GitService: Sendable {
    /// Root of the working tree containing `folderURL`, or `nil` when it is outside one.
    func findRepositoryRoot(for folderURL: URL) async -> URL?

    /// Status of every path Git reports as changed, keyed by absolute URL.
    ///
    /// Paths Git says nothing about are absent from the result rather than mapped to
    /// ``GitFileStatus/unmodified``.
    func status(repositoryRoot: URL) async throws -> [URL: GitFileStatus]

    /// Writes the committed contents of a file to a temporary location and returns it.
    ///
    /// - Parameters:
    ///   - relativePath: Path of the file relative to `repositoryRoot`.
    ///   - gitRef: Commit-ish to read from, such as `HEAD` or a branch name.
    func extractCommittedVersion(
        ofFileAt relativePath: String,
        repositoryRoot: URL,
        gitRef: String
    ) async throws -> URL
}
