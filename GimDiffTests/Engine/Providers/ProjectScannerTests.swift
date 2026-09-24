//
//  ProjectScannerTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Project scanning")
struct ProjectScannerTests {
    private func scanner(gitService: StubGitService = StubGitService()) -> ProjectScanner {
        ProjectScanner(filesystem: DefaultFilesystemService(), gitService: gitService)
    }

    @Test("Returns the project root, the working tree root, and the suites")
    func returnsABundle() async throws {
        let fixture = try ProjectFixture.modularProject()
        let bundle = try await scanner(gitService: StubGitService(repositoryRoot: fixture.url))
            .scan(projectRoot: fixture.url)

        #expect(bundle.rootURL == fixture.url)
        #expect(bundle.gitRootURL == fixture.url)
        #expect(bundle.suites.map(\.name) == ["SettingsViewTests", "UserProfileTests"])
    }

    @Test("A project outside a working tree has no Git root")
    func reportsNoGitRootOutsideARepository() async throws {
        let fixture = try ProjectFixture.modularProject()

        let bundle = try await scanner().scan(projectRoot: fixture.url)

        #expect(bundle.gitRootURL == nil)
        #expect(bundle.hasGitDiff == false)
    }

    @Test("Changed snapshots are counted across every suite")
    func countsChangesAcrossSuites() async throws {
        let fixture = try ProjectFixture.modularProject()
        let gitService = StubGitService(
            repositoryRoot: fixture.url,
            statuses: [
                fixture.fileURL("Snapshots/UserProfileTests/profile_header.1.png"): .modified,
                fixture.fileURL("Features/Settings/Tests/Snapshots/SettingsViewTests/settings.1.png"): .untracked,
            ]
        )

        let bundle = try await scanner(gitService: gitService).scan(projectRoot: fixture.url)

        #expect(bundle.hasGitDiff)
        #expect(bundle.modifiedSnapshotsCount == 2)
    }

    @Test("A cancelled scan stops instead of running to completion")
    func honoursCancellation() async throws {
        let fixture = try ProjectFixture.modularProject()
        let scanner = scanner()

        // Cancelled from inside the task, before the scan begins: cancelling from outside
        // would race the scheduler and could pass without the scan ever seeing the flag.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan(projectRoot: fixture.url)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("An unrecognised folder fails rather than reporting an empty project")
    func reportsUnrecognisedLayouts() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("README.md", contents: "# Notes")

        await #expect(throws: GimDiffError.unrecognisedProjectLayout(fixture.url)) {
            try await scanner().scan(projectRoot: fixture.url)
        }
    }
}
