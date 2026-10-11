//
//  ChangeKindBadge.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Names what a pull request did to a snapshot: added, modified, deleted, or renamed.
///
/// Spelled out rather than abbreviated to a letter. The sidebar has room for the word, and
/// "D" beside a snapshot name reads as easily as "diff" as it does "deleted".
struct ChangeKindBadge: View {
    let kind: PRSnapshotChange.Kind

    var body: some View {
        Text(kind.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(0.4)))
            .fixedSize()
            .help(explanation)
            .accessibilityLabel(explanation)
    }

    private var tint: Color {
        switch kind {
        case .added: .green
        case .modified: .orange
        case .removed: .red
        case .renamed: .blue
        }
    }

    private var explanation: String {
        switch kind {
        case .added: String(localized: "Added by this pull request; the base branch has no version to compare with")
        case .modified: String(localized: "Modified by this pull request")
        case .removed: String(localized: "Deleted by this pull request; only the base branch's version exists")
        case .renamed: String(localized: "Renamed by this pull request")
        }
    }
}

#Preview {
    HStack {
        ChangeKindBadge(kind: .added)
        ChangeKindBadge(kind: .modified)
        ChangeKindBadge(kind: .removed)
        ChangeKindBadge(kind: .renamed)
    }
    .padding()
}
