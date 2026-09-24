//
//  ClipboardService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit

/// Writes snapshot paths and images to the system pasteboard.
@MainActor
struct ClipboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Puts a file on the pasteboard so it can be pasted into Finder or another app.
    func copy(fileAt url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}
