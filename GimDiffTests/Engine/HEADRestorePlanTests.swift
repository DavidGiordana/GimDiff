//
//  HEADRestorePlanTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Planning a restore to HEAD")
struct HEADRestorePlanTests {
    private let folder = URL(fileURLWithPath: "/repo/Snapshots/AlphaTests", isDirectory: true)

    private func file(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    private func suite(_ snapshots: [(String, GitFileStatus)]) -> SnapshotSuite {
        SnapshotSuite(
            name: "AlphaTests",
            snapshotsFolderURL: folder,
            snapshots: snapshots.map { SnapshotItem(name: $0.0, fileURL: file("\($0.0).png"), gitStatus: $0.1) },
            providerId: "test"
        )
    }

    @Test("What HEAD has is restored, and what it does not have goes to the Trash")
    func sortsEachChange() {
        let plan = HEADRestorePlan(
            suites: [suite([("edited", .modified), ("staged", .added), ("fresh", .untracked), ("clean", .unmodified)])],
            statuses: [
                file("edited.png"): .modified,
                file("staged.png"): .added,
                file("fresh.png"): .untracked,
                file("gone.png"): .deleted,
            ]
        )

        #expect(plan.committedURLs == [file("edited.png"), file("gone.png")])
        #expect(plan.trashedURLs == [file("staged.png"), file("fresh.png")])
        #expect(plan.restoredURLs == [file("edited.png"), file("gone.png"), file("staged.png")])
    }

    @Test("A file in a folder git reports untracked as a whole is trashed")
    func inheritsACollapsedFolder() {
        let plan = HEADRestorePlan(
            suites: [suite([("fresh", .untracked)])],
            statuses: [folder: .untracked]
        )

        #expect(plan.trashedURLs == [file("fresh.png")])
    }

    @Test("Only git's answer sends a file to the Trash")
    func staleAnnotationNeverTrashes() {
        let plan = HEADRestorePlan(
            suites: [suite([("fresh", .untracked), ("edited", .modified)])],
            statuses: [:]
        )

        #expect(plan.trashedURLs.isEmpty)
        #expect(plan.committedURLs == [file("edited.png")])
    }

    @Test("A deleted path outside every snapshot folder, or not an image, is left alone")
    func keepsToSnapshotFolders() {
        let plan = HEADRestorePlan(
            suites: [suite([])],
            statuses: [
                URL(fileURLWithPath: "/repo/Sources/App.swift"): .deleted,
                URL(fileURLWithPath: "/repo/Other/gone.png"): .deleted,
                file("notes.txt"): .deleted,
            ]
        )

        #expect(plan.isEmpty)
    }

    @Test("A project matching HEAD has nothing to do")
    func emptyWhenClean() {
        #expect(HEADRestorePlan(suites: [suite([("clean", .unmodified)])], statuses: [:]).isEmpty)
    }
}
