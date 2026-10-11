//
//  AppCommands.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// GimDiff's menu bar, and with it every shortcut that has to work whatever is focused.
struct AppCommands: Commands {
    let state: AppState
    let delegate: AppDelegate

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.canvasBackdrop) private var canvasBackdrop

    var body: some Commands {
        let _ = registerWindowOpener()

        CommandGroup(replacing: .appInfo) {
            Button("About GimDiff") {
                delegate.showAboutPanel()
            }
        }

        // GimDiff shows one window, so there is nothing for File ▸ New to make.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .newItem) {
            Button("Open Project…") {
                state.promptForProject()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Pull Request…") {
                state.presentPullRequestSheet()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            // ⌘R refreshes the canvas rather than the project. A snapshot is looked at far
            // more often than a folder is rescanned, and rereading two images is the cheap
            // half of the pair, so the bare shortcut goes to the one used every minute.
            Button("Refresh Images") {
                state.refreshPreviewImages()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Reload Project") {
                state.reload()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            // Deliberately unshortcut'd: every spelling near ⌘W is already the window's, and
            // closing the project is not closing the window. The sidebar header carries the
            // button this mirrors.
            if state.isReviewingPullRequest {
                Button("Close Pull Request Review") {
                    state.closePullRequestReview()
                }
            } else {
                Button("Close Project") {
                    state.closeProject()
                }
            }

            // The sidebar's recent list again. Forgetting one folder stays on its row: a
            // menu has no way to point at the folder an item would remove.
            Menu("Open Recent") {
                ForEach(state.recentProjects, id: \.path) { url in
                    Button(url.lastPathComponent) {
                        state.openProject(at: url)
                    }
                }

                Divider()

                Button("Clear Recent Projects") {
                    state.clearRecentProjects()
                }
            }
            .disabled(state.recentProjects.isEmpty)
        }

        // Replaced rather than added to: an extra item bound to ⌘V would shadow the filter
        // field's paste, because AppKit matches key equivalents against the menu bar before
        // the first responder sees the event. `pasteCommand()` offers the key to the field
        // first and ingests the clipboard only when nothing took it.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { state.performEditAction(.cut) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { state.performEditAction(.copy) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste from Clipboard") { state.pasteCommand() }
                .keyboardShortcut("v", modifiers: .command)
            Button("Select All") { state.performEditAction(.selectAll) }
                .keyboardShortcut("a", modifiers: .command)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Expand Sidebar") {
                state.expandSidebar()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Collapse Sidebar") {
                state.collapseSidebar()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            // The sidebar's own Project / Test Run switch again, over the same state.
            Picker("Sidebar Shows", selection: sidebarSource) {
                Text("Project Status").tag(SidebarSource.project)
                Text("Test Run").tag(SidebarSource.testRun)
            }
            .pickerStyle(.inline)
            .disabled(!state.canShowTestRun)

            // And the sidebar's run picker, newest first.
            Picker("Test Runs", selection: testRunBundle) {
                ForEach(state.testRuns.bundles) { bundle in
                    Text(TestRunBundleLabel.title(of: bundle, among: state.testRuns.bundles))
                        .tag(Optional(bundle.url))
                }
            }
            .disabled(!state.canShowTestRun)

            Divider()

            Toggle("Show Only Modified Snapshots", isOn: binding(\.showGitModifiedOnly))
                .disabled(!state.canFilterByGitChanges)
            Toggle("Show Only Suites with Warnings", isOn: binding(\.showWarningsOnly))
                .disabled(!state.canFilterByWarnings)

            Divider()

            // The toolbar's comparison picker again: both write ``AppState/diffMode``, so a
            // picker over it here is the same control.
            Picker("Comparison", selection: binding(\.canvas.diffMode)) {
                Text("Side by Side").tag(DiffMode.sideBySide)
                Text("Split View").tag(DiffMode.curtain)
                Text("Onion Skin").tag(DiffMode.onionSkin)
                Text("Diff Mask").tag(DiffMode.difference)
            }
            .pickerStyle(.inline)
            .disabled(state.canvas.preview?.isComparison != true)

            // The diff mask footer's tolerance menu again. Enabled with any comparison, not
            // only under the mask: it is remembered, and set before switching to it.
            Picker("Diff Tolerance", selection: binding(\.canvas.diffTolerance)) {
                ForEach(DiffTolerance.presets, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(state.canvas.preview?.isComparison != true)

            Divider()

            // The footer controls of each pane, applied to every pane on screen at once.
            // ⌘0 is Collapse Sidebar's, so resetting the zoom goes without a shortcut.
            Menu("Image Size") {
                Button("Fit") { state.canvas.requestView(.fit) }
                Button("Actual Size (1:1)") { state.canvas.requestView(.actualSize) }
                Button("Free") { state.canvas.requestView(.free) }
            }
            .disabled(!state.canvas.hasZoomableImages)

            Button("Zoom In") { state.canvas.requestView(.zoomIn) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!state.canvas.hasZoomableImages)
            Button("Zoom Out") { state.canvas.requestView(.zoomOut) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!state.canvas.hasZoomableImages)
            Button("Centre and Reset Zoom") { state.canvas.requestView(.resetZoom) }
                .disabled(!state.canvas.hasZoomableImages)

            // The link button in each side-by-side pane's footer.
            Toggle("Link Panes", isOn: binding(\.canvas.linksPanes))
                .disabled(state.canvas.preview?.isComparison != true || state.canvas.diffMode != .sideBySide)

            // The onion skin's slider, at the three places worth going to by name.
            Menu("Onion Skin") {
                Button("\(onionSideTitle(.baseline)) Only") {
                    state.canvas.requestView(.fadeOnionSkin(to: 0))
                }
                Button("Both Equally") {
                    state.canvas.requestView(.fadeOnionSkin(to: CanvasModel.defaultOnionOpacity))
                }
                Button("\(onionSideTitle(.candidate)) Only") {
                    state.canvas.requestView(.fadeOnionSkin(to: 1))
                }
            }
            .disabled(!state.canvas.showsOnionSkin)

            Divider()

            // The toolbar's two colour wells, minus the custom colour, which needs the well.
            Picker("Panel Background", selection: canvasBackdrop?.panelBackground ?? .constant(nil)) {
                backdropChoices
            }
            .disabled(canvasBackdrop == nil)

            Picker("Image Matte", selection: canvasBackdrop?.imageMatte ?? .constant(nil)) {
                backdropChoices
            }
            .disabled(canvasBackdrop == nil)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find") {
                state.focusFilter()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Clear Filters") {
                state.clearFilters()
            }
            .disabled(!state.isFiltering)
        }

        // The ⌘-modified half of the tree's keyboard. AppKit offers a ⌘ shortcut to the
        // menu bar and never to the focused view's `keyDown(with:)`, so these cannot sit
        // beside the arrow keys in the sidebar's `onKeyPress` — and being menu items makes
        // them discoverable, which a bare key is not.
        //
        // The tree's bare keys — Space for the preview, ↩ for the test file — have items here
        // too, but without a shortcut: a menu item bound to a bare key is matched before the
        // first responder sees it, so it would fire while the user typed in the search box.
        CommandMenu("Snapshot") {
            Button(state.isShowingSelectedSnapshot ? "Hide Snapshot" : "Show Snapshot") {
                state.togglePreview()
            }
            .disabled(state.selectedSnapshot == nil)

            Button(state.compareActionTitle(for: state.selectedSnapshot)) {
                state.showSelectedSnapshot(withGitDiff: true)
            }
            .disabled(state.selectedSnapshot == nil)

            Button(state.showAloneActionTitle) {
                state.showSelectedSnapshot(withGitDiff: false)
            }
            .disabled(state.selectedSnapshot == nil)

            Divider()

            // ⌥ rather than bare arrows: the menu bar is matched before the tree's own key
            // handling, so a bare ↓ here would take the tree's ↓ away. ⌥↓ in the filter field
            // goes to the menu as well, which is the trade for reaching it from anywhere.
            Button("Next Change") {
                state.selectNextChange()
            }
            .keyboardShortcut(.downArrow, modifiers: .option)
            .disabled(!state.canStepThroughChanges)

            Button("Previous Change") {
                state.selectPreviousChange()
            }
            .keyboardShortcut(.upArrow, modifiers: .option)
            .disabled(!state.canStepThroughChanges)

            Divider()

            Button("Copy Name") {
                state.copySelectedRowName()
            }
            .disabled(state.selectedRowName == nil)

            // Only Split View and the onion skin: they are one picture on screen, so a copy
            // of them is what the user is looking at. ⇧⌘C rather than ⌘C, which stays Copy.
            Button("Copy Comparison Image") {
                state.copyComparisonImage(
                    backdrop: canvasBackdrop?.panelBackground.wrappedValue.map { NSColor($0).cgColor },
                    matte: canvasBackdrop?.imageMatte.wrappedValue.map { NSColor($0).cgColor }
                )
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!state.canvas.canCopyComparisonImage)

            Divider()

            Button("Open Test File in Xcode") {
                state.openTestSource()
            }
            .disabled(state.isReviewingPullRequest || state.selectedSuite?.sourceCodeURL == nil)

            Button("Open in Preview") {
                state.openSelectedSnapshotInPreviewApp()
            }
            .disabled(state.isReviewingPullRequest || state.selectedSnapshot == nil)

            Button("Reveal in Finder") {
                state.revealSelectionInFinder()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state.isReviewingPullRequest || state.selectedRow == nil)

            Button("Open Snapshots Folder") {
                state.openSnapshotsFolderForSelection()
            }
            .disabled(state.isReviewingPullRequest || state.selectedSuite == nil)

            Divider()

            // The same two choices the bar under the canvas offers, in the same words.
            if state.canvas.looseRolesAreUnknown {
                Button("Keep Left") {
                    state.keepLeft()
                }

                Button("Keep Right") {
                    state.keepRight()
                }
            } else if state.canvas.preview?.isLoosePair == true {
                Button("Keep Baseline") {
                    state.keepBaseline()
                }

                Button("Keep Candidate") {
                    state.keepCandidate()
                }
                .disabled(!state.canPromoteCandidate)
            } else {
                Button("Accept Candidate") {
                    state.promoteCandidateToBaseline()
                }
                .disabled(!state.canPromoteCandidate)

                Button("Reject Candidate") {
                    state.revertCandidateToBaseline()
                }
                .disabled(!state.canRevertToBaseline)
            }

            // Unshortcut'd for the same reason, and more so: it overwrites every snapshot
            // the run failed on.
            Button("Accept All Test Run Failures…") {
                state.requestAcceptAllTestRunFailures()
            }
            .disabled(state.acceptableTestRunFailuresCount == 0)

            // The candidate pane's file menu, for a test that attached the snapshot more
            // than once.
            if state.testRunCandidatesOnScreen.count > 1 {
                Picker("Test Run Candidate", selection: testRunCandidate) {
                    ForEach(state.testRunCandidatesOnScreen) { candidate in
                        Text(candidate.name).tag(Optional(candidate.fileURL))
                    }
                }
            }

            Divider()

            // Each pane header's close button.
            if state.canvas.preview?.isComparison == true, let panes = state.canvas.preview?.panes {
                ForEach(panes) { pane in
                    Button("Close \(state.canvas.sideTitle(for: pane))") {
                        state.closePane(pane.role)
                    }
                }
            }

            Button("Clear Canvas") {
                state.canvas.close()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(state.canvas.preview == nil)

            Divider()

            // No shortcut, for the reason Accept and Reject have none: it overwrites a file,
            // and git keeps no copy of a change that was never staged.
            Button(state.selectedSnapshot == nil ? "Discard Changes in Suite" : "Discard Changes") {
                state.discardSelectionGitChanges()
            }
            .disabled(state.discardableSelection.isEmpty)

            Button("Discard All Changes in Project…") {
                state.requestDiscardAllGitChanges()
            }
            .disabled(state.discardableProjectSnapshots.isEmpty)

            Button(state.selectedSnapshot == nil ? "Move Snapshots Folder to Trash" : "Move Snapshot to Trash") {
                state.deleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        // Replaced so the item opens GimDiff's own help sheet instead of the system's
        // "Help isn't available" alert. AppKit still adds its menu search field above it.
        // Every message that came and went, so one that closed itself or was replaced can be
        // read again. Choosing one copies it, for a bug report or a chat.
        CommandGroup(after: .windowArrangement) {
            Menu("Recent Messages") {
                ForEach(state.recentMessages) { message in
                    Button(Self.menuTitle(of: message)) {
                        state.copyToClipboard(message.text)
                    }
                }

                Divider()

                Button("Clear Recent Messages") {
                    state.clearRecentMessages()
                }
            }
            .disabled(state.recentMessages.isEmpty)
        }

        CommandGroup(replacing: .help) {
            Button("GimDiff Help") {
                state.presentHelp()
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    /// A binding onto one of the state's properties, which `Commands` cannot take with `$`.
    /// Switches through ``AppState/showTestRun()`` and ``AppState/showProjectStatus()``
    /// rather than assigning, because switching also reads the run and moves the selection.
    private var sidebarSource: Binding<SidebarSource> {
        Binding(
            get: { state.sidebarSource },
            set: { $0 == .testRun ? state.showTestRun() : state.showProjectStatus() }
        )
    }

    /// Shows the run picked through ``AppState/showTestRun(from:)``, switching the sidebar
    /// to it when it was showing the project.
    private var testRunBundle: Binding<URL?> {
        Binding(
            get: { state.testRuns.selectedBundle?.url },
            set: { url in url.map(state.showTestRun(from:)) }
        )
    }

    /// A message as a menu item: when it came, and as much of it as a menu has room for.
    private static func menuTitle(of message: AppMessage) -> String {
        let time = message.date.formatted(date: .omitted, time: .standard)
        let limit = 80
        let text = message.text.count > limit ? message.text.prefix(limit - 1) + "…" : message.text
        return "\(time) — \(text)"
    }

    /// The image in the candidate pane, switched through ``AppState/selectTestRunCandidate(_:)``.
    private var testRunCandidate: Binding<URL?> {
        Binding(
            get: { state.canvas.preview?.candidate?.fileURL },
            set: { url in
                guard let candidate = state.testRunCandidatesOnScreen.first(where: { $0.fileURL == url })
                else { return }
                state.selectTestRunCandidate(candidate)
            }
        )
    }

    /// What the onion skin calls one side, which is its position when the roles are unknown.
    private func onionSideTitle(_ role: SnapshotPane.Role) -> String {
        guard let pane = state.canvas.preview?.panes.first(where: { $0.role == role }) else {
            return role == .baseline ? "Baseline" : "Candidate"
        }
        return state.canvas.sideTitle(for: pane)
    }

    /// No colour, then the toolbar's presets in the same order.
    @ViewBuilder
    private var backdropChoices: some View {
        Text("None").tag(Color?.none)
        ForEach(BackdropColorButton.presets, id: \.name) { preset in
            Text(preset.name).tag(Optional(preset.color))
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppState, Value>) -> Binding<Value> {
        let state = state
        return Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0 }
        )
    }

    /// Hands `openWindow` to the app delegate, which AppKit calls outside any view.
    ///
    /// Done from the menu bar because the point is a launch with no window: when GimDiff is
    /// started to open a folder, SwiftUI treats it as a document launch and presents no
    /// scene, so no view exists to read the environment from. The menu bar is built either
    /// way. A `Commands` of its own would not do: one that contributes no items is never
    /// evaluated.
    private func registerWindowOpener() {
        let openWindow = openWindow
        delegate.openMainWindow = { openWindow(id: GimDiffApp.mainWindowID) }
    }
}
