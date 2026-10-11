//
//  PullRequestReviewTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import Foundation
import Testing
@testable import GimDiff

@Suite("Pull request review")
@MainActor
struct PullRequestReviewTests {
    private static let reference = GitHubPRReference(owner: "octo", repo: "app", pullNumber: 7)
    private static let snapshotPath = "Tests/Snapshots/HomeTests/testHome.png"

    // MARK: - Opening

    @Test("A fetched pull request replaces the tree, with every suite open")
    func showsPullRequestSuites() async throws {
        let fixture = Fixture()

        await fixture.open("https://github.com/octo/app/pull/7")

        let session = try #require(fixture.state.pullRequestReview.session)
        #expect(session.id == "octo/app#7")
        #expect(fixture.state.isReviewingPullRequest)
        #expect(fixture.state.currentProject?.suites.map(\.name) == ["HomeTests", "LoginTests"])
        #expect(fixture.state.visibleRows.count == 4)
        #expect(!fixture.state.pullRequestReview.isSheetPresented)
        #expect(!fixture.state.pullRequestReview.isFetching)
        #expect(fixture.state.pullRequestReview.input.isEmpty)
        #expect(fixture.service.requested == [Self.reference])
    }

    @Test("A fetched pull request selects and shows its first snapshot")
    func selectsFirstSnapshot() async throws {
        let fixture = Fixture()

        await fixture.open("https://github.com/octo/app/pull/7")

        let snapshotRows = fixture.state.visibleRows.filter(\.isSnapshot)
        let firstSnapshot = try #require(snapshotRows.first)
        #expect(fixture.state.selectedRowID == firstSnapshot.id)
        #expect(fixture.state.canvas.preview?.snapshotID == firstSnapshot.snapshot?.id)
    }

    @Test("A failed fetch keeps the sheet up with the reason, and the project untouched")
    func failedFetchStaysInSheet() async throws {
        let fixture = Fixture(result: .failure(GitHubCLIAuthError.notAuthenticated))
        let project = AppStateFixture.twoSuites()
        fixture.state.load(project)

        await fixture.open("https://github.com/octo/app/pull/7")

        #expect(fixture.state.pullRequestReview.isSheetPresented)
        #expect(!fixture.state.pullRequestReview.isFetching)
        #expect(fixture.state.pullRequestReview.error == "Please run 'gh auth login' in terminal to review GitHub PRs")
        #expect(fixture.state.pullRequestReview.session == nil)
        #expect(fixture.state.currentProject == project)
    }

    @Test("Text that names no pull request is refused before anything is fetched")
    func rejectsUnrecognisedInput() async throws {
        let fixture = Fixture()

        await fixture.open("not a pull request")

        #expect(fixture.state.pullRequestReview.error != nil)
        #expect(fixture.service.requested.isEmpty)
    }

    @Test("A bare number is looked up in the open project's GitHub remote")
    func resolvesNumberAgainstProject() async throws {
        var git = StubGitService()
        git.remoteURL = "git@github.com:octo/app.git"
        let fixture = Fixture(gitService: git)
        fixture.state.load(AppStateFixture.twoSuites())

        await fixture.open("7")

        #expect(fixture.service.requested == [Self.reference])
        #expect(fixture.state.isReviewingPullRequest)
    }

    @Test("A gimdiff://open-pr URL opens the review")
    func opensFromURLScheme() async throws {
        let fixture = Fixture()
        let url = try #require(URL(string: "gimdiff://open-pr?url=https://github.com/octo/app/pull/7"))

        fixture.state.handle(url)
        await fixture.state.pullRequestReview.currentFetch?.value

        #expect(fixture.state.isReviewingPullRequest)
    }

    @Test("Pasting a pull request link opens the review")
    func opensFromClipboard() async throws {
        let fixture = Fixture()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("please review https://github.com/octo/app/pull/7", forType: .string)

        fixture.state.pasteFromClipboard()
        await fixture.state.pullRequestReview.currentFetch?.value

        #expect(fixture.service.requested == [Self.reference])
        #expect(fixture.state.isReviewingPullRequest)
    }

    @Test("The sheet is filled in from a pull request link on the clipboard")
    func prefillsSheetFromClipboard() {
        let fixture = Fixture()
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("github.com/octo/app/pull/7/files", forType: .string)

        fixture.state.presentPullRequestSheet()

        #expect(fixture.state.pullRequestReview.isSheetPresented)
        #expect(fixture.state.pullRequestReview.input == "https://github.com/octo/app/pull/7")
    }

