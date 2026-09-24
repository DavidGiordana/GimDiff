//
//  TreeRowItem.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One line of the sidebar tree, already flattened.
///
/// The sidebar is a plain `List` over an array of these rather than an `OutlineGroup`.
/// `OutlineGroup` owns the hierarchy itself, which costs two things GimDiff needs: the
/// arrow keys stop moving between levels once a row is a disclosure group, and deleting a
/// node rebuilds the group's identity so the selection is dropped instead of moving to the
/// neighbouring row. A flat array keeps selection, arrow keys, and deletion in one place —
/// ``AppState`` — where all three can agree.
enum TreeRowItem: Identifiable, Hashable {
    /// A suite, carrying the state the row draws: whether its children follow it in the
    /// array, and how many of them survived the filters.
    case suite(SnapshotSuite, isExpanded: Bool, childCount: Int)
    /// A snapshot, tagged with the suite it is shown under.
    case snapshot(SnapshotItem, parentSuiteID: String)

    /// Selection identity. Namespaced by kind, and by parent for a snapshot, so the same
    /// image discovered under two suites never collapses into one selectable row.
    var id: String {
        switch self {
        case let .suite(suite, _, _):
            Self.suiteRowID(suite.id)
        case let .snapshot(snapshot, parentSuiteID):
            Self.snapshotRowID(snapshot.id, parentSuiteID: parentSuiteID)
        }
    }

    static func suiteRowID(_ suiteID: String) -> String {
        "suite:\(suiteID)"
    }

    static func snapshotRowID(_ snapshotID: String, parentSuiteID: String) -> String {
        "snapshot:\(parentSuiteID):\(snapshotID)"
    }

    /// Identifier of the suite this row belongs to, whether it is the suite or a child.
    var suiteID: String {
        switch self {
        case let .suite(suite, _, _): suite.id
        case let .snapshot(_, parentSuiteID): parentSuiteID
        }
    }

    /// The snapshot on this row, absent on a suite row.
    var snapshot: SnapshotItem? {
        guard case let .snapshot(snapshot, _) = self else { return nil }
        return snapshot
    }

    /// Whether the row is indented under a suite.
    var isSnapshot: Bool { snapshot != nil }

    /// Text shown on the row, and what "copy name" puts on the pasteboard.
    var name: String {
        switch self {
        case let .suite(suite, _, _): suite.name
        case let .snapshot(snapshot, _): snapshot.displayName
        }
    }

    /// Whether the row differs from what the repository has committed.
    var hasGitDiff: Bool {
        switch self {
        case let .suite(suite, _, _): suite.hasGitDiff
        case let .snapshot(snapshot, _): snapshot.hasGitDiff
        }
    }
}
