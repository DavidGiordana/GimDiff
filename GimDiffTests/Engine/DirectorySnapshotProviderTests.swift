//
//  DirectorySnapshotProviderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Directory snapshot provider")
struct DirectorySnapshotProviderTests {
    @Test("Treats images under a failure folder as the failing side")
    func splitsOnTheFailureFolder() {
        let pairs = DirectorySnapshotProvider.pairs(from: [
            URL(fileURLWithPath: "/tmp/__Snapshots__/home.png"),
            URL(fileURLWithPath: "/tmp/__Snapshots__/failures/home.png"),
        ])

        #expect(pairs.count == 1)
        #expect(pairs[0].reference.url.path == "/tmp/__Snapshots__/home.png")
        #expect(pairs[0].failure.url.path == "/tmp/__Snapshots__/failures/home.png")
    }

    /// Documents a limitation of the convention: the marker moves an image to the failure
    /// side, but pairing still matches on the exact file name. A failure image therefore has
    /// to keep its reference's name and be distinguished by its folder.
    @Test("A marker embedded in the file name leaves the image unpaired")
    func markerInTheFileNameBreaksPairing() {
        let pairs = DirectorySnapshotProvider.pairs(from: [
            URL(fileURLWithPath: "/tmp/snaps/home.png"),
            URL(fileURLWithPath: "/tmp/snaps/home.failure.png"),
        ])

        #expect(pairs.isEmpty)
    }

    @Test("Matching is case-insensitive, so Failures and failures both count")
    func markerIsCaseInsensitive() {
        let pairs = DirectorySnapshotProvider.pairs(from: [
            URL(fileURLWithPath: "/tmp/snaps/home.png"),
            URL(fileURLWithPath: "/tmp/snaps/FAILURES/home.png"),
        ])

        #expect(pairs.count == 1)
        #expect(pairs[0].failure.url.path == "/tmp/snaps/FAILURES/home.png")
    }

    @Test("A folder with only reference images yields no comparisons")
    func referencesAloneYieldNothing() {
        let pairs = DirectorySnapshotProvider.pairs(from: [
            URL(fileURLWithPath: "/tmp/snaps/home.png"),
            URL(fileURLWithPath: "/tmp/snaps/settings.png"),
        ])

        #expect(pairs.isEmpty)
    }

    @Test("Reads pairs off disk and ignores non-image files")
    func readsPairsFromDisk() async throws {
        let root = try TemporaryDirectory()
        try root.write("home.png")
        try root.write("failures/home.png")
        try root.write("failures/notes.txt")
        let provider = DirectorySnapshotProvider(fileSystem: DefaultFilesystemService())

        #expect(await provider.canHandle(folder: root.url))
        let pairs = try await provider.pairs(in: root.url)

        #expect(pairs.map(\.name) == ["home"])
    }

    @Test("Declines a folder that holds no images at all")
    func declinesAnEmptyFolder() async throws {
        let root = try TemporaryDirectory()
        try root.write("README.md")
        let provider = DirectorySnapshotProvider(fileSystem: DefaultFilesystemService())

        #expect(await provider.canHandle(folder: root.url) == false)
    }
}
