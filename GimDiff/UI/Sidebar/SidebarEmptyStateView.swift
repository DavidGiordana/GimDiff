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
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button(actionTitle, action: action)
        }
        // Claims the rest of the column, which the `List` it stands in for does by itself.
        // Without it the sidebar's stack shrinks to fit and is centred vertically, taking
        // the search field with it — so emptying the tree with a filter appears to move the
        // search field into the middle of the sidebar.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SidebarEmptyStateView {
    /// A project is open, and the scan found no snapshot folders anywhere in it.
    static func noSnapshotsDiscovered(reload: @escaping () -> Void) -> SidebarEmptyStateView {
        SidebarEmptyStateView(
            systemImage: "photo.on.rectangle.angled",
            title: "No Snapshots Discovered",
            message: """
                No snapshot directories (Snapshots/ or __Snapshots__) were found in this project.
                """,
            actionTitle: "Reload",
            action: reload
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

#Preview("No matches") {
    SidebarEmptyStateView.noMatches {}
}
