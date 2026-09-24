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
/// Two shapes are understood:
///
/// - `gimdiff://open?path=/some/snapshot/folder`
/// - `gimdiff://compare?reference=/path/a.png&failure=/path/b.png`
enum GimDiffURLCommand: Equatable, Sendable {
    /// Load every snapshot pair found under a folder.
    case open(folder: URL)
    /// Load a single explicit comparison.
    case compare(reference: URL, failure: URL)

    /// The scheme GimDiff is registered to handle.
    static let scheme = "gimdiff"

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

        switch components?.host?.lowercased() {
        case "open":
            self = .open(folder: try Self.fileURL(named: "path", in: parameters))
        case "compare":
            self = .compare(
                reference: try Self.fileURL(named: "reference", in: parameters),
                failure: try Self.fileURL(named: "failure", in: parameters)
            )
        case let action:
            throw GimDiffError.unsupportedAction(action)
        }
    }

    private static func fileURL(named name: String, in parameters: [String: String]) throws -> URL {
        guard let path = parameters[name] else { throw GimDiffError.missingParameter(name) }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }
}
