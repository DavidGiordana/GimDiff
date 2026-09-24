//
//  ProviderIgnoreFilter.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Decides which directories snapshot discovery refuses to walk into.
///
/// A checked-out repository can carry tens of thousands of files that are certainly not
/// snapshots: resolved packages, derived data, vendored pods. Pruning those subtrees at the
/// directory level is what keeps a scan fast, so the filter is consulted before descending
/// rather than after collecting.
struct ProviderIgnoreFilter: Sendable, Equatable {
    /// Build products, dependency caches, and tooling folders, none of which hold snapshots
    /// a developer is working on.
    static let defaultIgnoredDirectoryNames: Set<String> = [
        "Tuist",
        ".build",
        ".swiftpm",
        "Derived",
        "DerivedData",
        "build",
        "Pods",
        "Carthage",
        "node_modules",
        "fastlane",
        ".git",
    ]

    /// Extensions of directories the Finder presents as a single document.
    ///
    /// The volume's own package flag covers `.xcodeproj` but not `.xcassets`, which is only
    /// a package once Xcode has registered the type — so the important one would be walked
    /// into, and an asset catalog holds thousands of images that are not snapshots.
    static let defaultIgnoredPathExtensions: Set<String> = [
        "app",
        "bundle",
        "docc",
        "framework",
        "playground",
        "xcarchive",
        "xcassets",
        "xcodeproj",
        "xcworkspace",
    ]

    /// Directory names pruned wherever they appear in the tree.
    let ignoredDirectoryNames: Set<String>
    /// Directory extensions pruned wherever they appear in the tree.
    let ignoredPathExtensions: Set<String>
    /// Multi-component paths pruned when a directory ends with one of them.
    let ignoredPathSuffixes: [String]

    init(
        ignoredDirectoryNames: Set<String> = defaultIgnoredDirectoryNames,
        ignoredPathExtensions: Set<String> = defaultIgnoredPathExtensions,
        ignoredPathSuffixes: [String] = []
    ) {
        self.ignoredDirectoryNames = ignoredDirectoryNames
        self.ignoredPathExtensions = ignoredPathExtensions
        self.ignoredPathSuffixes = ignoredPathSuffixes
    }

    /// Builds a filter from user-supplied entries, on top of the defaults.
    ///
    /// An entry without a separator names a directory and is pruned anywhere; an entry with
    /// one is treated as a path and pruned only where it matches.
    init(additionalIgnoredPaths: [String]) {
        var names = Self.defaultIgnoredDirectoryNames
        var suffixes: [String] = []

        for entry in additionalIgnoredPaths {
            let trimmed = entry.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard !trimmed.isEmpty else { continue }
            if trimmed.contains("/") {
                suffixes.append(trimmed)
            } else {
                names.insert(trimmed)
            }
        }

        self.init(ignoredDirectoryNames: names, ignoredPathSuffixes: suffixes)
    }

    /// Whether the walk should refuse to descend into `url`.
    ///
    /// Asked once per directory as the tree is walked, so pruning a parent prunes
    /// everything beneath it; the check itself only looks at `url` and never at what it
    /// contains.
    func shouldIgnore(url: URL) -> Bool {
        let name = url.lastPathComponent
        if ignoredDirectoryNames.contains(name) { return true }
        if ignoredPathExtensions.contains(url.pathExtension.lowercased()) { return true }

        let path = url.standardizedFileURL.path
        return ignoredPathSuffixes.contains { path == $0 || path.hasSuffix("/" + $0) }
    }
}
