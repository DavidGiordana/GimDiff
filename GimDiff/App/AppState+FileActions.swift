//
//  AppState+FileActions.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The actions the canvas performs on the two files it is showing.
///
/// Kept apart from ``AppState`` itself because these are the only places GimDiff writes a
/// snapshot rather than reading one, and both of them overwrite a file the user has not been
/// asked about. Everything here goes through ``FilesystemService``, so the whole surface is
/// testable against the in-memory double.
extension AppState {
    // MARK: - Refreshing

    /// Reads the images on screen off disk again, without rescanning the project.
    ///
    /// The file names have not changed, so nothing about the preview tells a view that a
    /// test run rewrote the bytes behind them. This is what says so.
    func refreshPreviewImages() {
        invalidateLoadedImages()
        refreshGitStatus()
        updateDiffReport()
    }

    // MARK: - Panes

    /// Drops one side of a comparison, leaving the other on screen on its own.
    func closePane(_ role: SnapshotPane.Role) {
        guard let survivor = preview?.panes.first(where: { $0.role != role }),
              preview?.isComparison == true
        else {
            closePreview()
            return
        }

        let name = survivor.fileURL.deletingPathExtension().lastPathComponent

        // An image out of the test run stays one on its own: nothing it is left beside
        // makes it a file of the project.
        guard survivor.origin != .testRun else {
            let item = SnapshotItem(
                id: preview?.snapshotID,
                name: testRunImageName(at: survivor.fileURL) ?? name,
                fileURL: survivor.fileURL
            )
            setPreview(.testRunAttachment(item))
            return
        }

        // A downloaded side stays a downloaded side: dropping its partner does not make it a
        // file on disk the user may act on. It keeps the snapshot's identifier too, so the
        // canvas can still say what the pull request did to it.
        guard survivor.origin != .pullRequest else {
            let item = SnapshotItem(id: preview?.snapshotID, name: name, fileURL: survivor.fileURL)
            setPreview(.pullRequestSide(item, role: survivor.role))
            return
        }

        setPreview(.single(SnapshotItem(name: name, fileURL: survivor.fileURL)))
    }

    // MARK: - Promotion

    /// Why the candidate cannot be written over the baseline, or `nil` when it can.
    ///
    /// A comparison against a commit holds a baseline `git show` wrote to a scratch file.
    /// Overwriting that would succeed and change nothing anybody could see, which is worse
    /// than refusing, so the reason is spelled out instead.
    var candidatePromotionObstacle: String? {
        guard let baseline = preview?.baseline else {
            return "There is no baseline on screen to overwrite."
        }
        guard baseline.origin != .pullRequest else {
            return Self.pullRequestPromotionObstacle
        }
        guard baseline.isWritable else {
            return """
            The baseline on screen was read out of \(Self.comparisonGitRef) and exists only \
            for this comparison. The candidate is already the file on disk — commit it to \
            make it the recorded baseline.
            """
        }
        return nil
    }

    var canPromoteCandidate: Bool { candidatePromotionObstacle == nil }

    /// Why the candidate out of a test run cannot be written to.
    static let testRunRevertObstacle = """
        The candidate is a copy of what the last test run rendered, not a file in the \
        project. Run the test again to replace it.
        """

    /// Why neither side of a pull request comparison can be written to.
    static let pullRequestPromotionObstacle = """
        Both images were downloaded from a GitHub pull request for review. Accept or revert \
        the change on its branch; there is no file on disk here to overwrite.
        """

    /// Whether the candidate on disk can be put back to what the baseline holds.
    ///
    /// True for a committed baseline as well as a recorded one: the candidate is always the
    /// working file, and that is the side this writes to — except under pull request
    /// review, where the candidate is a downloaded copy as well.
    var canRevertToBaseline: Bool {
        guard let candidate = preview?.candidate, preview?.baseline != nil else { return false }
        return candidate.isWritable
    }

    /// Accepts the candidate: copies it over the baseline on disk.
    func promoteCandidateToBaseline() {
        guard let candidate = preview?.candidate, let baseline = preview?.baseline else { return }

        if let obstacle = candidatePromotionObstacle {
            report(obstacle)
            return
        }

        guard copy(contentsOf: candidate.fileURL, over: baseline.fileURL) else { return }
        finishFileAction()

        // The snapshot now holds what the run rendered, so the failure is settled.
        if case let .testRunFailure(_, snapshotID, _) = preview {
            resolveTestRunFailure(snapshotID: snapshotID)
        }
    }

    /// Discards the candidate: copies the baseline back over it on disk.
    func revertCandidateToBaseline() {
        guard let candidate = preview?.candidate, let baseline = preview?.baseline else { return }
        guard candidate.isWritable else {
            report(candidate.origin == .testRun ? Self.testRunRevertObstacle : Self.pullRequestPromotionObstacle)
            return
        }
        guard copy(contentsOf: baseline.fileURL, over: candidate.fileURL) else { return }
        finishFileAction()
    }

    /// Replaces `destination` with the bytes of `source`, leaving `source` where it is.
    ///
    /// Staged through a scratch file rather than copied straight over, because
    /// ``FilesystemService/replaceFile(at:with:)`` consumes what it is handed: promoting a
    /// candidate must not delete the image the canvas is still pointing at. The exchange is
    /// what makes the write atomic, and a snapshot half overwritten is worse than either
    /// version of it.
    ///
    /// - Returns: Whether the write went through; a failure is already on the error banner.
    private func copy(contentsOf source: URL, over destination: URL) -> Bool {
        do {
            let staged = filesystem.createTemporaryFile(
                prefix: destination.deletingPathExtension().lastPathComponent,
                extension: destination.pathExtension.isEmpty ? "tmp" : destination.pathExtension
            )
            try filesystem.copyFile(from: source, to: staged)
            try filesystem.replaceFile(at: destination, with: staged)
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func finishFileAction() {
        refreshPreviewImages()
    }

    // MARK: - Test source

    /// The suite that recorded the image on screen, when the preview came from a scan.
    var previewSuite: SnapshotSuite? {
        guard let snapshotID = preview?.snapshotID else { return nil }
        return currentProject?.suites.first { suite in
            suite.snapshots.contains { $0.id == snapshotID }
        }
    }

    func openTestSourceForPreview() {
        guard let suite = previewSuite else {
            report("GimDiff does not know which test recorded this image.")
            return
        }
        openTestSource(for: suite)
    }

    // MARK: - Diff mask

    /// Measures the two panes against each other, or clears the measurement.
    ///
    /// Driven by the canvas rather than by every mutation that could invalidate it: the
    /// comparison decodes both images, so it runs when the mask is actually on screen and
    /// not on the chance that it might be.
    func updateDiffReport() {
        diffTask?.cancel()

        guard diffMode == .difference,
              let candidate = preview?.candidate,
              let baseline = preview?.baseline
        else {
            setDiffReport(nil)
            return
        }

        setDiffReport(nil, isComputing: true)
        diffTask = Task { [imageDiff] in
            do {
                let measured = try await imageDiff.compare(
                    candidateURL: candidate.fileURL,
                    baselineURL: baseline.fileURL
                )
                guard !Task.isCancelled else { return }
                setDiffReport(measured)
            } catch {
                guard !Task.isCancelled else { return }
                setDiffReport(nil)
                report(error)
            }
        }
    }

    /// The pixel comparison in flight, if any, so a caller can wait for it.
    var currentDiffComparison: Task<Void, Never>? { diffTask }
}
