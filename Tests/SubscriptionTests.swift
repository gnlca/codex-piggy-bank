import Foundation
import Testing
@testable import TokensPiggyBankCore

struct SubscriptionTests {
    private let now = Date(timeIntervalSince1970: 1_793_100_000)

    @Test func averagesAccountsEquallyRegardlessOfPlan() {
        let small = account(remaining: 80, plan: "prolite")
        let large = account(remaining: 20, plan: "promax")
        let result = UsageSummary(accounts: [small, large])
        #expect(result.remainingPercent == 50)
        #expect(result.includedCount == 2)
        #expect(result.window?.remainingPercent == 50)
    }

    @Test func excludesPausedStaleMissingAndNonWeeklyLimits() {
        let valid = account(remaining: 60)
        var pausedProfile = ProviderProfile(name: "Paused", kind: .codex)
        pausedProfile.isEnabled = false
        let paused = UsageSummary.Account(profile: pausedProfile, snapshot: snapshot(remaining: 0))
        var stale = account(remaining: 0)
        stale.isStale = true
        let missing = UsageSummary.Account(profile: ProviderProfile(name: "Missing", kind: .claude), snapshot: nil)
        let modelOnly = UsageSummary.Account(profile: valid.profile, snapshot: UsageSnapshot(
            fetchedAt: now, planType: "prolite", windows: [
                UsageWindow(usedPercent: 100, windowDurationMinutes: 10_080, resetsAt: nil, source: .model),
                UsageWindow(usedPercent: 100, windowDurationMinutes: 300, resetsAt: nil, source: .primary),
            ], individualLimit: nil, resetSummary: nil))
        let result = UsageSummary(accounts: [valid, paused, stale, missing, modelOnly])
        #expect(result.remainingPercent == 60)
        #expect(result.includedCount == 1)
        #expect(result.totalCount == 4)
        #expect(result.unavailableCount == 3)
        #expect(UsageSummary(accounts: [stale, missing]).remainingPercent == nil)
        #expect(UsageSummary(accounts: []).remainingPercent == nil)
    }

    @Test func newestSubscriptionReportCountsOnceAndSeparateWorkspacesRemainSeparate() {
        let profile = ProviderProfile(name: "Work", kind: .claude)
        let shared = snapshot(remaining: 80, date: now.addingTimeInterval(-60), identity: "account:organization-a")
        let fresh = snapshot(remaining: 40, identity: "account:organization-a")
        let other = snapshot(remaining: 20, identity: "account:organization-b")
        let result = UsageSummary(accounts: [
            .init(profile: profile, snapshot: shared),
            .init(profile: profile, snapshot: fresh),
            .init(profile: profile, snapshot: other),
        ])
        #expect(result.remainingPercent == 30)
        #expect(result.includedCount == 2)
        #expect(result.duplicateCount == 1)
        #expect(result.unavailableCount == 0)
    }

    @Test func personalAccountsCanBeDeduplicatedWithoutAProviderAccountID() {
        let first = ProviderProfile(name: "Personal", kind: .codex)
        let second = ProviderProfile(name: "Work", kind: .codex)
        var snapshot = snapshot(remaining: 75, plan: "pro")
        snapshot.accountLabel = "person@example.com"
        let result = UsageSummary(accounts: [
            .init(profile: first, snapshot: snapshot), .init(profile: second, snapshot: snapshot),
        ])
        #expect(result.remainingPercent == 75)
        #expect(result.includedCount == 1)
        #expect(result.duplicateCount == 1)
        #expect(result.unavailableCount == 0)
    }

    @Test func unknownPlansAreIncludedAndTheFinalMeanIsRounded() {
        let result = UsageSummary(accounts: [account(remaining: 80, plan: "unknown"), account(remaining: 21)])
        #expect(result.remainingPercent == 51)
        #expect(result.includedCount == 2)
    }

    @Test func identifiesPlanNamesAndClaudeTiers() {
        let claude = ProviderProfile(name: "Claude", kind: .claude)
        var max = snapshot(remaining: 50, plan: "max")
        #expect(PlanCapacity(profile: claude, snapshot: max).title == "Max")
        max.planTier = "default_claude_max_5x"
        #expect(PlanCapacity(profile: claude, snapshot: max).title == "Max 5×")
        max.planTier = "default_claude_max_20x"
        #expect(PlanCapacity(profile: claude, snapshot: max).title == "Max 20×")
        var downgraded = snapshot(remaining: 50, plan: "pro")
        downgraded.planTier = max.planTier
        #expect(PlanCapacity(profile: claude, snapshot: downgraded).title == "Pro")
        let codex = ProviderProfile(name: "Codex", kind: .codex)
        #expect(PlanCapacity(profile: codex, snapshot: snapshot(remaining: 50, plan: "pro")).title == "Pro 200")
        #expect(PlanCapacity(profile: codex, snapshot: snapshot(remaining: 50)).title == "Pro 100 · 5×")
    }

