//
//  SnapshotMetadata.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Physical properties of a snapshot image, read once when the file is discovered.
struct SnapshotMetadata: Sendable, Hashable {
    /// Width in pixels as stored, before the scale factor is applied.
    var pixelWidth: Int
    /// Height in pixels as stored, before the scale factor is applied.
    var pixelHeight: Int
    /// Backing-store scale the image was rendered at: `1.0`, `2.0`, or `3.0`.
    var scaleFactor: Double
    var fileSizeBytes: Int64
    var format: ImageFormat

    init(
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: Double = 1.0,
        fileSizeBytes: Int64 = 0,
        format: ImageFormat = .png
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scaleFactor = scaleFactor
        self.fileSizeBytes = fileSizeBytes
        self.format = format
    }

    /// Size in points, which is what the test that produced the snapshot asked for.
    var pointWidth: Double {
        scaleFactor > 0 ? Double(pixelWidth) / scaleFactor : Double(pixelWidth)
    }

    /// Size in points, which is what the test that produced the snapshot asked for.
    var pointHeight: Double {
        scaleFactor > 0 ? Double(pixelHeight) / scaleFactor : Double(pixelHeight)
    }
}
