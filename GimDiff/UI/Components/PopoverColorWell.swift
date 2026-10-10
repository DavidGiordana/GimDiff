//
//  PopoverColorWell.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import SwiftUI

/// A colour well that opens a compact popover instead of the detached system Color Panel.
///
/// SwiftUI's `ColorPicker` uses `NSColorWellStyleDefault`, which puts the full Color Panel on
/// screen as a separate window. That window outlives the click, floats over the snapshot the
/// user is trying to look at, and has to be closed by hand — all of which is wrong for a
/// control that only picks a backdrop. `NSColorWellStyleMinimal` shows the same picker as a
/// popover anchored to the well and dismisses it on the next click outside.
///
/// `nil` means no colour: the canvas falls back to its own background, and the well draws
/// the clear swatch.
struct PopoverColorWell: NSViewRepresentable {
    /// Size the minimal well is pinned to, so a row of them lines up in a toolbar.
    static let controlSize = CGSize(width: 30, height: 22)

    @Binding var color: Color?
    /// Spoken name of the control, since the well itself carries no label.
    var accessibilityLabel: String

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(
            frame: NSRect(origin: .zero, size: Self.controlSize)
        )
        // Only the minimal and expanded styles reach for the popover; the default style is
        // the one that detaches the Color Panel into its own window.
        well.colorWellStyle = .minimal
        well.supportsAlpha = true
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.setAccessibilityLabel(accessibilityLabel)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.onChange = { color = $0 }
        well.setAccessibilityLabel(accessibilityLabel)

        // Compared against what was last pushed in rather than against `well.color`: the
        // well reports its colour in whatever space the picker handed it, so a round trip
        // through `NSColor` does not come back equal and the well would be reset on every
        // update — mid-drag included.
        guard context.coordinator.appliedColor != color else { return }
        context.coordinator.appliedColor = color
        context.coordinator.isApplyingBinding = true
        well.color = NSColor(color ?? .clear)
        context.coordinator.isApplyingBinding = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Color?) -> Void = { _ in }
        /// The value SwiftUI last wrote into the well, used to tell its edits from ours.
        var appliedColor: Color?
        /// Swallows the action the well sends back while the binding is being applied.
        var isApplyingBinding = false

        @objc
        func colorChanged(_ sender: NSColorWell) {
            guard !isApplyingBinding else { return }
            let picked = Color(nsColor: sender.color)
            appliedColor = picked
            onChange(picked)
        }
    }
}

/// A toolbar button that shows a backdrop colour as a swatch and picks a new one in a popover.
///
/// The toolbar only has room for a glance: an icon saying what the colour is for and a dot
/// saying what it is. Choosing happens in the popover, where a row of presets covers the
/// usual reasons for a backdrop — reading a transparent image against light, dark, or a
/// colour that appears in neither mode — and a colour well handles anything else.
struct BackdropColorButton: View {
    /// The neutrals and the one loud colour a transparent snapshot is usually read against.
    ///
    /// Named, because the View menu offers the same colours by name.
    static let presets: [(name: String, color: Color)] = [
        ("White", .white),
        ("Light Grey", Color(white: 0.85)),
        ("Grey", Color(white: 0.5)),
        ("Dark Grey", Color(white: 0.2)),
        ("Black", .black),
        ("Green", Color(red: 0, green: 0.85, blue: 0.3)),
    ]

    let title: String
    let systemImage: String
    let help: String
    @Binding var color: Color?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                ColorSwatch(color: color, diameter: 12)
            }
        }
        .help(help)
        .accessibilityLabel(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            picker
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            HStack(spacing: 8) {
                swatchButton(nil, name: "None")
                ForEach(Self.presets, id: \.name) { preset in
                    swatchButton(preset.color, name: preset.name)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Custom")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                PopoverColorWell(color: $color, accessibilityLabel: "Custom \(title)")
                    .frame(
                        width: PopoverColorWell.controlSize.width,
                        height: PopoverColorWell.controlSize.height
                    )
            }
        }
        // Sized by its content rather than pinned: a fixed width ran the last swatch into
        // the popover's rounded corner. The padding clears that corner radius as well.
        .padding(16)
        .fixedSize()
    }

    private func swatchButton(_ candidate: Color?, name: String) -> some View {
        let isSelected = candidate == color
        return Button {
            color = candidate
        } label: {
            ColorSwatch(color: candidate, diameter: 22)
                .padding(2)
                .overlay {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        // The selection ring already marks the chosen swatch; a focus ring around the first
        // one as the popover opens reads as a second selection.
        .focusEffectDisabled()
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A round colour sample; no colour at all is drawn as an empty circle struck through.
struct ColorSwatch: View {
    let color: Color?
    let diameter: CGFloat

    var body: some View {
        ZStack {
            if let color {
                Circle().fill(color)
            } else {
                Circle().fill(.background)
                Path { path in
                    let inset = diameter * 0.2
                    path.move(to: CGPoint(x: diameter - inset, y: inset))
                    path.addLine(to: CGPoint(x: inset, y: diameter - inset))
                }
                .stroke(.red, lineWidth: max(1, diameter / 12))
            }
            Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
    }
}

#Preview {
    BackdropColorButton(
        title: "Panel Background",
        systemImage: "rectangle.inset.filled",
        help: "Background behind the image",
        color: .constant(.orange)
    )
    .padding()
}
