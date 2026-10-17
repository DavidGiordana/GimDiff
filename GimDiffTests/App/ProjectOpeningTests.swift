//
//  ProjectOpeningTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// `AppState` against the real scanner and the real disk, rather than a built bundle.
@Suite("Opening a project")
@MainActor
struct ProjectOpeningTests {
    private func state(defaults: TemporaryDefaults) -> AppState {
        AppState(gitService: StubGitService(), watcher: StubProjectWatcher(), defaults: defaults.defaults)
    }

    @Test("A scanned project fills the tree and remembers the folder")
    func scansAProject() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value

        #expect(state.isLoading == false)
        #expect(state.currentProject?.suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])
        #expect(state.recentProjects.map(\.path) == [fixture.url.path])
        #expect(state.lastError == nil)
    }

    @Test("The first row is selected once a scan lands, so the keyboard has somewhere to start")
    func selectsTheFirstRow() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value

        let selected = try #require(state.selectedRowID)
        #expect(selected == state.visibleRows.first?.id)
    }

    @Test("A folder that is not one reports an error instead of scanning")
    func refusesANonFolder() {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: URL(fileURLWithPath: "/no/such/folder"))

        #expect(state.currentProject == nil)
        #expect(state.isLoading == false)
        #expect(state.lastError?.contains("is not a folder") == true)
    }

    @Test("A second open cancels the first, and only the newer result lands")
    func supersedesTheScanInFlight() async throws {
        let first = try ProjectFixture.modularProject()
        let second = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: first.url)
        let superseded = state.currentScan
        state.openProject(at: second.url)
        await superseded?.value
        await state.currentScan?.value

        #expect(state.currentProject?.rootURL == second.url)
        #expect(state.currentProject?.suites.map(\.name) == ["ButtonTests"])
        #expect(state.isLoading == false)
    }

    @Test("The folder being scanned is named before its project exists")
    func namesTheFolderInFlight() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)

        #expect(state.isLoading)
        #expect(state.currentProject == nil)
        #expect(state.loadingProjectURL?.path == fixture.url.resolvingSymlinksInPath().path)

        await state.currentScan?.value

        #expect(state.loadingProjectURL == nil)
        #expect(state.currentProject != nil)
    }

    @Test("Cancelling the first scan leaves no project open")
    func cancellingAFirstOpen() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        let scan = state.currentScan
        state.cancelProjectLoading()
        await scan?.value

        #expect(state.currentProject == nil)
        #expect(state.isLoading == false)
        #expect(state.lastError == nil)
    }

    @Test("Cancelling a rescan keeps the project it was refreshing")
    func cancellingAReload() async throws {
        let fixture = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value

        try fixture.write("Tests/__Snapshots__/ButtonTests/button.3.png")
        state.reload()
        let scan = state.currentScan
        state.cancelProjectLoading()
        await scan?.value

        #expect(state.isLoading == false)
        #expect(state.currentProject?.suites.first?.snapshots.count == 2)
    }

    @Test("Reload rescans the open project and picks up a new snapshot")
    func reloadSeesNewSnapshots() async throws {
        let fixture = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value
        #expect(state.currentProject?.suites.first?.snapshots.count == 2)

        try fixture.write("Tests/__Snapshots__/ButtonTests/button.3.png")
        state.reload()
        await state.currentScan?.value

        #expect(state.currentProject?.suites.first?.snapshots.count == 3)
    }

    @Test("Reload does nothing when no project is open")
    func reloadNeedsAProject() {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.reload()

        #expect(state.currentScan == nil)
        #expect(state.isLoading == false)
    }

    @Test("A folder handed over as a path is scanned; a loose image is previewed")
    func routesAPathByWhatItIs() async throws {
        let fixture = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openPath(fixture.url)
        await state.currentScan?.value
        #expect(state.currentProject?.rootURL == fixture.url)

        state.openPath(fixture.fileURL("Tests/__Snapshots__/ButtonTests/button.1.png"))
        #expect(state.canvas.preview?.title == "button.1")
    }

    @Test("A path that is neither a folder nor an image is reported")
    func refusesAnythingElse() throws {
        let fixture = try ProjectFixture.pointFreeProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openPath(fixture.fileURL("Package.swift"))

        #expect(state.canvas.preview == nil)
        #expect(state.lastError?.contains("Package.swift") == true)
    }

    @Test("Two dropped images become one comparison")
    func pairsTwoDroppedImages() async {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)
        let reference = URL(fileURLWithPath: "/tmp/reference.png")
        let failure = URL(fileURLWithPath: "/tmp/failure.png")

        state.openPaths([reference, failure])
        await state.canvas.currentLooseRoleResolution?.value

        guard case let .comparison(pair, snapshotID, title, baselineOrigin) = state.canvas.preview else {
            Issue.record("Expected a comparison, got \(String(describing: state.canvas.preview))")
            return
        }
        #expect(pair.reference.url == reference)
        #expect(pair.failure.url == failure)
        #expect(snapshotID == nil)
        #expect(title == "failure")
        // Two loose files are both on disk, so both promotion actions apply to them.
        #expect(baselineOrigin == .workingTree)
        // Neither file stands apart and a drop labels nothing, so the order is only a guess.
        #expect(state.canvas.looseRoleCertainty == .unknown)
    }

    @Test("An empty drop changes nothing")
    func ignoresAnEmptyDrop() {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openPaths([])

        #expect(state.canvas.preview == nil)
        #expect(state.lastError == nil)
    }

    // MARK: - Closing

    @Test("Closing a project clears everything that described it")
    func closingClearsTheProject() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value
        state.filterText = "profile"
        state.showGitModifiedOnly = true
        let snapshot = try #require(state.currentProject?.suites.first?.snapshots.first)
        state.showSnapshot(snapshot, withGitDiff: false)

        state.closeProject()

        #expect(state.currentProject == nil)
        #expect(state.visibleRows.isEmpty)
        #expect(state.selectedRowID == nil)
        #expect(state.expandedSuiteIDs.isEmpty)
        #expect(state.canvas.preview == nil)
        #expect(state.isFiltering == false)
        #expect(state.isLoading == false)
    }

    @Test("A closed project stays in the recent list, so it is one click away again")
    func closingKeepsTheFolderInRecents() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        await state.currentScan?.value
        state.closeProject()

        #expect(state.recentProjects.map(\.path) == [fixture.url.path])
    }

    @Test("Closing while a scan is in flight stops it landing afterwards")
    func closingCancelsTheScanInFlight() async throws {
        let fixture = try ProjectFixture.modularProject()
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)

        state.openProject(at: fixture.url)
        let scan = state.currentScan
        state.closeProject()
        await scan?.value

        #expect(state.currentProject == nil)
        #expect(state.isLoading == false)
    }

    // MARK: - URL scheme

    /// A folder holding empty files of these names, removed when the test lets go of it.
    private func scratchFiles(_ names: [String]) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    private func compareURL(reference: URL, failure: URL) throws -> URL {
        var components = URLComponents()
        components.scheme = "gimdiff"
        components.host = "compare"
        components.queryItems = [
            URLQueryItem(name: "reference", value: reference.path),
            URLQueryItem(name: "failure", value: failure.path),
        ]
        return try #require(components.url)
    }

    @Test("A gimdiff://compare URL opens the comparison it names")
    func handlesACompareURL() throws {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)
        let folder = try scratchFiles(["a.png", "b.png"])
        defer { try? FileManager.default.removeItem(at: folder) }

        state.handle(try compareURL(
            reference: folder.appendingPathComponent("a.png"),
            failure: folder.appendingPathComponent("b.png")
        ))

        #expect(state.canvas.preview?.isComparison == true)
        #expect(state.canvas.preview?.title == "b")
    }

    @Test("A compare link naming a file that is not an image, or not there, opens nothing", arguments: [
        ("notes.txt", "b.png"),
        ("a.png", "missing.png"),
        ("folder.png", "b.png"),
    ])
    func refusesALinkToAnythingButImages(reference: String, failure: String) throws {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)
        let folder = try scratchFiles(["notes.txt", "a.png", "b.png"])
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder.png"), withIntermediateDirectories: true)

        state.handle(try compareURL(
            reference: folder.appendingPathComponent(reference),
            failure: folder.appendingPathComponent(failure)
        ))

        #expect(state.canvas.preview == nil)
        #expect(state.lastError != nil)
    }

    @Test("A gimdiff:// URL GimDiff cannot read is reported rather than ignored")
    func reportsAnUnusableURL() throws {
        let defaults = TemporaryDefaults()
        let state = state(defaults: defaults)
        let url = try #require(URL(string: "gimdiff://sing?about=snapshots"))

        state.handle(url)

        #expect(state.lastError != nil)

        state.dismissMessage()
        #expect(state.lastError == nil)
    }

    @Test("A path relative to the working tree is what git is asked for")
    func buildsRepositoryRelativePaths() {
        let root = URL(fileURLWithPath: "/Repo", isDirectory: true)

        #expect(
            AppState.relativePath(of: URL(fileURLWithPath: "/Repo/Snapshots/a.png"), under: root)
                == "Snapshots/a.png"
        )
        #expect(
            AppState.relativePath(of: URL(fileURLWithPath: "/Elsewhere/a.png"), under: root) == nil
        )
        #expect(AppState.relativePath(of: root, under: root) == nil)
    }
}
