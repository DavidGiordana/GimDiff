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
/// compared against attaches a picture of a file the project holds, so an attachment
/// showing the same image as a snapshot *is* that snapshot's baseline, whatever either one
/// is called and whichever library attached it.
///
/// Identical bytes are looked for first, and identical pixels only when no image of a step
/// has them. A library that attaches the reference as a decoded image re-encodes it —
/// swift-snapshot-testing does — and that usually reproduces the file only because the
/// same encoder wrote it. A snapshot recorded on another machine or edited by hand holds
/// the same picture in other bytes.
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
        let restored = Self.snapshotsAtHEAD(in: project)
        var differences: [TestRunDifference] = []

        for failure in report.failures {
            try Task.checkCancellation()
            for group in failure.groups {
                differences.append(
                    contentsOf: self.differences(
                        in: group,
                        of: failure,
                        since: failure.startedAt ?? report.startedAt,
                        restored: restored,
                        index: &index
                    )
                )
            }
        }

        return differences
    }

    private func differences(
        in group: TestRunImageGroup,
        of failure: TestRunFailure,
        since runStart: Date?,
        restored: Set<URL>,
        index: inout SnapshotIndex
    ) -> [TestRunDifference] {
        let attached = group.images.compactMap { image -> (image: TestRunImage, data: Data)? in
            guard let data = try? filesystem.readFile(at: image.fileURL) else { return nil }
            return (image, data)
        }

        var matches = attached.flatMap { image, data in
            index.snapshots(holding: data).map { Match(image: image, baseline: $0) }
        }
        if matches.isEmpty {
            let related = Self.nameParts(of: failure)
            matches = attached.flatMap { image, data in
                index.snapshots(depicting: data, preferringPathsNaming: related)
                    .map { Match(image: image, baseline: $0) }
            }
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
        // candidate. Whatever the step had to say has been overtaken, so it says nothing —
        // unless Git says the file is back at `HEAD`: an accepted candidate that was then
        // discarded holds the reference the run compared against once more.
        guard !matches.contains(where: { match in
            !restored.contains(match.baseline.fileURL) && isWritten(match.baseline.fileURL, after: runStart)
        }) else {
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

    /// The snapshots Git has nothing against, when the project is a repository.
    ///
    /// Outside one every snapshot reads as unmodified, which says nothing, so none counts.
    private static func snapshotsAtHEAD(in project: ProjectBundle) -> Set<URL> {
        guard project.gitRootURL != nil else { return [] }
        return Set(project.suites.flatMap(\.snapshots).filter { $0.gitStatus == .unmodified }.map(\.fileURL))
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

        let parts = nameParts(of: failure)
        let scores = matches.map { match in
            parts.filter { match.baseline.fileURL.path.contains($0) }.count
        }
        let best = scores.max() ?? 0

        return zip(matches, scores).filter { $0.1 == best }.map(\.0)
    }

    /// The parts of the identifier Xcode gives the failed test: its class and its method.
    private static func nameParts(of failure: TestRunFailure) -> [Substring] {
        failure.id
            .split(separator: "/")
            .map { $0.prefix { $0 != "(" } }
            .filter { !$0.isEmpty }
    }
}

/// The project's snapshots, looked up by what they contain.
///
/// Sizes are collected up front and contents only on demand: an attachment can only equal a
/// snapshot of its own length, which leaves a handful of files to read out of a project
/// that may hold thousands.
private struct SnapshotIndex {
    private let filesystem: any FilesystemService
    private var baselines: [TestRunDifference.Baseline] = []
    private var baselinesBySize: [Int: [TestRunDifference.Baseline]] = [:]
    private var contents: [String: Data] = [:]
    /// What each snapshot decoded to, `nil` when it would not decode. Only the digest is
    /// kept: a decoded snapshot is megabytes.
    private var pixels: [String: ImagePixels?] = [:]

    init(project: ProjectBundle, filesystem: any FilesystemService) {
        self.filesystem = filesystem

        for suite in project.suites {
            for snapshot in suite.snapshots {
                guard let size = filesystem.fileSize(at: snapshot.fileURL) else { continue }
                let baseline = TestRunDifference.Baseline(
                    suiteID: suite.id,
                    snapshotID: snapshot.id,
                    fileURL: snapshot.fileURL
                )
                baselines.append(baseline)
                baselinesBySize[size, default: []].append(baseline)
            }
        }
    }

    /// Every snapshot whose file is byte for byte `data`.
    mutating func snapshots(holding data: Data) -> [TestRunDifference.Baseline] {
        (baselinesBySize[data.count] ?? []).filter { contents(of: $0.fileURL) == data }
    }

    /// Every snapshot showing the same pixels as `data`, however either one was encoded.
    ///
    /// Decoding is what makes this the fallback: a length rules nothing out here, so every
    /// snapshot is a candidate. The ones whose path names the failed test are decoded
    /// first, and the rest only when none of those is the picture. The names only order the
    /// search; the pixels decide.
    mutating func snapshots(
        depicting data: Data,
        preferringPathsNaming parts: [Substring]
    ) -> [TestRunDifference.Baseline] {
        guard let attached = ImagePixels(decoding: data) else { return [] }

        let (named, others) = baselines.reduce(
            into: ([TestRunDifference.Baseline](), [TestRunDifference.Baseline]())
        ) { tiers, baseline in
            if parts.contains(where: { baseline.fileURL.path.contains($0) }) {
                tiers.0.append(baseline)
            } else {
                tiers.1.append(baseline)
            }
        }

        for tier in [named, others] {
            let found = tier.filter { pixels(of: $0.fileURL) == attached }
            if !found.isEmpty { return found }
        }
        return []
    }

    private mutating func contents(of url: URL) -> Data? {
        if let known = contents[url.path] { return known }
        let data = try? filesystem.readFile(at: url)
        contents[url.path] = data
        return data
    }

    private mutating func pixels(of url: URL) -> ImagePixels? {
        if let known = pixels[url.path] { return known }
        let decoded = (try? filesystem.readFile(at: url)).flatMap(ImagePixels.init(decoding:))
        pixels[url.path] = decoded
        return decoded
    }
}
