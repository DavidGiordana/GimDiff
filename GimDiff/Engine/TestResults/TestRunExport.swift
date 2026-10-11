//
//  TestRunExport.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One thing a test run has to report outside the app: a failed snapshot with what the test
/// rendered, or an image the run attached that matches no snapshot.
struct TestRunExportEntry: Sendable, Equatable {
    enum Kind: String, Sendable {
        /// A snapshot of the project the test compared against and failed.
        case failure
        /// An image that matches no snapshot: a new snapshot, or a reference replaced by hand.
        case unmatched
    }

    var kind: Kind
    /// The test that failed, as Xcode identifies it.
    var testIdentifier: String
    var testName: String
    var suiteName: String?
    var snapshotName: String?
    /// The snapshot in the project, for a failure.
    var baselineURL: URL?
    /// What the test rendered, or the unmatched image itself.
    var candidateURL: URL
    /// A name for the files written about this entry, safe on any volume and unique within
    /// the run, without an extension.
    var fileStem: String
}

/// Flattens a read test run into entries a report or a CI artifact folder can list.
///
/// The app shows a run as a tree to act on; outside the app it is a list to read, so every
/// rendering of a failed snapshot and every unmatched image becomes one entry, in the order
/// the tests ran.
enum TestRunExport {
    static func entries(for results: TestRunResults, in project: ProjectBundle) -> [TestRunExportEntry] {
        let suites = Dictionary(project.suites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var stems = UniqueStems()
        var entries: [TestRunExportEntry] = []

        for difference in results.differences {
            if let baseline = difference.baseline {
                let suite = suites[baseline.suiteID]
                let snapshot = suite?.snapshots.first { $0.id == baseline.snapshotID }
                for candidate in difference.candidates {
                    let suiteName = suite?.name ?? difference.testName
                    let snapshotName = snapshot?.displayName ?? baseline.fileURL.deletingPathExtension().lastPathComponent
                    entries.append(TestRunExportEntry(
                        kind: .failure,
                        testIdentifier: difference.testIdentifier,
                        testName: difference.testName,
                        suiteName: suite?.name,
                        snapshotName: snapshotName,
                        baselineURL: baseline.fileURL,
                        candidateURL: candidate.fileURL,
                        fileStem: stems.claim(fileStem(suiteName, snapshotName))
                    ))
                }
            } else {
                for image in difference.candidates {
                    entries.append(TestRunExportEntry(
                        kind: .unmatched,
                        testIdentifier: difference.testIdentifier,
                        testName: difference.testName,
                        suiteName: nil,
                        snapshotName: nil,
                        baselineURL: nil,
                        candidateURL: image.fileURL,
                        fileStem: stems.claim(fileStem(difference.testName, image.name))
                    ))
                }
            }
        }

        return entries
    }

    /// Joins `parts` with dots into a name any volume accepts.
    ///
    /// Test and attachment names carry spaces, slashes, parentheses, and colons; anything
    /// but letters, digits, `-`, and `_` becomes `_`, and runs of it collapse, so a CI
    /// artifact list stays readable.
    static func fileStem(_ parts: String...) -> String {
        let cleaned = parts.map { part in
            var result = ""
            var lastWasReplacement = false
            for scalar in part.unicodeScalars {
                if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                    result.unicodeScalars.append(scalar)
                    lastWasReplacement = false
                } else if !lastWasReplacement {
                    result.append("_")
                    lastWasReplacement = true
                }
            }
            return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        let joined = cleaned.filter { !$0.isEmpty }.joined(separator: ".")
        return joined.isEmpty ? "snapshot" : joined
    }

    /// Hands out each stem once, numbering a repeat: a test that asserts the same snapshot
    /// twice fails it twice, and the second set of files must not overwrite the first.
    private struct UniqueStems {
        private var used: Set<String> = []

        mutating func claim(_ stem: String) -> String {
            var candidate = stem
            var number = 2
            while used.contains(candidate.lowercased()) {
                candidate = "\(stem)-\(number)"
                number += 1
            }
            // Compared without case: the default macOS volume does not tell `A` from `a`.
            used.insert(candidate.lowercased())
            return candidate
        }
    }
}
