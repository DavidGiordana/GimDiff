//
//  HelpPresentationTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The help sheet shares the window with the Open PR sheet, and only one can be up.
@Suite("Help sheet")
@MainActor
struct HelpPresentationTests {
    @Test("Help opens and closes")
    func presentsAndDismisses() {
        let fixture = AppStateFixture()

        fixture.state.presentHelp()
        #expect(fixture.state.isHelpPresented)

        fixture.state.dismissHelp()
        #expect(fixture.state.isHelpPresented == false)
    }

    @Test("Help does not open over the Open PR sheet")
    func yieldsToThePullRequestSheet() {
        let fixture = AppStateFixture()
        fixture.state.isPullRequestSheetPresented = true

        fixture.state.presentHelp()

        #expect(fixture.state.isHelpPresented == false)
    }

    @Test("Opening a pull request puts the help away")
    func pullRequestSheetReplacesHelp() {
        let fixture = AppStateFixture()
        fixture.state.presentHelp()

        fixture.state.presentPullRequestSheet()

        #expect(fixture.state.isHelpPresented == false)
        #expect(fixture.state.isPullRequestSheetPresented)
    }

    @Test("Every topic has something to read")
    func topicsAreFilled() {
        for topic in HelpTopic.allCases {
            #expect(topic.sections.isEmpty == false, "\(topic.title) has no sections")
        }
    }
}
