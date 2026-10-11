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
        canvas.invalidateLoadedImages()
        refreshGitStatus()
        canvas.updateDiffReport()
    }

    // MARK: - Panes

    /// Drops one side of a comparison, leaving the other on screen on its own.
    func closePane(_ role: SnapshotPane.Role) {
        guard let survivor = canvas.preview?.panes.first(where: { $0.role != role }),
              canvas.preview?.isComparison == true
        else {
            canvas.close()
            return
        }

        let name = survivor.fileURL.deletingPathExtension().lastPathComponent

        // An image out of the test run stays one on its own: nothing it is left beside
        // makes it a file of the project.
        guard survivor.origin != .testRun else {
            let item = SnapshotItem(
                id: canvas.preview?.snapshotID,
                name: testRuns.imageName(at: survivor.fileURL) ?? name,
                fileURL: survivor.fileURL
            )
            canvas.show(.testRunAttachment(item))
            return
        }

        // A downloaded side stays a downloaded side: dropping its partner does not make it a
        // file on disk the user may act on. It keeps the snapshot's identifier too, so the
        // canvas can still say what the pull request did to it.
        guard survivor.origin != .pullRequest else {
            let item = SnapshotItem(id: canvas.preview?.snapshotID, name: name, fileURL: survivor.fileURL)
            canvas.show(.pullRequestSide(item, role: survivor.role))
            return
        }

        canvas.show(.single(SnapshotItem(name: name, fileURL: survivor.fileURL)))
    }

    // MARK: - Promotion

    /// Why the candidate cannot be written over the baseline, or `nil` when it can.
    ///
    /// A comparison against a commit holds a baseline `git show` wrote to a scratch file.
    /// Overwriting that would succeed and change nothing anybody could see, which is worse
    /// than refusing, so the reason is spelled out instead.
    var candidatePromotionObstacle: String? {
        guard let baseline = canvas.preview?.baseline else {
            return "There is no baseline on screen to overwrite."
        }
        guard baseline.origin != .pullRequest else {
            return Self.pullRequestPromotionObstacle
        }
        guard baseline.isWritable else {
            return """
            The baseline on screen was read out of \(CanvasModel.comparisonGitRef) and exists only \
            for this comparison. The candidate is already the file on disk — commit it to \
            make it the recorded baseline.
            """
        }
        return nil
    }

    var canPromoteCandidate: Bool { candidatePromotionObstacle == nil }

    /// Why the candidate out of a test run cannot be written to.
    static let testRunRevertObstacle = """
        The candidate is a copy of what the test run rendered, not a file in the \
        project. Run the test again to replace it.
        """

    /// Why neither side of a pull request comparison can be written to.
    static let pullRequestPromotionObstacle = """
        Both images were downloaded from a GitHub pull request for review. Accept or reject \
        the change on its branch; there is no file on disk here to overwrite.
        """

    /// Whether the candidate on disk can be put back to what the baseline holds.
    ///
    /// True for a committed baseline as well as a recorded one: the candidate is always the
    /// working file, and that is the side this writes to — except under pull request
    /// review, where the candidate is a downloaded copy as well.
    var canRevertToBaseline: Bool { candidateRevertObstacle == nil }

    /// Why the candidate cannot be put back to the baseline, or `nil` when it can.
    var candidateRevertObstacle: String? {
        guard let candidate = canvas.preview?.candidate, canvas.preview?.baseline != nil else {
            return "There is no comparison on screen to reject."
        }
        guard candidate.isWritable else {
            return candidate.origin == .testRun ? Self.testRunRevertObstacle : Self.pullRequestPromotionObstacle
        }
        return nil
    }

    /// Accepts the candidate: copies it over the baseline on disk.
    ///
    /// - Parameter actionName: What Edit ▸ Undo calls the write.
    /// - Returns: Whether the baseline was written.
    @discardableResult
    func promoteCandidateToBaseline(actionName: String = "Accept Candidate") -> Bool {
        guard let candidate = canvas.preview?.candidate, let baseline = canvas.preview?.baseline else { return false }

        if let obstacle = candidatePromotionObstacle {
            report(obstacle)
            return false
        }

        let saved = saveForUndo([baseline.fileURL])
        guard copy(contentsOf: candidate.fileURL, over: baseline.fileURL) else {
            discardSaved(saved)
            return false
        }
        registerUndo(restoring: saved, actionName: actionName)

        // The snapshot now holds what the run rendered, so the failure is settled. Settled
        // before the refresh, so the images reloaded are the ones left on the canvas rather
        // than the run's copy, which may be gone.
        if case let .testRunFailure(_, snapshotID, _) = canvas.preview {
            resolveTestRunFailure(snapshotID: snapshotID)
        }
        finishFileAction()
        return true
    }

    // MARK: - Test runs

    /// How many snapshots Accept All would re-record: every one the run on screen failed on.
    ///
    /// Zero outside the run's view, so the action is only offered where its effect is listed.
    var acceptableTestRunFailuresCount: Int {
        guard sidebarSource == .testRun else { return 0 }
        return testRuns.results?.failedSnapshotsCount ?? 0
    }

    /// Asks before ``acceptAllTestRunFailures()``, which every route to it goes through.
    ///
    /// A single Accept overwrites the file on the canvas, which has just been looked at;
    /// accepting them all overwrites files nobody may have opened, so it is confirmed first.
    func requestAcceptAllTestRunFailures() {
        guard acceptableTestRunFailuresCount > 0 else { return }
        isConfirmingAcceptAllTestRunFailures = true
    }

    /// Accepts every failure of the run on screen: copies what each test rendered over the
    /// snapshot it failed on.
    ///
    /// Each snapshot takes the image its canvas opens on — the first its test attached
    /// besides the baseline — so accepting them all is accepting each one as shown. Images
    /// that matched no snapshot are left alone: there is no file of the project for them to
    /// replace. A write that fails keeps its snapshot listed, with the error on the banner,
    /// and does not hold back the others.
    func acceptAllTestRunFailures() {
        isConfirmingAcceptAllTestRunFailures = false
        guard acceptableTestRunFailuresCount > 0, let testRun = testRuns.results else { return }

        var accepted: Set<SnapshotItem.ID> = []
        var saved: [SavedFile] = []
        for snapshot in currentProject?.suites.flatMap(\.snapshots) ?? [] where !accepted.contains(snapshot.id) {
            guard let candidate = testRun.candidates(forSnapshotID: snapshot.id).first else { continue }
            let original = saveForUndo([snapshot.fileURL])
            guard copy(contentsOf: candidate.fileURL, over: snapshot.fileURL) else {
                discardSaved(original)
                continue
            }
            saved += original
            accepted.insert(snapshot.id)
        }

        // One step for the lot: the confirmation asked about them together.
        registerUndo(restoring: saved, actionName: "Accept All Test Run Failures")
        guard !accepted.isEmpty else { return }
        resolveTestRunFailures(snapshotIDs: accepted)
        finishFileAction()
    }

    // MARK: - Loose pairs

    /// Settles an undecided pair in favour of the left image: it is written over the right
    /// one, and stays on screen on its own.
    ///
    /// Written rather than merely kept, unlike ``keepBaseline()``: with the sides unknown,
    /// the right image may be the recorded snapshot, and keeping the left has to reach it.
    func keepLeft() {
        guard canvas.looseRolesAreUnknown, revertCandidateToBaseline(actionName: "Keep Left") else { return }
        closePane(.candidate)
    }

    /// Settles an undecided pair in favour of the right image: it is written over the left
    /// one, and stays on screen on its own.
    func keepRight() {
        guard canvas.looseRolesAreUnknown, promoteCandidateToBaseline(actionName: "Keep Right") else { return }
        closePane(.baseline)
    }

    /// Settles a pasted pair in favour of the recorded file: nothing is written, and the
    /// baseline stays on screen on its own.
    func keepBaseline() {
        guard canvas.preview?.isLoosePair == true, !canvas.looseRolesAreUnknown else { return }
        closePane(.candidate)
    }

    /// Settles a pasted pair in favour of the candidate: it is written over the baseline,
    /// which then stays on screen on its own, holding what was kept.
    ///
    /// A write that fails leaves the pair up, so the error banner is read against it.
    func keepCandidate() {
        guard canvas.preview?.isLoosePair == true,
              !canvas.looseRolesAreUnknown,
              promoteCandidateToBaseline(actionName: "Keep Candidate")
        else { return }
        closePane(.candidate)
    }

    /// Rejects the candidate: copies the baseline back over it on disk.
    ///
    /// - Parameter actionName: What Edit ▸ Undo calls the write.
    /// - Returns: Whether the candidate was written.
    @discardableResult
    func revertCandidateToBaseline(actionName: String = "Reject Candidate") -> Bool {
        guard let candidate = canvas.preview?.candidate, let baseline = canvas.preview?.baseline else { return false }
        if let obstacle = candidateRevertObstacle {
            report(obstacle)
            return false
        }
        let saved = saveForUndo([candidate.fileURL])
        guard copy(contentsOf: baseline.fileURL, over: candidate.fileURL) else {
            discardSaved(saved)
            return false
        }
        registerUndo(restoring: saved, actionName: actionName)
        finishFileAction()
        return true
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
    func copy(contentsOf source: URL, over destination: URL) -> Bool {
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
        guard let snapshotID = canvas.preview?.snapshotID else { return nil }
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
}
