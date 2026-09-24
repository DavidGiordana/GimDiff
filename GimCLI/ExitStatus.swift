//
//  ExitStatus.swift
//  gimdiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Status `gimdiff` exits with.
///
/// The split between ``differencesFound`` and ``failure`` is what lets a build script tell
/// "the snapshots moved" from "the tool could not run", which a single non-zero code cannot.
enum ExitStatus: Int32, Sendable {
    /// The command ran, and found nothing to report.
    case success = 0
    /// The command ran, and the images or the log it examined did not match.
    case differencesFound = 1
    /// The command could not complete.
    case failure = 2
    /// The arguments were not usable.
    case usage = 64
}
