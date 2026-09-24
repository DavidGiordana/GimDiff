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
    private var storedTrashedPaths: [String] = []

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

    func createDirectory(at url: URL) {
        lock.withLock { registerDirectory(Self.key(for: url)) }
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

    func trashFile(at url: URL) throws {
        try lock.withLock {
            let key = Self.key(for: url)
            guard storedFiles[key] != nil || storedDirectories.contains(key) else {
                throw Self.noSuchFile(url)
            }
            storedFiles[key] = nil
            storedDirectories.remove(key)
            storedTrashedPaths.append(key)
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
