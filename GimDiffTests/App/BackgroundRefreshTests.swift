//
//  BackgroundRefreshTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// What a fresh scan does to a window somebody is in the middle of using.
@Suite("Merging a background scan")
@MainActor
struct ProjectMergeTests {
    /// `bundle` without the snapshots or suites `isRemoved` picks out.
    private func pruned(_ bundle: ProjectBundle, where isRemoved: (String) -> Bool) -> ProjectBundle {
        var result = bundle
        result.suites = bundle.suites.compactMap { suite in
            guard !isRemoved(suite.name) else { return nil }
            var kept = suite
            kept.snapshots.removeAll { isRemoved("\(suite.name)/\($0.name)") }
            return kept
        }
        return result
    }

    @Test("A scan that found the same project changes nothing")
    func identicalBundle() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/footer"))
        let preview = fixture.state.canvas.preview

        fixture.state.merge(AppStateFixture.twoSuites())

        #expect(fixture.selectedRowDescription == "AlphaTests/footer")
        #expect(fixture.state.isExpanded(suiteWithID: fixture.suiteID("AlphaTests")))
        #expect(fixture.state.canvas.preview == preview)
    }

    @Test("New snapshots arrive around a selection, open suites, and canvas that all stay put")
    func addedSnapshot() {
        let fixture = AppStateFixture(bundle: pruned(AppStateFixture.twoSuites()) { $0 == "AlphaTests/header" })
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/footer"))
        fixture.state.filterText = "o"

        fixture.state.merge(AppStateFixture.twoSuites())

        #expect(fixture.state.filterText == "o")
        fixture.state.filterText = ""
        #expect(fixture.rowDescriptions == [
            "AlphaTests", "AlphaTests/header", "AlphaTests/footer", "AlphaTests/sidebar", "BetaTests",
        ])
        #expect(fixture.selectedRowDescription == "AlphaTests/footer")
        #expect(fixture.state.canvas.preview?.title == "footer")
    }

    @Test("A selected snapshot that is gone hands the selection to the row below and closes its pane")
    func removedSelection() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/footer"))

        fixture.state.merge(pruned(AppStateFixture.twoSuites()) { $0 == "AlphaTests/footer" })

        #expect(fixture.selectedRowDescription == "AlphaTests/sidebar")
        #expect(fixture.state.canvas.preview == nil)
    }

    @Test("With nothing below it, the selection moves to the row above")
    func removedLastRow() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("BetaTests")
        fixture.select("BetaTests/menu")

        fixture.state.merge(pruned(AppStateFixture.twoSuites()) { $0 == "BetaTests/menu" })

        #expect(fixture.selectedRowDescription == "BetaTests/toolbar")
    }

    @Test("A suite that is gone takes its rows and its open state with it")
    func removedSuite() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let alphaID = fixture.suiteID("AlphaTests")
        fixture.expand("AlphaTests")
        fixture.select("AlphaTests/sidebar")

        fixture.state.merge(pruned(AppStateFixture.twoSuites()) { $0 == "AlphaTests" })

        #expect(fixture.rowDescriptions == ["BetaTests"])
        #expect(fixture.selectedRowDescription == "BetaTests")
        #expect(fixture.state.isExpanded(suiteWithID: alphaID) == false)
    }

    @Test("A preview of a snapshot that is still there survives the merge")
    func keptPreview() {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/header"))

        fixture.state.merge(pruned(AppStateFixture.twoSuites()) { $0 == "BetaTests" })

        #expect(fixture.state.canvas.preview?.title == "header")
        #expect(fixture.selectedRowDescription == "AlphaTests/header")
    }

    @Test("A tree that had no rows gets a selection once it has some")
    func emptyTreeFills() {
        let fixture = AppStateFixture(bundle: ProjectBundle(rootURL: AppStateFixture.root))
        #expect(fixture.state.selectedRowID == nil)

        fixture.state.merge(AppStateFixture.twoSuites())

        #expect(fixture.selectedRowDescription == "AlphaTests")
    }
}

/// File events driven through `AppState`, against a real project on disk where a rescan
/// is involved and against the in-memory one where it is not.
@Suite("Refreshing from file events")
@MainActor
struct BackgroundRefreshTests {
    private static let buttonSuite = "Tests/__Snapshots__/ButtonTests"

