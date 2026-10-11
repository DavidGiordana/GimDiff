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
    @Environment(AppState.self) private var state

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
            HStack(spacing: 8) {
                DiffTolerancePicker(tolerance: tolerance)
                DiffReportPill(report: report, isComputing: isComputing)
            }
        }
    }

    private var tolerance: Binding<DiffTolerance> {
        Binding(
            get: { state.canvas.diffTolerance },
            set: { state.canvas.diffTolerance = $0 }
        )
    }
}

/// How loose the mask is, beside what it found.
struct DiffTolerancePicker: View {
    @Binding var tolerance: DiffTolerance

    var body: some View {
        Picker("Tolerance", selection: $tolerance) {
            ForEach(DiffTolerance.presets, id: \.self) { preset in
                Text(preset.title).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("How different two pixels may look and still count as the same, as a perceptual distance (ΔE). ΔE 2.3 is about the smallest change anybody can see.")
        .accessibilityLabel("Tolerance")
    }
}

extension DiffTolerance {
    /// What the canvas and the View menu call this tolerance.
    var title: String {
        guard !isExact else { return "Exact" }
        let value = maximumDeltaE.formatted(.number.precision(.fractionLength(0...1)))
        return maximumDeltaE == 2.3 ? "ΔE \(value) (Just Noticeable)" : "ΔE \(value)"
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
                .help(Self.detail(of: report))
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
        guard !report.isIdentical else {
            return report.toleratedPixelCount == 0 ? "100% Match" : "Match within Tolerance"
        }

        let pixels = report.differentPixelCount
        let summary = String(format: "%.2f%% Diff (%@ pixels)", report.diffPercentage, pixels.formatted())
        guard report.toleratedPixelCount > 0 else { return summary }
        return "\(summary) · \(report.toleratedPixelCount.formatted()) tolerated"
    }

    /// How loose the comparison would have to be for the two images to match.
    static func detail(of report: ImageDiffReport) -> String {
        guard report.hasIdenticalDimensions else {
            return "The images are different sizes, so no pixel lines up with another."
        }
        guard report.maximumDeltaE > 0 else { return "Every pixel is byte for byte the same." }
        let largest = report.maximumDeltaE.formatted(.number.precision(.fractionLength(1)))
        return "The largest difference is ΔE \(largest). A tolerance at least that loose would call these images a match."
    }

    static func tint(for report: ImageDiffReport) -> Color {
        guard report.hasIdenticalDimensions else { return .orange }
        return report.isIdentical ? .green : .pink
    }
}
