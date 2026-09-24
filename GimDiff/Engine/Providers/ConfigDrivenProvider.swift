//
//  ConfigDrivenProvider.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A project's own description of where its snapshots live.
///
/// Every field is optional: a configuration that sets one thing should not have to restate
/// the defaults for everything else.
struct GimDiffConfiguration: Codable, Sendable, Equatable {
    /// Folder holding the suites, either a path relative to the project root or a folder
    /// name to look for anywhere in the tree.
    var snapshotsDirectory: String?
    /// File extensions to collect, replacing the formats GimDiff recognises by default.
    var extensions: [String]?
    /// Path template for a suite's test file, relative to the project root, in which
    /// ``ConfigDrivenProvider/suitePlaceholder`` stands for the suite name.
    var testFilePattern: String?
    /// Extra folders to prune, on top of the standard build and cache directories.
    var ignoredPaths: [String]?
}

/// Discovers snapshots the way a project's `.gimdiffrc.json` says to.
///
/// Sits first in the registry so a project that describes itself is never second-guessed by
/// the conventions the other providers assume.
struct ConfigDrivenProvider: SnapshotProvider {
    /// Name of the file a project drops in its root to configure GimDiff.
    static let configurationFileName = ".gimdiffrc.json"
    /// Token replaced by the suite name inside ``GimDiffConfiguration/testFilePattern``.
    static let suitePlaceholder = "{suite}"

    let id = "config"
    let displayName = "Project Configuration"

    init() {}

    func canHandle(projectRoot: URL, filesystem: any FilesystemService) async -> Bool {
        configuration(in: projectRoot, filesystem: filesystem) != nil
    }

    func discoverSuites(in projectRoot: URL, filesystem: any FilesystemService) async throws -> [SnapshotSuite] {
        guard let configuration = configuration(in: projectRoot, filesystem: filesystem) else { return [] }

        let filter = ProviderIgnoreFilter(additionalIgnoredPaths: configuration.ignoredPaths ?? [])
        let contents = try treeContents(under: projectRoot, filesystem: filesystem, ignoring: filter)
        let filesByParent = contents.filesByParentPath()
        let extensions = configuration.extensions.map { Set($0.map { $0.lowercased() }) }
        let sourceFiles = swiftFileIndex(in: contents)

        var suites: [SnapshotSuite] = []

        for root in snapshotRoots(for: configuration, in: projectRoot, contents: contents, filesystem: filesystem) {
            try Task.checkCancellation()

            // A suite per subfolder, which is how every layout GimDiff knows is arranged.
            let subdirectories = contents.directories.filter {
                $0.deletingLastPathComponent().path == root.path
            }
            let filesBySuite = contents.filesByNearestFolder(among: Set(subdirectories.map(\.path)))
            for directory in subdirectories {
                let items = snapshotItems(
                    in: filesBySuite[directory.path] ?? [],
                    relativeTo: directory,
                    extensions: extensions
                )
                guard !items.isEmpty else { continue }
                suites.append(
                    suite(
                        named: directory.lastPathComponent,
                        folder: directory,
                        items: items,
                        configuration: configuration,
                        projectRoot: projectRoot,
                        filesystem: filesystem,
                        sourceFiles: sourceFiles
                    )
                )
            }

            // A flat folder of images is a single suite named after the folder itself.
            let flatItems = snapshotItems(
                in: filesByParent[root.path] ?? [],
                relativeTo: root,
                extensions: extensions
            )
            guard !flatItems.isEmpty else { continue }
            suites.append(
                suite(
                    named: root.lastPathComponent,
                    folder: root,
                    items: flatItems,
                    configuration: configuration,
                    projectRoot: projectRoot,
                    filesystem: filesystem,
                    sourceFiles: sourceFiles
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
        let configuration = configuration(in: projectRoot, filesystem: filesystem)

        if let url = patternedSourceFile(
            for: suiteName,
            configuration: configuration,
            projectRoot: projectRoot,
            filesystem: filesystem
        ) {
            return url
        }

        let filter = ProviderIgnoreFilter(additionalIgnoredPaths: configuration?.ignoredPaths ?? [])
        guard let contents = try? treeContents(
            under: projectRoot,
            filesystem: filesystem,
            ignoring: filter
        ) else { return nil }

        return swiftFileIndex(in: contents)[suiteName]
    }

    /// Reads and decodes `.gimdiffrc.json`, or `nil` when it is absent or malformed.
    ///
    /// A file GimDiff cannot parse is treated as no configuration at all, so a typo demotes
    /// the project to convention-based discovery instead of showing nothing.
    func configuration(in projectRoot: URL, filesystem: any FilesystemService) -> GimDiffConfiguration? {
        let url = projectRoot.appendingPathComponent(Self.configurationFileName)
        guard let data = try? filesystem.readFile(at: url) else { return nil }
        return try? JSONDecoder().decode(GimDiffConfiguration.self, from: data)
    }

    /// The folders to look inside, from an explicit relative path or a folder name.
    private func snapshotRoots(
        for configuration: GimDiffConfiguration,
        in projectRoot: URL,
        contents: ProjectTreeContents,
        filesystem: any FilesystemService
    ) -> [URL] {
        let configured = configuration.snapshotsDirectory ?? SwiftModularProvider.snapshotsFolderName
        let explicit = projectRoot.appendingPathComponent(configured).standardizedFileURL
        if filesystem.isDirectory(at: explicit) { return [explicit] }

        return contents.directories.filter { $0.lastPathComponent == configured }
    }

    private func suite(
        named name: String,
        folder: URL,
        items: [SnapshotItem],
        configuration: GimDiffConfiguration,
        projectRoot: URL,
        filesystem: any FilesystemService,
        sourceFiles: [String: URL]
    ) -> SnapshotSuite {
        let patterned = patternedSourceFile(
            for: name,
            configuration: configuration,
            projectRoot: projectRoot,
            filesystem: filesystem
        )

        return SnapshotSuite(
            name: name,
            sourceCodeURL: patterned ?? sourceFiles[name],
            snapshotsFolderURL: folder,
            snapshots: items,
            providerId: id
        )
    }

    /// Resolves `testFilePattern` for one suite, when the pattern names the suite at all.
    private func patternedSourceFile(
        for suiteName: String,
        configuration: GimDiffConfiguration?,
        projectRoot: URL,
        filesystem: any FilesystemService
    ) -> URL? {
        guard let pattern = configuration?.testFilePattern,
              pattern.contains(Self.suitePlaceholder)
        else { return nil }

        let relativePath = pattern.replacingOccurrences(of: Self.suitePlaceholder, with: suiteName)
        let url = projectRoot.appendingPathComponent(relativePath).standardizedFileURL
        return filesystem.fileExists(at: url) ? url : nil
    }
}
