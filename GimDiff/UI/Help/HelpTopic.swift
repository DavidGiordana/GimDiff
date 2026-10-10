//
//  HelpTopic.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// One page of the help sheet.
///
/// The words live here as data rather than in the view, so a shortcut that moves in
/// ``AppCommands`` has one obvious place to be corrected in the help as well.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case keyboard
    case comparing
    case pullRequests
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .keyboard: "Keyboard Shortcuts"
        case .comparing: "Comparing Snapshots"
        case .pullRequests: "Reviewing Pull Requests"
        case .automation: "URL Scheme and CLI"
        }
    }

    var symbolName: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .keyboard: "keyboard"
        case .comparing: "rectangle.split.2x1"
        case .pullRequests: "arrow.triangle.pull"
        case .automation: "terminal"
        }
    }

    var sections: [HelpSection] {
        switch self {
        case .gettingStarted: Self.gettingStartedSections
        case .keyboard: Self.keyboardSections
        case .comparing: Self.comparingSections
        case .pullRequests: Self.pullRequestSections
        case .automation: Self.automationSections
        }
    }
}

/// A headed run of help content.
struct HelpSection: Identifiable {
    let title: String
    let blocks: [HelpBlock]

    var id: String { title }
}

/// One piece of a section. Text is Markdown, so `**bold**` and `` `code` `` render.
enum HelpBlock {
    case text(String)
    case shortcuts([HelpShortcut])
    case code(String)
}

/// A key, or a chord of keys, and what it does.
struct HelpShortcut: Identifiable {
    let keys: String
    let action: String

    var id: String { keys + action }

    init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }
}

// MARK: - Content

private extension HelpTopic {
    static let gettingStartedSections: [HelpSection] = [
        HelpSection(title: "Open a project", blocks: [
            .text("""
                Choose **File ▸ Open Project…** (⌘O), drag a folder onto the window, or pick one \
                from the recent list. GimDiff finds every snapshot folder in it and groups the \
                images under the test suite that recorded them.
                """),
        ]),
        HelpSection(title: "Open images directly", blocks: [
            .text("""
                Drop one image on the window to look at it, or two to compare them: the first \
                is read as the baseline and the second as the candidate.
                """),
            .text("""
                **Paste** (⌘V, or the **Paste** button in the toolbar) works the same way. \
                Copy a failure log from Xcode or Swift Testing and GimDiff reads the image \
                paths out of it; copy files in the Finder and GimDiff opens them. A GitHub \
                pull request link opens that pull request.
                """),
        ]),
        HelpSection(title: "Find a snapshot", blocks: [
            .text("""
                Type in the sidebar's filter field (⌘F) to narrow the tree by name. The \
                **Modified** chip under it keeps only snapshots that differ from their \
                committed version, and **Warnings** keeps only suites whose test source could \
                not be found. Each chip appears only when the project has something it would \
                keep.
                """),
        ]),
        HelpSection(title: "Failures from your test runs", blocks: [
            .text("""
                A project opens on its own status. Switch the sidebar from **Project** to \
                **Test Run** (or View ▸ Test Run) to read the newest run Xcode left in \
                DerivedData; the menu under the switch (or View ▸ Test Runs) lists every run \
                Xcode still keeps, to look at an older one instead. The sidebar lists only the \
                snapshots the run failed on, and \
                selecting one shows the image the test rendered against the recorded file. \
                Use **Diff Mask** to see where they differ. **Accept** re-records the snapshot without \
                running the test again. Switch back to **Project** at any time; the run stays \
                read, and a new one is picked up as soon as Xcode finishes writing it — unless \
                you picked an older run, which stays until you pick the newest again.
                """),
        ]),
        HelpSection(title: "After re-running your tests", blocks: [
            .text("""
                GimDiff watches the open project, so a test run shows up on its own: \
                rewritten images are redrawn, new and deleted snapshots come and go in the \
                tree, and the badges follow your commits — even while GimDiff is in the \
                background. **Refresh Images** (⌘R) and **Reload Project** (⇧⌘R) are there \
                for when you would rather ask: the first reads the images on screen off \
                disk again, the second rescans the whole folder from scratch.
                """),
        ]),
    ]

    static let keyboardSections: [HelpSection] = [
        HelpSection(title: "Project", blocks: [
            .shortcuts([
                HelpShortcut("⌘O", "Open a project folder"),
                HelpShortcut("⇧⌘O", "Open a GitHub pull request"),
                HelpShortcut("⌘R", "Refresh the images on screen"),
                HelpShortcut("⇧⌘R", "Rescan the project"),
                HelpShortcut("⌘V", "Paste a log, files, or a pull request link"),
            ]),
        ]),
        HelpSection(title: "Sidebar", blocks: [
            .text("These keys work while the snapshot tree has focus."),
            .shortcuts([
                HelpShortcut("↑ ↓", "Move the selection, showing each snapshot"),
                HelpShortcut("→", "Open a suite, or step into its first snapshot"),
                HelpShortcut("←", "Close a suite, or step up to it"),
                HelpShortcut("Space", "Show or hide the selected snapshot"),
                HelpShortcut("↩", "Open the suite's test file in Xcode"),
                HelpShortcut("/", "Jump to the filter field"),
                HelpShortcut("⌘F", "Jump to the filter field from anywhere"),
            ]),
        ]),
        HelpSection(title: "Filter field", blocks: [
            .shortcuts([
                HelpShortcut("↩ or ↓", "Move to the first matching row"),
                HelpShortcut("⎋", "Clear the filters and go back to the tree"),
            ]),
        ]),
        HelpSection(title: "Snapshot", blocks: [
            .shortcuts([
                HelpShortcut("⌘↩", "Reveal the selection in the Finder"),
                HelpShortcut("⌘L", "Clear the canvas"),
                HelpShortcut("⌘⌫", "Move the selection to the Trash"),
            ]),
        ]),
        HelpSection(title: "Window", blocks: [
            .shortcuts([
                HelpShortcut("⌘1", "Show the sidebar"),
                HelpShortcut("⌘0", "Hide the sidebar"),
                HelpShortcut("⌘?", "Open this help"),
            ]),
        ]),
    ]

