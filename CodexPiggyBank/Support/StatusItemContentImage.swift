import AppKit

@MainActor
enum StatusItemContentImage {
    private static let height: CGFloat = 18
    private static let markSize: CGFloat = 17
    private static let indicatorSize: CGFloat = 14
    private static let compactGap: CGFloat = 3
    private static let sectionGap: CGFloat = 4

    static func make(
        presentation: StatusPresentation,
        weeklyWindow: UsageWindow?
    ) -> NSImage {
        let parts = makeParts(
            presentation: presentation,
            weeklyWindow: weeklyWindow
        )
        let width = ceil(parts.reduce(0) { $0 + $1.width })
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
            var x: CGFloat = 0
            for part in parts {
                part.draw(at: x, canvasHeight: bounds.height)
                x += part.width
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func makeParts(
        presentation: StatusPresentation,
        weeklyWindow: UsageWindow?
    ) -> [StatusItemPart] {
        var parts: [StatusItemPart] = []

        if let mark = NSImage(named: "PiggyBankMark") {
            parts += [.image(mark, size: markSize), .gap(compactGap)]
        }

        parts.append(.text(presentation.leadingText))

        if !presentation.showsBankSummary {
            parts += [.gap(compactGap), .text("·"), .gap(compactGap)]
            if let icon = statusIcon(named: presentation.symbolName) {
                parts.append(.image(icon, size: indicatorSize))
            }
            if !presentation.deadline.isEmpty {
                parts += [.gap(compactGap), .text(presentation.deadline)]
            }
        }

        if let weeklyWindow {
            parts += [
                .gap(sectionGap),
                .text("·"),
                .gap(compactGap),
                .image(
                    WeeklyUsageRing.image(
                        remainingPercent: weeklyWindow.remainingPercent,
                        color: .black
                    ),
                    size: indicatorSize
                ),
                .gap(compactGap),
                .text("\(weeklyWindow.remainingPercent)%"),
            ]
        }

        return parts
    }

    private static func statusIcon(named name: String) -> NSImage? {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: NSFont.systemFontSize,
                weight: .medium
            )
        )
    }
}

private enum StatusItemPart {
    case gap(CGFloat)
    case image(NSImage, size: CGFloat)
    case text(String)

    var width: CGFloat {
        switch self {
        case let .gap(width), let .image(_, width):
            return width
        case let .text(value):
            return attributedText(value).size().width
        }
    }

    func draw(at x: CGFloat, canvasHeight: CGFloat) {
        switch self {
        case .gap:
            return
        case let .image(image, size):
            image.draw(
                in: NSRect(
                    x: x,
                    y: floor((canvasHeight - size) / 2),
                    width: size,
                    height: size
                )
            )
        case let .text(value):
            let text = attributedText(value)
            text.draw(
                at: NSPoint(
                    x: x,
                    y: floor((canvasHeight - text.size().height) / 2) + 1
                )
            )
        }
    }

    private func attributedText(_ value: String) -> NSAttributedString {
        NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: NSFont.systemFontSize,
                    weight: .medium
                ),
                .foregroundColor: NSColor.black,
            ]
        )
    }
}
