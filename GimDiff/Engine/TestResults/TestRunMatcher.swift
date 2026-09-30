//
//  TestRunMatcher.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One thing a failed test has to show: the images a step attached, against the snapshot
/// in the project they were compared with when there is one.
struct TestRunDifference: Identifiable, Sendable, Equatable {
    /// The snapshot in the open project a difference is about.
    struct Baseline: Sendable, Equatable {
        var suiteID: SnapshotSuite.ID
        var snapshotID: SnapshotItem.ID
        var fileURL: URL
    }

    let id: String
    /// The test that failed, as Xcode identifies it.
    var testIdentifier: String
    var testName: String
    /// What Xcode calls the step that attached the images.
    var title: String
    /// `nil` when none of the step's images is a snapshot the project holds: the test
    /// attached something that is not a comparison, or its baseline was replaced by hand.
    var baseline: Baseline?
    /// What the test rendered: the first image the step attached besides the baseline.
    ///
    /// When a step matched no snapshot, every image it attached, since there is no
    /// baseline to tell a rendering apart from anything else.
    var candidates: [TestRunImage]
}

/// Pairs the images of a test run with the snapshots of the open project.
///
/// The pairing is made on contents alone. An assertion that attaches the reference it
/// compared against attaches a copy of a file the project holds, so an attachment with the
/// same bytes as a snapshot *is* that snapshot's baseline, whatever either one is called
/// and whichever library attached it.
struct TestRunMatcher: Sendable {
    private let filesystem: any FilesystemService

    init(filesystem: any FilesystemService) {
        self.filesystem = filesystem
    }

    /// Everything the failed tests of `report` have to show, in the order the tests ran.
    ///
    /// - Throws: `CancellationError`, checked once per failed test.
    func differences(in report: TestRunReport, against project: ProjectBundle) throws -> [TestRunDifference] {
        var index = SnapshotIndex(project: project, filesystem: filesystem)
        var differences: [TestRunDifference] = []

        for failure in report.failures {
            try Task.checkCancellation()
            for group in failure.groups {
                differences.append(
                    contentsOf: self.differences(in: group, of: failure, since: report.startedAt, index: &index)
                )
            }
        }

        return differences
    }

    private func differences(
        in group: TestRunImageGroup,
        of failure: TestRunFailure,
        since runStart: Date?,
        index: inout SnapshotIndex
    ) -> [TestRunDifference] {
        var matches: [Match] = []
        for image in group.images {
            guard let data = try? filesystem.readFile(at: image.fileURL) else { continue }
            matches += index.snapshots(holding: data).map { Match(image: image, baseline: $0) }
        }

        guard !matches.isEmpty else {
            return [
                TestRunDifference(
                    id: group.id,
                    testIdentifier: failure.id,
                    testName: failure.name,
                    title: group.title,
                    baseline: nil,
                    candidates: group.images
                ),
            ]
        }

        // A snapshot written after the run began is not the file the run compared against.
        // The usual way there is accepting the candidate, which leaves the *rendered* image
        // equal to the snapshot and would otherwise turn the old reference into the
        // candidate. Whatever the step had to say has been overtaken, so it says nothing.
        guard !matches.contains(where: { isWritten($0.baseline.fileURL, after: runStart) }) else {
            return []
        }

        return Self.mostRelated(matches, to: failure).compactMap { match in
            // The rendering is the first image attached besides the reference, which is the
            // one choice left to attachment order. An assertion attaches what it got before
            // any picture it draws of the difference, and that picture has no place here:
            // the canvas measures the difference itself, in the diff mask. Another matched
            // image still counts, because a rendering can be identical to some other snapshot
            // in the project without being a baseline.
            guard let rendered = group.images.first(where: { $0.id != match.image.id }) else {
                // A step that attached the reference and nothing else has nothing to compare.
                return nil
            }
            let candidates = [rendered]

            return TestRunDifference(
                id: "\(group.id)|\(match.baseline.suiteID)|\(match.baseline.snapshotID)",
                testIdentifier: failure.id,
                testName: failure.name,
                title: group.title,
                baseline: match.baseline,
                candidates: candidates
            )
        }
    }

    private func isWritten(_ file: URL, after runStart: Date?) -> Bool {
        guard let runStart, let written = filesystem.modificationDate(at: file) else { return false }
        return written > runStart
    }

    // MARK: - Ambiguity

    private struct Match {
        var image: TestRunImage
        var baseline: TestRunDifference.Baseline
    }

    /// Narrows `matches` to the snapshots whose path names the most of the failed test.
    ///
    /// Contents alone stop being enough when the same image is recorded twice — an empty
    /// state shared by two screens, a light and a dark variant that render alike. Only
    /// then is a name consulted, and only as a preference: the parts of the identifier
    /// Xcode gives the test are looked for in the snapshot's path, and when no snapshot
    /// mentions more of them than another, all of them are kept.
    private static func mostRelated(_ matches: [Match], to failure: TestRunFailure) -> [Match] {
        guard matches.count > 1 else { return matches }

        let parts = failure.id
            .split(separator: "/")
            .map { $0.prefix { $0 != "(" } }
            .filter { !$0.isEmpty }
        let scores = matches.map { match in
            parts.filter { match.baseline.fileURL.path.contains($0) }.count
        }
        let best = scores.max() ?? 0

        return zip(matches, scores).filter { $0.1 == best }.map(\.0)
    }
}

/// The project's snapshots, looked up by what they contain.
///
/// Sizes are collected up front and contents only on demand: an attachment can only equal a
/// snapshot of its own length, which leaves a handful of files to read out of a project
/// that may hold thousands.
private struct SnapshotIndex {
    private let filesystem: any FilesystemService
    private var baselinesBySize: [Int: [TestRunDifference.Baseline]] = [:]
    private var contents: [String: Data] = [:]

    init(project: ProjectBundle, filesystem: any FilesystemService) {
        self.filesystem = filesystem

        for suite in project.suites {
            for snapshot in suite.snapshots {
                guard let size = filesystem.fileSize(at: snapshot.fileURL) else { continue }
                baselinesBySize[size, default: []].append(
                    TestRunDifference.Baseline(
                        suiteID: suite.id,
                        snapshotID: snapshot.id,
                        fileURL: snapshot.fileURL
                    )
                )
            }
        }
    }

    /// Every snapshot whose file is byte for byte `data`.
    mutating func snapshots(holding data: Data) -> [TestRunDifference.Baseline] {
        (baselinesBySize[data.count] ?? []).filter { contents(of: $0.fileURL) == data }
    }

    private mutating func contents(of url: URL) -> Data? {
        if let known = contents[url.path] { return known }
        let data = try? filesystem.readFile(at: url)
        contents[url.path] = data
        return data
    }
}
