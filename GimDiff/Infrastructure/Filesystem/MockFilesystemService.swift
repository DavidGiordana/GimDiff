//
//  MockFilesystemService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// In-memory ``FilesystemService`` used by unit tests.
///
/// Nothing reaches the real volume, so tests stay hermetic and leave no scratch files
/// behind. State is guarded by a lock because the protocol is `Sendable` and callers are
/// free to reach it from any executor.
final class MockFilesystemService: FilesystemService, @unchecked Sendable {
    /// Root of the fake volume the mock hands out temporary paths under.
    static let temporaryDirectory = URL(fileURLWithPath: "/mock-tmp", isDirectory: true)

    private let lock = NSLock()
    private var storedFiles: [String: Data] = [:]
    private var storedDirectories: Set<String> = ["/"]
    private var storedPackages: Set<String> = []
    private var storedTrashedPaths: [String] = []
    /// What each trashed item held, keyed by the path the mock says it went to, with every
    /// file under it stored relative to the item itself.
    private var storedTrash: [String: [String: Data]] = [:]
    private var storedRemovedPaths: [String] = []
    private var storedModificationDates: [String: Date] = [:]

    init(files: [URL: Data] = [:], directories: [URL] = []) {
        for directory in directories {
            registerDirectory(Self.key(for: directory))
        }
        for (url, data) in files {
            let key = Self.key(for: url)
            storedFiles[key] = data
            registerParents(of: key)
        }
    }

    // MARK: - Inspection

    /// Every file currently on the fake volume, keyed by absolute path.
    var files: [String: Data] {
        lock.withLock { storedFiles }
    }

    /// Paths handed to ``trashFile(at:)``, in call order.
    var trashedPaths: [String] {
        lock.withLock { storedTrashedPaths }
    }

    /// Paths handed to ``removeItem(at:)``, in call order.
    var removedPaths: [String] {
        lock.withLock { storedRemovedPaths }
    }

    /// Seeds a file without going through ``writeFile(at:data:)``.
    func stub(_ url: URL, contents: String) {
        stub(url, data: Data(contents.utf8))
    }

    func stub(_ url: URL, data: Data) {
        lock.withLock {
            let key = Self.key(for: url)
            storedFiles[key] = data
            registerParents(of: key)
        }
    }

    /// Dates a file. Nothing has a date until a test gives it one: the mock keeps no clock,
    /// and a date invented on every write would make tests depend on how fast they ran.
    func setModificationDate(_ date: Date, at url: URL) {
        lock.withLock { storedModificationDates[Self.key(for: url)] = date }
    }

    func createDirectory(at url: URL) {
        lock.withLock { registerDirectory(Self.key(for: url)) }
    }

    /// Marks a directory as a document package, the way an `.xcassets` folder is on disk.
    ///
    /// Nothing is a package until a test says so: the real service reads a flag off the
    /// volume, and there is nothing here to read it from.
    func markAsPackage(at url: URL) {
        lock.withLock {
            let key = Self.key(for: url)
            registerDirectory(key)
            storedPackages.insert(key)
        }
    }

