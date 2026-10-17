//
//  IngestionService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Turns pasted text into something GimDiff can open: a copied test failure log becomes a
/// comparison, and a link becomes a pull request. A `gimdiff://` URL is read by
/// ``GimDiffURLCommand`` instead.
protocol IngestionService: Sendable {
    /// Recovers image paths from pasted text, typically an Xcode or Swift Testing failure log.
    ///
    /// - Returns: `nil` when the text names no image.
    func parseClipboardText(_ text: String) -> IngestionPayload?

    /// Finds a GitHub pull request link in pasted text, such as a chat message holding one.
    ///
    /// - Returns: `nil` when the text links to no pull request on `github.com`.
    func parsePullRequest(_ text: String) -> GitHubPRReference?
}
