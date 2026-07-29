import Foundation

@MainActor
final class CodexExecutableLocator {
    private enum Keys {
        static let selectedExecutable = "selectedCodexExecutable"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    var selectedURL: URL? {
        guard let path = defaults.string(forKey: Keys.selectedExecutable) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        return isValidExecutable(url) ? url : nil
    }

    func resolve() -> URL? {
        if let selectedURL {
            return selectedURL
        }

        for candidate in candidates() where isValidExecutable(candidate) {
            return candidate
        }
        return nil
    }

    func select(_ url: URL) throws {
        guard isValidExecutable(url), reportsCodexVersion(url) else {
            throw CodexExecutableError.notExecutable
        }
        defaults.set(url.path, forKey: Keys.selectedExecutable)
    }

    func clearSelection() {
        defaults.removeObject(forKey: Keys.selectedExecutable)
    }

    private func candidates() -> [URL] {
        var paths: [String] = []

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        paths.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
        ])

        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
    }

    private func isValidExecutable(_ url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    private func reportsCodexVersion(_ url: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let version = String(decoding: data, as: UTF8.self).lowercased()
        return process.terminationStatus == 0 && version.contains("codex")
    }
}

enum CodexExecutableError: LocalizedError {
    case notExecutable

    var errorDescription: String? {
        "The selected file does not respond correctly to “codex --version”."
    }
}
