//
//  GitHubPRURLParser.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A repository on `github.com`, named the way its URLs name it.
struct GitHubRepository: Equatable, Hashable, Sendable {
    var owner: String
    var name: String
}

/// One pull request on `github.com`.
struct GitHubPRReference: Equatable, Hashable, Sendable {
    var owner: String
    var repo: String
    var pullNumber: Int

    init(owner: String, repo: String, pullNumber: Int) {
        self.owner = owner
        self.repo = repo
        self.pullNumber = pullNumber
    }

    init(repository: GitHubRepository, pullNumber: Int) {
        self.init(owner: repository.owner, repo: repository.name, pullNumber: pullNumber)
    }

    var repository: GitHubRepository { GitHubRepository(owner: owner, name: repo) }

    /// The pull request's page, which is the one spelling every trigger agrees on.
    var webURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = GitHubPRURLParser.host
        components.path = "/\(owner)/\(repo)/pull/\(pullNumber)"
        // Owner and repository names are restricted to URL-safe characters by the pattern
        // that produced them, so the components always assemble.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// `owner/repo#123`, the short form GitHub itself writes in cross-references.
    var shortDescription: String { "\(owner)/\(repo)#\(pullNumber)" }
}

/// Recognises pull requests on `github.com` in whatever form a person hands them over.
///
/// Only `github.com` is understood. An Enterprise host would need its own API base and its
/// own token from `gh`, and guessing at either would send a token somewhere it was not
/// issued for.
enum GitHubPRURLParser {
    static let host = "github.com"

    /// GitHub limits owners to letters, digits, and hyphens, and repositories to those plus
    /// `.` and `_`. Matching the real character sets, rather than "anything but a slash",
    /// is what stops a trailing quote or bracket in a pasted message becoming part of a name.
    private static let ownerPattern = "[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"
    private static let repoPattern = "[A-Za-z0-9._-]+"

    /// A pull request URL anywhere in a run of text, with or without its scheme.
    ///
    /// The lookbehind keeps `notgithub.com/…` and `api.github.com/…` from matching: the
    /// host has to be `github.com` itself, optionally behind `www.`.
    private static let urlPattern =
        #"(?<![\w.-])(?:https?://)?(?:www\.)?github\.com/("#
        + ownerPattern + ")/(" + repoPattern + #")/pull/(\d+)(?!\d)"#

    /// `owner/repo#123`, alone on the line.
    private static let shortPattern = "^(" + ownerPattern + ")/(" + repoPattern + #")#(\d+)$"#

    /// A bare number, with or without GitHub's leading `#`.
    private static let numberPattern = #"^#?(\d+)$"#

    /// The remote spellings Git accepts for a `github.com` repository.
    private static let remotePatterns = [
        #"^(?:https?|git|ssh)://(?:[^@/]+@)?(?:www\.)?github\.com(?::\d+)?/("#
            + ownerPattern + ")/(" + repoPattern + ")/?$",
        "^(?:[^@/]+@)?github\\.com:(" + ownerPattern + ")/(" + repoPattern + ")/?$",
    ]

    /// The first pull request URL in `text`, which may be surrounded by anything.
    ///
    /// This is the clipboard's reading: a link pasted out of a chat message arrives with the
    /// message around it.
    static func reference(in text: String) -> GitHubPRReference? {
        guard let groups = firstMatch(of: urlPattern, in: text) else { return nil }
        return reference(owner: groups[0], repo: groups[1], number: groups[2])
    }

    /// Reads what a person typed into the Open PR field: a URL, `owner/repo#123`, or a
    /// number.
    ///
    /// - Parameter defaultRepository: The repository a bare number belongs to, usually the
    ///   one the open project was cloned from. A number with no repository to put it in is
    ///   not a pull request, so the result is then `nil`.
    static func reference(
        fromInput input: String,
        defaultRepository: GitHubRepository? = nil
    ) -> GitHubPRReference? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let reference = reference(in: trimmed) {
            return reference
        }
        if let groups = firstMatch(of: shortPattern, in: trimmed) {
            return reference(owner: groups[0], repo: groups[1], number: groups[2])
        }
        if let groups = firstMatch(of: numberPattern, in: trimmed),
           let defaultRepository,
           let number = pullNumber(groups[0]) {
            return GitHubPRReference(repository: defaultRepository, pullNumber: number)
        }
        return nil
    }

    /// Whether `input` is a bare pull request number, which needs a repository to mean
    /// anything.
    static func isBareNumber(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return firstMatch(of: numberPattern, in: trimmed) != nil
    }

    /// The repository a Git remote URL points at, when it points at `github.com`.
    ///
    /// Reads the HTTPS, SSH, and scp-like (`git@github.com:owner/repo.git`) spellings.
    static func repository(fromRemoteURL remote: String) -> GitHubRepository? {
        var trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".git") {
            trimmed = String(trimmed.dropLast(".git".count))
        }

        for pattern in remotePatterns {
            if let groups = firstMatch(of: pattern, in: trimmed) {
                return GitHubRepository(owner: groups[0], name: groups[1])
            }
        }
        return nil
    }

    // MARK: - Matching

    private static func reference(owner: String, repo: String, number: String) -> GitHubPRReference? {
        guard let pullNumber = pullNumber(number) else { return nil }
        let repo = repo.hasSuffix(".git") ? String(repo.dropLast(".git".count)) : repo
        return GitHubPRReference(owner: owner, repo: repo, pullNumber: pullNumber)
    }

    /// GitHub numbers pull requests from 1, so `0` is a typo rather than a request.
    private static func pullNumber(_ digits: String) -> Int? {
        guard let number = Int(digits), number > 0 else { return nil }
        return number
    }

    /// The capture groups of the first match, or `nil` when there is none.
    private static func firstMatch(of pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let scanned = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: scanned.length))
        else { return nil }

        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : scanned.substring(with: range)
        }
    }
}
