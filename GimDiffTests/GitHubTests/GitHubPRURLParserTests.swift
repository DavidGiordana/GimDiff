//
//  GitHubPRURLParserTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("GitHub pull request URL parsing")
struct GitHubPRURLParserTests {
    private let expected = GitHubPRReference(owner: "davidgiordana", repo: "GimDiff", pullNumber: 123)

    @Test(
        "Reads the owner, repository, and number out of a pull request link",
        arguments: [
            "https://github.com/davidgiordana/GimDiff/pull/123",
            "http://github.com/davidgiordana/GimDiff/pull/123",
            "github.com/davidgiordana/GimDiff/pull/123",
            "https://www.github.com/davidgiordana/GimDiff/pull/123",
            "https://github.com/davidgiordana/GimDiff/pull/123/files",
            "https://github.com/davidgiordana/GimDiff/pull/123/files#diff-abc",
            "https://github.com/davidgiordana/GimDiff/pull/123?notification_referrer_id=1",
            "https://github.com/davidgiordana/GimDiff/pull/123#issuecomment-99",
        ]
    )
    func parsesPullRequestLinks(_ link: String) {
        #expect(GitHubPRURLParser.reference(in: link) == expected)
    }

    @Test("Finds a link inside a surrounding message")
    func findsLinkInProse() {
        let message = "Could you look at the snapshots in <https://github.com/davidgiordana/GimDiff/pull/123>?"

        #expect(GitHubPRURLParser.reference(in: message) == expected)
    }

    @Test("Keeps dots, underscores, and hyphens in repository names")
    func keepsRepositoryPunctuation() {
        let reference = GitHubPRURLParser.reference(in: "https://github.com/some-org/my_app.ios/pull/7")

        #expect(reference == GitHubPRReference(owner: "some-org", repo: "my_app.ios", pullNumber: 7))
    }

    @Test(
        "Rejects links that are not a pull request on github.com",
        arguments: [
            "https://github.com/davidgiordana/GimDiff",
            "https://github.com/davidgiordana/GimDiff/issues/123",
            "https://github.com/davidgiordana/GimDiff/pull/",
            "https://github.com/davidgiordana/GimDiff/pull/abc",
            "https://github.com/davidgiordana/GimDiff/pull/0",
            "https://gitlab.com/davidgiordana/GimDiff/pull/123",
            "https://notgithub.com/davidgiordana/GimDiff/pull/123",
            "https://api.github.com/davidgiordana/GimDiff/pull/123",
            "https://github.example.com/davidgiordana/GimDiff/pull/123",
            "/Users/david/Snapshots/home.png",
            "",
        ]
    )
    func rejectsOtherLinks(_ text: String) {
        #expect(GitHubPRURLParser.reference(in: text) == nil)
    }

    @Test("Reads owner/repo#123 typed on its own")
    func parsesShortForm() {
        #expect(GitHubPRURLParser.reference(fromInput: " davidgiordana/GimDiff#123 ") == expected)
    }

    @Test("Resolves a bare number against the repository it is given")
    func resolvesBareNumber() {
        let repository = GitHubRepository(owner: "davidgiordana", name: "GimDiff")

        #expect(GitHubPRURLParser.reference(fromInput: "123", defaultRepository: repository) == expected)
        #expect(GitHubPRURLParser.reference(fromInput: "#123", defaultRepository: repository) == expected)
    }

    @Test("A bare number with no repository is not a pull request")
    func bareNumberNeedsRepository() {
        #expect(GitHubPRURLParser.reference(fromInput: "123") == nil)
        #expect(GitHubPRURLParser.isBareNumber("123"))
        #expect(!GitHubPRURLParser.isBareNumber("12a"))
    }

    @Test("The web link is the canonical spelling")
    func buildsWebURL() {
        #expect(expected.webURL.absoluteString == "https://github.com/davidgiordana/GimDiff/pull/123")
        #expect(expected.shortDescription == "davidgiordana/GimDiff#123")
    }

