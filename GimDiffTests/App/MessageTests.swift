//
//  MessageTests.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
import Testing
@testable import GimDiff

/// The message under the canvas: which ones close themselves, and the history behind them.
@Suite("Messages")
@MainActor
struct MessageTests {
    /// A state whose notices close almost at once, so a test does not wait six seconds.
    private func state() -> AppState {
        let state = AppStateFixture().state
        state.noticeLifetime = .milliseconds(20)
        return state
    }

    @Test("A notice closes itself and stays in the history")
    func noticeClosesItself() async {
        let state = state()

        state.report("Nothing to copy.")
        #expect(state.currentMessage?.kind == .notice)
        await state.currentMessageDismissal?.value

        #expect(state.currentMessage == nil)
        #expect(state.recentMessages.map(\.text) == ["Nothing to copy."])
    }

    @Test("A failure stays until it is dismissed")
    func failureStays() async throws {
        let state = state()

        state.report(CocoaError(.fileWriteNoPermission))
        #expect(state.currentMessage?.kind == .failure)
        #expect(state.currentMessageDismissal == nil)
        try await Task.sleep(for: .milliseconds(60))
        #expect(state.currentMessage != nil)

        state.dismissMessage()
        #expect(state.currentMessage == nil)
    }

    @Test("A notice under the pointer stays, and closes once the pointer leaves")
    func hoverHoldsANotice() async throws {
        let state = state()

        state.report("Read-only.")
        state.holdMessage(true)
        try await Task.sleep(for: .milliseconds(60))
        #expect(state.currentMessage?.text == "Read-only.")

        state.holdMessage(false)
        await state.currentMessageDismissal?.value
        #expect(state.currentMessage == nil)
    }

    @Test("A notice's countdown never closes the message that replaced it")
    func replacedNoticeLeavesTheNewMessage() async throws {
        let state = state()

        state.report("First.")
        state.report(CocoaError(.fileReadNoSuchFile))
        try await Task.sleep(for: .milliseconds(60))

        #expect(state.currentMessage?.kind == .failure)
        #expect(state.recentMessages.count == 2)
    }

    @Test("The history lists the newest first and keeps only the last few")
    func historyIsCapped() {
        let state = state()

        for number in 1...(AppState.recentMessagesLimit + 3) {
            state.report("Message \(number)")
        }

        #expect(state.recentMessages.count == AppState.recentMessagesLimit)
        #expect(state.recentMessages.first?.text == "Message \(AppState.recentMessagesLimit + 3)")
        #expect(state.recentMessages.last?.text == "Message 4")

        state.clearRecentMessages()
        #expect(state.recentMessages.isEmpty)
    }
}
