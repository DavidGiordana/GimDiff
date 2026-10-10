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
    /// Whether the source said which image is which, rather than only listing them.
    ///
    /// False for a log that names two paths without labelling either: the order it printed
    /// them in is all the sides were chosen from.
    var rolesAreStated: Bool

    init(
        candidateURL: URL,
        baselineURL: URL? = nil,
        candidateTag: String? = nil,
        baselineTag: String? = nil,
        rolesAreStated: Bool = false
    ) {
        self.candidateURL = candidateURL
        self.baselineURL = baselineURL
        self.candidateTag = candidateTag
        self.baselineTag = baselineTag
        self.rolesAreStated = rolesAreStated
    }
}
