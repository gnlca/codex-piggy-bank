import Foundation
import Testing
@testable import TokensPiggyBankCore

@Suite @MainActor
struct ProviderTests {
    @Test func profileStorageFollowsAccountIdentity() {
        var profile = ProviderProfile(id: ProviderProfile.legacyID, name: "Work", kind: .codex)
        #expect(profile.storageID == ProviderProfile.legacyID)
        profile.configurationDirectory = "/tmp/tokens-test/work"
        let workID = profile.storageID
        profile.name = "Renamed"
        #expect(profile.storageID == workID)
        profile.configurationDirectory = "/tmp/tokens-test/personal"
        #expect(profile.storageID != workID)
        let codexID = profile.storageID
        profile.kind = .claude
        #expect(profile.storageID != codexID)
    }

    @Test func environmentsKeepSystemHomeAndDefaultClaudeLogin() {
        let original = ProcessInfo.processInfo.environment
        var profile = ProviderProfile(name: "Claude", kind: .claude)
        #expect(profile.environment["HOME"] == original["HOME"])
        #expect(profile.environment["CLAUDE_CONFIG_DIR"] == original["CLAUDE_CONFIG_DIR"])
        profile.configurationDirectory = "~/Claude Personal"
        #expect(profile.environment["CLAUDE_CONFIG_DIR"] == profile.resolvedDirectory)
        #expect(profile.environment["HOME"] == original["HOME"])
    }

    @Test func migratesPersistsSelectsAndRemovesProfiles() async throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/tmp/old-codex", forKey: "selectedCodexExecutable")
        let store = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(store.profiles.first?.id == ProviderProfile.legacyID)
        #expect(store.profiles.first?.executablePath == "/tmp/old-codex")

        var personal = ProviderProfile.new(kind: .claude)
        personal.name = "Personal"
        try await store.save(personal)
        store.select(personal.id)
        #expect(store.selectedStore?.profile.name == "Personal")
        let reopened = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(reopened.selectedProfileID == personal.id)
        #expect(reopened.profiles.contains(personal))

