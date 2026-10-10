# GimDiff — Development Guide

GimDiff is a native macOS visual snapshot diffing and management tool.
Bundle identifier: `com.davidgiordana.GimDiff`.

## Commands

Build:

```sh
xcodebuild -scheme GimDiff -destination 'platform=macOS' build
```

Test:

```sh
xcodebuild -scheme GimDiff -destination 'platform=macOS' test
```

Run a single suite or test while iterating:

```sh
xcodebuild -scheme GimDiff -destination 'platform=macOS' test -only-testing:GimDiffTests
xcodebuild -scheme GimDiff -destination 'platform=macOS' test -only-testing:GimDiffTests/GitCommandTests
```

The `gimdiff` command-line tool is a second target in the same project:

```sh
xcodebuild -scheme gimdiff -destination 'platform=macOS' build
```

All three commands must finish clean — no errors and no new warnings — before a change is
considered done.

### If a test run leaves the app wedged

A cancelled test run can orphan `debugserver` with the host app stopped under it (`ps`
shows state `SX`, and `kill -9` has no effect). The next run then fails with
`Failed to terminate com.davidgiordana.GimDiff`. Kill the debugger, then the app:

```sh
pkill -9 debugserver
pkill -9 -f 'GimDiff.app/Contents/MacOS/GimDiff'
```

## Platform

- **Deployment target:** macOS 14.0 (Sonoma).
- **Language:** Swift 6 language mode, full concurrency checking.
- **Default actor isolation:** `nonisolated`. UI types opt in to `@MainActor` (SwiftUI's
  `View` and `App` already do). This keeps `Engine/` usable from any executor instead of
  pinning the whole module to the main actor.
- **App Sandbox:** off. GimDiff spawns `/usr/bin/git` and reads snapshot folders anywhere
  on disk; neither is possible inside the sandbox. Do not re-enable it without replacing
  the process-running strategy.

## Architecture

```
GimDiff/
├── App/             App lifecycle, AppState, URL scheme handling, Window scene
├── Engine/          Pure Swift: models, providers, Git, diffing, ingestion
├── Infrastructure/  Process runner, filesystem, clipboard
├── UI/              Sidebar, tree, viewers, canvas, colour pickers
└── Extensions/      Foundation and SwiftUI helpers

GimCLI/              Argument parsing and subcommands for the `gimdiff` tool
```

Dependencies point inward: `UI` and `App` depend on `Engine`; `Infrastructure` implements
protocols that `Engine` declares; `Engine` depends on nothing but Foundation.

### Engine purity

`Engine/` must contain **zero** SwiftUI or AppKit imports. It holds the domain logic and
must stay testable without a running app. Verify with:

```sh
grep -rn '^import \(SwiftUI\|AppKit\|Cocoa\)' GimDiff/Engine
```

That command must print nothing.

When the engine needs a platform capability, declare a protocol in `Engine/` and implement
it in `Infrastructure/`. `CommandRunning` and `SystemCommandRunner` are the worked example:
`GitRepository` talks to the protocol, so tests substitute a double instead of spawning git.

### Single-window mandate

GimDiff is a single-instance utility.

- The scene is `Window("GimDiff", id: "main-window")` — never `WindowGroup`.
- `File ▸ New` is removed via `CommandGroup(replacing: .newItem) {}`.
- `AppDelegate` handles `applicationShouldHandleReopen(_:hasVisibleWindows:)`,
  `application(_:open:)`, and `application(_:openFiles:)` by raising the existing window
  rather than opening another.

`GimDiffUITests` asserts this: launching and reopening must leave exactly one window.

### Sidebar: the flattened visible tree

The sidebar is a flat `List` over `AppState.visibleRows`, never an `OutlineGroup`. Suites
and their snapshots are interleaved into one array of `TreeRowItem`, so the whole tree is
one level as far as `List` is concerned.

