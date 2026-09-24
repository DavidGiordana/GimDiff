//
//  GitServiceTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Git command construction")
struct GitServiceCommandTests {
    private let repositoryRoot = URL(fileURLWithPath: "/tmp/My Repo")

    @Test("Status runs git directly, in the repository root")
    func statusCommand() {
        let command = DefaultGitService.statusCommand(in: repositoryRoot)

        #expect(command.executableURL == URL(fileURLWithPath: "/usr/bin/git"))
        #expect(command.arguments == ["status", "-s"])
        #expect(command.workingDirectory == repositoryRoot)
    }

    @Test("Show asks for one path at one ref, as a single argument")
    func showCommand() {
        let command = DefaultGitService.showCommand(
            ofFileAt: "Snapshots/home screen.png",
            gitRef: "HEAD",
            in: repositoryRoot
        )

        #expect(command.arguments == ["show", "HEAD:Snapshots/home screen.png"])
        #expect(command.workingDirectory == repositoryRoot)
    }

    @Test("A path containing shell metacharacters is passed through untouched")
    func pathsAreNotEscaped() {
        let command = DefaultGitService.showCommand(
            ofFileAt: "Snapshots/$(whoami); rm -rf *.png",
            gitRef: "main",
            in: repositoryRoot
        )

        #expect(command.arguments == ["show", "main:Snapshots/$(whoami); rm -rf *.png"])
    }

    @Test("Leading separators are stripped so the path stays repository-relative", arguments: [
        ("Snapshots/home.png", "Snapshots/home.png"),
        ("./Snapshots/home.png", "Snapshots/home.png"),
        ("/Snapshots/home.png", "Snapshots/home.png"),
        ("././Snapshots/home.png", "Snapshots/home.png"),
    ])
    func normalizesRelativePaths(input: String, expected: String) {
        #expect(DefaultGitService.normalize(input) == expected)
    }
}

@Suite("Git status parsing")
struct GitStatusParsingTests {
    private let repositoryRoot = URL(fileURLWithPath: "/repo")

    @Test("Maps the porcelain status columns onto a file status", arguments: [
        (" M", GitFileStatus.modified),
        ("M ", GitFileStatus.modified),
        ("MM", GitFileStatus.modified),
        ("A ", GitFileStatus.modified),
        ("??", GitFileStatus.untracked),
        (" D", GitFileStatus.deleted),
        ("D ", GitFileStatus.deleted),
    ])
    func mapsStatusCodes(code: String, expected: GitFileStatus) {
        #expect(DefaultGitService.status(forCode: code) == expected)
    }

    @Test("Ignores records GimDiff has nothing to show for", arguments: ["!!", "  "])
    func ignoresUninterestingCodes(code: String) {
        #expect(DefaultGitService.status(forCode: code) == nil)
    }

    @Test("Resolves each record against the repository root")
    func resolvesPathsAgainstRoot() {
        let output = """
         M Snapshots/home.png
        ?? Snapshots/new.png
         D Snapshots/gone.png

        """

        let statuses = DefaultGitService.parseStatus(output, repositoryRoot: repositoryRoot)

        #expect(statuses == [
            URL(fileURLWithPath: "/repo/Snapshots/home.png"): .modified,
            URL(fileURLWithPath: "/repo/Snapshots/new.png"): .untracked,
            URL(fileURLWithPath: "/repo/Snapshots/gone.png"): .deleted,
        ])
    }

    @Test("Keeps a path that contains spaces intact")
    func keepsSpacesInPaths() {
        let statuses = DefaultGitService.parseStatus(
            " M Snapshots/home screen.png\n",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [URL(fileURLWithPath: "/repo/Snapshots/home screen.png"): .modified])
    }

    @Test("A rename is reported against the path that now exists on disk")
    func renameUsesDestination() {
        let statuses = DefaultGitService.parseStatus(
            "R  Snapshots/old.png -> Snapshots/new.png\n",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [URL(fileURLWithPath: "/repo/Snapshots/new.png"): .modified])
    }

    @Test("Quoting applied by git is undone")
    func unquotesPaths() {
        let statuses = DefaultGitService.parseStatus(
            "?? \"Snapshots/caf\\\"e.png\"\n",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [URL(fileURLWithPath: "/repo/Snapshots/caf\"e.png"): .untracked])
    }

    @Test("Empty and truncated lines are skipped rather than crashing")
    func skipsUnusableLines() {
        #expect(DefaultGitService.parseStatus("\n M\n??\n\n", repositoryRoot: repositoryRoot).isEmpty)
    }

    @Test("A clean tree reports nothing")
    func cleanTreeIsEmpty() {
        #expect(DefaultGitService.parseStatus("", repositoryRoot: repositoryRoot).isEmpty)
    }
}

@Suite("Git service behaviour")
struct DefaultGitServiceTests {
    @Test("Finds the working tree root by walking up from a snapshot folder")
    func findsRepositoryRoot() async {
        let filesystem = MockFilesystemService()
        filesystem.createDirectory(at: URL(fileURLWithPath: "/repo/.git"))
        filesystem.createDirectory(at: URL(fileURLWithPath: "/repo/Tests/Snapshots/iPad"))
        let service = DefaultGitService(runner: RecordingCommandRunner(), filesystem: filesystem)

        let root = await service.findRepositoryRoot(
            for: URL(fileURLWithPath: "/repo/Tests/Snapshots/iPad")
        )

        #expect(root == URL(fileURLWithPath: "/repo"))
    }

