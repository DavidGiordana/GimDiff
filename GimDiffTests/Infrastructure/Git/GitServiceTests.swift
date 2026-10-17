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

    @Test("Status asks for porcelain, NUL-separated and unquoted, in the repository root")
    func statusCommand() {
        let command = DefaultGitService.statusCommand(in: repositoryRoot)

        #expect(command.executableURL == URL(fileURLWithPath: "/usr/bin/git"))
        #expect(command.arguments == [
            "-c", "core.quotePath=false",
            "status", "--porcelain=v1", "-z", "--untracked-files=normal",
        ])
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
        ("A ", GitFileStatus.added),
        ("AM", GitFileStatus.added),
        ("R ", GitFileStatus.added),
        ("RM", GitFileStatus.added),
        ("C ", GitFileStatus.added),
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
        let output = " M Snapshots/home.png\0?? Snapshots/new.png\0 D Snapshots/gone.png\0"

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
            " M Snapshots/home screen.png\0",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [URL(fileURLWithPath: "/repo/Snapshots/home screen.png"): .modified])
    }

    @Test("A rename is added at the path on disk and deleted at the path HEAD has")
    func renameUsesDestination() {
        let statuses = DefaultGitService.parseStatus(
            "R  Snapshots/new.png\0Snapshots/old.png\0",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [
            URL(fileURLWithPath: "/repo/Snapshots/new.png"): .added,
            URL(fileURLWithPath: "/repo/Snapshots/old.png"): .deleted,
        ])
    }

    @Test("A copy is added at its new path, and its source is left alone")
    func copyKeepsItsSource() {
        let statuses = DefaultGitService.parseStatus(
            "C  Snapshots/copy.png\0Snapshots/original.png\0 M Snapshots/home.png\0",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [
            URL(fileURLWithPath: "/repo/Snapshots/copy.png"): .added,
            URL(fileURLWithPath: "/repo/Snapshots/home.png"): .modified,
        ])
    }

    @Test("Accents, quotes, and a separator lookalike arrive as they are spelled")
    func keepsPathsVerbatim() {
        let statuses = DefaultGitService.parseStatus(
            "?? Snapshots/café \"quoted\" -> ünï.png\0",
            repositoryRoot: repositoryRoot
        )

        #expect(statuses == [URL(fileURLWithPath: "/repo/Snapshots/café \"quoted\" -> ünï.png"): .untracked])
    }

    @Test("Empty and truncated records are skipped rather than crashing")
    func skipsUnusableLines() {
        #expect(DefaultGitService.parseStatus("\0 M\0??\0\0", repositoryRoot: repositoryRoot).isEmpty)
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
                standardOutput: " M Snapshots/home.png\0?? Snapshots/new.png\0",
                standardError: ""
            )
        )
        let service = DefaultGitService(runner: runner, filesystem: MockFilesystemService())

        let statuses = try await service.status(repositoryRoot: URL(fileURLWithPath: "/repo"))

        #expect(statuses == [
            URL(fileURLWithPath: "/repo/Snapshots/home.png"): .modified,
            URL(fileURLWithPath: "/repo/Snapshots/new.png"): .untracked,
        ])
        #expect(runner.recorded.map(\.arguments) == [
            DefaultGitService.statusCommand(in: URL(fileURLWithPath: "/repo")).arguments,
        ])
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
        // The file made for git to write into is not left behind.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: DefaultFilesystemService.sessionDirectory.path)) ?? []
        #expect(!leftovers.contains { $0.hasPrefix("never-committed-HEAD") })
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

    @Test("Status survives a configuration that colours it, adds a branch line, and hides untracked files")
    func ignoresTheUsersStatusConfiguration() async throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/café.png", data: Data([0x01]))
        try repository.commit()
        try repository.configure("color.status", "always")
        try repository.configure("status.branch", "true")
        try repository.configure("status.showUntrackedFiles", "no")
        try repository.configure("core.quotePath", "true")
        try repository.write("Snapshots/café.png", data: Data([0x02]))
        try repository.write("Snapshots/ünï.png", data: Data([0x03]))

        let statuses = try await service.status(repositoryRoot: repository.url)

        #expect(statuses == [
            repository.url.appendingPathComponent("Snapshots/café.png").standardizedFileURL: .modified,
            repository.url.appendingPathComponent("Snapshots/ünï.png").standardizedFileURL: .untracked,
        ])
    }

    @Test("A staged rename reports the new path added and the old one deleted")
    func reportsARealRename() async throws {
        let repository = try GitFixture()
        try repository.write("Snapshots/old.png", data: Data(repeating: 0x07, count: 512))
        try repository.commit()
        try FileManager.default.moveItem(
            at: repository.url.appendingPathComponent("Snapshots/old.png"),
            to: repository.url.appendingPathComponent("Snapshots/nüevo.png")
        )
        try repository.stage("Snapshots/old.png")
        try repository.stage("Snapshots/nüevo.png")

        let statuses = try await service.status(repositoryRoot: repository.url)

        #expect(statuses == [
            repository.url.appendingPathComponent("Snapshots/nüevo.png").standardizedFileURL: .added,
            repository.url.appendingPathComponent("Snapshots/old.png").standardizedFileURL: .deleted,
        ])
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
