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

    /// The view both side-by-side panes follow while Link Panes is on. Dropped whenever the
    /// link is broken or the pair changes, so the next link starts from the baseline pane.
    @State private var linkedTransform: LinkedPaneTransform?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backdrop)
            .navigationTitle(preview?.title ?? "GimDiff")
            .navigationSubtitle(subtitle)
            .onChange(of: panesAreLinked) { linkedTransform = nil }
            .onChange(of: preview) { linkedTransform = nil }
    }

    /// Whether the two panes on screen move together: only side by side, the one mode that
    /// draws them in two viewers.
    private var panesAreLinked: Bool {
        state.canvas.linksPanes && preview?.isComparison == true && state.canvas.diffMode == .sideBySide
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
            if let loadingURL = state.loadingProjectURL {
                CanvasLoadingStateView(projectURL: loadingURL, cancel: state.cancelProjectLoading)
            } else {
                CanvasEmptyStateView()
            }

        case .single, .pullRequestSide, .testRunAttachment:
            if let only = preview?.panes.first {
                pane(only)
            }

        case .comparison, .testRunFailure:
            comparison
        }
    }

    /// The comparison, with the decision about it underneath.
    ///
    /// Under pull request review there is no file to write, so the bar is gone rather than
    /// showing two disabled buttons.
    private var comparison: some View {
        VStack(spacing: 0) {
            comparisonSurface
            if !state.isReviewingPullRequest {
                SnapshotDecisionBar()
            }
        }
    }

    @ViewBuilder
    private var comparisonSurface: some View {
        if let candidate = preview?.candidate, let baseline = preview?.baseline {
            switch state.canvas.diffMode {
            case .sideBySide:
                // A gap rather than a hairline: a thin full-height seam between two panes is
                // how macOS draws a split view's divider, and it was read as one to drag.
                HStack(spacing: 8) {
                    pane(baseline)
                    pane(candidate)
                }

            case .curtain:
                combined(candidate: candidate, baseline: baseline) {
                    SnapshotSplitSliderView(
                        leading: baseline,
                        trailing: candidate,
                        reloadToken: state.canvas.imageReloadToken,
                        matte: imageMatte
                    )
                }

            case .difference:
                combined(candidate: candidate, baseline: baseline) {
                    DiffMaskView(
                        report: state.canvas.diffReport,
                        isComputing: state.canvas.isComputingDiff,
                        candidateURL: candidate.fileURL,
                        reloadToken: state.canvas.imageReloadToken,
                        matte: imageMatte
                    )
                }

            case .onionSkin:
                combined(candidate: candidate, baseline: baseline) {
                    OnionSkinView(
                        baseline: baseline,
                        candidate: candidate,
                        reloadToken: state.canvas.imageReloadToken,
                        matte: imageMatte
                    )
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
                reloadToken: state.canvas.imageReloadToken,
                matte: imageMatte,
                link: panesAreLinked ? $linkedTransform : nil,
                seedsLink: pane.role == .baseline
            ) {
                if preview?.isComparison == true, state.canvas.diffMode == .sideBySide {
                    LinkPanesButton()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paneBackdrop)
    }

    /// One surface showing both images, with both headers stacked above it.
    ///
    /// The headers stay side by side even though the images no longer are, so each side's
    /// name and origin read in the same place whatever the mode.
    private func combined(
        candidate: SnapshotPane,
        baseline: SnapshotPane,
        @ViewBuilder body: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                SnapshotPaneHeader(pane: baseline)
                SnapshotPaneHeader(pane: candidate)
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
        return state.canvas.diffMode.title
    }
}

/// Links or unlinks the zoom of the two side-by-side panes, from either pane's footer.
struct LinkPanesButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var canvas = state.canvas
        Toggle(isOn: $canvas.linksPanes) {
            Image(systemName: "link")
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .help(state.canvas.linksPanes
            ? "Zoom and move each pane on its own"
            : "Zoom and move both panes together")
        .accessibilityLabel("Link Panes")
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
            .accessibilityLabel("Close \(state.canvas.sideTitle(for: pane))")

            // A pair whose sides nobody could tell apart is named by position only:
            // calling either image the baseline would be a guess dressed as a fact.
            if state.canvas.looseRolesAreUnknown {
                PositionBadge(isLeft: pane.role == .baseline)
            } else {
                RoleBadge(pane: pane)
            }

            // Once per preview rather than once per pane: both panes are the same change.
            if let change = state.pullRequestReview.change(forSnapshotID: state.canvas.preview?.snapshotID),
               pane.id == state.canvas.preview?.panes.first?.id {
                ChangeKindBadge(kind: change.kind)
            }

            fileName

            Spacer(minLength: 8)

            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// The file the pane shows, or the attachment it was copied from.
    ///
    /// An image out of a test run is exported under an identifier, which says nothing; the
    /// name it was attached under does. When a test asserted the same snapshot more than
    /// once, this is where the candidate is chosen among the renderings.
    @ViewBuilder
    private var fileName: some View {
        let candidates = pane.role == .candidate ? state.testRunCandidatesOnScreen : []

        if candidates.count > 1 {
            Menu {
                ForEach(candidates) { candidate in
                    Button(candidate.name) {
                        state.selectTestRunCandidate(candidate)
                    }
                }
            } label: {
                Text(displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .font(.caption)
            // Truncated rather than sized to fit: a header wider than its pane pushes the
            // two panes off an even split.
            .help("Choose which image the test attached to compare with the baseline")
        } else {
            Text(displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(pane.fileURL.path)
        }
    }

    private var displayName: String {
        guard pane.origin == .testRun else { return pane.fileURL.lastPathComponent }
        return state.testRuns.imageName(at: pane.fileURL) ?? pane.fileURL.lastPathComponent
    }

    /// Accepting and rejecting are not here: they decide between both panes, so they live
    /// once in ``SnapshotDecisionBar`` rather than split across the two headers.
    @ViewBuilder
    private var actions: some View {
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

/// The strip under a comparison that decides it: keep the candidate, or put the baseline back.
///
/// One place for both actions, whatever the diff mode, with the reason an action is
/// unavailable written out beside it rather than left to a tooltip. A pasted pair is
/// offered as a choice of which side to keep instead, since rejecting it has nothing worth
/// writing to; see ``SnapshotPreview/isLoosePair``. When nothing could say which of the
/// two is the baseline, the choice is offered by position, with no side named as either.
struct SnapshotDecisionBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if state.canvas.looseRolesAreUnknown {
                    note(Self.undecidedNote)
                    Spacer(minLength: 8)
                    positionButtons
                } else if state.canvas.preview?.isLoosePair == true {
                    if let reason = Self.reason(for: state.canvas.looseRoleCertainty) {
                        note(reason)
                    }
                    Spacer(minLength: 8)
                    keepButtons
                } else {
                    obstacle
                    Spacer(minLength: 8)
                    decisionButtons
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    /// Neither one prominent: with the sides unknown there is no answer to suggest.
    @ViewBuilder
    private var positionButtons: some View {
        Button {
            state.keepLeft()
        } label: {
            Label("Keep Left", systemImage: "checkmark")
        }
        .controlSize(.large)
        .help("Overwrite the right image with the left one")

        Button {
            state.keepRight()
        } label: {
            Label("Keep Right", systemImage: "checkmark")
        }
        .controlSize(.large)
        .help("Overwrite the left image with the right one")
    }

    static let undecidedNote = """
        GimDiff can’t tell which image is the recorded snapshot. Keep the one that’s \
        right; the other is overwritten with it.
        """

    /// What decided the sides, when it was the files rather than the source's own labels.
    static func reason(for certainty: LooseRoleCertainty?) -> String? {
        guard case let .inferred(evidence, swapped) = certainty else { return nil }
        let because = switch evidence {
        case .trackedByGit: "Git tracks the baseline and not the candidate"
        case .insideProject: "the baseline is in the open project and the candidate is not"
        }
        return swapped
            ? "Sides swapped from the order given: \(because)."
            : "Sides chosen because \(because)."
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
            .help(text)
    }

    /// Baseline first, like the panes above them.
    @ViewBuilder
    private var keepButtons: some View {
        Button {
            state.keepBaseline()
        } label: {
            Label("Keep Baseline", systemImage: "checkmark")
        }
        .controlSize(.large)
        .help("Leave the baseline as it is and set the candidate aside")

        Button {
            state.keepCandidate()
        } label: {
            Label("Keep Candidate", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!state.canPromoteCandidate)
        .help(state.candidatePromotionObstacle ?? "Overwrite the baseline with the candidate")
    }

    @ViewBuilder
    private var decisionButtons: some View {
        Button {
            state.revertCandidateToBaseline()
        } label: {
            Label("Reject", systemImage: "xmark")
        }
        .controlSize(.large)
        .disabled(!state.canRevertToBaseline)
        .help(state.candidateRevertObstacle ?? "Overwrite the candidate with the baseline")
        .accessibilityLabel("Reject Candidate")

        Button {
            state.promoteCandidateToBaseline()
        } label: {
            Label("Accept", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!state.canPromoteCandidate)
        .help(state.candidatePromotionObstacle ?? "Overwrite the baseline with the candidate")
        .accessibilityLabel("Accept Candidate")
    }

    /// Why one of the two buttons is disabled, when one is.
    ///
    /// Accept's reason first: a comparison against `HEAD` is the common case, and the
    /// disabled Accept is the one that needs explaining.
    @ViewBuilder
    private var obstacle: some View {
        if let reason = state.candidatePromotionObstacle ?? state.candidateRevertObstacle {
            Label(reason, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(reason)
        }
    }
}

/// The pill naming a side by where it sits, for a pair whose roles are unknown.
private struct PositionBadge: View {
    let isLeft: Bool

    var body: some View {
        Text(isLeft ? "Left" : "Right")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.gray.opacity(0.15), in: .capsule)
            .overlay(Capsule().strokeBorder(.gray.opacity(0.45)))
            .fixedSize()
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
    @Environment(AppState.self) private var state

    var body: some View {
        EmptyStateView(
            systemImage: "photo.stack",
            title: "No Snapshot Selected",
            message: "Select a snapshot test from the sidebar, or copy a failure log and paste it here (⌘V).",
            actionTitle: "Paste from Clipboard",
            action: state.pasteFromClipboard
        )
    }
}

/// Shown on an empty canvas while a project is being scanned.
///
/// Laid out like ``EmptyStateView``, with a spinner where the icon would be, so the canvas
/// does not jump when the scan lands and the empty state takes its place.
struct CanvasLoadingStateView: View {
    let projectURL: URL
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .frame(height: 48)

            Text("Opening “\(projectURL.lastPathComponent)”")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(projectURL.path)

            Text("Looking for snapshot tests…")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Cancel", action: cancel)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ProjectLoadingState")
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
