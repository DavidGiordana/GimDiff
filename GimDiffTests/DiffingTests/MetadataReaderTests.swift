//
//  MetadataReaderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Snapshot metadata")
struct MetadataReaderTests {
    private let reader = MetadataReader()

    @Test("Reads the pixel dimensions of an image")
    func readsDimensions() throws {
        let metadata = try reader.metadata(for: ImageFixtures.identicalA)

        #expect(metadata.pixelWidth == 100)
        #expect(metadata.pixelHeight == 100)
    }

    @Test("A non-square image keeps width and height apart")
    func readsNonSquareDimensions() throws {
        let metadata = try reader.metadata(for: ImageFixtures.mismatchedDimensions)

        #expect(metadata.pixelWidth == 100)
        #expect(metadata.pixelHeight == 150)
    }

    @Test("An unmarked image is read at 1x")
    func defaultsToUnscaled() throws {
        let metadata = try reader.metadata(for: ImageFixtures.identicalA)

        #expect(metadata.scaleFactor == 1.0)
        #expect(metadata.pointWidth == 100)
    }

    @Test("@2x in the file name is read as a 2x backing store")
    func readsDoubleScaleFromName() throws {
        let metadata = try reader.metadata(for: ImageFixtures.retina2x)

        #expect(metadata.pixelWidth == 200)
        #expect(metadata.scaleFactor == 2.0)
        #expect(metadata.pointWidth == 100)
        #expect(metadata.pointHeight == 100)
    }

    @Test("@3x in the file name is read as a 3x backing store")
    func readsTripleScaleFromName() throws {
        let metadata = try reader.metadata(for: ImageFixtures.retina3x)

        #expect(metadata.pixelWidth == 300)
        #expect(metadata.scaleFactor == 3.0)
        #expect(metadata.pointWidth == 100)
    }

    @Test("A 144 DPI image with no marked name is read as 2x")
    func readsScaleFromResolution() throws {
        let metadata = try reader.metadata(for: ImageFixtures.dense144DPI)

        #expect(metadata.scaleFactor == 2.0)
        #expect(metadata.pointWidth == 50)
    }

    @Test("Only a resolution that is a whole 2x or 3x of 72 DPI counts as a scale")
    func readsScaleFromKnownResolutionsOnly() {
        #expect(MetadataReader.scaleFactor(fromDPI: 144) == 2.0)
        #expect(MetadataReader.scaleFactor(fromDPI: 216) == 3.0)
        // A pHYs chunk stores pixels per metre, so a round DPI comes back a hair off.
        #expect(MetadataReader.scaleFactor(fromDPI: 143.99) == 2.0)
        #expect(MetadataReader.scaleFactor(fromDPI: 72) == nil)
        #expect(MetadataReader.scaleFactor(fromDPI: 150) == nil)
        #expect(MetadataReader.scaleFactor(fromDPI: 288) == nil)
        #expect(MetadataReader.scaleFactor(fromDPI: 0) == nil)
    }

    @Test("Only @2x and @3x are read off a name")
    func readsKnownSuffixesOnly() {
        #expect(MetadataReader.scaleFactor(forFileNamed: "home@2x") == 2.0)
        #expect(MetadataReader.scaleFactor(forFileNamed: "home@3x") == 3.0)
        #expect(MetadataReader.scaleFactor(forFileNamed: "home@4x") == nil)
        #expect(MetadataReader.scaleFactor(forFileNamed: "home") == nil)
        #expect(MetadataReader.scaleFactor(forFileNamed: "home@2x_old") == nil)
    }

    @Test("The format comes from the file extension")
    func readsFormat() throws {
        let metadata = try reader.metadata(for: ImageFixtures.identicalA)

        #expect(metadata.format == .png)
    }

    @Test("The size on disk is reported")
    func readsFileSize() throws {
        let metadata = try reader.metadata(for: ImageFixtures.identicalA)
        let onDisk = try #require(
            try FileManager.default.attributesOfItem(
                atPath: ImageFixtures.identicalA.path
            )[.size] as? Int64
        )

        #expect(metadata.fileSizeBytes == onDisk)
    }

    @Test("A file that is not there is reported as unreadable")
    func rejectsMissingFile() {
        #expect(throws: GimDiffError.unreadableImage(ImageFixtures.missing)) {
            try reader.metadata(for: ImageFixtures.missing)
        }
    }

    @Test("A file that is not an image is reported as unreadable")
    func rejectsNonImage() throws {
        let directory = try TemporaryDirectory()
        let text = try directory.write("notes.png", contents: "this is not a PNG")

        #expect(throws: GimDiffError.unreadableImage(text)) {
            try reader.metadata(for: text)
        }
    }
}
