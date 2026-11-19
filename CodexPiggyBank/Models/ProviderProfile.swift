import CryptoKit
import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case antigravity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .antigravity: "Antigravity"
        }
    }

    var configurationVariable: String {
        switch self {
        case .codex: "CODEX_HOME"
        case .claude: "CLAUDE_CONFIG_DIR"
        case .antigravity: "GEMINI_HOME"
        }
    }

    var defaultDirectory: String {
        switch self {
        case .codex: "~/.codex"
        case .claude: "~/.claude"
        case .antigravity: "~/.gemini"
        }
    }

    var executableName: String { self == .antigravity ? "agy" : rawValue }
}

struct ProviderProfile: Codable, Equatable, Identifiable, Sendable {
    static let legacyID = "default-codex"

    var id: String = UUID().uuidString
    var name: String
    var kind: ProviderKind
    var configurationDirectory = ""
    var executablePath = ""
    var isEnabled = true
    var accentHex: String?
    var t3InstanceID: String?
    var legacyDirectory: String?

    var initials: String? {
        guard name.localizedCaseInsensitiveCompare(kind.title) != .orderedSame else { return nil }
        let words = name.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
        guard let first = words.first else { return nil }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var resolvedDirectory: String {
        let configured = configurationDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPath = t3InstanceID == nil
            ? ProcessInfo.processInfo.environment[kind.configurationVariable] ?? kind.defaultDirectory
            : kind.defaultDirectory
        let path = configured.isEmpty ? defaultPath : configured
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    var storageID: String {
        if id == Self.legacyID, kind == .codex,
           configurationDirectory.isEmpty || legacyDirectory == resolvedDirectory {
            return Self.legacyID
        }
        let digest = SHA256.hash(data: Data("\(kind.rawValue):\(resolvedDirectory)".utf8))
        let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(id)-\(suffix)"
    }

    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Leave HOME intact: Claude uses the system Keychain even for custom accounts.
        if !configurationDirectory.isEmpty {
            environment[kind.configurationVariable] = resolvedDirectory
        } else if t3InstanceID != nil {
            // A default T3 account must not inherit the running harness's custom account.
            environment[kind.configurationVariable] = kind == .codex ? resolvedDirectory : nil
        }
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        return environment
    }

    static func new(kind: ProviderKind) -> ProviderProfile {
        var profile = ProviderProfile(name: kind.title, kind: kind)
        // Antigravity keeps one Google sign-in in the Keychain, whatever its folder.
        if kind != .antigravity {
            profile.configurationDirectory = "~/Library/Application Support/Tokens Piggy Bank/Accounts/\(profile.id)"
        }
        return profile
    }
}
