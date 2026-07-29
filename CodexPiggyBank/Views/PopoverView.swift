import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var store: ResetStore
    @State private var topChromeHeight: CGFloat = 112
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                ResetSectionView(store: store)
                    .padding(.top, topChromeHeight)
                    .padding(.bottom, 58)
                    .thinScrollIndicator(verticalOffset: $scrollOffset)
            }

            topChrome
                .zIndex(1)
        }
        .frame(width: 380, height: 340)
        .background(.clear)
        .overlay(alignment: .bottom) {
            footer
        }
        .onPreferenceChange(TopChromeHeightKey.self) { height in
            guard height > 0 else {
                return
            }
            topChromeHeight = height
        }
    }

    private var topChrome: some View {
        VStack(spacing: 0) {
            header
            UsageSectionView(store: store)
        }
        .background {
            GeometryReader { proxy in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: proxy.size.height + 52)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.70),
                                .init(color: .black.opacity(0.82), location: 0.80),
                                .init(color: .black.opacity(0.35), location: 0.92),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .preference(
                        key: TopChromeHeightKey.self,
                        value: proxy.size.height
                    )
                    .opacity(topBlurProgress)
                    .animation(
                        .easeOut(duration: 0.14),
                        value: topBlurProgress
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private var topBlurProgress: CGFloat {
        min(max(scrollOffset / 20, 0), 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("NucleoPiggyBank")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)

            Text("Codex Piggy Bank")
                .font(.headline.weight(.regular))

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                }
            }
            .liquidGlassCircleButton()
            .disabled(store.isRefreshing)
            .help("Refresh")
            .accessibilityLabel("Refresh Codex data")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                Image("CodexMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 21)

                Circle()
                    .fill(Color(nsColor: store.connectionColor))
                    .frame(width: 7, height: 7)
                    .offset(x: 15, y: 14)
            }
            .frame(width: 23, height: 22, alignment: .topLeading)

            Text(shortConnectionLabel)
                .font(.callout)

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 16, height: 16)
            }
            .liquidGlassCircleButton()
            .help("Quit Codex Piggy Bank")
            .accessibilityLabel("Quit Codex Piggy Bank")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.82), location: 0.32),
                            .init(color: .black, location: 0.58),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
        }
    }

    private var shortConnectionLabel: String {
        store.connectionLabel == "Codex connected"
            ? "Connected"
            : store.connectionLabel
    }
}

private struct TopChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
