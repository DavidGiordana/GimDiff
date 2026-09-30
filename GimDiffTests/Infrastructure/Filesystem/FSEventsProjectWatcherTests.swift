//
//  FSEventsProjectWatcherTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The watcher against a real volume, which is the only place its events come from.
@Suite("Watching a folder with FSEvents")
struct FSEventsProjectWatcherTests {
    /// Own writes are let through: the test process is the one doing the writing.
    private let watcher = FSEventsProjectWatcher(latency: 0.05, ignoresOwnWrites: false)

    /// The first event matching `isExpected`, or `nil` if none arrives in time.
    private func firstEvent(
        in stream: AsyncStream<[ProjectFileEvent]>,
        where isExpected: @escaping @Sendable (ProjectFileEvent) -> Bool
    ) async -> ProjectFileEvent? {
        let search = Task {
            for await batch in stream {
                if let match = batch.first(where: isExpected) { return Optional(match) }
            }
            return nil
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            search.cancel()
        }
        defer { timeout.cancel() }
        return await search.value
    }

    @Test("A file written under the root is reported under the root as it was given")
    func reportsAWrittenFile() async throws {
        // `NSTemporaryDirectory()` is `/var/…`, which FSEvents reports as `/private/var/…`.
        let directory = try TemporaryDirectory()
        let expected = directory.url.appendingPathComponent("Snapshots/home.png").standardizedFileURL.path

        let stream = watcher.changes(under: [directory.url])
        try directory.write("Snapshots/home.png")

        let event = await firstEvent(in: stream) { $0.url.path == expected }
        #expect(event?.isDirectory == false)
    }

    @Test("A folder is reported as one")
    func reportsAFolder() async throws {
        let directory = try TemporaryDirectory()
        let expected = directory.url.appendingPathComponent("Snapshots").standardizedFileURL.path

        let stream = watcher.changes(under: [directory.url])
        try FileManager.default.createDirectory(
            at: directory.url.appendingPathComponent("Snapshots"),
            withIntermediateDirectories: true
        )

        let event = await firstEvent(in: stream) { $0.url.path == expected }
        #expect(event?.isDirectory == true)
    }
}