    @Test func metadataCannotAssignAnotherLoginsTier() {
        let data = Data(#"{"oauthAccount":{"emailAddress":"person@example.com","accountUuid":"a","organizationUuid":"o","organizationRateLimitTier":"default_claude_max_20x"}}"#.utf8)
        #expect(ClaudeAccountMetadata.decode(data, email: "other@example.com") == nil)
        #expect(ClaudeAccountMetadata.decode(data, email: nil) == nil)
        let account = ClaudeAccountMetadata.decode(data, email: "PERSON@example.com")
        #expect(account?.organizationRateLimitTier == "default_claude_max_20x")
        #expect(account?.identity == "a:o")
    }

    @Test func claudeCreditsRequireLiveUsableGrantAndConfirmedNextGrant() throws {
        let data = Data(#"""
        {"rate_limits":{"cedar_ember":{"eligible":true,"next_grant_id":"live","grants":[
          {"id":"live","resets_left":2,"ends_at":"2030-01-01T00:00:00Z","usable_now":true},
          {"id":"paused","resets_left":10,"paused":true,"usable_now":true},
          {"id":"expired","resets_left":10,"ends_at":"2020-01-01T00:00:00Z","usable_now":true},
          {"id":"unusable","resets_left":10,"usable_now":false},
          {"id":"bad-date","resets_left":10,"ends_at":"invalid","usable_now":true},
          {"id":"missing-date","resets_left":1,"usable_now":true},
          {"id":"negative","resets_left":-1,"usable_now":true},
          {"id":"boolean","resets_left":true,"usable_now":true}
        ]}}}
        """#.utf8)
        let summary = try #require(ClaudeUsageClient.decodeResetCredits(data, now: now))
        #expect(summary.availableCount == 3)
        #expect(summary.missingDetailCount == 0)
        #expect(summary.credits?.count == 2)
        #expect(summary.credits?.first?.grantedAt == nil)
        #expect(summary.credits?.first?.id == "claude-live")
        let missingNext = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"next_grant_id\":\"live\"", with: "\"next_grant_id\":\"expired\"").utf8)
        #expect(ClaudeUsageClient.decodeResetCredits(missingNext, now: now)?.availableCount == 0)
    }

    private func account(remaining: Int, plan: String = "prolite") -> UsageSummary.Account {
        .init(profile: ProviderProfile(name: "Account", kind: .codex), snapshot: snapshot(remaining: remaining, plan: plan))
    }

    private func snapshot(remaining: Int, plan: String = "prolite", date: Date? = nil, identity: String? = nil) -> UsageSnapshot {
        UsageSnapshot(fetchedAt: date ?? now, planType: plan, windows: [
            UsageWindow(usedPercent: 100 - remaining, windowDurationMinutes: 10_080, resetsAt: nil, source: .secondary)
        ], individualLimit: nil, resetSummary: nil, accountID: identity)
    }
}

@Suite @MainActor
struct T3ImportTests {
    private let fixture = Data(#"""
    {"providerInstances":{
      "codex_work":{"driver":"codex","displayName":"Work","accentColor":"#ea580c","enabled":true,"config":{"shadowHomePath":"/tmp/tokens-test-work"}},
      "codex":{"driver":"codex","displayName":"Personal","enabled":false},
      "claudeAgent":{"driver":"claudeAgent","displayName":"Claude Personal","enabled":true,"config":{"homePath":"","binaryPath":"claude"}},
      "claude_team":{"driver":"claudeAgent","displayName":"Claude Team","enabled":false,"config":{"homePath":"/tmp/tokens-test-team"}},
      "other":{"driver":"other","enabled":true}
    }}
    """#.utf8)

    @Test func importIsIdempotentPreservesDefaultsAndUsesT3Homes() throws {
        let imported = try T3ProviderImporter.profiles(from: fixture)
        let codex = ProviderProfile(id: ProviderProfile.legacyID, name: "Codex", kind: .codex, t3InstanceID: "codex")
        let claude = ProviderProfile(id: "default-claude", name: "Claude", kind: .claude)
        let merged = T3ProviderImporter.merge(imported, into: [codex, claude])
        #expect(merged.count == 4)
        let personal = try #require(merged.first { $0.t3InstanceID == "codex" })
        #expect(personal.id == ProviderProfile.legacyID)
        #expect(personal.storageID == ProviderProfile.legacyID)
        #expect(!personal.isEnabled)
        #expect(personal.environment["CODEX_HOME"] == NSHomeDirectory() + "/.codex")
        #expect(merged.first { $0.t3InstanceID == "codex_work" }?.environment["CODEX_HOME"] == "/tmp/tokens-test-work")
        let defaultClaude = try #require(merged.first { $0.t3InstanceID == "claudeAgent" })
        #expect(defaultClaude.id == "default-claude")
        #expect(defaultClaude.executablePath.isEmpty)
        #expect(defaultClaude.environment["CLAUDE_CONFIG_DIR"] == nil)
        #expect(defaultClaude.environment["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        #expect(T3ProviderImporter.merge(try T3ProviderImporter.profiles(from: fixture), into: merged) == merged)
    }

    @Test func importingAnExistingCustomHomeKeepsItsLegacyRemindersAndCache() {
        let old = ProviderProfile(id: ProviderProfile.legacyID, name: "Codex", kind: .codex)
        var imported = ProviderProfile(name: "Existing account", kind: .codex,
                                       configurationDirectory: old.resolvedDirectory, t3InstanceID: "existing")
        let merged = T3ProviderImporter.merge([imported], into: [old])
        #expect(merged.count == 1)
        #expect(merged[0].storageID == ProviderProfile.legacyID)
        imported = merged[0]
        imported.configurationDirectory = "/tmp/different-account"
        #expect(imported.storageID != ProviderProfile.legacyID)
    }

    @Test func persistsImportAndAllSelectionWithoutTouchingSource() async throws {
        let suite = "TokensPiggyBank.ImportTest.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: file) }
        try fixture.write(to: file)
        let store = ProviderStore(defaults: defaults, storeFactory: ProviderTests.makeStore)
        var personal = try #require(store.profiles.first { $0.kind == .codex })
        personal.t3InstanceID = "codex"
        try await store.save(personal)
        #expect(try await store.importT3(from: file) == 4)
        #expect(store.enabledProfiles.count == 2)
        #expect(store.selectedProfileID == nil)
        #expect(try Data(contentsOf: file) == fixture)
        let reopened = ProviderStore(defaults: defaults, storeFactory: ProviderTests.makeStore)
        #expect(reopened.profiles == store.profiles)
        #expect(reopened.selectedProfileID == nil)
    }

    @Test func mixedResetRowsSortByExpiryAndRetainAccountIdentity() async throws {
        let same = ResetCredit(title: "Full reset", description: nil, grantedAt: Date(), expiresAt: Date().addingTimeInterval(3_600))
        let later = ResetCredit(title: "Full reset", description: nil, grantedAt: Date(), expiresAt: Date().addingTimeInterval(7_200))
        let expired = ResetCredit(title: "Full reset", description: nil, grantedAt: Date(), expiresAt: Date().addingTimeInterval(-10))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let stores = [ProviderKind.codex, .claude].map { kind in
            let profile = ProviderProfile(name: kind.title, kind: kind)
            return ResetStore(profile: profile, client: ResetFixture(credits: [later, expired, same]),
                              cache: SnapshotCache(fileURL: root.appendingPathComponent(profile.id)),
                              notifications: FakeNotifications(), calendar: FakeCalendar())
        }
        for store in stores { await store.refresh() }
        let bank = BankResets(stores: stores)
        #expect(bank.count == 4)
        #expect(bank.entries.count == 4)
        #expect(Set(bank.entries.map(\.id)).count == 4)
        #expect(bank.entries.first?.credit.expiresAt == same.expiresAt)
        #expect(BankResets(stores: [stores[0]]).count == 2)
    }
}

private struct ResetFixture: UsageReading {
    let credits: [ResetCredit]
    func readSnapshot(for profile: ProviderProfile) async throws -> UsageSnapshot {
        UsageSnapshot(fetchedAt: Date(), planType: "prolite", windows: [], individualLimit: nil,
                      resetSummary: ResetSummary(availableCount: credits.count, credits: credits))
    }
}
