//
//  TestRunSources.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The runs of every kind a project can have, offered together, newest first.
///
/// A project can be tested by Xcode and by Paparazzi at once — a multiplatform repository
/// is — and the run picker lists both rather than making one hide the other.
struct CombinedTestResultLocator: TestResultLocating {
    private let locators: [any TestResultLocating]

    init(_ locators: [any TestResultLocating]) {
        self.locators = locators
    }

    func resultBundles(forProjectAt rootURL: URL, gitRootURL: URL?) -> [TestRunBundle] {
        Self.newestFirst(locators.flatMap { $0.resultBundles(forProjectAt: rootURL, gitRootURL: gitRootURL) })
    }

    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] {
        locators.flatMap { $0.resultDirectories(forProjectAt: rootURL, gitRootURL: gitRootURL) }
    }

    func resultBundles(for project: ProjectBundle) -> [TestRunBundle] {
        Self.newestFirst(locators.flatMap { $0.resultBundles(for: project) })
    }

    func resultDirectories(for project: ProjectBundle) -> [URL] {
        locators.flatMap { $0.resultDirectories(for: project) }
    }

    /// A run that records no date goes last, where nothing can claim it is the newest.
    private static func newestFirst(_ bundles: [TestRunBundle]) -> [TestRunBundle] {
        bundles.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.createdAt, rhs.element.createdAt) {
                case let (left?, right?) where left != right: left > right
                case (_?, nil): true
                case (nil, _?): false
                default: lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}

/// Reads a run with the reader that understands it: Paparazzi's failure folders with
/// ``PaparazziFailureReader``, anything else as an Xcode result bundle.
struct CombinedTestResultReader: TestResultReading {
    private let xcode: any TestResultReading
    private let paparazzi: any TestResultReading

    init(xcode: any TestResultReading, paparazzi: any TestResultReading) {
        self.xcode = xcode
        self.paparazzi = paparazzi
    }

    /// A path with no `.xcresult` extension is taken for a Paparazzi failures folder.
    func report(forBundleAt bundle: URL) async throws -> TestRunReport {
        bundle.pathExtension == "xcresult"
            ? try await xcode.report(forBundleAt: bundle)
            : try await paparazzi.report(forBundleAt: bundle)
    }

    func report(for bundle: TestRunBundle) async throws -> TestRunReport {
        bundle.failureFolders.isEmpty
            ? try await xcode.report(for: bundle)
            : try await paparazzi.report(for: bundle)
    }
}
