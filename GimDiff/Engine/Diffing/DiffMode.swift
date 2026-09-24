//
//  DiffMode.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// How a `SnapshotPair` is presented on the canvas.
enum DiffMode: String, CaseIterable, Identifiable, Sendable {
    /// Reference and failure shown next to each other.
    case sideBySide
    /// Failure drawn over the reference with a draggable split.
    case curtain
    /// Failure drawn over the reference at partial opacity.
    case onionSkin
    /// Only the pixels that differ between the two images.
    case difference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: "Side by Side"
        case .curtain: "Curtain"
        case .onionSkin: "Onion Skin"
        case .difference: "Difference"
        }
    }

    /// SF Symbol representing the mode in toolbars and pickers.
    var symbolName: String {
        switch self {
        case .sideBySide: "rectangle.split.2x1"
        case .curtain: "slider.horizontal.below.rectangle"
        case .onionSkin: "square.on.square"
        case .difference: "circle.lefthalf.filled"
        }
    }
}
