//
//  GitCommandTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Git command construction")
struct GitCommandTests {
    private let repository = URL(fileURLWithPath: "/tmp/My Repo")

    @Test("Commands run git directly rather than through a shell")
    func invokesGitDirectly() {
        let command = GitCommand.status(in: repository)

        #expect(command.executableURL == URL(fileURLWithPath: "/usr/bin/git"))
        #expect(command.workingDirectory == repository)
    }

    @Test("Status asks for machine-readable output including untracked files")
    func statusArguments() {
        #expect(GitCommand.status(in: repository).arguments == [
            "-c", "core.quotePath=false", "status", "--porcelain=v1", "--untracked-files=all",
        ])
    }

    @Test("Branch lookup uses the abbreviated ref")
    func currentBranchArguments() {
        #expect(GitCommand.currentBranch(in: repository).arguments == [
            "rev-parse", "--abbrev-ref", "HEAD",
        ])
    }

    @Test("Paths are passed as separate arguments and need no escaping")
    func pathsArePassedVerbatim() {
        let paths = [
            URL(fileURLWithPath: "/tmp/My Repo/Snapshots/home screen.png"),
            URL(fileURLWithPath: "/tmp/My Repo/Snapshots/it's-a-name.png"),
        ]

        let command = GitCommand.checkout(paths: paths, in: repository)

        #expect(command.arguments == [
            "checkout",
            "--",
            "/tmp/My Repo/Snapshots/home screen.png",
            "/tmp/My Repo/Snapshots/it's-a-name.png",
        ])
    }

    @Test("A double dash separates paths from options so filenames are never read as flags")
    func pathsAreSeparatedByDoubleDash() {
        let path = URL(fileURLWithPath: "/tmp/My Repo/--force.png")

        let command = GitCommand.add(paths: [path], in: repository)

        #expect(command.arguments == ["add", "--", "/tmp/My Repo/--force.png"])
    }
}
