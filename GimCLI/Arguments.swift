//
//  Arguments.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One command's arguments, split into positional values, flags, and options.
///
/// Hand-rolled rather than taken from a package: the grammar is three subcommands and four
/// options, and a dependency would be a larger change to the project than the parser it
/// replaces.
struct Arguments: Sendable {
    /// Error raised for input the grammar cannot accept.
    enum Failure: Error, Equatable {
        /// An option that takes a value was last on the line.
        case missingValue(option: String)
        /// A flag or option the command does not define.
        case unknownOption(String)
        /// A required positional argument was absent.
        case missingArgument(name: String)
        /// More positional arguments than the command accepts.
        case unexpectedArgument(String)
        /// An option given a value it cannot take.
        case invalidValue(option: String, value: String)
    }

    /// Values given without a leading dash, in the order they appeared.
    private(set) var positional: [String] = []
    /// Options given as `--name value` or `--name=value`.
    private(set) var options: [String: String] = [:]
    /// Options given on their own.
    private(set) var flags: Set<String> = []

    /// Splits `raw`, treating any `--name` in `valueOptions` as taking the token after it.
    ///
    /// - Throws: ``Failure/missingValue(option:)`` when such an option ends the line.
    init(_ raw: [String], valueOptions: Set<String> = []) throws {
        var iterator = raw.makeIterator()

        while let token = iterator.next() {
            // A lone "--" ends option parsing, so a file really named "--json" can be passed.
            if token == "--" {
                while let remaining = iterator.next() { positional.append(remaining) }
                break
            }

            guard token.hasPrefix("-"), token.count > 1 else {
                positional.append(token)
                continue
            }

            let name = Self.normalize(token)
            if let separator = name.firstIndex(of: "=") {
                options[String(name[name.startIndex..<separator])] = String(
                    name[name.index(after: separator)...]
                )
            } else if valueOptions.contains(name) {
                guard let value = iterator.next() else { throw Failure.missingValue(option: name) }
                options[name] = value
            } else {
                flags.insert(name)
            }
        }
    }

    /// Whether `--name` was given.
    func hasFlag(_ name: String) -> Bool { flags.contains(name) }

    /// The value of `--name`, if it was given.
    func value(of name: String) -> String? { options[name] }

    /// The positional argument at `index`, named for the error raised when it is absent.
    func argument(at index: Int, named name: String) throws -> String {
        guard index < positional.count else { throw Failure.missingArgument(name: name) }
        return positional[index]
    }

    /// Rejects positional arguments beyond `count`, which a typo in an option name produces.
    func rejectPositionalArguments(beyond count: Int) throws {
        guard positional.count > count else { return }
        throw Failure.unexpectedArgument(positional[count])
    }

    /// Rejects any flag or option the command does not define.
    func rejectOptions(outside known: Set<String>) throws {
        let given = flags.union(options.keys)
        guard let unknown = given.subtracting(known).sorted().first else { return }
        throw Failure.unknownOption("--" + unknown)
    }

    /// Strips the leading dashes and folds the name to lower case.
    private static func normalize(_ token: String) -> String {
        var name = Substring(token)
        while name.hasPrefix("-") { name = name.dropFirst() }
        return name.lowercased()
    }
}

extension Arguments.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            "--\(option) needs a value."
        case let .unknownOption(name):
            "unknown option \(name)."
        case let .missingArgument(name):
            "missing required argument <\(name)>."
        case let .unexpectedArgument(value):
            "unexpected argument “\(value)”."
        case let .invalidValue(option, value):
            "--\(option) cannot be “\(value)”."
        }
    }
}

extension Arguments {
    /// Reads a positional path, expanding a leading tilde and resolving it against the
    /// working directory the CLI was invoked from.
    func fileURL(at index: Int, named name: String) throws -> URL {
        Self.fileURL(from: try argument(at: index, named: name))
    }

    /// Reads a path given as an option value.
    func fileURL(of option: String) -> URL? {
        value(of: option).map(Self.fileURL(from:))
    }

    static func fileURL(from path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        // Relative to the shell's directory rather than to whatever the tool's is: the
        // person typed the path against what `pwd` prints.
        return URL(
            fileURLWithPath: expanded,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
    }
}
