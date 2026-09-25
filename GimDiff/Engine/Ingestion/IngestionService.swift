//
//  IngestionService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Turns text and URLs arriving from elsewhere into a comparison GimDiff can open.
///
/// The two entry points are a copied test failure log and the `gimdiff://` URL scheme.
protocol IngestionService: Sendable {
    /// Recovers image paths from pasted text, typically an Xcode or Swift Testing failure log.
    ///
    /// - Returns: `nil` when the text names no image.
    func parseClipboardText(_ text: String) -> IngestionPayload?

    /// Reads a comparison out of a `gimdiff://` URL.
    ///
    /// - Returns: `nil` when the URL is not GimDiff's or names no candidate image.
    func parseURLScheme(_ url: URL) -> IngestionPayload?

    /// Finds a GitHub pull request link in pasted text, such as a chat message holding one.
    ///
    /// - Returns: `nil` when the text links to no pull request on `github.com`.
    func parsePullRequest(_ text: String) -> GitHubPRReference?
}
