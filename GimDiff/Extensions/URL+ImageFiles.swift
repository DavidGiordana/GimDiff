//
//  URL+ImageFiles.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

extension URL {
    /// Extensions GimDiff is willing to load as a snapshot.
    static let snapshotImageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    /// Whether the path extension names an image format GimDiff can display.
    var isImageFile: Bool {
        Self.snapshotImageExtensions.contains(pathExtension.lowercased())
    }
}
