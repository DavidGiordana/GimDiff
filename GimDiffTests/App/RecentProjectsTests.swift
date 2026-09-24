//
//  RecentProjectsTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

@Suite("Recent projects")
@MainActor
struct RecentProjectsTests {
    private func folder(_ name: String) -> URL {
        URL(fileURLWithPath: "/Projects/\(name)", isDirectory: true)
    }

    @Test("A new state starts with whatever the defaults remembered")
    func readsPersistedProjects() {
        let defaults = TemporaryDefaults()
        defaults.defaults.set(["/Projects/One", "/Projects/Two"], forKey: AppState.recentProjectsKey)

        let state = AppState(defaults: defaults.defaults)

        #expect(state.recentProjects.map(\.path) == ["/Projects/One", "/Projects/Two"])
    }

    @Test("The most recently opened folder comes first")
    func ordersMostRecentFirst() {
        let fixture = AppStateFixture()

        fixture.state.addRecentProject(folder("One"))
        fixture.state.addRecentProject(folder("Two"))

        #expect(fixture.state.recentProjects.map(\.lastPathComponent) == ["Two", "One"])
    }

    @Test("Reopening a folder moves it to the top rather than duplicating it")
    func deduplicates() {
        let fixture = AppStateFixture()

        fixture.state.addRecentProject(folder("One"))
        fixture.state.addRecentProject(folder("Two"))
        fixture.state.addRecentProject(folder("One"))

        #expect(fixture.state.recentProjects.map(\.lastPathComponent) == ["One", "Two"])
    }

    @Test("The list forgets the oldest folder once it is full")
    func capsTheList() {
        let fixture = AppStateFixture()

        for index in 0...AppState.recentProjectsLimit {
            fixture.state.addRecentProject(folder("Project\(index)"))
        }

        #expect(fixture.state.recentProjects.count == AppState.recentProjectsLimit)
        #expect(fixture.state.recentProjects.first?.lastPathComponent
            == "Project\(AppState.recentProjectsLimit)")
        #expect(fixture.state.recentProjects.contains { $0.lastPathComponent == "Project0" } == false)
    }

    @Test("One folder can be forgotten without disturbing the rest")
    func removesOneEntry() {
        let fixture = AppStateFixture()
        fixture.state.addRecentProject(folder("One"))
        fixture.state.addRecentProject(folder("Two"))
        fixture.state.addRecentProject(folder("Three"))

        fixture.state.removeRecentProject(folder("Two"))

        #expect(fixture.state.recentProjects.map(\.lastPathComponent) == ["Three", "One"])
    }

    @Test("The whole history can be cleared")
    func clearsEverything() {
        let fixture = AppStateFixture()
        fixture.state.addRecentProject(folder("One"))

        fixture.state.clearRecentProjects()

        #expect(fixture.state.recentProjects.isEmpty)
    }

    @Test("Every change is written straight back to the defaults")
    func persistsEveryChange() {
        let fixture = AppStateFixture()
        let defaults = fixture.defaults.defaults

        fixture.state.addRecentProject(folder("One"))
        fixture.state.addRecentProject(folder("Two"))
        #expect(defaults.stringArray(forKey: AppState.recentProjectsKey)
            == ["/Projects/Two", "/Projects/One"])

        fixture.state.removeRecentProject(folder("Two"))
        #expect(defaults.stringArray(forKey: AppState.recentProjectsKey) == ["/Projects/One"])

        fixture.state.clearRecentProjects()
        #expect(defaults.stringArray(forKey: AppState.recentProjectsKey) == [])
    }
}
