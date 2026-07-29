import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ResetStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var isStale = false
    private(set) var errorMessage: String?
    private(set) var scheduledNotificationKeys: Set<String> = []
    private(set) var createdCalendarKeys: Set<String> = []
    private(set) var pendingActionKeys: Set<String> = []
    private(set) var clock = Date()

    @ObservationIgnored private let client: CodexAppServerClient
    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let locator: CodexExecutableLocator
    @ObservationIgnored private let notifications: any NotificationScheduling
    @ObservationIgnored private let calendar: any CalendarEventManaging
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored var onStatusChange: (() -> Void)?

    init(
        client: CodexAppServerClient,
        cache: SnapshotCache,
        locator: CodexExecutableLocator,
        notifications: any NotificationScheduling,
        calendar: any CalendarEventManaging
    ) {
        self.client = client
        self.cache = cache
        self.locator = locator
        self.notifications = notifications
        self.calendar = calendar
    }

    static func live() -> ResetStore {
        ResetStore(
            client: CodexAppServerClient(),
            cache: SnapshotCache(),
            locator: CodexExecutableLocator(),
            notifications: NotificationService(),
            calendar: CalendarService()
        )
    }

    var windows: [UsageWindow] {
        snapshot?.windows.sorted {
            ($0.windowDurationMinutes ?? .max) < ($1.windowDurationMinutes ?? .max)
        } ?? []
    }

    var resetCredits: [ResetCredit] {
        snapshot?.sortedResetCredits ?? []
    }

    var availableResetCount: Int {
        snapshot?.resetSummary?.availableCount ?? 0
    }

    var missingResetDetailCount: Int {
        snapshot?.resetSummary?.missingDetailCount ?? 0
    }

    var lastUpdatedText: String {
        snapshot.map { ExpiryFormatting.lastUpdated($0.fetchedAt, now: clock) }
            ?? "Waiting for the first update"
    }

    var connectionLabel: String {
        if locator.resolve() == nil {
            return "Codex not found"
        }
        if isStale {
            return "Data out of date"
        }
        if snapshot != nil {
            return "Codex connected"
        }
        return "Connecting to Codex"
    }

    var connectionColor: NSColor {
        if locator.resolve() == nil {
            return .systemRed
        }
        if isStale {
            return .systemOrange
        }
        return snapshot == nil ? .secondaryLabelColor : .systemGreen
    }

    var codexPath: String? {
        locator.resolve()?.path
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
        guard refreshTask == nil, clockTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }

            if let cached = await cache.load() {
                snapshot = cached
                isStale = true
                notifyStatusChange()
            }

            scheduledNotificationKeys = await notifications.scheduledKeys()
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
        refreshTask?.cancel()
        clockTask?.cancel()
        refreshTask = nil
        clockTask = nil
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }
        guard let executableURL = locator.resolve() else {
            errorMessage = "Codex CLI was not found. Select the codex executable."
            isStale = snapshot != nil
            notifyStatusChange()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let newSnapshot = try await client.readSnapshot(executableURL: executableURL)
            snapshot = newSnapshot
            isStale = false
            errorMessage = nil
            clock = Date()

            try? await cache.save(newSnapshot)

            let validKeys = Set(newSnapshot.sortedResetCredits.map(\.id))
            await notifications.reconcile(validKeys: validKeys)
            scheduledNotificationKeys = await notifications.scheduledKeys()
            createdCalendarKeys = await calendar.createdKeys()
        } catch {
            isStale = snapshot != nil
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
            scheduledNotificationKeys = await notifications.scheduledKeys()
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

        do {
            _ = try await calendar.toggleEvent(for: credit, now: clock)
            createdCalendarKeys = await calendar.createdKeys()
            errorMessage = nil
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func chooseCodexExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Select the Codex executable"
        panel.message = "Choose the “codex” executable."
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try locator.select(url)
            errorMessage = nil
            Task { await refresh() }
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
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
