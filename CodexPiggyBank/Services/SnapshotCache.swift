import Foundation

actor SnapshotCache {
    private let fileURL: URL
    private let legacyFileURL: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(profileID: String = ProviderProfile.legacyID, fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL(profileID: profileID)
        legacyFileURL = fileURL == nil && profileID == ProviderProfile.legacyID
            ? Self.supportDirectory.appendingPathComponent("Codex Piggy Bank/snapshot.json") : nil
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> UsageSnapshot? {
        guard let data = (try? Data(contentsOf: fileURL)) ?? legacyFileURL.flatMap({ try? Data(contentsOf: $0) }) else {
            return nil
        }
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
    }

    private static func defaultFileURL(profileID: String) -> URL {
        supportDirectory
            .appendingPathComponent("Tokens Piggy Bank/Snapshots", isDirectory: true)
            .appendingPathComponent("\(profileID).json")
    }
}
