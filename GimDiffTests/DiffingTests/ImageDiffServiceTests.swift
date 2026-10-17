//
//  ImageDiffServiceTests.swift
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

    /// A large opaque PNG of `width` × `height`, filled with `grey`, in the scratch directory.
    private func writeLargeImage(width: Int, height: Int, grey: CGFloat) throws -> URL {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: grey, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let url = filesystem.createTemporaryFile(prefix: "large", extension: "png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    // MARK: - Threading

    @Test("A comparison started on the main actor leaves it free while it runs")
    @MainActor
    func leavesTheMainActorFree() async throws {
        let candidate = try writeLargeImage(width: 2_500, height: 3_500, grey: 0.2)
        let baseline = try writeLargeImage(width: 2_500, height: 3_500, grey: 0.8)
        defer {
            try? FileManager.default.removeItem(at: candidate)
            try? FileManager.default.removeItem(at: baseline)
        }

        // Counts the turns the main actor gets while the comparison is in flight. Held on
        // the main actor for the whole of it, it would get none.
        var turns = 0
        var isDone = false
        let heartbeat = Task { @MainActor in
            while !isDone {
                turns += 1
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        let report = try await makeService().compare(candidateURL: candidate, baselineURL: baseline)
        isDone = true
        await heartbeat.value
        defer { discard(report) }

        #expect(report.differentPixelCount == 2_500 * 3_500)
        #expect(turns > 1)
    }

    @Test("A cancelled comparison stops instead of finishing")
    func stopsWhenCancelled() async throws {
        let candidate = try writeLargeImage(width: 2_500, height: 3_500, grey: 0.2)
        let baseline = try writeLargeImage(width: 2_500, height: 3_500, grey: 0.8)
        defer {
            try? FileManager.default.removeItem(at: candidate)
            try? FileManager.default.removeItem(at: baseline)
        }

        let comparison = Task {
            try await makeService().compare(candidateURL: candidate, baselineURL: baseline)
        }
        comparison.cancel()

        await #expect(throws: CancellationError.self) {
            try await comparison.value
        }
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
            diffColor: CGColor(srgbRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            tolerance: .exact
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

    // MARK: - Tolerance

    @Test("A pixel is no distance from itself")
    func samePixelIsNoDistance() {
        let grey: DefaultImageDiffService.Pixel = (120, 120, 120, 255)
        #expect(DefaultImageDiffService.perceptualDistance(grey, grey) == 0)
    }

    @Test("Black and white are the whole scale apart")
    func blackAndWhiteAreFarApart() {
        let distance = DefaultImageDiffService.perceptualDistance((0, 0, 0, 255), (255, 255, 255, 255))
        #expect(abs(distance - 100) < 0.01)
    }

    @Test("A one-step rounding change is below what anybody can see")
    func roundingIsImperceptible() {
        let distance = DefaultImageDiffService.perceptualDistance((120, 120, 120, 255), (121, 120, 120, 255))
        #expect(distance > 0)
        #expect(distance < 1)
    }

    @Test("A pixel that turns transparent is as different as it can be")
    func alphaCountsOnTheSameScale() {
        let distance = DefaultImageDiffService.perceptualDistance((0, 0, 0, 255), (0, 0, 0, 0))
        #expect(distance == 100)
    }

    @Test("An exact comparison counts a one-step change and measures how small it is")
    func exactCountsRounding() async throws {
        let pair = try SolidImages(candidate: (121, 120, 120), baseline: (120, 120, 120))
        defer { pair.remove() }

        let report = try await makeService().compare(candidateURL: pair.candidate, baselineURL: pair.baseline)
        defer { discard(report) }

        #expect(report.differentPixelCount == 100)
        #expect(report.toleratedPixelCount == 0)
        #expect(report.maximumDeltaE > 0)
        #expect(report.maximumDeltaE < 1)
    }

    @Test("A tolerance forgives a change below it, and says how much it forgave")
    func toleranceForgivesSmallChanges() async throws {
        let pair = try SolidImages(candidate: (121, 120, 120), baseline: (120, 120, 120))
        defer { pair.remove() }

        let report = try await makeService().compare(
            candidateURL: pair.candidate,
            baselineURL: pair.baseline,
            tolerance: DiffTolerance(maximumDeltaE: 1)
        )
        defer { discard(report) }

        #expect(report.differentPixelCount == 0)
        #expect(report.toleratedPixelCount == 100)
        #expect(report.isIdentical)
    }

    @Test("A tolerance does not forgive a change above it")
    func toleranceKeepsLargeChanges() async throws {
        let pair = try SolidImages(candidate: (255, 0, 0), baseline: (0, 0, 255))
        defer { pair.remove() }

        let report = try await makeService().compare(
            candidateURL: pair.candidate,
            baselineURL: pair.baseline,
            tolerance: DiffTolerance(maximumDeltaE: 10)
        )
        defer { discard(report) }

        #expect(report.differentPixelCount == 100)
        #expect(report.toleratedPixelCount == 0)
        #expect(report.maximumDeltaE > 10)
    }

    @Test("A negative tolerance is read as exact")
    func negativeToleranceIsExact() {
        #expect(DiffTolerance(maximumDeltaE: -3).isExact)
    }
}

/// Two 10 × 10 opaque images of one colour each, written to a scratch folder.
///
/// Built at run time rather than checked in: the point is the exact byte values, and a
/// fixture saved through an editor can come back colour-managed into different ones.
private struct SolidImages {
    let candidate: URL
    let baseline: URL

    init(candidate: (UInt8, UInt8, UInt8), baseline: (UInt8, UInt8, UInt8)) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("GimDiffSolidImages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.candidate = folder.appendingPathComponent("candidate.png")
        self.baseline = folder.appendingPathComponent("baseline.png")
        try Self.write(candidate, to: self.candidate)
        try Self.write(baseline, to: self.baseline)
    }

    func remove() {
        try? FileManager.default.removeItem(at: candidate.deletingLastPathComponent())
    }

    private static func write(_ color: (UInt8, UInt8, UInt8), to url: URL) throws {
        let side = 10
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            bytes[offset] = color.0
            bytes[offset + 1] = color.1
            bytes[offset + 2] = color.2
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
