//
//  DefaultIngestionService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Recovers comparisons from pasted failure logs and from `gimdiff://` URLs.
struct DefaultIngestionService: IngestionService {
    /// The scheme GimDiff is registered to handle.
    static let scheme = "gimdiff"

    /// Query names read as the candidate image, in order of preference.
    static let candidateParameterNames = ["candidate", "failure", "actual", "new"]
    /// Query names read as the baseline image, in order of preference.
    static let baselineParameterNames = ["baseline", "reference", "recorded", "expected", "old"]
    private static let candidateTagParameterNames = ["candidatetag", "failuretag"]
    private static let baselineTagParameterNames = ["baselinetag", "referencetag"]

    /// Matches an image path, with or without a `file://` prefix.
    ///
    /// Whitespace and quotes end a path: failure logs surround paths with one or the
    /// other, and allowing them would swallow the prose around the path. A path that really
    /// does contain a space still survives, because logs emit those percent-encoded inside
    /// a `file://` URL. The lookbehind keeps `https://host/a.png` from being read as the
    /// absolute path `/host/a.png`.
    static let imagePathPattern = #"(?<![:@\w/])(?:file://)?(/[^\s"'<>|]*\.(?:png|jpe?g|webp))"#

    init() {}

    // MARK: - Clipboard

    func parseClipboardText(_ text: String) -> IngestionPayload? {
        let references = Self.imageReferences(in: text)
        guard let first = references.first else { return nil }

        guard references.count > 1 else {
            return IngestionPayload(candidateURL: first.url, candidateTag: first.tag)
        }

        let baseline: ImageReference
        let candidate: ImageReference
        let rolesAreStated: Bool
        let baselineIndex = references.firstIndex { $0.role == .baseline }
        let candidateIndex = references.firstIndex { $0.role == .candidate }
        let unlabelledIndex = references.firstIndex { $0.role == nil }

        if let baselineIndex, let candidateIndex, baselineIndex != candidateIndex {
            baseline = references[baselineIndex]
            candidate = references[candidateIndex]
            rolesAreStated = true
        } else if let baselineIndex, candidateIndex == nil, let unlabelledIndex {
            // One label settles both sides: a log that names the reference has said the
            // other path is the image the run produced, wherever either one appears.
            baseline = references[baselineIndex]
            candidate = references[unlabelledIndex]
            rolesAreStated = true
        } else if let candidateIndex, baselineIndex == nil, let unlabelledIndex {
            baseline = references[unlabelledIndex]
            candidate = references[candidateIndex]
            rolesAreStated = true
        } else {
            // Unlabelled logs print the committed reference first and the image the failing
            // run produced second.
            baseline = references[0]
            candidate = references[1]
            rolesAreStated = false
        }

        return IngestionPayload(
            candidateURL: candidate.url,
            baselineURL: baseline.url,
            candidateTag: candidate.tag,
            baselineTag: baseline.tag,
            rolesAreStated: rolesAreStated
        )
    }

    // MARK: - Pull requests

    func parsePullRequest(_ text: String) -> GitHubPRReference? {
        GitHubPRURLParser.reference(in: text)
    }

    // MARK: - URL scheme

    func parseURLScheme(_ url: URL) -> IngestionPayload? {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            parameters[item.name.lowercased()] = value
        }

        guard let candidate = Self.value(for: Self.candidateParameterNames, in: parameters) else {
            return nil
        }

