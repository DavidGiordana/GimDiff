//
//  SwiftModularProvider.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Recognises the layout modular Swift projects use: a `Snapshots/` folder per module, with
/// one subfolder per test suite.
///
/// ```
/// Features/Summary/Tests/Snapshots/CHSSummaryViewControllerSnapshotTests/
///     summaryVC_skeleton.1.png
///     summaryVC_loaded.1.png
/// ```
///
/// Tuist workspaces and SwiftPM packages both land here, which is why the marker files of
/// either are enough to claim a project.
struct SwiftModularProvider: SnapshotProvider {
    /// Folder name that holds one subfolder per suite.
    static let snapshotsFolderName = "Snapshots"
    /// Files that mark the root of a modular Swift project.
    static let projectMarkerFiles = ["Package.swift", "Project.swift", "Workspace.swift"]

    let id = "swift.modular"
    let displayName = "Swift Module Snapshots"

    private let ignoreFilter: ProviderIgnoreFilter

    init(ignoreFilter: ProviderIgnoreFilter = ProviderIgnoreFilter()) {
        self.ignoreFilter = ignoreFilter
    }

    func canHandle(projectRoot: URL, filesystem: any FilesystemService) async -> Bool {
        let marked = Self.projectMarkerFiles.contains {
            filesystem.fileExists(at: projectRoot.appendingPathComponent($0))
        }
        if marked { return true }

        let children = (try? filesystem.contentsOfDirectory(at: projectRoot)) ?? []
        if children.contains(where: { $0.pathExtension == "xcodeproj" }) { return true }

        // No marker file: claim the project only if it actually holds a Snapshots folder.
        let contents = try? treeContents(under: projectRoot, filesystem: filesystem, ignoring: ignoreFilter)
        return contents?.directories.contains { $0.lastPathComponent == Self.snapshotsFolderName } ?? false
    }

    func discoverSuites(in projectRoot: URL, filesystem: any FilesystemService) async throws -> [SnapshotSuite] {
        let contents = try treeContents(under: projectRoot, filesystem: filesystem, ignoring: ignoreFilter)
        let sourceFiles = swiftFileIndex(in: contents)

        let snapshotFolderPaths = Set(
            contents.directories
                .filter { $0.lastPathComponent == Self.snapshotsFolderName }
                .map(\.path)
        )
        let suiteFolders = contents.directories.filter {
            snapshotFolderPaths.contains($0.deletingLastPathComponent().path)
        }
        let filesBySuite = contents.filesByNearestFolder(among: Set(suiteFolders.map(\.path)))

        var suites: [SnapshotSuite] = []

        for directory in suiteFolders {
            try Task.checkCancellation()

            let items = snapshotItems(in: filesBySuite[directory.path] ?? [], relativeTo: directory)
            guard !items.isEmpty else { continue }

            let name = directory.lastPathComponent
            suites.append(
                SnapshotSuite(
                    name: name,
                    sourceCodeURL: sourceFiles[name],
                    snapshotsFolderURL: directory,
                    snapshots: items,
                    providerId: id
                )
            )
        }

        return suites.sorted { $0.name < $1.name }
    }

    func resolveSourceFile(
        for suiteName: String,
        in projectRoot: URL,
        filesystem: any FilesystemService
    ) async -> URL? {
        guard let contents = try? treeContents(
            under: projectRoot,
            filesystem: filesystem,
            ignoring: ignoreFilter
        ) else { return nil }

        return swiftFileIndex(in: contents)[suiteName]
    }
}