    static let comparingSections: [HelpSection] = [
        HelpSection(title: "Candidate and baseline", blocks: [
            .text("""
                The **candidate** is the image your test just recorded: the file on disk. The \
                **baseline** is what it is measured against — the version committed to git, \
                or a reference image you opened beside it. The baseline is always on the left and the candidate on the right.
                """),
            .text("""
                Selecting a snapshot compares it with its committed version when git has one. \
                **Snapshot ▸ Show Snapshot without Git Diff** shows the file on its own.
                """),
        ]),
        HelpSection(title: "Comparison modes", blocks: [
            .text("""
                **Side by Side** shows the two images next to each other. **Split View** draws \
                both in one frame under a split you drag across it. **Onion Skin** lays the \
                candidate over the baseline; drag its slider to fade from one to the other, \
                and whatever moves is what changed. **Diff Mask** paints every changed \
                pixel in magenta and reports how much of the image changed. Switch between them \
                from the toolbar or the **View** menu.
                """),
        ]),
        HelpSection(title: "Zoom and backgrounds", blocks: [
            .text("""
                Each pane has its own display mode: **Fit**, **Actual Size (1:1)**, or \
                **Free**. In Free, scroll over the image to zoom around the pointer. The \
                toolbar's colour wells set the panel background and a matte behind the image, \
                which makes a transparent snapshot readable.
                """),
        ]),
        HelpSection(title: "Accepting and rejecting", blocks: [
            .text("""
                The bar under a comparison decides it. **Accept** copies the candidate over \
                the baseline file. **Reject** copies the baseline over the candidate. Both \
                overwrite a file on disk; when one is unavailable, the bar says why.
                """),
            .text("""
                A pair pasted from a failure log, dropped in, or opened by URL offers \
                **Keep Baseline** and **Keep Candidate** instead. Keeping the baseline writes \
                nothing; keeping the candidate copies it over the baseline. Either way the \
                baseline is left on screen on its own.
                """),
            .text("""
                GimDiff checks which side is which before showing the pair: a file Git \
                tracks, or one inside the open project, is the baseline, even when the log \
                listed it second. When nothing tells the two apart, the panes are called \
                **Left** and **Right** instead, and the bar offers **Keep Left** and \
                **Keep Right**: the image you keep is copied over the other one.
                """),
            .text("""
                When the baseline is the committed version there is nothing to accept into: \
                the candidate already is the working file, so commit it instead.
                """),
        ]),
    ]

    static let pullRequestSections: [HelpSection] = [
        HelpSection(title: "Open a pull request", blocks: [
            .text("""
                Choose **File ▸ Open Pull Request…** (⇧⌘O), or paste a pull request link. \
                The field takes a link, `owner/repo#123`, or a bare number from the open \
                project's repository.
                """),
            .text("""
                GimDiff downloads both versions of every changed image under a `Snapshots` or \
                `__Snapshots__` folder, without checking the branch out. Each snapshot is \
                marked **Added**, **Modified**, **Deleted**, or **Renamed**.
                """),
        ]),
        HelpSection(title: "Signing in", blocks: [
            .text("""
                GimDiff borrows the GitHub CLI's login and stores no token of its own. Install \
                `gh` and sign in once; only github.com is supported.
                """),
            .code("gh auth login"),
        ]),
        HelpSection(title: "A read-only review", blocks: [
            .text("""
                The downloaded images are scratch copies, so accepting, reverting, and \
                deleting are turned off. **File ▸ Close Pull Request Review** deletes the \
                copies and puts back the project you had open.
                """),
        ]),
    ]

    static let automationSections: [HelpSection] = [
        HelpSection(title: "gimdiff:// links", blocks: [
            .text("Other tools can drive the open window with a link:"),
            .code("""
                gimdiff://open?path=/path/to/snapshots
                gimdiff://compare?reference=/path/a.png&failure=/path/b.png
                gimdiff://open-pr?url=https://github.com/owner/repo/pull/123
                """),
        ]),
        HelpSection(title: "The gimdiff command", blocks: [
            .text("The command-line tool hands work to the running app, or runs on its own:"),
            .code("""
                gimdiff <project-path>
                gimdiff <candidate> <baseline>
                gimdiff pr <url-or-number>
                gimdiff scan <project-path> [--json]
                gimdiff diff <candidate> <baseline> [--out <mask.png>] [--json]
                gimdiff parse-clipboard [--input "<log text>"] [--json]
                """),
            .text("""
                It exits with `0` when there is nothing to report, `1` when the images or the \
                project differ, `2` when the command could not run, and `64` when the \
                arguments were not usable.
                """),
        ]),
    ]
}
