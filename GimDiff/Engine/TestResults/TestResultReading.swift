//
//  TestResultReading.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Reads what failed in a test run, and exports the images the failures attached.
protocol TestResultReading: Sendable {
    /// - Throws: `GimDiffError` when the bundle cannot be read, or `CancellationError`.
    ///   Nothing is left in the scratch folder when it throws.
    func report(forBundleAt bundle: URL) async throws -> TestRunReport

    /// The report of a run a locator found, which may be more than one folder.
    ///
    /// Defaults to reading ``TestRunBundle/url``, which is all an Xcode bundle is.
    func report(for bundle: TestRunBundle) async throws -> TestRunReport
}

extension TestResultReading {
    func report(for bundle: TestRunBundle) async throws -> TestRunReport {
        try await report(forBundleAt: bundle.url)
    }
}

/// Finds the result bundles of a project's test runs.
///
/// Xcode keeps those outside the project, in a folder named after a hash of the
/// workspace's path, so locating one means reading Xcode's own bookkeeping. The engine
/// only names the question.
protocol TestResultLocating: Sendable {
    /// Every result bundle of every workspace belonging to the project, newest first, or
    /// none when none of them has been tested.
    ///
    /// - Parameter gitRootURL: The working tree holding the project. A project opened on
    ///   one module's snapshot folder is tested through a workspace elsewhere in the
    ///   repository, and the working tree is what ties the two together.
    func resultBundles(forProjectAt rootURL: URL, gitRootURL: URL?) -> [TestRunBundle]

    /// The folders a new run of the project would be written into, for watching.
    ///
    /// Only folders that exist: a workspace that has never been tested has nowhere yet.
    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL]

    /// The runs of `project`, newest first.
    ///
    /// Defaults to looking by the project's location. A locator whose runs are kept beside
    /// the snapshots, as Paparazzi's are, reads where those are from the project's suites
    /// instead of walking the tree for them again.
    func resultBundles(for project: ProjectBundle) -> [TestRunBundle]

    /// The folders `project`'s next run would be written into, for watching.
    func resultDirectories(for project: ProjectBundle) -> [URL]
}

extension TestResultLocating {
    func resultBundles(for project: ProjectBundle) -> [TestRunBundle] {
        resultBundles(forProjectAt: project.rootURL, gitRootURL: project.gitRootURL)
    }

    func resultDirectories(for project: ProjectBundle) -> [URL] {
        resultDirectories(forProjectAt: project.rootURL, gitRootURL: project.gitRootURL)
    }

    /// The newest result bundle of any workspace belonging to the project, or `nil` when
    /// none of them has been tested.
    func latestResultBundle(forProjectAt rootURL: URL, gitRootURL: URL?) -> URL? {
        resultBundles(forProjectAt: rootURL, gitRootURL: gitRootURL).first?.url
    }
}