That is deliberate. `OutlineGroup` owns the hierarchy, and owning it costs two things
GimDiff needs: the arrow keys stop crossing levels once a row is a disclosure group, and
deleting a node rebuilds the group's identity so the selection is dropped rather than moved
to the neighbouring row. Flattening puts selection, arrow keys, and deletion in `AppState`
where all three can agree.

Consequences worth knowing before changing any of it:

- A suite's snapshots follow it in the array when the suite is expanded **or** when a search
  query is active. `TreeRowItem.suite` carries that effective state, while
  `expandedSuiteIDs` holds only what the user opened.
- Row identifiers are namespaced (`suite:<id>`, `snapshot:<suiteID>:<id>`) so the same image
  discovered under two suites stays two selectable rows.
- Deletion recomputes the replacement selection from the rows *as they still stand*, before
  pruning. Reverse the order and the neighbour is no longer identifiable, which is what
  leaves the tree with no selection and the keyboard with nothing to move.
- A deletion prunes `currentProject.suites` in memory. The scan that found the snapshot
  walked the whole project; nothing about removing one file needs that repeated.

### Keyboard routing: ⌘ keys are menu items, bare keys are not

This split is not a style choice, and getting it wrong fails silently.

AppKit offers a ⌘-modified key to `performKeyEquivalent(with:)` — the menu bar — and never
to the focused view's `keyDown(with:)`, which is what SwiftUI's `onKeyPress` observes. So:

- **⌘ shortcuts go in `AppCommands`.** `⌘↩` and `⌘⌫` live in the *Snapshot* menu. Putting
  them in the sidebar's `onKeyPress` compiles, matches nothing, and does nothing.
- **Bare keys go in `SnapshotTreeView.handle(_:)`.** `→`, `←`, Space, `↩`, and `/` are read
  there, where nothing sees them unless the rows have focus. A menu item bound to a bare
  Space or `↩` would fire while the user was typing in the search field.

Two more traps in the same area:

- `⌘V` is a single command that offers the key to the focused text field first
  (`WorkspaceService.forwardPasteToFocusedField()`) and ingests the clipboard only when
  nothing takes it. A second menu item bound to `⌘V` would shadow the search field's paste,
  because the menu bar is consulted before the first responder.
- `⎋` in the search field is read with `onKeyPress(.escape)`, not `onExitCommand`. A focused
  `TextField` turns `⎋` into its own `cancelOperation(_:)` and never forwards it.

### Sidebar focus

`SnapshotTreeView` claims focus when the window becomes key, from `onAppear` and from
`onChange(of: controlActiveState)`, and defers the assignment by one turn of the main actor.

All three parts are load-bearing. A `@FocusState` assignment made before the window is key
is discarded, and assigning inside the update that *made* it key is still too early — the
focus system has not engaged. Either mistake ships an app that launches with a selected row
the arrow keys cannot move until the tree is clicked once. `defaultFocus` does not work here
either. `GimDiffUITests/KeyboardNavigationUITests` is the regression guard: it drives the
tree with nothing but keys, so a focus regression fails there rather than reaching a user.

A non-flag launch argument is read by AppKit as a file to open, and one that names no file
suppresses the window entirely. The UI tests therefore reset state with a defaults override
(`-GimDiffResetState YES`), not a bare word.

### The canvas: roles, not sides

The detail column talks in ``SnapshotPane`` values, not in left and right. A pane carries a
**role** (`candidate` or `baseline`) and an **origin** (`workingTree` or `committedVersion`),
and `SnapshotPreview.panes` always puts the baseline first and the candidate second, reading
old to new like every other diff tool. Every action in a pane header — and `⌘←` / `⌘→` in the
*Snapshot* menu — reads as an arrow pointing at the file it overwrites: Accept points left at
the baseline, Revert points right at the candidate. That only works if the sides keep their
order.

