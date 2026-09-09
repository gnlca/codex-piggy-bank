import SwiftUI

enum UsageProgressColor {
    static func color(for remainingPercent: Int) -> Color {
        switch remainingPercent {
        case ..<15:
            return .red
        case ..<40:
            return .orange
        case ..<70:
            return .yellow
        default:
            return .green
        }
    }
}
