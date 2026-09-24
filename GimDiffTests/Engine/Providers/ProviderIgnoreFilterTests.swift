//
//  ProviderIgnoreFilterTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Provider ignore rules")
struct ProviderIgnoreFilterTests {
    private let filter = ProviderIgnoreFilter()

    @Test("Prunes every build and cache directory by name", arguments: [
        "Tuist", ".build", ".swiftpm", "Derived", "DerivedData",
        "build", "Pods", "Carthage", "node_modules", "fastlane", ".git",
    ])
    func prunesCacheDirectories(name: String) {
        #expect(filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/Features/\(name)")))
    }

    @Test("Leaves ordinary project folders alone", arguments: [
        "Snapshots", "Tests", "Sources", "__Snapshots__", "Features",
    ])
    func keepsProjectDirectories(name: String) {
        #expect(!filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/\(name)")))
    }

    @Test("A name is pruned wherever it appears, not only at the root")
    func prunesAtAnyDepth() {
        #expect(filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/a/b/c/node_modules")))
    }

    @Test("A configured bare name joins the pruned set")
    func addsConfiguredName() {
        let filter = ProviderIgnoreFilter(additionalIgnoredPaths: ["Legacy"])

        #expect(filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/Modules/Legacy")))
        #expect(filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/Pods")))
    }

    @Test("A configured multi-component path is pruned only where it matches")
    func addsConfiguredPath() {
        let filter = ProviderIgnoreFilter(additionalIgnoredPaths: ["Modules/Legacy"])

        #expect(filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/Modules/Legacy")))
        #expect(!filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/Other/Legacy")))
    }

    @Test("Blank configuration entries are discarded rather than pruning everything")
    func ignoresBlankEntries() {
        let filter = ProviderIgnoreFilter(additionalIgnoredPaths: ["", "  ", "/"])

        #expect(!filter.shouldIgnore(url: URL(fileURLWithPath: "/repo/Snapshots")))
    }

    @Test("Discovery never walks into a cache, even one holding a plausible suite")
    func discoveryPrunesCachedSnapshots() async throws {
        let fixture = try ProjectFixture.modularProject()
        let provider = SwiftModularProvider()

        let suites = try await provider.discoverSuites(
            in: fixture.url,
            filesystem: DefaultFilesystemService()
        )

        // Every pruned folder in the fixture holds a CachedTests suite; finding one here
        // would mean the walk descended into Tuist, .build, Pods, or DerivedData.
        #expect(!suites.contains { $0.name == "CachedTests" })
        #expect(suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])

        let discoveredPaths = suites.flatMap { $0.snapshots.map(\.fileURL.path) }
        #expect(!discoveredPaths.contains { $0.contains("/Tuist/") })
        #expect(!discoveredPaths.contains { $0.contains("/.build/") })
        #expect(!discoveredPaths.contains { $0.contains("/Pods/") })
        #expect(!discoveredPaths.contains { $0.contains("/DerivedData/") })
    }

    @Test("A cache nested inside a module is pruned just like one at the project root")
    func prunesNestedCaches() async throws {
        let fixture = try ProjectFixture.modularProject()
        let provider = SwiftModularProvider()

        let suites = try await provider.discoverSuites(
            in: fixture.url,
            filesystem: DefaultFilesystemService()
        )
        let discoveredPaths = suites.flatMap { $0.snapshots.map(\.fileURL.path) }

        // These sit several levels down, inside Features/, not at the root.
        #expect(!discoveredPaths.contains { $0.contains("/Tests/DerivedData/") })
        #expect(!discoveredPaths.contains { $0.contains("/Tests/Derived/") })
        #expect(!discoveredPaths.contains { $0.contains("/node_modules/") })
        #expect(suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])
    }

    /// Pruning is about not wandering into caches while looking for a project; it is not a
    /// refusal to read one. Opening a folder is an explicit instruction to look inside it.
    @Test("A folder opened directly is scanned even when its name is normally pruned")
    func scansAnExplicitlyOpenedCacheFolder() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("DerivedData/Package.swift", contents: "// marker")
        try fixture.write("DerivedData/Snapshots/HomeTests/home.1.png")

        let suites = try await SwiftModularProvider().discoverSuites(
            in: fixture.fileURL("DerivedData"),
            filesystem: DefaultFilesystemService()
        )

        #expect(suites.map(\.name) == ["HomeTests"])
    }

    @Test("A file that happens to share a pruned name is still collected")
    func prunesDirectoriesRatherThanFiles() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("Package.swift", contents: "// marker")
        try fixture.write("Snapshots/HomeTests/build.png")
        try fixture.write("Snapshots/HomeTests/DerivedData.png")

        let suites = try await SwiftModularProvider().discoverSuites(
            in: fixture.url,
            filesystem: DefaultFilesystemService()
        )

        #expect(suites[0].snapshots.map(\.name) == ["DerivedData", "build"])
    }

    @Test("A Swift file inside a cache is never offered as a suite's source")
    func discoveryPrunesCachedSourceFiles() async throws {
        let fixture = try ProjectFixture.modularProject()
        let provider = SwiftModularProvider()

        let resolved = await provider.resolveSourceFile(
            for: "CachedTests",
            in: fixture.url,
            filesystem: DefaultFilesystemService()
        )

        #expect(resolved == nil)
    }
}
