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
    /// No snapshot provider recognised the layout of a project folder.
    case unrecognisedProjectLayout(URL)
    /// A file is missing, or holds no image any installed decoder understands.
    case unreadableImage(URL)
    /// A pixel buffer or an encoder could not be created for an image.
    case imageProcessingFailed(URL)
    /// A test result bundle answered with something other than the report it was asked for.
    case unreadableTestResults(URL)
}

extension GimDiffError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedScheme(scheme):
            String(localized: "“\(scheme ?? String(localized: "(none)"))” is not a GimDiff URL scheme.")
        case let .unsupportedAction(action):
            String(localized: "GimDiff does not know how to handle the action “\(action ?? String(localized: "(none)"))”.")
        case let .missingParameter(name):
            String(localized: "The URL is missing the required “\(name)” parameter.")
        case let .commandFailed(command, exitCode, message):
            String(localized: "“\(command)” failed with status \(exitCode): \(message)")
        case let .notARepository(url):
            String(localized: "“\(url.path)” is not inside a Git repository.")
        case let .unrecognisedProjectLayout(url):
            String(localized: "GimDiff found no snapshots it recognises under “\(url.path)”.")
        case let .unreadableImage(url):
            String(localized: "“\(url.path)” could not be read as an image.")
        case let .imageProcessingFailed(url):
            String(localized: "“\(url.path)” could not be prepared for comparison.")
        case let .unreadableTestResults(url):
            String(localized: "The test results in “\(url.path)” could not be read.")
        }
    }
}
