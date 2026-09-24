//
//  SwiftPointFreeLegacyProvider.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Recognises the layout swift-snapshot-testing writes by default.
///
/// ```
/// Tests/
///     ButtonTests.swift
///     __Snapshots__/ButtonTests/button.1.png
/// ```
///
/// The test file sits beside `__Snapshots__` rather than anywhere in the tree, so a suite is
/// linked to its source by adjacency first and by name across the project second.
struct SwiftPointFreeLegacyProvider: SnapshotProvider {
    /// Folder swift-snapshot-testing writes recorded images into.
    static let snapshotsFolderName = "__Snapshots__"
    /// Suffix the library's own convention gives a test file.
    static let testFileSuffix = "Tests"

    let id = "swift.pointfree"
    let displayName = "Point-Free Snapshots"

    private let ignoreFilter: ProviderIgnoreFilter

    init(ignoreFilter: ProviderIgnoreFilter = ProviderIgnoreFilter()) {
        self.ignoreFilter = ignoreFilter
    }

    func canHandle(projectRoot: URL, filesystem: any FilesystemService) async -> Bool {
        let contents = try? treeContents(under: projectRoot, filesystem: filesystem, ignoring: ignoreFilter)
        return contents?.directories.contains { $0.lastPathComponent == Self.snapshotsFolderName } ?? false
    }

    func discoverSuites(in projectRoot: URL, filesystem: any FilesystemService) async throws -> [SnapshotSuite] {
        let contents = try treeContents(under: projectRoot, filesystem: filesystem, ignoring: ignoreFilter)
        let filesByParent = contents.filesByParentPath()
        let sourceFiles = swiftFileIndex(in: contents)

        var suites: [SnapshotSuite] = []

        for folder in contents.directories where folder.lastPathComponent == Self.snapshotsFolderName {
            try Task.checkCancellation()
            let parent = folder.deletingLastPathComponent()
            let suiteFolders = contents.directories.filter {
                $0.deletingLastPathComponent().path == folder.path
            }
            let filesBySuite = contents.filesByNearestFolder(among: Set(suiteFolders.map(\.path)))

            for directory in suiteFolders {
                let items = snapshotItems(in: filesBySuite[directory.path] ?? [], relativeTo: directory)
                guard !items.isEmpty else { continue }

                let name = directory.lastPathComponent
                suites.append(
                    SnapshotSuite(
                        name: name,
                        sourceCodeURL: adjacentTestFile(
                            named: name,
                            beside: parent,
                            in: filesByParent,
                            // One suite beside one test file is unambiguous; several suites
                            // sharing a folder are not, and a wrong link is worse than none.
                            allowingSuffixMatch: suiteFolders.count == 1
                        ) ?? sourceFiles[name],
                        snapshotsFolderURL: directory,
                        snapshots: items,
                        providerId: id
                    )
                )
            }

            // Older recordings drop images straight into __Snapshots__, with no folder per
            // class; the suite then takes its name from the folder holding the test file.
            let flatItems = snapshotItems(in: filesByParent[folder.path] ?? [], relativeTo: folder)
            guard !flatItems.isEmpty else { continue }

            let name = parent.lastPathComponent
            suites.append(
                SnapshotSuite(
                    name: name,
                    sourceCodeURL: adjacentTestFile(
                        named: name,
                        beside: parent,
                        in: filesByParent,
                        allowingSuffixMatch: true
                    ),
                    snapshotsFolderURL: folder,
                    snapshots: flatItems,
                    providerId: id
                )
            )
        }

        return suites.sorted { $0.name < $1.name }
    }

    /// Looks the suite up by name across the project.
    ///
    /// Adjacency cannot help here the way it does in ``discoverSuites(in:filesystem:)``:
    /// a bare suite name carries no folder to be adjacent to.
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

    /// The test file next to a `__Snapshots__` folder that records `name`.
    private func adjacentTestFile(
        named name: String,
        beside directory: URL,
        in filesByParent: [String: [URL]],
        allowingSuffixMatch: Bool
    ) -> URL? {
        let swiftFiles = (filesByParent[directory.path] ?? [])
            .filter { $0.pathExtension.lowercased() == "swift" }

        if let exact = swiftFiles.first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
            return exact
        }
        guard allowingSuffixMatch else { return nil }

        let testFiles = swiftFiles.filter {
            $0.deletingPathExtension().lastPathComponent.hasSuffix(Self.testFileSuffix)
        }
        return testFiles.count == 1 ? testFiles[0] : nil
    }
}
