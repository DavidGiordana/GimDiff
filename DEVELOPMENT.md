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
- `AppDelegate` handles `applicationShouldHandleReopen(_:hasVisibleWindows:)` and
  `application(_:open:)` by raising the existing window rather than opening another.

`GimDiffUITests` asserts this: launching and reopening must leave exactly one window.

### URL scheme

`gimdiff://` is registered in `GimDiff/Info.plist` (role `Viewer`, identifier
`com.davidgiordana.GimDiff`). Two actions are understood:

```
gimdiff://open?path=/path/to/snapshots
gimdiff://compare?reference=/path/a.png&failure=/path/b.png
```

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

## Command-line tool

`gimdiff` is a `com.apple.product-type.tool` target. `GimCLI/` holds only argument parsing
and the subcommands; everything they do is `Engine/` and `Infrastructure/` code, compiled
into the tool from the same folders the app compiles them from.

```
gimdiff scan <project-path> [--json]
gimdiff diff <candidate> <baseline> [--out <mask.png>] [--json]
gimdiff parse-clipboard [--input "<log text>"] [--json]
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
(`GimDiffTests/Engine`, `GimDiffTests/Infrastructure`).

- Unit tests use **Swift Testing** (`@Suite`, `@Test`, `#expect`, `#require`).
- Image fixtures are checked in under `GimDiffTests/Fixtures/Images/` and reached through
  `ImageFixtures`, which locates them with `#filePath` rather than through `Bundle`. Project
  *trees*, by contrast, are still built at run time by `ProjectFixture` — see the note there
  for why they cannot be committed.
- UI tests use **XCTest**, because XCUIApplication has no Swift Testing equivalent.
- Avoid the `#URL` macro: it needs macOS 15, and the deployment target is 14.0. Use
  `try #require(URL(string:))`.
- Do not assert against the menu bar from UI tests; menu interaction is unreliable in the
  test runner.

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