The origin is load-bearing. A comparison against `HEAD` holds a baseline `git show` wrote to
a scratch file, so *accepting the candidate has nothing to write to*: the candidate already
is the file on disk. `promoteCandidateToBaseline()` refuses that case and says why, through
`candidatePromotionObstacle`. `revertCandidateToBaseline()` works either way, because the
side it writes to is always the working file.

Both write through a scratch file rather than straight over the destination.
`FilesystemService.replaceFile(at:with:)` *consumes* what it is handed — that is what makes
the exchange atomic — so handing it the candidate directly would delete the image the canvas
is still pointing at.

Two more rules that are easy to undo by accident:

- **`diffMode` is the only thing that decides what is drawn.** The toolbar's segmented
  picker and the View menu's Comparison picker are both bindings over it, not flags of their
  own, which is what makes the modes mutually exclusive without any code saying so.
- **Images are read by `SnapshotImageLoader`, never by `AsyncImage`.** `AsyncImage` caches on
  the URL, and GimDiff's whole job is a file whose name stays put while its contents change.
  `AppState.imageReloadToken` is the counter that says the bytes moved; every view that
  decodes an image keys its `task(id:)` on it.

`⌘R` refreshes the images on screen and `⇧⌘R` rescans the project, rather than the other way
round: a snapshot is looked at far more often than a folder is walked again.

### Background refresh

Nobody has to press ⌘R after a test run. `AppState+Watching` keeps the open project in step
with the disk, whether or not the window is key:

- **One FSEvents stream, not a descriptor per folder.** `FSEventsProjectWatcher` implements
  `ProjectWatching`, which `Engine/` declares. The kernel does the watching, so an idle
  project costs nothing. The stream carries `kFSEventStreamCreateFlagIgnoreSelf`: GimDiff's
  own promotions and deletions already refresh as part of being performed.
- **`ProjectChangeClassifier` decides what a batch means**, off the main actor, and drops
  most of it on the path alone — anything under a folder `ProviderIgnoreFilter` prunes, the
  Git object store, a test source being saved. What is left asks for one of three things,
  cheapest first: the badges (`HEAD` moved), the images on screen (a snapshot already in the
  tree was rewritten), or a rescan (a snapshot, a suite, or a test source came or went).
- **`.git/index` is not watched, on purpose.** `git status` refreshes the index as a side
  effect, so answering an index change with a status read would never stop. Only `HEAD`,
  `packed-refs`, and `refs/heads/` count.
- **A background rescan goes through `merge(_:)`, never `load(_:)`.** `load` is for a project
  somebody asked for and resets the selection, the open suites, and the canvas. `merge`
  keeps all three, and moves the selection only when its row is gone — to the neighbour a
  deletion would have picked.
- **One refresh at a time.** Changes that arrive while a rescan is walking the project
  accumulate in `pendingChange` and become a single follow-up, so a test run that writes for
  a minute does not queue a minute of scans. A deletion made during a scan bumps
  `projectEdits`, which makes that scan's result be thrown away and taken again: it may have
  listed the file before it went, and GimDiff's own writes are not reported for a later
  batch to correct.

A pull request review is not watched. Tests that load a project hand `AppState` a
`StubProjectWatcher`, so no real stream delivers an event halfway through an assertion;
`AppState.projectFilesChanged(_:)` is the seam they drive instead.

### URL scheme

`gimdiff://` is registered in `GimDiff/Info.plist` (role `Viewer`, identifier
`com.davidgiordana.GimDiff`). Three actions are understood:

```
gimdiff://open?path=/path/to/snapshots
gimdiff://compare?reference=/path/a.png&failure=/path/b.png
gimdiff://open-pr?url=https://github.com/owner/repo/pull/123
```

`open` reads as either shape: given a candidate and no folder it is the comparison between
them, so `gimdiff://open?candidate=…&baseline=…` does not have to be spelled `compare`.

Each action and each parameter also answers to the synonyms listed at the top of
`GimDiffURLCommand` — `open-project`, `baseline`, `candidate` — so the vocabulary the CLI
and the ingestion service use does not have to be translated at the boundary.

