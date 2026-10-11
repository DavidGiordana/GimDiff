//
//  EmptyStateView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The one look every empty column in the window shares: an icon, a title, a line of
/// explanation, and optionally the action that fills the column.
///
/// Hand-built rather than `ContentUnavailableView`, whose title and icon are sized for a
/// whole window. Beside the canvas that made the narrow sidebar's empty state the loudest
/// thing on screen, and one component for both columns is what keeps them the same size.
struct EmptyStateView: View {
    let systemImage: String
    /// Colour for the icon, when the state is news rather than an absence.
    var tint: Color?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "folder.badge.plus",
        title: "No Recent Projects",
        message: "Open a project folder or drag a folder here",
        actionTitle: "Open Project…",
        action: {}
    )
}
