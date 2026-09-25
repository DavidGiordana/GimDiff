//
//  FilesystemService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Every disk operation GimDiff performs, behind one substitutable seam.
///
/// Routing reads and writes through a protocol keeps the callers testable: unit tests
/// inject an in-memory double and never touch the real volume.
protocol FilesystemService: Sendable {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool

    /// Whether `url` is a document package: a directory the Finder presents as one file,
    /// such as `.xcassets`, `.xcodeproj`, or `.app`.
    ///
    /// Snapshot discovery treats a package as opaque. An asset catalog holds thousands of
    /// images that are not snapshots, and descending into one is both slow and wrong.
    func isPackage(at url: URL) -> Bool

    /// Immediate children of `url`, not recursing into subdirectories.
    ///
    /// Hidden entries are skipped. A `url` that is a symlink to a directory lists the
    /// directory it points at, so children come back under their resolved paths.
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?
    ) throws -> [URL]

    func readFile(at url: URL) throws -> Data

    /// Writes `data` to `url`, creating any missing parent directories.
    func writeFile(at url: URL, data: Data) throws

    /// Copies `source` over `destination`, replacing whatever was there.
    func copyFile(from source: URL, to destination: URL) throws

    /// Swaps `source` into `destination` atomically, consuming `source`.
    ///
    /// Accepting a snapshot must never leave a half-written image behind, so the new file
    /// is exchanged with the old one in a single step rather than truncated and rewritten.
    func replaceFile(at destination: URL, with source: URL) throws

    /// Moves `url` to the user's Trash so a deletion stays recoverable.
    func trashFile(at url: URL) throws

    /// Deletes `url` outright, folder and all.
    ///
    /// Reserved for GimDiff's own scratch files, such as a pull request's downloaded
    /// snapshots. Those are copies nobody asked to keep, and sending them to the Trash would
    /// leave a folder there for every review. Anything the user owns goes through
    /// ``trashFile(at:)``.
    func removeItem(at url: URL) throws

    /// A unique, not-yet-existing URL inside a scratch directory that does exist.
    ///
    /// Callers write to the returned location; the enclosing directory is guaranteed, the
    /// file itself is not created.
    func createTemporaryFile(prefix: String, extension fileExtension: String) -> URL

    /// Every image file under `folder`, including nested directories, sorted by path.
    ///
    /// Sorting is part of the contract: the sidebar order must not depend on the order a
    /// volume happens to enumerate in.
    ///
    /// A requirement rather than an extension-only member, so the walk below stays a
    /// default an implementation is free to replace. Were it extension-only it would
    /// dispatch statically, and a conforming type's own version would be skipped whenever
    /// the caller held an `any FilesystemService`.
    func imageFiles(under folder: URL) -> [URL]
}

extension FilesystemService {
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    /// Walks `folder` through ``contentsOfDirectory(at:includingPropertiesForKeys:)``.
    ///
    /// A directory that cannot be read is skipped rather than failing the whole walk: one
    /// unreadable subfolder should not hide every snapshot beside it.
    func imageFiles(under folder: URL) -> [URL] {
        var images: [URL] = []
        var pending = [folder]

        while let directory = pending.popLast() {
            guard let children = try? contentsOfDirectory(at: directory) else { continue }
            for child in children {
                if isDirectory(at: child) {
                    pending.append(child)
                } else if child.isImageFile {
                    images.append(child)
                }
            }
        }

        return images.sorted { $0.path < $1.path }
    }

    func createTemporaryFile(prefix: String = "GimDiff") -> URL {
        createTemporaryFile(prefix: prefix, extension: "tmp")
    }
}
