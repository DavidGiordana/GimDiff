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

    /// Prints the URL the remote called `name` fetches from.
    static func remoteURL(named name: String, in directory: URL) -> Command {
        command(["remote", "get-url", "--", name], in: directory)
    }

    /// Machine-readable status of the working tree.
    ///
    /// Porcelain rather than `-s`, which follows the user's configuration: `color.status`
    /// would put escape codes in every record and `status.branch` add one of its own.
    /// `-z` ends each record with a NUL and never quotes a path, so a name holding an accent
    /// or a quote comes back as written. The untracked files are asked for explicitly,
    /// because `status.showUntrackedFiles=no` would otherwise leave every new snapshot out;
    /// `normal` reports a new folder as one record, which ``ProviderRegistry`` resolves.
    static func status(in directory: URL) -> Command {
        command(
            ["-c", "core.quotePath=false", "status", "--porcelain=v1", "-z", "--untracked-files=normal"],
            in: directory
        )
    }

    /// Writes the contents of `relativePath` at `gitRef` to standard output.
    ///
    /// One argument, `ref:path`, so a path holding spaces or shell characters reaches git
    /// as it is spelled.
    static func show(ofFileAt relativePath: String, gitRef: String, in directory: URL) -> Command {
        command(["show", "\(gitRef):\(normalize(relativePath))"], in: directory)
    }

    /// Succeeds when `path` is a file Git tracks, and fails when it is not.
    static func lsFilesErrorUnmatch(path: URL, in directory: URL) -> Command {
        command(["ls-files", "--error-unmatch", "--", path.path], in: directory)
    }

    /// Puts `paths` back to what `HEAD` holds, in the index and the working tree alike.
    ///
    /// `restore` rather than `checkout --`: checkout copies from the index, so a change that
    /// was staged would survive being discarded.
    static func restoreFromHEAD(paths: [URL], in directory: URL) -> Command {
        command(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths.map(\.path), in: directory)
    }

    /// Strips the leading `./` or `/` that would make a repository-relative path absolute.
    static func normalize(_ relativePath: String) -> String {
        var path = relativePath
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    private static func command(_ arguments: [String], in directory: URL) -> Command {
        Command(executableURL: executableURL, arguments: arguments, workingDirectory: directory)
    }
}
