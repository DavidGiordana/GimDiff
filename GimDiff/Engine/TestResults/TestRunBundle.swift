//
//  TestRunBundle.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One test run left for a project, found without reading it: a result bundle Xcode
/// wrote, or the failure folders Paparazzi's verify tasks did.
struct TestRunBundle: Sendable, Hashable, Identifiable {
    /// The `.xcresult` folder, or the project's root for Paparazzi's failures, which are
    /// spread over its modules.
    let url: URL
    /// When the run began, as the bundle records it; `nil` when it records nothing.
    let createdAt: Date?
    /// The workspace or package that ran the tests, by its file name.
    let workspaceName: String
    /// The folders Paparazzi wrote the run's renderings into, one per module and variant.
    /// Empty for an Xcode bundle, which is the whole run in one folder.
    let failureFolders: [URL]

    var id: URL { url }

    init(url: URL, createdAt: Date?, workspaceName: String, failureFolders: [URL] = []) {
        self.url = url
        self.createdAt = createdAt
        self.workspaceName = workspaceName
        self.failureFolders = failureFolders
    }

    /// The bundle's own name without its extension, for a run that records no date.
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}
