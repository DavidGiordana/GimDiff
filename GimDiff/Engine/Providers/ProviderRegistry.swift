//
//  ProviderRegistry.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Picks the provider that understands a project and annotates what it finds with Git status.
final class ProviderRegistry: Sendable {
    /// Providers in priority order: a project that describes itself wins, then the modern
    /// module layout, then the legacy one.
    static let defaultProviders: [any SnapshotProvider] = [
        ConfigDrivenProvider(),
        SwiftModularProvider(),
        SwiftPointFreeLegacyProvider(),
    ]

    let providers: [any SnapshotProvider]

    init(providers: [any SnapshotProvider] = ProviderRegistry.defaultProviders) {
        self.providers = providers
    }

    /// Suites under `projectRoot`, each item carrying its status in the working tree.
    func discoverSuites(
        in projectRoot: URL,
        filesystem: any FilesystemService,
        gitService: any GitService
    ) async throws -> [SnapshotSuite] {
        // Resolved so a symlinked path matches the paths discovery and git both report.
        let root = projectRoot.resolvingSymlinksInPath()
        return try await discoverSuites(
            in: root,
            filesystem: filesystem,
            gitService: gitService,
            repositoryRoot: await gitService.findRepositoryRoot(for: root)
        )
    }

    /// The same discovery, for a caller that has already located the working tree root.
    func discoverSuites(
        in projectRoot: URL,
        filesystem: any FilesystemService,
        gitService: any GitService,
        repositoryRoot: URL?
    ) async throws -> [SnapshotSuite] {
        let suites = try await discoverUnannotatedSuites(in: projectRoot, filesystem: filesystem)
        guard !suites.isEmpty, let repositoryRoot else { return suites }

        // Status is an enhancement, not the point: a repository GimDiff cannot read should
        // still show its snapshots, just without the changed markers.
        guard let statuses = try? await gitService.status(repositoryRoot: repositoryRoot) else {
            return suites
        }

        return Self.annotate(suites, with: statuses)
    }

    /// Runs the first provider that claims the project, falling through when it finds nothing.
    ///
    /// A marker file is enough for a provider to claim a project, so a package using the
    /// legacy layout would otherwise be claimed by the modular provider and reported empty.
    private func discoverUnannotatedSuites(
        in projectRoot: URL,
        filesystem: any FilesystemService
    ) async throws -> [SnapshotSuite] {
        var claimed = false

        for provider in providers {
            try Task.checkCancellation()
            guard await provider.canHandle(projectRoot: projectRoot, filesystem: filesystem) else {
                continue
            }
            claimed = true

            let suites = try await provider.discoverSuites(in: projectRoot, filesystem: filesystem)
            if !suites.isEmpty { return suites }
        }

        guard claimed else { throw GimDiffError.unrecognisedProjectLayout(projectRoot) }
        return []
    }

    /// Copies each file's Git status onto the item that points at it.
    ///
    /// ``SnapshotSuite/hasGitDiff`` reads through to its items, so a suite starts reporting a
    /// difference as soon as one of its snapshots does.
    /// Every snapshot is re-annotated, including against an empty `statuses`: a refresh run
    /// after a snapshot was reverted reports nothing about it, and that silence is the news.
    static func annotate(
        _ suites: [SnapshotSuite],
        with statuses: [URL: GitFileStatus]
    ) -> [SnapshotSuite] {
        let byPath = Dictionary(
            statuses.map { ($0.key.standardizedFileURL.path, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        return suites.map { suite in
            var annotated = suite
            annotated.snapshots = suite.snapshots.map { item in
                var updated = item
                updated.gitStatus = status(forFileAt: item.fileURL, in: byPath) ?? .unmodified
                return updated
            }
            return annotated
        }
    }

    /// The status Git reports for one file, directly or through a folder it collapsed.
    ///
    /// `git status -s` reports a brand-new directory as a single `?? Dir/` record rather
    /// than one per file, so a file with no record of its own inherits from the nearest
    /// ancestor that has one.
    static func status(forFileAt url: URL, in byPath: [String: GitFileStatus]) -> GitFileStatus? {
        let path = url.standardizedFileURL.path
        if let exact = byPath[path] { return exact }

        var current = (path as NSString).deletingLastPathComponent
        while current != "/", !current.isEmpty {
            if let inherited = byPath[current] { return inherited }
            current = (current as NSString).deletingLastPathComponent
        }

        return nil
    }
}
