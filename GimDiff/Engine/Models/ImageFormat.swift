//
//  ImageFormat.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Encoding of a snapshot image on disk.
enum ImageFormat: Sendable, Hashable {
    case png
    case jpg
    case webp
    /// A format GimDiff does not recognise, carrying the file extension it was read from.
    case unknown(String)

    /// Derives the format from a file extension, with or without its leading dot.
    ///
    /// `jpeg` folds into ``jpg`` so the two spellings compare equal.
    init(fileExtension: String) {
        let normalized = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        switch normalized {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpg
        case "webp": self = .webp
        default: self = .unknown(normalized)
        }
    }

    /// The format of the image at `url`, inferred from its path extension.
    init(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    /// Whether GimDiff recognises the format, rather than having kept an unfamiliar
    /// extension verbatim.
    ///
    /// Snapshot discovery filters on this, so the set of extensions it collects and the
    /// set this enum models can never drift apart.
    var isRecognized: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// Extension GimDiff writes when it creates a file in this format.
    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpg: "jpg"
        case .webp: "webp"
        case let .unknown(value): value
        }
    }
}
