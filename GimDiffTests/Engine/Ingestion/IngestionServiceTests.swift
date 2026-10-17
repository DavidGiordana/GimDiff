//
//  IngestionServiceTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Failure log ingestion")
struct ClipboardIngestionTests {
    private let service = DefaultIngestionService()

    @Test("Reads both sides out of an Xcode test failure log")
    func parsesXcodeFailureLog() throws {
        let log = """
        /Users/david/Dev/Demo/Tests/HomeTests.swift:42: error: -[HomeTests testHome] : \
        failed - Snapshot does not match reference.

        @−
        "file:///Users/david/Dev/Demo/Tests/__Snapshots__/HomeTests/testHome.1.png"
        @+
        "file:///var/folders/9c/T/testHome.1.png"

        To configure output for a custom diff tool, use 'withSnapshotTesting'.
        """

        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.baselineURL == URL(
            fileURLWithPath: "/Users/david/Dev/Demo/Tests/__Snapshots__/HomeTests/testHome.1.png"
        ))
        #expect(payload.candidateURL == URL(fileURLWithPath: "/var/folders/9c/T/testHome.1.png"))
    }

    @Test("Reads the Recorded and Failure lines of a Swift Testing failure log")
    func parsesSwiftTestingFailureLog() throws {
        let log = """
        ✘ Test homeScreen() recorded an issue at HomeTests.swift:18:5: Expectation failed
          Recorded: file:///Users/david/Dev/Demo/__Snapshots__/homeScreen.png
          Failure:  file:///var/folders/9c/T/homeScreen.png
        """

        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.baselineURL == URL(
            fileURLWithPath: "/Users/david/Dev/Demo/__Snapshots__/homeScreen.png"
        ))
        #expect(payload.baselineTag == "Recorded")
        #expect(payload.candidateURL == URL(fileURLWithPath: "/var/folders/9c/T/homeScreen.png"))
        #expect(payload.candidateTag == "Failure")
    }

    @Test("Labels win over the order the paths appear in")
    func labelsBeatOrdering() throws {
        let log = """
        Failure: /var/folders/9c/T/homeScreen.png
        Reference: /Users/david/Dev/Demo/__Snapshots__/homeScreen.png
        """

        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.candidateURL == URL(fileURLWithPath: "/var/folders/9c/T/homeScreen.png"))
        #expect(payload.baselineURL == URL(
            fileURLWithPath: "/Users/david/Dev/Demo/__Snapshots__/homeScreen.png"
        ))
        #expect(payload.candidateTag == "Failure")
        #expect(payload.baselineTag == "Reference")
        #expect(payload.rolesAreStated)
    }

    @Test("A swift-snapshot-testing diff states its sides with − and +")
    func diffMarkersStateTheSides() throws {
        let log = """
        failed - Snapshot "active" does not match reference.

        @−
        "file:///Users/david/Dev/Demo/__Snapshots__/CardsTests/testCard.active.png"
        @+
        "file:///Users/david/Library/Developer/CoreSimulator/tmp/CardsTests/testCard.active.png"
        """

        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.baselineURL?.path.contains("__Snapshots__") == true)
        #expect(payload.candidateURL.path.contains("CoreSimulator") == true)
        #expect(payload.rolesAreStated)
    }

    @Test("An unlabelled pair is read as reference first, new image second")
    func unlabelledPairUsesOrder() throws {
        let log = #"ksdiff "/Snapshots/home.png" "/tmp/home.png""#

        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.baselineURL == URL(fileURLWithPath: "/Snapshots/home.png"))
        #expect(payload.candidateURL == URL(fileURLWithPath: "/tmp/home.png"))
        #expect(payload.baselineTag == nil)
        #expect(payload.candidateTag == nil)
        #expect(payload.rolesAreStated == false)
    }

    @Test("One labelled path settles both sides, wherever it appears", arguments: [
        "Failure: /tmp/fail.png\n/Snapshots/ref.png",
        "/tmp/fail.png\nReference: /Snapshots/ref.png",
        "/Snapshots/ref.png\nActual: /tmp/fail.png",
        "Expected: /Snapshots/ref.png\n/tmp/fail.png",
    ])
    func oneLabelSettlesBothSides(log: String) throws {
        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.baselineURL == URL(fileURLWithPath: "/Snapshots/ref.png"))
        #expect(payload.candidateURL == URL(fileURLWithPath: "/tmp/fail.png"))
        #expect(payload.rolesAreStated)
    }

    @Test("Two paths with the same label say nothing about the sides")
    func sameLabelTwiceUsesOrder() throws {
        let log = "Reference: /Snapshots/a.png\nReference: /Snapshots/b.png"

        let payload = try #require(service.parseClipboardText(log))

        #expect(payload.baselineURL == URL(fileURLWithPath: "/Snapshots/a.png"))
        #expect(payload.candidateURL == URL(fileURLWithPath: "/Snapshots/b.png"))
        #expect(payload.rolesAreStated == false)
    }

    @Test("A single path becomes the candidate, with no baseline")
    func singlePathHasNoBaseline() throws {
        let payload = try #require(
            service.parseClipboardText("file:///Users/david/Snapshots/home.png")
        )

        #expect(payload.candidateURL == URL(fileURLWithPath: "/Users/david/Snapshots/home.png"))
        #expect(payload.baselineURL == nil)
    }

    @Test("Percent-encoded spaces in a file URL are decoded")
    func decodesPercentEncodedPaths() throws {
        let payload = try #require(
            service.parseClipboardText("file:///Users/david/My%20Snapshots/home%20screen.png")
        )

        #expect(payload.candidateURL == URL(
            fileURLWithPath: "/Users/david/My Snapshots/home screen.png"
        ))
    }

    @Test("Every supported image extension is recognised", arguments: [
        "png", "PNG", "jpg", "jpeg", "webp",
    ])
    func recognisesImageExtensions(pathExtension: String) throws {
        let payload = try #require(service.parseClipboardText("/Snapshots/home.\(pathExtension)"))

        #expect(payload.candidateURL == URL(fileURLWithPath: "/Snapshots/home.\(pathExtension)"))
    }

    @Test("A source path is not mistaken for an image path")
    func ignoresNonImagePaths() {
        let log = "/Users/david/Dev/Demo/Tests/HomeTests.swift:42: error: failed"

        #expect(service.parseClipboardText(log) == nil)
    }

    @Test("A remote image URL is not read as a local path")
    func ignoresRemoteURLs() {
        #expect(service.parseClipboardText("https://example.com/snapshots/home.png") == nil)
    }

    @Test("Prose around a path is not swallowed into it")
    func doesNotSwallowSurroundingProse() throws {
        let payload = try #require(
            service.parseClipboardText("error: could not read /Snapshots/home.png while diffing")
        )

        #expect(payload.candidateURL == URL(fileURLWithPath: "/Snapshots/home.png"))
    }

    @Test("Text with no image at all yields nothing")
    func emptyTextYieldsNothing() {
        #expect(service.parseClipboardText("") == nil)
        #expect(service.parseClipboardText("All tests passed.") == nil)
    }
}

