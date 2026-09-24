//
//  FileSystemService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Reads the snapshot folders GimDiff works with.
struct FileSystemService: Sendable {
    private var fileManager: FileManager { .default }

    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Every image file under `folder`, including nested directories.
    ///
    /// Package contents and hidden files are skipped; the result is sorted by path so the
    /// sidebar order does not depend on enumeration order.
    func imageFiles(under folder: URL) -> [URL] {
        let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let files = enumerator?.compactMap { $0 as? URL }.filter(\.isImageFile) ?? []
        return files.sorted { $0.path < $1.path }
    }

    func copyItem(at source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: source, to: destination)
    }
}
