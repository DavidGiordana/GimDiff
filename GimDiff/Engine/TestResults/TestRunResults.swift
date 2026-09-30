//
//  TestRunResults.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What the last test run has to show about the open project, ready to be looked up by row.
struct TestRunResults: Sendable, Equatable {
    /// The result bundle the differences were read from.
    let bundleURL: URL
    /// Folder holding the images, to be removed when the results leave the screen.
    let scratchDirectory: URL
    /// When the run began, when the bundle says.
    let startedAt: Date?
    private(set) var differences: [TestRunDifference]
    /// The images each failing snapshot was attached with, keyed by the snapshot's identifier.
    private(set) var candidatesBySnapshotID: [SnapshotItem.ID: [TestRunImage]]

    init(bundleURL: URL, scratchDirectory: URL, startedAt: Date? = nil, differences: [TestRunDifference]) {
        self.bundleURL = bundleURL
        self.scratchDirectory = scratchDirectory
        self.startedAt = startedAt
        self.differences = differences
        candidatesBySnapshotID = Self.candidates(in: differences)
    }

    init(report: TestRunReport, differences: [TestRunDifference]) {
        self.init(
            bundleURL: report.bundleURL,
            scratchDirectory: report.scratchDirectory,
            startedAt: report.startedAt,
            differences: differences
        )
    }

    var isEmpty: Bool { differences.isEmpty }

    /// How many snapshots of the project the run failed on.
    var failedSnapshotsCount: Int { candidatesBySnapshotID.count }

    /// The images attached beside `snapshotID` when its test failed, or none when it did not.
    func candidates(forSnapshotID snapshotID: SnapshotItem.ID) -> [TestRunImage] {
        candidatesBySnapshotID[snapshotID] ?? []
    }

    func isFailing(snapshotID: SnapshotItem.ID) -> Bool {
        candidatesBySnapshotID[snapshotID] != nil
    }

    /// The differences that are about no snapshot the project holds.
    var unmatched: [TestRunDifference] {
        differences.filter { $0.baseline == nil }
    }

    /// The image exported to `url`, which is what knows the name it was attached under.
    func image(at url: URL) -> TestRunImage? {
        differences.lazy.flatMap(\.candidates).first { $0.fileURL == url }
    }

    /// Forgets everything the run said about one snapshot, once it has been acted on.
    mutating func resolve(snapshotID: SnapshotItem.ID) {
        differences.removeAll { $0.baseline?.snapshotID == snapshotID }
        candidatesBySnapshotID = Self.candidates(in: differences)
    }

    private static func candidates(in differences: [TestRunDifference]) -> [SnapshotItem.ID: [TestRunImage]] {
        var candidates: [SnapshotItem.ID: [TestRunImage]] = [:]
        for difference in differences {
            guard let baseline = difference.baseline else { continue }
            // A test asserting the same snapshot twice attaches twice; both sets are offered.
            for image in difference.candidates where candidates[baseline.snapshotID]?.contains(image) != true {
                candidates[baseline.snapshotID, default: []].append(image)
            }
        }
        return candidates
    }
}
