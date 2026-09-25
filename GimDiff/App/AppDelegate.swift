//
//  AppDelegate.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit

/// Owns the shared application state and keeps GimDiff to a single window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Defaults key the UI tests set, so recent projects left by an earlier run cannot leak
    /// into an assertion about the empty state.
    ///
    /// Passed as `-GimDiffResetState YES` rather than as a bare word: AppKit reads any
    /// non-flag launch argument as a file to open, and a bare argument that resolves to no
    /// file suppresses the window entirely — which is exactly what the UI tests then fail on.
    static let resetStateKey = "GimDiffResetState"

    let state: AppState
    /// Presents the main window when none exists; supplied by the scene's commands.
    var openMainWindow: (() -> Void)?

    override init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.resetStateKey) {
            defaults.removeObject(forKey: AppState.recentProjectsKey)
        }
        state = AppState(defaults: defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    /// Nothing outlives the window, so closing it quits rather than leaving a menu bar behind.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Files handed over by the Finder, or by `open -a GimDiff <path>` from a terminal.
    ///
    /// The paths are routed into the existing window and the window is raised; LaunchServices
    /// delivers them to the running copy, so no second instance is ever involved.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        state.openPaths(filenames.map { URL(fileURLWithPath: $0) })
        raiseMainWindow()
        sender.reply(toOpenOrPrint: .success)
    }

    /// Handles `gimdiff://` URLs, raising the existing window rather than opening a new one.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            state.handle(url)
        }
        raiseMainWindow()
    }

    /// Clicking the Dock icon brings the window back, whether it is hidden or only buried.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.unhide(nil)
        }
        raiseMainWindow()
        return true
    }

    /// Brings the one window forward, creating it if the launch did not.
    ///
    /// A cold launch that opens a folder delivers the paths before any window exists, and
    /// SwiftUI then presents none of its own, so there may be nothing to raise yet. The
    /// paths arrive before launching has finished; the check waits one turn of the main
    /// actor so the window is asked for once it has.
    private func raiseMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        Task { @MainActor in
            guard !NSApp.windows.contains(where: { $0.canBecomeMain }) else { return }
            openMainWindow?()
        }
    }
}
