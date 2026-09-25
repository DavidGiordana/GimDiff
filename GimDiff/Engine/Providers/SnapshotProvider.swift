//
//  SnapshotProvider.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Recognises one project layout and reports the snapshot suites it holds.
///
/// Snapshot libraries disagree about where images live, so a provider exists per
/// convention and ``ProviderRegistry`` picks the first that claims a project.
protocol SnapshotProvider: Sendable {
    /// Stable identifier recorded on every suite this provider produces.
    var id: String { get }
    /// Name shown when GimDiff reports which layout it recognised.
    var displayName: String { get }

    /// Whether this provider recognises the layout under `projectRoot`.
    func canHandle(projectRoot: URL, filesystem: any FilesystemService) async -> Bool

    /// Every snapshot suite the provider finds under `projectRoot`.
    ///
    /// Items come back with `gitStatus` left at ``GitFileStatus/unmodified``; annotating
    /// them against a working tree is ``ProviderRegistry``'s job.
    func discoverSuites(in projectRoot: URL, filesystem: any FilesystemService) async throws -> [SnapshotSuite]

    /// The test source file that records `suiteName`, when one can be located.
    func resolveSourceFile(
        for suiteName: String,
        in projectRoot: URL,
        filesystem: any FilesystemService
    ) async -> URL?
}

/// One pass over a project tree, with ignored subtrees already pruned.
///
/// Discovery needs directories and files together — the folders that look like snapshot
/// containers, and the `.swift` files that name the suites inside them — so the walk
/// collects both at once rather than being run twice.
struct ProjectTreeContents: Sendable, Equatable {
    /// Every directory beneath the root, the root itself excluded.
    var directories: [URL]
    /// Every regular file beneath the root, including its immediate children.
    var files: [URL]

    /// Files grouped by the path of the directory holding them.
    ///
    /// Keyed by path rather than by `URL`, because `deletingLastPathComponent()` leaves a
    /// trailing slash behind and the same folder would otherwise hash two different ways.
    func filesByParentPath() -> [String: [URL]] {
        Dictionary(grouping: files) { $0.deletingLastPathComponent().path }
    }

    /// Files grouped by the closest folder in `folderPaths` that contains them.
    ///
    /// Suites often sort their images into subfolders — one per device, appearance, or
    /// locale — so a suite has to claim its whole subtree rather than only the files lying
    /// directly inside it. Matching the *nearest* ancestor keeps a nested suite's images
    /// with the nested suite instead of the one above it.
    func filesByNearestFolder(among folderPaths: Set<String>) -> [String: [URL]] {
        var grouped: [String: [URL]] = [:]

        for file in files {
            var current = file.deletingLastPathComponent().path
            while current != "/", !current.isEmpty {
                if folderPaths.contains(current) {
                    grouped[current, default: []].append(file)
                    break
                }
                current = (current as NSString).deletingLastPathComponent
            }
        }

        return grouped
    }
}

extension SnapshotProvider {
    /// Walks `root`, refusing to descend into anything `filter` prunes.
    ///
    /// The filter is asked about each child as the walk descends, so a pruned name is
    /// pruned at any depth: a `DerivedData` inside a feature module is skipped exactly like
    /// one at the project root. `root` itself is deliberately exempt — opening a folder is
    /// an explicit instruction to look in it, even when it is named like a cache.
    ///
    /// Cancellation is checked once per directory: a scan of a large repository should stop
    /// promptly when the window closes or a newer scan supersedes it.
    func treeContents(
        under root: URL,
        filesystem: any FilesystemService,
        ignoring filter: ProviderIgnoreFilter
    ) throws -> ProjectTreeContents {
        var directories: [URL] = []
        var files: [URL] = []
        var visited: Set<String> = []
        var pending = [root.standardizedFileURL]

        while let directory = pending.popLast() {
            try Task.checkCancellation()
            // Listing follows symlinks, so a link pointing back up the tree would otherwise
            // be walked forever. Children of a link come back under their resolved paths,
            // which is what makes the path enough to recognise a folder already seen.
            guard visited.insert(directory.path).inserted else { continue }
            // An unreadable directory is skipped rather than failing the scan: one folder
            // the user cannot read should not hide every snapshot beside it.
            guard let children = try? filesystem.contentsOfDirectory(at: directory) else { continue }

            for child in children.map(\.standardizedFileURL) {
                guard filesystem.isDirectory(at: child) else {
                    files.append(child)
                    continue
                }
                guard !filter.shouldIgnore(url: child), !filesystem.isPackage(at: child) else {
                    continue
                }
                directories.append(child)
                pending.append(child)
            }
        }

        return ProjectTreeContents(
            directories: directories.sorted { $0.path < $1.path },
            files: files.sorted { $0.path < $1.path }
        )
    }

    /// Every `.swift` file in `contents`, keyed by file name without its extension.
    ///
    /// Where two modules declare the same test class name the shallower path wins, which is
    /// the one a developer is more likely to mean.
    func swiftFileIndex(in contents: ProjectTreeContents) -> [String: URL] {
        var index: [String: URL] = [:]

        for file in contents.files where file.pathExtension.lowercased() == "swift" {
            let name = file.deletingPathExtension().lastPathComponent
            guard let existing = index[name] else {
                index[name] = file
                continue
            }
            if file.pathComponents.count < existing.pathComponents.count {
                index[name] = file
            }
        }

        return index
    }

    /// Splits `<testMethod>.<counter>.png` into the method name and its counter.
    ///
    /// A file with no trailing counter keeps its whole name and reports no index, which is
    /// what a test recording a single snapshot produces.
    func decomposeSnapshotName(_ fileURL: URL) -> (name: String, variantIndex: Int?) {
        SnapshotItem.decomposeName(of: fileURL)
    }

    /// Builds the items for one suite from the images anywhere beneath its folder.
    ///
    /// `extensions` defaults to the formats ``ImageFormat`` models, so the discovery filter
    /// and the display layer can never disagree about what counts as a snapshot.
    func snapshotItems(
        in files: [URL],
        relativeTo suiteFolder: URL,
        extensions: Set<String>? = nil
    ) -> [SnapshotItem] {
        files
            .filter { file in
                guard let extensions else { return ImageFormat(url: file).isRecognized }
                return extensions.contains(file.pathExtension.lowercased())
            }
            .sorted { $0.path < $1.path }
            .map { file in
                let decomposed = decomposeSnapshotName(file)
                return SnapshotItem(
                    name: qualifiedName(decomposed.name, of: file, under: suiteFolder),
                    variantIndex: decomposed.variantIndex,
                    fileURL: file
                )
            }
    }

    /// Prefixes a nested snapshot with the folders between it and its suite.
    ///
    /// A suite that records the same test for several devices writes the same file name in
    /// each device's folder; without the prefix the sidebar would show two entries that
    /// read identically.
    private func qualifiedName(_ name: String, of file: URL, under suiteFolder: URL) -> String {
        let directory = file.deletingLastPathComponent().path
        let prefix = suiteFolder.path + "/"
        guard directory != suiteFolder.path, directory.hasPrefix(prefix) else { return name }
        return String(directory.dropFirst(prefix.count)) + "/" + name
    }
}
