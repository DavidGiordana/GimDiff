//
//  PaparazziProviderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Paparazzi snapshot discovery")
struct PaparazziProviderTests {
    private let provider = PaparazziProvider()
    private let filesystem = DefaultFilesystemService()

    // MARK: - Claiming

    @Test("Claims a project holding a module's snapshots/images folder")
    func claimsPaparazziProjects() async throws {
        let fixture = try ProjectFixture.paparazziProject()

        #expect(await provider.canHandle(projectRoot: fixture.url, filesystem: filesystem))
    }

    @Test("Declines Swift layouts, and an images folder that is not under src/…/snapshots")
    func declinesOtherLayouts() async throws {
        let modular = try ProjectFixture.modularProject()
        let stray = try ProjectFixture()
        try stray.write("docs/snapshots/images/screen.png")

        #expect(await provider.canHandle(projectRoot: modular.url, filesystem: filesystem) == false)
        #expect(await provider.canHandle(projectRoot: stray.url, filesystem: filesystem) == false)
    }

    @Test("The registry picks Paparazzi for an Android project")
    func registryPicksPaparazzi() async throws {
        let fixture = try ProjectFixture.paparazziProject()

        let suites = try await ProviderRegistry().discoverSuites(
            in: fixture.url,
            filesystem: filesystem,
            gitService: StubGitService(),
            repositoryRoot: nil
        )

        #expect(Set(suites.map(\.providerId)) == [provider.id])
    }

    // MARK: - Grouping

    @Test("A suite per test class, each named after the class, sharing its module's folder")
    func groupsByClass() async throws {
        let fixture = try ProjectFixture.paparazziProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["ButtonTest", "LaunchViewTest", "LaunchViewTest"])
        #expect(suites.allSatisfy { $0.sharesFolder })
        #expect(Set(suites.map(\.id)).count == 3)

        let appImages = fixture.fileURL("app/src/test/snapshots/images")
        let app = suites.filter { $0.snapshotsFolderURL == appImages }
        #expect(app.map(\.name) == ["ButtonTest", "LaunchViewTest"])
        #expect(app[1].snapshots.map(\.name) == ["pixel5", "pixel5_dark_mode"])
        #expect(app[1].snapshots.allSatisfy { $0.variantIndex == nil })
    }

    @Test("Videos and a failing run's output under build are not listed")
    func listsRecordedImagesOnly() async throws {
        let fixture = try ProjectFixture.paparazziProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)
        let paths = suites.flatMap(\.snapshots).map(\.fileURL.path)

        #expect(paths.count == 4)
        #expect(paths.allSatisfy { $0.contains("/snapshots/images/") })
    }

    // MARK: - Sources

    @Test("Links each class to the test source its package names, in Kotlin or Java")
    func linksSourcesByPackage() async throws {
        let fixture = try ProjectFixture.paparazziProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)
        let sources = Set(suites.filter { $0.name == "LaunchViewTest" }.compactMap(\.sourceCodeURL))

        #expect(sources == [
            fixture.fileURL("app/src/test/kotlin/com/example/LaunchViewTest.kt"),
            fixture.fileURL("feature/src/test/java/com/example/feature/LaunchViewTest.java"),
        ])
    }

    @Test("A production class of the same name is never offered as the test file")
    func ignoresProductionSources() async throws {
        let fixture = try ProjectFixture.paparazziProject()

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)
        let button = try #require(suites.first { $0.name == "ButtonTest" })

        #expect(button.sourceCodeURL == nil)
        #expect(await provider.resolveSourceFile(for: "ButtonTest", in: fixture.url, filesystem: filesystem) == nil)
    }

    @Test("A nested class is linked to the file of the class around it")
    func linksNestedClasses() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("app/src/test/kotlin/com/example/ScreensTest.kt", contents: "// tests")
        try fixture.write("app/src/test/snapshots/images/com.example_ScreensTest$Home_idle.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["ScreensTest$Home"])
        #expect(suites[0].sourceCodeURL == fixture.fileURL("app/src/test/kotlin/com/example/ScreensTest.kt"))
    }

    // MARK: - Names

    @Test("A declared class settles where an underscored package or class name ends")
    func splitsUnderscoresAgainstSources() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("app/src/test/kotlin/com/my_app/Big_ButtonTest.kt", contents: "// tests")
        try fixture.write("app/src/test/snapshots/images/com.my_app_Big_ButtonTest_on_dark.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["Big_ButtonTest"])
        #expect(suites[0].snapshots.map(\.name) == ["on_dark"])
        #expect(suites[0].sourceCodeURL != nil)
    }

    @Test("Without sources, the first two separators split package, class, and snapshot")
    func splitsWithoutSources() {
        let recorded = PaparazziProvider.recordedName(of: "com.example_LaunchViewTest_pixel5_dark")

        #expect(recorded == PaparazziProvider.RecordedName(
            packageName: "com.example",
            className: "LaunchViewTest",
            snapshotName: "pixel5_dark"
        ))
        #expect(PaparazziProvider.recordedName(of: "launch") == nil)
        #expect(PaparazziProvider.recordedName(of: "com.example_LaunchViewTest") == nil)
    }

    @Test("An image Paparazzi could not have named is listed under its module")
    func keepsUnparsableNames() async throws {
        let fixture = try ProjectFixture()
        try fixture.write("app/src/test/snapshots/images/hand-made.png")

        let suites = try await provider.discoverSuites(in: fixture.url, filesystem: filesystem)

        #expect(suites.map(\.name) == ["app"])
        #expect(suites[0].snapshots.map(\.name) == ["hand-made"])
    }
}
