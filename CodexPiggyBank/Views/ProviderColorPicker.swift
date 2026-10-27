import AppKit
import SwiftUI

struct ProviderColorPicker: View {
    let name: String
    @Binding var hex: String?

    var body: some View {
        RoundColorWell(color: Binding(
            get: { hex.flatMap(BadgeColor.init).map { NSColor($0.color) } ?? .controlBackgroundColor },
            set: { color in
                guard let rgb = color.usingColorSpace(.sRGB) else { return }
                let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                    .map { Int((min(1, max(0, $0)) * 255).rounded()) }
                hex = String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
            }
        ), name: name)
        .frame(width: 24, height: 24)
        .help("Change the badge color for \(name)")
        .contextMenu { Button("Use default color") { hex = nil } }
    }
}

private struct RoundColorWell: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var color: NSColor
    let name: String

    func makeNSView(context: Context) -> CircularColorWell {
        let well = CircularColorWell(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        well.colorWellStyle = .minimal
        well.supportsAlpha = false
        well.wantsLayer = true
        well.layer?.cornerRadius = 12
        well.layer?.masksToBounds = true
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: CircularColorWell, context: Context) {
        context.coordinator.color = $color
        well.isEnabled = isEnabled
        if !well.color.isEqual(color) { well.color = color }
        well.setAccessibilityLabel("Color for \(name)")
    }

    func makeCoordinator() -> Coordinator { Coordinator(color: $color) }

    @MainActor final class Coordinator: NSObject {
        var color: Binding<NSColor>
        init(color: Binding<NSColor>) { self.color = color }

        @objc func colorChanged(_ sender: NSColorWell) { color.wrappedValue = sender.color }
    }
}

private final class CircularColorWell: NSColorWell {
    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }
}
