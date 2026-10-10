//
//  TestRunTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// A test run's failures, laid over the tree and acted on from the canvas.
@Suite("Test run failures")
@MainActor
struct TestRunTests {
    private static let scratch = URL(fileURLWithPath: "/scratch/run", isDirectory: true)
    private static let unmatchedSuite = "Unmatched Test Run Attachments"

    /// `twoSuites()` with every snapshot holding bytes of its own, and a run that failed on
    /// `header` and `menu` and attached one image that belongs to nothing.
    private func openWithFailures(
        resultDirectories: [URL] = [],
        switchingToRun: Bool = true,
        attachingUnmatched: Bool = true
    ) async -> AppStateFixture {
        let fixture = AppStateFixture()
        fixture.testResults.resultDirectories = resultDirectories
        let bundle = AppStateFixture.twoSuites()
        for suite in bundle.suites {
            fixture.filesystem.createDirectory(at: suite.snapshotsFolderURL)
            for snapshot in suite.snapshots {
                fixture.filesystem.stub(snapshot.fileURL, contents: "\(snapshot.name) recorded")
            }
        }

        var failures = [
            failure("AlphaTests/testHeader()", images: [
                ("R1", "header recorded"), ("X", "header rendered"), ("D", "header difference"),
            ]),
            failure("BetaTests/testMenu()", images: [("R2", "menu recorded"), ("Y", "menu rendered")]),
        ]
        if attachingUnmatched {
            failures.append(failure("BetaTests/testNew()", images: [("N", "never recorded")]))
        }
        fixture.testResults.report = TestRunReport(
            bundleURL: StubTestResults.bundleURL,
            scratchDirectory: Self.scratch,
            failures: failures
        )
        for failure in fixture.testResults.report?.failures ?? [] {
            for image in failure.groups.flatMap(\.images) {
                fixture.filesystem.stub(image.fileURL, contents: contents[image.id] ?? "")
            }
        }

        fixture.state.load(bundle)
        await fixture.state.currentTestRunLocate?.value
        if switchingToRun {
            fixture.state.showTestRun()
            await fixture.state.currentTestRunRefresh?.value
        }
        return fixture
    }

    private let contents = [
        "R1": "header recorded", "X": "header rendered", "D": "header difference",
        "R2": "menu recorded", "Y": "menu rendered", "N": "never recorded",
    ]

    private func failure(
        _ identifier: String,
        images: [(id: String, contents: String)],
        scratch: URL = Self.scratch
    ) -> TestRunFailure {
        TestRunFailure(
            id: identifier,
            name: String(identifier.split(separator: "/").last ?? ""),
            groups: [
                TestRunImageGroup(
                    id: "\(identifier)#0/0",
                    title: "Attached",
                    images: images.map { image in
                        TestRunImage(
                            id: image.id,
                            name: "attachment \(image.id)",
                            fileURL: scratch.appendingPathComponent("\(image.id).png")
                        )
                    }
                ),
            ]
        )
    }

    private func snapshot(_ name: String, in fixture: AppStateFixture) throws -> SnapshotItem {
        try #require(fixture.state.currentProject?.suites.flatMap(\.snapshots).first { $0.name == name })
    }

    private func expandAll(_ fixture: AppStateFixture) {
        for case let .suite(suite, isExpanded, _) in fixture.state.visibleRows where !isExpanded {
            fixture.state.toggleExpansion(ofSuiteWithID: suite.id)
        }
    }

    // MARK: - Switching

    @Test("A project opens on its own status, without reading the run")
    func opensOnProjectStatus() async throws {
        let fixture = await openWithFailures(switchingToRun: false)

        #expect(fixture.state.sidebarSource == .project)
        #expect(fixture.testResults.readCount == 0)
        #expect(fixture.state.testRun == nil)
        #expect(fixture.state.canShowTestRun)
        #expect(fixture.rowDescriptions == ["AlphaTests", "BetaTests"])
    }