    @Test("A worktree, where .git is a file rather than a folder, is still a root")
    func findsRootFromGitFile() async {
        let filesystem = MockFilesystemService()
        filesystem.stub(URL(fileURLWithPath: "/worktree/.git"), contents: "gitdir: /repo/.git/worktrees/a")
        filesystem.createDirectory(at: URL(fileURLWithPath: "/worktree/Snapshots"))
        let service = DefaultGitService(runner: RecordingCommandRunner(), filesystem: filesystem)

        let root = await service.findRepositoryRoot(for: URL(fileURLWithPath: "/worktree/Snapshots"))

        #expect(root == URL(fileURLWithPath: "/worktree"))
    }

    @Test("A folder outside any repository has no root")
    func reportsNoRootOutsideARepository() async {
        let filesystem = MockFilesystemService()
        filesystem.createDirectory(at: URL(fileURLWithPath: "/elsewhere/Snapshots"))
        let service = DefaultGitService(runner: RecordingCommandRunner(), filesystem: filesystem)

        #expect(await service.findRepositoryRoot(for: URL(fileURLWithPath: "/elsewhere/Snapshots")) == nil)
    }

    @Test("Status runs one git invocation and returns the parsed records")
    func statusParsesRunnerOutput() async throws {
        let runner = RecordingCommandRunner(
            result: CommandResult(
                exitCode: 0,
                standardOutput: " M Snapshots/home.png\n?? Snapshots/new.png\n",
                standardError: ""
            )
        )
        let service = DefaultGitService(runner: runner, filesystem: MockFilesystemService())

        let statuses = try await service.status(repositoryRoot: URL(fileURLWithPath: "/repo"))

        #expect(statuses == [
            URL(fileURLWithPath: "/repo/Snapshots/home.png"): .modified,
            URL(fileURLWithPath: "/repo/Snapshots/new.png"): .untracked,
        ])
        #expect(runner.recorded.map(\.arguments) == [["status", "-s"]])
    }

    @Test("A failing status surfaces git's own message")
    func statusSurfacesGitError() async {
        let runner = RecordingCommandRunner(
            result: CommandResult(
                exitCode: 128,
                standardOutput: "",
                standardError: "fatal: not a git repository\n"
            )
        )
        let service = DefaultGitService(runner: runner, filesystem: MockFilesystemService())

        await #expect(throws: GimDiffError.commandFailed(
            command: "git status",
            exitCode: 128,
            message: "fatal: not a git repository"
        )) {
            try await service.status(repositoryRoot: URL(fileURLWithPath: "/repo"))
        }
    }
}

@Suite("Git service against a real repository", .serialized)
struct GitServiceIntegrationTests {
    private let service = DefaultGitService()

    @Test("Extracts the committed bytes of a modified binary file")
    func extractsCommittedVersion() async throws {
        let repository = try GitFixture()
        let committed = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0x0A, 0x0D, 0x1A, 0x0A])
        try repository.write("Snapshots/home.png", data: committed)
        try repository.commit()
        try repository.write("Snapshots/home.png", data: Data(repeating: 0x42, count: 2048))

        let extracted = try await service.extractCommittedVersion(
            ofFileAt: "Snapshots/home.png",
            repositoryRoot: repository.url,
            gitRef: "HEAD"
        )
        defer { try? FileManager.default.removeItem(at: extracted) }

        #expect(try Data(contentsOf: extracted) == committed)
        #expect(extracted.pathExtension == "png")
    }

    @Test("Asking for a path that is not in the commit fails with git's message")
    func reportsMissingPath() async throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/home.png", data: Data([0x01]))
        try repository.commit()

        await #expect(throws: GimDiffError.self) {
            _ = try await service.extractCommittedVersion(
                ofFileAt: "Snapshots/never-committed.png",
                repositoryRoot: repository.url,
                gitRef: "HEAD"
            )
        }
    }

    @Test("Status reports a modified file and an untracked one")
    func reportsWorkingTreeStatus() async throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/home.png", data: Data([0x01]))
        try repository.commit()
        try repository.write("Snapshots/home.png", data: Data([0x02]))
        try repository.write("Snapshots/new.png", data: Data([0x03]))

        let statuses = try await service.status(repositoryRoot: repository.url)

        let home = repository.url.appendingPathComponent("Snapshots/home.png").standardizedFileURL
        let new = repository.url.appendingPathComponent("Snapshots/new.png").standardizedFileURL
        #expect(statuses[home] == .modified)
        #expect(statuses[new] == .untracked)
    }

    @Test("The repository root is found from a nested snapshot folder")
    func findsRealRepositoryRoot() async throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/iPad/home.png", data: Data([0x01]))

        let root = await service.findRepositoryRoot(
            for: repository.url.appendingPathComponent("Snapshots/iPad")
        )

        #expect(root?.path == repository.url.path)
    }
}

/// A throwaway Git working tree, removed when the test releases it.
private final class GitFixture {
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

/// A `CommandRunning` double that records what it was asked to run.
private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let result: CommandResult
    private let lock = NSLock()
    private var commands: [Command] = []

    init(result: CommandResult = CommandResult(exitCode: 0, standardOutput: "", standardError: "")) {
        self.result = result
    }

    var recorded: [Command] {
        lock.withLock { commands }
    }

    func run(_ command: Command) async throws -> CommandResult {
        lock.withLock { commands.append(command) }
        return result
    }
}
