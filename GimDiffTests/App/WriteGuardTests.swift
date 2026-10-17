//
//  WriteGuardTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// Accept and the Keep choices write only images over images, whatever opened the pair.
@Suite("Writing only images")
@MainActor
struct WriteGuardTests {
    private static let folder = URL(fileURLWithPath: "/Users/someone/Documents", isDirectory: true)

    private func fixture(reference: String, failure: String) -> (AppStateFixture, URL, URL) {
        let fixture = AppStateFixture()
        let referenceURL = Self.folder.appendingPathComponent(reference)
        let failureURL = Self.folder.appendingPathComponent(failure)
        fixture.filesystem.stub(referenceURL, contents: "reference bytes")
        fixture.filesystem.stub(failureURL, contents: "failure bytes")
        fixture.state.canvas.showComparison(reference: referenceURL, failure: failureURL, certainty: .stated)
        return (fixture, referenceURL, failureURL)
    }

    @Test("Keeping the candidate never writes an image over a document")
    func refusesToOverwriteADocument() throws {
        let (fixture, notes, _) = fixture(reference: "notes.txt", failure: "home.png")

        fixture.state.keepCandidate()

        #expect(try fixture.filesystem.readFile(at: notes) == Data("reference bytes".utf8))
        #expect(fixture.state.lastError != nil)
        // The pair stays up, so the refusal is read against it.
        #expect(fixture.state.canvas.preview?.isComparison == true)
    }

    @Test("Keeping the candidate never writes a document over a snapshot")
    func refusesToWriteADocument() throws {
        let (fixture, snapshot, _) = fixture(reference: "home.png", failure: "passwords.txt")

        fixture.state.keepCandidate()

        #expect(try fixture.filesystem.readFile(at: snapshot) == Data("reference bytes".utf8))
        #expect(fixture.state.lastError != nil)
    }

    @Test("Two images are written as before")
    func writesAnImageOverAnImage() throws {
        let (fixture, snapshot, _) = fixture(reference: "home.png", failure: "home-failure.PNG")

        fixture.state.keepCandidate()

        #expect(try fixture.filesystem.readFile(at: snapshot) == Data("failure bytes".utf8))
        #expect(fixture.state.lastError == nil)
    }
}
