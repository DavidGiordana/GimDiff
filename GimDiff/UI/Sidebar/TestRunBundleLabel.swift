//
//  TestRunBundleLabel.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// How a test run is named in the sidebar's run picker and in the View menu.
enum TestRunBundleLabel {
    /// The run's date, the workspace that ran it when the project has runs from more than
    /// one, and a mark on the newest.
    ///
    /// The date is to the minute unless another run began in the same minute — a run
    /// cancelled and started again — when the seconds are what tell the two apart. The
    /// bundle's own name stands in only for a run that records no date: it is Xcode's to
    /// format, so it is shown but never read.
    static func title(of bundle: TestRunBundle, among bundles: [TestRunBundle]) -> String {
        var title = bundle.createdAt.map { date in
            let sharesMinute = bundles.contains { other in
                other.url != bundle.url && other.createdAt.map(minute(of:)) == minute(of: date)
            }
            return sharesMinute
                ? date.formatted(date: .abbreviated, time: .standard)
                : date.formatted(date: .abbreviated, time: .shortened)
        } ?? bundle.name
        if Set(bundles.map(\.workspaceName)).count > 1 {
            title += " · \(bundle.workspaceName)"
        }
        if bundle.url == bundles.first?.url {
            title += " (Latest)"
        }
        return title
    }

    private static func minute(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
    }
}
