//
//  GitRepository.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Reads and mutates the Git working tree that holds a set of snapshots.
struct GitRepository: Sendable {
    /// Any directory inside the working tree.
    let directory: URL
    private let runner: any CommandRunning

    init(directory: URL, runner: any CommandRunning) {
        self.directory = directory
        self.runner = runner
    }

    /// The absolute root of the working tree containing ``directory``.
    func toplevel() async throws -> URL {
        let result = try await runner.run(GitCommand.revParseToplevel(in: directory))
        guard result.isSuccess else { throw GimDiffError.notARepository(directory) }
        return URL(fileURLWithPath: result.trimmedOutput).standardizedFileURL
    }

    /// The checked-out branch name, or `HEAD` when the repository is in a detached state.
    func currentBranch() async throws -> String {
        try await succeeding(GitCommand.currentBranch(in: directory), named: "git rev-parse").trimmedOutput
    }

    /// Paths reported as changed or untracked, resolved against the working tree root.
    func changedPaths() async throws -> [URL] {
        let root = try await toplevel()
        // Porcelain output is read untrimmed: the status flags live in the first two
        // columns, and an unmodified-in-index entry leads with a significant space.
        let status = try await succeeding(GitCommand.status(in: directory), named: "git status").standardOutput

        return status.split(separator: "\n").compactMap { line in
            // Porcelain v1 records are "XY <path>"; the status flags occupy the first two columns.
            guard line.count > 3 else { return nil }
            let path = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            return root.appendingPathComponent(path).standardizedFileURL
        }
    }

    /// Discards local changes to `paths`, restoring the committed snapshots.
    func restore(paths: [URL]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await succeeding(GitCommand.checkout(paths: paths, in: directory), named: "git checkout")
    }

    /// Runs `command`, turning a non-zero exit into an error carrying git's own message.
    private func succeeding(_ command: Command, named name: String) async throws -> CommandResult {
        let result = try await runner.run(command)
        guard result.isSuccess else {
            throw GimDiffError.commandFailed(
                command: name,
                exitCode: result.exitCode,
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }
}
