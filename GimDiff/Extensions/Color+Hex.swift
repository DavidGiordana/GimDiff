//
//  Color+Hex.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import SwiftUI

extension Color {
    /// Builds a colour from a `#RRGGBB` or `#RRGGBBAA` string.
    ///
    /// - Returns: `nil` when the string is not a six- or eight-digit hex triplet.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }

        guard digits.count == 6 || digits.count == 8,
              let value = UInt32(digits, radix: 16) else { return nil }

        let hasAlpha = digits.count == 8
        let components = hasAlpha ? [24, 16, 8, 0] : [16, 8, 0]
        let channels = components.map { Double((value >> $0) & 0xFF) / 255 }

        self.init(
            .sRGB,
            red: channels[0],
            green: channels[1],
            blue: channels[2],
            opacity: hasAlpha ? channels[3] : 1
        )
    }

    /// The `#RRGGBB` representation of the colour in the sRGB space.
    var hexString: String {
        let components = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let channels = [components.redComponent, components.greenComponent, components.blueComponent]
        return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}