    // MARK: - Canvas

    @Test("A changed snapshot is shown against its base, with both panes read-only")
    func showsReadOnlyComparison() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        let session = try #require(fixture.state.pullRequestReview.session)
        let change = try #require(session.changes[Self.snapshotPath])

        fixture.selectSnapshot(Self.snapshotPath)

        let preview = try #require(fixture.state.canvas.preview)
        #expect(preview.candidate?.fileURL == change.candidateURL)
        #expect(preview.baseline?.fileURL == change.baselineURL)
        #expect(preview.panes.allSatisfy { $0.origin == .pullRequest && !$0.isWritable })
        #expect(preview.baseline?.roleSubtitle == "Base Branch")
        #expect(!fixture.state.canPromoteCandidate)
        #expect(!fixture.state.canRevertToBaseline)
        #expect(fixture.state.candidatePromotionObstacle == AppState.pullRequestPromotionObstacle)
    }

    @Test("Promoting or reverting under review writes nothing")
    func promotionsWriteNothing() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        fixture.selectSnapshot(Self.snapshotPath)
        let before = fixture.filesystem.files

        fixture.state.promoteCandidateToBaseline()
        fixture.state.revertCandidateToBaseline()

        #expect(fixture.filesystem.files == before)
        #expect(fixture.state.lastError == AppState.pullRequestPromotionObstacle)
    }

    @Test("Deleting under review is refused and trashes nothing")
    func deletionIsRefused() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        fixture.selectSnapshot(Self.snapshotPath)
        let rowCount = fixture.state.visibleRows.count

        fixture.state.deleteSelection()

        #expect(fixture.filesystem.trashedPaths.isEmpty)
        #expect(fixture.state.visibleRows.count == rowCount)
        #expect(fixture.state.lastError != nil)
    }

    @Test("Each snapshot knows what the pull request did to it")
    func namesEachChange() async throws {
        let fixture = Fixture(result: .success(.mixed))
        await fixture.open("https://github.com/octo/app/pull/7")

        #expect(fixture.state.pullRequestReview.change(forSnapshotID: "Tests/Snapshots/HomeTests/testAdded.png")?.kind == .added)
        #expect(fixture.state.pullRequestReview.change(forSnapshotID: "Tests/Snapshots/HomeTests/testGone.png")?.kind == .removed)
        #expect(fixture.state.pullRequestReview.change(forSnapshotID: "Tests/Snapshots/HomeTests/testHome.png")?.kind == .modified)
        #expect(fixture.state.pullRequestReview.change(forSnapshotID: nil) == nil)
        #expect(PRSnapshotChange.Kind.removed.title == "Deleted")
    }

    @Test("An added snapshot is shown on its own, as the pull request's version")
    func showsAddedSnapshotAlone() async throws {
        let fixture = Fixture(result: .success(.mixed))
        await fixture.open("https://github.com/octo/app/pull/7")

        fixture.selectSnapshot("Tests/Snapshots/HomeTests/testAdded.png")

        let preview = try #require(fixture.state.canvas.preview)
        #expect(!preview.isComparison)
        #expect(preview.panes.map(\.role) == [.candidate])
        #expect(preview.candidate?.origin == .pullRequest)
        #expect(preview.candidate?.roleSubtitle == "Pull Request Head")
        #expect(preview.snapshotID == "Tests/Snapshots/HomeTests/testAdded.png")
    }

    @Test("A deleted snapshot is shown on its own, as the base branch's version")
    func showsDeletedSnapshotAlone() async throws {
        let fixture = Fixture(result: .success(.mixed))
        await fixture.open("https://github.com/octo/app/pull/7")

        fixture.selectSnapshot("Tests/Snapshots/HomeTests/testGone.png")

        let preview = try #require(fixture.state.canvas.preview)
        #expect(preview.panes.map(\.role) == [.baseline])
        #expect(preview.baseline?.origin == .pullRequest)
        #expect(preview.baseline?.roleSubtitle == "Base Branch")
        #expect(preview.candidate == nil)
        #expect(!fixture.state.canPromoteCandidate)
        #expect(!fixture.state.canRevertToBaseline)
    }

    @Test("Showing only the pull request's version drops the base branch")
    func showsHeadOnly() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        let snapshot = try #require(fixture.state.pullRequestReview.session?.suites.first?.snapshots.first)

        fixture.state.showSnapshot(snapshot, withGitDiff: false)

        let preview = try #require(fixture.state.canvas.preview)
        #expect(preview.panes.map(\.role) == [.candidate])
        #expect(preview.candidate?.origin == .pullRequest)
    }

    @Test("Closing one pane of a comparison keeps the other a pull request side")
    func closingAPaneStaysReadOnly() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        fixture.selectSnapshot(Self.snapshotPath)

        fixture.state.closePane(.candidate)

        let preview = try #require(fixture.state.canvas.preview)
        #expect(preview.panes.map(\.role) == [.baseline])
        #expect(preview.baseline?.origin == .pullRequest)
        #expect(preview.snapshotID == Self.snapshotPath)
        #expect(fixture.state.pullRequestReview.change(forSnapshotID: preview.snapshotID)?.kind == .modified)
    }

    // MARK: - Closing

    @Test("Closing the review deletes its files and puts the project back")
    func closeRestoresProject() async throws {
        let fixture = Fixture()
        let project = AppStateFixture.twoSuites()
        fixture.state.load(project)
        await fixture.open("https://github.com/octo/app/pull/7")
        let session = try #require(fixture.state.pullRequestReview.session)

        fixture.state.closePullRequestReview()

        #expect(fixture.state.pullRequestReview.session == nil)
        #expect(fixture.state.currentProject == project)
        #expect(fixture.filesystem.removedPaths == [session.tempDirectoryURL.path])
        #expect(!fixture.filesystem.fileExists(at: session.tempDirectoryURL))
        #expect(fixture.filesystem.trashedPaths.isEmpty)
    }

    @Test("A review is left unwatched, and closing it watches the project again")
    func reviewIsNotWatched() async throws {
        let fixture = Fixture()
        let project = AppStateFixture.twoSuites()
        fixture.state.load(project)
        #expect(fixture.watcher.watchedRoots == [[project.rootURL]])

        await fixture.open("https://github.com/octo/app/pull/7")
        #expect(fixture.watcher.watchedRoots.count == 1)

        fixture.state.closePullRequestReview()
        #expect(fixture.watcher.watchedRoots == [[project.rootURL], [project.rootURL]])
    }

    @Test("Closing a review opened with no project returns to the recent list")
    func closeWithoutProject() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")

        fixture.state.closePullRequestReview()

        #expect(fixture.state.currentProject == nil)
        #expect(fixture.state.canvas.preview == nil)
        #expect(fixture.filesystem.removedPaths.count == 1)
    }

    @Test("A second review replaces the first but still returns to the original project")
    func secondReviewKeepsOriginalProject() async throws {
        let fixture = Fixture()
        let project = AppStateFixture.twoSuites()
        fixture.state.load(project)
        await fixture.open("https://github.com/octo/app/pull/7")
        let first = try #require(fixture.state.pullRequestReview.session)

        await fixture.open("https://github.com/octo/app/pull/7")
        let second = try #require(fixture.state.pullRequestReview.session)
        #expect(first.tempDirectoryURL != second.tempDirectoryURL)
        #expect(fixture.filesystem.removedPaths == [first.tempDirectoryURL.path])

        fixture.state.closePullRequestReview()
        #expect(fixture.state.currentProject == project)
    }

    @Test("Closing the project ends the review without bringing the old project back")
    func openingProjectEndsReview() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        let session = try #require(fixture.state.pullRequestReview.session)

        fixture.state.closeProject()

        #expect(fixture.state.pullRequestReview.session == nil)
        #expect(fixture.state.currentProject == nil)
        #expect(fixture.filesystem.removedPaths == [session.tempDirectoryURL.path])
    }

    @Test("The app's exit deletes the review's files")
    func terminationDiscardsFiles() async throws {
        let fixture = Fixture()
        await fixture.open("https://github.com/octo/app/pull/7")
        let session = try #require(fixture.state.pullRequestReview.session)

        fixture.state.pullRequestReview.discardFiles()

        #expect(!fixture.filesystem.fileExists(at: session.tempDirectoryURL))
    }

    @Test("A pull request touching no snapshot opens as an empty review")
    func emptyReview() async throws {
        let fixture = Fixture(result: .success(.empty))

        await fixture.open("https://github.com/octo/app/pull/7")

        #expect(fixture.state.isReviewingPullRequest)
        #expect(fixture.state.pullRequestReview.session?.suites.isEmpty == true)
        #expect(fixture.state.visibleRows.isEmpty)
    }
}

