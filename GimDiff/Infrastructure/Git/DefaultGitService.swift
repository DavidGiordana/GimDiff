//
//  DefaultGitService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// ``GitService`` that shells out to the `git` shipped with the developer tools.
///
/// Every invocation is a `Process` with a discrete argument array — never a shell string —
/// so a snapshot path containing spaces, quotes, or `$` reaches git verbatim and cannot be
/// reinterpreted.
struct DefaultGitService: GitService {
    /// Location of the Git executable.
    static let executableURL = URL(fileURLWithPath: "/usr/bin/git")
    /// Marker that identifies a working tree root; a file in a worktree, a folder otherwise.
    static let gitDirectoryName = ".git"

    private static let queue = DispatchQueue(
        label: "com.davidgiordana.GimDiff.git-service",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let runner: any CommandRunning
    private let filesystem: any FilesystemService

    init(
        runner: any CommandRunning = SystemCommandRunner(),
        filesystem: any FilesystemService = DefaultFilesystemService()
    ) {
        self.runner = runner
        self.filesystem = filesystem
    }

    // MARK: - Commands

    /// Short, machine-readable status of the working tree.
    static func statusCommand(in repositoryRoot: URL) -> Command {
        Command(
            executableURL: executableURL,
            arguments: ["status", "-s"],
            workingDirectory: repositoryRoot
        )
    }

    /// Writes the contents of `relativePath` at `gitRef` to standard output.
    static func showCommand(ofFileAt relativePath: String, gitRef: String, in repositoryRoot: URL) -> Command {
        Command(
            executableURL: executableURL,
            arguments: ["show", "\(gitRef):\(normalize(relativePath))"],
            workingDirectory: repositoryRoot
        )
    }

    // MARK: - GitService

    func findRepositoryRoot(for folderURL: URL) async -> URL? {
        let start = folderURL.standardizedFileURL
        // Paths rather than URLs: `deletingLastPathComponent()` leaves a trailing slash
        // behind, which would make the returned root unequal to the same folder spelled
        // any other way.
        var current = filesystem.isDirectory(at: start)
            ? start.path
            : start.deletingLastPathComponent().path

        while true {
            let directory = URL(fileURLWithPath: current, isDirectory: true)
            if filesystem.fileExists(at: directory.appendingPathComponent(Self.gitDirectoryName)) {
                return URL(fileURLWithPath: current)
            }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current else { return nil }
            current = parent
        }
    }

    func status(repositoryRoot: URL) async throws -> [URL: GitFileStatus] {
        let command = Self.statusCommand(in: repositoryRoot)
        let result = try await runner.run(command)
        guard result.isSuccess else {
            throw GimDiffError.commandFailed(
                command: "git status",
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return Self.parseStatus(result.standardOutput, repositoryRoot: repositoryRoot)
    }

    func remoteURL(named name: String, repositoryRoot: URL) async throws -> String {
        let result = try await runner.run(GitCommand.remoteURL(named: name, in: repositoryRoot))
        guard result.isSuccess, !result.trimmedOutput.isEmpty else {
            throw GimDiffError.commandFailed(
                command: "git remote get-url",
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.trimmedOutput
    }

    func extractCommittedVersion(
        ofFileAt relativePath: String,
        repositoryRoot: URL,
        gitRef: String
    ) async throws -> URL {
        let normalized = Self.normalize(relativePath)
        let destination = filesystem.createTemporaryFile(
            prefix: Self.temporaryFilePrefix(for: normalized, gitRef: gitRef),
            extension: (normalized as NSString).pathExtension
        )
        // The handle below opens an existing file, and it is also what guarantees the
        // enclosing directory is there before git starts writing.
        try filesystem.writeFile(at: destination, data: Data())

        let arguments = Self.showCommand(
            ofFileAt: normalized,
            gitRef: gitRef,
            in: repositoryRoot
        ).arguments

        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(with: Result {
                    try Self.stream(arguments: arguments, in: repositoryRoot, to: destination)
                    return destination
                })
            }
        }
    }

    // MARK: - Status parsing

    /// Turns `git status -s` output into absolute paths and their status.
    ///
    /// Records are `XY <path>`: two status columns, a space, then the path. Ignored files
    /// and records whose columns are blank are dropped rather than reported as unmodified.
    static func parseStatus(_ output: String, repositoryRoot: URL) -> [URL: GitFileStatus] {
        var statuses: [URL: GitFileStatus] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard line.count > 3 else { continue }
            guard let status = status(forCode: String(line.prefix(2))) else { continue }

            var path = String(line.dropFirst(3))
            // A rename reads "old -> new"; the new path is the one on disk.
            if let arrow = path.range(of: " -> ") {
                path = String(path[arrow.upperBound...])
            }
            path = unquote(path.trimmingCharacters(in: .whitespaces))
            guard !path.isEmpty else { continue }

            statuses[repositoryRoot.appendingPathComponent(path).standardizedFileURL] = status
        }

        return statuses
    }

    /// Maps the two status columns of a porcelain record onto a ``GitFileStatus``.
    ///
    /// - Returns: `nil` for records GimDiff has nothing to show for, such as ignored files.
    static func status(forCode code: String) -> GitFileStatus? {
        switch code {
        case "??": .untracked
        case "!!": nil
        case _ where code.contains("D"): .deleted
        case _ where code.trimmingCharacters(in: .whitespaces).isEmpty: nil
        default: .modified
        }
    }

    // MARK: - Process

    /// Runs git with stdout wired straight to `destination`.
    ///
    /// Snapshots are binary, so the bytes never pass through a `String` the way
    /// ``CommandRunning`` results do; they go from the pipe to the file untouched.
    private static func stream(arguments: [String], in repositoryRoot: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GimDiffError.commandFailed(
                command: "git show",
                exitCode: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // MARK: - Paths

    /// Strips the leading `./` or `/` that would make a repository-relative path absolute.
    static func normalize(_ relativePath: String) -> String {
        var path = relativePath
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    /// A file name that identifies the extracted image without leaking path separators.
    private static func temporaryFilePrefix(for relativePath: String, gitRef: String) -> String {
        let name = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let ref = gitRef.replacingOccurrences(of: "/", with: "-")
        return "\(name.isEmpty ? "snapshot" : name)-\(ref)"
    }

    /// Undoes the quoting git applies to paths holding unusual characters.
    private static func unquote(_ path: String) -> String {
        guard path.count > 1, path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        return String(path.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
