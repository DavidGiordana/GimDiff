//
//  Console.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The terminal a command writes to.
///
/// A type rather than bare `print` calls so results and diagnostics stay on separate
/// streams: `gimdiff diff ... --json | jq` has to keep working while errors remain visible.
struct Console: Sendable {
    /// Width the label column is padded to, so successive rows line up.
    static let labelWidth = 12

    private let standardOutput: FileHandle
    private let standardError: FileHandle

    init(
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    func write(_ line: String = "") {
        write(line, to: standardOutput)
    }

    /// Writes a labelled row, aligned with every other row written this way.
    func write(_ label: String, _ value: String) {
        write(label.padding(toLength: Self.labelWidth, withPad: " ", startingAt: 0) + value)
    }

    func writeError(_ message: String) {
        write("gimdiff: " + message, to: standardError)
    }

    private func write(_ line: String, to handle: FileHandle) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        handle.write(data)
    }
}
