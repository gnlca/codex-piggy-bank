import Foundation

/// Runs a short command and returns its output only when it exits successfully. Diagnostics are never collected.
enum ProcessRunner {
    static func output(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                       timeout: TimeInterval) async -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            // Drain while running so chatty commands cannot fill the pipe and stall.
            let reader = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
            process.terminationHandler = { process in
                let status = process.terminationStatus
                Task { continuation.resume(returning: status == 0 ? await reader.value : nil) }
            }
            do { try process.run() } catch {
                process.terminationHandler = nil
                try? output.fileHandleForWriting.close()
                reader.cancel()
                continuation.resume(returning: nil)
                return
            }
            try? output.fileHandleForWriting.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        }
    }

    /// Reads a login item with `security`, as Claude Code and Antigravity do, so its existing Keychain access applies.
    static func keychainPassword(service: String, account: String = NSUserName()) async -> Data? {
        await output(URL(fileURLWithPath: "/usr/bin/security"),
                     ["find-generic-password", "-a", account, "-w", "-s", service], timeout: 3)
    }
}
