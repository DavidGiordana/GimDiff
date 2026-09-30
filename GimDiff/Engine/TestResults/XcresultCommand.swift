//
//  XcresultCommand.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Builds `xcresulttool` invocations as discrete argument arrays.
///
/// A result bundle's storage is private to Xcode and has changed between releases, so
/// GimDiff never opens one itself. `xcresulttool` is the reader Xcode ships for it, and
/// what it prints follows a schema of its own.
enum XcresultCommand {
    /// `xcrun` rather than the tool itself: the tool lives inside whichever Xcode is
    /// selected, and only `xcrun` knows where that is.
    static let executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

    /// Prints the tree of everything the run executed, with the outcome of each node.
    static func tests(in bundle: URL) -> Command {
        command(["get", "test-results", "tests", "--path", bundle.path, "--compact"])
    }

    /// Prints the totals of the run, with when it started and finished.
    static func summary(of bundle: URL) -> Command {
        command(["get", "test-results", "summary", "--path", bundle.path, "--compact"])
    }

    /// Prints what one test did, step by step, with the attachments each step recorded.
    static func activities(ofTest testIdentifier: String, in bundle: URL) -> Command {
        command([
            "get", "test-results", "activities",
            "--path", bundle.path,
            "--test-id", testIdentifier,
            "--compact",
        ])
    }

    /// Writes every attachment one test recorded into `directory`, creating it if needed.
    ///
    /// `--only-failures` is deliberately absent. It keeps the attachments Xcode tied to the
    /// failure itself, and the images a snapshot assertion attaches are recorded beside the
    /// failure rather than on it.
    static func exportAttachments(
        ofTest testIdentifier: String,
        in bundle: URL,
        to directory: URL
    ) -> Command {
        command([
            "export", "attachments",
            "--path", bundle.path,
            "--output-path", directory.path,
            "--test-id", testIdentifier,
        ])
    }

    private static func command(_ arguments: [String]) -> Command {
        Command(executableURL: executableURL, arguments: ["xcresulttool"] + arguments)
    }
}
