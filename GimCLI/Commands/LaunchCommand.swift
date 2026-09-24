//
//  LaunchCommand.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import Foundation

/// `gimdiff <project>` and `gimdiff <candidate> <baseline>`
///
/// The launcher path: paths with no subcommand hand the work to the GUI.
///
/// The tool never spawns the app itself. It builds a `gimdiff://` URL and gives it to
/// LaunchServices, which routes it to the copy of GimDiff already running and delivers it
/// through `application(_:open:)`. That is what keeps the single-window mandate intact from
/// the terminal: a second `gimdiff` in a second tab retargets the open window rather than
/// putting a second one beside it.
enum LaunchCommand {
    static let summary = "Open a project, or one comparison, in the running GimDiff window."
    static let usage = """
    Usage: gimdiff <project-path>
           gimdiff <candidate> <baseline>

      Hands the paths to GimDiff through the gimdiff:// URL scheme, bringing the existing
      window to the front and loading them into it.
    """

    static let valueOptions: Set<String> = []
    static let knownOptions: Set<String> = []

    static func run(_ arguments: Arguments, console: Console) async throws -> ExitStatus {
        try arguments.rejectOptions(outside: knownOptions)
        try arguments.rejectPositionalArguments(beyond: 2)

        let url = try urlToOpen(for: arguments)
        try await open(url)

        console.write("Opened \(url.absoluteString)")
        return .success
    }

    /// Chooses the action from the shape of the arguments: one folder opens a project, two
    /// images open the comparison between them.
    static func urlToOpen(for arguments: Arguments) throws -> URL {
        let first = try arguments.fileURL(at: 0, named: "path")

        guard arguments.positional.count > 1 else {
            guard DefaultFilesystemService().isDirectory(at: first) else {
                throw LaunchFailure.notAProjectFolder(first)
            }
            return try url(host: "open", parameters: [("path", first)])
        }

        let baseline = try arguments.fileURL(at: 1, named: "baseline")
        return try url(
            host: "compare",
            parameters: [("reference", baseline), ("failure", first)]
        )
    }

    /// Builds a `gimdiff://` URL, letting `URLComponents` encode the paths.
    ///
    /// Hand-assembling the query would be the bug that a snapshot folder named
    /// `Home Screen & Detail` finds: `&` inside a value has to arrive escaped.
    private static func url(host: String, parameters: [(name: String, url: URL)]) throws -> URL {
        var components = URLComponents()
        components.scheme = GimDiffURLCommand.scheme
        components.host = host
        components.queryItems = parameters.map { URLQueryItem(name: $0.name, value: $0.url.path) }

        guard let url = components.url else { throw LaunchFailure.malformedURL(host) }
        return url
    }

    /// Hands the URL to LaunchServices with activation requested.
    private static func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.open(url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Reasons the launcher could not hand its arguments to the app.
    enum LaunchFailure: Error, Equatable {
        /// The single path given is not a folder, so there is no project to open.
        case notAProjectFolder(URL)
        /// The paths could not be assembled into a URL.
        case malformedURL(String)
    }
}

extension LaunchCommand.LaunchFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .notAProjectFolder(url):
            "“\(url.path)” is not a folder. Pass a project folder, or two images to compare."
        case let .malformedURL(host):
            "the paths could not be assembled into a gimdiff://\(host) URL."
        }
    }
}
