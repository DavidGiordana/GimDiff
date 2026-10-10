//
//  TestRunBundle.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One result bundle Xcode left for a project, found without reading it.
struct TestRunBundle: Sendable, Hashable, Identifiable {
    /// The `.xcresult` folder.
    let url: URL
    /// When the run began, as the bundle records it; `nil` when it records nothing.
    let createdAt: Date?
    /// The workspace or package that ran the tests, by its file name.
    let workspaceName: String

    var id: URL { url }

    init(url: URL, createdAt: Date?, workspaceName: String) {
        self.url = url
        self.createdAt = createdAt
        self.workspaceName = workspaceName
    }

    /// The bundle's own name without its extension, for a run that records no date.
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}
