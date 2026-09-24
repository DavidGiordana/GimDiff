//
//  ConfigDrivenProviderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Configuration-driven discovery")
struct ConfigDrivenProviderTests {
    private let provider = ConfigDrivenProvider()
    private let filesystem = DefaultFilesystemService()

    @Test("Claims only a project that carries a configuration file")
    func claimsConfiguredProjects() async throws {
        let configured = try ProjectFixture()
        try configured.write(".gimdiffrc.json", contents: #"{"snapshotsDirectory": "Fixtures"}"#)
        let plain = try ProjectFixture()
        try plain.write("Package.swift", contents: "// marker")

        #expect(await provider.canHandle(projectRoot: configured.url, filesystem: filesystem))
        #expect(await provider.canHandle(projectRoot: plain.url, filesystem: filesystem) == false)
    }

    @Test("A configuration GimDiff cannot parse is treated as none at all")
    func declinesMalformedConfiguration() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: "{ not json")

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem) == false)
    }

    @Test("Reads suites out of the configured directory")
    func discoversFromConfiguredDirectory() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: #"{"snapshotsDirectory": "Tests/Fixtures/Images"}"#)
        try fixture.write("Tests/Fixtures/Images/HomeTests/home.1.png")
        try fixture.write("Tests/Fixtures/Images/AwayTests/away.1.png")
        try fixture.write("Snapshots/DecoyTests/decoy.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["AwayTests", "HomeTests"])
        #expect(suites.allSatisfy { $0.providerId == provider.id })
    }

    @Test("A bare folder name is looked for anywhere in the tree")
    func findsConfiguredFolderNameAtAnyDepth() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: #"{"snapshotsDirectory": "Recorded"}"#)
        try fixture.write("Features/Home/Recorded/HomeTests/home.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
    }

    @Test("The configured extensions replace the defaults")
    func honoursConfiguredExtensions() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: #"{"snapshotsDirectory": "Shots", "extensions": ["webp"]}"#)
        try fixture.write("Shots/HomeTests/home.1.webp")
        try fixture.write("Shots/HomeTests/home.2.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].snapshots.map(\.fileURL.lastPathComponent) == ["home.1.webp"])
    }

    @Test("Configured paths are pruned on top of the standard caches")
    func honoursConfiguredIgnores() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: #"{"ignoredPaths": ["Legacy"]}"#)
        try fixture.write("Modules/Current/Snapshots/HomeTests/home.1.png")
        try fixture.write("Modules/Legacy/Snapshots/OldTests/old.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
    }

    @Test("The test file pattern names each suite's source")
    func honoursTestFilePattern() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(
            ".gimdiffrc.json",
            contents: #"{"snapshotsDirectory": "Shots", "testFilePattern": "Sources/{suite}Spec.swift"}"#
        )
        try fixture.write("Shots/HomeTests/home.1.png")
        try fixture.write("Sources/HomeTestsSpec.swift", contents: "// spec")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].sourceCodeURL == fixture.fileURL("Sources/HomeTestsSpec.swift"))
    }

    @Test("A pattern pointing at nothing falls back to a search by name")
    func fallsBackWhenPatternMisses() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(
            ".gimdiffrc.json",
            contents: #"{"snapshotsDirectory": "Shots", "testFilePattern": "Nowhere/{suite}.swift"}"#
        )
        try fixture.write("Shots/HomeTests/home.1.png")
        try fixture.write("Tests/HomeTests.swift", contents: "// tests")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].sourceCodeURL == fixture.fileURL("Tests/HomeTests.swift"))
    }

    @Test("A flat folder of images is one suite named after the folder")
    func handlesFlatConfiguredFolder() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: #"{"snapshotsDirectory": "Shots"}"#)
        try fixture.write("Shots/home.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["Shots"])
        #expect(suites[0].snapshots.map(\.name) == ["home"])
    }

    @Test("An empty configuration falls back to the conventional Snapshots folder")
    func defaultsToTheConventionalFolder() async throws {
        let fixture = try ProjectFixture()
        try fixture.write(".gimdiffrc.json", contents: "{}")
        try fixture.write("Snapshots/HomeTests/home.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["HomeTests"])
    }
}
