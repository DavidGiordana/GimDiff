//
//  CommandRunning.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A single executable invocation, expressed as an executable plus discrete arguments.
///
/// Commands are never assembled as shell strings: every argument is passed through
/// verbatim, so paths containing spaces or quotes need no escaping and cannot be
/// reinterpreted by a shell.
struct Command: Equatable, Sendable {
    /// Absolute location of the executable to spawn.
    var executableURL: URL
    /// Arguments handed to the executable, one element per argument.
    var arguments: [String]
    /// Directory the process starts in, or `nil` to inherit the caller's.
    var workingDirectory: URL?

    init(executableURL: URL, arguments: [String] = [], workingDirectory: URL? = nil) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

/// The outcome of a finished `Command`.
struct CommandResult: Equatable, Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String

    var isSuccess: Bool { exitCode == 0 }

    /// Standard output with surrounding whitespace and newlines removed.
    var trimmedOutput: String {
        standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Runs external processes on behalf of the engine.
///
/// The engine depends on this abstraction rather than on `Process` directly, which keeps
/// it free of platform APIs and lets tests substitute a recording double.
protocol CommandRunning: Sendable {
    func run(_ command: Command) async throws -> CommandResult
}
