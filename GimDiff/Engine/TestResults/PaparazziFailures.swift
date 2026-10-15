//
//  PaparazziFailures.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Where Paparazzi leaves what a verify task failed on, relative to a module.
///
/// ```
/// app/build/paparazzi/failures/debug/
///     com.example_LaunchViewTest_pixel5.png        what the test rendered
///     delta-com.example_LaunchViewTest_pixel5.png  recorded | difference | rendered
/// ```
///
/// Paparazzi 1.3 writes straight into `failures`, 2.0 into a folder per variant. The
/// rendering beside each delta is written from 1.3.2 on; older versions write the delta
/// alone, which shows the difference but holds no image to accept, and are not read.
enum PaparazziFailureLayout {
    /// The folder a module's Paparazzi tasks write their output into.
    static let outputPath = "build/paparazzi"
    /// The folder a verify task writes its failures into, emptied when the task starts.
    static let failuresPath = "build/paparazzi/failures"
    /// Prefix of the composite Paparazzi draws of each failure.
    static let deltaPrefix = "delta-"
    /// How a run made of Paparazzi's failures is named beside Xcode's in the run picker.
    static let runName = "Paparazzi"

    /// The module whose snapshots fill an images folder: the folder above `src`.
    static func module(ofImagesFolder folder: URL) -> URL {
        folder
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The module a failure folder belongs to: the folder holding its `build`.
    static func module(ofFailureFolder folder: URL) -> URL? {
        let components = folder.standardizedFileURL.pathComponents
        guard let buildIndex = components.lastIndex(of: "build"), buildIndex > 0 else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[..<buildIndex])), isDirectory: true)
    }

    /// The renderings in one failure folder, sorted: every image but the deltas.
    static func renderings(in folder: URL, filesystem: any FilesystemService) -> [URL] {
        ((try? filesystem.contentsOfDirectory(at: folder)) ?? [])
            .filter { !filesystem.isDirectory(at: $0) }
            .filter { ImageFormat(url: $0).isRecognized && !$0.lastPathComponent.hasPrefix(deltaPrefix) }
            .sorted { $0.path < $1.path }
    }
}

/// Finds the failures Paparazzi's verify tasks left in the open project's modules.
///
/// They are one run, whatever the number of modules and variants: a verify is started for
/// the whole project far more often than for one module, and a run per folder would leave
/// all but one of them behind the run picker.
struct PaparazziFailureLocator: TestResultLocating {
    private let filesystem: any FilesystemService

    init(filesystem: any FilesystemService) {
        self.filesystem = filesystem
    }

    /// Nothing without the project's suites, which are what say where its modules are.
    func resultBundles(forProjectAt rootURL: URL, gitRootURL: URL?) -> [TestRunBundle] { [] }

    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] { [] }

    func resultBundles(for project: ProjectBundle) -> [TestRunBundle] {
        let folders = failureFolders(of: project)
        guard !folders.isEmpty else { return [] }

        let newest = folders
            .flatMap { PaparazziFailureLayout.renderings(in: $0, filesystem: filesystem) }
            .compactMap(filesystem.modificationDate(at:))
            .max()
        return [
            TestRunBundle(
                url: project.rootURL,
                createdAt: newest,
                workspaceName: PaparazziFailureLayout.runName,
                failureFolders: folders
            ),
        ]
    }

    /// Each module's `build/paparazzi`, or its `build` until a verify has made that: the
    /// failures folder itself is deleted and made again by every verify.
    func resultDirectories(for project: ProjectBundle) -> [URL] {
        modules(of: project).compactMap { module in
            let output = module.appendingPathComponent(PaparazziFailureLayout.outputPath, isDirectory: true)
            if filesystem.isDirectory(at: output) { return output }
            let build = module.appendingPathComponent("build", isDirectory: true)
            return filesystem.isDirectory(at: build) ? build : nil
        }
    }

    /// The failure folders holding at least one rendering: each module's `failures`, and
    /// each variant's folder inside it.
    func failureFolders(of project: ProjectBundle) -> [URL] {
        modules(of: project).flatMap { module -> [URL] in
            let failures = module.appendingPathComponent(PaparazziFailureLayout.failuresPath, isDirectory: true)
            guard filesystem.isDirectory(at: failures) else { return [] }
            let variants = ((try? filesystem.contentsOfDirectory(at: failures)) ?? [])
                .filter(filesystem.isDirectory(at:))
                .sorted { $0.path < $1.path }
            return ([failures] + variants).filter {
                !PaparazziFailureLayout.renderings(in: $0, filesystem: filesystem).isEmpty
            }
        }
    }

    /// The modules whose snapshots Paparazzi recorded, from the suites already discovered.
    private func modules(of project: ProjectBundle) -> [URL] {
        let providerID = PaparazziProvider().id
        let modules = project.suites
            .filter { $0.providerId == providerID }
            .map { PaparazziFailureLayout.module(ofImagesFolder: $0.snapshotsFolderURL).standardizedFileURL }
        return Array(Set(modules)).sorted { $0.path < $1.path }
    }
}

