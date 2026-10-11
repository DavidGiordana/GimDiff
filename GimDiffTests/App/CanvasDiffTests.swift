//
//  CanvasDiffTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation
import Testing
@testable import GimDiff

/// What the canvas measures, and what it says about the measurement.
@Suite("Canvas measurements")
@MainActor
struct CanvasDiffTests {
    private static let candidateURL = URL(fileURLWithPath: "/Projects/Demo/failures/header.png")
    private static let baselineURL = URL(fileURLWithPath: "/Projects/Demo/Snapshots/header.png")

    private func state(
        imageDiff: StubImageDiffService,
        defaults: TemporaryDefaults
    ) -> AppState {
        let filesystem = MockFilesystemService()
        filesystem.stub(Self.candidateURL, contents: "candidate")
        filesystem.stub(Self.baselineURL, contents: "baseline")

        let state = AppState(
            filesystem: filesystem,
            gitService: StubGitService(),
            imageDiff: imageDiff,
            defaults: defaults.defaults
        )
        state.canvas.showComparison(reference: Self.baselineURL, failure: Self.candidateURL)
        return state
    }

    // MARK: - Measuring

    @Test("The comparison runs only while the diff mask is the mode on screen")
    func measuresOnlyForTheMask() async {
        let defaults = TemporaryDefaults()
        let state = state(imageDiff: StubImageDiffService(), defaults: defaults)

        state.canvas.updateDiffReport()
        await state.canvas.currentDiffComparison?.value
        #expect(state.canvas.diffReport == nil)
        #expect(state.canvas.isComputingDiff == false)

        state.canvas.diffMode = .difference
        state.canvas.updateDiffReport()
        await state.canvas.currentDiffComparison?.value

        #expect(state.canvas.diffReport?.differentPixelCount == 100)
        #expect(state.canvas.isComputingDiff == false)
    }

    @Test("Turning the mask back off drops the measurement with it")
    func clearsTheMeasurement() async {
        let defaults = TemporaryDefaults()
        let state = state(imageDiff: StubImageDiffService(), defaults: defaults)

        state.canvas.diffMode = .difference
        state.canvas.updateDiffReport()
        await state.canvas.currentDiffComparison?.value
        #expect(state.canvas.diffReport != nil)

        state.canvas.diffMode = .sideBySide
        state.canvas.updateDiffReport()
        #expect(state.canvas.diffReport == nil)
    }

    @Test("A new preview cannot be left describing the pair before it")
    func dropsTheReportWithThePreview() async {
        let defaults = TemporaryDefaults()
        let state = state(imageDiff: StubImageDiffService(), defaults: defaults)

        state.canvas.diffMode = .difference
        state.canvas.updateDiffReport()
        await state.canvas.currentDiffComparison?.value
        #expect(state.canvas.diffReport != nil)

        state.openPath(Self.candidateURL)
        #expect(state.canvas.diffReport == nil)
    }

    @Test("A comparison that cannot be made reaches the error banner")
    func reportsAFailedComparison() async {
        let defaults = TemporaryDefaults()
        let diff = StubImageDiffService(failure: GimDiffError.unreadableImage(Self.candidateURL))
        let state = state(imageDiff: diff, defaults: defaults)

        state.canvas.diffMode = .difference
        state.canvas.updateDiffReport()
        await state.canvas.currentDiffComparison?.value

        #expect(state.canvas.diffReport == nil)
        #expect(state.canvas.isComputingDiff == false)
        #expect(state.lastError != nil)
    }

    // MARK: - Reporting

    @Test("The footer pill leads with the number that matters")
    func summarisesAReport() {
        let matching = ImageDiffReport(
            candidateSize: CGSize(width: 100, height: 100),
            baselineSize: CGSize(width: 100, height: 100),
            hasIdenticalDimensions: true,
            differentPixelCount: 0,
            totalPixelCount: 10_000,
            diffPercentage: 0
        )
        #expect(DiffReportPill.summary(of: matching) == "100% Match")

        let changed = ImageDiffReport(
            candidateSize: CGSize(width: 1_000, height: 100),
            baselineSize: CGSize(width: 1_000, height: 100),
            hasIdenticalDimensions: true,
            differentPixelCount: 450,
            totalPixelCount: 100_000,
            diffPercentage: 0.45
        )
        let english = Locale(identifier: "en_US")
        #expect(DiffReportPill.summary(of: changed, locale: english) == "0.45% Diff (450 pixels)")
        // The number follows the locale; the words come from the app's language, English.
        let french = DiffReportPill.summary(of: changed, locale: Locale(identifier: "fr_FR"))
        #expect(french.hasPrefix("0,45"))
        #expect(french.hasSuffix(" Diff (450 pixels)"))

        let mismatched = ImageDiffReport(
            candidateSize: CGSize(width: 100, height: 100),
            baselineSize: CGSize(width: 100, height: 150),
            hasIdenticalDimensions: false,
            differentPixelCount: 10_000,
            totalPixelCount: 10_000,
            diffPercentage: 100
        )
        #expect(DiffReportPill.summary(of: mismatched) == "⚠️ Size Mismatch")
    }

    // MARK: - Git status

    @Test("A status refresh re-annotates the tree without rescanning it")
    func refreshesGitStatus() async {
        let defaults = TemporaryDefaults()
        let bundle = AppStateFixture.twoSuites()
        let footer = AppStateFixture.root
            .appendingPathComponent("Snapshots/AlphaTests/footer.png")

        let state = AppState(
            filesystem: MockFilesystemService(),
            gitService: StubGitService(
                repositoryRoot: AppStateFixture.root,
                statuses: [footer: .modified]
            ),
            watcher: StubProjectWatcher(),
            defaults: defaults.defaults
        )
        state.load(bundle)

        state.refreshGitStatus()
        await state.currentGitStatusRefresh?.value

        let alpha = state.currentProject?.suites.first { $0.name == "AlphaTests" }
        #expect(alpha?.snapshots.first { $0.name == "footer" }?.gitStatus == .modified)
        // `header` was modified in the built bundle and git no longer says so, which is the
        // whole point of re-reading: a promotion is visible as a badge going away.
        #expect(alpha?.snapshots.first { $0.name == "header" }?.gitStatus == .unmodified)
    }

    @Test("A repository with nothing to report clears every badge")
    func clearsGitStatusWhenNothingIsReported() async {
        let defaults = TemporaryDefaults()
        let state = AppState(
            filesystem: MockFilesystemService(),
            gitService: StubGitService(repositoryRoot: AppStateFixture.root),
            watcher: StubProjectWatcher(),
            defaults: defaults.defaults
        )
        state.load(AppStateFixture.twoSuites())

        state.refreshGitStatus()
        await state.currentGitStatusRefresh?.value

        #expect(state.currentProject?.hasGitDiff == false)
    }
}
