//
//  CanvasModel.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// What the detail column shows and how: the pair on screen, the comparison mode, the pixel
/// measurement, and the settings the canvas remembers.
///
/// Owns the canvas and nothing about the tree. Which image a selected row should put on
/// screen — a test run's rendering, a pull request's version, the committed file — is
/// ``AppState``'s to decide; it then hands the choice here.
@MainActor
@Observable
final class CanvasModel {
    /// `UserDefaults` key the diff mask's tolerance is remembered under, as a ΔE.
    static let diffToleranceKey = "diff_tolerance_delta_e"
    /// `UserDefaults` key Link Panes is remembered under.
    static let linksPanesKey = "links_panes"
    /// Commit-ish a snapshot is compared against when its Git diff is shown.
    static let comparisonGitRef = "HEAD"

    /// What the canvas is showing. Changed through ``show(_:)`` and the methods built on it.
    private(set) var preview: SnapshotPreview?
    /// How a pair is compared. Survives a change of preview: stepping through a folder of
    /// snapshots in curtain mode should stay in curtain mode.
    var diffMode: DiffMode = .sideBySide
    /// Pixel comparison of the two panes, recomputed whenever the diff mask is on.
    private(set) var diffReport: ImageDiffReport?
    /// Whether that comparison is in flight, so the footer can say so rather than go blank.
    private(set) var isComputingDiff = false
    /// How far apart two pixels may be before the diff mask paints them.
    ///
    /// Remembered across launches: it describes the renderer a project's tests run on,
    /// which does not change from one snapshot to the next.
    var diffTolerance: DiffTolerance = .exact {
        didSet {
            guard diffTolerance != oldValue else { return }
            defaults.set(diffTolerance.maximumDeltaE, forKey: Self.diffToleranceKey)
            updateDiffReport()
        }
    }
    /// Whether the two side-by-side panes zoom and pan together.
    ///
    /// Off by default, because the panes' independence is the point when one is held at 1:1
    /// on a detail while the other stays fitted. Remembered once turned on, as a way of
    /// working rather than a property of one comparison.
    var linksPanes = false {
        didSet { defaults.set(linksPanes, forKey: Self.linksPanesKey) }
    }
    /// How the sides of a loose pair were chosen, while one is on screen.
    ///
    /// `nil` for anything else: a snapshot's own comparison has sides the project gave it.
    private(set) var looseRoleCertainty: LooseRoleCertainty?
    /// Bumped to make the canvas read its images off disk again.
    ///
    /// A counter rather than a flag because the file name never changes: nothing about the
    /// URL tells a view that the bytes behind it were rewritten by a test run.
    private(set) var imageReloadToken = 0
    /// The last View menu command addressed to the canvas's own controls.
    ///
    /// Display mode, zoom, and the onion skin's fade belong to the views that draw them, so
    /// the menu cannot set them directly; it posts a request each of those views carries
    /// out. The serial makes the same command twice in a row two requests.
    private(set) var viewRequest: CanvasViewRequest?

    /// Where a comparison that failed is reported, which is the window's banner. Set by
    /// ``AppState`` once it exists.
    @ObservationIgnored var reportError: @MainActor (any Error) -> Void = { _ in }

    @ObservationIgnored private let imageDiff: any ImageDiffService
    @ObservationIgnored private let gitService: any GitService
    @ObservationIgnored private let defaults: UserDefaults
    /// Held so a second diff request supersedes the first rather than racing it.
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var committedVersionTask: Task<Void, Never>?
    @ObservationIgnored private var looseRoleTask: Task<Void, Never>?

    init(imageDiff: any ImageDiffService, gitService: any GitService, defaults: UserDefaults) {
        self.imageDiff = imageDiff
        self.gitService = gitService
        self.defaults = defaults
        // Assigned here, where the property observers do not run, so loading a setting does
        // not write it straight back.
        diffTolerance = DiffTolerance(maximumDeltaE: defaults.double(forKey: Self.diffToleranceKey))
        linksPanes = defaults.bool(forKey: Self.linksPanesKey)
    }

    // MARK: - Showing

    /// Replaces what the canvas is showing, dropping anything measured about the last pair.
    ///
    /// Every route into ``preview`` runs through here: a report left over from the previous
    /// pair would otherwise keep describing it under the new one's images.
    func show(_ newValue: SnapshotPreview?) {
        diffTask?.cancel()
        // Whatever the canvas shows next, a pair still being decided is no longer wanted.
        looseRoleTask?.cancel()
        looseRoleCertainty = nil
        preview = newValue
        diffReport = nil
        isComputingDiff = false
    }

    /// Clears the canvas, abandoning a committed version still being extracted.
    func close() {
        committedVersionTask?.cancel()
        show(nil)
    }

    /// Abandons a committed version still being extracted, for a caller about to show
    /// something else.
    func cancelCommittedVersion() {
        committedVersionTask?.cancel()
    }