Parsing lives in `Engine/Ingestion/GimDiffURLCommand.swift` and is fully unit tested; the
`App` layer only forwards the URL. Try it against a debug build with:

```sh
open 'gimdiff://open?path=/path/to/snapshots'
```

`GimDiff/Info.plist` is a partial plist merged with the generated one
(`GENERATE_INFOPLIST_FILE = YES`). It is excluded from Copy Bundle Resources through a
`PBXFileSystemSynchronizedBuildFileExceptionSet`; keep that exception if you add files
that should not ship as resources.

## Pull request review

GimDiff can review the snapshots a GitHub pull request changes without checking it out.
`Engine/GitHub/` reads the pull request through the REST API and downloads both versions
of every changed image under `Snapshots/` or `__Snapshots__/` into a scratch folder; the
review then stands in for the open project until it is closed.

- **Authentication is borrowed, never stored.** `GitHubTokenResolver` runs
  `/usr/bin/env PATH=… gh auth token --hostname github.com`. The `PATH` assignment matters:
  an app launched from the Finder inherits launchd's search path, which has no Homebrew in
  it. Only `github.com` is supported.
- **Files come from the contents API, with an LFS fallback.** Snapshot folders are often
  stored with Git LFS, and for those the contents API answers with the pointer file. A blob
  starting with the LFS pointer line is fetched again from `media.githubusercontent.com`.
- **Every route goes through the Open PR sheet** — ⌘⇧O, the toolbar, a pasted link (⌘V),
  `gimdiff://open-pr`, and `gimdiff pr`. The sheet stays up while the fetch runs, so
  progress and failures (`gh` missing, not logged in, no access) are shown beside the field.
- **The review is read-only.** Both panes carry the `pullRequest` origin, so the promotion
  actions refuse them and the pane headers hide their arrows; deletion is refused too.
  Actions that open a file elsewhere — Preview, the Finder, the test source — are hidden:
  the files are scratch copies that disappear with the review.
- **Every snapshot names its change.** `ChangeKindBadge` shows Added, Modified, Deleted, or
  Renamed on each sidebar row and on the canvas. An added or deleted snapshot has one
  version only, shown as `SnapshotPreview.pullRequestSide` under the side it belongs to —
  never as `.single`, which always means the candidate on disk.
- **The scratch folder is deleted, not trashed**, through `FilesystemService.removeItem(at:)`,
  when the review closes, when a project replaces it, and when the app terminates. Closing
  a review puts back the project it replaced.

## Test run failures

The sidebar has two views of an open project, switched by the *Project / Test Run*
control under the project header (and View ▸ Sidebar Shows). `AppState.sidebarSource` holds
which one is up; switch through `showTestRun()` and `showProjectStatus()`, never by assigning.

- **Every run is offered; the newest is the default.** `testRunBundles` lists every bundle
  of the project, newest first, and the menu under the switch (and View ▸ Test Runs) picks
  one through `showTestRun(from:)`. Picking an older run sets `pinnedTestRunBundleURL`, and
  a pinned run stays on screen when a newer one arrives; picking the newest clears the pin,
  so the view follows new runs again. A pinned run that is deleted gives way to the newest.
- **The switch appears only when there is a run.** `load(_:)` looks for the project's
  bundles with `locateTestRun()` — a property list per workspace and per run, no `xcresulttool` —
  and `showsSidebarSourcePicker` stays false until one is found. It stays up while the
  run's view is showing, so a run deleted from under it still has a way back. A project
  never tested has no `Logs/Test` folder to watch, so its first run appears on the next
  load rather than live.
- **The project view is the default, and reads nothing.** `load(_:)` always lands on it and
  forgets any run read for the last project. The run is read the first time somebody
  switches to it — exporting attachments through `xcresulttool` is not free, and most
  visits to a project are not about its last run.
