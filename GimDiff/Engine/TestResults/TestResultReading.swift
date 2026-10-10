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
}

extension TestResultLocating {
    /// The newest result bundle of any workspace belonging to the project, or `nil` when
    /// none of them has been tested.
    func latestResultBundle(forProjectAt rootURL: URL, gitRootURL: URL?) -> URL? {
        resultBundles(forProjectAt: rootURL, gitRootURL: gitRootURL).first?.url
    }
}
