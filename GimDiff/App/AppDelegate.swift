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
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    /// Clicking the Dock icon or opening the app again raises the existing window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        raiseMainWindow()
        return true
    }

    /// Handles `gimdiff://` URLs, raising the existing window rather than opening a new one.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            state.handle(url)
        }
        raiseMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func raiseMainWindow() {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
