//
//  TestRunReport.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// The failed tests of one run, with the images each of them attached.
///
/// Everything here is what Xcode recorded about the run, not what any snapshot library
/// says about itself: which tests failed, which step of a test attached which file, and
/// the names those were given. The names are carried for display and are never read for
/// meaning. Which image is a baseline is decided later, from its bytes, by
/// ``TestRunMatcher``.
struct TestRunReport: Sendable, Equatable {
    /// The result bundle the report was read from.
    let bundleURL: URL
    /// Folder holding the exported images, owned by whoever asked for the report.
    ///
    /// The images are copies nobody asked to keep, so the folder is to be removed with
    /// ``FilesystemService/removeItem(at:)`` once the report is no longer on screen.
    let scratchDirectory: URL
    /// When the run began, or `nil` when the bundle does not say.
    ///
    /// What dates the report: a snapshot written since then is not the file the run saw.
    var startedAt: Date?
    var failures: [TestRunFailure]
}

/// One test that failed.
struct TestRunFailure: Identifiable, Sendable, Equatable {
    /// The identifier Xcode gives the test, such as `CardsTests/testCardArtwork()`.
    let id: String
    var name: String
    /// Empty when the test failed without attaching an image.
    var groups: [TestRunImageGroup]
    /// When this test ran, for a report gathered from runs made at different times;
    /// `nil` defers to ``TestRunReport/startedAt``.
    ///
    /// Paparazzi verifies each module on its own, and a module verified last week must not
    /// date the failures of one verified a minute ago.
    var startedAt: Date?
}

/// The images one step of a test attached together.
///
/// A step is the unit because it is the only grouping Xcode records: an assertion that
/// attaches what it expected beside what it got does so in one step, and a test asserting
/// twice produces two.
struct TestRunImageGroup: Identifiable, Sendable, Equatable {
    let id: String
    /// What Xcode calls the step, shown as it is.
    var title: String
    /// In the order they were attached.
    var images: [TestRunImage]
}

/// One image attached to a test.
struct TestRunImage: Identifiable, Sendable, Hashable {
    /// The identifier Xcode gave the attachment.
    let id: String
    /// The name the attachment was recorded under, shown as it is.
    var name: String
    /// The exported copy, inside the report's scratch folder.
    var fileURL: URL
}
