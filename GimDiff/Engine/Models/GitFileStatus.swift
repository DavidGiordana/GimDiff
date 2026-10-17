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
    /// Staged at a path `HEAD` does not have: added, or the new name of a rename or copy.
    ///
    /// Kept apart from ``modified`` because there is nothing at `HEAD` to go back to.
    /// Restoring such a path from `HEAD` deletes it.
    case added
    /// Not tracked by the repository at all.
    case untracked
    /// Tracked, but removed from the working tree.
    case deleted
}
