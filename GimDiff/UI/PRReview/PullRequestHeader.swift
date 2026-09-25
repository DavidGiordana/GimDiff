//
//  PullRequestHeader.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Names the pull request under review in the sidebar, and offers the way out of it.
struct PullRequestHeader: View {
    let session: PRReviewSession
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label {
                    Text("PR #\(session.prNumber)")
                } icon: {
                    Image(systemName: "arrow.triangle.pull")
                        .fontWeight(.heavy)
                }
                .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
                    .foregroundStyle(.tint)
                    .help(session.reference.webURL.absoluteString)

                Text("\(session.reference.owner)/\(session.reference.repo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                // Always visible, like the project header's: it is the only way back to the
                // project the review replaced.
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close the review and delete its downloaded snapshots")
                .accessibilityLabel("Close Pull Request Review")
            }

            Text(session.title)
                .font(.headline)
                .lineLimit(2)
                .help(session.title)

            Text("@\(session.author)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(session.headRef)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                Text(session.baseRef)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(session.headRef) into \(session.baseRef)")
        }
    }
}
