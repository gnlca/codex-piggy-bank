import SwiftUI

struct UsageRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let remaining: Int?
    var size: CGFloat = 68
    var isStale = false
    var label: String?
    var paceRemainingPercent: Int?

    private var lineWidth: CGFloat { size <= 44 ? 3 : 5 }

    var body: some View {
        ZStack {
            ZStack {
                Circle().strokeBorder(.primary.opacity(0.08), lineWidth: lineWidth)
                if let remaining {
                    Circle().inset(by: lineWidth / 2)
                        .trim(from: 0, to: CGFloat(min(100, max(0, remaining))) / 100)
                        .stroke(UsageProgressColor.color(for: remaining), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .mask {
                Rectangle().overlay {
                    if let paceRemainingPercent {
                        PaceTick(length: lineWidth + 3).stroke(lineWidth: 4)
                            .rotationEffect(.degrees(Double(paceRemainingPercent) * 3.6))
                            .transaction { $0.animation = nil }
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            if let paceRemainingPercent {
                PaceTick(length: lineWidth + 3)
                    .stroke(.primary.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [2, 1]))
                    .rotationEffect(.degrees(Double(paceRemainingPercent) * 3.6))
                    .transaction { $0.animation = nil }
            }
            VStack(spacing: 0) {
                Text(remaining.map { "\($0)%" } ?? "—")
                    .font(.system(size: size * 0.20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let label {
                    Text(label).font(.system(size: size <= 44 ? 7 : 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: remaining)
        .opacity(isStale ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.map { "\($0), " } ?? "")\(remaining.map { "\($0) percent remaining\(isStale ? ", out of date" : "")" } ?? "Usage unavailable")")
        .accessibilityValue(paceRemainingPercent.map { "Even pace: \($0) percent remaining" } ?? "")
    }
}

private struct PaceTick: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        Path {
            $0.move(to: CGPoint(x: rect.midX, y: rect.minY))
            $0.addLine(to: CGPoint(x: rect.midX, y: rect.minY + length))
        }
    }
}
