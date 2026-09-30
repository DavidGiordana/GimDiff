//
//  ProjectWatching.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One path the volume reported as created, removed, renamed, or rewritten.
struct ProjectFileEvent: Sendable, Hashable {
    let url: URL
    /// Whether the path names a folder.
    ///
    /// Carried with the event because the path may be gone by the time anybody looks: a
    /// folder that was moved away cannot be asked what it was.
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
    }
}

/// Reports what changes under a set of folders, for as long as somebody is listening.
///
/// Declared here and implemented in `Infrastructure/`, so the engine can say what a change
/// means without knowing how the volume is observed, and tests can hand over events no
/// disk ever produced.
protocol ProjectWatching: Sendable {
    /// Batches of changes beneath `roots`, until the caller stops iterating.
    ///
    /// Paths come back spelled under the root they were found beneath, exactly as that
    /// root was given, so they compare equal to the paths a scan of it discovered.
    func changes(under roots: [URL]) -> AsyncStream<[ProjectFileEvent]>
}