- **The run's view lists only what failed**, plus a synthetic suite of images that matched
  nothing. Its suites open on arrival and its first failure is selected. The Modified and
  Warnings chips belong to the project view and are cleared on every switch.
- **The run stays read across switches.** A new bundle arriving while the run's view is up
  is read once the folder settles; one arriving while the project view is up only discards
  the old results, so the next switch reads the new run.

Nothing about reading a run assumes a snapshot library: every decision is made from Xcode's
own structure or from bytes.

- **Finding the run.** `DerivedDataLocator` matches each DerivedData folder's `info.plist`
  (`WorkspacePath`) against the project root and its working tree, and takes the newest
  `Logs/Test/*.xcresult` by the `dateCreated` the bundle records. It honours Xcode's
  `IDECustomDerivedDataLocation` when that is absolute.
- **Reading it.** `XcresultReader` goes through `xcrun xcresulttool` only — the bundle
  format is private. Failed test cases come from `get test-results tests`; images are
  grouped by the activity that attached them (innermost wins, since Xcode repeats an
  attachment on every enclosing step); each failed test's attachments are exported into a
  scratch folder and kept only if their leading bytes are PNG, JPEG, or WebP. Names are
  displayed, never parsed.
- **Matching it.** `TestRunMatcher` makes an attached image the baseline of a snapshot when
  their bytes are identical. The candidate is the first image the step attached after
  that — the one decision left to attachment order, since an assertion attaches what it
  rendered before any picture of the difference, and the canvas draws its own difference
  in the diff mask. A step matching nothing lists all its images. The test identifier is
  consulted only to break a tie between identical snapshots.
- **Staleness is by date.** A step whose matched snapshot was written after the run began
  is dropped. Accepting a candidate makes the *rendered* image equal the snapshot; without
  this rule, reading the same bundle again would offer the old reference as the candidate.
- **The canvas.** A failing snapshot opens as `SnapshotPreview.testRunFailure`: the
  candidate carries the `testRun` origin (never written to, so Revert is refused) and the
  baseline is the working file (so Accept works and settles the failure in memory). Images
  that match nothing are listed under a synthetic suite, `AppState.testRunSuiteID`, which
  cannot be deleted and carries no source warning.
- **Refreshing.** The watcher also watches each workspace's `Logs/Test`; see above for what
  an event there does in each view. A re-read waits for the folder to be quiet for a
  second, because a bundle is written for as long as the run lasts. The scratch folder is
  deleted when the results are replaced, the project closes, or the app quits.

Tests that load a project should hand `AppState` a `StubTestResults`, as `AppStateFixture`
does, so the developer's own DerivedData never decides what an assertion sees.

## Command-line tool

`gimdiff` is a `com.apple.product-type.tool` target. `GimCLI/` holds only argument parsing
and the subcommands; everything they do is `Engine/` and `Infrastructure/` code, compiled
into the tool from the same folders the app compiles them from.

```
gimdiff scan <project-path> [--json]
gimdiff diff <candidate> <baseline> [--out <mask.png>] [--json]
gimdiff parse-clipboard [--input "<log text>"] [--json]
gimdiff pr <url-or-number>             # hands a GitHub pull request to the running app
gimdiff <project-path>                 # hands the path to the running app
gimdiff <candidate> <baseline>         # hands one comparison to the running app
```

Exit codes are part of the contract, because a build script needs to tell a difference from
a failure: `0` nothing to report, `1` the images or the project differ, `2` the command
could not run, `64` the arguments were not usable.

The launcher never spawns the app. It builds a `gimdiff://` URL and passes it to
`NSWorkspace` with `configuration.activates = true`, so LaunchServices routes it to the copy
already running and `AppDelegate` retargets the one window. That is what keeps the
single-window mandate intact from a terminal.

## Git safety

Never build a command as a shell string, and never invoke `/bin/zsh -c` or `/bin/sh -c`.
Use `Process` with a discrete argument array so paths containing spaces, quotes, or `$`
cannot be reinterpreted.

