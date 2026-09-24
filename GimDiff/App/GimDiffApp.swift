//
//  GimDiffApp.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

@main
struct GimDiffApp: App {
    /// Identifier of the single window GimDiff ever shows.
    static let mainWindowID = "main-window"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `Window` rather than `WindowGroup`: GimDiff is a single-instance utility, so a
        // second open event must raise the existing window instead of creating another.
        Window("GimDiff", id: Self.mainWindowID) {
            RootView()
                .environment(appDelegate.state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
