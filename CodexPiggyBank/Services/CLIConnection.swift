import Foundation

/// A short-lived, read-only JSON-lines connection. No prompt or tool invocation is sent.
final class CLIConnection: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var isStopped = false
    private var timedOut = false

    var didTimeOut: Bool { lock.withLock { timedOut } }

    init(executable: URL, arguments: [String], environment: [String: String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        // Never collect CLI diagnostics, which may include account credentials.
        process.standardError = FileHandle.nullDevice
    }

    var lines: AsyncLineSequence<FileHandle.AsyncBytes> {
        output.fileHandleForReading.bytes.lines
    }

    func start() throws {
        try lock.withLock {
            guard !isStopped else { throw CancellationError() }
            try process.run()
            try output.fileHandleForWriting.close()
            try input.fileHandleForReading.close()
        }
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            guard !isStopped else { throw CancellationError() }
            try input.fileHandleForWriting.write(contentsOf: data)
        }
    }

    func stop(timedOut: Bool = false) {
        lock.withLock {
            guard !isStopped else { return }
            isStopped = true
            self.timedOut = timedOut
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                // These processes serve only this probe, and have no session to save.
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}
