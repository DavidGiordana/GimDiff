//
//  SidebarView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// Lists the snapshot comparisons currently loaded.
struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        List(state.pairs, selection: $state.selection) { pair in
            Label(pair.name, systemImage: "photo.on.rectangle.angled")
                .tag(pair.id)
        }
        .overlay {
            if state.pairs.isEmpty {
                ContentUnavailableView(
                    "No Snapshots",
                    systemImage: "tray",
                    description: Text("Open a snapshot folder to start comparing.")
                )
            }
        }
        .navigationTitle("Snapshots")
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
}
