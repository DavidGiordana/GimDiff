//
//  FilesystemServiceTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("In-memory filesystem")
struct MockFilesystemServiceTests {
    private let root = URL(fileURLWithPath: "/repo/Snapshots")

    @Test("Writing a file creates the folders leading to it")
    func writeCreatesIntermediateDirectories() throws {
        let filesystem = MockFilesystemService()
        let file = root.appendingPathComponent("iPad/home.png")

        try filesystem.writeFile(at: file, data: Data("snapshot".utf8))

        #expect(filesystem.fileExists(at: file))
        #expect(filesystem.isDirectory(at: root.appendingPathComponent("iPad")))
        #expect(filesystem.isDirectory(at: root))
        #expect(!filesystem.isDirectory(at: file))
    }

    @Test("Reading back returns exactly what was written")
    func readsBackWrittenBytes() throws {
        let filesystem = MockFilesystemService()
        let file = root.appendingPathComponent("home.png")
        let data = Data([0x89, 0x50, 0x4E, 0x47])

        try filesystem.writeFile(at: file, data: data)

        #expect(try filesystem.readFile(at: file) == data)
    }

    @Test("Reading a file that was never written fails")
    func readingMissingFileThrows() {
        let filesystem = MockFilesystemService()

        #expect(throws: (any Error).self) {
            try filesystem.readFile(at: root.appendingPathComponent("missing.png"))
        }
    }

    @Test("Listing a folder returns its immediate children only")
    func listsImmediateChildren() throws {
        let filesystem = MockFilesystemService()
        try filesystem.writeFile(at: root.appendingPathComponent("home.png"), data: Data())
        try filesystem.writeFile(at: root.appendingPathComponent("settings.png"), data: Data())
        try filesystem.writeFile(at: root.appendingPathComponent("iPad/home.png"), data: Data())

        let names = try filesystem.contentsOfDirectory(at: root).map(\.lastPathComponent)

        #expect(names == ["home.png", "iPad", "settings.png"])
    }

    @Test("Listing a folder that does not exist fails")
    func listingMissingDirectoryThrows() {
        let filesystem = MockFilesystemService()

        #expect(throws: (any Error).self) {
            try filesystem.contentsOfDirectory(at: root)
        }
    }

    @Test("Copying duplicates the bytes and leaves the source in place")
    func copyLeavesSourceInPlace() throws {
        let filesystem = MockFilesystemService()
        let source = root.appendingPathComponent("home.png")
        let destination = root.appendingPathComponent("Archive/home.png")
        filesystem.stub(source, contents: "new")
        filesystem.stub(destination, contents: "old")

        try filesystem.copyFile(from: source, to: destination)

        #expect(filesystem.contents(of: destination) == "new")
        #expect(filesystem.contents(of: source) == "new")
    }

    @Test("Replacing overwrites the destination and consumes the source")
    func replaceConsumesSource() throws {
        let filesystem = MockFilesystemService()
        let destination = root.appendingPathComponent("home.png")
        let replacement = URL(fileURLWithPath: "/mock-tmp/incoming.png")
        filesystem.stub(destination, contents: "committed")
        filesystem.stub(replacement, contents: "accepted")

        try filesystem.replaceFile(at: destination, with: replacement)

        #expect(filesystem.contents(of: destination) == "accepted")
        #expect(!filesystem.fileExists(at: replacement))
    }

    @Test("Replacing works when the destination does not exist yet")
    func replaceCreatesMissingDestination() throws {
        let filesystem = MockFilesystemService()
        let destination = root.appendingPathComponent("brand-new.png")
        let replacement = URL(fileURLWithPath: "/mock-tmp/incoming.png")
        filesystem.stub(replacement, contents: "accepted")

        try filesystem.replaceFile(at: destination, with: replacement)

        #expect(filesystem.contents(of: destination) == "accepted")
    }

    @Test("Trashing removes the file and records the path")
    func trashRemovesFile() throws {
        let filesystem = MockFilesystemService()
        let file = root.appendingPathComponent("home.png")
        filesystem.stub(file, contents: "snapshot")

        try filesystem.trashFile(at: file)

        #expect(!filesystem.fileExists(at: file))
        #expect(filesystem.trashedPaths == ["/repo/Snapshots/home.png"])
    }

    @Test("The default walk finds images in nested folders and ignores everything else")
    func findsNestedImages() throws {
        let filesystem = MockFilesystemService()
        try filesystem.writeFile(at: root.appendingPathComponent("home.png"), data: Data())
        try filesystem.writeFile(at: root.appendingPathComponent("iPad/settings.PNG"), data: Data())
        try filesystem.writeFile(at: root.appendingPathComponent("notes.txt"), data: Data())
        try filesystem.writeFile(at: root.appendingPathComponent(".hidden.png"), data: Data())

        let images = filesystem.imageFiles(under: root).map(\.lastPathComponent)

        #expect(images == ["home.png", "settings.PNG"])
    }

    @Test("The default walk sorts by path so the sidebar order is stable")
    func sortsImagesByPath() throws {
        let filesystem = MockFilesystemService()
        for name in ["c.png", "a.png", "iPad/b.png"] {
            try filesystem.writeFile(at: root.appendingPathComponent(name), data: Data())
        }

        let images = filesystem.imageFiles(under: root).map(\.lastPathComponent)

        #expect(images == ["a.png", "c.png", "b.png"])
    }

    @Test("A folder holding no images yields none")
    func findsNoImagesInATextOnlyFolder() throws {
        let filesystem = MockFilesystemService()
        try filesystem.writeFile(at: root.appendingPathComponent("README.md"), data: Data())

        #expect(filesystem.imageFiles(under: root).isEmpty)
    }

    @Test("Temporary paths are unique and sit in a folder that exists")
    func temporaryPathsAreUnique() {
        let filesystem = MockFilesystemService()

        let first = filesystem.createTemporaryFile(prefix: "home", extension: "png")
        let second = filesystem.createTemporaryFile(prefix: "home", extension: "png")

        #expect(first != second)
        #expect(first.pathExtension == "png")
        #expect(first.lastPathComponent.hasPrefix("home-"))
        #expect(filesystem.isDirectory(at: first.deletingLastPathComponent()))
        #expect(!filesystem.fileExists(at: first))
    }
}

