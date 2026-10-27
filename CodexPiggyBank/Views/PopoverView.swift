import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topChromeHeight: CGFloat = 150
    @State private var scrollOffset: CGFloat = 0

    let providers: ProviderStore
    let openProviders: () -> Void

    private var contentInset: CGFloat { singleStore == nil ? 24 : 18 }

    var body: some View {
        let size = Self.contentSize(for: providers)
        return ZStack(alignment: .top) {
            ThinScrollView(verticalOffset: $scrollOffset) {
                VStack(alignment: .leading, spacing: 20) {
                    if providers.enabledProfiles.isEmpty {
                        emptyState
                    } else if let store = singleStore {
                        BankResetList(stores: [store], showsProvider: false)
                    } else if let store = providers.selectedStore {
                        AccountUsageView(store: store)
                        BankResetList(stores: [store])
                    } else {
                        accounts
                        BankResetList(stores: providers.enabledStores)
                    }
                }
                .padding(.horizontal, contentInset).padding(.vertical, 18).padding(.bottom, 64)
                .padding(.top, topChromeHeight)
            }
            .id(contentID)
            topChrome.zIndex(1)
        }
        .overlay(alignment: .bottom) { footer }
        .frame(width: size.width, height: size.height)
        .onChange(of: contentID) { scrollOffset = 0 }
        .alert("Couldn’t update Calendar", isPresented: Binding(
            get: { calendarErrorStore != nil },
            set: { if !$0 { calendarErrorStore?.dismissCalendarFailure() } }
        ), presenting: calendarErrorStore?.calendarFailure) { failure in
            if failure.needsAccess {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private var calendarErrorStore: ResetStore? {
        providers.enabledStores.first { $0.calendarFailure != nil }
    }

    static func contentSize(for providers: ProviderStore) -> NSSize {
        let stores = providers.enabledStores
        guard stores.count == 1, let store = stores.first else {
            return NSSize(width: 420, height: 640)
        }
        let limitCount = max(store.windows.count, 1) + (store.snapshot?.individualLimit == nil ? 0 : 1)
        return NSSize(width: 380, height: min(580, 380 + CGFloat(limitCount - 1) * 72))
    }

    private var singleStore: ResetStore? {
        let stores = providers.enabledStores
        return stores.count == 1 ? stores.first : nil
    }

    private var contentID: [String] {
        providers.enabledProfiles.map(\.id) + [providers.selectedProfileID ?? "all", providers.usesCompactProviderCards ? "compact" : "grid"]
    }

    private var topChrome: some View {
        VStack(spacing: 0) {
            header
            if let store = singleStore {
                AccountUsageView(store: store, showsAccountHeader: false)
                    .padding(.horizontal, 18).padding(.vertical, 12)
            } else {
                ProviderTabs(profiles: providers.enabledProfiles, selection: Binding(
                    get: { providers.selectedProfileID }, set: { providers.select($0) }
                ))
                if providers.selectedProfileID == nil, !providers.enabledProfiles.isEmpty {
                    globalSummary.padding(.horizontal, contentInset).padding(.top, 14)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topChromeHeight = $0 }
        .background {
            GeometryReader { proxy in
                Rectangle().fill(.ultraThinMaterial)
                    .frame(height: proxy.size.height + 52)
                    .mask(LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.70),
                            .init(color: .black.opacity(0.82), location: 0.80),
                            .init(color: .black.opacity(0.35), location: 0.92),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .opacity(topBlurProgress)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: topBlurProgress)
                    .allowsHitTesting(false)
            }
        }
    }

    private var topBlurProgress: CGFloat {
        min(max(scrollOffset / 20, 0), 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("PiggyBankMark").resizable().renderingMode(.template)
                .scaledToFit().frame(width: 19, height: 19)
            Text("Tokens Piggy Bank").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await providers.refreshAll() }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise").opacity(providers.isRefreshing ? 0 : 1)
                    if providers.isRefreshing { ProgressView().controlSize(.small) }
                }
                .font(.system(size: 16)).frame(width: 24, height: 24)
                .foregroundStyle(Color.primary)
            }
            .liquidGlassCircleButton()
            .frame(width: 40, height: 40)
            .disabled(providers.isRefreshing || providers.enabledProfiles.isEmpty)
            .help("Refresh all accounts").accessibilityLabel("Refresh all accounts")
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.top, 8)
    }

    private var globalSummary: some View {
        let usage = providers.usageSummary
        return VStack(alignment: .leading, spacing: 8) {
            UsageLimitView(title: "Weekly limit", remainingPercent: usage.remainingPercent)
            if usage.unavailableCount > 0 {
                Text(usage.coverageLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .help("\(usage.coverageLabel). Average weekly percentage across available accounts. Duplicate subscriptions count once, using the latest report.")
    }

    @ViewBuilder
    private var accounts: some View {
        if providers.usesCompactProviderCards {
            VStack(spacing: 8) { accountCards }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 10) {
                accountCards
            }
        }
    }

    private var accountCards: some View {
        ForEach(providers.enabledStores, id: \.profile.id) { store in
            Button { providers.select(store.profile.id) } label: {
                AccountUsageCard(store: store, compact: providers.usesCompactProviderCards)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show limits and resets for \(store.profile.name)")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Your piggy bank is ready").font(.headline)
            Text("Enable an account or add Codex and Claude in Providers.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Manage providers", action: openProviders).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(connectionLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 8) { footerButtons }
            } else {
                footerButtons
            }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.82), location: 0.32),
                        .init(color: .black, location: 0.58),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .allowsHitTesting(false)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 8) {
            Button(action: openProviders) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 16)).frame(width: 24, height: 24)
            }
            .liquidGlassCircleButton()
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings").accessibilityLabel("Settings")
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 16)).frame(width: 24, height: 24)
            }
            .liquidGlassCircleButton()
            .help("Quit Tokens Piggy Bank").accessibilityLabel("Quit Tokens Piggy Bank")
        }
    }

    private var connectionLabel: String {
        let stores = providers.enabledStores
        if stores.isEmpty { return "No active accounts" }
        if providers.isRefreshing { return "Updating…" }
        if stores.contains(where: { $0.isStale || $0.snapshot == nil }) { return "Check providers" }
        guard let oldest = stores.compactMap(\.snapshot?.fetchedAt).min() else { return "Connecting…" }
        return ExpiryFormatting.lastUpdated(oldest, now: stores.map(\.clock).max() ?? Date())
    }
}