// MARK: - Fixture

/// What the stubbed pull request changes.
private enum Outcome: Sendable {
    /// Two suites with one modified snapshot each.
    case populated
    /// Files, but no snapshots among them.
    case empty
    /// One snapshot added, one deleted, and one modified, all in `HomeTests`.
    case mixed
}

@MainActor
private struct Fixture {
    let state: AppState
    let filesystem = MockFilesystemService()
    let service: StubPRService
    let watcher = StubProjectWatcher()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("GimDiffTests-\(UUID().uuidString)"))
    let defaults = TemporaryDefaults()

    init(
        result: Result<Outcome, any Error> = .success(.populated),
        gitService: StubGitService = StubGitService()
    ) {
        service = StubPRService(filesystem: filesystem, result: result)
        state = AppState(
            filesystem: filesystem,
            gitService: gitService,
            watcher: watcher,
            clipboard: ClipboardService(pasteboard: pasteboard),
            pullRequests: service,
            defaults: defaults.defaults
        )
    }

    func open(_ input: String) async {
        state.openPullRequest(input)
        await state.pullRequestReview.currentFetch?.value
    }

    func selectSnapshot(_ path: String) {
        let row = state.visibleRows.first { row in
            if case let .snapshot(snapshot, _) = row { return snapshot.id == path }
            return false
        }
        state.selectRow(withID: row?.id)
    }
}

