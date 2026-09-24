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

    private func raiseMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
