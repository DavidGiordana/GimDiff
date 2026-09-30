//
//  ImageFormatSniffingTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Image format from leading bytes")
struct ImageFormatSniffingTests {
    @Test("A checked-in PNG is recognised from its contents")
    func recognisesRealPNG() throws {
        let data = try Data(contentsOf: ImageFixtures.identicalA)

        #expect(ImageFormat(sniffing: data) == .png)
    }

    @Test("JPEG and WebP are recognised by their signatures")
    func recognisesOtherSignatures() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let webp = Data("RIFF".utf8) + Data([0x24, 0x00, 0x00, 0x00]) + Data("WEBPVP8 ".utf8)

        #expect(ImageFormat(sniffing: jpeg) == .jpg)
        #expect(ImageFormat(sniffing: webp) == .webp)
    }

    @Test("Anything else is not an image, whatever it would be called")
    func rejectsEverythingElse() {
        let wave = Data("RIFF".utf8) + Data([0x24, 0x00, 0x00, 0x00]) + Data("WAVEfmt ".utf8)

        #expect(ImageFormat(sniffing: Data()) == nil)
        #expect(ImageFormat(sniffing: Data("failed - Snapshot does not match".utf8)) == nil)
        #expect(ImageFormat(sniffing: Data([0x89, 0x50])) == nil)
        #expect(ImageFormat(sniffing: wave) == nil)
    }

    @Test("A slice is read from its own start")
    func readsSlices() {
        let padded = Data([0x00, 0x00]) + Data([0xFF, 0xD8, 0xFF, 0xE0])

        #expect(ImageFormat(sniffing: padded.dropFirst(2)) == .jpg)
    }
}
