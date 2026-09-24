//
//  WorkspaceService.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit

/// Hands files to the apps and panels that know what to do with them.
///
/// Everything the sidebar's context menus and keyboard shortcuts do *outside* GimDiff goes
/// through here, so the views never reach for `NSWorkspace` themselves and a test can
/// substitute a double for the whole boundary.
@MainActor
struct WorkspaceService {
    /// Where Preview.app lives on a stock system.
    static let previewApplicationURL = URL(fileURLWithPath: "/System/Applications/Preview.app")

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    /// Opens `url` in whichever app the system has registered for it — Xcode, for `.swift`.
    func open(_ url: URL) {
        workspace.open(url)
    }

    /// Opens a Finder window with `url` selected, rather than opening the file itself.
    func revealInFinder(_ url: URL) {
        workspace.activateFileViewerSelecting([url])
    }

    /// Opens an image in Preview.app specifically, whatever the user's default viewer is.
    ///
    /// GimDiff registers itself for image types, so opening with the default app would
    /// hand the file straight back to GimDiff.
    func openInPreview(_ url: URL) {
        workspace.open(
            [url],
            withApplicationAt: Self.previewApplicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// Asks the user for a project folder.
    ///
    /// - Returns: The chosen folder, or `nil` when the panel was cancelled.
    func chooseProjectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose a project folder to scan for snapshots."

        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Sends an Edit-menu action down the responder chain.
    ///
    /// - Returns: Whether a responder claimed it.
    @discardableResult
    func perform(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    /// Offers ⌘V to the focused text field.
    ///
    /// - Returns: Whether a text responder took it, in which case GimDiff must not also
    ///   read the pasteboard itself.
    func forwardPasteToFocusedField() -> Bool {
        perform(#selector(NSText.paste(_:)))
    }

    /// The Edit-menu actions GimDiff forwards verbatim, so replacing the pasteboard command
    /// group does not take cut, copy, and select-all away from the filter field.
    enum EditAction {
        case cut
        case copy
        case selectAll

        var selector: Selector {
            switch self {
            case .cut: #selector(NSText.cut(_:))
            case .copy: #selector(NSText.copy(_:))
            case .selectAll: #selector(NSText.selectAll(_:))
            }
        }
    }

    func perform(_ action: EditAction) {
        perform(action.selector)
    }
}
