//
//  GimDiffCLI.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Routes a command line to the subcommand that handles it.
enum GimDiffCLI {
    static let toolName = "gimdiff"
    static let version = "1.0"

    static let usage = """
    gimdiff — snapshot comparison for the terminal.

    Usage: gimdiff <subcommand> [options]
           gimdiff <project-path>
           gimdiff <candidate> <baseline>

    Subcommands:
      \(ScanCommand.name.padded)\(ScanCommand.summary)
      \(DiffCommand.name.padded)\(DiffCommand.summary)
      \(ParseClipboardCommand.name.padded)\(ParseClipboardCommand.summary)

    Given paths and no subcommand, gimdiff opens them in the running GimDiff window.

    Options:
      \("--help".padded)Show this message, or a subcommand's own.
      \("--version".padded)Print the version and exit.

    Run “gimdiff <subcommand> --help” for the options a subcommand takes.
    """

    /// Runs one invocation, including the tool's own path as the shell passed it.
    static func run(arguments raw: [String], console: Console = Console()) async -> ExitStatus {
        let tokens = Array(raw.dropFirst())

        guard let first = tokens.first else {
            console.write(usage)
            return .usage
        }

        switch first.lowercased() {
        case "--help", "-h", "help":
            console.write(usage)
            return .success
        case "--version", "-v", "version":
            console.write("\(toolName) \(version)")
            return .success
        default:
            return await dispatch(first, tokens: tokens, console: console)
        }
    }

    private static func dispatch(
        _ first: String,
        tokens: [String],
        console: Console
    ) async -> ExitStatus {
        switch first.lowercased() {
        case ScanCommand.name:
            await run(
                Array(tokens.dropFirst()),
                usage: ScanCommand.usage,
                valueOptions: ScanCommand.valueOptions,
                console: console,
                body: ScanCommand.run
            )
        case DiffCommand.name:
            await run(
                Array(tokens.dropFirst()),
                usage: DiffCommand.usage,
                valueOptions: DiffCommand.valueOptions,
                console: console,
                body: DiffCommand.run
            )
        case ParseClipboardCommand.name:
            await run(
                Array(tokens.dropFirst()),
                usage: ParseClipboardCommand.usage,
                valueOptions: ParseClipboardCommand.valueOptions,
                console: console,
                body: ParseClipboardCommand.run
            )
        default:
            // Anything else is read as a path. An unknown *option* is not: it is a typo, and
            // treating `--jsno` as a file to open would hide it.
            first.hasPrefix("-")
                ? reportUnknownSubcommand(first, console: console)
                : await run(
                    tokens,
                    usage: LaunchCommand.usage,
                    valueOptions: LaunchCommand.valueOptions,
                    console: console,
                    body: LaunchCommand.run
                )
        }
    }

    /// Parses one subcommand's arguments and runs it, turning any failure into a message
    /// and a status rather than a crash.
    private static func run(
        _ tokens: [String],
        usage: String,
        valueOptions: Set<String>,
        console: Console,
        body: (Arguments, Console) async throws -> ExitStatus
    ) async -> ExitStatus {
        do {
            let arguments = try Arguments(tokens, valueOptions: valueOptions)
            guard !arguments.hasFlag("help"), !arguments.hasFlag("h") else {
                console.write(usage)
                return .success
            }
            return try await body(arguments, console)
        } catch let failure as Arguments.Failure {
            console.writeError(failure.localizedDescription)
            console.write(usage)
            return .usage
        } catch {
            console.writeError(error.localizedDescription)
            return .failure
        }
    }

    private static func reportUnknownSubcommand(_ token: String, console: Console) -> ExitStatus {
        console.writeError("unknown option \(token).")
        console.write(usage)
        return .usage
    }
}

private extension String {
    /// Padded to the width the usage text lines its descriptions up at.
    var padded: String {
        padding(toLength: 18, withPad: " ", startingAt: 0)
    }
}
