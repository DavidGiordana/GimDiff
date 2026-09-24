//
//  DefaultFilesystemService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// ``FilesystemService`` backed by `FileManager.default`.
struct DefaultFilesystemService: FilesystemService {
    /// Scratch directory holding the committed images extracted for a comparison.
    static let temporaryDirectoryName = "com.davidgiordana.GimDiff"

    private var fileManager: FileManager { .default }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func isPackage(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?
    ) throws -> [URL] {
        // FileManager refuses to list a symlink even when it points at a directory, and
        // reports the failure as "no such file". Resolving first is what lets a project
        // reached through a symlinked path be read at all.
        try fileManager.contentsOfDirectory(
            at: url.resolvingSymlinksInPath(),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
    }

    func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeFile(at url: URL, data: Data) throws {
        try createParentDirectory(of: url)
        try data.write(to: url, options: .atomic)
    }

    func copyFile(from source: URL, to destination: URL) throws {
        try createParentDirectory(of: destination)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    func replaceFile(at destination: URL, with source: URL) throws {
        try createParentDirectory(of: destination)

        // `replaceItemAt` needs something to exchange with; on a first accept the
        // destination does not exist yet, so a plain move is the atomic equivalent.
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: source, to: destination)
            return
        }

        _ = try fileManager.replaceItemAt(destination, withItemAt: source)
    }

    func trashFile(at url: URL) throws {
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    func createTemporaryFile(prefix: String, extension fileExtension: String) -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(Self.temporaryDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    /// Overrides the protocol's walk with a single `FileManager` enumeration.
    ///
    /// Beyond being one pass instead of one call per directory, the enumerator skips
    /// package descendants, so a `.app` or `.bundle` sitting in a snapshot folder is not
    /// mined for the images inside it.
    func imageFiles(under folder: URL) -> [URL] {
        let enumerator = fileManager.enumerator(
            at: folder.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let files = enumerator?.compactMap { $0 as? URL }.filter(\.isImageFile) ?? []
        return files.sorted { $0.path < $1.path }
    }

    private func createParentDirectory(of url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
