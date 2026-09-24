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

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