    /// Shows `snapshot`, upgraded to a comparison with its committed version once git has
    /// written that out.
    ///
    /// The image is put on screen immediately: extracting the committed file spawns a
    /// process, and waiting for that before drawing anything would make every selection
    /// feel slow.
    ///
    /// - Parameter gitRoot: The repository the snapshot is in; `nil` shows it on its own.
    func showWithCommittedVersion(_ snapshot: SnapshotItem, gitRoot: URL?) {
        committedVersionTask?.cancel()
        show(.single(snapshot))

        guard snapshot.gitStatus == .modified,
              let gitRoot,
              let relativePath = AppState.relativePath(of: snapshot.fileURL, under: gitRoot)
        else { return }

        committedVersionTask = Task { [gitService] in
            // An untracked or newly added snapshot has nothing at HEAD to compare with, so
            // a failure here is ordinary: the image stays on screen on its own.
            guard let committed = try? await gitService.extractCommittedVersion(
                ofFileAt: relativePath,
                repositoryRoot: gitRoot,
                gitRef: Self.comparisonGitRef
            ) else { return }

            guard !Task.isCancelled, preview?.snapshotID == snapshot.id else { return }
            show(.comparison(
                SnapshotPair(reference: committed, failure: snapshot.fileURL),
                snapshotID: snapshot.id,
                title: snapshot.displayName,
                baselineOrigin: .committedVersion
            ))
        }
    }

    /// The committed-version extraction in flight, if any, so a caller can wait for it.
    var currentGitDiff: Task<Void, Never>? { committedVersionTask }

    /// Shows two loose images side by side, from a drop, the clipboard, or a URL.
    ///
    /// - Parameter certainty: How the sides were chosen. A caller that named them — a
    ///   `gimdiff://compare` URL — leaves the default.
    func showComparison(reference: URL, failure: URL, certainty: LooseRoleCertainty = .stated) {
        committedVersionTask?.cancel()
        show(.comparison(
            SnapshotPair(reference: reference, failure: failure),
            snapshotID: nil,
            title: failure.deletingPathExtension().lastPathComponent,
            baselineOrigin: .workingTree
        ))
        looseRoleCertainty = certainty
    }

    /// Shows a pasted or dropped pair once ``LooseRoleResolver`` has looked at the files.
    ///
    /// The pair is shown only after: drawing it in the source's order first and swapping
    /// it a moment later would put a baseline label on the wrong image, however briefly.
    func showLooseComparison(baseline: URL, candidate: URL, rolesAreStated: Bool, projectRoot: URL?) {
        looseRoleTask?.cancel()
        let resolver = LooseRoleResolver(gitService: gitService)
        looseRoleTask = Task {
            let resolution = await resolver.resolve(
                baseline: baseline,
                candidate: candidate,
                rolesAreStated: rolesAreStated,
                projectRoot: projectRoot
            )
            guard !Task.isCancelled else { return }
            showComparison(
                reference: resolution.baselineURL,
                failure: resolution.candidateURL,
                certainty: resolution.certainty
            )
        }
    }

    /// The side decision in flight for a pasted or dropped pair, if any.
    var currentLooseRoleResolution: Task<Void, Never>? { looseRoleTask }

    // MARK: - Sides

    /// Whether the pair on screen is loose and nothing could tell which side is the
    /// baseline, so neither may be called one.
    var looseRolesAreUnknown: Bool {
        preview?.isLoosePair == true && looseRoleCertainty == .unknown
    }

    /// What to call a pane on screen: its role, or its position when the roles are unknown.
    func sideTitle(for pane: SnapshotPane) -> String {
        guard looseRolesAreUnknown else { return pane.roleTitle }
        return pane.role == .baseline ? "Left" : "Right"
    }

    // MARK: - Diff mask

    /// Measures the two panes against each other, or clears the measurement.
    ///
    /// Driven by the canvas rather than by every mutation that could invalidate it: the
    /// comparison decodes both images, so it runs when the mask is actually on screen and
    /// not on the chance that it might be.
    func updateDiffReport() {
        diffTask?.cancel()

        guard diffMode == .difference,
              let candidate = preview?.candidate,
              let baseline = preview?.baseline
        else {
            setDiffReport(nil)
            return
        }

        setDiffReport(nil, isComputing: true)
        diffTask = Task { [imageDiff, diffTolerance] in
            do {
                let measured = try await imageDiff.compare(
                    candidateURL: candidate.fileURL,
                    baselineURL: baseline.fileURL,
                    tolerance: diffTolerance
                )
                guard !Task.isCancelled else { return }
                setDiffReport(measured)
            } catch {
                guard !Task.isCancelled else { return }
                setDiffReport(nil)
                reportError(error)
            }
        }
    }

    /// The pixel comparison in flight, if any, so a caller can wait for it.
    var currentDiffComparison: Task<Void, Never>? { diffTask }

    private func setDiffReport(_ report: ImageDiffReport?, isComputing: Bool = false) {
        diffReport = report
        isComputingDiff = isComputing
    }

    // MARK: - Images and view commands

    /// Makes every view holding a decoded image read it off disk again.
    func invalidateLoadedImages() {
        imageReloadToken += 1
    }

    /// Whether anything on screen has the display mode and zoom the View menu drives: a
    /// single image, a side-by-side pair, or the diff mask. The curtain and the onion skin
    /// draw both images in one fixed frame.
    var hasZoomableImages: Bool {
        guard let preview else { return false }
        guard preview.isComparison else { return true }
        return diffMode == .sideBySide || diffMode == .difference
    }

    /// Whether the onion skin is on screen for the View menu's fade commands to reach.
    var showsOnionSkin: Bool {
        preview?.isComparison == true && diffMode == .onionSkin
    }

    /// Hands `command` to whichever canvas views it applies to.
    func requestView(_ command: CanvasViewCommand) {
        viewRequest = CanvasViewRequest(serial: (viewRequest?.serial ?? 0) + 1, command: command)
    }
}
