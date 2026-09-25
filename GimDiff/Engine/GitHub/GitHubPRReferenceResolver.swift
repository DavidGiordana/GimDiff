//
//  GitHubPRReferenceResolver.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Why typed input could not be read as a pull request.
enum GitHubPRInputError: Error, Equatable {
    /// The text is not a pull request URL, `owner/repo#123`, or a number.
    case unrecognized(String)
    /// A bare number was given with no repository to look it up in.
    case numberNeedsRepository
    /// The repository's `origin` points somewhere other than `github.com`.
    case remoteNotOnGitHub(String)
}

extension GitHubPRInputError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unrecognized(input):
            """
            “\(input)” is not a GitHub pull request. Paste a link such as \
            https://github.com/owner/repo/pull/123, or write owner/repo#123.
            """
        case .numberNeedsRepository:
            """
            A pull request number can only be looked up inside a repository cloned from GitHub. \
            Use the pull request's full link, or owner/repo#123, instead.
            """
        case let .remoteNotOnGitHub(remote):
            "The repository's origin (\(remote)) is not on github.com, so a bare number cannot be looked up."
        }
    }
}

/// Turns what a person typed into the pull request it names.
///
/// A link or `owner/repo#123` stands on its own. A bare number is looked up against the
/// repository the caller is standing in — the open project for the app, the working
/// directory for the command-line tool — by reading where its `origin` points.
struct GitHubPRReferenceResolver: Sendable {
    /// The remote a bare number is resolved against.
    static let remoteName = "origin"

    let gitService: any GitService

    /// - Parameters:
    ///   - repositoryRoot: A folder inside the repository a bare number belongs to.
    ///   - preferredRepository: Consulted before `repositoryRoot`, for a caller that already
    ///     knows which repository is meant, such as one already reviewing a pull request.
    func reference(
        for input: String,
        repositoryRoot: URL?,
        preferredRepository: GitHubRepository? = nil
    ) async throws -> GitHubPRReference {
        if let reference = GitHubPRURLParser.reference(fromInput: input) {
            return reference
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubPRURLParser.isBareNumber(trimmed) else {
            throw GitHubPRInputError.unrecognized(trimmed)
        }

        let repository: GitHubRepository
        if let preferredRepository {
            repository = preferredRepository
        } else {
            repository = try await self.repository(at: repositoryRoot)
        }
        guard let reference = GitHubPRURLParser.reference(fromInput: trimmed, defaultRepository: repository) else {
            throw GitHubPRInputError.unrecognized(trimmed)
        }
        return reference
    }

    private func repository(at root: URL?) async throws -> GitHubRepository {
        guard let root,
              let remote = try? await gitService.remoteURL(named: Self.remoteName, repositoryRoot: root)
        else { throw GitHubPRInputError.numberNeedsRepository }

        guard let repository = GitHubPRURLParser.repository(fromRemoteURL: remote) else {
            throw GitHubPRInputError.remoteNotOnGitHub(remote)
        }
        return repository
    }
}
