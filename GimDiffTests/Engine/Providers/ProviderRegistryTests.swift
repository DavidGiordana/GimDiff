//
//  ProviderRegistryTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Provider registry")
struct ProviderRegistryTests {
    private let filesystem = DefaultFilesystemService()

    @Test("Ships the four providers in priority order")
    func defaultOrder() {
        #expect(ProviderRegistry().providers.map(\.id) == [
            "config", "swift.modular", "swift.pointfree", "android.paparazzi",
        ])
    }

    @Test("A configured project is read by the configuration provider")
    func configurationWinsOverConvention() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write(".gimdiffrc.json", contents: #"{"snapshotsDirectory": "Shots"}"#)
        try fixture.write("Shots/HomeTests/home.1.png")

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: filesystem,
            gitService: StubGitService()
        )

        #expect(suites.map(\.providerId) == ["config"])
    }

    /// A marker file is enough for the modular provider to claim a project, so a package
    /// laid out the old way would be claimed and reported empty without the fall-through.
    @Test("A package using the legacy layout still reaches the legacy provider")
    func fallsThroughToTheLegacyProvider() async throws {
        let fixture = try ProjectFixture.pointFreeProject()

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: filesystem,
            gitService: StubGitService()
        )

        #expect(suites.map(\.name) == ["ButtonTests"])
        #expect(suites.map(\.providerId) == ["swift.pointfree"])
    }

    @Test("A modular project is read by the modular provider")
    func readsModularProjects() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: filesystem,
            gitService: StubGitService()
        )

        #expect(suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])
        #expect(suites.allSatisfy { $0.providerId == "swift.modular" })
    }

    @Test("A folder no provider recognises is reported as such")
    func reportsUnrecognisedLayouts() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("README.md", contents: "# Notes")

        await #expect(throws: GimDiffError.unrecognisedProjectLayout(fixture.url)) {
            try await ProviderRegistry().discoverSuites(
                in: fixture.url,
                filesystem: filesystem,
                gitService: StubGitService()
            )
        }
    }

    @Test("A claimed project that genuinely holds nothing is empty, not an error")
    func claimedButEmptyProjectsAreNotErrors() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: filesystem,
            gitService: StubGitService()
        )

        #expect(suites.isEmpty)
    }

    @Test("Snapshots outside a working tree are reported without status")
    func worksOutsideARepository() async throws {
        let fixture = try ProjectFixture.modularProject()

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: filesystem,
            gitService: StubGitService(repositoryRoot: nil)
        )

        #expect(suites.count == 2)
        #expect(suites.allSatisfy { !$0.hasGitDiff })
    }
}
