//
//  IngestionPayload.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A comparison GimDiff was handed from outside the app.
///
/// The candidate is the image under examination — usually the one a failing test just
/// wrote. The baseline is what it should have matched, and is absent when the source named
/// only one image.
struct IngestionPayload: Sendable, Equatable {
    var candidateURL: URL
    var baselineURL: URL?
    /// Label the source used for the candidate, such as `Failure`, when it named one.
    var candidateTag: String?
    /// Label the source used for the baseline, such as `Recorded`, when it named one.
    var baselineTag: String?

    init(
        candidateURL: URL,
        baselineURL: URL? = nil,
        candidateTag: String? = nil,
        baselineTag: String? = nil
    ) {
        self.candidateURL = candidateURL
        self.baselineURL = baselineURL
        self.candidateTag = candidateTag
        self.baselineTag = baselineTag
    }
}
