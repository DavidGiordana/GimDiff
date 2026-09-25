//
//  SnapshotPreview.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Where the file behind one side of a comparison came from.
enum SnapshotOrigin: Equatable, Sendable {
    /// A file in the project, which GimDiff is free to overwrite.
    case workingTree
    /// A temporary copy of what a commit holds, written out by `git show`.
    ///
    /// Overwriting one of these would change nothing anybody could see afterwards, so the
    /// promotion actions refuse a pane that carries it.
    case committedVersion
}

/// One side of what the canvas is showing.
struct SnapshotPane: Identifiable, Equatable, Sendable {
    /// Which half of a comparison a pane is.
    enum Role: String, Sendable {
        /// The image the most recent run produced.
        case candidate
        /// The image the test asserts against.
        case baseline
    }

    let role: Role
    let fileURL: URL
    let origin: SnapshotOrigin

    /// Namespaced by role, because the same file can legitimately sit on both sides.
    var id: String { "\(role.rawValue):\(fileURL.path)" }

    var roleTitle: String {
        switch role {
        case .candidate: "Candidate"
        case .baseline: "Baseline"
        }
    }

    /// Where the pane's file lives, which is the only thing telling the two sides apart
    /// when both carry the same file name.
    var roleSubtitle: String {
        switch (role, origin) {
        case (.candidate, _): "Current"
        case (.baseline, .committedVersion): "Committed in Git"
        case (.baseline, .workingTree): "Recorded on Disk"
        }
    }

    /// Whether GimDiff may write over this pane's file.
    var isWritable: Bool { origin == .workingTree }
}

/// What the detail pane is showing, or `nil` when the pane is closed.
enum SnapshotPreview: Equatable, Sendable {
    /// One image on its own: an untracked snapshot, or a loose file that was dropped in.
    case single(SnapshotItem)
    /// Two images to compare — a snapshot against its committed version, or a pair handed
    /// to GimDiff by a drop, the clipboard, or a `gimdiff://compare` URL.
    ///
    /// `baselineOrigin` is what separates the two: a comparison against `HEAD` holds a
    /// baseline git wrote to a scratch file, and that file is not something a promotion may
    /// be pointed at.
    case comparison(
        SnapshotPair,
        snapshotID: String?,
        title: String,
        baselineOrigin: SnapshotOrigin
    )

    /// Identifier of the discovered snapshot this preview came from, when it came from one.
    ///
    /// Deleting that snapshot closes the pane, so the pane has to be able to say which
    /// snapshot it is standing on even when it is showing a pair of temporary files.
    var snapshotID: String? {
        switch self {
        case let .single(snapshot): snapshot.id
        case let .comparison(_, snapshotID, _, _): snapshotID
        }
    }

    /// Name shown as the window's title.
    var title: String {
        switch self {
        case let .single(snapshot): snapshot.displayName
        case let .comparison(_, _, title, _): title
        }
    }

    /// Whether two images are on screen, which is what the diff-mode picker acts on.
    var isComparison: Bool {
        guard case .comparison = self else { return false }
        return true
    }

    /// The panes to draw, left to right.
    ///
    /// The candidate leads: it is the image the user just produced and the one every action
    /// in the header is about, so it reads first and the baseline it is measured against
    /// sits beside it.
    var panes: [SnapshotPane] {
        switch self {
        case let .single(snapshot):
            [SnapshotPane(role: .candidate, fileURL: snapshot.fileURL, origin: .workingTree)]
        case let .comparison(pair, _, _, baselineOrigin):
            [
                SnapshotPane(role: .candidate, fileURL: pair.failure.url, origin: .workingTree),
                SnapshotPane(role: .baseline, fileURL: pair.reference.url, origin: baselineOrigin),
            ]
        }
    }

    var candidate: SnapshotPane? { panes.first { $0.role == .candidate } }
    var baseline: SnapshotPane? { panes.first { $0.role == .baseline } }
}