        personal.name = "Personal Max"
        try await reopened.save(personal)
        #expect(reopened.selectedStore?.profile.name == "Personal Max")
        personal.isEnabled = false
        try await reopened.save(personal)
        #expect(reopened.selectedProfileID != personal.id)
        await reopened.remove(personal)
        #expect(!reopened.profiles.contains(where: { $0.id == personal.id }))
        for profile in reopened.profiles { await reopened.remove(profile) }
        #expect(reopened.selectedStore == nil)
        let empty = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(empty.profiles.isEmpty)
    }

    @Test func rejectsDuplicateAccountsAndRelativePaths() async throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        var profile = ProviderProfile.new(kind: .codex)
        profile.configurationDirectory = "relative/path"
        await #expect(throws: ProviderSettingsError.self) { try await store.save(profile) }
        profile.configurationDirectory = ""
        await #expect(throws: ProviderSettingsError.self) { try await store.save(profile) }
        profile.configurationDirectory = "/tmp/new-account"
        profile.name = "  "
        await #expect(throws: ProviderSettingsError.self) { try await store.save(profile) }
    }

    @Test func ownsNewAccountsAndPersistsTheirColorsAndAppearance() async throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(store.usesCompactProviderCards)
        var profile = ProviderProfile.new(kind: .claude)
        #expect(profile.configurationDirectory.hasPrefix("~/Library/Application Support/Tokens Piggy Bank/Accounts/"))
        #expect(profile.t3InstanceID == nil)
        profile.name = "Independent account"
        profile.accentHex = "#AB48CD"
        try await store.save(profile)
        store.setAccentColor("#19A388", for: profile.id)
        store.setCompactProviderCards(false)
        let reopened = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(reopened.profiles.first { $0.id == profile.id }?.accentHex == "#19A388")
        #expect(!reopened.usesCompactProviderCards)
        reopened.setAccentColor(nil, for: profile.id)
        reopened.setCompactProviderCards(true)
        let restored = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(restored.profiles.first { $0.id == profile.id }?.accentHex == nil)
        #expect(restored.usesCompactProviderCards)
    }

    @Test func changingColorPreservesUsageAndAnInFlightRefresh() async throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let reader = SuspendedReader()
        let store = ProviderStore(defaults: defaults) { profile in
            ResetStore(profile: profile, client: reader, cache: SnapshotCache(fileURL: directory.appendingPathComponent(profile.id)),
                       notifications: FakeNotifications(), calendar: FakeCalendar())
        }
        let profile = try #require(store.profiles.first)
        let usage = try #require(store.stores[profile.id])
        let refresh = Task { await usage.refresh() }
        await reader.waitUntilStarted()
        store.setAccentColor("#4499FF", for: profile.id)
        #expect(store.stores[profile.id] === usage)
        #expect(usage.isRefreshing)
        await reader.complete()
        await refresh.value
        let snapshot = try #require(usage.snapshot)
        store.setAccentColor("#AA22CC", for: profile.id)
        #expect(usage.snapshot == snapshot)
        #expect(usage.profile.accentHex == "#AA22CC")
        #expect(store.profiles.first?.accentHex == "#AA22CC")
    }

    @Test func legacyPlanWeightsDoNotPreventLoadingAccounts() throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(##"{"profiles":[{"id":"old","name":"Old account","kind":"claude","configurationDirectory":"/tmp/legacy-claude","executablePath":"","isEnabled":true,"weightOverride":20,"accentHex":"#123456"}]}"##.utf8), forKey: "providerConfiguration")
        let store = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(store.errorMessage == nil)
        #expect(store.profiles.first?.name == "Old account")
        #expect(store.profiles.first?.accentHex == "#123456")
    }

    @Test func renamingKeepsTheAccountAndItsInFlightUsageAndUpdatesReminderNames() async throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let reader = SuspendedReader()
        let notifications = FakeNotifications()
        let calendar = FakeCalendar()
        let store = ProviderStore(defaults: defaults) { profile in
            ResetStore(profile: profile, client: reader, cache: SnapshotCache(fileURL: directory.appendingPathComponent(profile.id)),
                       notifications: notifications, calendar: calendar)
        }
        let profile = try #require(store.profiles.first)
        let usage = try #require(store.stores[profile.id])
        store.select(profile.id)
        let refresh = Task { await usage.refresh() }
        await reader.waitUntilStarted()
        try await store.rename(profile.id, to: "  Personal account  ")
        #expect(store.stores[profile.id] === usage)
        #expect(usage.profile.name == "Personal account")
        #expect(usage.profile.storageID == profile.storageID)
        #expect(usage.isRefreshing)
        #expect(await notifications.profileName == "Personal account")
        #expect(await calendar.profileName == "Personal account")
        await reader.complete()
        await refresh.value
        #expect(usage.snapshot != nil)
        let reopened = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(reopened.selectedProfileID == profile.id)
        #expect(reopened.selectedStore?.profile.name == "Personal account")
        await #expect(throws: ProviderSettingsError.self) { try await store.rename(profile.id, to: "  ") }
        #expect(usage.profile.name == "Personal account")
    }

    @Test func corruptConfigurationIsNotSilentlyOverwritten() throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("broken".utf8)
        defaults.set(data, forKey: "providerConfiguration")
        let store = ProviderStore(defaults: defaults, storeFactory: Self.makeStore)
        #expect(store.errorMessage != nil)
        #expect(defaults.data(forKey: "providerConfiguration") == data)
    }

    @Test func signInQuotesPathsAndUsesTheSameAccountEnvironment() {
        var profile = ProviderProfile(name: "Personal", kind: .claude)
        let executable = URL(fileURLWithPath: "/tmp/Claude CLI/claude")
        let defaultCommand = ProviderLogin.loginCommand(profile, executable: executable)
        #expect(!defaultCommand.contains("CLAUDE_CONFIG_DIR="))
        profile.configurationDirectory = "/tmp/John's $(echo bad) account"
        let command = ProviderLogin.loginCommand(profile, executable: executable)
        #expect(command.contains("CLAUDE_CONFIG_DIR='/tmp/John'\\''s $(echo bad) account'"))
        #expect(command.hasSuffix("'/tmp/Claude CLI/claude' auth login"))
    }

    @Test func stoppingRefreshDiscardsLateResults() async throws {
        let reader = SuspendedReader()
        let notifications = FakeNotifications()
        let profile = ProviderProfile(name: "Work", kind: .codex)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ResetStore(profile: profile, client: reader, cache: SnapshotCache(fileURL: cacheURL),
                               notifications: notifications, calendar: FakeCalendar())
        let refresh = Task { await store.refresh() }
        await reader.waitUntilStarted()
        store.stop()
        await reader.complete()
        await refresh.value
        #expect(store.snapshot == nil)
        #expect(store.errorMessage == nil)
        #expect(await notifications.reconciledKeys.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
    }

    static func makeStore(_ profile: ProviderProfile) -> ResetStore {
        ResetStore(profile: profile, client: SuspendedReader(),
                   cache: SnapshotCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                   notifications: FakeNotifications(), calendar: FakeCalendar())
    }
}

actor FakeNotifications: NotificationScheduling {
    var reconciledKeys: [Set<String>] = []
    var profileName: String?
    func renameProfile(to name: String) { profileName = name }
    func enabledKeys() -> Set<String> { [] }
    func toggle(for credit: ResetCredit, now: Date) -> Bool { true }
    func reconcile(validKeys: Set<String>) { reconciledKeys.append(validKeys) }
}

actor FakeCalendar: CalendarEventManaging {
    var profileName: String?
    func renameProfile(to name: String) { profileName = name }
    func createdKeys() -> Set<String> { [] }
    func toggleEvent(for credit: ResetCredit, now: Date) -> Bool { true }
}

actor SuspendedReader: UsageReading {
    private var continuation: CheckedContinuation<UsageSnapshot, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func readSnapshot(for profile: ProviderProfile) async throws -> UsageSnapshot {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func complete() {
        continuation?.resume(returning: UsageSnapshot(fetchedAt: Date(), planType: "pro", windows: [],
                                                     individualLimit: nil, resetSummary: nil))
        continuation = nil
    }
}
