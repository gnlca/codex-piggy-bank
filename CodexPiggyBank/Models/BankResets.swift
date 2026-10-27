import Foundation

@MainActor
struct BankResets {
    struct Entry: Identifiable {
        let store: ResetStore
        let credit: ResetCredit
        let id: String

        @MainActor init(store: ResetStore, credit: ResetCredit) {
            self.store = store
            self.credit = credit
            id = "\(store.profile.storageID):\(credit.id)"
        }
    }

    let stores: [ResetStore]

    init(stores: [ResetStore]) {
        var identities: Set<String> = []
        self.stores = stores.sorted {
            ($0.snapshot?.fetchedAt ?? .distantPast) > ($1.snapshot?.fetchedAt ?? .distantPast)
        }.filter {
            guard let id = $0.snapshot?.subscriptionIdentity(for: $0.profile.kind) else { return true }
            return identities.insert("\($0.profile.kind.rawValue):\(id)").inserted
        }
    }

    var entries: [Entry] {
        stores.flatMap { store in store.resetCredits.map { Entry(store: store, credit: $0) } }.sorted {
            let left = $0.credit.expiresAt ?? .distantFuture
            let right = $1.credit.expiresAt ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
    }

    var count: Int { stores.reduce(0) { $0 + $1.availableResetCount } }

    func status(now: Date = Date()) -> StatusPresentation {
        guard stores.contains(where: { $0.snapshot != nil }) else { return .loading }
        if stores.contains(where: \.isStale) { return StatusPresentation(count: count, deadline: "", state: .stale) }
        guard count > 0 else { return StatusPresentation(count: 0, deadline: "", state: .empty) }
        guard let next = entries.compactMap(\.credit.expiresAt).first, next.timeIntervalSince(now) <= 2 * 86_400 else {
            return StatusPresentation(count: count, deadline: "", state: .banked)
        }
        return StatusPresentation(count: count, deadline: ExpiryFormatting.compactDeadline(next, now: now),
                                  state: next.timeIntervalSince(now) < 86_400 ? .urgent : .approaching)
    }
}
