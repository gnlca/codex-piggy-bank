import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ResetStore {
    private(set) var profile: ProviderProfile
    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var isStale = false
    private(set) var errorMessage: String?
    private(set) var calendarFailure: CalendarFailure?
    private(set) var notificationEnabledKeys: Set<String> = []
    private(set) var createdCalendarKeys: Set<String> = []
    private(set) var pendingActionKeys: Set<String> = []
    private(set) var clock = Date()

    @ObservationIgnored private let client: any UsageReading
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let notifications: any NotificationScheduling
    @ObservationIgnored private let calendar: any CalendarEventManaging
    @ObservationIgnored private var requestTask: Task<UsageSnapshot, Error>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored var onStatusChange: (() -> Void)?

    init(
        profile: ProviderProfile,
        client: any UsageReading,
        cache: SnapshotCache,
        notifications: any NotificationScheduling,
        calendar: any CalendarEventManaging
    ) {
        self.profile = profile
        self.client = client
        self.cache = cache
        self.notifications = notifications
        self.calendar = calendar
    }

    static func live(profile: ProviderProfile) -> ResetStore {
        ResetStore(
            profile: profile,
            client: ProviderUsageClient(),
            cache: SnapshotCache(profileID: profile.storageID),
            notifications: NotificationService(profileID: profile.storageID, profileName: profile.name),
            calendar: CalendarService(profileID: profile.storageID, profileName: profile.name)
        )
    }

    var windows: [UsageWindow] {
        snapshot?.windows.sorted {
            ($0.windowDurationMinutes ?? .max) < ($1.windowDurationMinutes ?? .max)
        } ?? []
    }

    var resetCredits: [ResetCredit] {
        snapshot?.sortedResetCredits.filter { $0.count > 0 && ($0.expiresAt.map { $0 > clock } ?? true) } ?? []
    }

    var weeklyWindow: UsageWindow? {
        snapshot?.windows.first { $0.isWeekly && $0.source != .model }
    }

    var overviewWindows: [UsageWindow] {
        windows.filter { $0.source != .model && ($0.windowDurationMinutes == 300 || $0.isWeekly) }
    }

    var availableResetCount: Int {
        resetCredits.reduce(0) { $0 + $1.count } + missingResetDetailCount
    }

    var missingResetDetailCount: Int {
        snapshot?.resetSummary?.missingDetailCount ?? 0
    }

    var lastUpdatedText: String {
        snapshot.map { ExpiryFormatting.lastUpdated($0.fetchedAt, now: clock) }
            ?? "Waiting for the first update"
    }

    var capacity: PlanCapacity { PlanCapacity(profile: profile, snapshot: snapshot) }

    func setAccentColor(_ hex: String?) {
        profile.accentHex = hex
    }

    func rename(to name: String) async {
        profile.name = name
        await notifications.renameProfile(to: name)
        await calendar.renameProfile(to: name)
    }

    var signInLabel: String { snapshot != nil || profile.t3InstanceID != nil ? "Sign in again…" : "Sign in…" }

    var connectionLabel: String {
        if ProviderExecutableLocator.resolve(profile) == nil {
            return "\(profile.kind.title) not found"
        }
        if !profile.isEnabled { return "Paused" }
        if errorMessage != nil && snapshot == nil { return "Connection failed" }
        if isStale {
            return "Data out of date"
        }
        if snapshot != nil {
            return "Signed in"
        }
        return "Connecting to \(profile.kind.title)"
    }

    var connectionColor: NSColor {
        if ProviderExecutableLocator.resolve(profile) == nil {
            return .systemRed
        }
        if !profile.isEnabled { return .secondaryLabelColor }
        if errorMessage != nil { return .systemOrange }
        if isStale {
            return .systemOrange
        }
        return snapshot == nil ? .secondaryLabelColor : .systemGreen
    }

    var executablePath: String? {
        ProviderExecutableLocator.resolve(profile)?.path
    }

    func statusPresentation(now: Date? = nil) -> StatusPresentation {
        let now = now ?? clock
        guard let snapshot else {
            return isStale
                ? StatusPresentation(count: nil, deadline: "—", state: .stale)
                : .loading
        }

        let count = snapshot.resetSummary?.availableCount ?? 0
        let nextExpiry = snapshot.sortedResetCredits
            .compactMap(\.expiresAt)
            .first(where: { $0 > now })

        if snapshot.resetSummary == nil, !isStale {
            return StatusPresentation(count: nil, deadline: "", state: .usage)
        }
        if isStale {
            return StatusPresentation(count: count, deadline: "", state: .stale)
        }

        guard count > 0 else {
            return StatusPresentation(count: 0, deadline: "", state: .empty)
        }

        guard let nextExpiry else {
            return StatusPresentation(count: count, deadline: "", state: .banked)
        }

        let remaining = nextExpiry.timeIntervalSince(now)
        guard remaining <= 2 * 86_400 else {
            return StatusPresentation(count: count, deadline: "", state: .banked)
        }

        return StatusPresentation(
            count: count,
            deadline: ExpiryFormatting.compactDeadline(nextExpiry, now: now),
            state: isStale
                ? .stale
                : (remaining < 86_400 ? .urgent : .approaching)
        )
    }

    func start() {
        guard profile.isEnabled, refreshTask == nil, clockTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }

            if let cached = await cache.load(), !Task.isCancelled, snapshot == nil {
                snapshot = cached
                isStale = true
                notifyStatusChange()
            }

            guard !Task.isCancelled else { return }
            notificationEnabledKeys = await notifications.enabledKeys()
            createdCalendarKeys = await calendar.createdKeys()
            await refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard !Task.isCancelled, let self else { return }
                clock = Date()
                notifyStatusChange()
                try? await Task.sleep(for: clockRefreshInterval)
            }
        }
    }

    func stop() {
        generation += 1
        requestTask?.cancel()
        requestTask = nil
        refreshTask?.cancel()
        clockTask?.cancel()
        refreshTask = nil
        clockTask = nil
    }

    func refresh() async {
        guard profile.isEnabled, !isRefreshing else { return }
        let currentGeneration = generation
        isRefreshing = true
        defer { isRefreshing = false; requestTask = nil }

        do {
            let task = Task { try await client.readSnapshot(for: profile) }
            requestTask = task
            let newSnapshot = try await task.value
            guard currentGeneration == generation, !Task.isCancelled else { return }
            snapshot = newSnapshot
            isStale = false
            errorMessage = nil
            clock = Date()

            try? await cache.save(newSnapshot)

            let validKeys = Set(resetCredits.map(\.id))
            await notifications.reconcile(validKeys: validKeys)
            notificationEnabledKeys = await notifications.enabledKeys()
            createdCalendarKeys = await calendar.createdKeys()
        } catch {
            guard currentGeneration == generation, !Task.isCancelled else { return }
            isStale = true
            errorMessage = friendlyMessage(for: error)
        }

        notifyStatusChange()
    }

    func toggleNotification(for credit: ResetCredit) async {
        guard !pendingActionKeys.contains(credit.id) else {
            return
        }
        pendingActionKeys.insert(credit.id)
        defer { pendingActionKeys.remove(credit.id) }

        do {
            _ = try await notifications.toggle(for: credit, now: clock)
            notificationEnabledKeys = await notifications.enabledKeys()
            errorMessage = nil
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func toggleCalendarEvent(for credit: ResetCredit) async {
        guard !pendingActionKeys.contains(credit.id) else {
            return
        }
        pendingActionKeys.insert(credit.id)
        defer { pendingActionKeys.remove(credit.id) }
        calendarFailure = nil

        do {
            _ = try await calendar.toggleEvent(for: credit, now: clock)
            createdCalendarKeys = await calendar.createdKeys()
            errorMessage = nil
        } catch {
            let needsAccess: Bool
            switch error as? ReminderError {
            case .calendarDenied, .calendarFullAccessDenied: needsAccess = true
            default: needsAccess = false
            }
            calendarFailure = CalendarFailure(message: friendlyMessage(for: error), needsAccess: needsAccess)
        }
    }

    func dismissCalendarFailure() { calendarFailure = nil }

    struct CalendarFailure {
        let message: String
        let needsAccess: Bool
    }

    func clearNotifications() async {
        await notifications.reconcile(validKeys: [])
        notificationEnabledKeys = []
    }

    func dismissError() {
        errorMessage = nil
    }

    func timeZoneDidChange() {
        clock = Date()
        notifyStatusChange()
    }

    private func notifyStatusChange() {
        onStatusChange?()
    }

    private var clockRefreshInterval: Duration {
        let expiries = snapshot?.sortedResetCredits
            .compactMap(\.expiresAt)
            .filter { $0 > clock } ?? []

        guard let nextExpiry = expiries.min() else {
            return .seconds(60)
        }

        let remaining = nextExpiry.timeIntervalSince(clock)
        if remaining > 3_600 {
            return .seconds(max(1, min(60, remaining - 3_600)))
        }
        if remaining > 0 {
            return .seconds(1)
        }
        return .seconds(60)
    }

    private func friendlyMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
