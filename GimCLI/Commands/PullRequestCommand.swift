//
//  PullRequestCommand.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// `gimdiff pr <url-or-number>`
///
/// Hands a pull request to the running GimDiff window, which downloads its snapshots and
/// shows them for review. The tool only works out which pull request is meant; the fetch
/// happens in the app, where its progress and any failure can be shown.
enum PullRequestCommand {
    static let name = "pr"
    static let summary = "Review the snapshots a GitHub pull request changes."
    static let usage = """
    Usage: gimdiff pr <url-or-number>

      Opens a GitHub pull request for snapshot review in the running GimDiff window.

      <url-or-number>  A pull request link, owner/repo#123, or a bare number. A number is
                       looked up in the repository the current directory belongs to, by
                       reading where its origin remote points.

    Requires the GitHub CLI (gh), logged in with “gh auth login”.
    """

    static let valueOptions: Set<String> = []
    static let knownOptions: Set<String> = []

    static func run(_ arguments: Arguments, console: Console) async throws -> ExitStatus {
        try arguments.rejectOptions(outside: knownOptions)
        try arguments.rejectPositionalArguments(beyond: 1)
        let input = try arguments.argument(at: 0, named: "url-or-number")

        let reference: GitHubPRReference
        do {
            reference = try await GitHubPRReferenceResolver(gitService: DefaultGitService()).reference(
                for: input,
                repositoryRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
        } catch let failure as GitHubPRInputError {
            console.writeError(failure.localizedDescription)
            return .usage
        }

        let url = try url(for: reference)
        try await LaunchCommand.open(url)

        console.write("Opened \(reference.shortDescription) in GimDiff")
        return .success
    }

    /// `gimdiff://open-pr?url=…`, carrying the canonical link whatever form was typed.
    ///
    /// The link rather than the number: the app resolves a bare number against the project
    /// it has open, which need not be the repository this terminal is in.
    static func url(for reference: GitHubPRReference) throws -> URL {
        var components = URLComponents()
        components.scheme = GimDiffURLCommand.scheme
        components.host = GimDiffURLCommand.pullRequestActions[0]
        components.queryItems = [URLQueryItem(name: "url", value: reference.webURL.absoluteString)]

        guard let url = components.url else {
            throw LaunchCommand.LaunchFailure.malformedURL(GimDiffURLCommand.pullRequestActions[0])
        }
        return url
    }
}
