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
        case .gettingStarted: String(localized: "Getting Started")
        case .keyboard: String(localized: "Keyboard Shortcuts")
        case .comparing: String(localized: "Comparing Snapshots")
        case .pullRequests: String(localized: "Reviewing Pull Requests")
        case .automation: String(localized: "URL Scheme and CLI")
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
        HelpSection(title: String(localized: "Open a project"), blocks: [
            .text(String(localized: """
                Choose **File ▸ Open Project…** (⌘O), drag a folder onto the window, or pick one \
                from the recent list. GimDiff finds every snapshot folder in it and groups the \
                images under the test suite that recorded them.
                """)),
            .text(String(localized: """
                **File ▸ Open Recent** lists the same folders as the recent list. Hover over a \
                folder in the list and click its **×**, or right-click it, to forget it or \
                reveal it in the Finder; **Clear Recent Projects** forgets them all. The **×** \
                beside the project's name (or **File ▸ Close Project**) goes back to the list.
                """)),
        ]),
        HelpSection(title: String(localized: "Open images directly"), blocks: [
            .text(String(localized: """
                Drop one image on the window to look at it, or two to compare them: the first \
                is read as the baseline and the second as the candidate.
                """)),
            .text(String(localized: """
                **Paste** (⌘V, or the **Paste** button in the toolbar) works the same way. \
                Copy a failure log from Xcode or Swift Testing and GimDiff reads the image \
                paths out of it; copy files in the Finder and GimDiff opens them. A GitHub \
                pull request link opens that pull request.
                """)),
        ]),
        HelpSection(title: String(localized: "Find a snapshot"), blocks: [
            .text(String(localized: """
                Type in the sidebar's filter field (⌘F) to narrow the tree by name. The \
                **Modified** chip under it keeps only snapshots that differ from their \
                committed version, and **Warnings** keeps only suites whose test source could \
                not be found. Each chip appears only when the project has something it would \
                keep. **Edit ▸ Clear Filters**, ⎋ in the field, or the field's **×** puts the \
                whole tree back. To visit the changed snapshots without hiding the rest, use \
                **Snapshot ▸ Next Change** (⌥↓) and **Previous Change** (⌥↑), which open each \
                suite on the way.
                """)),
        ]),
        HelpSection(title: String(localized: "Act on a snapshot"), blocks: [
            .text(String(localized: """
                Right-click a row, or use the **Snapshot** menu on the selected one, to copy its \
                name, open it in Preview, reveal it in the Finder, open its snapshots folder, \
                open its test file in Xcode, or move it to the Trash. The buttons at the right \
                of each pane's header do the same for the image in that pane.
                """)),
        ]),
        HelpSection(title: String(localized: "Discard changes"), blocks: [
            .text(String(localized: """
                **Discard Changes** puts a modified snapshot back to its committed version; on \
                a suite it does so for every modified snapshot in it. **Discard All…**, beside \
                the filter chips (or **Snapshot ▸ Discard All Changes in Project…**), does it \
                for the whole project after asking first. Untracked snapshots are left alone. \
                A change that was never committed exists nowhere but in GimDiff's undo: \
                **Edit ▸ Undo** (⌘Z) puts it back until you open another project or quit.
                """)),
        ]),
        HelpSection(title: String(localized: "Failures from your test runs"), blocks: [
            .text(String(localized: """
                A project opens on its own status. Switch the sidebar from **Project** to \
                **Test Run** (or View ▸ Test Run) to read the newest run Xcode left in \
                DerivedData; the menu under the switch (or View ▸ Test Runs) lists every run \
                Xcode still keeps, to look at an older one instead. The sidebar lists only the \
                snapshots the run failed on, and \
                selecting one shows the image the test rendered against the recorded file. \
                Use **Diff Mask** to see where they differ. **Accept** re-records the snapshot without \
                running the test again, and **Accept All…** beside the run picker (or \
                **Snapshot ▸ Accept All Test Run Failures…**) does so for every failure at \
                once, after asking. When a test attached the snapshot more than once, click \
                the candidate's file name (or use **Snapshot ▸ Test Run Candidate**) to choose \
                which rendering to compare. Switch back to **Project** at any time; the run stays \
                read, and a new one is picked up as soon as Xcode finishes writing it — unless \
                you picked an older run, which stays until you pick the newest again.
                """)),
        ]),
        HelpSection(title: String(localized: "Messages"), blocks: [
            .text(String(localized: """
                What GimDiff has to tell you appears in a strip under the canvas. An \
                explanation — why an action is unavailable — goes away on its own after a few \
                seconds, unless the pointer is on it; a failure stays until you dismiss it. \
                **Window ▸ Recent Messages** keeps the last ten; choose one to copy it.
                """)),
        ]),
        HelpSection(title: String(localized: "After re-running your tests"), blocks: [
            .text(String(localized: """
                GimDiff watches the open project, so a test run shows up on its own: \
                rewritten images are redrawn, new and deleted snapshots come and go in the \
                tree, and the badges follow your commits — even while GimDiff is in the \
                background. **Refresh Images** (⌘R) and **Reload Project** (⇧⌘R) are there \
                for when you would rather ask: the first reads the images on screen off \
                disk again, the second rescans the whole folder from scratch.
                """)),
        ]),
    ]

    static let keyboardSections: [HelpSection] = [
        HelpSection(title: String(localized: "Project"), blocks: [
            .shortcuts([
                HelpShortcut("⌘O", String(localized: "Open a project folder")),
                HelpShortcut("⇧⌘O", String(localized: "Open a GitHub pull request")),
                HelpShortcut("⌘R", String(localized: "Refresh the images on screen")),
                HelpShortcut("⇧⌘R", String(localized: "Rescan the project")),
                HelpShortcut("⌘V", String(localized: "Paste a log, files, or a pull request link")),
            ]),
        ]),
        HelpSection(title: String(localized: "Sidebar"), blocks: [
            .text(String(localized: "These keys work while the snapshot tree has focus.")),
            .shortcuts([
                HelpShortcut("↑ ↓", String(localized: "Move the selection, showing each snapshot")),
                HelpShortcut("→", String(localized: "Open a suite, or step into its first snapshot")),
                HelpShortcut("←", String(localized: "Close a suite, or step up to it")),
                HelpShortcut("Space", String(localized: "Show or hide the selected snapshot")),
                HelpShortcut("↩", String(localized: "Open the suite's test file in Xcode")),
                HelpShortcut("/", String(localized: "Jump to the filter field")),
                HelpShortcut("⌥↓ ⌥↑", String(localized: "Jump to the next or previous changed snapshot")),
                HelpShortcut("⌘F", String(localized: "Jump to the filter field from anywhere")),
            ]),
        ]),
        HelpSection(title: String(localized: "Filter field"), blocks: [
            .shortcuts([
                HelpShortcut("↩ or ↓", String(localized: "Move to the first matching row")),
                HelpShortcut("⎋", String(localized: "Clear the filters and go back to the tree")),
            ]),
        ]),
        HelpSection(title: String(localized: "Snapshot"), blocks: [
            .shortcuts([
                HelpShortcut("⌘↩", String(localized: "Reveal the selection in the Finder")),
                HelpShortcut("⌘L", String(localized: "Clear the canvas")),
                HelpShortcut("⇧⌘C", String(localized: "Copy Split View or the onion skin as an image")),
                HelpShortcut("⌘= ⌘-", String(localized: "Zoom the images in and out")),
                HelpShortcut("⌘⌫", String(localized: "Move the selection to the Trash")),
                HelpShortcut("⌘Z ⇧⌘Z", String(localized: "Undo or redo the last change to a file")),
            ]),
        ]),
        HelpSection(title: String(localized: "Window"), blocks: [
            .shortcuts([
                HelpShortcut("⌘1", String(localized: "Show the sidebar")),
                HelpShortcut("⌘0", String(localized: "Hide the sidebar")),
                HelpShortcut("⌘?", String(localized: "Open this help")),
            ]),
        ]),
    ]

    static let comparingSections: [HelpSection] = [
        HelpSection(title: String(localized: "Candidate and baseline"), blocks: [
            .text(String(localized: """
                The **candidate** is the image your test just recorded: the file on disk. The \
                **baseline** is what it is measured against — the version committed to git, \
                or a reference image you opened beside it. The baseline is always on the left and the candidate on the right.
                """)),
            .text(String(localized: """
                Selecting a snapshot compares it with its committed version when git has one. \
                **Snapshot ▸ Show Snapshot without Git Diff** shows the file on its own.
                """)),
        ]),
        HelpSection(title: String(localized: "Comparison modes"), blocks: [
            .text(String(localized: """
                **Side by Side** shows the two images next to each other. **Split View** draws \
                both in one frame under a split you drag across it. **Onion Skin** lays the \
                candidate over the baseline; drag its slider to fade from one to the other, \
                and whatever moves is what changed. **Diff Mask** paints every changed \
                pixel in magenta and reports how much of the image changed. Switch between them \
                from the toolbar or the **View** menu. **View ▸ Onion Skin** jumps the fade to \
                either image or back to both equally, as the slider's **Reset** does.
                """)),
            .text(String(localized: """
                In **Split View** and **Onion Skin**, **Snapshot ▸ Copy Comparison Image** \
                (⇧⌘C) puts what you see on the clipboard as one picture, at the snapshots' own \
                resolution: cut where the split stands or faded as far as the slider goes, \
                with the sides and the setting written underneath. Paste it into a pull \
                request, an issue, or a chat.
                """)),
            .text(String(localized: """
                The mask's **Tolerance** menu (also **View ▸ Diff Tolerance**) lets through \
                differences nobody could see. It measures how far apart two pixels look, as a \
                ΔE: at ΔE 2.3, about the smallest visible change, anti-aliasing and rounding \
                stop being painted while real changes still are. Hover over the result to see \
                the largest difference between the two images. GimDiff remembers the setting.
                """)),
            .text(String(localized: """
                The **×** in a pane's header (or **Snapshot ▸ Close Baseline** and **Close \
                Candidate**) closes that side and leaves the other on screen on its own.
                """)),
        ]),
        HelpSection(title: String(localized: "Zoom and backgrounds"), blocks: [
            .text(String(localized: """
                Each pane has its own display mode: **Fit**, **Actual Size (1:1)**, or \
                **Free**. In Free, scroll or pinch over the image to zoom around the pointer, \
                drag to move it, or use the **−** and **+** buttons and type a factor between \
                them; the target button centres the image at 1.0 again. **View ▸ Image Size**, \
                **Zoom In** (⌘=), **Zoom Out** (⌘-), and **Centre and Reset Zoom** do the same \
                for every pane at once.
                """)),
            .text(String(localized: """
                Side by side, each pane zooms on its own. Click the link button in either \
                pane's footer (or **View ▸ Link Panes**) to zoom and move both together, so the \
                same part of each image stays under the same point.
                """)),
            .text(String(localized: """
                The toolbar's colour wells set the panel background and a matte behind the \
                image, which makes a transparent snapshot readable. **View ▸ Panel Background** \
                and **View ▸ Image Matte** offer the same presets.
                """)),
        ]),
        HelpSection(title: String(localized: "Accepting and rejecting"), blocks: [
            .text(String(localized: """
                The bar under a comparison decides it. **Accept** copies the candidate over \
                the baseline file. **Reject** copies the baseline over the candidate. Both \
                overwrite a file on disk; when one is unavailable, the bar says why.
                """)),
            .text(String(localized: """
                Every action that writes a snapshot — Accept, Reject, Keep, Accept All, \
                Discard, and Move to Trash — can be taken back with **Edit ▸ Undo** (⌘Z) and \
                repeated with **Redo** (⇧⌘Z), until you open another project or quit.
                """)),
            .text(String(localized: """
                A pair pasted from a failure log, dropped in, or opened by URL offers \
                **Keep Baseline** and **Keep Candidate** instead. Keeping the baseline writes \
                nothing; keeping the candidate copies it over the baseline. Either way the \
                baseline is left on screen on its own.
                """)),
            .text(String(localized: """
                GimDiff checks which side is which before showing the pair: a file Git \
                tracks, or one inside the open project, is the baseline, even when the log \
                listed it second. When nothing tells the two apart, the panes are called \
                **Left** and **Right** instead, and the bar offers **Keep Left** and \
                **Keep Right**: the image you keep is copied over the other one.
                """)),
            .text(String(localized: """
                When the baseline is the committed version there is nothing to accept into: \
                the candidate already is the working file, so commit it instead.
                """)),
        ]),
    ]

    static let pullRequestSections: [HelpSection] = [
        HelpSection(title: String(localized: "Open a pull request"), blocks: [
            .text(String(localized: """
                Choose **File ▸ Open Pull Request…** (⇧⌘O), or paste a pull request link. \
                The field takes a link, `owner/repo#123`, or a bare number from the open \
                project's repository.
                """)),
            .text(String(localized: """
                GimDiff downloads both versions of every changed image under a `Snapshots` or \
                `__Snapshots__` folder, without checking the branch out. Each snapshot is \
                marked **Added**, **Modified**, **Deleted**, or **Renamed**.
                """)),
        ]),
        HelpSection(title: String(localized: "Signing in"), blocks: [
            .text(String(localized: """
                GimDiff borrows the GitHub CLI's login and stores no token of its own. Install \
                `gh` and sign in once; only github.com is supported.
                """)),
            .code("gh auth login"),
        ]),
        HelpSection(title: String(localized: "A read-only review"), blocks: [
            .text(String(localized: """
                The downloaded images are scratch copies, so accepting, reverting, and \
                deleting are turned off. **File ▸ Close Pull Request Review** deletes the \
                copies and puts back the project you had open.
                """)),
        ]),
    ]

    static let automationSections: [HelpSection] = [
        HelpSection(title: String(localized: "gimdiff:// links"), blocks: [
            .text(String(localized: "Other tools can drive the open window with a link:")),
            .code("""
                gimdiff://open?path=/path/to/snapshots
                gimdiff://compare?reference=/path/a.png&failure=/path/b.png
                gimdiff://open-pr?url=https://github.com/owner/repo/pull/123
                """),
        ]),
        HelpSection(title: String(localized: "The gimdiff command"), blocks: [
            .text(String(localized: "The command-line tool hands work to the running app, or runs on its own:")),
            .code("""
                gimdiff <project-path>
                gimdiff <candidate> <baseline>
                gimdiff pr <url-or-number>
                gimdiff scan <project-path> [--json]
                gimdiff diff <candidate> <baseline> [--out <mask.png>] [--tolerance <ΔE>] [--json]
                gimdiff test-run <project-path> [--result <bundle>] [--out <folder>] [--tolerance <ΔE>] [--json]
                gimdiff parse-clipboard [--input "<log text>"] [--json]
                """),
            .text(String(localized: """
                It exits with `0` when there is nothing to report, `1` when the images or the \
                project differ, `2` when the command could not run, and `64` when the \
                arguments were not usable.
                """)),
        ]),
    ]
}
