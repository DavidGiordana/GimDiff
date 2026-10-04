//
//  ImagePixels.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO

/// What an encoded image looks like, independent of how it was encoded.
///
/// Two files can hold the same picture in different bytes: another encoder, another
/// compression level, an alpha channel added or dropped, metadata written or not. Drawing
/// both into the same 8-bit premultiplied sRGB layout removes every one of those, so equal
/// pixels here are the same picture.
struct ImagePixels: Sendable, Equatable {
    let width: Int
    let height: Int
    /// A hash of the normalised pixels, for comparing many images against one without
    /// keeping any of their buffers.
    let digest: Int

    /// `nil` when `data` is not an image ImageIO can decode.
    init?(decoding data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return nil }

        var hasher = Hasher()
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(bytes: UnsafeRawBufferPointer(start: pixels, count: bytesPerRow * height))

        self.width = width
        self.height = height
        digest = hasher.finalize()
    }
}
