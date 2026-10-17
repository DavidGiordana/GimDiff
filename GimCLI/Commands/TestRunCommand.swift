//
//  TestRunCommand.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// `gimdiff test-run <projectPath> [--result <bundle>] [--out <folder>] [--tolerance <ΔE>] [--json]`
///
/// The sidebar's Test Run view for a build machine: which snapshots a run failed on, what
/// the tests rendered, and how far apart the two are, without opening the bundle in Xcode.
enum TestRunCommand {
    static let name = "test-run"
    static let summary = "Report the snapshots an Xcode or Paparazzi test run failed on."
    static let usage = """
    Usage: gimdiff test-run <project-path> [--result <bundle.xcresult>] [--out <folder>]
                            [--tolerance <ΔE>] [--json]

      Reads an Xcode test result bundle, or the failures a Paparazzi verify left in the
      project's modules, and lists every snapshot of the project a test failed on, with
      the image the test rendered and how much of it differs, plus any attached image
      that matches no snapshot.

      --result <path>     The .xcresult bundle, or a module's build/paparazzi/failures
                          folder, to read. Defaults to the newest run found: the bundles
                          Xcode keeps in DerivedData for the project, and every module's
                          Paparazzi failures. CI that sets its own DerivedData folder
                          should pass the bundle.
      --out <folder>      Write <name>.baseline.png, <name>.candidate.png, and
                          <name>.diff.png for each failure into <folder>, and
                          <name>.png for each unmatched image.
      --tolerance <ΔE>    As for gimdiff diff: how far apart two pixels may look and still
                          count as the same. Defaults to 0.
      --json              Emit the result as JSON instead of text.

    Needs Xcode for a result bundle, which is read with xcrun xcresulttool. Paparazzi
    failures are read from the renderings Paparazzi 1.3.2 and later write beside each
    delta image.

    Exits 0 when the run failed on no snapshot, 1 when it did, 2 when the bundle could
    not be read.
    """

    static let valueOptions: Set<String> = ["result", "out", "tolerance"]
    static let knownOptions: Set<String> = ["result", "out", "tolerance", "json"]

    /// Why the command has no bundle to read.
    struct NoResultBundle: LocalizedError {
        let projectURL: URL

        var errorDescription: String? {
            "No test results for \(projectURL.path). Run its tests, or pass --result."
        }
    }

    static func run(_ arguments: Arguments, console: Console) async throws -> ExitStatus {
        try arguments.rejectOptions(outside: knownOptions)
        try arguments.rejectPositionalArguments(beyond: 1)

        let projectURL = try arguments.fileURL(at: 0, named: "project-path")
        let tolerance = try DiffCommand.tolerance(from: arguments)
        let outputFolder = arguments.fileURL(of: "out")

        let filesystem = DefaultFilesystemService()
        let gitService = DefaultGitService(filesystem: filesystem)
        let project = try await ProjectScanner(filesystem: filesystem, gitService: gitService)
            .scan(projectRoot: projectURL)

        // In the tool's own scratch folder, which it deletes before exiting.
        let scratch = DefaultFilesystemService.sessionDirectory.appendingPathComponent("TestRuns", isDirectory: true)
        let reader = CombinedTestResultReader(
            xcode: XcresultReader(runner: SystemCommandRunner(), filesystem: filesystem, temporaryRoot: scratch),
            paparazzi: PaparazziFailureReader(filesystem: filesystem, temporaryRoot: scratch)
        )
        let report: TestRunReport
        if let resultURL = arguments.fileURL(of: "result") {
            report = try await reader.report(forBundleAt: resultURL)
        } else {
            let locator = CombinedTestResultLocator([
                DerivedDataLocator(),
                PaparazziFailureLocator(filesystem: filesystem),
            ])
            guard let bundle = locator.resultBundles(for: project).first else {
                throw NoResultBundle(projectURL: projectURL)
            }
            report = try await reader.report(for: bundle)
        }
        let bundleURL = report.bundleURL
        // The exported attachments are copies made for this run of the tool alone.
        defer { try? filesystem.removeItem(at: report.scratchDirectory) }

        let results = TestRunResults(
            report: report,
            differences: try TestRunMatcher(filesystem: filesystem).differences(in: report, against: project)
        )
        let entries = TestRunExport.entries(for: results, in: project)

        let imageDiff = DefaultImageDiffService(filesystem: filesystem)
        var rows: [Row] = []
        for entry in entries {
            rows.append(try await row(
                for: entry,
                tolerance: tolerance,
                imageDiff: imageDiff,
                outputFolder: outputFolder,
                filesystem: filesystem
            ))
        }

        if arguments.hasFlag("json") {
            console.write(try JSONOutput.encode(Report(
                project: project,
                bundleURL: bundleURL,
                startedAt: report.startedAt,
                tolerance: tolerance,
                outputFolder: outputFolder,
                rows: rows
            )))
        } else {
            writeText(project: project, bundleURL: bundleURL, startedAt: report.startedAt, rows: rows, to: console)
        }

        return rows.isEmpty ? .success : .differencesFound
    }

    // MARK: - Measuring and writing

    /// One entry with its measurement, and where its files went when they were written.
    struct Row {
        var entry: TestRunExportEntry
        var diff: ImageDiffReport?
        var baselineOut: URL?
        var candidateOut: URL?
        var maskOut: URL?
    }

