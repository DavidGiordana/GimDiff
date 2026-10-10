//
//  FileActionsTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The two actions that write a snapshot, and the state they leave behind.
@Suite("Canvas file actions")
@MainActor
struct FileActionsTests {
    private static let candidateURL = URL(fileURLWithPath: "/Projects/Demo/failures/header.png")
    private static let baselineURL = URL(fileURLWithPath: "/Projects/Demo/Snapshots/header.png")

    /// An `AppState` holding a comparison between two files that both exist on disk.
    private func loosePair(
        candidate: String = "candidate-bytes",
        baseline: String = "baseline-bytes"
    ) -> (state: AppState, filesystem: MockFilesystemService, defaults: TemporaryDefaults) {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        filesystem.stub(Self.candidateURL, contents: candidate)
        filesystem.stub(Self.baselineURL, contents: baseline)

        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            defaults: defaults.defaults
        )
        state.showComparison(reference: Self.baselineURL, failure: Self.candidateURL)
        return (state, filesystem, defaults)
    }

    // MARK: - Promotion

    @Test("Accepting the candidate writes it over the baseline and leaves the candidate alone")
    func promotesTheCandidate() {
        let fixture = loosePair()
        let tokenBefore = fixture.state.imageReloadToken

        fixture.state.promoteCandidateToBaseline()

        #expect(fixture.filesystem.contents(of: Self.baselineURL) == "candidate-bytes")
        // Staged through a scratch file precisely so `replaceFile` cannot consume the image
        // the canvas is still pointing at.
        #expect(fixture.filesystem.contents(of: Self.candidateURL) == "candidate-bytes")
        #expect(fixture.state.lastError == nil)
        #expect(fixture.state.imageReloadToken == tokenBefore + 1)
    }

    @Test("Reverting writes the baseline back over the candidate")
    func revertsToTheBaseline() {
        let fixture = loosePair()

        fixture.state.revertCandidateToBaseline()

        #expect(fixture.filesystem.contents(of: Self.candidateURL) == "baseline-bytes")
        #expect(fixture.filesystem.contents(of: Self.baselineURL) == "baseline-bytes")
        #expect(fixture.state.lastError == nil)
    }

    @Test("A comparison of two files on disk leaves both decisions open, with nothing to explain")
    func offersBothDecisions() {
        let fixture = loosePair()

        #expect(fixture.state.candidatePromotionObstacle == nil)
        #expect(fixture.state.candidateRevertObstacle == nil)
    }

    @Test("Rejection with no comparison on screen is unavailable, and says so")
    func explainsAnUnavailableRejection() {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        filesystem.stub(Self.candidateURL, contents: "candidate-bytes")
        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            defaults: defaults.defaults
        )
        state.openPath(Self.candidateURL)

        #expect(state.canRevertToBaseline == false)
        #expect(state.candidateRevertObstacle != nil)
        // Nothing to compare is not a failure, so nothing reaches the banner.
        state.revertCandidateToBaseline()
        #expect(state.lastError == nil)
    }

    // MARK: - Loose pairs

    @Test("A pasted pair is decided by keeping a side; a snapshot's comparison is not")
    func recognisesALoosePair() {
        let fixture = loosePair()
        #expect(fixture.state.preview?.isLoosePair == true)

        fixture.state.setPreview(.comparison(
            SnapshotPair(reference: Self.baselineURL, failure: Self.candidateURL),
            snapshotID: "header",
            title: "header",
            baselineOrigin: .workingTree
        ))
        #expect(fixture.state.preview?.isLoosePair == false)
    }

    @Test("Keeping the baseline writes nothing and leaves the baseline on screen alone")
    func keepsTheBaseline() {
        let fixture = loosePair()

        fixture.state.keepBaseline()

        #expect(fixture.filesystem.contents(of: Self.baselineURL) == "baseline-bytes")
        #expect(fixture.filesystem.contents(of: Self.candidateURL) == "candidate-bytes")
        #expect(fixture.state.preview?.isComparison == false)
        #expect(fixture.state.preview?.panes.map(\.fileURL) == [Self.baselineURL])
    }

    @Test("Keeping the candidate writes it over the baseline, which then stands alone")
    func keepsTheCandidate() {
        let fixture = loosePair()

        fixture.state.keepCandidate()

        #expect(fixture.filesystem.contents(of: Self.baselineURL) == "candidate-bytes")
        #expect(fixture.state.preview?.isComparison == false)
        #expect(fixture.state.preview?.panes.map(\.fileURL) == [Self.baselineURL])
        #expect(fixture.state.lastError == nil)
    }

    @Test("Keeping a candidate that cannot be written leaves the pair up beside the error")
    func keepsThePairWhenTheWriteFails() {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        filesystem.stub(Self.baselineURL, contents: "baseline-bytes")
        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            defaults: defaults.defaults
        )
        // The candidate is named but was never written, so the copy has no source.
        state.showComparison(reference: Self.baselineURL, failure: Self.candidateURL)

        state.keepCandidate()

        #expect(state.preview?.isComparison == true)
        #expect(state.lastError != nil)
    }

    // MARK: - Undecided pairs

    @Test("A pair nothing could tell apart is named by position, not by role")
    func namesAnUndecidedPairByPosition() throws {
        let fixture = loosePair()
        fixture.state.showComparison(
            reference: Self.baselineURL,
            failure: Self.candidateURL,
            certainty: .unknown
        )

        let preview = try #require(fixture.state.preview)
        #expect(fixture.state.looseRolesAreUnknown)
        #expect(preview.panes.map(fixture.state.sideTitle(for:)) == ["Left", "Right"])

        // Keeping "the baseline" would be acting on a guess, so it is not on offer.
        fixture.state.keepBaseline()
        #expect(fixture.state.preview?.isComparison == true)
    }

    @Test("Keeping the left image writes it over the right one, which may be the recorded file")
    func keepsTheLeftImage() {
        let fixture = loosePair()
        fixture.state.showComparison(
            reference: Self.baselineURL,
            failure: Self.candidateURL,
            certainty: .unknown
        )

        fixture.state.keepLeft()

        #expect(fixture.filesystem.contents(of: Self.candidateURL) == "baseline-bytes")
        #expect(fixture.state.preview?.panes.map(\.fileURL) == [Self.baselineURL])
    }

    @Test("Keeping the right image writes it over the left one and leaves it on screen")
    func keepsTheRightImage() {
        let fixture = loosePair()
        fixture.state.showComparison(
            reference: Self.baselineURL,
            failure: Self.candidateURL,
            certainty: .unknown
        )

        fixture.state.keepRight()

        #expect(fixture.filesystem.contents(of: Self.baselineURL) == "candidate-bytes")
        #expect(fixture.state.preview?.panes.map(\.fileURL) == [Self.candidateURL])
        // The pair is decided; the image left on screen is no longer one of two unknowns.
        #expect(fixture.state.looseRolesAreUnknown == false)
    }

    @Test("A pasted pair whose files tell them apart is shown the right way round")
    func resolvesAPastedPairFromTheFiles() async {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        var git = StubGitService(repositoryRoot: URL(fileURLWithPath: "/Projects/Demo"))
        git.trackedFiles = [Self.baselineURL]
        let state = AppState(filesystem: filesystem, gitService: git, defaults: defaults.defaults)

        // Handed over the wrong way round, with nothing in the source to say otherwise.
        state.showLooseComparison(
            baseline: Self.candidateURL,
            candidate: Self.baselineURL,
            rolesAreStated: false
        )
        await state.currentLooseRoleResolution?.value

        #expect(state.preview?.baseline?.fileURL == Self.baselineURL)
        #expect(state.preview?.candidate?.fileURL == Self.candidateURL)
        #expect(state.looseRoleCertainty == .inferred(.trackedByGit, swapped: true))
        #expect(state.preview.map { $0.panes.map(state.sideTitle(for:)) } == ["Baseline", "Candidate"])
    }

    @Test("Neither action leaves the staging file behind")
    func cleansUpTheStagingFile() {
        let fixture = loosePair()

        fixture.state.promoteCandidateToBaseline()

        let staged = fixture.filesystem.files.keys.filter { $0.hasPrefix("/mock-tmp/") }
        #expect(staged.isEmpty)
    }

    @Test("A promotion with nothing to write to is refused rather than attempted")
    func refusesAPromotionWithoutABaseline() {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        filesystem.stub(Self.candidateURL, contents: "candidate-bytes")
        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            defaults: defaults.defaults
        )
        state.openPath(Self.candidateURL)

        #expect(state.canPromoteCandidate == false)
        state.promoteCandidateToBaseline()
        #expect(state.lastError == nil)
    }

    @Test("A baseline read out of a commit cannot be promoted onto, and says why")
    func refusesToWriteOverACommittedBaseline() {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        let committed = URL(fileURLWithPath: "/mock-tmp/header-HEAD.png")
        filesystem.stub(Self.candidateURL, contents: "candidate-bytes")
        filesystem.stub(committed, contents: "committed-bytes")

        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            defaults: defaults.defaults
        )
        state.setPreview(.comparison(
            SnapshotPair(reference: committed, failure: Self.candidateURL),
            snapshotID: nil,
            title: "header",
            baselineOrigin: .committedVersion
        ))

        #expect(state.canPromoteCandidate == false)
        state.promoteCandidateToBaseline()

        #expect(filesystem.contents(of: committed) == "committed-bytes")
        #expect(state.lastError?.contains("HEAD") == true)

        // The candidate is the working file either way, so putting it back is still offered.
        #expect(state.canRevertToBaseline)
        state.revertCandidateToBaseline()
        #expect(filesystem.contents(of: Self.candidateURL) == "committed-bytes")
    }

    @Test("A write that fails reaches the error banner and changes nothing")
    func reportsAFailedWrite() {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()
        filesystem.stub(Self.baselineURL, contents: "baseline-bytes")
        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            defaults: defaults.defaults
        )
        // The candidate is named but was never written, so the copy has no source.
        state.showComparison(reference: Self.baselineURL, failure: Self.candidateURL)

        state.promoteCandidateToBaseline()

        #expect(filesystem.contents(of: Self.baselineURL) == "baseline-bytes")
        #expect(state.lastError != nil)
    }

    // MARK: - Panes

    @Test("Closing one pane leaves the other on screen on its own")
    func closingAPaneKeepsTheOther() {
        let fixture = loosePair()

        fixture.state.closePane(.baseline)

        #expect(fixture.state.preview?.isComparison == false)
        #expect(fixture.state.preview?.candidate?.fileURL == Self.candidateURL)

        fixture.state.closePane(.candidate)
        #expect(fixture.state.preview == nil)
    }

    @Test("Closing the candidate promotes the baseline to the only pane")
    func closingTheCandidateKeepsTheBaseline() {
        let fixture = loosePair()

        fixture.state.closePane(.candidate)

        #expect(fixture.state.preview?.candidate?.fileURL == Self.baselineURL)
    }

    // MARK: - Roles

    @Test("Each pane names its side and where its file came from")
    func describesEachRole() {
        let fixture = loosePair()

        #expect(fixture.state.preview?.candidate?.roleTitle == "Candidate")
        #expect(fixture.state.preview?.candidate?.roleSubtitle == "Current")
        #expect(fixture.state.preview?.baseline?.roleTitle == "Baseline")
        #expect(fixture.state.preview?.baseline?.roleSubtitle == "Recorded on Disk")

        let committed = SnapshotPane(
            role: .baseline,
            fileURL: Self.baselineURL,
            origin: .committedVersion
        )
        #expect(committed.roleSubtitle == "Committed in Git")
        #expect(committed.isWritable == false)
    }

    @Test("The baseline leads, so the panes read old to new")
    func ordersThePanes() {
        let fixture = loosePair()

        #expect(fixture.state.preview?.panes.map(\.role) == [.baseline, .candidate])
    }
}
