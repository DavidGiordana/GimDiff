//
//  OpenPRSheetView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Asks for a pull request, and shows the fetch until its snapshots are on disk.
///
/// The sheet stays up while the fetch runs rather than closing on submit: a pull request
/// with many snapshots takes a while to download, and a failure — `gh` not logged in, a
/// private repository the account cannot see — needs to be read beside the field that
/// caused it, not on a banner after the sheet has gone.
struct OpenPRSheetView: View {
    @Environment(AppState.self) private var state

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        @Bindable var review = state.pullRequestReview

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review GitHub Pull Request")
                        .font(.headline)
                    Text("Compare the snapshots a pull request changes, without checking it out.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "https://github.com/owner/repo/pull/123",
                    text: $review.input
                )
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .disabled(state.pullRequestReview.isFetching)
                .onSubmit(submit)
                .accessibilityIdentifier("PullRequestField")

                Text("A link, owner/repo#123, or a number from the open project's repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = state.pullRequestReview.error {
                Label {
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
            }

            HStack {
                if state.pullRequestReview.isFetching {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading snapshots…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    state.dismissPullRequestSheet()
                }
                .keyboardShortcut(.cancelAction)

                Button("Review Snapshots", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { isFieldFocused = true }
    }

    private var canSubmit: Bool {
        !state.pullRequestReview.isFetching
            && !state.pullRequestReview.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        state.openPullRequest(state.pullRequestReview.input)
    }
}

#Preview {
    OpenPRSheetView()
        .environment(AppState())
}
