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

    /// The URL the remote called `name` fetches from, such as `git@github.com:owner/repo.git`.
    func remoteURL(named name: String, repositoryRoot: URL) async throws -> String

    /// Throws away every local change to the files at `fileURLs`, staged or not, leaving
    /// them as `HEAD` holds them.
    func discardChanges(to fileURLs: [URL], repositoryRoot: URL) async throws

    /// Whether Git tracks the file at `fileURL`, or `nil` when Git could not be asked.
    ///
    /// `nil` is kept apart from `false` on purpose: a failure to run git says nothing about
    /// the file, and a caller deciding something from the answer must not read it as one.
    func isTracked(_ fileURL: URL, repositoryRoot: URL) async -> Bool?
}
