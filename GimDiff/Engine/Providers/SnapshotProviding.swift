//
//  SnapshotProviding.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Supplies the snapshot pairs shown in the sidebar.
///
/// Each testing framework lays its snapshots out differently, so a provider exists per
/// convention and is selected when a folder is opened.
protocol SnapshotProviding: Sendable {
    /// Name shown when GimDiff reports which convention it recognised.
    var name: String { get }

    /// Whether this provider recognises the layout under `folder`.
    func canHandle(folder: URL) async -> Bool

    /// Reference/failure pairs discovered under `folder`.
    func pairs(in folder: URL) async throws -> [SnapshotPair]
}
