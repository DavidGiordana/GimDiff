//
//  GitFileStatus.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// How Git sees a snapshot file relative to the last commit.
enum GitFileStatus: Sendable, Hashable {
    /// Identical to the committed version.
    case unmodified
    /// Tracked, with local edits.
    case modified
    /// Not tracked by the repository at all.
    case untracked
    /// Tracked, but removed from the working tree.
    case deleted
}