/// A `GitHubPRService` that writes a canned session into the mock filesystem.
private final class StubPRService: GitHubPRService, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [GitHubPRReference] = []
    private let filesystem: MockFilesystemService
    private let result: Result<Outcome, any Error>

    init(filesystem: MockFilesystemService, result: Result<Outcome, any Error>) {
        self.filesystem = filesystem
        self.result = result
    }

    var requested: [GitHubPRReference] { lock.withLock { recorded } }

    func fetchPRSession(reference: GitHubPRReference) async throws -> PRReviewSession {
        lock.withLock { recorded.append(reference) }
        let outcome = try result.get()

        let directory = MockFilesystemService.temporaryDirectory
            .appendingPathComponent("PR-\(UUID().uuidString)", isDirectory: true)
        filesystem.createDirectory(at: directory)

        var changes: [PRSnapshotChange] = []
        if outcome == .mixed {
            for (name, kind) in [("testAdded", PRSnapshotChange.Kind.added), ("testGone", .removed), ("testHome", .modified)] {
                let path = "Tests/Snapshots/HomeTests/\(name).png"
                let candidate = kind == .removed ? nil : directory.appendingPathComponent("head/\(path)")
                let baseline = kind == .added ? nil : directory.appendingPathComponent("base/\(path)")
                if let candidate { filesystem.stub(candidate, contents: "head") }
                if let baseline { filesystem.stub(baseline, contents: "base") }
                changes.append(PRSnapshotChange(
                    path: path,
                    kind: kind,
                    candidateURL: candidate,
                    baselineURL: baseline
                ))
            }
        }
        if outcome == .populated {
            for path in [
                "Tests/Snapshots/HomeTests/testHome.png",
                "Tests/Snapshots/LoginTests/testLogin.png",
            ] {
                let candidate = directory.appendingPathComponent("head/\(path)")
                let baseline = directory.appendingPathComponent("base/\(path)")
                filesystem.stub(candidate, contents: "head")
                filesystem.stub(baseline, contents: "base")
                changes.append(PRSnapshotChange(
                    path: path,
                    kind: .modified,
                    candidateURL: candidate,
                    baselineURL: baseline
                ))
            }
        }

        return PRReviewSession(
            id: reference.shortDescription,
            reference: reference,
            prNumber: reference.pullNumber,
            title: "Refresh the home screen",
            author: "mona",
            baseRef: "main",
            headRef: "feature/home",
            baseSHA: "base000",
            headSHA: "head111",
            suites: DefaultGitHubPRService.suites(
                from: changes,
                candidateRoot: directory.appendingPathComponent("head", isDirectory: true)
            ),
            changes: Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0) }),
            changedFileCount: max(changes.count, 3),
            tempDirectoryURL: directory
        )
    }
}
