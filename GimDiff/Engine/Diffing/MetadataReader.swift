//
//  MetadataReader.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import ImageIO

/// Reads the physical properties of a snapshot without decoding it.
protocol MetadataReading: Sendable {
    /// Properties of the image at `url`.
    ///
    /// - Throws: ``GimDiffError/unreadableImage(_:)`` when the file is missing or is not
    ///   an image any installed decoder understands.
    func metadata(for url: URL) throws -> SnapshotMetadata
}

/// ``MetadataReading`` backed by ImageIO.
///
/// The header alone answers every question here, so the reader asks `CGImageSource` for
/// properties and never for pixels. A folder of 4K snapshots costs a few kilobytes of
/// reads instead of a few gigabytes of decoded bitmaps.
struct MetadataReader: MetadataReading {
    /// Points per inch a `1.0` scale image is stored at.
    static let baseDPI = 72.0

    /// Suffixes Apple's naming convention uses to mark a backing-store scale.
    private static let scaleSuffixes: [(suffix: String, scale: Double)] = [
        ("@2x", 2.0),
        ("@3x", 3.0),
    ]

    init() {}

    func metadata(for url: URL) throws -> SnapshotMetadata {
        // `shouldCache: false` keeps ImageIO from holding a decoded copy of an image the
        // caller only wanted the dimensions of.
        let options = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
                as? [CFString: Any]
        else { throw GimDiffError.unreadableImage(url) }

        guard let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw GimDiffError.unreadableImage(url) }

        return SnapshotMetadata(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scaleFactor: Self.scaleFactor(for: url, properties: properties),
            fileSizeBytes: Self.fileSizeBytes(of: url),
            format: ImageFormat(url: url)
        )
    }

    // MARK: - Scale

    /// The scale a snapshot was rendered at.
    ///
    /// The file name wins over the stored resolution: `@2x` is a deliberate statement by
    /// the test that recorded the image, while DPI is whatever the encoder happened to
    /// write, and the two disagree often enough that guessing from DPI first would mislabel
    /// ordinary `@2x` snapshots saved at 72 DPI.
    static func scaleFactor(for url: URL, properties: [CFString: Any]) -> Double {
        if let named = scaleFactor(forFileNamed: url.deletingPathExtension().lastPathComponent) {
            return named
        }

        let stored = properties[kCGImagePropertyDPIWidth] as? Double
            ?? properties[kCGImagePropertyDPIHeight] as? Double
        return stored.flatMap(scaleFactor(fromDPI:)) ?? 1.0
    }

    /// Reads `@2x` or `@3x` off a file name that has already lost its extension.
    static func scaleFactor(forFileNamed name: String) -> Double? {
        let lowered = name.lowercased()
        return scaleSuffixes.first { lowered.hasSuffix($0.suffix) }?.scale
    }

    /// Derives a scale from the resolution stored in the file.
    ///
    /// Only a DPI that is a whole multiple of 72 counts, and only 2x or 3x: a scanned image
    /// at 150 DPI is not a Retina snapshot, and reporting it as one would halve every size
    /// GimDiff shows for it.
    static func scaleFactor(fromDPI dpi: Double) -> Double? {
        guard dpi > 0 else { return nil }

        let ratio = (dpi / baseDPI).rounded()
        guard ratio >= 2, ratio <= 3 else { return nil }

        // A pHYs chunk stores pixels per metre, so a nominal 144 DPI comes back a hair off.
        guard abs(dpi - ratio * baseDPI) <= 1.0 else { return nil }
        return ratio
    }

    // MARK: - Size

    /// Size on disk, reported as zero when the volume will not say.
    private static func fileSizeBytes(of url: URL) -> Int64 {
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? 0)
    }
}
