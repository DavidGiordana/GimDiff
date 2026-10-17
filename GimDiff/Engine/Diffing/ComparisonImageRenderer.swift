//
//  ComparisonImageRenderer.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The words written under a rendered comparison, so the picture explains itself to
/// somebody who never saw the canvas.
struct ComparisonCaption: Sendable, Equatable {
    /// What the image on the left, or underneath, is: "Baseline", or "Left" when nothing
    /// could tell the sides apart.
    var leftTitle: String
    var rightTitle: String
    /// Where the split stood or how far the fade went, written between the two.
    var detail: String
}

/// Draws one of the canvas's single-frame comparisons — the split and the onion skin — as
/// a picture at the snapshots' own resolution.
///
/// Rendered from the images rather than captured from the window, so the result does not
/// depend on how large the window is or how far it is zoomed, and the same code is what a
/// test checks.
enum ComparisonImageRenderer {
    /// The images are laid out the way every comparison mode lays them out: at one pixel to
    /// one pixel, from the top-left corner of a frame as large as the two together.
    ///
    /// Unscaled, so a pixel of one sits over the same pixel of the other whatever their
    /// sizes, which is the alignment the diff mask measures with. Scaling the smaller image
    /// up to fit would shift every row of it, and an overlay would then show a change
    /// everywhere. Rects are measured from the top, as SwiftUI measures them.
    struct Layout: Equatable {
        var canvasSize: CGSize
        var leftRect: CGRect
        var rightRect: CGRect

        /// Where both images are, together: the span a split position is a fraction of.
        var imageBounds: CGRect { leftRect.union(rightRect) }

        /// `rect`, a part of the canvas, where it lands once the canvas is fitted into
        /// `size` with its aspect kept and centred.
        func rect(_ rect: CGRect, fittedIn size: CGSize) -> CGRect {
            guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
            let ratio = min(size.width / canvasSize.width, size.height / canvasSize.height)
            let origin = CGPoint(
                x: (size.width - canvasSize.width * ratio) / 2,
                y: (size.height - canvasSize.height * ratio) / 2
            )
            return CGRect(
                x: origin.x + rect.minX * ratio,
                y: origin.y + rect.minY * ratio,
                width: rect.width * ratio,
                height: rect.height * ratio
            )
        }
    }

    static func layout(left: CGSize, right: CGSize) -> Layout {
        Layout(
            canvasSize: CGSize(width: max(left.width, right.width), height: max(left.height, right.height)),
            leftRect: CGRect(origin: .zero, size: left),
            rightRect: CGRect(origin: .zero, size: right)
        )
    }

    /// Where the divider falls for `position`, a fraction of the images' width.
    static func splitX(at position: Double, in layout: Layout) -> CGFloat {
        let bounds = layout.imageBounds
        return bounds.minX + bounds.width * CGFloat(min(max(position, 0), 1))
    }

    // MARK: - Rendering

    /// The left image up to the split and the right one after it, with the divider drawn
    /// where it stood.
    static func split(
        left: CGImage,
        right: CGImage,
        position: Double,
        backdrop: CGColor?,
        matte: CGColor?,
        caption: ComparisonCaption
    ) -> CGImage? {
        let layout = layout(left: size(of: left), right: size(of: right))
        let divider = splitX(at: position, in: layout)

        return render(layout: layout, backdrop: backdrop, caption: caption) { context, size in
            context.saveGState()
            context.clip(to: CGRect(x: divider, y: 0, width: size.width - divider, height: size.height))
            draw(right, in: flipped(layout.rightRect, in: size), matte: matte, alpha: 1, context: context)
            context.restoreGState()

            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: divider, height: size.height))
            draw(left, in: flipped(layout.leftRect, in: size), matte: matte, alpha: 1, context: context)
            context.restoreGState()

