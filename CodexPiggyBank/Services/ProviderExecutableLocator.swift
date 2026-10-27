import Foundation

enum ProviderExecutableLocator {
    static func resolve(_ profile: ProviderProfile) -> URL? {
        let selected = profile.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            let url = URL(fileURLWithPath: (selected as NSString).expandingTildeInPath)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }

        let paths = (profile.environment["PATH"] ?? "").split(separator: ":")
            .map { "\($0)/\(profile.kind.rawValue)" }
        let bundled = profile.kind == .codex ? ["/Applications/Codex.app/Contents/Resources/codex"] : []
        return (paths + bundled).first(where: FileManager.default.isExecutableFile(atPath:))
            .map { URL(fileURLWithPath: $0) }
    }
}
