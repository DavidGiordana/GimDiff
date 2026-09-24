//
//  GitBubblingTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Git status bubbling")
struct GitBubblingTests {
    private let folder = URL(fileURLWithPath: "/repo/Snapshots/HomeTests")

    private func suite(fileNames: [String]) -> SnapshotSuite {
        SnapshotSuite(
            name: "HomeTests",
            snapshotsFolderURL: folder,
            snapshots: fileNames.map {
                SnapshotItem(name: ($0 as NSString).deletingPathExtension, fileURL: folder.appendingPathComponent($0))
            },
            providerId: "test"
        )
    }

    @Test("A clean suite reports no difference")
    func cleanSuiteHasNoDiff() {
        let annotated = ProviderRegistry.annotate([suite(fileNames: ["home.png", "away.png"])], with: [:])

        #expect(annotated[0].hasGitDiff == false)
        #expect(annotated[0].modifiedSnapshotsCount == 0)
    }

    @Test("One modified child marks the whole suite as changed")
    func oneModifiedChildBubblesUp() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png", "away.png"])],
            with: [folder.appendingPathComponent("home.png"): .modified]
        )

        #expect(annotated[0].hasGitDiff)
        #expect(annotated[0].modifiedSnapshotsCount == 1)
        #expect(annotated[0].snapshots.map(\.gitStatus) == [.modified, .unmodified])
    }

    @Test("An untracked child counts as a difference too")
    func untrackedChildBubblesUp() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png"])],
            with: [folder.appendingPathComponent("home.png"): .untracked]
        )

        #expect(annotated[0].hasGitDiff)
    }

    @Test("A deleted child is recorded but is not something to review")
    func deletedChildIsNotADiff() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png"])],
            with: [folder.appendingPathComponent("home.png"): .deleted]
        )

        #expect(annotated[0].snapshots[0].gitStatus == .deleted)
        #expect(annotated[0].hasGitDiff == false)
    }

    @Test("A file Git says nothing about stays unmodified")
    func unreportedFilesStayClean() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png"])],
            with: [URL(fileURLWithPath: "/repo/elsewhere/other.png"): .modified]
        )

        #expect(annotated[0].snapshots[0].gitStatus == .unmodified)
        #expect(annotated[0].hasGitDiff == false)
    }

    /// `git status -s` collapses a brand-new folder into a single `?? Dir/` record rather
    /// than listing the files inside it, so inheritance is the only way those files are
    /// ever marked.
    @Test("Files inherit the status of a folder Git reported as a whole")
    func filesInheritFromACollapsedFolder() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png", "away.png"])],
            with: [URL(fileURLWithPath: "/repo/Snapshots"): .untracked]
        )

        #expect(annotated[0].snapshots.allSatisfy { $0.gitStatus == .untracked })
        #expect(annotated[0].hasGitDiff)
        #expect(annotated[0].modifiedSnapshotsCount == 2)
    }

    @Test("A file's own record wins over the folder it sits in")
    func exactRecordBeatsInheritance() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png", "away.png"])],
            with: [
                URL(fileURLWithPath: "/repo/Snapshots"): .untracked,
                folder.appendingPathComponent("home.png"): .modified,
            ]
        )

        let statuses = Dictionary(
            uniqueKeysWithValues: annotated[0].snapshots.map { ($0.fileURL.lastPathComponent, $0.gitStatus) }
        )
        #expect(statuses["home.png"] == .modified)
        #expect(statuses["away.png"] == .untracked)
    }

    @Test("Bubbling carries on up to the project bundle")
    func bundleReportsTheProjectAsChanged() {
        let annotated = ProviderRegistry.annotate(
            [suite(fileNames: ["home.png"])],
            with: [folder.appendingPathComponent("home.png"): .modified]
        )
        let bundle = ProjectBundle(
            rootURL: URL(fileURLWithPath: "/repo"),
            gitRootURL: URL(fileURLWithPath: "/repo"),
            suites: annotated
        )

        #expect(bundle.hasGitDiff)
        #expect(bundle.modifiedSnapshotsCount == 1)
    }

    @Test("Discovery through the registry annotates what it finds")
    func registryAnnotatesDiscoveredSuites() async throws {
        let fixture = try ProjectFixture.modularProject()
        let changed = fixture.fileURL("Snapshots/UserProfileTests/profile_header.1.png")
        let gitService = StubGitService(repositoryRoot: fixture.url, statuses: [changed: .modified])

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: DefaultFilesystemService(),
            gitService: gitService
        )
        let profile = try #require(suites.first { $0.name == "UserProfileTests" })

        #expect(profile.hasGitDiff)
        #expect(profile.modifiedSnapshotsCount == 1)
        #expect(suites.first { $0.name == "SettingsViewTests" }?.hasGitDiff == false)
    }

    @Test("Snapshots still load when the working tree cannot be read")
    func survivesAFailingGitStatus() async throws {
        let fixture = try ProjectFixture.modularProject()
        let gitService = StubGitService(repositoryRoot: fixture.url, statusFails: true)

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: DefaultFilesystemService(),
            gitService: gitService
        )

        #expect(suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])
        #expect(suites.allSatisfy { !$0.hasGitDiff })
    }
}
