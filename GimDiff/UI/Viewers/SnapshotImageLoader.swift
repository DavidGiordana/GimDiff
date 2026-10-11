//
//  SnapshotImageLoader.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO

/// A decoded snapshot, carried across executors as one immutable value.
///
/// `CGImage` is immutable once made, but it is not declared `Sendable`, so the unchecked
/// conformance is stated here in one place rather than at every call site that decodes off
/// the main actor.
struct DecodedSnapshotImage: @unchecked Sendable {
    let cgImage: CGImage
    /// Pixels per point the image was recorded at: 3 for a snapshot taken on a @3x
    /// simulator, 1 when neither its name nor its DPI says otherwise.
    ///
    /// Drawing at this scale rather than the display's is what makes 1:1 mean the size the
    /// device drew the view, independent of the Mac it is inspected on.
    var recordedScale: CGFloat = 1

    /// Size as stored, in pixels.
    var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }
}

/// What the canvas found at a path.
enum CanvasImage: Sendable {
    case loaded(DecodedSnapshotImage)
    /// Nothing there, nothing in it, or nothing any installed decoder understood.
    case unavailable
}

/// Reads a snapshot off disk for the canvas.
///
/// Deliberately not `AsyncImage`: it keys its cache on the URL, and GimDiff's whole job is
/// to show a file whose name never changes while its contents do. A refresh, a promotion, or
/// a test run would all leave the stale bitmap on screen.
enum SnapshotImageLoader {
    /// Decodes the image at `url`.
    ///
    /// An empty file is reported as unavailable before it reaches ImageIO: a zero-byte PNG
    /// is what a killed test run leaves behind, and it is a missing snapshot rather than a
    /// corrupt one.
    static func load(_ url: URL) -> CanvasImage {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size > 0
        else { return .unavailable }

        // Decoded here, on the background task that calls this, rather than left lazy: a
        // lazy image is decoded the first time it is drawn, which is during the render on
        // the main thread — 5 to 10 ms per full-screen snapshot, twice per comparison.
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else { return .unavailable }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let scale = MetadataReader.scaleFactor(for: url, properties: properties ?? [:])
        return .loaded(DecodedSnapshotImage(cgImage: image, recordedScale: scale))
    }
}
