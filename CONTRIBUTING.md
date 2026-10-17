# Contributing to GimDiff

Thanks for helping. This page covers the practical side; [DEVELOPMENT.md](DEVELOPMENT.md) is the
full development guide, covering the architecture, the decisions behind it, and the rules a
change has to keep.

## Getting set up

You need Xcode 26 on macOS 14 or later. Open `GimDiff.xcodeproj`; there are no package
dependencies to resolve.

### Code signing

The project signs to run locally by default, which needs no Apple Developer account. To
sign with your own team:

```sh
cp Config/Local.xcconfig.template Config/Local.xcconfig
```

Then put your team ID in `Config/Local.xcconfig`. The file is git-ignored, so the
team ID never lands in a commit. Don't set a team in the project's Signing & Capabilities
tab: Xcode would write it into `project.pbxproj`.

## Before you open a pull request

All of these must pass with no errors and no new warnings:

```sh
xcodebuild -scheme GimDiff -destination 'platform=macOS' build
xcodebuild -scheme GimDiff -destination 'platform=macOS' test
xcodebuild -scheme gimdiff -destination 'platform=macOS' build
```

And these two must print nothing:

```sh
# Engine/ stays free of UI frameworks
grep -rn '^import \(SwiftUI\|AppKit\|Cocoa\)' GimDiff/Engine
# No trailing whitespace
grep -rn '[[:space:]]\+$' --include='*.swift' GimDiff GimCLI GimDiffTests GimDiffUITests
```

CI runs the build, the unit tests, and both checks on every pull request. The UI tests
need a logged-in desktop session, so run them locally when you touch the sidebar,
keyboard handling, or windowing.

## Guidelines

- **Tests come with the change.** Every engine feature and provider needs unit tests in
  `GimDiffTests`, written with Swift Testing.
- **A new app-only file** (anything under `GimDiff/App/` or `GimDiff/UI/`, or that
  imports SwiftUI or AppKit) must be added to the `gimdiff` target's exception list in
  the project file. See *Project file* in DEVELOPMENT.md.
- **User-facing text goes through `Localizable.xcstrings`.** See *Localization* in DEVELOPMENT.md.
- **Git commands are argument arrays**, never shell strings. See *Git safety* in DEVELOPMENT.md.
- **Commit messages** are plain and imperative: `Add Paparazzi failure reader`, not
  `Added stuff`.
- Keep a pull request to one change. Open an issue first if you're planning something large.

## Reporting a bug

Open an issue with the macOS version, the GimDiff version, the snapshot library
your project uses, and the steps that show the problem. A small project that reproduces
it helps most.
