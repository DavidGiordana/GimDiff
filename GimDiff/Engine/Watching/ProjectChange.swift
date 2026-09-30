//
//  ProjectChange.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What a batch of file events asks of the open project.
///
/// Three answers of rising cost, kept apart so the common case stays cheap: a test run
/// rewriting the bytes of snapshots that are already in the tree needs the canvas redrawn
/// and the badges recomputed, not the project walked again.
struct ProjectChange: Sendable, Equatable {
    /// Paths of snapshots already in the tree whose bytes were rewritten in place.
    var rewrittenSnapshotPaths: Set<String> = []
    /// Whether the standing of the snapshots against `HEAD` may have moved.
    var needsGitStatus = false
    /// Whether snapshots, suites, or test sources came or went, so the tree itself is stale.
    var needsRescan = false

    var isEmpty: Bool {
        !needsRescan && !needsGitStatus && rewrittenSnapshotPaths.isEmpty
    }

    mutating func formUnion(_ other: ProjectChange) {
        rewrittenSnapshotPaths.formUnion(other.rewrittenSnapshotPaths)
        needsGitStatus = needsGitStatus || other.needsGitStatus
        needsRescan = needsRescan || other.needsRescan
    }
}

/// Reads a batch of file events against the project they happened in.
///
/// Most of what a volume reports is noise as far as GimDiff is concerned — build products,
/// Git's object store, every source file saved in an editor — and a build can report
/// thousands of paths a second. So an event is dropped on its path alone wherever it can
/// be, and the disk is only asked about the few that could matter.
struct ProjectChangeClassifier: Sendable {
    /// Marker that identifies a working tree root; a file in a worktree, a folder otherwise.
    static let gitDirectoryName = ".git"

    private let filesystem: any FilesystemService
    private let filter: ProviderIgnoreFilter

    init(filesystem: any FilesystemService, filter: ProviderIgnoreFilter = ProviderIgnoreFilter()) {
        self.filesystem = filesystem
        self.filter = filter
    }

    /// Where the repository holding `project` keeps its metadata, when it is in one.
    static func gitDirectory(of project: ProjectBundle) -> URL? {
        project.gitRootURL?.appendingPathComponent(gitDirectoryName, isDirectory: true)
    }

    func classify(_ events: [ProjectFileEvent], in project: ProjectBundle) -> ProjectChange {
        var change = ProjectChange()
        let rootPath = project.rootURL.standardizedFileURL.path
        let gitPath = Self.gitDirectory(of: project)?.standardizedFileURL.path
        // Built on first use: a batch made entirely of build products never needs it.
        var index: KnownFiles?

        for event in events {
            let path = event.url.standardizedFileURL.path

            if let gitPath, let inside = Self.relativePath(of: path, under: gitPath) {
                if Self.movesHead(inside) { change.needsGitStatus = true }
                continue
            }

            guard let relative = Self.relativePath(of: path, under: rootPath) else { continue }
            // The root itself is how a watcher says it lost track and everything is suspect.
            guard !relative.isEmpty else {
                change.needsRescan = true
                continue
            }
            guard !isPruned(relative, under: rootPath, isDirectory: event.isDirectory) else { continue }

            // A folder is only reported when it is created, removed, or renamed, and a
            // rename carries every snapshot inside it to a new path without naming one.
            guard !event.isDirectory else {
                change.needsRescan = true
                continue
            }

            let known = index ?? KnownFiles(project)
            index = known
            classify(fileAt: path, relativePath: relative, known: known, into: &change)
        }

        return change
    }

    private func classify(
        fileAt path: String,
        relativePath: String,
        known: KnownFiles,
        into change: inout ProjectChange
    ) {
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.lowercased()

        if known.snapshotPaths.contains(path) {
            if filesystem.fileExists(at: url) {
                change.rewrittenSnapshotPaths.insert(path)
                change.needsGitStatus = true
            } else {
                change.needsRescan = true
            }
        } else if ImageFormat(fileExtension: fileExtension).isRecognized
            || known.snapshotExtensions.contains(fileExtension) {
            // An image that is already gone again was a scratch file on its way to being
            // renamed over a snapshot, and the rename is reported under the snapshot's name.
            if filesystem.fileExists(at: url) { change.needsRescan = true }
        } else if relativePath == ConfigDrivenProvider.configurationFileName {
            change.needsRescan = true
        } else if fileExtension == "swift" {
            // Saving a test file says nothing about its snapshots. Only a source that went
            // away, or one arriving under the name of a suite that had none, moves a warning.
            if known.sourcePaths.contains(path) {
                if !filesystem.fileExists(at: url) { change.needsRescan = true }
            } else if known.suiteNamesMissingSource.contains(url.deletingPathExtension().lastPathComponent),
                      filesystem.fileExists(at: url) {
                change.needsRescan = true
            }
        }
    }

    /// Whether discovery would never have walked to `relativePath`.
    ///
    /// The same filter the scan descends with, asked about every folder on the way down:
    /// what a scan cannot find, a change cannot have altered.
    private func isPruned(_ relativePath: String, under rootPath: String, isDirectory: Bool) -> Bool {
        var components = relativePath.split(separator: "/")
        if !isDirectory { components.removeLast() }

        var current = rootPath
        for component in components {
            current += "/" + component
            if filter.shouldIgnore(url: URL(fileURLWithPath: current, isDirectory: true)) { return true }
        }
        return false
    }

    /// Whether a path inside the Git directory is one a commit or a checkout rewrites.
    ///
    /// The index is deliberately not among them. `git status` refreshes it as a side
    /// effect, so reading the status in answer to an index change would be answering
    /// GimDiff's own question for ever. What clears or sets a badge without touching a
    /// snapshot is `HEAD` moving, and that always passes through one of these.
    static func movesHead(_ relativePath: String) -> Bool {
        guard !relativePath.hasSuffix(".lock") else { return false }
        return relativePath == "HEAD"
            || relativePath == "packed-refs"
            || relativePath.hasPrefix("refs/heads/")
    }

    /// `path` relative to `root`: empty for the root itself, `nil` when it is outside.
    static func relativePath(of path: String, under root: String) -> String? {
        guard path != root else { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}

/// The paths a project already accounts for, which is what tells a rewrite from an arrival.
private struct KnownFiles {
    var snapshotPaths: Set<String> = []
    /// Extensions the project's snapshots carry, so a configuration that collects a format
    /// GimDiff would not pick up by default still has its new files noticed.
    var snapshotExtensions: Set<String> = []
    var sourcePaths: Set<String> = []
    var suiteNamesMissingSource: Set<String> = []

    init(_ project: ProjectBundle) {
        for suite in project.suites {
            if let source = suite.sourceCodeURL {
                sourcePaths.insert(source.standardizedFileURL.path)
            } else {
                suiteNamesMissingSource.insert(suite.name)
            }
            for snapshot in suite.snapshots {
                snapshotPaths.insert(snapshot.fileURL.standardizedFileURL.path)
                snapshotExtensions.insert(snapshot.fileURL.pathExtension.lowercased())
            }
        }
    }
}
