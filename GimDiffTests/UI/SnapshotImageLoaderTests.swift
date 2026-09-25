//
//  SnapshotImageLoaderTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Snapshot image loading")
struct SnapshotImageLoaderTests {
    @Test("An unmarked image is drawn at 1x")
    func unmarkedImageIsUnscaled() throws {
        let decoded = try Self.decoded(ImageFixtures.identicalA)

        #expect(decoded.recordedScale == 1)
    }

    @Test("A 144 DPI image is drawn at the 2x it was recorded at")
    func readsScaleFromResolution() throws {
        let decoded = try Self.decoded(ImageFixtures.dense144DPI)

        #expect(decoded.recordedScale == 2)
        #expect(decoded.pixelSize == CGSize(width: 100, height: 100))
    }

    @Test("A name marked @3x is drawn at 3x")
    func readsScaleFromName() throws {
        let decoded = try Self.decoded(ImageFixtures.retina3x)

        #expect(decoded.recordedScale == 3)
    }

    private static func decoded(_ url: URL) throws -> DecodedSnapshotImage {
        guard case let .loaded(decoded) = SnapshotImageLoader.load(url) else {
            Issue.record("\(url.lastPathComponent) did not decode")
            throw CancellationError()
        }
        return decoded
    }
}
