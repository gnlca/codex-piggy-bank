import AppKit
import SwiftUI

struct ProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProviderProfile
    @State private var errorMessage: String?
    @State private var isSaving = false
    let isNew: Bool
    let store: ProviderStore

    init(profile: ProviderProfile, isNew: Bool, store: ProviderStore) {
        _draft = State(initialValue: profile)
        self.isNew = isNew
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderIcon(profile: draft, size: 26)
                Text(isNew ? "Add \(draft.kind.title)" : "Edit \(draft.name)").font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(24)
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("e.g. Claude Personal"))
                    LabeledContent("Color") {
                        ProviderColorPicker(name: draft.name, hex: $draft.accentHex)
                        Button("Default") { draft.accentHex = nil }.disabled(draft.accentHex == nil)
                    }
                    Toggle("Enabled", isOn: $draft.isEnabled).toggleStyle(.switch)
                }
                Section {
                    LabeledContent("Account folder") {
                        HStack {
                            TextField("Account folder", text: $draft.configurationDirectory,
                                      prompt: Text("Default (\(draft.kind.defaultDirectory))"))
                                .labelsHidden()
                            Button("Choose…") { choosePath(isDirectory: true) }
                        }
                    }
                    LabeledContent("CLI executable") {
                        HStack {
                            TextField("CLI executable", text: $draft.executablePath, prompt: Text("Find automatically"))
                                .labelsHidden()
                            Button("Choose…") { choosePath(isDirectory: false) }
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Each subscription uses a separate account folder. Leave it empty to reuse your default CLI sign-in.")
                }
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if #available(macOS 26.0, *) {
                    saveButton.buttonStyle(.glassProminent)
                } else {
                    saveButton.buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 480)
        .disabled(isSaving)
    }

    private var saveButton: some View {
        Button(isNew ? "Add provider" : "Save changes") {
            isSaving = true
            Task {
                defer { isSaving = false }
                do { try await store.save(draft); dismiss() }
                catch { errorMessage = error.localizedDescription }
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func choosePath(isDirectory: Bool) {
        let panel = NSOpenPanel()
        panel.title = isDirectory ? "Choose the account folder" : "Choose the \(draft.kind.title) executable"
        panel.canChooseDirectories = isDirectory
        panel.canChooseFiles = !isDirectory
        panel.canCreateDirectories = isDirectory
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isDirectory { draft.configurationDirectory = url.path }
        else { draft.executablePath = url.path }
    }
}
