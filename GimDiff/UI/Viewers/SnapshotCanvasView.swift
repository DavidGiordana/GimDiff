//
//  SnapshotCanvasView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Renders whatever the preview pane is holding, or an empty state when it is closed.
///
/// One pane for a lone snapshot, two for a comparison, and one combined surface for the
/// modes that draw both images in the same coordinates.
struct SnapshotCanvasView: View {
    @Environment(AppState.self) private var state

    let preview: SnapshotPreview?
    /// Colour behind the panes, chosen in the toolbar.
    let panelBackground: Color?
    /// Colour painted behind the images themselves, for reading transparent snapshots.
    let imageMatte: Color?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backdrop)
            .navigationTitle(preview?.title ?? "GimDiff")
            .navigationSubtitle(subtitle)
    }

    /// The chosen panel colour, but only while there is a panel to put it behind.
    ///
    /// The empty state keeps the window's own colour whatever the well is set to. The
    /// setting describes the backdrop a snapshot is being read against, and a saturated
    /// colour flooding a window with nothing in it reads as a fault rather than a choice.
    private var panelTint: Color? {
        preview == nil ? nil : panelBackground
    }

    /// The tint, or the colour the window would have had without one.
    ///
    /// Drawn behind the panes rather than only at the edges: each pane paints this same
    /// backdrop, so the colour is what a transparent snapshot is actually read against.
    @ViewBuilder
    private var backdrop: some View {
        if let panelTint {
            panelTint
        } else {
            Color(nsColor: .underPageBackgroundColor)
        }
    }

    /// The backdrop inside one pane, under the image and its footer.
    @ViewBuilder
    private var paneBackdrop: some View {
        if let panelTint {
            panelTint
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch preview {
        case nil:
            CanvasEmptyStateView()

        case .single, .pullRequestSide:
            if let only = preview?.panes.first {
                pane(only)
            }

        case .comparison:
            comparison
        }
    }

    @ViewBuilder
    private var comparison: some View {
        if let candidate = preview?.candidate, let baseline = preview?.baseline {
            switch state.diffMode {
            case .sideBySide:
                HStack(spacing: 1) {
                    pane(candidate)
                    pane(baseline)
                }
                .background(.quaternary)

            case .curtain:
                combined(candidate: candidate, baseline: baseline) {
                    SnapshotSplitSliderView(
                        leading: candidate,
                        trailing: baseline,
                        reloadToken: state.imageReloadToken,
                        matte: imageMatte
                    )
                }

            case .difference:
                combined(candidate: candidate, baseline: baseline) {
                    DiffMaskView(
                        report: state.diffReport,
                        isComputing: state.isComputingDiff,
                        candidateURL: candidate.fileURL,
                        reloadToken: state.imageReloadToken,
                        matte: imageMatte
                    )
                }

            case .onionSkin:
                combined(candidate: candidate, baseline: baseline) {
                    ZStack {
                        SnapshotImageViewer(
                            fileURL: baseline.fileURL,
                            reloadToken: state.imageReloadToken,
                            matte: imageMatte
                        )
                        SnapshotImageViewer(
                            fileURL: candidate.fileURL,
                            reloadToken: state.imageReloadToken,
                            matte: nil
                        )
                        .opacity(0.5)
                    }
                }
            }
        }
    }

    /// One image under its own header.
    private func pane(_ pane: SnapshotPane) -> some View {
        VStack(spacing: 0) {
            SnapshotPaneHeader(pane: pane)
            Divider()
            SnapshotImageViewer(
                fileURL: pane.fileURL,
                reloadToken: state.imageReloadToken,
                matte: imageMatte
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paneBackdrop)
    }

    /// One surface showing both images, with both headers stacked above it.
    ///
    /// The headers stay side by side even though the images no longer are: the actions in
    /// them are still about one file each, and moving them around as the mode changes would
    /// leave the user hunting for the button that promotes a candidate.
    private func combined(
        candidate: SnapshotPane,
        baseline: SnapshotPane,
        @ViewBuilder body: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                SnapshotPaneHeader(pane: candidate)
                SnapshotPaneHeader(pane: baseline)
            }
            .background(.quaternary)

            Divider()

            body()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(paneBackdrop)
    }

    /// Names the mode in the window's subtitle, so a screenshot says what it is showing.
    private var subtitle: String {
        guard preview?.isComparison == true else { return "" }
        return state.diffMode.title
    }
}

