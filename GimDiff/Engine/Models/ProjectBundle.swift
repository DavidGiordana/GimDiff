//
//  ProjectBundle.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The result of one scan: a project folder and everything GimDiff found inside it.
struct ProjectBundle: Sendable, Equatable {
    /// Folder the scan was asked to look at.
    let rootURL: URL
    /// Root of the working tree containing it, absent when it is not in one.
    let gitRootURL: URL?
    /// Mutable so a deletion can prune one subtree in place. Dropping a snapshot must not
    /// cost a second walk of the project just to learn what the caller already knows.
    var suites: [SnapshotSuite]

    init(rootURL: URL, gitRootURL: URL? = nil, suites: [SnapshotSuite] = []) {
        self.rootURL = rootURL
        self.gitRootURL = gitRootURL
        self.suites = suites
    }

    /// Whether any suite in the project differs from what the repository has committed.
    var hasGitDiff: Bool { suites.contains(where: \.hasGitDiff) }

    /// How many snapshots across every suite differ from the committed versions.
    var modifiedSnapshotsCount: Int {
        suites.reduce(0) { $0 + $1.modifiedSnapshotsCount }
    }
}