/// Reads Paparazzi's failure folders as a test run.
///
/// Each rendering becomes a failed step holding a copy of the snapshot it was compared with
/// and a copy of the rendering, which is exactly what ``TestRunMatcher`` pairs: the copy is
/// the snapshot byte for byte, so the rendering is its candidate. A rendering whose snapshot
/// was never recorded has nothing to pair with and is listed on its own.
///
/// Both are copied into a scratch folder, because the next verify deletes the failures
/// while the canvas may still be showing one.
struct PaparazziFailureReader: TestResultReading {
    private let filesystem: any FilesystemService
    private let temporaryRoot: URL

    /// - Parameter temporaryRoot: Folder each report creates its own scratch folder in.
    init(
        filesystem: any FilesystemService,
        temporaryRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("com.davidgiordana.GimDiff.TestRuns", isDirectory: true)
    ) {
        self.filesystem = filesystem
        self.temporaryRoot = temporaryRoot
    }

    /// Reads one failures folder, and the variant folders inside it.
    func report(forBundleAt bundle: URL) async throws -> TestRunReport {
        let folder = bundle.standardizedFileURL
        let variants = ((try? filesystem.contentsOfDirectory(at: folder)) ?? [])
            .filter(filesystem.isDirectory(at:))
            .sorted { $0.path < $1.path }
        return try await report(of: [folder] + variants, bundleURL: folder)
    }

    func report(for bundle: TestRunBundle) async throws -> TestRunReport {
        guard !bundle.failureFolders.isEmpty else { return try await report(forBundleAt: bundle.url) }
        return try await report(of: bundle.failureFolders, bundleURL: bundle.url)
    }

    private func report(of folders: [URL], bundleURL: URL) async throws -> TestRunReport {
        let scratch = temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderings = folders.flatMap { folder in
            PaparazziFailureLayout.renderings(in: folder, filesystem: filesystem).map { (folder, $0) }
        }

        do {
            var failures: [TestRunFailure] = []
            for (index, (folder, rendering)) in renderings.enumerated() {
                try Task.checkCancellation()
                failures.append(
                    try failure(
                        rendered: rendering,
                        in: folder,
                        copyingInto: scratch.appendingPathComponent(String(index), isDirectory: true)
                    )
                )
            }
            return TestRunReport(bundleURL: bundleURL, scratchDirectory: scratch, startedAt: nil, failures: failures)
        } catch {
            try? filesystem.removeItem(at: scratch)
            throw error
        }
    }

    private func failure(rendered: URL, in folder: URL, copyingInto directory: URL) throws -> TestRunFailure {
        let stem = rendered.deletingPathExtension().lastPathComponent
        let recorded = PaparazziFailureLayout.module(ofFailureFolder: folder)
            .flatMap { recordedSnapshot(named: rendered.lastPathComponent, in: $0) }

        var images: [TestRunImage] = []
        if let recorded {
            let copy = directory.appendingPathComponent("recorded-" + recorded.lastPathComponent)
            try filesystem.copyFile(from: recorded, to: copy)
            images.append(TestRunImage(id: copy.path, name: String(localized: "Recorded"), fileURL: copy))
        }
        let copy = directory.appendingPathComponent(rendered.lastPathComponent)
        try filesystem.copyFile(from: rendered, to: copy)
        images.append(TestRunImage(id: copy.path, name: String(localized: "Rendered"), fileURL: copy))

        let name = PaparazziProvider.recordedName(of: stem).map { "\($0.className).\($0.snapshotName)" } ?? stem
        return TestRunFailure(
            // The snapshot's path, so the matcher's tie-break between identical snapshots
            // finds every part of it in the right one.
            id: (recorded ?? rendered).path,
            name: name,
            groups: [TestRunImageGroup(id: directory.lastPathComponent, title: stem, images: images)],
            // The rendering was written as the test ran, after it had read the snapshot.
            startedAt: filesystem.modificationDate(at: rendered)
        )
    }

    /// The snapshot a rendering was compared with: the file of the same name in one of the
    /// module's source sets.
    private func recordedSnapshot(named fileName: String, in module: URL) -> URL? {
        let sources = module.appendingPathComponent(PaparazziProvider.sourceFolderName, isDirectory: true)
        let sourceSets = ((try? filesystem.contentsOfDirectory(at: sources)) ?? [])
            .sorted { $0.path < $1.path }
        // The unit test source set first, which is where Paparazzi records by default.
        let ordered = sourceSets.filter { $0.lastPathComponent == "test" }
            + sourceSets.filter { $0.lastPathComponent != "test" }
        return ordered
            .map {
                $0.appendingPathComponent(PaparazziProvider.snapshotsFolderName, isDirectory: true)
                    .appendingPathComponent(PaparazziProvider.imagesFolderName, isDirectory: true)
                    .appendingPathComponent(fileName)
            }
            .first(where: filesystem.fileExists(at:))
    }
}
