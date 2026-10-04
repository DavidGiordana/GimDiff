//
//  ImagePixelsTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GimDiff

@Suite("Decoding an image to its pixels")
struct ImagePixelsTests {
    /// `url`'s image written again by ImageIO, with a resolution the original does not
    /// carry: the same picture in other bytes, the way a second encoder writes it.
    static func reencoded(_ url: URL) throws -> Data {
        struct Unencodable: Error {}

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let buffer = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil)
        else { throw Unencodable() }

        let properties = [kCGImagePropertyDPIWidth: 216, kCGImagePropertyDPIHeight: 216] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw Unencodable() }
        return buffer as Data
    }

    @Test("The same picture in other bytes decodes to the same pixels")
    func ignoresEncoding() throws {
        let original = try Data(contentsOf: ImageFixtures.identicalA)
        let reencoded = try Self.reencoded(ImageFixtures.identicalA)
        #expect(original != reencoded)

        let pixels = try #require(ImagePixels(decoding: original))
        #expect(ImagePixels(decoding: reencoded) == pixels)
        #expect(pixels.width == 100)
        #expect(pixels.height == 100)
    }

    @Test("Pictures one square apart decode to different pixels")
    func tellsPicturesApart() throws {
        let before = ImagePixels(decoding: try Data(contentsOf: ImageFixtures.modifiedA))
        let after = ImagePixels(decoding: try Data(contentsOf: ImageFixtures.modifiedB))

        #expect(before != nil)
        #expect(before != after)
    }

    @Test("Bytes that are not an image decode to nothing")
    func rejectsNonImage() {
        #expect(ImagePixels(decoding: Data("not an image".utf8)) == nil)
    }
}
