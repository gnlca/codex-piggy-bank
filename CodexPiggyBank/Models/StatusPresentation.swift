import Foundation

struct StatusPresentation: Equatable, Sendable {
    enum State: Sendable {
        case loading
        case banked
        case approaching
        case urgent
        case empty
        case stale
    }

    let count: Int?
    let deadline: String
    let state: State

    static let loading = StatusPresentation(count: nil, deadline: "—", state: .loading)

    var symbolName: String {
        switch state {
        case .banked, .empty:
            return "building.columns.fill"
        case .stale:
            return "exclamationmark.triangle"
        case .loading, .approaching, .urgent:
            return "timer"
        }
    }

    var showsBankSummary: Bool {
        state == .banked || state == .empty
    }

    var leadingText: String {
        count.map(String.init) ?? "—"
    }
}
