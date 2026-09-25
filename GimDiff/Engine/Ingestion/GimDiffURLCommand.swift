//
//  GimDiffURLCommand.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// An instruction delivered to the app through the `gimdiff://` URL scheme.
///
/// Three shapes are understood:
///
/// - `gimdiff://open?path=/some/snapshot/folder`
/// - `gimdiff://compare?reference=/path/a.png&failure=/path/b.png`
/// - `gimdiff://open-pr?url=https://github.com/owner/repo/pull/123`
///
/// Each action and each parameter also answers to the vocabulary the rest of GimDiff uses
/// for the same thing — `open-project` for the first, `baseline` and `candidate` for the
/// second — so a URL assembled from what the CLI calls its arguments opens the app instead
/// of being rejected over a synonym.
///
/// `open` reads as either shape. It is the verb anything handing GimDiff a path reaches for
/// first, and a URL that names a pair of images rather than a folder is unambiguously the
/// comparison between them; rejecting it over the host name would be pedantry.
enum GimDiffURLCommand: Equatable, Sendable {
    /// Load every snapshot pair found under a folder.
    case open(folder: URL)
    /// Load a single explicit comparison.
    case compare(reference: URL, failure: URL)
    /// Review the snapshots a GitHub pull request changes.
    ///
    /// Carried as the text it arrived as rather than parsed here: a bare number is a valid
    /// request, and only the app knows which repository the open project belongs to.
    case openPullRequest(String)

    /// The scheme GimDiff is registered to handle.
    static let scheme = "gimdiff"

    /// Hosts that open a folder, and the parameters each reads the folder from.
    static let openActions = ["open", "open-project"]
    static let folderParameterNames = ["path", "project", "folder"]
    /// Hosts that open one comparison.
    static let compareActions = ["compare", "diff"]
    static let referenceParameterNames = ["reference", "baseline", "recorded", "expected"]
    static let failureParameterNames = ["failure", "candidate", "actual", "new"]
    /// Hosts that open a pull request review.
    static let pullRequestActions = ["open-pr", "pr", "pull-request", "review-pr"]
    static let pullRequestParameterNames = ["url", "pr", "reference", "number"]

    /// Parses an incoming URL.
    ///
    /// - Throws: `GimDiffError` when the scheme, action, or parameters are not usable.
    init(url: URL) throws {
        guard url.scheme?.lowercased() == Self.scheme else {
            throw GimDiffError.unsupportedScheme(url.scheme)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let parameters = components?.queryItems?.reduce(into: [String: String]()) { result, item in
            guard let value = item.value, !value.isEmpty else { return }
            result[item.name] = value
        } ?? [:]

        let action = components?.host?.lowercased()
        switch action {
        case let action? where Self.compareActions.contains(action):
            self = try Self.comparison(in: parameters)
        case let action? where Self.pullRequestActions.contains(action):
            guard let reference = Self.value(named: Self.pullRequestParameterNames, in: parameters) else {
                throw GimDiffError.missingParameter(Self.pullRequestParameterNames[0])
            }
            self = .openPullRequest(reference)
        case let action? where Self.openActions.contains(action):
            // A folder parameter settles it. Without one, a named candidate means the URL
            // is carrying a pair, and anything else is an `open` missing its path — which
            // is the error to report rather than a comparison missing both sides.
            if Self.value(named: Self.folderParameterNames, in: parameters) == nil,
               Self.value(named: Self.failureParameterNames, in: parameters) != nil {
                self = try Self.comparison(in: parameters)
            } else {
                self = .open(
                    folder: try Self.fileURL(named: Self.folderParameterNames, in: parameters)
                )
            }
        default:
            throw GimDiffError.unsupportedAction(action)
        }
    }

    private static func comparison(in parameters: [String: String]) throws -> Self {
        .compare(
            reference: try fileURL(named: referenceParameterNames, in: parameters),
            failure: try fileURL(named: failureParameterNames, in: parameters)
        )
    }

    /// The first of `names` the URL carried, or `nil` when it carried none of them.
    private static func value(named names: [String], in parameters: [String: String]) -> String? {
        names.lazy.compactMap { parameters[$0] }.first
    }

    /// The first of `names` the URL carried, reported against the preferred spelling when
    /// it carried none.
    private static func fileURL(named names: [String], in parameters: [String: String]) throws -> URL {
        guard let path = value(named: names, in: parameters) else {
            throw GimDiffError.missingParameter(names[0])
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }
}
