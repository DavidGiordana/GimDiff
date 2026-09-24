//
//  SwiftPointFreeLegacyProviderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Point-Free snapshot discovery")
struct SwiftPointFreeLegacyProviderTests {
    private let provider = SwiftPointFreeLegacyProvider()
    private let filesystem = DefaultFilesystemService()

    @Test("Claims a project holding a __Snapshots__ folder")
    func claimsLegacyProjects() async throws {
        let fixture = try ProjectFixture.pointFreeProject()

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem))
    }

    @Test("Declines a project that uses the modular layout")
    func declinesModularProjects() async throws {
        let fixture = try ProjectFixture.modularProject()

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem) == false)
    }

    @Test("Finds the suite and its snapshots")
    func discoversSuites() async throws {
        let fixture = try ProjectFixture.pointFreeProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["ButtonTests"])
        #expect(suites[0].snapshots.map(\.name) == ["button", "button"])
        #expect(suites[0].snapshots.map(\.variantIndex) == [1, 2])
        #expect(suites[0].providerId == provider.id)
    }

    @Test("Links the suite to the test file beside its __Snapshots__ folder")
    func linksAdjacentTestFile() async throws {
        let fixture = try ProjectFixture.pointFreeProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].sourceCodeURL == fixture.fileURL("Tests/ButtonTests.swift"))
    }

    @Test("A lone test file beside a lone suite is linked even when the names differ")
    func linksSingleAdjacentTestFileBySuffix() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Tests/ButtonSnapshotTests.swift", contents: "// tests")
        try fixture.write("Tests/__Snapshots__/ButtonTests/button.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites[0].sourceCodeURL == fixture.fileURL("Tests/ButtonSnapshotTests.swift"))
    }

    /// Guessing is only safe while there is one candidate; with several suites beside
    /// several test files a wrong link is worse than none.
    @Test("Several suites beside one test file are left unlinked rather than mislinked")
    func refusesToGuessAcrossSeveralSuites() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Tests/ButtonTests.swift", contents: "// tests")
        try fixture.write("Tests/__Snapshots__/ButtonTests/button.1.png")
        try fixture.write("Tests/__Snapshots__/LabelTests/label.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["ButtonTests", "LabelTests"])
        #expect(suites[0].sourceCodeURL == fixture.fileURL("Tests/ButtonTests.swift"))
        #expect(suites[1].sourceCodeURL == nil)
    }

    @Test("Images dropped straight into __Snapshots__ form a suite named after their folder")
    func handlesFlatSnapshotFolders() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("ButtonTests/ButtonTests.swift", contents: "// tests")
        try fixture.write("ButtonTests/__Snapshots__/button.1.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["ButtonTests"])
        #expect(suites[0].snapshots.map(\.name) == ["button"])
        #expect(suites[0].sourceCodeURL == fixture.fileURL("ButtonTests/ButtonTests.swift"))
    }

    @Test("Resolves a source file by suite name")
    func resolvesSourceFileByName() async throws {
        let fixture = try ProjectFixture.pointFreeProject()

        let resolved = await provider.resolveSourceFile(
            for: "ButtonTests",
            in: fixture.url,
            filesystem: filesystem
        )

        #expect(resolved == fixture.fileURL("Tests/ButtonTests.swift"))
    }
}