    @Test(
        "Reads the repository out of every remote spelling Git accepts for github.com",
        arguments: [
            "https://github.com/davidgiordana/GimDiff.git",
            "https://github.com/davidgiordana/GimDiff",
            "https://token@github.com/davidgiordana/GimDiff.git",
            "git@github.com:davidgiordana/GimDiff.git",
            "github.com:davidgiordana/GimDiff",
            "ssh://git@github.com/davidgiordana/GimDiff.git",
            "ssh://git@github.com:22/davidgiordana/GimDiff.git",
            "git://github.com/davidgiordana/GimDiff.git\n",
        ]
    )
    func parsesRemoteURLs(_ remote: String) {
        #expect(
            GitHubPRURLParser.repository(fromRemoteURL: remote)
                == GitHubRepository(owner: "davidgiordana", name: "GimDiff")
        )
    }

    @Test(
        "Rejects remotes hosted anywhere but github.com",
        arguments: [
            "git@gitlab.com:davidgiordana/GimDiff.git",
            "https://github.example.com/davidgiordana/GimDiff.git",
            "/Users/david/Repositories/GimDiff.git",
        ]
    )
    func rejectsOtherRemotes(_ remote: String) {
        #expect(GitHubPRURLParser.repository(fromRemoteURL: remote) == nil)
    }
}

@Suite("GitHub pull request input resolution")
struct GitHubPRReferenceResolverTests {
    private let root = URL(fileURLWithPath: "/Projects/GimDiff")

    @Test("A link resolves without consulting git")
    func linkNeedsNoRepository() async throws {
        let resolver = GitHubPRReferenceResolver(gitService: StubGitService())

        let reference = try await resolver.reference(
            for: "https://github.com/octo/app/pull/9",
            repositoryRoot: nil
        )

        #expect(reference == GitHubPRReference(owner: "octo", repo: "app", pullNumber: 9))
    }

    @Test("A bare number is looked up in the repository's origin")
    func numberUsesOrigin() async throws {
        var git = StubGitService()
        git.remoteURL = "git@github.com:octo/app.git"
        let resolver = GitHubPRReferenceResolver(gitService: git)

        let reference = try await resolver.reference(for: "42", repositoryRoot: root)

        #expect(reference == GitHubPRReference(owner: "octo", repo: "app", pullNumber: 42))
    }

    @Test("A preferred repository wins over the origin")
    func preferredRepositoryWins() async throws {
        var git = StubGitService()
        git.remoteURL = "git@github.com:octo/app.git"
        let resolver = GitHubPRReferenceResolver(gitService: git)

        let reference = try await resolver.reference(
            for: "42",
            repositoryRoot: root,
            preferredRepository: GitHubRepository(owner: "other", name: "lib")
        )

        #expect(reference == GitHubPRReference(owner: "other", repo: "lib", pullNumber: 42))
    }

    @Test("A bare number outside any repository is reported as needing one")
    func numberWithoutRepository() async {
        let resolver = GitHubPRReferenceResolver(gitService: StubGitService())

        await #expect(throws: GitHubPRInputError.numberNeedsRepository) {
            try await resolver.reference(for: "42", repositoryRoot: nil)
        }
        await #expect(throws: GitHubPRInputError.numberNeedsRepository) {
            try await resolver.reference(for: "42", repositoryRoot: root)
        }
    }

    @Test("A bare number in a repository hosted elsewhere names the remote")
    func numberWithForeignRemote() async {
        var git = StubGitService()
        git.remoteURL = "git@gitlab.com:octo/app.git"
        let resolver = GitHubPRReferenceResolver(gitService: git)

        await #expect(throws: GitHubPRInputError.remoteNotOnGitHub("git@gitlab.com:octo/app.git")) {
            try await resolver.reference(for: "42", repositoryRoot: root)
        }
    }

    @Test("Text that is no kind of pull request is rejected as such")
    func rejectsGarbage() async {
        let resolver = GitHubPRReferenceResolver(gitService: StubGitService())

        await #expect(throws: GitHubPRInputError.unrecognized("not a pr")) {
            try await resolver.reference(for: "  not a pr ", repositoryRoot: root)
        }
    }
}
