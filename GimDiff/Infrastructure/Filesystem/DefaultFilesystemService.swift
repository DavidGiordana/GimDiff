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
    /// Where every process's scratch folder is made.
    static let scratchRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(temporaryDirectoryName, isDirectory: true)
    /// The folder this process's scratch files go in, named after the process.
    ///
    /// One per process because the app and any number of `gimdiff` invocations can run at
    /// once: the name is what lets a sweep tell a folder whose owner is gone from one still
    /// in use. Masks, committed versions, undo copies, a test run's exports, and a pull
    /// request's downloads all live under it, so removing it removes the lot.
    static let sessionDirectory = scratchRoot
        .appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier), isDirectory: true)
    /// Scratch roots of versions before per-process folders, swept but no longer written.
    static let legacyScratchRoots = [
        scratchRoot,
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(temporaryDirectoryName).TestRuns"),
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(temporaryDirectoryName).PullRequests"),
    ]
    /// How old a file of a legacy root must be before a sweep takes it: an older GimDiff
    /// may still be running and writing there.
    static let legacyScratchLifetime: TimeInterval = 24 * 60 * 60

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

    func fileSize(at url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return nil }
        return values?.fileSize
    }

    func modificationDate(at url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
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

    @discardableResult
    func trashFile(at url: URL) throws -> URL? {
        var resulting: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try createParentDirectory(of: destination)
        try fileManager.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func createTemporaryFile(prefix: String, extension fileExtension: String) -> URL {
        let directory = Self.sessionDirectory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    // MARK: - Scratch lifetime

    /// Deletes this process's scratch folder, for a process on its way out.
    static func removeSessionScratch() {
        try? FileManager.default.removeItem(at: sessionDirectory)
    }

    /// Deletes what processes that are no longer running left behind.
    ///
    /// A folder named after a process is kept while that process runs, and goes with
    /// everything in it once it does not: a crash, a force quit, or a debugger stopping the
    /// app never reached ``removeSessionScratch()``. Anything else in a scratch root
    /// predates per-process folders and goes once ``legacyScratchLifetime`` has passed.
    ///
    /// - Parameters:
    ///   - isRunning: Whether a process is alive, replaced by tests.
    static func removeAbandonedScratch(
        sessionsIn root: URL = scratchRoot,
        legacyRoots: [URL] = legacyScratchRoots,
        isRunning: (pid_t) -> Bool = DefaultFilesystemService.isRunning,
        now: Date = Date()
    ) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]

        for entry in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? [] {
            guard let pid = pid_t(entry.lastPathComponent) else { continue }
            if !isRunning(pid) { try? fileManager.removeItem(at: entry) }
        }

        for legacyRoot in legacyRoots {
            for entry in (try? fileManager.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: keys)) ?? [] {
                // A session folder is the sweep above's to judge, whichever root it is in.
                guard legacyRoot != root || pid_t(entry.lastPathComponent) == nil else { continue }
                let modified = (try? entry.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
                if now.timeIntervalSince(modified) > legacyScratchLifetime {
                    try? fileManager.removeItem(at: entry)
                }
            }
            if legacyRoot != root, (try? fileManager.contentsOfDirectory(atPath: legacyRoot.path))?.isEmpty == true {
                try? fileManager.removeItem(at: legacyRoot)
            }
        }
    }

    /// Whether the process `pid` is alive. `EPERM` means it is, and belongs to someone else.
    static func isRunning(_ pid: pid_t) -> Bool {
        pid == getpid() || kill(pid, 0) == 0 || errno == EPERM
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
