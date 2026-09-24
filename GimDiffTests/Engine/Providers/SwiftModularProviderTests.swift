//
//  SwiftModularProviderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Modular Swift project discovery")
struct SwiftModularProviderTests {
    private let provider = SwiftModularProvider()
    private let filesystem = DefaultFilesystemService()

    @Test("Claims a project by its marker file", arguments: [
        "Package.swift", "Project.swift", "Workspace.swift",
    ])
    func claimsMarkedProjects(marker: String) async throws {
        let fixture = try ProjectFixture()
        try fixture.write(marker, contents: "// marker")

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem))
    }

    @Test("Claims a project holding an Xcode project file")
    func claimsXcodeProjects() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Demo.xcodeproj/project.pbxproj", contents: "// project")

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem))
    }

    @Test("Claims an unmarked folder that nonetheless holds a Snapshots directory")
    func claimsFoldersWithSnapshots() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Module/Snapshots/HomeTests/home.1.png")

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem))
    }

    @Test("Declines a folder with neither a marker nor snapshots")
    func declinesUnrelatedFolders() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("README.md", contents: "# Notes")

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem) == false)
    }

    @Test("Finds every suite, including ones nested inside feature modules")
    func discoversAllSuites() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])
        #expect(suites.allSatisfy { $0.providerId == provider.id })
    }

    @Test("A suite points at the folder its images live in")
    func recordsSnapshotsFolder() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)
        let profile = try #require(suites.first { $0.name == "UserProfileTests" })

        #expect(profile.snapshotsFolderURL == fixture.fileURL("Snapshots/UserProfileTests"))
        #expect(profile.id == fixture.fileURL("Snapshots/UserProfileTests").path)
    }

    @Test("Splits a trailing counter off the test method name")
    func decomposesSnapshotNames() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)
        let profile = try #require(suites.first { $0.name == "UserProfileTests" })

        #expect(profile.snapshots.map(\.name) == ["profile_footer", "profile_header", "profile_header"])
        #expect(profile.snapshots.map(\.variantIndex) == [nil, 1, 2])
    }

    @Test("Decomposition handles names with and without a counter", arguments: [
        ("summaryVC_skeleton.1.png", "summaryVC_skeleton", 1),
        ("profile_header.12.webp", "profile_header", 12),
        ("home.png", "home", nil),
        ("home.dark.2.jpg", "home.dark", 2),
        ("release.1.0.png", "release.1", 0),
    ] as [(String, String, Int?)])
    func decomposesFileNames(fileName: String, name: String, variantIndex: Int?) {
        let decomposed = provider.decomposeSnapshotName(URL(fileURLWithPath: "/tmp/\(fileName)"))

        #expect(decomposed.name == name)
        #expect(decomposed.variantIndex == variantIndex)
    }

    @Test("Files that are not images are left out")
    func ignoresNonImageFiles() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)
        let profile = try #require(suites.first { $0.name == "UserProfileTests" })

        #expect(!profile.snapshots.contains { $0.fileURL.lastPathComponent == "notes.txt" })
        #expect(profile.snapshots.count == 3)
    }

    @Test("Collects every extension the app can display", arguments: ["png", "jpg", "jpeg", "webp"])
    func collectsSupportedExtensions(pathExtension: String) async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/home.1.\(pathExtension)")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.first?.snapshots.count == 1)
    }

    @Test("Links each suite to the test file that records it")
    func linksSourceFiles() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(
            suites.first { $0.name == "UserProfileTests" }?.sourceCodeURL
                == fixture.fileURL("Tests/UserProfileTests.swift")
        )
        #expect(
            suites.first { $0.name == "SettingsViewTests" }?.sourceCodeURL
                == fixture.fileURL("Features/Settings/Tests/SettingsViewTests.swift")
        )
    }

    @Test("Resolves a source file by suite name on its own")
    func resolvesSourceFileByName() async throws {
        let fixture = try ProjectFixture.modularProject()

        let resolved = await provider.resolveSourceFile(
            for: "SettingsViewTests",
            in: fixture.url,
            filesystem: filesystem
        )

        #expect(resolved == fixture.fileURL("Features/Settings/Tests/SettingsViewTests.swift"))
    }

    @Test("A suite with no test file on disk is reported without one")
    func toleratesMissingSourceFile() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/OrphanTests/orphan.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["OrphanTests"])
        #expect(suites[0].sourceCodeURL == nil)
    }

    @Test("An empty suite folder produces no suite at all")
    func skipsEmptySuiteFolders() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/EmptyTests/README.md", contents: "# nothing here")

        #expect(try await provider.discoverSuites(in: fixture.url, filesystem: filesystem).isEmpty)
    }

    @Test("Items start unannotated, for the registry to fill in")
    func leavesGitStatusToTheRegistry() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.allSatisfy { $0.snapshots.allSatisfy { $0.gitStatus == .unmodified } })
        #expect(suites.allSatisfy { !$0.hasGitDiff })
    }
}
