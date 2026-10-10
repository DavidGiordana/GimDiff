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
    private var storedReports: [TestRunReport] = []
    private var storedDirectories: [URL] = []
    private var storedReadCount = 0

    /// The newest run the stub reports, or `nil` for a project that has never been tested.
    /// Setting it leaves that run as the only one.
    var report: TestRunReport? {
        get { lock.withLock { storedReports.first } }
        set { lock.withLock { storedReports = newValue.map { [$0] } ?? [] } }
    }

    /// Every run the stub reports, newest first.
    var reports: [TestRunReport] {
        get { lock.withLock { storedReports } }
        set { lock.withLock { storedReports = newValue } }
    }

    var resultDirectories: [URL] {
        get { lock.withLock { storedDirectories } }
        set { lock.withLock { storedDirectories = newValue } }
    }

    /// How many times a bundle has been read.
    var readCount: Int {
        lock.withLock { storedReadCount }
    }

    func resultBundles(forProjectAt rootURL: URL, gitRootURL: URL?) -> [TestRunBundle] {
        reports.map { report in
            TestRunBundle(url: report.bundleURL, createdAt: report.startedAt, workspaceName: "Demo.xcodeproj")
        }
    }

    func resultDirectories(forProjectAt rootURL: URL, gitRootURL: URL?) -> [URL] {
        resultDirectories
    }

    func report(forBundleAt bundle: URL) async throws -> TestRunReport {
        let report = lock.withLock {
            storedReadCount += 1
            return storedReports.first { $0.bundleURL == bundle }
        }
        guard let report else { throw GimDiffError.unreadableTestResults(bundle) }
        return report
    }
}