            // White with a dark edge, so it reads over a light image and a dark one alike.
            let width = max(2, size.width / 400)
            context.setFillColor(CGColor(gray: 0, alpha: 0.45))
            context.fill(CGRect(x: divider - width, y: 0, width: width * 2, height: size.height))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: divider - width / 2, y: 0, width: width, height: size.height))
        }
    }

    /// The right image over the left one at `rightOpacity`, as the onion skin draws them.
    static func onionSkin(
        under left: CGImage,
        over right: CGImage,
        rightOpacity: Double,
        backdrop: CGColor?,
        matte: CGColor?,
        caption: ComparisonCaption
    ) -> CGImage? {
        let layout = layout(left: size(of: left), right: size(of: right))
        return render(layout: layout, backdrop: backdrop, caption: caption) { context, size in
            // The matte goes behind the lower image only, as on the canvas: behind the upper
            // one too, it would hide the lower image wherever the upper is transparent.
            draw(left, in: flipped(layout.leftRect, in: size), matte: matte, alpha: 1, context: context)
            draw(
                right,
                in: flipped(layout.rightRect, in: size),
                matte: nil,
                alpha: CGFloat(min(max(rightOpacity, 0), 1)),
                context: context
            )
        }
    }

    /// The image encoded as PNG, the form a pasteboard and every chat client take.
    static func pngData(_ image: CGImage) -> Data? {
        guard let buffer = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    /// Decodes the image at `url`, or `nil` when there is none or it will not decode.
    static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Pieces

    /// Height of the caption strip for an image `width` pixels wide: large enough to read
    /// when a phone screenshot is pasted at full size, small beside it.
    static func captionHeight(forWidth width: CGFloat) -> CGFloat {
        (fontSize(forWidth: width) * 2.2).rounded()
    }

    private static func fontSize(forWidth width: CGFloat) -> CGFloat {
        min(max(width / 36, 12), 48)
    }

    private static func render(
        layout: Layout,
        backdrop: CGColor?,
        caption: ComparisonCaption,
        drawImages: (CGContext, CGSize) -> Void
    ) -> CGImage? {
        let imageSize = layout.canvasSize
        let stripHeight = captionHeight(forWidth: imageSize.width)
        let width = Int(imageSize.width.rounded(.up))
        let height = Int((imageSize.height + stripHeight).rounded(.up))
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Core Graphics counts up from the bottom: the strip is drawn first, at the bottom,
        // and the images are moved up above it.
        drawCaption(caption, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: stripHeight), context: context)

        context.saveGState()
        context.translateBy(x: 0, y: stripHeight)
        if let backdrop {
            context.setFillColor(backdrop)
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
        drawImages(context, imageSize)
        context.restoreGState()

        return context.makeImage()
    }

    private static func draw(_ image: CGImage, in rect: CGRect, matte: CGColor?, alpha: CGFloat, context: CGContext) {
        context.saveGState()
        context.setAlpha(alpha)
        if let matte {
            context.setFillColor(matte)
            context.fill(rect)
        }
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private static func drawCaption(_ caption: ComparisonCaption, in strip: CGRect, context: CGContext) {
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(strip)

        let fontSize = fontSize(forWidth: strip.width)
        let inset = fontSize * 0.8
        let baseline = strip.midY - fontSize * 0.35
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)

        let left = line(caption.leftTitle, font: font, gray: 1)
        let right = line(caption.rightTitle, font: font, gray: 1)
        draw(left, at: CGPoint(x: strip.minX + inset, y: baseline), context: context)
        draw(right, at: CGPoint(x: strip.maxX - inset - width(of: right), y: baseline), context: context)

        // Centred between the titles, and cut short with an ellipsis rather than run into
        // them: a long snapshot name on a narrow image is the usual case, not an odd one.
        let room = strip.width - 2 * (max(width(of: left), width(of: right)) + 2 * inset)
        guard room > fontSize * 2 else { return }
        var detail = line(caption.detail, font: font, gray: 0.7)
        if width(of: detail) > room,
           let truncated = CTLineCreateTruncatedLine(detail, Double(room), .middle, line("…", font: font, gray: 0.7)) {
            detail = truncated
        }
        draw(detail, at: CGPoint(x: strip.midX - width(of: detail) / 2, y: baseline), context: context)
    }

    private static func line(_ text: String, font: CTFont, gray: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func draw(_ line: CTLine, at point: CGPoint, context: CGContext) {
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func size(of image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// A layout rect, measured from the top, in Core Graphics' coordinates, which count up
    /// from the bottom of the `canvas`.
    private static func flipped(_ rect: CGRect, in canvas: CGSize) -> CGRect {
        CGRect(x: rect.minX, y: canvas.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
