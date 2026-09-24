//
//  FileSystemServiceTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Snapshot folder reads")
struct FileSystemServiceTests {
    private let service = FileSystemService()

    @Test("Finds image files in nested folders and ignores everything else")
    func findsNestedImages() throws {
        let root = try TemporaryDirectory()
        try root.write("Snapshots/home.png")
        try root.write("Snapshots/iPad/settings.PNG")
        try root.write("Snapshots/notes.txt")
        try root.write("Snapshots/.hidden.png")

        let images = service.imageFiles(under: root.url).map(\.lastPathComponent)

        #expect(images == ["home.png", "settings.PNG"])
    }

    @Test("Sorts results by path so the sidebar order is stable")
    func sortsByPath() throws {
        let root = try TemporaryDirectory()
        for name in ["c.png", "a.png", "b.png"] {
            try root.write(name)
        }

        let images = service.imageFiles(under: root.url).map(\.lastPathComponent)

        #expect(images == ["a.png", "b.png", "c.png"])
    }

    @Test("Distinguishes folders from files")
    func distinguishesFoldersFromFiles() throws {
        let root = try TemporaryDirectory()
        try root.write("home.png")

        #expect(service.isDirectory(at: root.url))
        #expect(!service.isDirectory(at: root.url.appendingPathComponent("home.png")))
        #expect(!service.isDirectory(at: root.url.appendingPathComponent("missing")))
    }

    @Test("Copying creates intermediate folders and replaces an existing file")
    func copyReplacesDestination() throws {
        let root = try TemporaryDirectory()
        let source = try root.write("source.png", contents: "new")
        let destination = root.url.appendingPathComponent("nested/deeper/home.png")
        try root.write("nested/deeper/home.png", contents: "old")

        try service.copyItem(at: source, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
    }
}
