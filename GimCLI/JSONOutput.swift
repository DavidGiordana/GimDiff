//
//  JSONOutput.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Renders a command's result as the JSON its `--json` flag promises.
enum JSONOutput {
    /// Keys are sorted and slashes left unescaped so the output diffs cleanly between runs
    /// and a path in it stays readable to a person reading the raw text.
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

extension URL {
    /// This URL written relative to `base`, or its full path when it lies outside.
    func path(relativeTo base: URL) -> String {
        let prefix = base.standardizedFileURL.path
        let full = standardizedFileURL.path
        guard full.hasPrefix(prefix + "/") else { return full }
        return String(full.dropFirst(prefix.count + 1))
    }
}