@Suite("Pull request link ingestion")
struct PullRequestIngestionTests {
    private let service = DefaultIngestionService()

    @Test("Finds a pull request link in pasted text")
    func findsPullRequestLink() {
        let text = "Snapshots moved again: https://github.com/octo/app/pull/7 — can you check?"

        #expect(service.parsePullRequest(text) == GitHubPRReference(owner: "octo", repo: "app", pullNumber: 7))
    }

    @Test("A failure log is not a pull request")
    func ignoresFailureLog() {
        let log = """
        Recorded: file:///Users/david/Dev/Demo/__Snapshots__/homeScreen.png
        Failure:  file:///var/folders/9c/T/homeScreen.png
        """

        #expect(service.parsePullRequest(log) == nil)
    }
}

@Suite("gimdiff:// ingestion")
struct URLSchemeIngestionTests {
    private let service = DefaultIngestionService()

    @Test("Reads candidate and baseline from the query string")
    func parsesCandidateAndBaseline() throws {
        let url = try url("gimdiff://open?candidate=/path/to/1.png&baseline=/path/to/2.png")

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.candidateURL == URL(fileURLWithPath: "/path/to/1.png"))
        #expect(payload.baselineURL == URL(fileURLWithPath: "/path/to/2.png"))
    }

    @Test("A candidate on its own is enough")
    func parsesCandidateAlone() throws {
        let url = try url("gimdiff://open?candidate=/path/to/1.png")

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.candidateURL == URL(fileURLWithPath: "/path/to/1.png"))
        #expect(payload.baselineURL == nil)
    }

    @Test("Tags ride along in their own query items")
    func parsesTags() throws {
        let url = try url(
            "gimdiff://open?candidate=/a.png&baseline=/b.png&candidateTag=Failure&baselineTag=Recorded"
        )

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.candidateTag == "Failure")
        #expect(payload.baselineTag == "Recorded")
    }

    @Test("The reference and failure spellings are accepted too")
    func acceptsAlternateParameterNames() throws {
        let url = try url("gimdiff://compare?reference=/path/a.png&failure=/path/b.png")

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.baselineURL == URL(fileURLWithPath: "/path/a.png"))
        #expect(payload.candidateURL == URL(fileURLWithPath: "/path/b.png"))
    }

    @Test("Percent-encoded paths survive parsing intact")
    func decodesPercentEncodedPaths() throws {
        let url = try url("gimdiff://open?candidate=/My%20Snapshots/home%20screen.png")

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.candidateURL == URL(fileURLWithPath: "/My Snapshots/home screen.png"))
    }

    @Test("A file:// value is accepted as readily as a bare path")
    func acceptsFileURLValues() throws {
        let url = try url("gimdiff://open?candidate=file:///Snapshots/home.png")

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.candidateURL == URL(fileURLWithPath: "/Snapshots/home.png"))
    }

    @Test("A leading tilde is expanded to the home directory")
    func expandsTilde() throws {
        let url = try url("gimdiff://open?candidate=~/Snapshots/home.png")

        let payload = try #require(service.parseURLScheme(url))

        #expect(payload.candidateURL == URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Snapshots/home.png")
            .standardizedFileURL)
    }

    @Test("Another app's scheme is ignored")
    func ignoresForeignSchemes() throws {
        #expect(service.parseURLScheme(try url("https://example.com/open?candidate=/a.png")) == nil)
    }

    @Test("A URL that names no candidate is ignored", arguments: [
        "gimdiff://open?baseline=/a.png",
        "gimdiff://open?candidate=",
        "gimdiff://open",
    ])
    func ignoresURLsWithoutACandidate(string: String) throws {
        #expect(service.parseURLScheme(try url(string)) == nil)
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
