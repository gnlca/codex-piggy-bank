import Foundation
import Observation

@MainActor
@Observable
final class ProviderStore {
    private(set) var profiles: [ProviderProfile] = []
    private(set) var selectedProfileID: String?
    private(set) var stores: [String: ResetStore] = [:]
    private(set) var errorMessage: String?
    private(set) var isUpdating = false
    private(set) var usesCompactProviderCards: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storeFactory: @MainActor (ProviderProfile) -> ResetStore
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored var onStatusChange: (() -> Void)?

    init(
        defaults: UserDefaults = .standard,
        storeFactory: @escaping @MainActor (ProviderProfile) -> ResetStore = ResetStore.live
    ) {
        self.defaults = defaults
        self.storeFactory = storeFactory
        usesCompactProviderCards = defaults.object(forKey: "compactProviderCards") as? Bool ?? true
        if let data = defaults.data(forKey: "providerConfiguration") {
            do {
                let configuration = try JSONDecoder().decode(Configuration.self, from: data)
                guard Set(configuration.profiles.map(\.id)).count == configuration.profiles.count else {
                    throw ProviderSettingsError.invalidConfiguration
                }
                profiles = configuration.profiles
                selectedProfileID = configuration.selectedProfileID
            } catch {
                errorMessage = "Saved providers could not be read. Add a provider to create a new configuration."
            }
        } else {
            var codex = ProviderProfile(id: ProviderProfile.legacyID, name: "Codex", kind: .codex)
            codex.executablePath = defaults.string(forKey: "selectedCodexExecutable") ?? ""
            profiles = [codex]
            let claude = ProviderProfile(id: "default-claude", name: "Claude", kind: .claude)
            if ProviderExecutableLocator.resolve(claude) != nil { profiles.append(claude) }
            persist()
        }
        for profile in profiles { stores[profile.id] = makeStore(profile) }
        reconcileSelection()
    }

    var enabledProfiles: [ProviderProfile] { profiles.filter(\.isEnabled) }
    var selectedStore: ResetStore? { selectedProfileID.flatMap { stores[$0] } }
    var enabledStores: [ResetStore] { enabledProfiles.compactMap { stores[$0.id] } }
    var isRefreshing: Bool { enabledStores.contains(where: \.isRefreshing) }
    var usageSummary: UsageSummary {
        UsageSummary(accounts: enabledStores.map { .init(profile: $0.profile, snapshot: $0.snapshot, isStale: $0.isStale) })
    }

    func setCompactProviderCards(_ compact: Bool) {
        usesCompactProviderCards = compact
        defaults.set(compact, forKey: "compactProviderCards")
        onStatusChange?()
    }

    func setAccentColor(_ hex: String?, for profileID: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].accentHex = hex
        stores[profileID]?.setAccentColor(hex)
        persist()
        onStatusChange?()
    }

    func select(_ id: String?) {
        guard id == nil || enabledProfiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        persist()
        onStatusChange?()
    }

    func rename(_ profileID: String, to proposedName: String) async throws {
        guard !isUpdating else { throw ProviderSettingsError.updateInProgress }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProviderSettingsError.missingName }
        guard let index = profiles.firstIndex(where: { $0.id == profileID }), profiles[index].name != name else { return }
        isUpdating = true
        defer { isUpdating = false }
        profiles[index].name = name
        persist()
        await stores[profileID]?.rename(to: name)
        onStatusChange?()
    }

    func save(_ proposed: ProviderProfile) async throws {
        guard !isUpdating else { throw ProviderSettingsError.updateInProgress }
        isUpdating = true
        defer { isUpdating = false }
        var profile = proposed
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.configurationDirectory = profile.configurationDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.executablePath = profile.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty else { throw ProviderSettingsError.missingName }
        for path in [profile.configurationDirectory, profile.executablePath] where !path.isEmpty {
            guard path.hasPrefix("/") || path.hasPrefix("~/") else { throw ProviderSettingsError.relativePath }
        }
        guard !profiles.contains(where: {
            $0.id != profile.id && $0.kind == profile.kind && $0.resolvedDirectory == profile.resolvedDirectory
        }) else { throw ProviderSettingsError.duplicateAccount }

        if let oldStore = stores[profile.id] {
            oldStore.stop()
            oldStore.onStatusChange = nil
            if oldStore.profile.storageID != profile.storageID || !profile.isEnabled {
                await oldStore.clearNotifications()
            }
        }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        let store = makeStore(profile)
        stores[profile.id] = store
        if isStarted { store.start() }
        reconcileSelection()
        persist()
        errorMessage = nil
        onStatusChange?()
    }

    func remove(_ profile: ProviderProfile) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let store = stores.removeValue(forKey: profile.id)
        store?.stop()
        store?.onStatusChange = nil
        profiles.removeAll { $0.id == profile.id }
        reconcileSelection()
        persist()
        onStatusChange?()
        await store?.clearNotifications()
    }

    @discardableResult
    func importT3(from url: URL = T3ProviderImporter.settingsURL) async throws -> Int {
        guard !isUpdating else { throw ProviderSettingsError.updateInProgress }
        let imported = try T3ProviderImporter.profiles(from: Data(contentsOf: url))
        guard !imported.isEmpty else { throw ProviderSettingsError.noT3Providers }
        let merged = T3ProviderImporter.merge(imported, into: profiles)
        guard Set(merged.map { "\($0.kind.rawValue):\($0.resolvedDirectory)" }).count == merged.count else {
            throw ProviderSettingsError.duplicateAccount
        }
        isUpdating = true
        defer { isUpdating = false }
        for profile in merged {
            if let old = stores[profile.id] {
                if old.profile == profile { continue }
                old.stop()
                old.onStatusChange = nil
                if old.profile.storageID != profile.storageID || !profile.isEnabled {
                    await old.clearNotifications()
                }
            }
            let store = makeStore(profile)
            stores[profile.id] = store
            if isStarted { store.start() }
        }
        profiles = merged
        selectedProfileID = nil
        persist()
        errorMessage = nil
        onStatusChange?()
        return imported.count
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        for store in stores.values { store.start() }
    }

    func stop() {
        isStarted = false
        for store in stores.values { store.stop() }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for store in stores.values where store.profile.isEnabled {
                group.addTask { await store.refresh() }
            }
        }
    }

    func timeZoneDidChange() {
        for store in stores.values { store.timeZoneDidChange() }
    }

    private func makeStore(_ profile: ProviderProfile) -> ResetStore {
        let store = storeFactory(profile)
        store.onStatusChange = { [weak self] in self?.onStatusChange?() }
        return store
    }

    private func reconcileSelection() {
        if selectedProfileID != nil, !enabledProfiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = nil
        }
    }

    private func persist() {
        let configuration = Configuration(profiles: profiles, selectedProfileID: selectedProfileID)
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: "providerConfiguration")
    }

    private struct Configuration: Codable {
        let profiles: [ProviderProfile]
        let selectedProfileID: String?
    }
}

enum ProviderSettingsError: LocalizedError {
    case missingName
    case relativePath
    case duplicateAccount
    case invalidConfiguration
    case updateInProgress
    case noT3Providers

    var errorDescription: String? {
        switch self {
        case .missingName: "Enter a name for this provider."
        case .relativePath: "Use an absolute path or a path starting with ~/."
        case .duplicateAccount: "This account folder is already configured. Choose a separate folder for another subscription."
        case .invalidConfiguration: "The saved provider configuration is invalid."
        case .updateInProgress: "Wait for the current provider change to finish."
        case .noT3Providers: "No Codex or Claude providers were found in T3 Code settings."
        }
    }
}
