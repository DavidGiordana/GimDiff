//
//  DerivedDataLocatorTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Locating test results in derived data")
struct DerivedDataLocatorTests {
    /// A derived data folder and a place to put projects, both thrown away with the test.
    private struct Fixture {
        let directory: TemporaryDirectory
        var derivedData: URL { directory.url.appendingPathComponent("DerivedData") }
        var projects: URL { directory.url.appendingPathComponent("Dev") }
        var locator: DerivedDataLocator { DerivedDataLocator(derivedDataURL: derivedData) }

        init() throws {
            directory = try TemporaryDirectory()
            try FileManager.default.createDirectory(at: derivedData, withIntermediateDirectories: true)
        }

        /// Records a workspace the way Xcode does, and returns its derived data folder.
        @discardableResult
        func addWorkspace(_ name: String, at workspacePath: String) throws -> URL {
            let folder = derivedData.appendingPathComponent(name)
            try write(["WorkspacePath": workspacePath], to: folder.appendingPathComponent("info.plist"))
            return folder
        }

        /// Records a run, returning its bundle.
        @discardableResult
        func addRun(_ name: String, in folder: URL, created: Date?) throws -> URL {
            let bundle = folder.appendingPathComponent("Logs/Test/\(name).xcresult")
            var info: [String: Any] = ["version": ["major": 3]]
            info["dateCreated"] = created
            try write(info, to: bundle.appendingPathComponent("Info.plist"))
            return bundle
        }

        private func write(_ propertyList: [String: Any], to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try PropertyListSerialization
                .data(fromPropertyList: propertyList, format: .xml, options: 0)
                .write(to: url)
        }
    }

    /// The temporary folder is reached through a symlink, and listing a folder answers with
    /// resolved paths, so the two spellings of one bundle are compared resolved.
    private static func isSamePlace(_ found: URL?, _ expected: URL) -> Bool {
        found?.resolvingSymlinksInPath().path == expected.resolvingSymlinksInPath().path
    }

    private static let earliest = Date(timeIntervalSince1970: 500)
    private static let earlier = Date(timeIntervalSince1970: 1_000)
    private static let later = Date(timeIntervalSince1970: 2_000)

    @Test("Finds the run of the workspace inside the project")
    func findsWorkspaceInsideProject() throws {
        let fixture = try Fixture()
        let app = fixture.projects.appendingPathComponent("App")
        let folder = try fixture.addWorkspace("App-abc", at: app.appendingPathComponent("App.xcodeproj").path)
        let bundle = try fixture.addRun("Test-1", in: folder, created: Self.earlier)
        let other = try fixture.addWorkspace(
            "Other-def",
            at: fixture.projects.appendingPathComponent("Other/Other.xcodeproj").path
        )
        try fixture.addRun("Test-1", in: other, created: Self.later)

        let found = fixture.locator.latestResultBundle(forProjectAt: app, gitRootURL: nil)

        #expect(Self.isSamePlace(found, bundle))
    }

    @Test("The newest run wins, by the date the bundle records")
    func prefersNewestRun() throws {
        let fixture = try Fixture()
        let app = fixture.projects.appendingPathComponent("App")
        let folder = try fixture.addWorkspace("App-abc", at: app.appendingPathComponent("App.xcodeproj").path)
        // Written newest first, so neither the listing order nor the volume's dates agree
        // with the recorded ones by accident.
        let newest = try fixture.addRun("Test-A", in: folder, created: Self.later)
        try fixture.addRun("Test-Z", in: folder, created: Self.earlier)

        let found = fixture.locator.latestResultBundle(forProjectAt: app, gitRootURL: nil)

        #expect(Self.isSamePlace(found, newest))
    }

    @Test("Every run of every workspace is listed, newest first")
    func listsEveryRunNewestFirst() throws {
        let fixture = try Fixture()
        let repository = fixture.projects.appendingPathComponent("Repo")
        let app = try fixture.addWorkspace("App-abc", at: repository.appendingPathComponent("App/App.xcworkspace").path)
        let kit = try fixture.addWorkspace("Kit-def", at: repository.appendingPathComponent("Kit/Kit.xcodeproj").path)
        let oldest = try fixture.addRun("Test-1", in: app, created: Self.earlier)
        let newest = try fixture.addRun("Test-2", in: kit, created: Self.later)
        let undated = try fixture.addRun("Test-3", in: app, created: nil)
        // A bundle that records no date is dated by the volume.
        try FileManager.default.setAttributes([.creationDate: Self.earliest], ofItemAtPath: undated.path)

        let found = fixture.locator.resultBundles(forProjectAt: repository, gitRootURL: nil)

        #expect(found.count == 3)
        #expect(Self.isSamePlace(found.first?.url, newest))
        #expect(Self.isSamePlace(found.dropFirst().first?.url, oldest))
        #expect(Self.isSamePlace(found.last?.url, undated))
        #expect(found.map(\.workspaceName) == ["Kit.xcodeproj", "App.xcworkspace", "App.xcworkspace"])
        #expect(found.first?.createdAt == Self.later)
    }