/// The header strip above one image: what it is, where it is, and what can be done to it.
struct SnapshotPaneHeader: View {
    @Environment(AppState.self) private var state

    let pane: SnapshotPane

    var body: some View {
        HStack(spacing: 8) {
            Button {
                state.closePane(pane.role)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Close this pane")
            .accessibilityLabel("Close \(pane.roleTitle)")

            RoleBadge(pane: pane)

            // Once per preview rather than once per pane: both panes are the same change.
            if let change = state.pullRequestChange(forSnapshotID: state.preview?.snapshotID),
               pane.id == state.preview?.panes.first?.id {
                ChangeKindBadge(kind: change.kind)
            }

            Text(pane.fileURL.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(pane.fileURL.path)

            Spacer(minLength: 8)

            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var actions: some View {
        // The promotion lives on the candidate and the revert on the baseline, because each
        // one reads as an arrow pointing at the file it overwrites. Under pull request review
        // neither arrow has a file to point at, so both are gone rather than disabled.
        switch pane.role {
        case _ where state.isReviewingPullRequest:
            EmptyView()

        case .candidate:
            Button {
                state.promoteCandidateToBaseline()
            } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canPromoteCandidate)
            .help(state.candidatePromotionObstacle ?? "Accept Candidate / Overwrite Baseline (⌘→)")
            .accessibilityLabel("Accept Candidate")

        case .baseline:
            Button {
                state.revertCandidateToBaseline()
            } label: {
                Image(systemName: "arrow.left")
            }
            .buttonStyle(.borderless)
            .disabled(!state.canRevertToBaseline)
            .help("Revert to Baseline — overwrite the candidate on disk (⌘←)")
            .accessibilityLabel("Revert to Baseline")
        }

        // Every action below opens a file on disk somewhere else. Under pull request review
        // the files are scratch copies deleted when the review ends, and there is no test
        // source to open, so the header offers none of them.
        if !state.isReviewingPullRequest {
            Button {
                state.openInPreviewApp(pane.fileURL)
            } label: {
                Image(systemName: "doc")
            }
            .buttonStyle(.borderless)
            .help("Open Image in Preview")

            Button {
                state.revealInFinder(pane.fileURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button {
                state.openTestSourceForPreview()
            } label: {
                Image(systemName: "ellipsis.curlybraces")
            }
            .buttonStyle(.borderless)
            .disabled(state.previewSuite == nil)
            .help("Open Test Source in Xcode")
        }
    }
}

/// The pill naming one side of the comparison and where its file came from.
private struct RoleBadge: View {
    let pane: SnapshotPane

    var body: some View {
        HStack(spacing: 5) {
            Text(pane.roleTitle)
                .font(.caption.weight(.semibold))
            Text(pane.roleSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(tint.opacity(0.15), in: .capsule)
        .overlay(Capsule().strokeBorder(tint.opacity(0.45)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch pane.role {
        case .candidate: .orange
        case .baseline: .blue
        }
    }
}

/// Shown when the canvas has nothing to draw.
struct CanvasEmptyStateView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "photo.stack",
            title: "No Snapshot Selected",
            message: "Select a snapshot test from the sidebar or paste snapshot paths with ⌘V."
        )
    }
}

/// Shown in place of an image that is not there, is empty, or will not decode.
struct MissingImageView: View {
    @Environment(AppState.self) private var state

    let fileURL: URL

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)

            Text("Image Not Found")
                .font(.headline)

            Text("The file does not exist at this path or could not be decoded.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(fileURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(fileURL.path)

            Button("Reveal in Finder") {
                state.revealInFinder(fileURL)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#Preview {
    SnapshotCanvasView(preview: nil, panelBackground: nil, imageMatte: nil)
        .environment(AppState())
}
