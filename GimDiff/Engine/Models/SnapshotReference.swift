//
//  SnapshotReference.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A single snapshot image on disk.
struct SnapshotReference: Identifiable, Hashable, Sendable {
    /// Role a snapshot image plays within a comparison.
    enum Kind: String, Hashable, Sendable {
        /// The committed image a test asserts against.
        case reference
        /// The image produced by the most recent failing run.
        case failure
    }

    let id: URL
    let kind: Kind

    /// Location of the image on disk.
    var url: URL { id }

    /// File name without its extension, used as the display name in the sidebar.
    var name: String { id.deletingPathExtension().lastPathComponent }

    init(url: URL, kind: Kind) {
        self.id = url
        self.kind = kind
    }
}