    @Test("The newest run is taken across every workspace of the project")
    func searchesEveryWorkspace() throws {
        let fixture = try Fixture()
        let repository = fixture.projects.appendingPathComponent("Repo")
        let app = try fixture.addWorkspace("App-abc", at: repository.appendingPathComponent("App/App.xcworkspace").path)
        let kit = try fixture.addWorkspace("Kit-def", at: repository.appendingPathComponent("Kit/Kit.xcodeproj").path)
        try fixture.addRun("Test-1", in: app, created: Self.earlier)
        let newest = try fixture.addRun("Test-1", in: kit, created: Self.later)

        let found = fixture.locator.latestResultBundle(forProjectAt: repository, gitRootURL: nil)

        #expect(Self.isSamePlace(found, newest))
    }

    @Test("A project opened on a snapshot folder finds the workspace that builds it")
    func findsWorkspaceAroundProject() throws {
        let fixture = try Fixture()
        let app = fixture.projects.appendingPathComponent("App")
        let folder = try fixture.addWorkspace("App-abc", at: app.appendingPathComponent("App.xcodeproj").path)
        let bundle = try fixture.addRun("Test-1", in: folder, created: Self.earlier)

        let found = fixture.locator.latestResultBundle(
            forProjectAt: app.appendingPathComponent("AppTests/__Snapshots__"),
            gitRootURL: nil
        )

        #expect(Self.isSamePlace(found, bundle))
    }

    @Test("A Swift package is built from its own folder, not from the one around it")
    func treatsPackageFolderAsWorkspace() throws {
        let fixture = try Fixture()
        let package = fixture.projects.appendingPathComponent("Package")
        let folder = try fixture.addWorkspace("Package-abc", at: package.path)
        let bundle = try fixture.addRun("Test-1", in: folder, created: Self.earlier)

        #expect(Self.isSamePlace(fixture.locator.latestResultBundle(forProjectAt: package, gitRootURL: nil), bundle))
        // A sibling is inside the folder holding the package, and that must not be enough.
        #expect(
            fixture.locator.latestResultBundle(
                forProjectAt: fixture.projects.appendingPathComponent("Sibling"),
                gitRootURL: nil
            ) == nil
        )
    }

    @Test("A workspace elsewhere in the same working tree counts")
    func findsWorkspaceInSameWorkingTree() throws {
        let fixture = try Fixture()
        let repository = fixture.projects.appendingPathComponent("Repo")
        let folder = try fixture.addWorkspace(
            "App-abc",
            at: repository.appendingPathComponent("App/App.xcodeproj").path
        )
        let bundle = try fixture.addRun("Test-1", in: folder, created: Self.earlier)
        let module = repository.appendingPathComponent("Modules/Cards/Tests/__Snapshots__")

        #expect(fixture.locator.latestResultBundle(forProjectAt: module, gitRootURL: nil) == nil)
        #expect(Self.isSamePlace(fixture.locator.latestResultBundle(forProjectAt: module, gitRootURL: repository), bundle))
    }

    @Test("A project whose name merely starts the same is not the project")
    func doesNotMatchOnPathPrefix() throws {
        let fixture = try Fixture()
        let folder = try fixture.addWorkspace(
            "AppStore-abc",
            at: fixture.projects.appendingPathComponent("AppStore/AppStore.xcodeproj").path
        )
        try fixture.addRun("Test-1", in: folder, created: Self.earlier)

        let found = fixture.locator.latestResultBundle(
            forProjectAt: fixture.projects.appendingPathComponent("App"),
            gitRootURL: nil
        )

        #expect(found == nil)
    }

    @Test("A workspace that was built but never tested has no run")
    func reportsNothingWithoutRuns() throws {
        let fixture = try Fixture()
        let app = fixture.projects.appendingPathComponent("App")
        try fixture.addWorkspace("App-abc", at: app.appendingPathComponent("App.xcodeproj").path)
        try fixture.directory.write("DerivedData/App-abc/Logs/Test/LogStoreManifest.plist", contents: "{}")

        #expect(fixture.locator.latestResultBundle(forProjectAt: app, gitRootURL: nil) == nil)
    }

    @Test("A derived data folder that does not exist has no run")
    func toleratesMissingDerivedData() throws {
        let directory = try TemporaryDirectory()
        let locator = DerivedDataLocator(derivedDataURL: directory.url.appendingPathComponent("Missing"))

        #expect(locator.latestResultBundle(forProjectAt: directory.url, gitRootURL: nil) == nil)
    }

    @Test("Only the result folders that exist are offered for watching")
    func offersExistingResultDirectories() throws {
        let fixture = try Fixture()
        let repository = fixture.projects.appendingPathComponent("Repo")
        let tested = try fixture.addWorkspace("App-abc", at: repository.appendingPathComponent("App/App.xcodeproj").path)
        try fixture.addRun("Test-1", in: tested, created: Self.earlier)
        try fixture.addWorkspace("Kit-def", at: repository.appendingPathComponent("Kit/Kit.xcodeproj").path)

        let directories = fixture.locator.resultDirectories(forProjectAt: repository, gitRootURL: nil)

        #expect(directories.map { $0.resolvingSymlinksInPath().path } == [
            tested.appendingPathComponent("Logs/Test").resolvingSymlinksInPath().path,
        ])
    }
}
