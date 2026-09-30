//
//  StubTestResults.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
@testable import GimDiff

/// Stands in for both derived data and `xcresulttool`, answering with whatever run a test
/// sets up.
///
/// Also what keeps an `AppState` under test from reading the developer's own derived data:
/// a project a test loads could otherwise pick up the failures of a real run.
final class StubTestResults: TestResultReading, TestResultLocating, @unchecked Sendable {
    static let bundleURL = URL(fileURLWithPath: "/DerivedData/Demo-hash/Logs/Test/Run.xcresult")

    private let lock = NSLock()
    private var storedReport: TestRunReport?
    private var storedDirectories: [URL] = []
    private var storedReadCount = 0

    /// The run the stub reports, or `nil` for a project that has never been tested.
    var report: TestRunReport? {
        get { lock.withLock { storedReport } }
        set { lock.withLock { storedReport = newValue } }
    }

    var resultDirectories: [URL] {
        get { lock.withLock { storedDirectories } }
        set { lock.withLock { storedDirectories = newValue } }
    }

    /// How many times a bundle has been read.
    var readCount: Int {
        lock.withLock { storedReadCount }
    }

    func latestResultBundle(forProjectAt rootURL: URL, gitRootURL: URL?) -> URL? {
        report?.bundleURL
    }

    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] {
        resultDirectories
    }

    func report(forBundleAt bundle: URL) async throws -> TestRunReport {
        let report = lock.withLock {
            storedReadCount += 1
            return storedReport
        }
        guard let report else { throw GimDiffError.unreadableTestResults(bundle) }
        return report
    }
}
