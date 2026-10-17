//
//  ComparisonImageRendererTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GimDiff

/// Drawing Split View and the onion skin as one picture for the clipboard.
@Suite("Comparison image")
struct ComparisonImageRendererTests {
    private let caption = ComparisonCaption(leftTitle: "Baseline", rightTitle: "Candidate", detail: "home")
    private let red: [UInt8] = [255, 0, 0]
    private let blue: [UInt8] = [0, 0, 255]

    // MARK: - Layout

    @Test("Two images of one size fill the same frame")
    func sameSizeLayout() {
        let layout = ComparisonImageRenderer.layout(
            left: CGSize(width: 100, height: 200),
            right: CGSize(width: 100, height: 200)
        )

        #expect(layout.canvasSize == CGSize(width: 100, height: 200))
        #expect(layout.leftRect == CGRect(x: 0, y: 0, width: 100, height: 200))
        #expect(layout.rightRect == layout.leftRect)
    }

    @Test("A smaller image sits unscaled in the top-left corner of the larger one's frame")
    func mixedSizeLayout() {
        let layout = ComparisonImageRenderer.layout(
            left: CGSize(width: 100, height: 200),
            right: CGSize(width: 50, height: 50)
        )

        #expect(layout.canvasSize == CGSize(width: 100, height: 200))
        #expect(layout.rightRect == CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(layout.imageBounds == CGRect(x: 0, y: 0, width: 100, height: 200))
    }

    @Test("A wider image and a taller one share a frame as large as both")
    func crossedSizeLayout() {
        let layout = ComparisonImageRenderer.layout(
            left: CGSize(width: 100, height: 50),
            right: CGSize(width: 50, height: 100)
        )

        #expect(layout.canvasSize == CGSize(width: 100, height: 100))
        #expect(layout.leftRect == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(layout.rightRect == CGRect(x: 0, y: 0, width: 50, height: 100))
    }

    @Test("A part of the canvas lands where the fitted canvas puts it")
    func fitsARectIntoTheView() {
        let layout = ComparisonImageRenderer.layout(
            left: CGSize(width: 100, height: 200),
            right: CGSize(width: 100, height: 100)
        )

        // The canvas fits a 400 × 400 view at 2×, centred across.
        #expect(layout.rect(layout.leftRect, fittedIn: CGSize(width: 400, height: 400)) == CGRect(x: 100, y: 0, width: 200, height: 400))
        #expect(layout.rect(layout.rightRect, fittedIn: CGSize(width: 400, height: 400)) == CGRect(x: 100, y: 0, width: 200, height: 200))
    }

    @Test("The split is a fraction of the images' width, kept inside it")
    func splitPosition() {
        let layout = ComparisonImageRenderer.Layout(
            canvasSize: CGSize(width: 300, height: 100),
            leftRect: CGRect(x: 100, y: 0, width: 100, height: 100),
            rightRect: CGRect(x: 100, y: 0, width: 100, height: 100)
        )

        #expect(ComparisonImageRenderer.splitX(at: 0, in: layout) == 100)
        #expect(ComparisonImageRenderer.splitX(at: 0.25, in: layout) == 125)
        #expect(ComparisonImageRenderer.splitX(at: 1, in: layout) == 200)
        #expect(ComparisonImageRenderer.splitX(at: 2, in: layout) == 200)
    }

    // MARK: - Rendering

    @Test("The split shows the left image before the divider and the right one after it")
    func splitDrawsBothSides() throws {
        let image = try #require(ComparisonImageRenderer.split(
            left: try solid(red),
            right: try solid(blue),
            position: 0.5,
            backdrop: nil,
            matte: nil,
            caption: caption
        ))
        let pixels = try Pixels(image)

        #expect(image.width == 200)
        #expect(image.height == 100 + Int(ComparisonImageRenderer.captionHeight(forWidth: 200)))
        #expect(pixels.rgb(x: 40, y: 50) == red)
        #expect(pixels.rgb(x: 160, y: 50) == blue)
    }

    @Test("A split at the far left shows only the right image")
    func splitAtTheEdge() throws {
        let image = try #require(ComparisonImageRenderer.split(
            left: try solid(red),
            right: try solid(blue),
            position: 0,
            backdrop: nil,
            matte: nil,
            caption: caption
        ))
        let pixels = try Pixels(image)

        #expect(pixels.rgb(x: 40, y: 50) == blue)
    }

    @Test("The onion skin shows the lower image, the upper one, or a blend, as faded")
    func onionSkinFades() throws {
        func centre(at opacity: Double) throws -> [UInt8] {
            let image = try #require(ComparisonImageRenderer.onionSkin(
                under: try solid(red),
                over: try solid(blue),
                rightOpacity: opacity,
                backdrop: nil,
                matte: nil,
                caption: caption
            ))
            return try Pixels(image).rgb(x: 100, y: 50)
        }

        #expect(try centre(at: 0) == red)
        #expect(try centre(at: 1) == blue)
        let blended = try centre(at: 0.5)
        #expect((120...135).contains(blended[0]))
        #expect((120...135).contains(blended[2]))
    }

    @Test("A shorter image is drawn from the top, over the top of the taller one")
    func onionSkinAlignsMismatchedSizesTopLeft() throws {
        let image = try #require(ComparisonImageRenderer.onionSkin(
            under: try solid(red, width: 200, height: 100),
            over: try solid(blue, width: 200, height: 50),
            rightOpacity: 1,
            backdrop: nil,
            matte: nil,
            caption: caption
        ))
        let pixels = try Pixels(image)

        #expect(image.width == 200)
        #expect(pixels.rgb(x: 100, y: 20) == blue)
        #expect(pixels.rgb(x: 100, y: 80) == red)
    }

    @Test("The caption strip sits under the images, dark, and the picture encodes as PNG")
    func captionAndPNG() throws {
        let image = try #require(ComparisonImageRenderer.onionSkin(
            under: try solid(red),
            over: try solid(blue),
            rightOpacity: 0,
            backdrop: nil,
            matte: nil,
            caption: caption
        ))
        let pixels = try Pixels(image)
        // The middle of the strip, between the left title and the detail.
        let stripRow = image.height - Int(ComparisonImageRenderer.captionHeight(forWidth: 200)) / 2
        let strip = pixels.rgb(x: 60, y: stripRow)
        #expect(strip.allSatisfy { $0 < 80 })

        let png = try #require(ComparisonImageRenderer.pngData(image))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == image.width)
        #expect(decoded.height == image.height)
    }

    // MARK: - Fixtures

    /// A 200 × 100 opaque image of one colour.
    private func solid(_ rgb: [UInt8], width: Int = 200, height: Int = 100) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            bytes[offset] = rgb[0]
            bytes[offset + 1] = rgb[1]
            bytes[offset + 2] = rgb[2]
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    /// An image's pixels, read top row first.
    private struct Pixels {
        let bytes: [UInt8]
        let width: Int

        init(_ image: CGImage) throws {
            width = image.width
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            try buffer.withUnsafeMutableBytes { raw in
                let context = try #require(CGContext(
                    data: raw.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            bytes = buffer
        }

        func rgb(x: Int, y: Int) -> [UInt8] {
            let offset = (y * width + x) * 4
            return Array(bytes[offset..<offset + 3])
        }
    }
}
