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

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return .unavailable }

        return .loaded(DecodedSnapshotImage(cgImage: image))
    }
}
