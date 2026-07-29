import SwiftUI

struct LiquidGlassCircleButtonStyle: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(tint)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(tint)
        }
    }
}

struct LiquidGlassIconToggleStyle: ViewModifier {
    let isOn: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if isOn {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .tint(tint)
            } else {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
            }
        } else if isOn {
            content
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .tint(tint)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
        }
    }
}

extension View {
    func liquidGlassCircleButton(tint: Color? = nil) -> some View {
        modifier(LiquidGlassCircleButtonStyle(tint: tint))
    }

    func liquidGlassIconToggle(isOn: Bool, tint: Color) -> some View {
        modifier(LiquidGlassIconToggleStyle(isOn: isOn, tint: tint))
    }
}
