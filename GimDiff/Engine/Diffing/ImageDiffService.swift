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
    /// Pixels whose bytes differ but which ``DiffTolerance`` counts as the same.
    ///
    /// Not in ``differentPixelCount``. Reported so a match within tolerance still says that
    /// something moved, and how much of it was forgiven.
    var toleratedPixelCount: Int
    /// The largest perceptual distance between any two corresponding pixels, as CIE76 ΔE.
    ///
    /// Measured whatever the tolerance, so it answers the question a tolerance raises: how
    /// loose would the comparison have to be for these two images to match.
    var maximumDeltaE: Double

    init(
        candidateSize: CGSize,
        baselineSize: CGSize,
        hasIdenticalDimensions: Bool,
        differentPixelCount: Int,
        totalPixelCount: Int,
        diffPercentage: Double,
        diffMaskURL: URL? = nil,
        toleratedPixelCount: Int = 0,
        maximumDeltaE: Double = 0
    ) {
        self.candidateSize = candidateSize
        self.baselineSize = baselineSize
        self.hasIdenticalDimensions = hasIdenticalDimensions
        self.differentPixelCount = differentPixelCount
        self.totalPixelCount = totalPixelCount
        self.diffPercentage = diffPercentage
        self.diffMaskURL = diffMaskURL
        self.toleratedPixelCount = toleratedPixelCount
        self.maximumDeltaE = maximumDeltaE
    }

    /// Whether the two images are the same size and match pixel for pixel, within the
    /// tolerance they were compared at.
    var isIdentical: Bool { hasIdenticalDimensions && differentPixelCount == 0 }
}

/// How far apart two pixels may be and still count as the same.
///
/// Measured perceptually rather than per channel: a renderer that shifts anti-aliasing or
/// rounds a colour differently moves the bytes without moving anything a person would see,
/// and a byte threshold large enough to forgive that also forgives a real change in a dark
/// colour. CIE76 ΔE weighs a difference by how visible it is.
struct DiffTolerance: Sendable, Hashable {
    /// The largest ΔE between two pixels that still counts as a match, where black against
    /// white is 100 and saturated colours can be further apart than that. Zero means
    /// the bytes must be identical.
    var maximumDeltaE: Double

    init(maximumDeltaE: Double) {
        self.maximumDeltaE = max(0, maximumDeltaE)
    }

    /// Byte for byte, the comparison GimDiff has always made.
    static let exact = DiffTolerance(maximumDeltaE: 0)

    /// The steps offered on the canvas: below the threshold of perception, at it (ΔE 2.3,
    /// the usual "just noticeable difference"), and two looser ones for noisy renderers.
    static let presets: [DiffTolerance] = [0, 1, 2.3, 5, 10].map(DiffTolerance.init(maximumDeltaE:))

    var isExact: Bool { maximumDeltaE == 0 }
}

/// Compares two snapshots pixel by pixel and reports how far apart they are.
protocol ImageDiffService: Sendable {
    /// Measures `candidateURL` against `baselineURL`.
    ///
    /// - Parameters:
    ///   - diffColor: Colour painted over every pixel that differs.
    ///   - tolerance: How far apart two pixels may be and still count as the same.
    /// - Returns: A report, carrying a highlight image when the two images were comparable.
    func compare(
        candidateURL: URL,
        baselineURL: URL,
        diffColor: CGColor,
        tolerance: DiffTolerance
    ) async throws -> ImageDiffReport
}

extension ImageDiffService {
    /// Compares two snapshots using GimDiff's own highlight colour.
    func compare(
        candidateURL: URL,
        baselineURL: URL,
        tolerance: DiffTolerance = .exact
    ) async throws -> ImageDiffReport {
        try await compare(
            candidateURL: candidateURL,
            baselineURL: baselineURL,
            diffColor: .gimDiffHighlight,
            tolerance: tolerance
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
