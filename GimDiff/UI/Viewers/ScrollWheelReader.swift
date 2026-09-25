//
//  ScrollWheelReader.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import AppKit
import SwiftUI

/// One turn of a scroll wheel or swipe of a trackpad, as the canvas needs to know it.
struct ScrollWheelTick {
    /// How far the wheel moved, positive when it was pushed away from the user.
    ///
    /// Already corrected for natural scrolling, so the same physical motion zooms the
    /// same way whatever the system preference says.
    let delta: CGFloat
    /// Whether ``delta`` is in points from a trackpad or Magic Mouse, rather than in the
    /// coarse lines a notched wheel reports.
    let isPrecise: Bool
    /// Where the pointer was, measured from the centre of the reader's frame.
    let locationFromCenter: CGPoint
}

/// Reports the scroll-wheel events that land inside its frame, and swallows them.
///
/// SwiftUI has no scroll-wheel gesture outside a `ScrollView`, so this reads the events off
/// a local monitor instead. A monitor rather than a `scrollWheel(with:)` override because it
/// sits as a background: the image in front of it would take the hit test, and the events
/// with it. Only events inside the reader's bounds and window are claimed, so every other
/// scroll view in the app keeps working.
struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: (ScrollWheelTick) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: ReaderView, coordinator: ()) {
        view.removeMonitor()
    }

    final class ReaderView: NSView {
        var onScroll: (ScrollWheelTick) -> Void = { _ in }
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return MainActor.assumeIsolated { self.handle(event) } ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// - Returns: Whether the event was inside the reader and has been consumed.
        private func handle(_ event: NSEvent) -> Bool {
            guard let window, event.window === window else { return false }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return false }

            // Inertia after a trackpad flick would keep zooming well past where the fingers
            // stopped, so only the part of the gesture under the user's hands counts.
            guard event.momentumPhase.isEmpty else { return true }

            let raw = event.scrollingDeltaY
            guard raw != 0 else { return true }

            onScroll(ScrollWheelTick(
                delta: event.isDirectionInvertedFromDevice ? -raw : raw,
                isPrecise: event.hasPreciseScrollingDeltas,
                locationFromCenter: CGPoint(
                    x: location.x - bounds.midX,
                    y: location.y - bounds.midY
                )
            ))
            return true
        }
    }
}
