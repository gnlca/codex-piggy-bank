import CryptoKit
import Foundation

/// Reads Claude's banked resets the way Claude Code does: `get_usage` omits them, so this asks the usage
/// endpoint for `cedar_ember` with the profile's existing login. The token is used for this request only.
struct ClaudeResetCreditsReader: Sendable {
    var timeout: TimeInterval = 10

    func readBlock(environment: [String: String], version: String?) async -> [String: Any]? {
        guard let token = await Self.accessToken(environment: environment),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/\(version ?? "unknown") (external, cli)", forHTTPHeaderField: "user-agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["cedar_ember"] as? [String: Any]
    }

    /// Claude Code keeps a custom `CLAUDE_CONFIG_DIR` login under a service suffixed with the path's hash.
    static func keychainService(configDirectory: String?) -> String {
        guard let configDirectory else { return "Claude Code-credentials" }
        let digest = SHA256.hash(data: Data(configDirectory.utf8))
        return "Claude Code-credentials-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static func accessToken(fromCredentials data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (root["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func accessToken(environment: [String: String]) async -> String? {
        let configDirectory = environment["CLAUDE_CONFIG_DIR"]
        if let data = await keychainCredentials(service: keychainService(configDirectory: configDirectory)),
           let token = accessToken(fromCredentials: data) {
            return token
        }
        let directory = configDirectory ?? "\(NSHomeDirectory())/.claude"
        let file = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath).appendingPathComponent(".credentials.json")
        return (try? Data(contentsOf: file)).flatMap(accessToken(fromCredentials:))
    }

    /// Uses `security`, as Claude Code does, so the login item's existing Keychain access applies.
    private static func keychainCredentials(service: String) async -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", NSUserName(), "-w", "-s", service]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
            }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if process.isRunning { process.terminate() } }
        }
    }
}
