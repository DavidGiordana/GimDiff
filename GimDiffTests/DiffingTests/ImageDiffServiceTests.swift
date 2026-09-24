//
//  ImageDiffServiceTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import Testing
@testable import GimDiff

@Suite("Pixel comparison")
struct ImageDiffServiceTests {
    private let filesystem = DefaultFilesystemService()

    private func makeService() -> DefaultImageDiffService {
        DefaultImageDiffService(filesystem: filesystem)
    }

    /// Removes a mask the service wrote, so a full run does not fill the scratch directory.
    private func discard(_ report: ImageDiffReport) {
        guard let url = report.diffMaskURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Identical

    @Test("Identical images differ nowhere")
    func identicalImagesMatch() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.identicalA,
            baselineURL: ImageFixtures.identicalB
        )
        defer { discard(report) }

        #expect(report.hasIdenticalDimensions)
        #expect(report.differentPixelCount == 0)
        #expect(report.totalPixelCount == 10_000)
        #expect(report.diffPercentage == 0.0)
        #expect(report.isIdentical)
    }

    @Test("An image compared with itself differs nowhere")
    func comparingAnImageWithItselfMatches() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedB
        )
        defer { discard(report) }

        #expect(report.differentPixelCount == 0)
        #expect(report.diffPercentage == 0.0)
    }

    // MARK: - Modified

    @Test("A 10 × 10 change in a 100 × 100 image is reported as exactly 1%")
    func countsChangedPixels() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedA
        )
        defer { discard(report) }

        #expect(report.hasIdenticalDimensions)
        #expect(report.differentPixelCount == 100)
        #expect(report.totalPixelCount == 10_000)
        #expect(report.diffPercentage == 1.0)
        #expect(!report.isIdentical)
    }

    @Test("The comparison is symmetric")
    func reportsTheSameCountEitherWayRound() async throws {
        let forward = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedA
        )
        let backward = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedA,
            baselineURL: ImageFixtures.modifiedB
        )
        defer {
            discard(forward)
            discard(backward)
        }

        #expect(forward.differentPixelCount == backward.differentPixelCount)
        #expect(forward.diffPercentage == backward.diffPercentage)
    }

    @Test("Both sizes are reported, in pixels")
    func reportsBothSizes() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedA
        )
        defer { discard(report) }

        #expect(report.candidateSize == CGSize(width: 100, height: 100))
        #expect(report.baselineSize == CGSize(width: 100, height: 100))
    }

    // MARK: - Mask

    @Test("A comparable pair produces a mask on disk")
    func writesAMask() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedA
        )
        defer { discard(report) }

        let maskURL = try #require(report.diffMaskURL)
        #expect(filesystem.fileExists(at: maskURL))
        #expect(maskURL.pathExtension == "png")

        let metadata = try MetadataReader().metadata(for: maskURL)
        #expect(metadata.pixelWidth == 100)
        #expect(metadata.pixelHeight == 100)
    }

    @Test("Changed pixels are painted in the highlight colour, unchanged ones dimmed to grey")
    func paintsTheMask() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedA
        )
        defer { discard(report) }

        let maskURL = try #require(report.diffMaskURL)

        // The fixture repaints the square from (10, 10) to (19, 19).
        let changed = try ImageFixtures.pixel(atX: 15, y: 15, in: maskURL)
        #expect(changed == [255, 0, 127, 255])

        let unchanged = try ImageFixtures.pixel(atX: 60, y: 60, in: maskURL)
        #expect(unchanged[0] == unchanged[1])
        #expect(unchanged[1] == unchanged[2])
        #expect(unchanged[3] == 255)
    }

    @Test("The highlight colour is the caller's")
    func honoursTheGivenColour() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.modifiedB,
            baselineURL: ImageFixtures.modifiedA,
            diffColor: CGColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        )
        defer { discard(report) }

        let maskURL = try #require(report.diffMaskURL)
        #expect(try ImageFixtures.pixel(atX: 15, y: 15, in: maskURL) == [0, 255, 0, 255])
    }

    @Test("GimDiff's own highlight is neon magenta")
    func usesNeonMagentaByDefault() {
        let components = DefaultImageDiffService.components(of: .gimDiffHighlight)

        #expect(components == (red: 255, green: 0, blue: 127, alpha: 255))
    }

    // MARK: - Mismatched dimensions

    @Test("Differently sized images are flagged rather than compared")
    func flagsMismatchedDimensions() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.mismatchedDimensions,
            baselineURL: ImageFixtures.identicalA
        )
        defer { discard(report) }

        #expect(!report.hasIdenticalDimensions)
        #expect(report.diffPercentage == 100.0)
        #expect(report.candidateSize == CGSize(width: 100, height: 150))
        #expect(report.baselineSize == CGSize(width: 100, height: 100))
        #expect(report.diffMaskURL == nil)
        #expect(!report.isIdentical)
    }

    @Test("A mismatch is flagged whichever side is the larger")
    func flagsMismatchedDimensionsEitherWayRound() async throws {
        let report = try await makeService().compare(
            candidateURL: ImageFixtures.identicalA,
            baselineURL: ImageFixtures.mismatchedDimensions
        )
        defer { discard(report) }

        #expect(!report.hasIdenticalDimensions)
        #expect(report.diffPercentage == 100.0)
    }

    // MARK: - Failures

    @Test("A file that is not there is reported as unreadable")
    func rejectsMissingCandidate() async {
        await #expect(throws: GimDiffError.unreadableImage(ImageFixtures.missing)) {
            try await makeService().compare(
                candidateURL: ImageFixtures.missing,
                baselineURL: ImageFixtures.identicalA
            )
        }
    }

    @Test("A missing baseline is reported as unreadable too")
    func rejectsMissingBaseline() async {
        await #expect(throws: GimDiffError.unreadableImage(ImageFixtures.missing)) {
            try await makeService().compare(
                candidateURL: ImageFixtures.identicalA,
                baselineURL: ImageFixtures.missing
            )
        }
    }

    // MARK: - Arithmetic

    @Test("The percentage is a percentage, not a fraction")
    func computesPercentage() {
        #expect(DefaultImageDiffService.percentage(of: 100, in: 10_000) == 1.0)
        #expect(DefaultImageDiffService.percentage(of: 10_000, in: 10_000) == 100.0)
        #expect(DefaultImageDiffService.percentage(of: 0, in: 10_000) == 0.0)
        // 0.045% — the shape the report documents, and the reason it is not a fraction.
        #expect(DefaultImageDiffService.percentage(of: 45, in: 100_000) == 0.045)
    }

    @Test("An empty grid does not divide by zero")
    func guardsAgainstAnEmptyImage() {
        #expect(DefaultImageDiffService.percentage(of: 0, in: 0) == 0.0)
    }
}
