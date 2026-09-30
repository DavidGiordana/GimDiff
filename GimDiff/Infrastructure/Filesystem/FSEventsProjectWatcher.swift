//
//  FSEventsProjectWatcher.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import CoreServices
import Foundation

/// ``ProjectWatching`` on top of FSEvents.
///
/// One recursive stream per project rather than a descriptor per folder: the kernel does
/// the watching, so an idle project costs nothing however many directories it has, and the
/// events arrive on a background queue whether or not GimDiff is the frontmost app.
struct FSEventsProjectWatcher: ProjectWatching {
    /// How long the system gathers events before handing them over.
    ///
    /// Long enough that a file written to a scratch name and renamed into place arrives as
    /// one batch, by which time the scratch name is already gone.
    var latency: TimeInterval = 0.5
    /// Whether writes made by this process are left out.
    ///
    /// GimDiff refreshes after its own promotions and deletions as part of performing them,
    /// so hearing about them a second time would only repeat the work.
    var ignoresOwnWrites = true

    func changes(under roots: [URL]) -> AsyncStream<[ProjectFileEvent]> {
        AsyncStream { continuation in
            let session = FSEventsSession(roots: roots, continuation: continuation)
            guard session.start(latency: latency, ignoresOwnWrites: ignoresOwnWrites) else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in session.stop() }
        }
    }
}

/// One running stream and the continuation it feeds.
///
/// `@unchecked Sendable` because the stream reference is written once, before the stream
/// is started, and only ever read again on ``queue``.
private final class FSEventsSession: @unchecked Sendable {
    /// Flags that say the item itself changed, as opposed to its ownership or attributes.
    private static let contentFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated
            | kFSEventStreamEventFlagItemRemoved
            | kFSEventStreamEventFlagItemRenamed
            | kFSEventStreamEventFlagItemModified
    )
    /// Flags that say events were lost and the folder named has to be looked at afresh.
    private static let rescanFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
    )

    private let queue = DispatchQueue(label: "com.davidgiordana.GimDiff.project-watcher", qos: .utility)
    private let continuation: AsyncStream<[ProjectFileEvent]>.Continuation
    private let roots: [(canonical: String, given: String)]
    private var stream: FSEventStreamRef?

    init(roots: [URL], continuation: AsyncStream<[ProjectFileEvent]>.Continuation) {
        self.continuation = continuation
        // FSEvents reports canonical paths — `/private/var/…` for a root given as
        // `/var/…` — so each root is remembered both ways and events are spelled back
        // the way the caller asked.
        self.roots = roots.map { root in
            let given = root.standardizedFileURL.path
            let canonical = (try? root.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath
            return (canonical ?? given, given)
        }
    }

    func start(latency: TimeInterval, ignoresOwnWrites: Bool) -> Bool {
        // The stream retains the session for as long as it can call back into it.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<FSEventsSession>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<FSEventsSession>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        var flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        if ignoresOwnWrites { flags |= kFSEventStreamCreateFlagIgnoreSelf }

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let session = Unmanaged<FSEventsSession>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                session.deliver(paths: paths, flags: UnsafeBufferPointer(start: flags, count: count))
            },
            &context,
            roots.map(\.canonical) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
        ) else { return false }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }
        return true
    }

    /// Tears the stream down on the queue its callbacks run on, so none is in flight.
    func stop() {
        queue.async { [self] in
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func deliver(paths: [String], flags: UnsafeBufferPointer<FSEventStreamEventFlags>) {
        var events: [ProjectFileEvent] = []

        for (path, flags) in zip(paths, flags) {
            let mustRescan = flags & Self.rescanFlags != 0
            guard mustRescan || flags & Self.contentFlags != 0 else { continue }

            let isDirectory = mustRescan
                || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
            events.append(ProjectFileEvent(
                url: URL(fileURLWithPath: spelledAsGiven(path), isDirectory: isDirectory),
                isDirectory: isDirectory
            ))
        }

        guard !events.isEmpty else { return }
        continuation.yield(events)
    }

    private func spelledAsGiven(_ path: String) -> String {
        for root in roots where root.canonical != root.given {
            if path == root.canonical { return root.given }
            if path.hasPrefix(root.canonical + "/") {
                return root.given + path.dropFirst(root.canonical.count)
            }
        }
        return path
    }
}
