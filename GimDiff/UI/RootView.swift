//
//  RootView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The contents of the single GimDiff window.
struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            SnapshotCanvasView(pair: state.selectedPair)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Diff Mode", selection: $state.diffMode) {
                            ForEach(DiffMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.symbolName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelStyle(.iconOnly)
                        .disabled(state.selectedPair == nil)
                    }
                }
        }
        .overlay(alignment: .top) {
            if let message = state.lastError {
                ErrorBanner(message: message, dismiss: state.dismissError)
            }
        }
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

#Preview {
    RootView()
        .environment(AppState())
}