    private static func row(
        for entry: TestRunExportEntry,
        tolerance: DiffTolerance,
        imageDiff: DefaultImageDiffService,
        outputFolder: URL?,
        filesystem: DefaultFilesystemService
    ) async throws -> Row {
        var row = Row(entry: entry)

        if let baseline = entry.baselineURL {
            // A pair that will not decode is still a failure worth listing; it is reported
            // without a measurement rather than ending the whole report.
            row.diff = try? await imageDiff.compare(
                candidateURL: entry.candidateURL,
                baselineURL: baseline,
                tolerance: tolerance
            )
        }

        guard let outputFolder else {
            if let mask = row.diff?.diffMaskURL { try? filesystem.removeItem(at: mask) }
            return row
        }

        let extensionOf = { (url: URL) in url.pathExtension.isEmpty ? "png" : url.pathExtension }
        switch entry.kind {
        case .failure:
            if let baseline = entry.baselineURL {
                let destination = outputFolder.appendingPathComponent("\(entry.fileStem).baseline.\(extensionOf(baseline))")
                try filesystem.copyFile(from: baseline, to: destination)
                row.baselineOut = destination
            }
            let candidate = outputFolder.appendingPathComponent("\(entry.fileStem).candidate.\(extensionOf(entry.candidateURL))")
            try filesystem.copyFile(from: entry.candidateURL, to: candidate)
            row.candidateOut = candidate
            if let mask = row.diff?.diffMaskURL {
                let destination = outputFolder.appendingPathComponent("\(entry.fileStem).diff.png")
                try filesystem.replaceFile(at: destination, with: mask)
                row.maskOut = destination
            }
        case .unmatched:
            let destination = outputFolder.appendingPathComponent("\(entry.fileStem).\(extensionOf(entry.candidateURL))")
            try filesystem.copyFile(from: entry.candidateURL, to: destination)
            row.candidateOut = destination
        }
        return row
    }

    // MARK: - Text

    private static func writeText(
        project: ProjectBundle,
        bundleURL: URL,
        startedAt: Date?,
        rows: [Row],
        to console: Console
    ) {
        let failures = rows.filter { $0.entry.kind == .failure }
        let unmatched = rows.filter { $0.entry.kind == .unmatched }

        console.write("Project", project.rootURL.path)
        console.write("Result", bundleURL.path)
        if let startedAt {
            console.write("Started", startedAt.formatted(.iso8601))
        }
        console.write("Failures", "\(count(failures.count, "snapshot")), \(count(unmatched.count, "unmatched image"))")

        guard !rows.isEmpty else {
            console.write()
            console.write("The run failed on no snapshot.")
            return
        }

        for row in failures {
            console.write()
            console.write("\(row.entry.suiteName ?? row.entry.testName)/\(row.entry.snapshotName ?? "?")  —  \(row.entry.testName)")
            if let baseline = row.entry.baselineURL {
                console.write("Baseline", baseline.path(relativeTo: project.rootURL))
            }
            console.write("Candidate", row.candidateOut?.path ?? "pass --out to keep the rendered image")
            console.write("Difference", difference(of: row.diff))
            if let mask = row.maskOut {
                console.write("Mask", mask.path)
            }
        }

        for row in unmatched {
            console.write()
            console.write("Unmatched  —  \(row.entry.testName)")
            console.write("Image", row.candidateOut?.path ?? "pass --out to keep the image")
        }
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    private static func difference(of report: ImageDiffReport?) -> String {
        guard let report else { return "not measured — the images could not be read" }
        guard report.hasIdenticalDimensions else {
            return "sizes differ: \(DiffCommand.dimensions(report.candidateSize)) against \(DiffCommand.dimensions(report.baselineSize))"
        }
        return "\(DiffCommand.percentage(report.diffPercentage)) (\(report.differentPixelCount) pixels)"
    }

    // MARK: - JSON

    private struct Report: Encodable {
        var project: String
        var result: String
        /// ISO 8601, as a person and a CI script both read a date.
        var startedAt: String?
        var tolerance: Double
        var outputFolder: String?
        var failureCount: Int
        var unmatchedCount: Int
        var entries: [Entry]

        init(
            project: ProjectBundle,
            bundleURL: URL,
            startedAt: Date?,
            tolerance: DiffTolerance,
            outputFolder: URL?,
            rows: [Row]
        ) {
            self.project = project.rootURL.path
            result = bundleURL.path
            self.startedAt = startedAt?.formatted(.iso8601)
            self.tolerance = tolerance.maximumDeltaE
            self.outputFolder = outputFolder?.path
            failureCount = rows.filter { $0.entry.kind == .failure }.count
            unmatchedCount = rows.filter { $0.entry.kind == .unmatched }.count
            entries = rows.map(Entry.init)
        }

        struct Entry: Encodable {
            var kind: String
            var test: String
            var testName: String
            var suite: String?
            var snapshot: String?
            var baselinePath: String?
            /// Only when --out wrote it: the run's own copy is gone once the command ends.
            var candidatePath: String?
            var maskPath: String?
            var identicalDimensions: Bool?
            var differentPixelCount: Int?
            var diffPercentage: Double?
            var maximumDeltaE: Double?

            init(_ row: Row) {
                kind = row.entry.kind.rawValue
                test = row.entry.testIdentifier
                testName = row.entry.testName
                suite = row.entry.suiteName
                snapshot = row.entry.snapshotName
                baselinePath = (row.baselineOut ?? row.entry.baselineURL)?.path
                candidatePath = row.candidateOut?.path
                maskPath = row.maskOut?.path
                identicalDimensions = row.diff?.hasIdenticalDimensions
                differentPixelCount = row.diff?.differentPixelCount
                diffPercentage = row.diff?.diffPercentage
                maximumDeltaE = row.diff?.maximumDeltaE
            }
        }
    }
}
