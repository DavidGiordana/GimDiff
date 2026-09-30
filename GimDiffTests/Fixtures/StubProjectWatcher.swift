//
//  StubProjectWatcher.swift
//  GimDiffTests
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation
@testable import GimDiff

/// A `ProjectWatching` double that reports only what a test sends through it.
///
/// Also what keeps an `AppState` under test from opening a real FSEvents stream: a change
/// on disk arriving on its own schedule would refresh the state halfway through whatever
/// the test was asserting.
final class StubProjectWatcher: ProjectWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRoots: [[URL]] = []
    private var continuations: [UUID: AsyncStream<[ProjectFileEvent]>.Continuation] = [:]

    /// The roots of every stream asked for, in call order.
    var watchedRoots: [[URL]] {
        lock.withLock { storedRoots }
    }

    /// How many streams somebody is still listening to.
    var activeStreamCount: Int {
        lock.withLock { continuations.count }
    }

    func changes(under roots: [URL]) -> AsyncStream<[ProjectFileEvent]> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                storedRoots.append(roots)
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { _ = continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Delivers one batch to every stream still open.
    func send(_ events: [ProjectFileEvent]) {
        let open = lock.withLock { Array(continuations.values) }
        for continuation in open {
            continuation.yield(events)
        }
    }
}