    @Test("Switching to the run reads it and lists only what failed")
    func listsFailures() async throws {
        let fixture = await openWithFailures()
        let state = fixture.state

        #expect(state.sidebarSource == .testRun)
        #expect(fixture.testResults.readCount == 1)
        #expect(state.testRun?.failedSnapshotsCount == 2)
        #expect(state.isFailingInTestRun(try snapshot("header", in: fixture)))
        #expect(!state.isFailingInTestRun(try snapshot("footer", in: fixture)))
        // Opened for reading, the way a pull request review is.
        #expect(fixture.rowDescriptions == [
            "AlphaTests",
            "AlphaTests/header",
            "BetaTests",
            "BetaTests/menu",
            Self.unmatchedSuite,
            "\(Self.unmatchedSuite)/testNew() · attachment N",
        ])
    }

    @Test("Switching to the run lands on its first failure")
    func selectsFirstFailure() async throws {
        let fixture = await openWithFailures()

        #expect(fixture.selectedRowDescription == "AlphaTests/header")
        #expect(fixture.state.preview?.candidate?.origin == .testRun)
    }

    @Test("Switching back lists the whole project again, and the run is kept")
    func switchesBack() async throws {
        let fixture = await openWithFailures()

        fixture.state.showProjectStatus()

        #expect(fixture.state.sidebarSource == .project)
        #expect(fixture.rowDescriptions.contains("AlphaTests/footer"))
        #expect(!fixture.rowDescriptions.contains { $0.hasPrefix(Self.unmatchedSuite) })
        // The header row is still selected, and is shown the way the project shows it.
        #expect(fixture.selectedRowDescription == "AlphaTests/header")
        #expect(fixture.state.preview?.candidate?.origin == .workingTree)

        fixture.state.showTestRun()
        await fixture.state.currentTestRunRefresh?.value
        #expect(fixture.testResults.readCount == 1)
        #expect(fixture.state.preview?.candidate?.origin == .testRun)
    }

    @Test("The project's filters are put away under the run")
    func clearsFiltersOnSwitch() async throws {
        let fixture = await openWithFailures(switchingToRun: false)
        fixture.state.showWarningsOnly = true

        fixture.state.showTestRun()
        await fixture.state.currentTestRunRefresh?.value

        #expect(!fixture.state.showWarningsOnly)
        #expect(!fixture.state.canFilterByWarnings)
        #expect(!fixture.state.canFilterByGitChanges)
    }

    @Test("A project that has never been tested offers no switch")
    func hidesSwitchWithoutRun() async throws {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        await fixture.state.currentTestRunLocate?.value

        #expect(fixture.state.latestTestRunBundle == nil)
        #expect(!fixture.state.canShowTestRun)
        #expect(!fixture.state.showsSidebarSourcePicker)

        fixture.state.showTestRun()
        #expect(fixture.state.sidebarSource == .project)
        #expect(fixture.testResults.readCount == 0)
    }

    @Test("A project with a run offers the switch without reading the run")
    func showsSwitchWithRun() async throws {
        let fixture = await openWithFailures(switchingToRun: false)

        #expect(fixture.state.latestTestRunBundle == StubTestResults.bundleURL)
        #expect(fixture.state.showsSidebarSourcePicker)
        #expect(fixture.testResults.readCount == 0)
    }

    @Test("A run that disappears while it is shown keeps the way back")
    func keepsSwitchWhenRunDisappears() async throws {
        let fixture = await openWithFailures()
        fixture.testResults.report = nil

        fixture.state.refreshTestRun()
        await fixture.state.currentTestRunRefresh?.value

        #expect(!fixture.state.canShowTestRun)
        #expect(fixture.state.showsSidebarSourcePicker)
        #expect(fixture.state.testRunError != nil)

        fixture.state.showProjectStatus()
        #expect(!fixture.state.showsSidebarSourcePicker)
    }

    @Test("A run with nothing failed says so and keeps no scratch folder")
    func passingRunLeavesNothing() async throws {
        let fixture = AppStateFixture()
        fixture.testResults.report = TestRunReport(
            bundleURL: StubTestResults.bundleURL,
            scratchDirectory: Self.scratch,
            failures: []
        )
        fixture.filesystem.createDirectory(at: Self.scratch)
        fixture.state.load(AppStateFixture.twoSuites())
        await fixture.state.currentTestRunLocate?.value

        fixture.state.showTestRun()
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.testRun?.isEmpty == true)
        #expect(fixture.state.testRunError == nil)
        #expect(fixture.state.isShowingTestRunPlaceholder)
        #expect(!fixture.filesystem.fileExists(at: Self.scratch))
    }

    @Test("There is no run to switch to under pull request review or without a project")
    func noRunWithoutProject() {
        let fixture = AppStateFixture()

        #expect(!fixture.state.canShowTestRun)
        fixture.state.showTestRun()
        #expect(fixture.state.sidebarSource == .project)
    }

    // MARK: - The canvas

    @Test("A failing snapshot opens against what its test rendered")
    func showsTheRenderedCandidate() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)

        fixture.state.showSnapshot(header, withGitDiff: true)

        #expect(fixture.state.preview?.candidate?.fileURL == Self.scratch.appendingPathComponent("X.png"))
        #expect(fixture.state.preview?.candidate?.origin == .testRun)
        #expect(fixture.state.preview?.baseline?.fileURL == header.fileURL)
        #expect(fixture.state.preview?.baseline?.origin == .workingTree)
        #expect(fixture.state.preview?.snapshotID == header.id)
        // D is the difference picture attached after the rendering; the diff mask replaces it.
        #expect(fixture.state.testRunCandidatesOnScreen.map(\.name) == ["attachment X"])
    }

    @Test("Another rendering of the same snapshot can be put in the candidate pane")
    func switchesCandidates() async throws {
        let fixture = await openWithFailures()
        fixture.state.showSnapshot(try snapshot("header", in: fixture), withGitDiff: true)
        // As a test asserting the snapshot a second time would offer it.
        let other = TestRunImage(id: "X2", name: "second", fileURL: Self.scratch.appendingPathComponent("X2.png"))

        fixture.state.selectTestRunCandidate(other)

        #expect(fixture.state.preview?.candidate?.fileURL == other.fileURL)
        #expect(fixture.state.preview?.baseline?.fileURL == (try snapshot("header", in: fixture)).fileURL)
    }

    @Test("Under the project's status, a failing snapshot opens the way any other does")
    func projectStatusIgnoresRun() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        fixture.state.showProjectStatus()

        fixture.state.showSnapshot(header, withGitDiff: true)

        #expect(fixture.state.preview?.candidate?.origin == .workingTree)
    }

    @Test("Without the diff, a failing snapshot shows on its own")
    func showsSnapshotAlone() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)

        fixture.state.showSnapshot(header, withGitDiff: false)

        #expect(fixture.state.preview == .single(header))
    }

    @Test("Accepting the candidate re-records the snapshot and settles its failure")
    func acceptsTheCandidate() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        fixture.state.showSnapshot(header, withGitDiff: true)

        fixture.state.promoteCandidateToBaseline()

        #expect(fixture.filesystem.contents(of: header.fileURL) == "header rendered")
        #expect(fixture.state.lastError == nil)
        #expect(!fixture.state.isFailingInTestRun(header))
        #expect(fixture.state.testRun?.failedSnapshotsCount == 1)
    }

    @Test("Accepting takes the snapshot off the run's list and moves on")
    func acceptingMovesOn() async throws {
        let fixture = await openWithFailures()
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/header"))

        fixture.state.promoteCandidateToBaseline()

        #expect(fixture.selectedRowDescription == "BetaTests")
        #expect(!fixture.rowDescriptions.contains("AlphaTests/header"))
    }

    @Test("Accepting a failure while the selection rests on a suite shows the accepted snapshot")
    func acceptingLeavesTheSettledSnapshot() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/header"))

        fixture.state.promoteCandidateToBaseline()

        #expect(fixture.state.preview == .single(header))
    }

    @Test("Accepting the last failure closes the canvas instead of reloading the run's copy")
    func acceptingTheLastFailureClosesTheCanvas() async throws {
        let fixture = await openWithFailures(attachingUnmatched: false)
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/header"))
        fixture.state.promoteCandidateToBaseline()
        fixture.state.selectRow(withID: fixture.rowID("BetaTests/menu"))

        fixture.state.promoteCandidateToBaseline()

        #expect(fixture.state.testRun?.isEmpty == true)
        #expect(fixture.state.isShowingTestRunPlaceholder)
        #expect(!fixture.filesystem.fileExists(at: Self.scratch))
        #expect(fixture.state.preview == nil)
        #expect(fixture.state.lastError == nil)
    }

    @Test("Accepting all re-records every failing snapshot and leaves the unmatched images")
    func acceptsAllFailures() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        let menu = try snapshot("menu", in: fixture)
        fixture.state.showSnapshot(header, withGitDiff: true)
        #expect(fixture.state.acceptableTestRunFailuresCount == 2)

        fixture.state.acceptAllTestRunFailures()

        #expect(fixture.filesystem.contents(of: header.fileURL) == "header rendered")
        #expect(fixture.filesystem.contents(of: menu.fileURL) == "menu rendered")
        #expect(fixture.state.lastError == nil)
        #expect(fixture.state.testRun?.failedSnapshotsCount == 0)
        #expect(fixture.state.acceptableTestRunFailuresCount == 0)
        #expect(fixture.rowDescriptions.allSatisfy { $0.hasPrefix(Self.unmatchedSuite) })
        // The canvas no longer points into the run's scratch folder.
        #expect(fixture.state.preview == .single(header))
    }

    @Test("Accepting all when only failures are listed closes the canvas and deletes the copies")
    func acceptingAllWithoutUnmatchedClosesTheCanvas() async throws {
        let fixture = await openWithFailures(attachingUnmatched: false)
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/header"))

        fixture.state.acceptAllTestRunFailures()

        #expect(fixture.state.isShowingTestRunPlaceholder)
        #expect(!fixture.filesystem.fileExists(at: Self.scratch))
        #expect(fixture.state.preview == nil)
    }

    @Test("Discarding what Accept All wrote brings the failures back")
    func discardingAcceptedFailuresRestoresThem() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        let menu = try snapshot("menu", in: fixture)

        fixture.state.acceptAllTestRunFailures()
        await fixture.state.currentGitStatusRefresh?.value
        // What the status read after a real accept would report.
        fixture.state.applyGitStatuses([header.fileURL: .modified, menu.fileURL: .modified])
        #expect(fixture.state.testRun?.failedSnapshotsCount == 0)

        fixture.state.showProjectStatus()
        // What `git restore` would leave behind.
        fixture.filesystem.stub(header.fileURL, contents: "header recorded")
        fixture.filesystem.stub(menu.fileURL, contents: "menu recorded")
        fixture.state.discardAllGitChanges()
        await fixture.state.currentDiscard?.value
        #expect(fixture.state.testRun == nil)

        // Reading the bundle again exports its attachments again.
        for image in fixture.testResults.report?.failures.flatMap(\.groups).flatMap(\.images) ?? [] {
            fixture.filesystem.stub(image.fileURL, contents: contents[image.id] ?? "")
        }
        fixture.state.showTestRun()
        await fixture.state.currentTestRunRefresh?.value
        #expect(fixture.testResults.readCount == 2)
        #expect(fixture.state.testRun?.failedSnapshotsCount == 2)
        #expect(fixture.state.isFailingInTestRun(header))
    }

    @Test("A write that fails keeps its snapshot listed while the others are accepted")
    func acceptingAllSurvivesAFailedWrite() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        let menu = try snapshot("menu", in: fixture)
        try fixture.filesystem.removeItem(at: Self.scratch.appendingPathComponent("X.png"))

        fixture.state.acceptAllTestRunFailures()

        #expect(fixture.state.lastError != nil)
        #expect(fixture.filesystem.contents(of: header.fileURL) == "header recorded")
        #expect(fixture.filesystem.contents(of: menu.fileURL) == "menu rendered")
        #expect(fixture.state.isFailingInTestRun(header))
        #expect(!fixture.state.isFailingInTestRun(menu))
    }

    @Test("Asking to accept all confirms first and writes nothing yet")
    func acceptAllAsksFirst() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)

        fixture.state.requestAcceptAllTestRunFailures()

        #expect(fixture.state.isConfirmingAcceptAllTestRunFailures)
        #expect(fixture.filesystem.contents(of: header.fileURL) == "header recorded")

        fixture.state.acceptAllTestRunFailures()

        #expect(!fixture.state.isConfirmingAcceptAllTestRunFailures)
        #expect(fixture.filesystem.contents(of: header.fileURL) == "header rendered")
    }

    @Test("Accepting all is not offered under the project's status")
    func acceptAllNeedsTheRunsView() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        fixture.state.showProjectStatus()

        #expect(fixture.state.acceptableTestRunFailuresCount == 0)
        fixture.state.requestAcceptAllTestRunFailures()
        #expect(!fixture.state.isConfirmingAcceptAllTestRunFailures)
        fixture.state.acceptAllTestRunFailures()

        #expect(fixture.filesystem.contents(of: header.fileURL) == "header recorded")
    }

    @Test("There is nothing to revert onto an image copied out of the run")
    func refusesRevert() async throws {
        let fixture = await openWithFailures()
        let header = try snapshot("header", in: fixture)
        fixture.state.showSnapshot(header, withGitDiff: true)

        #expect(!fixture.state.canRevertToBaseline)
        fixture.state.revertCandidateToBaseline()

        #expect(fixture.state.lastError == AppState.testRunRevertObstacle)
        #expect(fixture.filesystem.contents(of: header.fileURL) == "header recorded")
    }

    @Test("Closing the baseline pane leaves the run's image on its own, still named")
    func closingBaselineKeepsCandidate() async throws {
        let fixture = await openWithFailures()
        fixture.state.showSnapshot(try snapshot("header", in: fixture), withGitDiff: true)

        fixture.state.closePane(.baseline)

        guard case let .testRunAttachment(item) = fixture.state.preview else {
            Issue.record("Expected the candidate on its own, got \(String(describing: fixture.state.preview))")
            return
        }
        #expect(item.name == "attachment X")
        #expect(fixture.state.preview?.candidate?.origin == .testRun)
    }

    // MARK: - Unmatched attachments

    @Test("An image nothing claims opens on its own and cannot be deleted")
    func unmatchedAttachment() async throws {
        let fixture = await openWithFailures()
        expandAll(fixture)
        let rowID = try #require(fixture.rowID("\(Self.unmatchedSuite)/testNew() · attachment N"))
        let file = Self.scratch.appendingPathComponent("N.png")

        fixture.state.selectRow(withID: rowID)
        #expect(fixture.state.preview?.candidate?.fileURL == file)
        #expect(fixture.state.preview?.isComparison == false)
        #expect(!fixture.state.canPromoteCandidate)

        fixture.state.deleteSelection()

        #expect(fixture.filesystem.fileExists(at: file))
        #expect(fixture.filesystem.trashedPaths.isEmpty)
        #expect(fixture.state.lastError != nil)
    }

    @Test("The suite of unmatched images carries no missing-source warning")
    func unmatchedSuiteIsNotAWarning() async throws {
        let fixture = await openWithFailures()
        let attachments = try #require(fixture.state.testRunAttachmentsSuite)

        #expect(attachments.isMissingSourceCode)
        #expect(!fixture.state.hasSourceWarning(attachments))
    }

    // MARK: - History

    private static let olderBundle = URL(fileURLWithPath: "/DerivedData/Demo-hash/Logs/Test/Older.xcresult")
    private static let olderScratch = URL(fileURLWithPath: "/scratch/older", isDirectory: true)

    /// Adds a run older than the one `openWithFailures` sets up, which failed on `header`
    /// alone, and locates both.
    private func addOlderRun(to fixture: AppStateFixture) async {
        let older = failure(
            "AlphaTests/testHeader()",
            images: [("R1", "header recorded"), ("O", "header rendered long ago")],
            scratch: Self.olderScratch
        )
        for image in older.groups.flatMap(\.images) {
            fixture.filesystem.stub(image.fileURL, contents: image.id == "R1" ? "header recorded" : "header rendered long ago")
        }
        fixture.filesystem.createDirectory(at: Self.olderScratch)
        fixture.filesystem.createDirectory(at: Self.scratch)
        fixture.testResults.reports.append(TestRunReport(
            bundleURL: Self.olderBundle,
            scratchDirectory: Self.olderScratch,
            failures: [older]
        ))
        fixture.state.locateTestRun()
        await fixture.state.currentTestRunLocate?.value
    }

    @Test("Every run is offered, newest first, and the newest is the one shown")
    func offersEveryRunNewestFirst() async throws {
        let fixture = await openWithFailures(switchingToRun: false)
        await addOlderRun(to: fixture)

        #expect(fixture.state.testRunBundles.map(\.url) == [StubTestResults.bundleURL, Self.olderBundle])
        #expect(fixture.state.selectedTestRunBundle?.url == StubTestResults.bundleURL)

        fixture.state.showTestRun()
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.testRun?.bundleURL == StubTestResults.bundleURL)
        #expect(fixture.state.pinnedTestRunBundleURL == nil)
    }

    @Test("Picking an older run lists what it failed on, and deletes the newer run's copies")
    func picksOlderRun() async throws {
        let fixture = await openWithFailures()
        await addOlderRun(to: fixture)

        fixture.state.showTestRun(from: Self.olderBundle)
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.testRun?.bundleURL == Self.olderBundle)
        #expect(fixture.state.selectedTestRunBundle?.url == Self.olderBundle)
        #expect(fixture.rowDescriptions == ["AlphaTests", "AlphaTests/header"])
        #expect(fixture.selectedRowDescription == "AlphaTests/header")
        #expect(fixture.state.preview?.candidate?.fileURL == Self.olderScratch.appendingPathComponent("O.png"))
        #expect(fixture.filesystem.removedPaths.contains(Self.scratch.path))
    }

    @Test("Picking a run while the project is shown switches to it")
    func pickingSwitchesToRun() async throws {
        let fixture = await openWithFailures(switchingToRun: false)
        await addOlderRun(to: fixture)

        fixture.state.showTestRun(from: Self.olderBundle)
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.sidebarSource == .testRun)
        #expect(fixture.state.testRun?.bundleURL == Self.olderBundle)
        #expect(fixture.testResults.readCount == 1)
    }

    @Test("A picked run stays on screen when the results change, and the newest is followed again once picked")
    func pinnedRunStays() async throws {
        let fixture = await openWithFailures()
        await addOlderRun(to: fixture)
        fixture.state.showTestRun(from: Self.olderBundle)
        await fixture.state.currentTestRunRefresh?.value
        let reads = fixture.testResults.readCount

        fixture.state.refreshTestRun()
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.testRun?.bundleURL == Self.olderBundle)
        #expect(fixture.testResults.readCount == reads)

        fixture.state.showTestRun(from: StubTestResults.bundleURL)
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.pinnedTestRunBundleURL == nil)
        #expect(fixture.state.testRun?.bundleURL == StubTestResults.bundleURL)
    }

    @Test("A picked run that is deleted gives way to the newest")
    func deletedPinnedRunFallsBack() async throws {
        let fixture = await openWithFailures()
        await addOlderRun(to: fixture)
        fixture.state.showTestRun(from: Self.olderBundle)
        await fixture.state.currentTestRunRefresh?.value

        fixture.testResults.reports.removeLast()
        fixture.state.refreshTestRun()
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.pinnedTestRunBundleURL == nil)
        #expect(fixture.state.testRun?.bundleURL == StubTestResults.bundleURL)
    }

    // MARK: - Lifetime

    @Test("Closing the project deletes the images copied out of the run")
    func closingDeletesScratch() async throws {
        let fixture = await openWithFailures()

        fixture.state.closeProject()

        #expect(fixture.state.testRun == nil)
        #expect(fixture.filesystem.removedPaths == [Self.scratch.path])
    }

    @Test("A new run written to derived data replaces the results")
    func newRunReplacesResults() async throws {
        let directory = URL(fileURLWithPath: "/DerivedData/Demo-hash/Logs/Test", isDirectory: true)
        let fixture = await openWithFailures(resultDirectories: [directory])
        #expect(fixture.watcher.watchedRoots.last?.contains(directory) == true)

        let secondScratch = URL(fileURLWithPath: "/scratch/second", isDirectory: true)
        fixture.testResults.report = TestRunReport(
            bundleURL: StubTestResults.bundleURL,
            scratchDirectory: secondScratch,
            failures: []
        )
        fixture.watcher.send([ProjectFileEvent(url: directory.appendingPathComponent("Run2.xcresult/Info.plist"))])

        for _ in 0 ..< 400 where fixture.state.testRun?.isEmpty != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        await fixture.state.currentTestRunRefresh?.value

        #expect(fixture.state.testRun?.isEmpty == true)
        #expect(fixture.filesystem.removedPaths.contains(Self.scratch.path))
    }

    @Test("A new run written while the project is shown is only noted, not read")
    func newRunOffScreenIsNotRead() async throws {
        let directory = URL(fileURLWithPath: "/DerivedData/Demo-hash/Logs/Test", isDirectory: true)
        let fixture = await openWithFailures(resultDirectories: [directory])
        fixture.state.showProjectStatus()

        await fixture.state.projectFilesChanged([
            ProjectFileEvent(url: directory.appendingPathComponent("Run2.xcresult/Info.plist")),
        ])

        #expect(fixture.state.testRun == nil)
        #expect(fixture.testResults.readCount == 1)
        #expect(fixture.filesystem.removedPaths.contains(Self.scratch.path))
    }
}
