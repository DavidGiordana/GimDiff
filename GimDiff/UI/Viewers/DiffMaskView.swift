//
//  DiffMaskView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The difference mask: every changed pixel painted neon magenta over a dimmed candidate.
///
/// The mask is a real image written by ``ImageDiffService``, not an effect layered over the
/// two panes, so it goes through the same viewer as any other snapshot and can be zoomed
/// into at 1:1 like one.
struct DiffMaskView: View {
    let report: ImageDiffReport?
    let isComputing: Bool
    /// Shown while the comparison runs, and when it finds no mask to draw.
    let candidateURL: URL
    let reloadToken: Int
    let matte: Color?

    var body: some View {
        SnapshotImageViewer(
            fileURL: report?.diffMaskURL ?? candidateURL,
            reloadToken: reloadToken,
            matte: matte
        ) {
            DiffReportPill(report: report, isComputing: isComputing)
        }
    }
}

/// What the pixel comparison found, as one line in the viewer's footer.
struct DiffReportPill: View {
    let report: ImageDiffReport?
    let isComputing: Bool

    var body: some View {
        if isComputing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Comparing…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let report {
            Text(Self.summary(of: report))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Self.tint(for: report))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Self.tint(for: report).opacity(0.15), in: .capsule)
                .accessibilityLabel(Self.summary(of: report))
        }
    }

    /// The headline number, or the reason there is not one.
    ///
    /// Differently sized images are called out rather than reported as 100% changed: the
    /// percentage would be true and useless, and the size is the thing to go and fix.
    static func summary(of report: ImageDiffReport) -> String {
        guard report.hasIdenticalDimensions else { return "⚠️ Size Mismatch" }
        guard !report.isIdentical else { return "100% Match" }

        let pixels = report.differentPixelCount
        return String(format: "%.2f%% Diff (%@ pixels)", report.diffPercentage, pixels.formatted())
    }

    static func tint(for report: ImageDiffReport) -> Color {
        guard report.hasIdenticalDimensions else { return .orange }
        return report.isIdentical ? .green : .pink
    }
}
