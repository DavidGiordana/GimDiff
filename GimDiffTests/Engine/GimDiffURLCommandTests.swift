//
//  GimDiffURLCommandTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("gimdiff:// URL parsing")
struct GimDiffURLCommandTests {
    @Test("Parses an open command into a folder URL")
    func parsesOpenCommand() throws {
        let command = try GimDiffURLCommand(url: try url("gimdiff://open?path=/tmp/Snapshots"))

        #expect(command == .open(folder: URL(fileURLWithPath: "/tmp/Snapshots")))
    }

    @Test("Parses a compare command into both image URLs")
    func parsesCompareCommand() throws {
        let command = try GimDiffURLCommand(
            url: try url("gimdiff://compare?reference=/tmp/a.png&failure=/tmp/b.png")
        )

        #expect(command == .compare(
            reference: URL(fileURLWithPath: "/tmp/a.png"),
            failure: URL(fileURLWithPath: "/tmp/b.png")
        ))
    }

    @Test("Percent-encoded paths survive parsing intact")
    func decodesPercentEncodedPaths() throws {
        let command = try GimDiffURLCommand(
            url: try url("gimdiff://open?path=/tmp/My%20Snapshots/Home%20Screen")
        )

        #expect(command == .open(folder: URL(fileURLWithPath: "/tmp/My Snapshots/Home Screen")))
    }

    @Test("A leading tilde is expanded to the home directory")
    func expandsTilde() throws {
        let command = try GimDiffURLCommand(url: try url("gimdiff://open?path=~/Snapshots"))

        let expected = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Snapshots")
            .standardizedFileURL
        #expect(command == .open(folder: expected))
    }

    @Test("Rejects URLs from another scheme")
    func rejectsForeignScheme() throws {
        let foreign = try url("https://example.com/open?path=/tmp")

        #expect(throws: GimDiffError.unsupportedScheme("https")) {
            try GimDiffURLCommand(url: foreign)
        }
    }

    @Test("Rejects an action the app does not implement")
    func rejectsUnknownAction() throws {
        let unknown = try url("gimdiff://explode?path=/tmp")

        #expect(throws: GimDiffError.unsupportedAction("explode")) {
            try GimDiffURLCommand(url: unknown)
        }
    }

    @Test("Rejects a compare command that names only one side", arguments: [
        "gimdiff://compare?reference=/tmp/a.png",
        "gimdiff://compare?failure=/tmp/b.png",
    ])
    func rejectsIncompleteCompare(string: String) throws {
        let incomplete = try url(string)

        #expect(throws: GimDiffError.self) {
            try GimDiffURLCommand(url: incomplete)
        }
    }

    @Test("Treats an empty parameter value as missing")
    func rejectsEmptyParameter() throws {
        let empty = try url("gimdiff://open?path=")

        #expect(throws: GimDiffError.missingParameter("path")) {
            try GimDiffURLCommand(url: empty)
        }
    }

    @Test("The CLI's spelling of the open action is understood", arguments: [
        "gimdiff://open-project?path=/tmp/Project",
        "gimdiff://open?project=/tmp/Project",
        "gimdiff://open?folder=/tmp/Project",
    ])
    func acceptsOpenSynonyms(string: String) throws {
        let command = try GimDiffURLCommand(url: try url(string))

        #expect(command == .open(folder: URL(fileURLWithPath: "/tmp/Project")))
    }

    @Test("The CLI's spelling of the compare action is understood", arguments: [
        "gimdiff://compare?baseline=/tmp/a.png&candidate=/tmp/b.png",
        "gimdiff://diff?reference=/tmp/a.png&failure=/tmp/b.png",
        "gimdiff://compare?expected=/tmp/a.png&actual=/tmp/b.png",
    ])
    func acceptsCompareSynonyms(string: String) throws {
        let command = try GimDiffURLCommand(url: try url(string))

        #expect(command == .compare(
            reference: URL(fileURLWithPath: "/tmp/a.png"),
            failure: URL(fileURLWithPath: "/tmp/b.png")
        ))
    }

    @Test("An open action that names a pair rather than a folder is read as a comparison", arguments: [
        "gimdiff://open?candidate=/tmp/b.png&baseline=/tmp/a.png",
        "gimdiff://open-project?candidate=/tmp/b.png&reference=/tmp/a.png",
    ])
    func readsAPairOutOfAnOpenAction(string: String) throws {
        let command = try GimDiffURLCommand(url: try url(string))

        #expect(command == .compare(
            reference: URL(fileURLWithPath: "/tmp/a.png"),
            failure: URL(fileURLWithPath: "/tmp/b.png")
        ))
    }

    @Test("An open action carrying a folder stays an open even beside a stray candidate")
    func prefersTheFolderWhenBothAreNamed() throws {
        let command = try GimDiffURLCommand(
            url: try url("gimdiff://open?path=/tmp/Project&candidate=/tmp/b.png")
        )

        #expect(command == .open(folder: URL(fileURLWithPath: "/tmp/Project")))
    }

    @Test("A missing parameter is reported under its preferred spelling")
    func reportsThePreferredParameterName() throws {
        let incomplete = try url("gimdiff://compare?candidate=/tmp/b.png")

        #expect(throws: GimDiffError.missingParameter("reference")) {
            try GimDiffURLCommand(url: incomplete)
        }
    }

    @Test("Reads a pull request review under any of its action names", arguments: [
        "open-pr", "pr", "pull-request", "review-pr",
    ])
    func parsesPullRequestAction(_ action: String) throws {
        let command = try GimDiffURLCommand(
            url: try url("gimdiff://\(action)?url=https%3A%2F%2Fgithub.com%2Focto%2Fapp%2Fpull%2F7")
        )

        #expect(command == .openPullRequest("https://github.com/octo/app/pull/7"))
    }

    @Test("A pull request review keeps a bare number for the app to resolve")
    func keepsBarePullRequestNumber() throws {
        let command = try GimDiffURLCommand(url: try url("gimdiff://open-pr?pr=42"))

        #expect(command == .openPullRequest("42"))
    }

    @Test("A pull request review with nothing to review is reported as missing its url")
    func reportsMissingPullRequest() {
        #expect(throws: GimDiffError.missingParameter("url")) {
            try GimDiffURLCommand(url: try url("gimdiff://open-pr"))
        }
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
