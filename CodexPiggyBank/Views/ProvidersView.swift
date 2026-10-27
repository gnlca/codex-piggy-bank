import AppKit
import SwiftUI

struct ProvidersView: View {
    let store: ProviderStore
    @State private var editingProfile: ProviderProfile?
    @State private var removingProfile: ProviderProfile?
    @State private var actionError: String?
    @State private var importMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Providers").font(.title2.weight(.semibold))
                    Text("\(store.profiles.count) accounts · \(store.enabledProfiles.count) active")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(ProviderKind.allCases) { kind in
                        Button("Add \(kind.title)") { editingProfile = .new(kind: kind) }
                    }
                } label: {
                    Label("Add provider", systemImage: "plus")
                }
                .fixedSize()
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if store.profiles.isEmpty {
                        ContentUnavailableView("Add your first account", systemImage: "person.crop.circle.badge.plus",
                                               description: Text("Connect Codex or Claude using a new or existing CLI sign-in."))
                    }
                    ForEach(store.profiles) { profile in
                        if let usage = store.stores[profile.id] {
                            ProviderRow(
                                store: usage,
                                edit: { editingProfile = usage.profile },
                                remove: { removingProfile = usage.profile },
                                rename: { name in Task { await rename(profile.id, to: name) } },
                                setColor: { store.setAccentColor($0, for: profile.id) },
                                setEnabled: { enabled in
                                    var updated = usage.profile
                                    updated.isEnabled = enabled
                                    Task { await save(updated) }
                                }
                            )
                            .padding(.horizontal, 24)
                            if profile.id != store.profiles.last?.id { Divider() }
                        }
                    }
                    if let error = actionError ?? store.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                }
            }
            Divider()
            HStack {
                Menu {
                    Button("Import from T3 Code…", systemImage: "square.and.arrow.down") { importT3() }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .fixedSize()
                if let importMessage {
                    Text(importMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { Task { await store.refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 16, height: 16)
                }
                .liquidGlassCircleButton().help("Refresh all providers")
                .accessibilityLabel("Refresh all providers")
                .disabled(store.enabledProfiles.isEmpty || store.isRefreshing)
            }
            .controlSize(.small).padding(.horizontal, 24).padding(.vertical, 14)
        }
        .disabled(store.isUpdating)
        .sheet(item: $editingProfile) { profile in
            ProviderEditor(profile: profile, isNew: !store.profiles.contains(where: { $0.id == profile.id }), store: store)
        }
        .confirmationDialog("Remove \(removingProfile?.name ?? "provider")?", isPresented: Binding(
            get: { removingProfile != nil }, set: { if !$0 { removingProfile = nil } }
        ), titleVisibility: .visible) {
            Button("Remove provider", role: .destructive) {
                guard let profile = removingProfile else { return }
                Task { await store.remove(profile) }
                removingProfile = nil
            }
        } message: {
            Text("Removes this provider and its pending reset notifications. Your CLI login and Calendar events are kept.")
        }
    }

    private func save(_ profile: ProviderProfile) async {
        do { try await store.save(profile); actionError = nil }
        catch { actionError = error.localizedDescription }
    }

    private func rename(_ profileID: String, to name: String) async {
        do { try await store.rename(profileID, to: name); actionError = nil }
        catch { actionError = error.localizedDescription }
    }

    private func importT3() {
        Task {
            do {
                let count = try await store.importT3()
                importMessage = "\(count) accounts imported."
                actionError = nil
            } catch { actionError = error.localizedDescription }
        }
    }
}

private struct ProviderRow: View {
    let store: ResetStore
    let edit: () -> Void
    let remove: () -> Void
    let rename: (String) -> Void
    let setColor: (String?) -> Void
    let setEnabled: (Bool) -> Void
    @State private var loginMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProviderIcon(profile: store.profile, size: 26).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    InlineProviderName(name: store.profile.name, rename: rename)
                    HStack(spacing: 6) {
                        Text(store.snapshot == nil ? store.profile.kind.title : store.capacity.title)
                        Text("·")
                        Text(store.connectionLabel)
                        if store.isRefreshing { ProgressView().controlSize(.mini) }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let email = store.snapshot?.accountLabel {
                        Text(email).font(.caption).foregroundStyle(.tertiary).lineLimit(1).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProviderColorPicker(name: store.profile.name, hex: Binding(
                    get: { store.profile.accentHex }, set: { setColor($0) }
                ))
                Toggle("Enabled", isOn: Binding(get: { store.profile.isEnabled }, set: { setEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .accessibilityLabel("Enable \(store.profile.name)")
                Button(action: edit) { Image(systemName: "pencil").frame(width: 16, height: 16) }
                    .liquidGlassCircleButton().help("Edit \(store.profile.name)")
                    .accessibilityLabel("Edit \(store.profile.name)")
                Menu {
                    Button(store.signInLabel, systemImage: "person.crop.circle.badge.checkmark", action: signIn)
                    Button("Refresh usage", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .disabled(store.isRefreshing || !store.profile.isEnabled)
                    Button("Use default color") { setColor(nil) }
                    Divider()
                    Button("Remove provider", systemImage: "trash", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 16, height: 16)
                }
                .menuStyle(.button).menuIndicator(.hidden).liquidGlassCircleButton().fixedSize()
                .help("More actions for \(store.profile.name)")
                .accessibilityLabel("More actions for \(store.profile.name)")
            }
            if let message = loginMessage ?? store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .padding(.leading, 48).fixedSize(horizontal: false, vertical: true)
            }
            if store.snapshot == nil, !store.isRefreshing {
                Button(store.signInLabel, action: signIn).controlSize(.small).padding(.leading, 48)
            }
        }
        .padding(.vertical, 16)
    }

    private func signIn() {
        do {
            try ProviderLogin.open(store.profile)
            loginMessage = "Finish signing in in Terminal, then refresh this account."
        } catch { loginMessage = error.localizedDescription }
    }
}
