//
//  ProjectChangeClassifierTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Reading file events against a project")
@MainActor
struct ProjectChangeClassifierTests {
    private let root = AppStateFixture.root
    private let project = AppStateFixture.twoSuites()
    private let filesystem = MockFilesystemService()

    /// The mock volume starts with every snapshot and test source the bundle names.
    init() {
        for suite in project.suites {
            if let source = suite.sourceCodeURL {
                filesystem.stub(source, contents: "// tests")
            }
            for snapshot in suite.snapshots {
                filesystem.stub(snapshot.fileURL, contents: "png")
            }
        }
    }

    private func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    private func classify(_ events: ProjectFileEvent..., in project: ProjectBundle? = nil) -> ProjectChange {
        ProjectChangeClassifier(filesystem: filesystem).classify(events, in: project ?? self.project)
    }

    private func file(_ relativePath: String) -> ProjectFileEvent {
        ProjectFileEvent(url: url(relativePath))
    }

    private func folder(_ relativePath: String) -> ProjectFileEvent {
        ProjectFileEvent(url: url(relativePath), isDirectory: true)
    }

    // MARK: - Snapshots

    @Test("A snapshot rewritten in place is named, and needs no rescan")
    func rewrittenSnapshot() {
        let change = classify(file("Snapshots/AlphaTests/header.png"))

        #expect(change.rewrittenSnapshotPaths == [url("Snapshots/AlphaTests/header.png").path])
        #expect(change.needsGitStatus)
        #expect(change.needsRescan == false)
    }

    @Test("A snapshot that is gone makes the tree stale")
    func removedSnapshot() throws {
        try filesystem.removeItem(at: url("Snapshots/AlphaTests/header.png"))

        let change = classify(file("Snapshots/AlphaTests/header.png"))

        #expect(change.needsRescan)
        #expect(change.rewrittenSnapshotPaths.isEmpty)
    }

    @Test("An image the project did not have makes the tree stale")
    func newSnapshot() {
        filesystem.stub(url("Snapshots/AlphaTests/banner.png"), contents: "png")

        #expect(classify(file("Snapshots/AlphaTests/banner.png")).needsRescan)
    }

    @Test("A scratch image that has already been renamed away is not news")
    func vanishedScratchImage() {
        #expect(classify(file("Snapshots/AlphaTests/.header.png.tmp.png")).isEmpty)
    }

    @Test("A new file in a format only this project's snapshots use is still noticed")
    func projectSpecificExtension() {
        let folder = url("Snapshots/GammaTests")
        let bundle = ProjectBundle(rootURL: root, suites: [
            SnapshotSuite(
                name: "GammaTests",
                snapshotsFolderURL: folder,
                snapshots: [SnapshotItem(name: "a", fileURL: folder.appendingPathComponent("a.bmp"))],
                providerId: "config"
            ),
        ])
        filesystem.stub(folder.appendingPathComponent("b.bmp"), contents: "bmp")

        #expect(classify(file("Snapshots/GammaTests/b.bmp"), in: bundle).needsRescan)
    }

    // MARK: - Folders

    @Test("A folder that came, went, or moved makes the tree stale")
    func folderEvent() {
        #expect(classify(folder("Snapshots/AlphaTests")).needsRescan)
    }

    @Test("The root itself is how a watcher says it lost track")
    func rootEvent() {
        #expect(classify(ProjectFileEvent(url: root, isDirectory: true)).needsRescan)
    }

    // MARK: - Noise

    @Test(
        "What a scan would never walk to is dropped on its path alone",
        arguments: [
            ".build/debug/Snapshots/CachedTests/cached.png",
            "DerivedData/Build/Products/icon.png",
            "Features/Home/node_modules/pkg/logo.png",
            "Resources/Assets.xcassets/AppIcon.appiconset/icon.png",
            "Demo.xcodeproj/project.pbxproj",
        ]
    )
    func prunedPaths(relativePath: String) {
        filesystem.stub(url(relativePath), contents: "png")

        #expect(classify(file(relativePath)).isEmpty)
        #expect(classify(folder((relativePath as NSString).deletingLastPathComponent)).isEmpty)
    }

