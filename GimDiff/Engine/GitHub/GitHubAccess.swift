//
//  GitHubAccess.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Sends one HTTP request and hands back what came back, whatever its status.
///
/// The engine names this rather than `URLSession` so the GitHub service can be exercised
/// against canned responses: a test that reached the real API would depend on the network,
/// on a token, and on a pull request nobody may ever edit again.
protocol HTTPClient: Sendable {
    /// - Throws: Only when no response arrived at all. A `404` is a response, and is
    ///   returned for the caller to interpret.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Supplies the token GimDiff presents to the GitHub API.
///
/// GimDiff never stores a token of its own. It borrows whichever one the GitHub CLI is
/// logged in with, so there is nothing to set up and nothing to leak from GimDiff's
/// preferences.
protocol GitHubTokenProviding: Sendable {
    func token() async throws -> String
}
