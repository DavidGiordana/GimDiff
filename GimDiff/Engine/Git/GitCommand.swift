//
//  GitCommand.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Builds `git` invocations as discrete argument arrays.
///
/// Every factory below returns a `Command` whose arguments are already separated, so no
/// caller ever has to quote or escape a path.
enum GitCommand {
    /// Location of the Git executable shipped with the developer tools.
    static let executableURL = URL(fileURLWithPath: "/usr/bin/git")

    /// Prints the absolute path of the working tree containing `directory`.
    static func revParseToplevel(in directory: URL) -> Command {
        command(["rev-parse", "--show-toplevel"], in: directory)
    }

    /// Prints the name of the checked-out branch, or `HEAD` when detached.
    static func currentBranch(in directory: URL) -> Command {
        command(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
    }

    /// Prints the URL the remote called `name` fetches from.
    static func remoteURL(named name: String, in directory: URL) -> Command {
        command(["remote", "get-url", "--", name], in: directory)
    }

    /// Lists modified and untracked paths, one `XY path` record per line.
    ///
    /// `core.quotePath` is disabled so snapshot names containing non-ASCII characters come
    /// back verbatim rather than octal-escaped.
    static func status(in directory: URL) -> Command {
        command(
            ["-c", "core.quotePath=false", "status", "--porcelain=v1", "--untracked-files=all"],
            in: directory
        )
    }

    /// Succeeds when `path` is a file Git tracks, and fails when it is not.
    static func lsFilesErrorUnmatch(path: URL, in directory: URL) -> Command {
        command(["ls-files", "--error-unmatch", "--", path.path], in: directory)
    }

    /// Restores `paths` to their committed state.
    static func checkout(paths: [URL], in directory: URL) -> Command {
        command(["checkout", "--"] + paths.map(\.path), in: directory)
    }

    /// Stages `paths`.
    static func add(paths: [URL], in directory: URL) -> Command {
        command(["add", "--"] + paths.map(\.path), in: directory)
    }

    private static func command(_ arguments: [String], in directory: URL) -> Command {
        Command(executableURL: executableURL, arguments: arguments, workingDirectory: directory)
    }
}
