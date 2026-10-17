//
//  ScanCommand.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// `gimdiff scan <projectPath> [--json]`
///
/// Runs the same discovery the sidebar runs, with no window and no app.
enum ScanCommand {
    static let name = "scan"
    static let summary = "List the snapshot suites in a project."
    static let usage = """
    Usage: gimdiff scan <project-path> [--json]

      Scans a project folder for snapshot suites and reports how many snapshots each
      holds, and how many of them differ from what the repository has committed.

      --json   Emit the result as JSON instead of text.
    """

    static let valueOptions: Set<String> = []
    static let knownOptions: Set<String> = ["json"]

    static func run(_ arguments: Arguments, console: Console) async throws -> ExitStatus {
        try arguments.rejectOptions(outside: knownOptions)
        try arguments.rejectPositionalArguments(beyond: 1)

        let projectURL = try arguments.fileURL(at: 0, named: "project-path")
        let scanner = ProjectScanner(
            filesystem: DefaultFilesystemService(),
            gitService: DefaultGitService()
        )
        let bundle = try await scanner.scan(projectRoot: projectURL)

        if arguments.hasFlag("json") {
            console.write(try JSONOutput.encode(Report(bundle)))
        } else {
            writeText(bundle, to: console)
        }

        return bundle.hasGitDiff ? .differencesFound : .success
    }

    // MARK: - Text

    private static func writeText(_ bundle: ProjectBundle, to console: Console) {
        console.write("Project", bundle.rootURL.path)
        console.write("Git root", bundle.gitRootURL?.path ?? "(not a repository)")
        console.write("Suites", String(bundle.suites.count))
        console.write("Snapshots", String(bundle.snapshotsCount))
        console.write("Modified", String(bundle.modifiedSnapshotsCount))

        guard !bundle.suites.isEmpty else {
            console.write()
            console.write("No snapshot suites were found.")
            return
        }

        for suite in bundle.suites {
            console.write()
            console.write("\(suite.name)  [\(suite.providerId)]")
            console.write(
                "  \(suite.snapshots.count) snapshots, \(suite.modifiedSnapshotsCount) modified"
            )

            for snapshot in suite.snapshots where snapshot.hasGitDiff {
                let marker = switch snapshot.gitStatus {
                case .untracked: "?"
                case .added: "A"
                default: "M"
                }
                console.write("  \(marker)  \(snapshot.fileURL.path(relativeTo: bundle.rootURL))")
            }
        }
    }

    // MARK: - JSON

    private struct Report: Encodable {
        var project: String
        var gitRoot: String?
        var suiteCount: Int
        var snapshotCount: Int
        var modifiedSnapshotCount: Int
        var suites: [Suite]

        init(_ bundle: ProjectBundle) {
            project = bundle.rootURL.path
            gitRoot = bundle.gitRootURL?.path
            suiteCount = bundle.suites.count
            snapshotCount = bundle.snapshotsCount
            modifiedSnapshotCount = bundle.modifiedSnapshotsCount
            suites = bundle.suites.map { Suite($0, relativeTo: bundle.rootURL) }
        }

        struct Suite: Encodable {
            var name: String
            var provider: String
            var folder: String
            var snapshotCount: Int
            var modifiedSnapshotCount: Int
            var modifiedSnapshots: [ModifiedSnapshot]

            init(_ suite: SnapshotSuite, relativeTo root: URL) {
                name = suite.name
                provider = suite.providerId
                folder = suite.snapshotsFolderURL.path(relativeTo: root)
                snapshotCount = suite.snapshots.count
                modifiedSnapshotCount = suite.modifiedSnapshotsCount
                modifiedSnapshots = suite.snapshots
                    .filter(\.hasGitDiff)
                    .map { ModifiedSnapshot($0, relativeTo: root) }
            }
        }

        struct ModifiedSnapshot: Encodable {
            var name: String
            var path: String
            var status: String

            init(_ snapshot: SnapshotItem, relativeTo root: URL) {
                name = snapshot.displayName
                path = snapshot.fileURL.path(relativeTo: root)
                status = switch snapshot.gitStatus {
                case .untracked: "untracked"
                case .added: "added"
                default: "modified"
                }
            }
        }
    }
}