@Suite("FileManager-backed filesystem")
struct DefaultFilesystemServiceTests {
    private let filesystem = DefaultFilesystemService()

    @Test("Writes, reads, and distinguishes folders from files")
    func writesAndReads() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("nested/home.png")

        try filesystem.writeFile(at: file, data: Data("snapshot".utf8))

        #expect(filesystem.fileExists(at: file))
        #expect(filesystem.isDirectory(at: root.url.appendingPathComponent("nested")))
        #expect(!filesystem.isDirectory(at: file))
        #expect(try filesystem.readFile(at: file) == Data("snapshot".utf8))
    }

    @Test("Listing a folder skips hidden entries")
    func listsVisibleChildren() throws {
        let root = try TemporaryDirectory()
        try root.write("home.png")
        try root.write(".hidden.png")

        let names = try filesystem.contentsOfDirectory(at: root.url).map(\.lastPathComponent)

        #expect(names == ["home.png"])
    }

    @Test("Copying replaces an existing destination")
    func copyReplacesDestination() throws {
        let root = try TemporaryDirectory()
        let source = try root.write("source.png", contents: "new")
        let destination = try root.write("nested/home.png", contents: "old")

        try filesystem.copyFile(from: source, to: destination)

        #expect(try filesystem.readFile(at: destination) == Data("new".utf8))
        #expect(filesystem.fileExists(at: source))
    }

    @Test("Replacing swaps the file in and removes the replacement")
    func replaceConsumesSource() throws {
        let root = try TemporaryDirectory()
        let destination = try root.write("home.png", contents: "committed")
        let replacement = try root.write("incoming.png", contents: "accepted")

        try filesystem.replaceFile(at: destination, with: replacement)

        #expect(try filesystem.readFile(at: destination) == Data("accepted".utf8))
        #expect(!filesystem.fileExists(at: replacement))
    }

    @Test("Replacing a destination that does not exist yet still lands the file")
    func replaceCreatesMissingDestination() throws {
        let root = try TemporaryDirectory()
        let destination = root.url.appendingPathComponent("brand-new.png")
        let replacement = try root.write("incoming.png", contents: "accepted")

        try filesystem.replaceFile(at: destination, with: replacement)

        #expect(try filesystem.readFile(at: destination) == Data("accepted".utf8))
    }

    @Test("Finds image files in nested folders and ignores everything else")
    func findsNestedImages() throws {
        let root = try TemporaryDirectory()
        try root.write("Snapshots/home.png")
        try root.write("Snapshots/iPad/settings.PNG")
        try root.write("Snapshots/notes.txt")
        try root.write("Snapshots/.hidden.png")

        let images = filesystem.imageFiles(under: root.url).map(\.lastPathComponent)

        #expect(images == ["home.png", "settings.PNG"])
    }

    @Test("Sorts results by path so the sidebar order is stable")
    func sortsImagesByPath() throws {
        let root = try TemporaryDirectory()
        for name in ["c.png", "a.png", "b.png"] {
            try root.write(name)
        }

        let images = filesystem.imageFiles(under: root.url).map(\.lastPathComponent)

        #expect(images == ["a.png", "b.png", "c.png"])
    }

    @Test("Package contents are left alone rather than mined for images")
    func skipsPackageDescendants() throws {
        let root = try TemporaryDirectory()
        try root.write("home.png")
        try root.write("Helper.app/Contents/Resources/icon.png")

        let images = filesystem.imageFiles(under: root.url).map(\.lastPathComponent)

        #expect(images == ["home.png"])
    }

    @Test("Temporary paths are unique, unused, and inside an existing folder")
    func temporaryPathsAreUsable() throws {
        let first = filesystem.createTemporaryFile(prefix: "home", extension: "png")
        let second = filesystem.createTemporaryFile(prefix: "home", extension: "png")

        #expect(first != second)
        #expect(!filesystem.fileExists(at: first))
        #expect(filesystem.isDirectory(at: first.deletingLastPathComponent()))

        try filesystem.writeFile(at: first, data: Data("snapshot".utf8))
        defer { try? FileManager.default.removeItem(at: first) }

        #expect(try filesystem.readFile(at: first) == Data("snapshot".utf8))
    }
}