    @Test("Files that are neither snapshots nor test sources are dropped")
    func unrelatedFiles() {
        filesystem.stub(url("README.md"), contents: "# Demo")
        filesystem.stub(url("Snapshots/AlphaTests/.DS_Store"), contents: "")

        #expect(classify(file("README.md"), file("Snapshots/AlphaTests/.DS_Store")).isEmpty)
    }

    @Test("Paths outside the project are dropped")
    func outsideTheProject() {
        let elsewhere = URL(fileURLWithPath: "/Projects/DemoTwo/Snapshots/AlphaTests/header.png")
        filesystem.stub(elsewhere, contents: "png")

        #expect(classify(ProjectFileEvent(url: elsewhere)).isEmpty)
    }

    // MARK: - Test sources

    @Test("Saving a test file says nothing about its snapshots")
    func savedSource() {
        filesystem.stub(url("Tests/OtherTests.swift"), contents: "// other")

        #expect(classify(file("Tests/AlphaTests.swift"), file("Tests/OtherTests.swift")).isEmpty)
    }

    @Test("A test source that went away makes the tree stale")
    func removedSource() throws {
        try filesystem.removeItem(at: url("Tests/AlphaTests.swift"))

        #expect(classify(file("Tests/AlphaTests.swift")).needsRescan)
    }

    @Test("A source arriving under the name of a suite that had none makes the tree stale")
    func sourceForAnOrphanedSuite() {
        filesystem.stub(url("Tests/BetaTests.swift"), contents: "// beta")

        #expect(classify(file("Tests/BetaTests.swift")).needsRescan)
    }

    @Test("The project's own configuration makes the tree stale, but only at the root")
    func configurationFile() {
        #expect(classify(file(".gimdiffrc.json")).needsRescan)
        #expect(classify(file("Tests/.gimdiffrc.json")).isEmpty)
    }

    // MARK: - Git

    @Test(
        "A commit or a checkout asks for the status alone",
        arguments: ["HEAD", "packed-refs", "refs/heads/main", "refs/heads/feature/tree"]
    )
    func headMoved(relativePath: String) {
        let change = classify(file(".git/\(relativePath)"))

        #expect(change == ProjectChange(needsGitStatus: true))
    }

    @Test(
        "The rest of the Git directory is dropped, the index included",
        arguments: ["index", "index.lock", "HEAD.lock", "objects/ab/cdef", "refs/remotes/origin/main", "logs/HEAD"]
    )
    func gitNoise(relativePath: String) {
        #expect(classify(file(".git/\(relativePath)")).isEmpty)
    }

    @Test("The Git directory is recognised above a project opened below the top of its repository")
    func gitDirectoryAboveTheProject() {
        let repository = root.deletingLastPathComponent()
        let bundle = ProjectBundle(rootURL: root, gitRootURL: repository, suites: project.suites)
        let head = repository.appendingPathComponent(".git/HEAD")

        #expect(classify(ProjectFileEvent(url: head), in: bundle) == ProjectChange(needsGitStatus: true))
    }

    // MARK: - Batches

    @Test("A batch asks for everything any of its events does")
    func mixedBatch() {
        filesystem.stub(url("Snapshots/AlphaTests/banner.png"), contents: "png")

        let change = classify(
            file("Snapshots/AlphaTests/footer.png"),
            file("Snapshots/AlphaTests/banner.png"),
            file(".build/noise.png")
        )

        #expect(change == ProjectChange(
            rewrittenSnapshotPaths: [url("Snapshots/AlphaTests/footer.png").path],
            needsGitStatus: true,
            needsRescan: true
        ))
    }

    @Test("Changes accumulate without losing what the earlier ones asked for")
    func union() {
        var pending = ProjectChange(rewrittenSnapshotPaths: ["/a.png"], needsGitStatus: true)
        pending.formUnion(ProjectChange(rewrittenSnapshotPaths: ["/b.png"], needsRescan: true))

        #expect(pending == ProjectChange(
            rewrittenSnapshotPaths: ["/a.png", "/b.png"],
            needsGitStatus: true,
            needsRescan: true
        ))
        #expect(ProjectChange().isEmpty)
    }
}
