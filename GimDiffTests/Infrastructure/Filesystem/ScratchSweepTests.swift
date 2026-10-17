//
//  ScratchSweepTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// What a launch deletes of the scratch files earlier processes left behind.
@Suite("Sweeping abandoned scratch folders")
final class ScratchSweepTests {
    private let base: URL
    private let root: URL
    private let legacyRoot: URL

    init() throws {
        base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffSweep-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("scratch", isDirectory: true)
        legacyRoot = base.appendingPathComponent("scratch.TestRuns", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    private func make(_ url: URL, age: TimeInterval = 0) throws {
        if url.hasDirectoryPath {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("file.png"))
        } else {
            try Data("x".utf8).write(to: url)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -age)],
            ofItemAtPath: url.path
        )
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func sweep(running: Set<pid_t>) {
        DefaultFilesystemService.removeAbandonedScratch(
            sessionsIn: root,
            legacyRoots: [root, legacyRoot],
            isRunning: running.contains
        )
    }

    @Test("A folder whose process is gone is deleted; one whose process runs is kept")
    func judgesSessionsByTheirProcess() throws {
        let gone = root.appendingPathComponent("4242", isDirectory: true)
        let alive = root.appendingPathComponent("4343", isDirectory: true)
        try make(gone)
        try make(alive, age: 7 * 24 * 60 * 60)

        sweep(running: [4343])

        #expect(!exists(gone))
        #expect(exists(alive))
    }

    @Test("Files from before per-process folders go once a day old, and not before")
    func agesOutLegacyFiles() throws {
        let stale = root.appendingPathComponent("undo-home-stale.png")
        let fresh = root.appendingPathComponent("undo-home-fresh.png")
        let staleRun = legacyRoot.appendingPathComponent("6991CB15", isDirectory: true)
        try make(stale, age: 2 * 24 * 60 * 60)
        try make(fresh, age: 60)
        try make(staleRun, age: 2 * 24 * 60 * 60)

        sweep(running: [])

        #expect(!exists(stale))
        #expect(exists(fresh))
        #expect(!exists(staleRun))
        // Emptied, a legacy root goes too; the current root stays for the sessions in it.
        #expect(!exists(legacyRoot))
        #expect(exists(root))
    }

    @Test("A running process's folder is safe however old it is")
    func neverTakesALiveSessionForLegacy() throws {
        let alive = root.appendingPathComponent("4343", isDirectory: true)
        try make(alive, age: 30 * 24 * 60 * 60)

        sweep(running: [4343])

        #expect(exists(alive))
    }

    @Test("This process's scratch folder is named after it, under the scratch root")
    func sessionFolderIsPerProcess() {
        let session = DefaultFilesystemService.sessionDirectory
        #expect(session.lastPathComponent == String(ProcessInfo.processInfo.processIdentifier))
        #expect(session.deletingLastPathComponent().standardizedFileURL == DefaultFilesystemService.scratchRoot.standardizedFileURL)
        #expect(DefaultFilesystemService.isRunning(getpid()))
    }
}
