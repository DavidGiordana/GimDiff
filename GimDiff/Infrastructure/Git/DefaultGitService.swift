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
        let command = GitCommand.status(in: repositoryRoot)
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

    func discardChanges(to fileURLs: [URL], repositoryRoot: URL) async throws {
        guard !fileURLs.isEmpty else { return }
        let result = try await runner.run(GitCommand.restoreFromHEAD(paths: fileURLs, in: repositoryRoot))
        guard result.isSuccess else {
            throw GimDiffError.commandFailed(
                command: "git restore",
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    func isTracked(_ fileURL: URL, repositoryRoot: URL) async -> Bool? {
        guard let result = try? await runner.run(
            GitCommand.lsFilesErrorUnmatch(path: fileURL, in: repositoryRoot)
        ) else { return nil }
        // `--error-unmatch` exits 1 for a path Git does not track; anything else is git
        // failing to answer, not an answer.
        switch result.exitCode {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    func extractCommittedVersion(
        ofFileAt relativePath: String,
        repositoryRoot: URL,
        gitRef: String
    ) async throws -> URL {
        let normalized = GitCommand.normalize(relativePath)
        let destination = filesystem.createTemporaryFile(
            prefix: Self.temporaryFilePrefix(for: normalized, gitRef: gitRef),
            extension: (normalized as NSString).pathExtension
        )
        // The handle below opens an existing file, and it is also what guarantees the
        // enclosing directory is there before git starts writing.
        try filesystem.writeFile(at: destination, data: Data())

        let arguments = GitCommand.show(
            ofFileAt: normalized,
            gitRef: gitRef,
            in: repositoryRoot
        ).arguments

        // Cancelled when the canvas moves on before git has finished writing.
        let running = CancellableProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { [filesystem] continuation in
                Self.queue.async {
                    continuation.resume(with: Result {
                        do {
                            try Self.stream(arguments: arguments, in: repositoryRoot, to: destination, as: running)
                        } catch {
                            // Whatever git managed to write is not the committed file.
                            try? filesystem.removeItem(at: destination)
                            throw error
                        }
                        return destination
                    })
                }
            }
        } onCancel: {
            running.cancel()
        }
    }

    // MARK: - Status parsing

    /// Turns `git status --porcelain=v1 -z` output into absolute paths and their status.
    ///
    /// Each record is `XY <path>` ended by a NUL: two status columns, a space, then the path
    /// exactly as it is spelled. A rename or a copy is followed by one more field, the path
    /// it came from. Ignored files and records whose columns are blank are dropped rather
    /// than reported as unmodified.
    static func parseStatus(_ output: String, repositoryRoot: URL) -> [URL: GitFileStatus] {
        var statuses: [URL: GitFileStatus] = [:]
        var fields = output.split(separator: "\0").makeIterator()

        func url(_ path: Substring) -> URL {
            repositoryRoot.appendingPathComponent(String(path)).standardizedFileURL
        }

        while let record = fields.next() {
            guard record.count > 3 else { continue }
            let code = String(record.prefix(2))

            if code.contains("R") || code.contains("C") {
                let source = fields.next()
                // `HEAD` still has a rename's old path, and restoring the project brings it
                // back. A copy's source is still where it was, so it says nothing.
                if code.contains("R"), let source {
                    statuses[url(source)] = .deleted
                }
            }

            guard let status = status(forCode: code) else { continue }
            statuses[url(record.dropFirst(3))] = status
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
        // The index column names a path new to the index: added, or a rename's or copy's
        // destination. None of them is at `HEAD`.
        case _ where "ARC".contains(code.prefix(1)): .added
        default: .modified
        }
    }

    // MARK: - Process

    /// Runs git with stdout wired straight to `destination`.
    ///
    /// Snapshots are binary, so the bytes never pass through a `String` the way
    /// ``CommandRunning`` results do; they go from the pipe to the file untouched.
    private static func stream(
        arguments: [String],
        in repositoryRoot: URL,
        to destination: URL,
        as running: CancellableProcess
    ) throws {
        let process = Process()
        process.executableURL = GitCommand.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        try running.start(process)
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if running.isCancelled { throw CancellationError() }
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

    /// A file name that identifies the extracted image without leaking path separators.
    private static func temporaryFilePrefix(for relativePath: String, gitRef: String) -> String {
        let name = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let ref = gitRef.replacingOccurrences(of: "/", with: "-")
        return "\(name.isEmpty ? "snapshot" : name)-\(ref)"
    }
}
