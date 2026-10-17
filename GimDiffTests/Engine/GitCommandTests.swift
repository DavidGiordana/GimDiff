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

    @Test("Status asks for porcelain, NUL-separated and unquoted, with untracked files")
    func statusArguments() {
        #expect(GitCommand.status(in: repository).arguments == [
            "-c", "core.quotePath=false",
            "status", "--porcelain=v1", "-z", "--untracked-files=normal",
        ])
    }

    @Test("Show asks for one path at one ref, as a single argument")
    func showArguments() {
        let command = GitCommand.show(ofFileAt: "Snapshots/home screen.png", gitRef: "HEAD", in: repository)

        #expect(command.arguments == ["show", "HEAD:Snapshots/home screen.png"])
        #expect(command.workingDirectory == repository)
    }

    @Test("A path containing shell metacharacters is passed through untouched")
    func showDoesNotEscape() {
        let command = GitCommand.show(ofFileAt: "Snapshots/$(whoami); rm -rf *.png", gitRef: "main", in: repository)

        #expect(command.arguments == ["show", "main:Snapshots/$(whoami); rm -rf *.png"])
    }

    @Test("Leading separators are stripped so the path stays repository-relative", arguments: [
        ("Snapshots/home.png", "Snapshots/home.png"),
        ("./Snapshots/home.png", "Snapshots/home.png"),
        ("/Snapshots/home.png", "Snapshots/home.png"),
        ("././Snapshots/home.png", "Snapshots/home.png"),
    ])
    func normalizesRelativePaths(input: String, expected: String) {
        #expect(GitCommand.normalize(input) == expected)
        #expect(GitCommand.show(ofFileAt: input, gitRef: "HEAD", in: repository).arguments == ["show", "HEAD:\(expected)"])
    }

    @Test("The tracking check fails on an untracked path, and keeps it behind --")
    func lsFilesArguments() {
        let path = URL(fileURLWithPath: "/tmp/My Repo/--force.png")
        #expect(GitCommand.lsFilesErrorUnmatch(path: path, in: repository).arguments == [
            "ls-files", "--error-unmatch", "--", "/tmp/My Repo/--force.png",
        ])
    }

    @Test("Discarding restores from HEAD, the index included, with the paths behind --")
    func restoreFromHEADArguments() {
        let path = URL(fileURLWithPath: "/tmp/My Repo/--force.png")
        #expect(GitCommand.restoreFromHEAD(paths: [path], in: repository).arguments == [
            "restore", "--source=HEAD", "--staged", "--worktree", "--", "/tmp/My Repo/--force.png",
        ])
    }

    @Test("Paths are passed as separate arguments and need no escaping")
    func pathsArePassedVerbatim() {
        let paths = [
            URL(fileURLWithPath: "/tmp/My Repo/Snapshots/home screen.png"),
            URL(fileURLWithPath: "/tmp/My Repo/Snapshots/it's-a-name.png"),
        ]

        #expect(GitCommand.restoreFromHEAD(paths: paths, in: repository).arguments.suffix(3) == [
            "--",
            "/tmp/My Repo/Snapshots/home screen.png",
            "/tmp/My Repo/Snapshots/it's-a-name.png",
        ])
    }

    @Test("The remote is named behind --, so a name cannot be read as an option")
    func remoteURLArguments() {
        #expect(GitCommand.remoteURL(named: "origin", in: repository).arguments == ["remote", "get-url", "--", "origin"])
    }
}
