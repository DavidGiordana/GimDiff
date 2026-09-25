//
//  RootView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

/// The contents of the single GimDiff window.
struct RootView: View {
    @Environment(AppState.self) private var state

    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
        } detail: {
            DetailView()
        }
        // The whole window is the drop target, not just the sidebar: a folder dragged onto
        // the canvas means the same thing as one dragged onto the tree.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            open(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                DropZoneOverlay()
            }
        }
        .overlay(alignment: .top) {
            if let message = state.lastError {
                ErrorBanner(message: message, dismiss: state.dismissError)
            }
        }
        .sheet(isPresented: pullRequestSheet) {
            OpenPRSheetView()
        }
    }

    /// The Open PR sheet's visibility, routed so a dismissal by the system also abandons
    /// the fetch the sheet was showing.
    private var pullRequestSheet: Binding<Bool> {
        Binding(
            get: { state.isPullRequestSheetPresented },
            set: { isPresented in
                if !isPresented { state.dismissPullRequestSheet() }
            }
        )
    }

    /// Bridges the sidebar's own visibility to the ⌘1 and ⌘0 commands.
    ///
    /// Pinned to `.all` rather than left to SwiftUI. Given only a detail column that asks
    /// for room, `NavigationSplitView` opens with the sidebar collapsed — and the sidebar is
    /// GimDiff's only navigation, so the app would launch with no way to reach a snapshot
    /// but the toolbar's reveal button.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { state.isSidebarVisible ? .all : .detailOnly },
            set: { state.isSidebarVisible = $0 != .detailOnly }
        )
    }

    /// Reads the dropped paths and hands them to the state as one batch.
    ///
    /// The providers answer on an arbitrary queue, so they are all awaited first and the
    /// state is touched once: a folder and two loose images have to be told apart by looking
    /// at the whole drop, not at whichever file happened to answer first.
    private func open(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                guard let url = await provider.fileURL() else { continue }
                urls.append(url)
            }
            state.openPaths(urls)
        }
    }
}

/// Translucent cover shown while a drag is over the window.
private struct DropZoneOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.3)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 52, weight: .medium))
                Text("Drop to process!")
                    .font(.title2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .shadow(radius: 6, y: 2)
        }
        .ignoresSafeArea()
        // The overlay is a hint, not a control: the drop is handled by the window beneath it,
        // and swallowing the mouse here would cancel the drag it is describing.
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityLabel("Drop to process")
    }
}

/// Transient banner describing the most recent failure.
private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Button("Dismiss", action: dismiss)
                .buttonStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .shadow(radius: 8, y: 2)
        .padding()
    }
}

private extension NSItemProvider {
    /// The file URL this provider carries, awaited rather than delivered on a callback queue.
    func fileURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
