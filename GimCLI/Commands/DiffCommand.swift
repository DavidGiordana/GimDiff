//
//  DiffCommand.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation

/// `gimdiff diff <candidatePath> <baselinePath> [--out <maskPath>] [--tolerance <ΔE>] [--json]`
///
/// The headless half of the canvas: the same pixel comparison, reported as text.
enum DiffCommand {
    static let name = "diff"
    static let summary = "Compare two images and report how far apart they are."
    static let usage = """
    Usage: gimdiff diff <candidate> <baseline> [--out <mask.png>] [--tolerance <ΔE>] [--json]

      Compares two images pixel by pixel and prints the share of the image that differs.

      --out <path>        Write the highlight mask to <path> as a PNG.
      --tolerance <ΔE>    Count two pixels as the same when they are at most this far apart
                          perceptually, as a CIE76 ΔE (black against white is 100). 2.3 is
                          about the smallest change anybody can see. Defaults to 0: the
                          bytes must match.
      --json              Emit the result as JSON instead of text.

    Exits 0 when the images match, 1 when they differ, 2 when the comparison failed.
    """

    static let valueOptions: Set<String> = ["out", "tolerance"]
    static let knownOptions: Set<String> = ["out", "tolerance", "json"]

    /// Decimal places used for the percentage, enough to keep a single changed pixel in a
    /// 4K snapshot from being reported as a flat zero.
    static let percentagePrecision = 4

    static func run(_ arguments: Arguments, console: Console) async throws -> ExitStatus {
        try arguments.rejectOptions(outside: knownOptions)
        try arguments.rejectPositionalArguments(beyond: 2)

        let candidateURL = try arguments.fileURL(at: 0, named: "candidate")
        let baselineURL = try arguments.fileURL(at: 1, named: "baseline")

        let filesystem = DefaultFilesystemService()
        let service = DefaultImageDiffService(filesystem: filesystem)
        let report = try await service.compare(
            candidateURL: candidateURL,
            baselineURL: baselineURL,
            tolerance: try tolerance(from: arguments)
        )

        let maskURL = try deliverMask(
            from: report,
            to: arguments.fileURL(of: "out"),
            filesystem: filesystem
        )

        if arguments.hasFlag("json") {
            console.write(try JSONOutput.encode(Report(report, maskURL: maskURL)))
        } else {
            writeText(report, maskURL: maskURL, to: console)
        }

        return report.isIdentical ? .success : .differencesFound
    }

    /// Reads `--tolerance`, refusing anything that is not a ΔE a comparison can use.
    static func tolerance(from arguments: Arguments) throws -> DiffTolerance {
        guard let text = arguments.value(of: "tolerance") else { return .exact }
        guard let value = Double(text), value.isFinite, value >= 0 else {
            throw Arguments.Failure.invalidValue(option: "tolerance", value: text)
        }
        return DiffTolerance(maximumDeltaE: value)
    }

    // MARK: - Mask

    /// Moves the mask to where the caller asked for it, or discards it when they did not.
    ///
    /// The comparison always draws a mask, so a run without `--out` would otherwise leave a
    /// PNG in the scratch directory every time — which for a tool meant to run in a loop on
    /// a build machine adds up.
    private static func deliverMask(
        from report: ImageDiffReport,
        to destination: URL?,
        filesystem: any FilesystemService
    ) throws -> URL? {
        guard let source = report.diffMaskURL else { return nil }

        guard let destination else {
            try? FileManager.default.removeItem(at: source)
            return nil
        }

        try filesystem.replaceFile(at: destination, with: source)
        return destination
    }

    // MARK: - Text

    private static func writeText(
        _ report: ImageDiffReport,
        maskURL: URL?,
        to console: Console
    ) {
        console.write("Candidate", dimensions(report.candidateSize))
        console.write("Baseline", dimensions(report.baselineSize))

        console.write(
            "Pixels",
            "\(report.differentPixelCount) of \(report.totalPixelCount) differ"
        )
        if let overlap = report.overlap {
            // Sizes that differ are laid over each other from the top-left corner; what
            // only one image covers is counted above, and the shared area is told apart.
            console.write(
                "Overlap",
                "\(overlap.differentPixelCount) of \(overlap.pixelCount) differ (\(percentage(overlap.diffPercentage)), top-left aligned)"
            )
        }

        if report.toleratedPixelCount > 0 {
            console.write("Tolerated", "\(report.toleratedPixelCount) within tolerance")
        }
        console.write("Largest ΔE", String(format: "%.2f", report.maximumDeltaE))

        console.write("Difference", percentage(report.diffPercentage))
        if let maskURL {
            console.write("Mask", maskURL.path)
        }
    }

    static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }

    static func percentage(_ value: Double) -> String {
        String(format: "%.\(percentagePrecision)f%%", value)
    }

    // MARK: - JSON

    private struct Report: Encodable {
        var candidateWidth: Int
        var candidateHeight: Int
        var baselineWidth: Int
        var baselineHeight: Int
        var identicalDimensions: Bool
        var identical: Bool
        var differentPixelCount: Int
        var totalPixelCount: Int
        var diffPercentage: Double
        var toleratedPixelCount: Int
        var maximumDeltaE: Double
        /// Present only when the sizes differ: the area both images cover.
        var overlapPixelCount: Int?
        var overlapDifferentPixelCount: Int?
        var overlapDiffPercentage: Double?
        var maskPath: String?

        init(_ report: ImageDiffReport, maskURL: URL?) {
            candidateWidth = Int(report.candidateSize.width)
            candidateHeight = Int(report.candidateSize.height)
            baselineWidth = Int(report.baselineSize.width)
            baselineHeight = Int(report.baselineSize.height)
            identicalDimensions = report.hasIdenticalDimensions
            identical = report.isIdentical
            differentPixelCount = report.differentPixelCount
            totalPixelCount = report.totalPixelCount
            diffPercentage = report.diffPercentage
            toleratedPixelCount = report.toleratedPixelCount
            maximumDeltaE = report.maximumDeltaE
            overlapPixelCount = report.overlap?.pixelCount
            overlapDifferentPixelCount = report.overlap?.differentPixelCount
            overlapDiffPercentage = report.overlap?.diffPercentage
            maskPath = maskURL?.path
        }
    }
}
