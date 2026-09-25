//
//  HelpView.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

/// The help sheet: a list of topics beside the one being read.
///
/// A sheet rather than a window of its own, because GimDiff shows exactly one window and
/// help is read for a moment and put away, not kept open beside the canvas.
struct HelpView: View {
    @Environment(AppState.self) private var state

    @State private var topic: HelpTopic = .gettingStarted

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(HelpTopic.allCases, selection: selection) { topic in
                    Label(topic.title, systemImage: topic.symbolName)
                        .tag(topic)
                }
                .listStyle(.sidebar)
                .frame(width: 210)

                Divider()

                ScrollView {
                    HelpTopicPage(topic: topic)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // A fresh scroll position per topic, rather than landing halfway down the
                // next page because the last one was read to the bottom.
                .id(topic)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done", action: state.dismissHelp)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 780, height: 560)
        // ⎋ as well as ↩: nothing in the sheet is lost by closing it.
        .onExitCommand(perform: state.dismissHelp)
    }

    /// The list's selection, which `List` wants optional but the page never is.
    private var selection: Binding<HelpTopic?> {
        Binding(
            get: { topic },
            set: { if let newValue = $0 { topic = newValue } }
        )
    }
}

/// One topic, laid out top to bottom.
private struct HelpTopicPage: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(topic.title, systemImage: topic.symbolName)
                .font(.title2.weight(.semibold))

            ForEach(topic.sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.headline)

                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                        HelpBlockView(block: block)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case let .text(markdown):
            Text(LocalizedStringKey(markdown))
                .fixedSize(horizontal: false, vertical: true)

        case let .shortcuts(shortcuts):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(shortcuts) { shortcut in
                    GridRow {
                        KeyCap(keys: shortcut.keys)
                            .gridColumnAlignment(.trailing)
                        Text(shortcut.action)
                    }
                }
            }

        case let .code(code):
            Text(code)
                .font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        }
    }
}

/// A shortcut drawn the way the menu bar draws it, on a key-shaped chip.
private struct KeyCap: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.callout.monospaced())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
    }
}

#Preview {
    HelpView()
        .environment(AppState())
}
