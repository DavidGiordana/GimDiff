//
//  ImageDiffService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation

/// What a pixel comparison of two snapshots found.
struct ImageDiffReport: Sendable, Equatable {
    /// Size of the image under examination, in pixels.
    var candidateSize: CGSize
    /// Size of the image it was measured against, in pixels.
    var baselineSize: CGSize
    /// Whether the two images cover the same pixel grid.
    ///
    /// When this is `false` the pixel counts below were never compared: differently sized
    /// images have no pixel-to-pixel correspondence to report on.
    var hasIdenticalDimensions: Bool
    var differentPixelCount: Int
    var totalPixelCount: Int
    /// Share of the grid that differs, as a percentage: `0.045` means 0.045%, not 4.5%.
    var diffPercentage: Double
    /// Highlight image written for this comparison, absent when none was produced.
    var diffMaskURL: URL?

    init(
        candidateSize: CGSize,
        baselineSize: CGSize,
        hasIdenticalDimensions: Bool,
        differentPixelCount: Int,
        totalPixelCount: Int,
        diffPercentage: Double,
        diffMaskURL: URL? = nil
    ) {
        self.candidateSize = candidateSize
        self.baselineSize = baselineSize
        self.hasIdenticalDimensions = hasIdenticalDimensions
        self.differentPixelCount = differentPixelCount
        self.totalPixelCount = totalPixelCount
        self.diffPercentage = diffPercentage
        self.diffMaskURL = diffMaskURL
    }

    /// Whether the two images are the same size and match pixel for pixel.
    var isIdentical: Bool { hasIdenticalDimensions && differentPixelCount == 0 }
}

/// Compares two snapshots pixel by pixel and reports how far apart they are.
protocol ImageDiffService: Sendable {
    /// Measures `candidateURL` against `baselineURL`.
    ///
    /// - Parameter diffColor: Colour painted over every pixel that differs.
    /// - Returns: A report, carrying a highlight image when the two images were comparable.
    func compare(candidateURL: URL, baselineURL: URL, diffColor: CGColor) async throws
        -> ImageDiffReport
}

extension ImageDiffService {
    /// Compares two snapshots using GimDiff's own highlight colour.
    func compare(candidateURL: URL, baselineURL: URL) async throws -> ImageDiffReport {
        try await compare(
            candidateURL: candidateURL,
            baselineURL: baselineURL,
            diffColor: .gimDiffHighlight
        )
    }
}

extension CGColor {
    /// Neon magenta `#FF007F`: the colour GimDiff paints changed pixels in.
    ///
    /// Chosen because it appears in almost no real interface, so a highlighted pixel is
    /// never mistaken for content the snapshot actually contains.
    static let gimDiffHighlight = CGColor(
        srgbRed: 255.0 / 255.0,
        green: 0.0 / 255.0,
        blue: 127.0 / 255.0,
        alpha: 1.0
    )
}
