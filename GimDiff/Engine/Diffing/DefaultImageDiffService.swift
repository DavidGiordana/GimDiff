//
//  DefaultImageDiffService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ``ImageDiffService`` that compares two snapshots byte for byte in a flat RGBA buffer.
///
/// Both images are redrawn into contexts GimDiff owns rather than being read in whatever
/// layout their encoder chose. That normalisation is what makes the comparison a single
/// pass over two byte arrays: colour space, component order, row padding, and premultiplied
/// alpha all match by construction, so a `!=` on four bytes is a genuine pixel difference
/// rather than an artefact of how the two files happened to be written.
struct DefaultImageDiffService: ImageDiffService {
    /// Bytes each pixel occupies in the comparison buffers: 8-bit RGBA.
    static let bytesPerPixel = 4
    /// How much of its original brightness an unchanged pixel keeps in the mask.
    ///
    /// Dark enough that the highlight colour dominates at a glance, bright enough that the
    /// shape of the snapshot still shows through and locates the change.
    static let unchangedPixelBrightness = 0.35
    /// How many rows the comparison runs between looks at whether it is still wanted.
    static let rowsBetweenCancellationChecks = 64

    /// Rec. 601 luma weights, used to flatten an unchanged pixel to grey.
    private static let lumaWeights = (red: 0.299, green: 0.587, blue: 0.114)

    private let filesystem: any FilesystemService

    init(filesystem: any FilesystemService) {
        self.filesystem = filesystem
    }

    @concurrent
    func compare(
        candidateURL: URL,
        baselineURL: URL,
        diffColor: CGColor,
        tolerance: DiffTolerance
    ) async throws -> ImageDiffReport {
        let candidate = try Self.loadImage(at: candidateURL)
        let baseline = try Self.loadImage(at: baselineURL)

        let candidateSize = CGSize(width: candidate.width, height: candidate.height)
        let baselineSize = CGSize(width: baseline.width, height: baseline.height)

        guard candidate.width == baseline.width, candidate.height == baseline.height else {
            // Differently sized images share no pixel grid, so there is nothing to count and
            // no mask to draw: the whole comparison is the mismatch.
            let pixels = candidate.width * candidate.height
            return ImageDiffReport(
                candidateSize: candidateSize,
                baselineSize: baselineSize,
                hasIdenticalDimensions: false,
                differentPixelCount: pixels,
                totalPixelCount: pixels,
                diffPercentage: 100.0
            )
        }

        let width = candidate.width
        let height = candidate.height
        let byteCount = width * height * Self.bytesPerPixel

        let candidateContext = try Self.bitmapContext(rendering: candidate, at: candidateURL)
        let baselineContext = try Self.bitmapContext(rendering: baseline, at: baselineURL)
        guard let maskContext = Self.bitmapContext(width: width, height: height),
              let candidatePixels = candidateContext.data?.assumingMemoryBound(to: UInt8.self),
              let baselinePixels = baselineContext.data?.assumingMemoryBound(to: UInt8.self),
              let maskPixels = maskContext.data?.assumingMemoryBound(to: UInt8.self)
        else { throw GimDiffError.imageProcessingFailed(candidateURL) }

        let highlight = Self.components(of: diffColor)
        var differentPixelCount = 0
        var toleratedPixelCount = 0
        var maximumDeltaE = 0.0

        // Checked every so many rows: stepping through snapshots supersedes a comparison
        // long before a large one is done, and nothing would want the rest of its answer.
        let pixelsBetweenChecks = width * Self.rowsBetweenCancellationChecks
        var pixelsUntilCheck = 0
        for offset in stride(from: 0, to: byteCount, by: Self.bytesPerPixel) {
            if pixelsUntilCheck == 0 {
                try Task.checkCancellation()
                pixelsUntilCheck = pixelsBetweenChecks
            }
            pixelsUntilCheck -= 1
            var differs = candidatePixels[offset] != baselinePixels[offset]
                || candidatePixels[offset + 1] != baselinePixels[offset + 1]
                || candidatePixels[offset + 2] != baselinePixels[offset + 2]
                || candidatePixels[offset + 3] != baselinePixels[offset + 3]

            // The distance is measured only where the bytes moved, which in a snapshot is
            // almost nowhere, so the colour maths costs nothing on a matching image.
            if differs {
                let distance = Self.perceptualDistance(
                    Self.pixel(candidatePixels, at: offset),
                    Self.pixel(baselinePixels, at: offset)
                )
                maximumDeltaE = max(maximumDeltaE, distance)
                if !tolerance.isExact, distance <= tolerance.maximumDeltaE {
                    differs = false
                    toleratedPixelCount += 1
                }
            }

            if differs {
                differentPixelCount += 1
                maskPixels[offset] = highlight.red
                maskPixels[offset + 1] = highlight.green
                maskPixels[offset + 2] = highlight.blue
                maskPixels[offset + 3] = highlight.alpha
            } else {
                let grey = Self.dimmedGrey(
                    red: candidatePixels[offset],
                    green: candidatePixels[offset + 1],
                    blue: candidatePixels[offset + 2]
                )
                maskPixels[offset] = grey
                maskPixels[offset + 1] = grey
                maskPixels[offset + 2] = grey
                maskPixels[offset + 3] = UInt8.max
            }
        }

        let totalPixelCount = width * height
        return ImageDiffReport(
            candidateSize: candidateSize,
            baselineSize: baselineSize,
            hasIdenticalDimensions: true,
            differentPixelCount: differentPixelCount,
            totalPixelCount: totalPixelCount,
            diffPercentage: Self.percentage(of: differentPixelCount, in: totalPixelCount),
            diffMaskURL: try writeMask(from: maskContext, for: candidateURL),
            toleratedPixelCount: toleratedPixelCount,
            maximumDeltaE: maximumDeltaE
        )
    }

