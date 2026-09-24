//
//  GimDiffError.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Errors surfaced by the engine.
enum GimDiffError: Error, Equatable {
    /// A `gimdiff://` URL used an unexpected scheme.
    case unsupportedScheme(String?)
    /// A `gimdiff://` URL named an action the app does not implement.
    case unsupportedAction(String?)
    /// A required query parameter was absent or empty.
    case missingParameter(String)
    /// A command exited with a non-zero status.
    case commandFailed(command: String, exitCode: Int32, message: String)
    /// The given location is not inside a Git working tree.
    case notARepository(URL)
}

extension GimDiffError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedScheme(scheme):
            "“\(scheme ?? "(none)")” is not a GimDiff URL scheme."
        case let .unsupportedAction(action):
            "GimDiff does not know how to handle the action “\(action ?? "(none)")”."
        case let .missingParameter(name):
            "The URL is missing the required “\(name)” parameter."
        case let .commandFailed(command, exitCode, message):
            "“\(command)” failed with status \(exitCode): \(message)"
        case let .notARepository(url):
            "“\(url.path)” is not inside a Git repository."
        }
    }
}