    /// Contents of `url` as text, for assertions that read better than raw `Data`.
    func contents(of url: URL) -> String? {
        lock.withLock { storedFiles[Self.key(for: url)] }.map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - FilesystemService

    func fileExists(at url: URL) -> Bool {
        lock.withLock {
            let key = Self.key(for: url)
            return storedFiles[key] != nil || storedDirectories.contains(key)
        }
    }

    func isDirectory(at url: URL) -> Bool {
        lock.withLock { storedDirectories.contains(Self.key(for: url)) }
    }

    func isPackage(at url: URL) -> Bool {
        lock.withLock { storedPackages.contains(Self.key(for: url)) }
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?
    ) throws -> [URL] {
        try lock.withLock {
            let key = Self.key(for: url)
            guard storedDirectories.contains(key) else { throw Self.noSuchFile(url) }

            let prefix = key == "/" ? "/" : key + "/"
            let children = Array(storedFiles.keys) + Array(storedDirectories)
            let names = children.compactMap { path -> String? in
                guard path != key, path.hasPrefix(prefix) else { return nil }
                // Only immediate children: anything with a further separator sits deeper.
                let remainder = path.dropFirst(prefix.count)
                guard !remainder.contains("/"), !remainder.hasPrefix(".") else { return nil }
                return String(remainder)
            }

            return Set(names).sorted().map { url.appendingPathComponent($0) }
        }
    }

    func fileSize(at url: URL) -> Int? {
        lock.withLock { storedFiles[Self.key(for: url)]?.count }
    }

    func modificationDate(at url: URL) -> Date? {
        lock.withLock { storedModificationDates[Self.key(for: url)] }
    }

    func readFile(at url: URL) throws -> Data {
        try lock.withLock {
            guard let data = storedFiles[Self.key(for: url)] else { throw Self.noSuchFile(url) }
            return data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        lock.withLock {
            let key = Self.key(for: url)
            storedFiles[key] = data
            registerParents(of: key)
        }
    }

    func copyFile(from source: URL, to destination: URL) throws {
        try lock.withLock {
            guard let data = storedFiles[Self.key(for: source)] else { throw Self.noSuchFile(source) }
            let key = Self.key(for: destination)
            storedFiles[key] = data
            registerParents(of: key)
        }
    }

    func replaceFile(at destination: URL, with source: URL) throws {
        try lock.withLock {
            let sourceKey = Self.key(for: source)
            guard let data = storedFiles[sourceKey] else { throw Self.noSuchFile(source) }
            let destinationKey = Self.key(for: destination)
            storedFiles[destinationKey] = data
            // `FileManager.replaceItemAt` consumes the replacement; mirror that here so a
            // test cannot pass against the mock and then fail against the real volume.
            storedFiles[sourceKey] = nil
            registerParents(of: destinationKey)
        }
    }

    @discardableResult
    func trashFile(at url: URL) throws -> URL? {
        try lock.withLock {
            let key = Self.key(for: url)
            guard storedFiles[key] != nil || storedDirectories.contains(key) else {
                throw Self.noSuchFile(url)
            }
            let trashKey = Self.trashDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(url.lastPathComponent)
                .path
            storedTrash[trashKey] = takeSubtree(at: key)
            storedTrashedPaths.append(key)
            return URL(fileURLWithPath: trashKey)
        }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try lock.withLock {
            let sourceKey = Self.key(for: source)
            let destinationKey = Self.key(for: destination)
            guard storedFiles[destinationKey] == nil, !storedDirectories.contains(destinationKey) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: destination])
            }

            let subtree: [String: Data]
            if let trashed = storedTrash.removeValue(forKey: sourceKey) {
                subtree = trashed
            } else {
                guard storedFiles[sourceKey] != nil || storedDirectories.contains(sourceKey) else {
                    throw Self.noSuchFile(source)
                }
                subtree = takeSubtree(at: sourceKey)
            }

            registerDirectory(destinationKey)
            for (relative, data) in subtree {
                let key = relative.isEmpty ? destinationKey : destinationKey + "/" + relative
                if relative.isEmpty { storedDirectories.remove(key) }
                storedFiles[key] = data
                registerParents(of: key)
            }
        }
    }

    func removeItem(at url: URL) throws {
        try lock.withLock {
            let key = Self.key(for: url)
            guard storedFiles[key] != nil || storedDirectories.contains(key) else {
                throw Self.noSuchFile(url)
            }
            let prefix = key + "/"
            storedFiles = storedFiles.filter { $0.key != key && !$0.key.hasPrefix(prefix) }
            storedDirectories = storedDirectories.filter { $0 != key && !$0.hasPrefix(prefix) }
            storedRemovedPaths.append(key)
        }
    }

    func createTemporaryFile(prefix: String, extension fileExtension: String) -> URL {
        let url = Self.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        createDirectory(at: Self.temporaryDirectory)
        return url
    }

    // MARK: - Storage

    /// Where the mock says trashed items went.
    static let trashDirectory = URL(fileURLWithPath: "/mock-trash", isDirectory: true)

    /// Removes the file or folder at `key` and returns every file it held, by path relative
    /// to it; a single file comes back under the empty path.
    private func takeSubtree(at key: String) -> [String: Data] {
        var subtree: [String: Data] = [:]
        if let data = storedFiles.removeValue(forKey: key) {
            subtree[""] = data
        }
        let prefix = key + "/"
        for (path, data) in storedFiles where path.hasPrefix(prefix) {
            subtree[String(path.dropFirst(prefix.count))] = data
            storedFiles[path] = nil
        }
        storedDirectories = storedDirectories.filter { $0 != key && !$0.hasPrefix(prefix) }
        return subtree
    }

    private func registerParents(of key: String) {
        registerDirectory((key as NSString).deletingLastPathComponent)
    }

    private func registerDirectory(_ key: String) {
        var current = key
        while current != "/", !current.isEmpty {
            storedDirectories.insert(current)
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private static func key(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    private static func noSuchFile(_ url: URL) -> Error {
        CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: url])
    }
}
