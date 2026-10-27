import Foundation

enum T3ProviderImporter {
    static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".t3/userdata/settings.json")
    }

    static func profiles(from data: Data) throws -> [ProviderProfile] {
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        let profiles = settings.providerInstances.compactMap { id, entry -> ProviderProfile? in
            let kind: ProviderKind
            switch entry.driver {
            case "codex": kind = .codex
            case "claudeAgent", "claude": kind = .claude
            default: return nil
            }
            let name = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            var profile = ProviderProfile(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? kind.title, kind: kind)
            profile.t3InstanceID = id
            profile.accentHex = entry.accentColor
            profile.isEnabled = entry.enabled ?? true
            let config = entry.config
            profile.configurationDirectory = kind == .codex
                ? config?.shadowHomePath ?? config?.homePath ?? ""
                : config?.homePath ?? ""
            let binary = config?.binaryPath ?? ""
            profile.executablePath = ["codex", "claude"].contains(binary) ? "" : binary
            return profile
        }
        for profile in profiles {
            for path in [profile.configurationDirectory, profile.executablePath] where !path.isEmpty {
                guard path.hasPrefix("/") || path.hasPrefix("~/") else { throw ProviderSettingsError.relativePath }
            }
        }
        guard Set(profiles.map { "\($0.kind.rawValue):\($0.resolvedDirectory)" }).count == profiles.count else {
            throw ProviderSettingsError.duplicateAccount
        }
        return profiles.sorted {
            if $0.isEnabled != $1.isEnabled { return $0.isEnabled }
            if $0.kind != $1.kind { return $0.kind == .codex }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func merge(_ imported: [ProviderProfile], into existing: [ProviderProfile]) -> [ProviderProfile] {
        var remaining = existing
        let merged = imported.map { imported in
            var profile = imported
            let index = remaining.firstIndex { $0.t3InstanceID == imported.t3InstanceID && imported.t3InstanceID != nil }
                ?? remaining.firstIndex { $0.kind == imported.kind && $0.resolvedDirectory == imported.resolvedDirectory }
            if let index {
                let old = remaining.remove(at: index)
                profile.id = old.id
                profile.legacyDirectory = old.legacyDirectory
                if old.storageID == ProviderProfile.legacyID, old.resolvedDirectory == profile.resolvedDirectory {
                    profile.legacyDirectory = old.resolvedDirectory
                }
            }
            return profile
        }
        return merged + remaining
    }

    private struct Settings: Decodable {
        let providerInstances: [String: Entry]
    }

    private struct Entry: Decodable {
        let driver: String
        let displayName: String?
        let accentColor: String?
        let enabled: Bool?
        let config: Config?
    }

    private struct Config: Decodable {
        let shadowHomePath: String?
        let homePath: String?
        let binaryPath: String?
    }
}
