//
//  CanvasZoom.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import Foundation

/// The arithmetic behind a pane's zoom, kept apart from the scroll view that applies it.
///
/// A magnification is measured against the image's actual size — its pixels at the density
/// it was recorded at — so 1 is always 1:1, and 100% in the footer means the same thing in
/// every pane whatever the pane's size.
enum CanvasZoom {
    /// Room left around a fitted image, so its edge never runs into the pane's.
    static let fitMargin: CGFloat = 12
    static let minimumMagnification: CGFloat = 0.1
    static let maximumMagnification: CGFloat = 16

    /// Where Zoom In and Zoom Out stop. Fixed stops rather than a fixed factor, so stepping
    /// from a fit of 43% lands on a round 50% instead of on 54%.
    static let stops: [CGFloat] = [0.1, 0.125, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16]

    /// The magnification at which the whole image fits `viewport`, inside the margin.
    ///
    /// A small image is enlarged to fit as well as a large one reduced: Fit means the image
    /// fills the pane, which is what makes a 20-point icon readable without typing a number.
    static func fitMagnification(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let width = max(viewportSize.width - 2 * fitMargin, 1)
        let height = max(viewportSize.height - 2 * fitMargin, 1)
        return min(width / imageSize.width, height / imageSize.height)
    }

    /// How far a pane may zoom. A fit beyond the fixed limits widens them, so Fit can always
    /// be pinched back to.
    static func range(fit: CGFloat) -> ClosedRange<CGFloat> {
        min(minimumMagnification, fit)...max(maximumMagnification, fit)
    }

    /// The next stop past `magnification` in `direction` (positive to zoom in), or the end
    /// of the range when there is no stop left.
    static func stepped(from magnification: CGFloat, zoomingIn: Bool, fit: CGFloat) -> CGFloat {
        let range = range(fit: fit)
        // A hair of slack, so a magnification that is a stop but for rounding is not
        // stepped to itself.
        let slack: CGFloat = 0.001
        let next = zoomingIn
            ? stops.first { $0 > magnification * (1 + slack) } ?? range.upperBound
            : stops.last { $0 < magnification * (1 - slack) } ?? range.lowerBound
        return min(max(next, range.lowerBound), range.upperBound)
    }

    /// The magnification after one scroll-wheel event of `delta` while ⌘ is held.
    ///
    /// Exponential in the distance scrolled, so a notch in and a notch out land back where
    /// they started at any scale.
    static func wheeled(from magnification: CGFloat, delta: CGFloat, isPrecise: Bool) -> CGFloat {
        magnification * exp(delta * (isPrecise ? 0.01 : 0.1))
    }

    /// The footer's text for `magnification`, as a whole percentage.
    static func percentText(_ magnification: CGFloat) -> String {
        Double(magnification).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Reads a typed zoom back as a magnification: `150`, `150%`, and `150 %` all mean 1.5.
    static func magnification(fromPercentText text: String) -> CGFloat? {
        let digits = text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let percent = Double(digits), percent.isFinite, percent > 0 else { return nil }
        return CGFloat(percent / 100)
    }
}

/// Where one pane's zoom stands, as the footer shows it and two linked panes share it.
///
/// The centre is an image point, measured from the image's top-left corner, rather than a
/// fraction of the image: two images of different sizes are aligned at their top-left
/// corners, as the diff mask compares them, so the same point is the same pixel in both.
struct PaneViewport: Equatable {
    /// Whether the pane is following its own size, refitting the image as it changes.
    var isFitting: Bool
    var magnification: CGFloat
    /// The image point at the centre of what is visible.
    var center: CGPoint

    /// What a pane shows before it has been laid out or touched.
    static let fitted = PaneViewport(isFitting: true, magnification: 1, center: .zero)

    /// Whether the pane is at the image's actual size, rather than merely fitted at 100%.
    var isActualSize: Bool {
        !isFitting && abs(magnification - 1) < 0.000_1
    }

    /// Equal but for rounding, which a round trip through two panes introduces and which,
    /// taken as a change, would bounce between them for ever. Two fitted panes are equal
    /// whatever their numbers: each fits its own image.
    func isClose(to other: PaneViewport) -> Bool {
        guard !isFitting, !other.isFitting else { return isFitting == other.isFitting }
        let tolerance: CGFloat = 0.01
        return abs(magnification - other.magnification) < 0.000_1
            && abs(center.x - other.center.x) < tolerance
            && abs(center.y - other.center.y) < tolerance
    }
}
