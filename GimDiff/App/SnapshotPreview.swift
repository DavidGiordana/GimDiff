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
    /// A copy of one side of a GitHub pull request, downloaded for review.
    ///
    /// Both sides of such a comparison carry it: neither file is the one in the pull
    /// request, so neither is anything a promotion could meaningfully overwrite.
    case pullRequest
    /// An image a test attached when it last failed, exported from the run's result bundle.
    ///
    /// Only ever a candidate. It may be written *from* — that is what accepting it means —
    /// but nothing is reverted onto it: the copy is scratch, and the run is over.
    case testRun
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
        case (.candidate, .pullRequest): "Pull Request Head"
        case (.baseline, .pullRequest): "Base Branch"
        case (_, .testRun): "Test Run"
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
    /// The one side a pull request has of a snapshot it adds or deletes: the head of an
    /// added snapshot, or the base of a deleted one.
    ///
    /// Kept apart from ``single(_:)`` because that case is always the candidate on disk,
    /// and a deleted snapshot's only image is neither.
    case pullRequestSide(SnapshotItem, role: SnapshotPane.Role)
    /// A snapshot on disk against an image its test attached when it last failed.
    ///
    /// The pair reads the way every other one does: the reference is the recorded file,
    /// which is what accepting the candidate overwrites.
    case testRunFailure(SnapshotPair, snapshotID: String, title: String)
    /// An image a failed test attached that is about no snapshot the project holds.
    case testRunAttachment(SnapshotItem)

    /// Identifier of the discovered snapshot this preview came from, when it came from one.
    ///
    /// Deleting that snapshot closes the pane, so the pane has to be able to say which
    /// snapshot it is standing on even when it is showing a pair of temporary files.
    var snapshotID: String? {
        switch self {
        case let .single(snapshot): snapshot.id
        case let .comparison(_, snapshotID, _, _): snapshotID
        case let .pullRequestSide(snapshot, _): snapshot.id
        case let .testRunFailure(_, snapshotID, _): snapshotID
        case let .testRunAttachment(snapshot): snapshot.id
        }
    }

    /// Name shown as the window's title.
    var title: String {
        switch self {
        case let .single(snapshot): snapshot.displayName
        case let .comparison(_, _, title, _): title
        case let .pullRequestSide(snapshot, _): snapshot.displayName
        case let .testRunFailure(_, _, title): title
        case let .testRunAttachment(snapshot): snapshot.displayName
        }
    }

    /// Whether two images are on screen, which is what the diff-mode picker acts on.
    var isComparison: Bool {
        switch self {
        case .comparison, .testRunFailure: true
        case .single, .pullRequestSide, .testRunAttachment: false
        }
    }

    /// The panes to draw, left to right.
    ///
    /// The baseline leads and the candidate follows it, old to new, the way `git diff`,
    /// GitHub, and every other diff tool read. The order is fixed rather than configurable:
    /// the header actions and ⌘← / ⌘→ are arrows pointing at the pane they overwrite.
    var panes: [SnapshotPane] {
        switch self {
        case let .single(snapshot):
            [SnapshotPane(role: .candidate, fileURL: snapshot.fileURL, origin: .workingTree)]
        case let .pullRequestSide(snapshot, role):
            [SnapshotPane(role: role, fileURL: snapshot.fileURL, origin: .pullRequest)]
        case let .comparison(pair, _, _, baselineOrigin):
            [
                SnapshotPane(role: .baseline, fileURL: pair.reference.url, origin: baselineOrigin),
                SnapshotPane(
                    role: .candidate,
                    fileURL: pair.failure.url,
                    origin: baselineOrigin == .pullRequest ? .pullRequest : .workingTree
                ),
            ]
        case let .testRunFailure(pair, _, _):
            [
                SnapshotPane(role: .baseline, fileURL: pair.reference.url, origin: .workingTree),
                SnapshotPane(role: .candidate, fileURL: pair.failure.url, origin: .testRun),
            ]
        case let .testRunAttachment(snapshot):
            [SnapshotPane(role: .candidate, fileURL: snapshot.fileURL, origin: .testRun)]
        }
    }

    var candidate: SnapshotPane? { panes.first { $0.role == .candidate } }
    var baseline: SnapshotPane? { panes.first { $0.role == .baseline } }
}
