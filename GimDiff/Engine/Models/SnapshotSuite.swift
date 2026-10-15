//
//  SnapshotSuite.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The snapshots recorded by a single test suite or test case.
struct SnapshotSuite: Identifiable, Sendable, Hashable {
    let id: String
    /// Test suite or test case name, as it appears in the source.
    var name: String
    /// The file declaring the suite, when the provider could locate it.
    var sourceCodeURL: URL?
    /// Folder holding this suite's recorded images.
    var snapshotsFolderURL: URL
    var snapshots: [SnapshotItem]
    /// Identifier of the ``SnapshotProviding`` implementation that produced this suite.
    var providerId: String
    /// Whether other suites keep their images in the same folder.
    ///
    /// Paparazzi records every test class of a module into one flat folder, so such a suite
    /// is its snapshots rather than its folder: deleting it must trash those files and
    /// leave the folder, which still holds every other class's images.
    var sharesFolder: Bool

    init(
        id: String? = nil,
        name: String,
        sourceCodeURL: URL? = nil,
        snapshotsFolderURL: URL,
        snapshots: [SnapshotItem] = [],
        providerId: String,
        sharesFolder: Bool = false
    ) {
        self.id = id ?? snapshotsFolderURL.path
        self.name = name
        self.sourceCodeURL = sourceCodeURL
        self.snapshotsFolderURL = snapshotsFolderURL
        self.snapshots = snapshots
        self.providerId = providerId
        self.sharesFolder = sharesFolder
    }

    /// Whether the provider could not locate the test source that records this suite.
    ///
    /// Surfaced as a warning in the sidebar: a suite with no source file is usually a
    /// folder of snapshots left behind by a test that has since been renamed or deleted.
    var isMissingSourceCode: Bool { sourceCodeURL == nil }

    /// Whether any snapshot in the suite differs from what the repository has committed.
    var hasGitDiff: Bool { snapshots.contains(where: \.hasGitDiff) }

    /// How many snapshots in the suite differ from what the repository has committed.
    var modifiedSnapshotsCount: Int { snapshots.filter(\.hasGitDiff).count }
}
