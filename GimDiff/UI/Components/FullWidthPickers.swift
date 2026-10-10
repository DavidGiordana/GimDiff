//
//  FullWidthPickers.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import SwiftUI

/// One choice of a full-width picker: what it says and what it selects.
struct PickerOption<Value: Hashable>: Hashable {
    let title: String
    let value: Value
}

/// A segmented control that spans the width it is offered.
///
/// SwiftUI's segmented `Picker` keeps its natural width on macOS: a wider frame only centres
/// it. `NSSegmentedControl` fills a wider frame once its segments are told to share it.
struct FullWidthSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let options: [PickerOption<Value>]
    @Binding var selection: Value
    var help: String?
    var accessibilityIdentifier: String?

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.select = { index in
            guard options.indices.contains(index) else { return }
            selection = options[index].value
        }
        if control.segmentCount != options.count { control.segmentCount = options.count }
        for (index, option) in options.enumerated() where control.label(forSegment: index) != option.title {
            control.setLabel(option.title, forSegment: index)
        }
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
        control.toolTip = help
        control.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        return CGSize(width: max(proposal.width ?? natural.width, natural.width), height: natural.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var select: (Int) -> Void = { _ in }

        @objc
        func segmentChanged(_ sender: NSSegmentedControl) {
            select(sender.selectedSegment)
        }
    }
}

/// A pop-up button that spans the width it is offered, its title on the leading edge.
///
/// SwiftUI's menu `Picker` keeps its natural width on macOS and centres itself in a wider
/// frame. Items are added one by one rather than through `addItems(withTitles:)`, which
/// drops a title it has already seen — and two runs can carry the same one.
struct FullWidthPopUpPicker<Value: Hashable>: NSViewRepresentable {
    let options: [PickerOption<Value>]
    @Binding var selection: Value?
    var help: String?
    var accessibilityLabel: String?
    var accessibilityIdentifier: String?

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.target = context.coordinator
        button.action = #selector(Coordinator.itemChosen(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.select = { index in
            guard options.indices.contains(index) else { return }
            selection = options[index].value
        }
        // Rebuilt only when the choices change, so an update does not close a menu that is
        // open or reset the item under the pointer.
        if context.coordinator.shownOptions != options {
            context.coordinator.shownOptions = options
            button.removeAllItems()
            for option in options {
                button.menu?.addItem(NSMenuItem(title: option.title, action: nil, keyEquivalent: ""))
            }
        }
        if let index = options.firstIndex(where: { $0.value == selection }) {
            button.selectItem(at: index)
        }
        button.toolTip = help
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let natural = nsView.intrinsicContentSize
        // Narrower than its longest title is fine: the button truncates rather than spill.
        return CGSize(width: proposal.width ?? natural.width, height: natural.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var select: (Int) -> Void = { _ in }
        var shownOptions: [PickerOption<Value>] = []

        @objc
        func itemChosen(_ sender: NSPopUpButton) {
            select(sender.indexOfSelectedItem)
        }
    }
}
