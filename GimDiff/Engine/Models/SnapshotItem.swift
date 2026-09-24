//
//  SnapshotItem.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One snapshot image belonging to a suite.
struct SnapshotItem: Identifiable, Sendable, Hashable {
    /// File path or URI, unique within a suite.
    let id: String
    /// Test method the snapshot was recorded for.
    var name: String
    /// Position among several snapshots recorded by the same test, or `nil` when the test
    /// records only one.
    var variantIndex: Int?
    var fileURL: URL
    /// Physical properties, absent until the file has been inspected.
    var metadata: SnapshotMetadata?
    var gitStatus: GitFileStatus

    init(
        id: String? = nil,
        name: String,
        variantIndex: Int? = nil,
        fileURL: URL,
        metadata: SnapshotMetadata? = nil,
        gitStatus: GitFileStatus = .unmodified
    ) {
        self.id = id ?? fileURL.path
        self.name = name
        self.variantIndex = variantIndex
        self.fileURL = fileURL
        self.metadata = metadata
        self.gitStatus = gitStatus
    }

    /// Whether this snapshot differs from what the repository has committed.
    var hasGitDiff: Bool { gitStatus == .modified || gitStatus == .untracked }

    /// Name shown in the sidebar, disambiguated when a test records several snapshots.
    var displayName: String {
        guard let variantIndex else { return name }
        return "\(name) (\(variantIndex))"
    }
}