```swift
// Correct — arguments arrive at git verbatim.
Command(
    executableURL: URL(fileURLWithPath: "/usr/bin/git"),
    arguments: ["checkout", "--", "/Snapshots/home screen.png"],
    workingDirectory: repository
)
```

Build invocations through `Engine/Git/GitCommand.swift` rather than assembling arguments at
the call site, and keep `--` before any user-supplied path so a file named `--force` is not
read as a flag.

## Tests

Every engine feature and every provider needs unit tests in `GimDiffTests`, written before
or alongside the implementation. `GimDiffTests` mirrors the app's layer layout
(`GimDiffTests/Engine`, `GimDiffTests/Infrastructure`, `GimDiffTests/App`).

`AppState` is tested like any other type. `AppStateFixture` hands it a bundle directly
through `AppState.load(_:)` so the tree, the arrow keys, and deletion are tested without a
disk scan; `ProjectOpeningTests` covers the scanning path against a real `ProjectFixture`
and awaits `AppState.currentScan`.

- Unit tests use **Swift Testing** (`@Suite`, `@Test`, `#expect`, `#require`).
- Image fixtures are checked in under `GimDiffTests/Fixtures/Images/` and reached through
  `ImageFixtures`, which locates them with `#filePath` rather than through `Bundle`. Project
  *trees*, by contrast, are still built at run time by `ProjectFixture` — see the note there
  for why they cannot be committed.
- UI tests use **XCTest**, because XCUIApplication has no Swift Testing equivalent.
- Avoid the `#URL` macro: it needs macOS 15, and the deployment target is 14.0. Use
  `try #require(URL(string:))`.
- Do not assert against the menu bar from UI tests; menu interaction is unreliable in the
  test runner. Typing a menu item's *shortcut* with `typeKey(_:modifiers:)` is fine, and is
  how `KeyboardNavigationUITests` exercises `⌘⌫`, `⌘↩`, `⌘F`, and `⌘1`/`⌘0`.
- A UI test that depends on an empty state must launch with `-GimDiffResetState YES`, or a
  project opened by hand on the developer's own machine decides what the assertion sees.

## Project file

The project uses Xcode 16+ synchronized folders (`PBXFileSystemSynchronizedRootGroup`), so
adding a Swift file to `GimDiff/`, `GimDiffTests/`, or `GimCLI/` on disk is enough — the
project file needs no edit and no new file reference.

One exception, and it is the one that bites: the `GimDiff/` folder is synchronized into
**two** targets, the app and `gimdiff`. The tool has no SwiftUI in it, so every app-only
file is listed by path in the `PBXFileSystemSynchronizedBuildFileExceptionSet` named
*Exceptions for "GimDiff" folder in "gimdiff" target*. Xcode does not accept a directory
there, only files. **Adding a file under `GimDiff/App/` or `GimDiff/UI/`, or any other file
that imports SwiftUI or AppKit, means adding its path to that list** — otherwise the next
`xcodebuild -scheme gimdiff` build fails on it.

## Code style

- No trailing whitespace, and no empty line containing indentation. Verify with:

  ```sh
  grep -rn '[[:space:]]\+$' --include='*.swift' GimDiff GimCLI GimDiffTests GimDiffUITests
  ```

  That command must print nothing.
- Comments explain *why*, not *what*. Skip a comment that restates the line below it.
- Document non-obvious behaviour with `///` on the declaration.

## Authorship

- File headers, when present, read:

  ```swift
  //
  //  Created by David Giordana.
  //  Copyright © 2026 David Giordana. All rights reserved.
  //
  ```

- Never attribute authorship to a tool, an assistant, or a model — not in source, not in
  documentation, not in commit messages.
- Commit messages are plain and imperative (`Initialize GimDiff architecture and layer
  structure`). No trailers, no badges, no co-author lines.
