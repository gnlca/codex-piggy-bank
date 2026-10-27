import Foundation

struct UsageSummary: Equatable, Sendable {
    struct Account: Sendable {
        let profile: ProviderProfile
        let snapshot: UsageSnapshot?
        var isStale = false
    }

    let remainingPercent: Int?
    let includedCount: Int
    let totalCount: Int
    let duplicateCount: Int

    init(accounts: [Account]) {
        let enabled = accounts.filter { $0.profile.isEnabled }
        let candidates = enabled.sorted {
            ($0.snapshot?.fetchedAt ?? .distantPast) > ($1.snapshot?.fetchedAt ?? .distantPast)
        }
        var identities: Set<String> = []
        var remaining: [Int] = []
        var duplicates = 0
        for account in candidates {
            guard !account.isStale, let snapshot = account.snapshot,
                  let weekly = snapshot.windows.first(where: { $0.isWeekly && $0.source != .model }) else { continue }
            if let identity = snapshot.subscriptionIdentity(for: account.profile.kind),
               !identities.insert("\(account.profile.kind.rawValue):\(identity)").inserted {
                duplicates += 1
                continue
            }
            remaining.append(weekly.remainingPercent)
        }
        // T3's poolWindows uses an arithmetic mean; collectLimitAccounts keeps the freshest duplicate.
        remainingPercent = remaining.isEmpty ? nil : Int((Double(remaining.reduce(0, +)) / Double(remaining.count)).rounded())
        includedCount = remaining.count
        totalCount = enabled.count
        duplicateCount = duplicates
    }

    var unavailableCount: Int { max(0, totalCount - includedCount - duplicateCount) }
    var coverageLabel: String { "\(includedCount) \(includedCount == 1 ? "account" : "accounts") with weekly limits" }

    var window: UsageWindow? {
        remainingPercent.map { UsageWindow(usedPercent: 100 - $0, windowDurationMinutes: 10_080, resetsAt: nil, source: .secondary) }
    }
}
