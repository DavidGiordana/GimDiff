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

    /// Text currently on the pasteboard, typically a copied test failure log.
    func string() -> String? {
        pasteboard.string(forType: .string)
    }

    /// File URLs on the pasteboard, as copying in the Finder leaves behind.
    func fileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    func copy(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Puts a PNG on the pasteboard, for pasting into a chat, an issue, or an image editor.
    func copy(pngData: Data) {
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    /// Puts a file on the pasteboard so it can be pasted into Finder or another app.
    func copy(fileAt url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}
