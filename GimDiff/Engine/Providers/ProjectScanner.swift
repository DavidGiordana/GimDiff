//
//  ProjectScanner.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Scans a project off the main actor and reports what it holds.
///
/// An actor rather than a plain type so a window can start a scan, drop it, and start
/// another without the two treading on each other. Cancellation is cooperative throughout:
/// the tree walk checks between directories, so abandoning a scan of a large repository
/// stops it rather than letting it run to completion unseen.
actor ProjectScanner {
    private let registry: ProviderRegistry
    private let filesystem: any FilesystemService
    private let gitService: any GitService

    init(
        registry: ProviderRegistry = ProviderRegistry(),
        filesystem: any FilesystemService,
        gitService: any GitService
    ) {
        self.registry = registry
        self.filesystem = filesystem
        self.gitService = gitService
    }

    /// Discovers every snapshot suite under `projectRoot`, annotated against its working tree.
    ///
    /// - Throws: `CancellationError` when the task is cancelled, or
    ///   ``GimDiffError/unrecognisedProjectLayout(_:)`` when no provider claims the folder.
    func scan(projectRoot: URL) async throws -> ProjectBundle {
        try Task.checkCancellation()

        // Resolved, not merely standardized: listing follows symlinks, so discovered files
        // carry resolved paths. A root left unresolved would disagree with them, and with
        // the paths git reports, leaving every snapshot unannotated.
        let root = projectRoot.resolvingSymlinksInPath()
        let gitRoot = await gitService.findRepositoryRoot(for: root)
        try Task.checkCancellation()

        let suites = try await registry.discoverSuites(
            in: root,
            filesystem: filesystem,
            gitService: gitService,
            repositoryRoot: gitRoot
        )
        try Task.checkCancellation()

        return ProjectBundle(rootURL: root, gitRootURL: gitRoot, suites: suites)
    }
}
