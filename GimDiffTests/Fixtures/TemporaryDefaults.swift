//
//  TemporaryDefaults.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// A throwaway `UserDefaults` domain that erases itself once the test releases it.
///
/// `AppState` persists its recent projects to real defaults, so a test that exercised
/// `.standard` would both read whatever the developer's own copy of GimDiff has remembered
/// and leave its fixtures behind for the next run to find.
final class TemporaryDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "com.davidgiordana.GimDiff.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
