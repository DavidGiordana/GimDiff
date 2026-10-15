//
//  SidebarEmptyStateView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// What the sidebar shows in place of a tree with no rows in it.
///
/// A project with no snapshots and a filter that matches nothing look the same to a `List`
/// and mean opposite things to the person reading it, so each carries the action that
/// resolves it: rescan, or drop the filters.
struct SidebarEmptyStateView: View {
    let systemImage: String
    var tint: Color?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        // `EmptyStateView` claims the rest of the column, which the `List` it stands in for
        // does by itself. Without that the sidebar's stack shrinks to fit and is centred
        // vertically, taking the search field with it — so emptying the tree with a filter
        // appears to move the search field into the middle of the sidebar.
        EmptyStateView(
            systemImage: systemImage,
            tint: tint,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action
        )
    }
}

extension SidebarEmptyStateView {
    /// A project is open, and the scan found no snapshot folders anywhere in it.
    static func noSnapshotsDiscovered(reload: @escaping () -> Void) -> SidebarEmptyStateView {
        SidebarEmptyStateView(
            systemImage: "photo.on.rectangle.angled",
            title: "No Snapshots Discovered",
            message: """
                No snapshot directories (Snapshots/, __Snapshots__, or Paparazzi’s snapshots/images) were found in this project.
                """,
            actionTitle: "Reload",
            action: reload
        )
    }

    /// A pull request is under review, and none of the files it changes is a snapshot.
    ///
    /// Good news rather than an error, which is why it is drawn in green: the pull request
    /// cannot have broken a snapshot it does not touch.
    static func noSnapshotChanges(prNumber: Int, close: @escaping () -> Void) -> SidebarEmptyStateView {
        SidebarEmptyStateView(
            systemImage: "checkmark.circle.fill",
            tint: .green,
            title: "No Snapshot Changes",
            message: "PR #\(prNumber) contains no modified snapshot image files.",
            actionTitle: "Close Review",
            action: close
        )
    }

    /// The test run was read, and none of its failures is about a snapshot.
    ///
    /// Drawn in green for the same reason as ``noSnapshotChanges(prNumber:close:)``.
    static func noTestFailures(showProject: @escaping () -> Void) -> SidebarEmptyStateView {
        SidebarEmptyStateView(
            systemImage: "checkmark.circle.fill",
            tint: .green,
            title: "No Snapshot Failures",
            message: "This test run failed on no snapshot of this project.",
            actionTitle: "Show Project",
            action: showProject
        )
    }

    /// The test run could not be found or read.
    static func testRunUnavailable(message: String, showProject: @escaping () -> Void) -> SidebarEmptyStateView {
        SidebarEmptyStateView(
            systemImage: "xmark.octagon",
            title: "No Test Results",
            // Interpolated, so the reason is shown as written rather than looked up.
            message: "\(message)",
            actionTitle: "Show Project",
            action: showProject
        )
    }

    /// The project holds snapshots, but the search text or the filter chips hide all of them.
    static func noMatches(clearFilters: @escaping () -> Void) -> SidebarEmptyStateView {
        SidebarEmptyStateView(
            systemImage: "magnifyingglass",
            title: "No Matching Snapshots",
            message: "No snapshots match your query or filter chips.",
            actionTitle: "Clear Filters",
            action: clearFilters
        )
    }
}

#Preview("No snapshots") {
    SidebarEmptyStateView.noSnapshotsDiscovered {}
}

#Preview("No snapshot changes") {
    SidebarEmptyStateView.noSnapshotChanges(prNumber: 123) {}
}

#Preview("No matches") {
    SidebarEmptyStateView.noMatches {}
}
