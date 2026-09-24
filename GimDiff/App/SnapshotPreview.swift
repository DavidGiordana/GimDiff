//
//  SnapshotPreview.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What the detail pane is showing, or `nil` when the pane is closed.
enum SnapshotPreview: Equatable, Sendable {
    /// One image on its own: an untracked snapshot, or a loose file that was dropped in.
    case single(SnapshotItem)
    /// Two images to compare — a snapshot against its committed version, or a pair handed
    /// to GimDiff by a drop, the clipboard, or a `gimdiff://compare` URL.
    case comparison(SnapshotPair, snapshotID: String?, title: String)

    /// Identifier of the discovered snapshot this preview came from, when it came from one.
    ///
    /// Deleting that snapshot closes the pane, so the pane has to be able to say which
    /// snapshot it is standing on even when it is showing a pair of temporary files.
    var snapshotID: String? {
        switch self {
        case let .single(snapshot): snapshot.id
        case let .comparison(_, snapshotID, _): snapshotID
        }
    }

    /// Name shown as the window's title.
    var title: String {
        switch self {
        case let .single(snapshot): snapshot.displayName
        case let .comparison(_, _, title): title
        }
    }

    /// Whether two images are on screen, which is what the diff-mode picker acts on.
    var isComparison: Bool {
        guard case .comparison = self else { return false }
        return true
    }
}
