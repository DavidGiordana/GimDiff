//
//  StubImageDiffService.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
@testable import GimDiff

/// An `ImageDiffService` double that answers with a canned report instead of decoding.
struct StubImageDiffService: ImageDiffService {
    /// Returned by every comparison, unless ``failure`` is set.
    var report: ImageDiffReport = ImageDiffReport(
        candidateSize: CGSize(width: 100, height: 100),
        baselineSize: CGSize(width: 100, height: 100),
        hasIdenticalDimensions: true,
        differentPixelCount: 100,
        totalPixelCount: 10_000,
        diffPercentage: 1.0,
        diffMaskURL: URL(fileURLWithPath: "/mock-tmp/mask.png")
    )
    /// Thrown in place of the report, to exercise the failure path.
    var failure: (any Error)?

    func compare(candidateURL: URL, baselineURL: URL, diffColor: CGColor) async throws
        -> ImageDiffReport
    {
        if let failure { throw failure }
        return report
    }
}
