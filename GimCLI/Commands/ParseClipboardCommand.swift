//
//  ParseClipboardCommand.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// `gimdiff parse-clipboard --input "<rawLogText>"`
///
/// Runs a failure log through the same extraction the paste path uses, so a log format that
/// GimDiff mis-reads can be diagnosed from a terminal instead of from the app.
enum ParseClipboardCommand {
    static let name = "parse-clipboard"
    static let summary = "Show which image paths GimDiff reads out of a failure log."
    static let usage = """
    Usage: gimdiff parse-clipboard [--input "<log text>"] [--json]

      Extracts the candidate and baseline image paths from a pasted test failure log.
      Reads standard input when --input is not given.

      --input <text>   The log text to examine.
      --json           Emit the result as JSON instead of text.

    Exits 0 when a path was found, 1 when the text named no image.
    """

    static let valueOptions: Set<String> = ["input"]
    static let knownOptions: Set<String> = ["input", "json"]

    static func run(_ arguments: Arguments, console: Console) async throws -> ExitStatus {
        try arguments.rejectOptions(outside: knownOptions)
        try arguments.rejectPositionalArguments(beyond: 0)

        let text = arguments.value(of: "input") ?? readStandardInput()
        let payload = DefaultIngestionService().parseClipboardText(text)

        if arguments.hasFlag("json") {
            console.write(try JSONOutput.encode(Report(payload)))
        } else {
            writeText(payload, to: console)
        }

        return payload == nil ? .differencesFound : .success
    }

    private static func readStandardInput() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Text

    private static func writeText(_ payload: IngestionPayload?, to console: Console) {
        guard let payload else {
            console.write("No image paths were found in the input.")
            return
        }

        console.write("Candidate", describe(payload.candidateURL, tag: payload.candidateTag))
        console.write("Baseline", describe(payload.baselineURL, tag: payload.baselineTag))
    }

    private static func describe(_ url: URL?, tag: String?) -> String {
        guard let url else { return "(none)" }
        guard let tag else { return url.path }
        return "\(url.path)  (\(tag))"
    }

    // MARK: - JSON

    private struct Report: Encodable {
        var matched: Bool
        var candidate: String?
        var candidateTag: String?
        var baseline: String?
        var baselineTag: String?

        init(_ payload: IngestionPayload?) {
            matched = payload != nil
            candidate = payload?.candidateURL.path
            candidateTag = payload?.candidateTag
            baseline = payload?.baselineURL?.path
            baselineTag = payload?.baselineTag
        }
    }
}
