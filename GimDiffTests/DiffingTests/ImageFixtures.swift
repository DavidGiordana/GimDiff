//
//  ImageFixtures.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO

/// The checked-in images the diffing tests measure against.
///
/// Located through `#filePath` rather than through `Bundle`, so the images are found whether
/// or not the synchronized folder decides to copy them into the test bundle, and so a
/// failure points at the file on disk that produced it.
enum ImageFixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("Images", isDirectory: true)

    /// 100 × 100, and byte-for-byte the same as ``identicalB``.
    static let identicalA = url("identical_a.png")
    static let identicalB = url("identical_b.png")
    /// 100 × 100. ``modifiedB`` repaints a 10 × 10 square of ``modifiedA`` red, so exactly
    /// 100 of the 10,000 pixels differ: 1% on the nose.
    static let modifiedA = url("modified_a.png")
    static let modifiedB = url("modified_b.png")
    /// 100 × 150, to pair against a 100 × 100 image.
    static let mismatchedDimensions = url("mismatched_dimensions.png")
    /// 200 × 200 and 300 × 300, named the way Apple's conventions mark a backing-store scale.
    static let retina2x = url("retina@2x.png")
    static let retina3x = url("retina@3x.png")
    /// 100 × 100, carrying a 144 DPI resolution and nothing in its name.
    static let dense144DPI = url("dense_144dpi.png")
    /// A path with no file behind it.
    static let missing = url("no_such_image.png")

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// One pixel of an image on disk, as straight 8-bit RGBA.
    ///
    /// Reading the mask back is the only way to assert it was actually painted: the report
    /// says how many pixels differ, not what was drawn where.
    static func pixel(atX x: Int, y: Int, in url: URL) throws -> [UInt8] {
        struct UnreadablePixel: Error {}

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw UnreadablePixel() }

        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: 1,
                      height: 1,
                      bitsPerComponent: 8,
                      bytesPerRow: 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }

            // Shifting the whole image so the wanted pixel lands in the 1 × 1 context. The
            // y axis is flipped because Core Graphics counts rows from the bottom.
            context.draw(
                image,
                in: CGRect(
                    x: -CGFloat(x),
                    y: -CGFloat(image.height - y - 1),
                    width: CGFloat(image.width),
                    height: CGFloat(image.height)
                )
            )
            return true
        }

        guard drawn else { throw UnreadablePixel() }
        return pixel
    }
}
