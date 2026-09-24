//
//  ProjectFixture.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A throwaway project tree, built on demand and removed when the test releases it.
///
/// The trees are materialised at run time rather than checked in. Two reasons: the cache
/// folders discovery has to prune — `.build`, `.swiftpm`, `build`, `DerivedData` — are all
/// in this repository's own `.gitignore`, so a committed fixture would arrive empty on a
/// fresh clone and the ignore tests would pass without ever exercising the rule; and a
/// committed `*.swift` fixture would be compiled into the test target by the synchronized
/// folder, since GimDiffTests has no build-file exception set.
final class ProjectFixture {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GimDiffFixture-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a file at `relativePath`, along with any folders leading to it.
    @discardableResult
    func write(_ relativePath: String, contents: String = "snapshot") throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Absolute URL of `relativePath` inside the fixture, whether or not it exists.
    func fileURL(_ relativePath: String) -> URL {
        url.appendingPathComponent(relativePath).standardizedFileURL
    }

    // MARK: - Layouts

    /// A modular Swift project: a `Snapshots/` folder per module, one subfolder per suite.
    ///
    /// Carries decoy suites inside every folder discovery is meant to prune, so the ignore
    /// rules are tested by what is missing from the result rather than by an empty tree.
    static func modularProject() throws -> ProjectFixture {
        let fixture = try ProjectFixture()

        try fixture.write("Package.swift", contents: "// swift-tools-version:6.0")

        try fixture.write("Snapshots/UserProfileTests/profile_header.1.png")
        try fixture.write("Snapshots/UserProfileTests/profile_header.2.png")
        try fixture.write("Snapshots/UserProfileTests/profile_footer.png")
        try fixture.write("Snapshots/UserProfileTests/notes.txt", contents: "not an image")
        try fixture.write("Tests/UserProfileTests.swift", contents: "// UserProfileTests")

        try fixture.write("Features/Settings/Tests/Snapshots/SettingsViewTests/settings.1.png")
        try fixture.write("Features/Settings/Tests/SettingsViewTests.swift", contents: "// SettingsViewTests")

        // A cache can sit at the project root or deep inside a module, so the decoys cover
        // both: every one of these holds a suite that discovery must never reach.
        let caches = [
            "Tuist/.build",
            ".build/checkouts/Dependency",
            "Pods/SomePod",
            "DerivedData/Build",
            "Features/Settings/Tests/DerivedData/Build",
            "Features/Settings/Tests/Derived/Sources",
            "Features/Home/node_modules/pkg",
        ]
        for cache in caches {
            try fixture.write("\(cache)/Snapshots/CachedTests/cached.1.png")
            try fixture.write("\(cache)/Snapshots/CachedTests/CachedTests.swift", contents: "// decoy")
        }

        return fixture
    }

    /// A project using swift-snapshot-testing's `__Snapshots__` convention.
    static func pointFreeProject() throws -> ProjectFixture {
        let fixture = try ProjectFixture()

        try fixture.write("Package.swift", contents: "// swift-tools-version:6.0")
        try fixture.write("Tests/__Snapshots__/ButtonTests/button.1.png")
        try fixture.write("Tests/__Snapshots__/ButtonTests/button.2.png")
        try fixture.write("Tests/ButtonTests.swift", contents: "// ButtonTests")

        return fixture
    }
}