    /// Share of a grid that differs, guarding the empty image rather than dividing by zero.
    static func percentage(of differentPixels: Int, in totalPixels: Int) -> Double {
        guard totalPixels > 0 else { return 0.0 }
        return (Double(differentPixels) / Double(totalPixels)) * 100.0
    }

    // MARK: - Perceptual distance

    /// One premultiplied RGBA pixel of a comparison buffer.
    typealias Pixel = (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)

    private static func pixel(_ buffer: UnsafeMutablePointer<UInt8>, at offset: Int) -> Pixel {
        (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
    }

    /// How visibly two pixels differ, as a ΔE: black against white is 100, and two
    /// saturated colours can be further apart still.
    ///
    /// The colour distance is CIE76 ΔE between the two premultiplied pixels, which is each
    /// one composited over black. Transparency is not a colour Lab can describe, so a change
    /// in alpha is scaled so that a fully opaque pixel turning fully transparent is 100, as
    /// far as black is from white, and the larger of the two wins.
    static func perceptualDistance(_ first: Pixel, _ second: Pixel) -> Double {
        let lab1 = lab(first)
        let lab2 = lab(second)
        let deltaE = sqrt(
            (lab1.l - lab2.l) * (lab1.l - lab2.l)
                + (lab1.a - lab2.a) * (lab1.a - lab2.a)
                + (lab1.b - lab2.b) * (lab1.b - lab2.b)
        )
        let deltaAlpha = abs(Double(first.alpha) - Double(second.alpha)) / 255.0 * 100.0
        return max(deltaE, deltaAlpha)
    }

    /// Each 8-bit sRGB value with the transfer curve undone, so the conversion to Lab is a
    /// table lookup rather than a `pow` per channel per pixel.
    private static let linearComponents: [Double] = (0...255).map { byte in
        let value = Double(byte) / 255.0
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// The pixel in CIE L*a*b*, against the D65 white sRGB is defined for.
    private static func lab(_ pixel: Pixel) -> (l: Double, a: Double, b: Double) {
        let red = linearComponents[Int(pixel.red)]
        let green = linearComponents[Int(pixel.green)]
        let blue = linearComponents[Int(pixel.blue)]

        let x = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047
        let y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
        let z = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883

        let fx = labCurve(x)
        let fy = labCurve(y)
        let fz = labCurve(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func labCurve(_ t: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        return t > epsilon ? cbrt(t) : (kappa * t + 16) / 116
    }

    // MARK: - Mask

    /// Encodes the mask as a PNG in a scratch directory and returns where it landed.
    private func writeMask(from context: CGContext, for candidateURL: URL) throws -> URL {
        guard let image = context.makeImage(), let data = Self.encodePNG(image) else {
            throw GimDiffError.imageProcessingFailed(candidateURL)
        }

        let destination = filesystem.createTemporaryFile(
            prefix: "\(candidateURL.deletingPathExtension().lastPathComponent)-diff",
            extension: ImageFormat.png.fileExtension
        )
        try filesystem.writeFile(at: destination, data: data)
        return destination
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        guard let buffer = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  buffer,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    // MARK: - Pixels

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GimDiffError.unreadableImage(url) }
        return image
    }

    /// A zeroed 8-bit RGBA context whose rows carry no padding.
    ///
    /// Unpadded rows are what let the comparison treat the buffer as one flat run of pixels
    /// instead of walking it row by row around the gaps.
    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }

        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func bitmapContext(rendering image: CGImage, at url: URL) throws -> CGContext {
        guard let context = bitmapContext(width: image.width, height: image.height) else {
            throw GimDiffError.imageProcessingFailed(url)
        }

        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return context
    }

    /// Flattens a pixel to grey and darkens it, so unchanged content reads as a backdrop.
    private static func dimmedGrey(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let luma = lumaWeights.red * Double(red)
            + lumaWeights.green * Double(green)
            + lumaWeights.blue * Double(blue)
        return UInt8((luma * unchangedPixelBrightness).rounded().clamped(to: 0...255))
    }

    /// The highlight colour as premultiplied sRGB bytes, matching the mask's layout.
    ///
    /// Falls back to opaque magenta for a colour in an exotic space that will not convert,
    /// because a mask drawn in the wrong colour still shows where the change is, and one
    /// never drawn at all does not.
    static func components(of color: CGColor) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 4
        else { return (255, 0, 127, 255) }

        let alpha = components[3]
        return (
            byte(components[0] * alpha),
            byte(components[1] * alpha),
            byte(components[2] * alpha),
            byte(alpha)
        )
    }

    private static func byte(_ value: CGFloat) -> UInt8 {
        UInt8((Double(value) * 255.0).rounded().clamped(to: 0...255))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
