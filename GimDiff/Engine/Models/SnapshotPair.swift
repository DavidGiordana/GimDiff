//
//  SnapshotPair.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A reference image paired with the failure image that should replace or match it.
struct SnapshotPair: Identifiable, Hashable, Sendable {
    let reference: SnapshotReference
    let failure: SnapshotReference

    var id: URL { reference.url }

    /// Display name shared by both sides of the comparison.
    var name: String { reference.name }

    init(reference: URL, failure: URL) {
        self.reference = SnapshotReference(url: reference, kind: .reference)
        self.failure = SnapshotReference(url: failure, kind: .failure)
    }

    /// Matches reference and failure images by file name, ignoring the directory each lives in.
    ///
    /// Images without a counterpart on the other side are dropped: a comparison needs both.
    static func matching(references: [URL], failures: [URL]) -> [SnapshotPair] {
        let failuresByName = Dictionary(
            failures.map { ($0.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return references.compactMap { reference in
            guard let failure = failuresByName[reference.lastPathComponent] else { return nil }
            return SnapshotPair(reference: reference, failure: failure)
        }
    }
}
