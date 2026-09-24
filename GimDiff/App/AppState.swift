//
//  AppState.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Observation

/// State shared by every view in the single GimDiff window.
@MainActor
@Observable
final class AppState {
    /// Snapshot comparisons currently loaded.
    private(set) var pairs: [SnapshotPair] = []
    /// The comparison shown on the canvas.
    var selection: SnapshotPair.ID?
    /// How the selected comparison is rendered.
    var diffMode: DiffMode = .sideBySide
    /// The most recent failure, shown as a banner until it is dismissed.
    private(set) var lastError: String?

    private let fileSystem: FileSystemService
    private let provider: any SnapshotProviding

    init(
        fileSystem: FileSystemService = FileSystemService(),
        provider: any SnapshotProviding = DirectorySnapshotProvider()
    ) {
        self.fileSystem = fileSystem
        self.provider = provider
    }

    /// The comparison matching ``selection``, if one is selected.
    var selectedPair: SnapshotPair? {
        pairs.first { $0.id == selection }
    }

    /// Acts on a `gimdiff://` URL delivered by the system.
    func handle(_ url: URL) {
        do {
            switch try GimDiffURLCommand(url: url) {
            case let .open(folder):
                open(folder: folder)
            case let .compare(reference, failure):
                load([SnapshotPair(reference: reference, failure: failure)])
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Loads every matched reference/failure pair found under `folder`.
    func open(folder: URL) {
        guard fileSystem.isDirectory(at: folder) else {
            lastError = "“\(folder.path)” is not a folder."
            return
        }

        Task {
            do {
                load(try await provider.pairs(in: folder))
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func dismissError() {
        lastError = nil
    }

    private func load(_ newPairs: [SnapshotPair]) {
        pairs = newPairs
        selection = newPairs.first?.id
        lastError = newPairs.isEmpty ? "No matching snapshot pairs were found." : nil
    }
}
