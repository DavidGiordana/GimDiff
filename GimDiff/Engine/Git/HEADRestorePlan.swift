//
//  HEADRestorePlan.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What putting a project's snapshots back to `HEAD` takes, worked out from Git's status.
///
/// `git restore --source=HEAD` brings back every path `HEAD` has, and deletes every path it
/// does not have. Those files — added, untracked, the new name of a rename — are moved to
/// the Trash before git runs instead, so nothing recorded is lost without a way back.
struct HEADRestorePlan: Sendable, Equatable {
    /// Snapshots `HEAD` has that differ from it: modified, deleted, or a rename's old name.
    private(set) var committedURLs: [URL] = []
    /// Snapshots staged at a path `HEAD` does not have.
    private(set) var stagedURLs: [URL] = []
    /// Snapshots Git does not track at all.
    private(set) var untrackedURLs: [URL] = []

    /// Paths handed to `git restore --source=HEAD --staged --worktree`: the committed ones
    /// come back, and the staged ones, already in the Trash, leave the index.
    var restoredURLs: [URL] { committedURLs + stagedURLs }
    /// Files moved to the Trash before git runs, because `HEAD` has nothing at their path.
    var trashedURLs: [URL] { stagedURLs + untrackedURLs }
    var isEmpty: Bool { committedURLs.isEmpty && trashedURLs.isEmpty }

    /// - Parameters:
    ///   - suites: The project's suites; only files inside their folders are planned for.
    ///   - statuses: What Git reported just now, which decides what goes to the Trash.
    init(suites: [SnapshotSuite], statuses: [URL: GitFileStatus]) {
        let byPath = Dictionary(
            statuses.map { ($0.key.standardizedFileURL.path, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<String> = []

        for snapshot in suites.flatMap(\.snapshots) {
            let url = snapshot.fileURL.standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }

            // Only Git's answer can send a file to the Trash. The tree's annotation may be
            // older, so it can add a restore at most: restoring a file that already matches
            // `HEAD` changes nothing.
            switch ProviderRegistry.status(forFileAt: url, in: byPath) {
            case .added?: stagedURLs.append(url)
            case .untracked?: untrackedURLs.append(url)
            case .modified?: committedURLs.append(url)
            case .deleted?, .unmodified?, nil:
                if snapshot.gitStatus == .modified { committedURLs.append(url) }
            }
        }

        // A deleted snapshot has no row, since a scan lists what is on disk, so it is found
        // in the status instead, under the folder of the suite it was recorded in.
        let folders = suites.map { $0.snapshotsFolderURL.standardizedFileURL.path + "/" }
        for (url, status) in statuses where status == .deleted {
            let url = url.standardizedFileURL
            guard url.isImageFile,
                  folders.contains(where: url.path.hasPrefix),
                  seen.insert(url.path).inserted
            else { continue }
            committedURLs.append(url)
        }

        committedURLs.sort { $0.path < $1.path }
        stagedURLs.sort { $0.path < $1.path }
        untrackedURLs.sort { $0.path < $1.path }
    }
}
