import SwiftUI

struct InlineProviderName: View {
    let name: String
    let rename: (String) -> Void
    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Text(name)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isEditing ? 0 : 1)
            .overlay(alignment: .leading) {
                if isEditing {
                    TextField("Provider name", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit(commit)
                        .onExitCommand { finishEditing() }
                        .onAppear { isFocused = true }
                        .accessibilityLabel("Provider name")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(height: 18)
            .contentShape(.rect)
            .onTapGesture(count: 2, perform: beginEditing)
            .onChange(of: isFocused) { if !isFocused { commit() } }
            .help("Double-click to rename")
            .accessibilityAction(named: "Rename") { beginEditing() }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        draft = name
        isEditing = true
    }

    private func commit() {
        guard isEditing else { return }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        finishEditing()
        if !value.isEmpty, value != name { rename(value) }
    }

    private func finishEditing() {
        isEditing = false
        isFocused = false
    }
}
