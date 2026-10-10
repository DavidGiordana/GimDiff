//
//  AppStateFixture.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
@testable import GimDiff

/// An `AppState` wired to doubles, with a hand-built project already loaded.
///
/// The projection, navigation, and deletion rules are all about the shape of a bundle, so
/// the bundles are written out here rather than scanned off a disk: a suite with no source
/// file and a snapshot git reports as modified are both one line, and neither needs a
/// working tree to exist.
@MainActor
struct AppStateFixture {
    let state: AppState
    let filesystem: MockFilesystemService
    /// Stands in for FSEvents, so the only file events are the ones a test sends.
    let watcher = StubProjectWatcher()
    /// Stands in for derived data, so no run is found unless a test sets one up.
    let testResults = StubTestResults()
    /// Records what a discard asked git to restore.
    let gitService: StubGitService
    /// Held for its lifetime: releasing it erases the defaults domain.
    let defaults: TemporaryDefaults

    /// Root the built bundles hang off.
    static let root = URL(fileURLWithPath: "/Projects/Demo", isDirectory: true)

    init(bundle: ProjectBundle? = nil, gitService: StubGitService = StubGitService()) {
        let filesystem = MockFilesystemService()
        let defaults = TemporaryDefaults()

        self.filesystem = filesystem
        self.defaults = defaults
        self.gitService = gitService
        state = AppState(
            filesystem: filesystem,
            gitService: gitService,
            watcher: watcher,
            testResults: testResults,
            testResultLocator: testResults,
            defaults: defaults.defaults
        )

        guard let bundle else { return }
        for suite in bundle.suites {
            filesystem.createDirectory(at: suite.snapshotsFolderURL)
            for snapshot in suite.snapshots {
                filesystem.stub(snapshot.fileURL, contents: "png")
            }
        }
        state.load(bundle)
    }

    // MARK: - Bundles

    /// Two suites: `AlphaTests` with three snapshots, `BetaTests` with two and no source file.
    static func twoSuites() -> ProjectBundle {
        ProjectBundle(
            rootURL: root,
            gitRootURL: root,
            suites: [
                suite(
                    named: "AlphaTests",
                    hasSourceCode: true,
                    snapshots: [
                        ("header", .modified),
                        ("footer", .unmodified),
                        ("sidebar", .unmodified),
                    ]
                ),
                suite(
                    named: "BetaTests",
                    hasSourceCode: false,
                    snapshots: [
                        ("toolbar", .untracked),
                        ("menu", .unmodified),
                    ]
                ),
            ]
        )
    }

    static func suite(
        named name: String,
        hasSourceCode: Bool,
        snapshots: [(name: String, gitStatus: GitFileStatus)]
    ) -> SnapshotSuite {
        let folder = root.appendingPathComponent("Snapshots/\(name)", isDirectory: true)
        return SnapshotSuite(
            name: name,
            sourceCodeURL: hasSourceCode
                ? root.appendingPathComponent("Tests/\(name).swift")
                : nil,
            snapshotsFolderURL: folder,
            snapshots: snapshots.map { snapshot in
                SnapshotItem(
                    name: snapshot.name,
                    fileURL: folder.appendingPathComponent("\(snapshot.name).png"),
                    gitStatus: snapshot.gitStatus
                )
            },
            providerId: "test"
        )
    }

    // MARK: - Reading rows

    /// The visible rows as `SuiteName` and `SuiteName/snapshot`, which is short enough to
    /// assert the whole projection against in one expression.
    var rowDescriptions: [String] {
        let rows = state.visibleRows
        // Read off the rows rather than the project: a suite of the test run's attachments
        // is a row without being part of the project.
        var suiteNames: [String: String] = [:]
        for case let .suite(suite, _, _) in rows {
            suiteNames[suite.id] = suite.name
        }

        return rows.map { row in
            switch row {
            case let .suite(suite, _, _):
                return suite.name
            case let .snapshot(snapshot, parentSuiteID):
                return "\(suiteNames[parentSuiteID] ?? "?")/\(snapshot.displayName)"
            }
        }
    }

    /// Description of the selected row, in the same form as ``rowDescriptions``.
    var selectedRowDescription: String? {
        guard let id = state.selectedRowID,
              let index = state.visibleRows.firstIndex(where: { $0.id == id })
        else { return nil }
        return rowDescriptions[index]
    }

    func select(_ description: String) {
        state.selectedRowID = rowID(description)
    }

    func rowID(_ description: String) -> String? {
        guard let index = rowDescriptions.firstIndex(of: description) else { return nil }
        return state.visibleRows[index].id
    }

    func suiteID(_ name: String) -> String {
        state.currentProject?.suites.first { $0.name == name }?.id ?? ""
    }

    func expand(_ name: String) {
        state.toggleExpansion(ofSuiteWithID: suiteID(name))
    }
}
