import Foundation
import Testing
@testable import TokensPiggyBankCore

struct ReminderIsolationTests {
    @Test func identicalResetDatesNeverMatchAnotherAccount() {
        let work = ResetNotificationScope(profileID: "work")
        let personal = ResetNotificationScope(profileID: "personal")
        let legacy = ResetNotificationScope(profileID: ProviderProfile.legacyID)
        let creditID = "1781654400-1784246400"
        let identifiers = [work, personal, legacy].map { "\($0.identifier(for: creditID)).3600" }

        #expect(identifiers.compactMap(work.creditKey) == [creditID])
        #expect(identifiers.compactMap(personal.creditKey) == [creditID])
        #expect(identifiers.compactMap(legacy.creditKey) == [creditID])
        #expect(legacy.creditKey(from: "codex-piggy-bank.\(creditID)") == creditID)
        #expect(work.creditKey(from: "unrelated.notification.300") == nil)
    }

    @Test func calendarReferencesStayWithTheirAccount() async throws {
        let suite = "TokensPiggyBankTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["legacy-reset": "legacy-event"], forKey: "createdResetCalendarEventIdentifiers")
        defaults.set(["work-reset": "work-event"], forKey: "createdResetCalendarEventIdentifiers.work")
        let legacy = CalendarService(defaults: UserDefaults(suiteName: suite)!)
        let work = CalendarService(profileID: "work", defaults: UserDefaults(suiteName: suite)!)
        let personal = CalendarService(profileID: "personal", defaults: UserDefaults(suiteName: suite)!)
        #expect(await legacy.createdKeys() == ["legacy-reset"])
        #expect(await work.createdKeys() == ["work-reset"])
        #expect(await personal.createdKeys().isEmpty)
    }

    @Test @MainActor func calendarDenialIsVisibleAndCanBeRetried() async {
        let calendar = RetryCalendar()
        let profile = ProviderProfile(name: "Work", kind: .codex)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ResetStore(profile: profile, client: SuspendedReader(), cache: SnapshotCache(fileURL: cacheURL),
                               notifications: FakeNotifications(), calendar: calendar)
        let credit = ResetCredit(title: "Full reset", description: nil, grantedAt: nil,
                                  expiresAt: Date().addingTimeInterval(86_400))
        await store.toggleCalendarEvent(for: credit)
        #expect(store.calendarFailure?.needsAccess == true)
        #expect(store.calendarFailure?.message == ReminderError.calendarDenied.errorDescription)
        #expect(store.createdCalendarKeys.isEmpty)
        #expect(store.pendingActionKeys.isEmpty)
        #expect(store.errorMessage == nil)

        store.dismissCalendarFailure()
        #expect(store.calendarFailure == nil)
        await calendar.allowAccess()
        await store.toggleCalendarEvent(for: credit)
        #expect(store.calendarFailure == nil)
        #expect(store.createdCalendarKeys == [credit.id])
        #expect(store.pendingActionKeys.isEmpty)
    }
}

private actor RetryCalendar: CalendarEventManaging {
    private var isAllowed = false
    private var keys: Set<String> = []

    func allowAccess() { isAllowed = true }
    func createdKeys() -> Set<String> { keys }
    func toggleEvent(for credit: ResetCredit, now: Date) throws -> Bool {
        guard isAllowed else { throw ReminderError.calendarDenied }
        keys.insert(credit.id)
        return true
    }
}
