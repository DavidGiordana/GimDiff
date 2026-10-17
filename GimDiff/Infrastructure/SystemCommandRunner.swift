//
//  SystemCommandRunner.swift
//  GimDiff
//
//  Created by David Giordana.
//  Copyright © 2026 David Giordana. All rights reserved.
//

import Foundation

/// Runs commands with `Process`, passing arguments as an array rather than through a shell.
struct SystemCommandRunner: CommandRunning {
    private static let queue = DispatchQueue(
        label: "com.davidgiordana.GimDiff.command-runner",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Runs `command` to completion, or until the task waiting on it is cancelled.
    ///
    /// Cancellation terminates the process rather than leaving it to finish unwatched: a
    /// test run read is abandoned whenever the user moves on, and an `xcresulttool` export
    /// of a large bundle would otherwise carry on for nothing.
    func run(_ command: Command) async throws -> CommandResult {
        let running = CancellableProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    continuation.resume(with: Result { try Self.execute(command, as: running) })
                }
            }
        } onCancel: {
            running.cancel()
        }
    }

    private static func execute(_ command: Command, as running: CancellableProcess) throws -> CommandResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try running.start(process)

        // Drain both pipes on separate threads: reading them in sequence would deadlock as
        // soon as the process filled the buffer of whichever pipe is read second. Started
        // once the process runs, so a launch that fails leaves no reader waiting forever.
        let outputBuffer = OutputBuffer()
        let errorBuffer = OutputBuffer()
        let group = DispatchGroup()
        drain(standardOutput, into: outputBuffer, group: group)
        drain(standardError, into: errorBuffer, group: group)

        process.waitUntilExit()
        group.wait()
        // A terminated process's status says it was killed, which no caller should read as
        // an answer.
        if running.isCancelled { throw CancellationError() }

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: outputBuffer.string,
            standardError: errorBuffer.string
        )
    }

    private static func drain(_ pipe: Pipe, into buffer: OutputBuffer, group: DispatchGroup) {
        group.enter()
        queue.async {
            buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
    }
}

/// Collects process output written from a reader thread.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        lock.withLock { data.append(newData) }
    }

    var string: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}

/// A process that cancellation can stop, whichever thread the cancellation arrives on.
///
/// `@unchecked Sendable` because every access to its state goes through the lock.
final class CancellableProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Launches `process`, unless cancellation came first: a task cancelled before its
    /// command started should not start it at all.
    func start(_ process: Process) throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            try process.run()
            self.process = process
        }
    }

    /// Terminates the process if it is running, and keeps one from starting later.
    func cancel() {
        lock.withLock {
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }
}
