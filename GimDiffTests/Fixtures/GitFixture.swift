//
//  GitFixture.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
@testable import GimDiff

/// A throwaway Git repository, initialised on demand and removed when the test releases it.
///
/// Shared between the Git service's own integration tests and the promotion tests, which
/// both need the one thing a double cannot provide: a real working tree with a real commit
/// behind it, so `git show` has something to extract and `git status` has something to say.
final class GitFixture {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffGit-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try run(["init", "--quiet"])
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ relativePath: String, data: Data) throws {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
    }

    /// Stages one path, leaving the rest of the working tree as it is.
    func stage(_ relativePath: String) throws {
        try run(["add", "--", relativePath])
    }

    /// Sets `key` in this repository's own configuration, which outranks the developer's.
    func configure(_ key: String, _ value: String) throws {
        try run(["config", key, value])
    }

    /// Stages everything and commits it without touching the developer's global Git config.
    func commit() throws {
        try run(["add", "--all"])
        try run([
            "-c", "user.name=GimDiff Tests",
            "-c", "user.email=tests@example.com",
            "-c", "commit.gpgsign=false",
            "commit", "--quiet", "--message", "Snapshot fixture",
        ])
    }

    private func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = url
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GimDiffError.commandFailed(
                command: "git " + arguments.joined(separator: " "),
                exitCode: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self)
            )
        }
    }
}
