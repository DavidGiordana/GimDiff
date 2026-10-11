//
//  AppState+Undo.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A file's bytes as they stood before GimDiff wrote over them, kept so Undo can put them
/// back.
struct SavedFile: Sendable {
    let file: URL
    /// A scratch copy of what the file held, or `nil` when there was no file to copy.
    let copy: URL?
}

/// Undo for every action that writes a snapshot: Accept, Reject, the Keep choices, Accept
/// All, Discard, and Move to Trash.
///
/// Git can bring back a committed baseline, but not a loose pair's file, a change that was
/// never committed, or whatever Discard threw away. So every write first copies what it is
/// about to overwrite into the scratch folder, and Undo copies it back. Undoing saves the
/// file again first, which is what Redo restores, so the two are the same operation.
extension AppState {
    /// Copies each of `files` aside before an action overwrites it.
    ///
    /// Empty without an undo manager: nothing could ever ask for the copies. A file that
    /// cannot be copied is left out, so the rest of the action can still be undone.
    func saveForUndo(_ files: [URL]) -> [SavedFile] {
        guard undoManager != nil else { return [] }
        return files.compactMap { file in
            guard filesystem.fileExists(at: file) else { return SavedFile(file: file, copy: nil) }
            let copy = filesystem.createTemporaryFile(
                prefix: "undo-" + file.deletingPathExtension().lastPathComponent,
                extension: file.pathExtension.isEmpty ? "tmp" : file.pathExtension
            )
            do {
                try filesystem.copyFile(from: file, to: copy)
                return SavedFile(file: file, copy: copy)
            } catch {
                return nil
            }
        }
    }

    /// Registers an undo that puts `saved` back, named for the menu as `actionName`.
    func registerUndo(restoring saved: [SavedFile], actionName: String) {
        guard let undoManager, !saved.isEmpty else {
            discardSaved(saved)
            return
        }
        register(on: undoManager, actionName: actionName) { state in
            state.restore(saved, actionName: actionName)
        }
    }

    /// Throws away copies an action that did not happen saved.
    func discardSaved(_ saved: [SavedFile]) {
        for copy in saved.compactMap(\.copy) {
            try? filesystem.removeItem(at: copy)
        }
    }

    /// Registers an undo that brings an item back out of the Trash.
    func registerUndoOfTrash(original: URL, trashed: URL, actionName: String) {
        guard let undoManager else { return }
        register(on: undoManager, actionName: actionName) { state in
            state.untrash(trashed, to: original, actionName: actionName)
        }
    }

    /// Drops every file action from the undo stack, leaving the filter field's typing.
    ///
    /// Called when the project changes: undoing then would rewrite files of a project
    /// nobody is looking at, with nothing on screen to say so.
    func forgetFileUndo() {
        undoManager?.removeAllActions(withTarget: self)
    }

    // MARK: - Performing

    private func restore(_ saved: [SavedFile], actionName: String) {
        let current = saveForUndo(saved.map(\.file))

        for entry in saved {
            if let copy = entry.copy {
                _ = self.copy(contentsOf: copy, over: entry.file)
            } else {
                // The action created the file. Trashed rather than deleted, because a file
                // GimDiff wrote is still the user's.
                do {
                    try filesystem.trashFile(at: entry.file)
                } catch {
                    report(error)
                }
            }
        }
        discardSaved(saved)
        registerUndo(restoring: current, actionName: actionName)

        // An accept settled a failure in memory, and only reading the run again brings it
        // back; a discard cleared badges that the status read now puts right.
        rereadTestRunAfterDiscarding()
        refreshPreviewImages()
    }

    private func untrash(_ trashed: URL, to original: URL, actionName: String) {
        do {
            try filesystem.moveItem(at: trashed, to: original)
        } catch {
            report(error)
            return
        }
        // Redo trashes it again, through the same path a deletion takes.
        if let undoManager {
            register(on: undoManager, actionName: actionName) { state in
                state.retrash(original, actionName: actionName)
            }
        }
        rescanAfterOwnEdit()
    }

    private func retrash(_ url: URL, actionName: String) {
        do {
            if let trashed = try filesystem.trashFile(at: url) {
                registerUndoOfTrash(original: url, trashed: trashed, actionName: actionName)
            }
        } catch {
            report(error)
            return
        }
        rescanAfterOwnEdit()
    }

    /// Registers `handler` as one step of the stack.
    ///
    /// Grouped explicitly only when nothing has opened a group already: the window opens one
    /// per event, and an undo or redo opens one for whatever it registers in turn.
    private func register(
        on undoManager: UndoManager,
        actionName: String,
        handler: @escaping @MainActor (AppState) -> Void
    ) {
        let needsGroup = undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { state in
            MainActor.assumeIsolated { handler(state) }
        }
        undoManager.setActionName(actionName)
        if needsGroup { undoManager.endUndoGrouping() }
    }
}
