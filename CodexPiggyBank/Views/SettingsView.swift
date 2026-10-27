import SwiftUI

struct SettingsView: View {
    let store: ProviderStore

    var body: some View {
        tabs.frame(minWidth: 660, idealWidth: 700, minHeight: 480, idealHeight: 560)
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(macOS 15.0, *) {
            TabView {
                Tab("Providers", systemImage: "person.2") { ProvidersView(store: store) }
                Tab("Appearance", systemImage: "paintpalette") { AppearanceView(store: store) }
            }
        } else {
            TabView {
                ProvidersView(store: store).tabItem { Label("Providers", systemImage: "person.2") }
                AppearanceView(store: store).tabItem { Label("Appearance", systemImage: "paintpalette") }
            }
        }
    }
}

struct AppearanceView: View {
    let store: ProviderStore

    var body: some View {
        Form {
            Section("Provider cards") {
                Toggle("Compact cards", isOn: Binding(
                    get: { store.usesCompactProviderCards }, set: { store.setCompactProviderCards($0) }
                ))
                .toggleStyle(.switch)
                Text("Compact cards show limits on the right. Turn this off for a grid with larger 5h and 7d rings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let account = store.enabledStores.first(where: { $0.overviewWindows.count > 1 }) ?? store.enabledStores.first {
                Section("Preview") {
                    AccountUsageCard(store: account, compact: store.usesCompactProviderCards)
                        .frame(maxWidth: store.usesCompactProviderCards ? 400 : 186, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }
}
