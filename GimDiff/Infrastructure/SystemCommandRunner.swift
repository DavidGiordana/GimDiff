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

    func run(_ command: Command) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                continuation.resume(with: Result { try Self.execute(command) })
            }
        }
    }

    private static func execute(_ command: Command) throws -> CommandResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        // Drain both pipes on separate threads: reading them in sequence would deadlock as
        // soon as the process filled the buffer of whichever pipe is read second.
        let outputBuffer = OutputBuffer()
        let errorBuffer = OutputBuffer()
        let group = DispatchGroup()
        drain(standardOutput, into: outputBuffer, group: group)
        drain(standardError, into: errorBuffer, group: group)

        try process.run()
        process.waitUntilExit()
        group.wait()

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
