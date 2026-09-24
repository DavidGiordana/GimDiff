//
//  DirectorySnapshotProvider.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Recognises the convention most snapshot-testing libraries follow: reference images sit
/// in one folder and the images written by a failing run sit alongside them, marked by
/// `failure` somewhere in the path.
struct DirectorySnapshotProvider: SnapshotProviding {
    /// Marks a path as holding the output of a failing run rather than a reference image.
    static let failureMarker = "failure"

    let name = "Directory"

    private let fileSystem: any FilesystemService

    init(fileSystem: any FilesystemService) {
        self.fileSystem = fileSystem
    }

    func canHandle(folder: URL) async -> Bool {
        fileSystem.isDirectory(at: folder) && !fileSystem.imageFiles(under: folder).isEmpty
    }

    func pairs(in folder: URL) async throws -> [SnapshotPair] {
        Self.pairs(from: fileSystem.imageFiles(under: folder))
    }

    /// Splits a flat list of images into reference/failure pairs.
    ///
    /// Separated from disk access so the convention itself can be tested directly.
    static func pairs(from images: [URL]) -> [SnapshotPair] {
        let failures = images.filter(isFailure)
        let references = images.filter { !isFailure($0) }
        return SnapshotPair.matching(references: references, failures: failures)
    }

    private static func isFailure(_ url: URL) -> Bool {
        url.path.localizedCaseInsensitiveContains(failureMarker)
    }
}
