import AppKit

enum WeeklyUsageRing {
    static func image(remainingPercent: Int, color: NSColor) -> NSImage {
        let fraction = CGFloat(min(100, max(0, remainingPercent))) / 100
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { bounds in
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            circle.lineWidth = 2.2
            color.withAlphaComponent(0.30).setStroke()
            circle.stroke()

            guard fraction > 0 else { return true }

            color.setStroke()
            if fraction == 1 {
                circle.stroke()
                return true
            }

            let arc = NSBezierPath()
            arc.lineWidth = circle.lineWidth
            arc.lineCapStyle = .round
            arc.appendArc(
                withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
                radius: (bounds.width - 3) / 2,
                startAngle: 90,
                endAngle: 90 - 360 * fraction,
                clockwise: true
            )
            arc.stroke()
            return true
        }
    }
}
