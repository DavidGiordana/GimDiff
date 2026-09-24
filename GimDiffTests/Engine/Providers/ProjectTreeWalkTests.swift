//
//  ProjectTreeWalkTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// Covers the parts of discovery that depend on how the tree itself is shaped: symlinks,
/// document packages, and suites that sort their images into subfolders.
@Suite("Project tree walking")
struct ProjectTreeWalkTests {
    private let provider = SwiftModularProvider()
    private let filesystem = DefaultFilesystemService()

    // MARK: - Symlinks

    @Test("A project reached through a symlinked path is read, not reported empty")
    func readsThroughASymlinkedRoot() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/home.1.png")
        let alias = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffAlias-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.url)
        defer { try? FileManager.default.removeItem(at: alias) }

        let suites = try await provider.discoverSuites(in: alias, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
    }

    @Test("Git status still lands when the project is opened through a symlink")
    func annotatesThroughASymlinkedRoot() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        let changed = try fixture.write("Snapshots/HomeTests/home.1.png")
        let alias = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffAlias-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.url)
        defer { try? FileManager.default.removeItem(at: alias) }

        let suites = try await ProviderRegistry().discoverSuites(
            in: alias,
            filesystem: filesystem,
            gitService: StubGitService(repositoryRoot: fixture.url, statuses: [changed: .modified])
        )

        #expect(suites.first?.hasGitDiff == true)
    }

    /// Snapshots kept outside the project and linked in are reachable only if the walk
    /// follows the link. Their paths come back resolved, so what discovery matches on is
    /// the real folder's name, not the link's.
    @Test("A symlinked folder is followed into content outside the project")
    func followsASymlinkedFolder() async throws {
        let project = try ProjectFixture()
        let external = try ProjectFixture()
        try project.write("Package.swift", contents: "// marker")
        try external.write("Snapshots/HomeTests/home.1.png")
        try FileManager.default.createSymbolicLink(
            at: project.fileURL("Linked"),
            withDestinationURL: external.url
        )

        let suites = try await provider.discoverSuites(in: project.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
        #expect(suites.first?.snapshots.first?.fileURL.path.hasPrefix(external.url.path) == true)
    }

    /// Following symlinks is what makes a cycle reachable, so the guard has to hold for the
    /// walk to terminate at all.
    @Test("A symlink pointing back up the tree terminates instead of looping")
    func survivesASymlinkCycle() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/home.1.png")
        try FileManager.default.createSymbolicLink(
            at: fixture.fileURL("Snapshots/loop"),
            withDestinationURL: fixture.url
        )

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
        #expect(suites[0].snapshots.count == 1)
    }

    @Test("Two symlinks pointing at each other terminate as well")
    func survivesAMutualSymlinkCycle() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("A/Snapshots/HomeTests/home.1.png")
        try fixture.write("B/keep.txt", contents: "x")
        try FileManager.default.createSymbolicLink(
            at: fixture.fileURL("A/toB"),
            withDestinationURL: fixture.fileURL("B")
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.fileURL("B/toA"),
            withDestinationURL: fixture.fileURL("A")
        )

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
    }

    // MARK: - Packages

    @Test("An asset catalog is not mined for snapshots")
    func skipsAssetCatalogs() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/home.1.png")
        try fixture.write("Sources/Media.xcassets/Icon.imageset/icon.png")

        let contents = try provider.treeContents(
            under: fixture.url,
            filesystem: filesystem,
            ignoring: ProviderIgnoreFilter()
        )

        #expect(!contents.directories.contains { $0.lastPathComponent == "Icon.imageset" })
        #expect(!contents.files.contains { $0.lastPathComponent == "icon.png" })
    }

    @Test("An Xcode project bundle is not walked into")
    func skipsXcodeProjectBundles() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Demo.xcodeproj/project.pbxproj", contents: "// proj")
        try fixture.write("Snapshots/HomeTests/home.1.png")

        let contents = try provider.treeContents(
            under: fixture.url,
            filesystem: filesystem,
            ignoring: ProviderIgnoreFilter()
        )

        #expect(!contents.files.contains { $0.lastPathComponent == "project.pbxproj" })
    }

    @Test("An Xcode project still marks the folder as a project GimDiff understands")
    func stillClaimsProjectsWithBundles() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Demo.xcodeproj/project.pbxproj", contents: "// proj")

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem))
    }

    @Test("An asset catalog inside a suite folder contributes nothing")
    func assetCatalogInsideASuiteIsIgnored() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/home.1.png")
        try fixture.write("Snapshots/HomeTests/Media.xcassets/Icon.imageset/icon.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].snapshots.map(\.fileURL.lastPathComponent) == ["home.1.png"])
    }

    // MARK: - Nested suite folders

    @Test("Images sorted into device folders still belong to their suite")
    func collectsNestedDeviceFolders() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/iPhone/home.1.png")
        try fixture.write("Snapshots/HomeTests/iPad/home.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
        #expect(suites[0].snapshots.count == 2)
    }

    @Test("A nested snapshot is named for the folder that distinguishes it")
    func qualifiesNestedNames() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/iPhone/home.1.png")
        try fixture.write("Snapshots/HomeTests/iPad/dark/home.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].snapshots.map(\.name) == ["iPad/dark/home", "iPhone/home"])
        #expect(suites[0].snapshots.allSatisfy { $0.variantIndex == 1 })
    }

    @Test("A snapshot lying directly in its suite folder keeps its plain name")
    func leavesFlatNamesAlone() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/home.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].snapshots.map(\.name) == ["home"])
    }

    @Test("A nested suite keeps its own images rather than the one above it")
    func nearestSuiteWins() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/OuterTests/outer.1.png")
        try fixture.write("Snapshots/OuterTests/Snapshots/InnerTests/inner.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["InnerTests", "OuterTests"])
        #expect(suites.first { $0.name == "InnerTests" }?.snapshots.map(\.name) == ["inner"])
        #expect(suites.first { $0.name == "OuterTests" }?.snapshots.map(\.name) == ["outer"])
    }

    @Test("Device folders work in the Point-Free layout too")
    func collectsNestedFoldersInLegacyLayout() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Tests/ButtonTests.swift", contents: "// tests")
        try fixture.write("Tests/__Snapshots__/ButtonTests/iPhone/button.1.png")
        try fixture.write("Tests/__Snapshots__/ButtonTests/iPad/button.1.png")

        let suites = try await SwiftPointFreeLegacyProvider().discoverSuites(
            in: fixture.url,
            filesystem: filesystem
        )

        #expect(suites.map(\.name) == ["ButtonTests"])
        #expect(suites[0].snapshots.map(\.name) == ["iPad/button", "iPhone/button"])
    }
}