    /// A scanned point-free project, with the state, its watcher, and the fixture kept alive.
    private func openProject() async throws -> (AppState, StubProjectWatcher, ProjectFixture, TemporaryDefaults) {
        let fixture = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        let watcher = StubProjectWatcher()
        let state = AppState(gitService: StubGitService(), watcher: watcher, defaults: defaults.defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value
        return (state, watcher, fixture, defaults)
    }

    private func settle(_ state: AppState) async {
        await state.currentBackgroundRefresh?.value
        await state.currentGitStatusRefresh?.value
    }

    /// Waits for something that happens on another task's schedule, within reason.
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 1000 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Rescans

    @Test("A snapshot written by a test run appears without the window being reset")
    func newSnapshotAppears() async throws {
        let (state, _, fixture, defaults) = try await openProject()
        _ = defaults
        let shown = try #require(state.visibleRows.last)
        state.selectRow(withID: shown.id)
        let preview = state.canvas.preview

        let added = try fixture.write("\(Self.buttonSuite)/button.3.png")
        await state.projectFilesChanged([ProjectFileEvent(url: added)])
        await settle(state)

        #expect(state.currentProject?.suites.first?.snapshots.count == 3)
        #expect(state.selectedRowID == shown.id)
        #expect(state.canvas.preview == preview)
        #expect(state.isLoading == false)
        #expect(state.lastError == nil)
    }

    @Test("A snapshot deleted outside GimDiff leaves the tree and hands on the selection")
    func removedSnapshotDisappears() async throws {
        let (state, _, fixture, defaults) = try await openProject()
        _ = defaults
        let rows = state.visibleRows
        let doomed = try #require(rows.first { $0.isSnapshot })
        state.selectRow(withID: doomed.id)

        let removed = fixture.fileURL("\(Self.buttonSuite)/button.1.png")
        try FileManager.default.removeItem(at: removed)
        await state.projectFilesChanged([ProjectFileEvent(url: removed)])
        await settle(state)

        #expect(state.currentProject?.suites.first?.snapshots.count == 1)
        #expect(state.selectedRowID == rows.last?.id)
        #expect(state.canvas.preview == nil)
    }

    @Test("Events delivered by the watcher reach the project on their own")
    func watcherDrivesTheRefresh() async throws {
        let (state, watcher, fixture, defaults) = try await openProject()
        _ = defaults
        #expect(watcher.watchedRoots == [[fixture.url]])

        let added = try fixture.write("\(Self.buttonSuite)/button.3.png")
        watcher.send([ProjectFileEvent(url: added)])
        try await eventually { state.currentProject?.suites.first?.snapshots.count == 3 }

        #expect(state.currentProject?.suites.first?.snapshots.count == 3)
    }

    @Test("A snapshot written by another process reaches the project through FSEvents")
    func externalWriteReachesTheProject() async throws {
        let fixture = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        // The watcher the app ships with, which leaves this process's own writes out.
        let state = AppState(gitService: StubGitService(), defaults: defaults.defaults)
        state.openProject(at: fixture.url)
        await state.currentScan?.value

        let copy = Process()
        copy.executableURL = URL(fileURLWithPath: "/bin/cp")
        copy.arguments = [
            fixture.fileURL("\(Self.buttonSuite)/button.1.png").path,
            fixture.fileURL("\(Self.buttonSuite)/button.3.png").path,
        ]
        try copy.run()
        copy.waitUntilExit()
        try await eventually { state.currentProject?.suites.first?.snapshots.count == 3 }

        #expect(state.currentProject?.suites.first?.snapshots.count == 3)
        #expect(state.isLoading == false)
    }

    @Test("Closing the project stops the watcher")
    func closingStopsWatching() async throws {
        let (state, watcher, _, defaults) = try await openProject()
        _ = defaults
        try await eventually { watcher.activeStreamCount == 1 }
        #expect(watcher.activeStreamCount == 1)

        state.closeProject()
        try await eventually { watcher.activeStreamCount == 0 }

        #expect(watcher.activeStreamCount == 0)
    }

    @Test("A state that is released stops its watcher")
    func releasingStopsWatching() async throws {
        let watcher = StubProjectWatcher()
        do {
            let fixture = AppStateFixture()
            let state = AppState(filesystem: fixture.filesystem, watcher: watcher, defaults: fixture.defaults.defaults)
            state.load(AppStateFixture.twoSuites())
            try await eventually { watcher.activeStreamCount == 1 }
            #expect(watcher.activeStreamCount == 1)
        }

        try await eventually { watcher.activeStreamCount == 0 }
        #expect(watcher.activeStreamCount == 0)
    }

    // MARK: - Rewrites

    @Test("A rewritten snapshot on screen is read again, without a rescan")
    func rewrittenSnapshotOnScreen() async {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/footer"))
        let token = fixture.state.canvas.imageReloadToken

        let footer = AppStateFixture.root.appendingPathComponent("Snapshots/AlphaTests/footer.png")
        await fixture.state.projectFilesChanged([ProjectFileEvent(url: footer)])
        await fixture.state.currentBackgroundRefresh?.value

        #expect(fixture.state.canvas.imageReloadToken == token + 1)
        #expect(fixture.state.canvas.preview?.title == "footer")
        #expect(fixture.selectedRowDescription == "AlphaTests/footer")
    }

    @Test("A rewritten snapshot that is not on screen redraws nothing")
    func rewrittenSnapshotOffScreen() async {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        fixture.expand("AlphaTests")
        fixture.state.selectRow(withID: fixture.rowID("AlphaTests/footer"))
        let token = fixture.state.canvas.imageReloadToken

        let sidebar = AppStateFixture.root.appendingPathComponent("Snapshots/AlphaTests/sidebar.png")
        await fixture.state.projectFilesChanged([ProjectFileEvent(url: sidebar)])
        await fixture.state.currentBackgroundRefresh?.value

        #expect(fixture.state.canvas.imageReloadToken == token)
    }

    // MARK: - Git

    @Test("A commit refreshes the badges and nothing else")
    func commitRefreshesBadges() async throws {
        let footer = AppStateFixture.root.appendingPathComponent("Snapshots/AlphaTests/footer.png")
        let defaults = TemporaryDefaults()
        let state = AppState(
            filesystem: MockFilesystemService(),
            gitService: StubGitService(repositoryRoot: AppStateFixture.root, statuses: [footer: .modified]),
            watcher: StubProjectWatcher(),
            defaults: defaults.defaults
        )
        state.load(AppStateFixture.twoSuites())
        let token = state.canvas.imageReloadToken

        let head = AppStateFixture.root.appendingPathComponent(".git/HEAD")
        await state.projectFilesChanged([ProjectFileEvent(url: head)])
        await settle(state)

        let statuses = state.currentProject?.suites.first?.snapshots.map(\.gitStatus)
        #expect(statuses == [.unmodified, .modified, .unmodified])
        #expect(state.canvas.imageReloadToken == token)
    }

    @Test("A project below the top of its repository watches the Git directory above it too")
    func watchesTheGitDirectoryAboveTheProject() {
        let fixture = AppStateFixture()
        let repository = AppStateFixture.root.deletingLastPathComponent()
        let gitDirectory = repository.appendingPathComponent(".git", isDirectory: true)
        fixture.filesystem.createDirectory(at: gitDirectory)

        fixture.state.load(ProjectBundle(rootURL: AppStateFixture.root, gitRootURL: repository))

        #expect(fixture.watcher.watchedRoots == [[AppStateFixture.root, gitDirectory]])
    }

    // MARK: - Noise

    @Test("Build products and saved sources start no refresh at all")
    func noiseIsIgnored() async {
        let fixture = AppStateFixture(bundle: AppStateFixture.twoSuites())
        let project = fixture.state.currentProject

        await fixture.state.projectFilesChanged([
            ProjectFileEvent(url: AppStateFixture.root.appendingPathComponent(".build/debug/icon.png")),
            ProjectFileEvent(url: AppStateFixture.root.appendingPathComponent("Sources/App.swift")),
            ProjectFileEvent(url: AppStateFixture.root.appendingPathComponent(".git/index")),
        ])

        #expect(fixture.state.currentBackgroundRefresh == nil)
        #expect(fixture.state.currentProject == project)
    }
}
