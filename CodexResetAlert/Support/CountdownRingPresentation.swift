import SwiftUI

struct CountdownRingPresentation {
    static var warningColor: Color {
        Color(red: 1, green: 0.36, blue: 0)
    }

    enum Level: Equatable {
        case warning
        case critical
    }

    let progress: CGFloat
    let level: Level

    init?(expiresAt: Date?, now: Date) {
        guard let expiresAt else {
            return nil
        }

        let remaining = expiresAt.timeIntervalSince(now)
        guard remaining > 0, remaining <= 3_600 else {
            return nil
        }

        progress = CGFloat(min(max(remaining / 3_600, 0), 1))

        if remaining <= 10 * 60 {
            level = .critical
        } else {
            level = .warning
        }
    }

    var color: Color {
        switch level {
        case .warning:
            Self.warningColor
        case .critical:
            .red
        }
    }
}