        return IngestionPayload(
            candidateURL: Self.fileURL(from: candidate),
            baselineURL: Self.value(for: Self.baselineParameterNames, in: parameters)
                .map(Self.fileURL(from:)),
            candidateTag: Self.value(for: Self.candidateTagParameterNames, in: parameters),
            baselineTag: Self.value(for: Self.baselineTagParameterNames, in: parameters),
            // A URL names each side by its parameter.
            rolesAreStated: true
        )
    }

    // MARK: - Log scanning

    /// Which side of a comparison a path was labelled as.
    private enum Role: Sendable {
        case candidate
        case baseline
    }

    private struct ImageReference {
        var url: URL
        var role: Role?
        var tag: String?
    }

    private struct RoleKeyword: Sendable {
        var keyword: String
        var role: Role
    }

    /// Words a failure log uses to name each side, matched case-insensitively.
    private static let roleKeywords: [RoleKeyword] = [
        RoleKeyword(keyword: "reference", role: .baseline),
        RoleKeyword(keyword: "baseline", role: .baseline),
        RoleKeyword(keyword: "recorded", role: .baseline),
        RoleKeyword(keyword: "expected", role: .baseline),
        RoleKeyword(keyword: "failure", role: .candidate),
        RoleKeyword(keyword: "failed", role: .candidate),
        RoleKeyword(keyword: "candidate", role: .candidate),
        RoleKeyword(keyword: "actual", role: .candidate),
        RoleKeyword(keyword: "received", role: .candidate),
    ]

    private static func imageReferences(in text: String) -> [ImageReference] {
        guard let regex = try? NSRegularExpression(pattern: imagePathPattern, options: [.caseInsensitive])
        else { return [] }

        let scanned = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: scanned.length))

        var references: [ImageReference] = []
        var previousEnd = 0

        for match in matches {
            let label = label(before: match.range, after: previousEnd, in: scanned, regex: regex)
            references.append(
                ImageReference(
                    url: fileURL(from: scanned.substring(with: match.range)),
                    role: label?.role,
                    tag: label?.tag
                )
            )
            previousEnd = match.range.upperBound
        }

        return references
    }

    /// The text that introduces a path: what precedes it on its own line, falling back to
    /// the line above when that line carries no path of its own.
    private static func label(
        before range: NSRange,
        after previousEnd: Int,
        in text: NSString,
        regex: NSRegularExpression
    ) -> (role: Role, tag: String?)? {
        let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        let contextStart = max(lineStart, previousEnd)
        let inline = text.substring(
            with: NSRange(location: contextStart, length: range.location - contextStart)
        )

        if let label = self.label(in: inline) { return label }
        guard lineStart > 0 else { return nil }

        let previousLine = text.substring(
            with: text.lineRange(for: NSRange(location: lineStart - 1, length: 0))
        )
        let previousLineRange = NSRange(location: 0, length: (previousLine as NSString).length)
        guard regex.firstMatch(in: previousLine, range: previousLineRange) == nil else { return nil }

        return self.label(in: previousLine)
    }

    private static func label(in context: String) -> (role: Role, tag: String?)? {
        let lowered = context.lowercased()
        var closest: (distance: Int, keyword: RoleKeyword)?

        // The keyword nearest the path wins: a line can mention both sides, as in
        // "failed - Snapshot does not match reference".
        for keyword in roleKeywords {
            guard let range = lowered.range(of: keyword.keyword, options: .backwards) else { continue }
            let distance = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
            if distance > (closest?.distance ?? -1) {
                closest = (distance, keyword)
            }
        }

        if let closest {
            return (closest.keyword.role, closest.keyword.keyword.capitalized)
        }

        // Unified-diff markers: the committed reference is the "−" side of the hunk.
        switch context.last(where: { !$0.isWhitespace }) {
        case "-"?, "\u{2212}"?: return (.baseline, nil)
        case "+"?: return (.candidate, nil)
        default: return nil
        }
    }

    // MARK: - Paths

    /// Reads a path that may arrive bare, tilde-prefixed, or as a `file://` URL.
    private static func fileURL(from value: String) -> URL {
        if value.lowercased().hasPrefix("file://") {
            if let url = URL(string: value), url.isFileURL {
                return url.standardizedFileURL
            }
            let path = String(value.dropFirst("file://".count))
            return URL(fileURLWithPath: path.removingPercentEncoding ?? path).standardizedFileURL
        }

        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func value(for names: [String], in parameters: [String: String]) -> String? {
        names.lazy.compactMap { parameters[$0] }.first
    }
}
