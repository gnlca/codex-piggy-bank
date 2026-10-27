import SwiftUI

struct ProviderTabs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedTab: String?
    @State private var hoveredTab: String?

    let profiles: [ProviderProfile]
    @Binding var selection: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    tab(nil, name: "All accounts") {
                        Text("All").font(.system(size: 11, weight: .medium))
                    }
                    ForEach(profiles) { profile in
                        tab(profile.id, name: profile.name) {
                            ProviderIcon(profile: profile, size: 18)
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Capsule().fill(.primary).frame(width: 48, height: 2)
                        .offset(x: CGFloat(selectedIndex) * 64 + 6)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: selectedIndex)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo(selection ?? "all")
                }
            }
        }
        .background(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.12)).frame(height: 1) }
        .onMoveCommand { direction in
            guard direction == .left || direction == .right else { return }
            let ids: [String?] = [nil] + profiles.map(\.id)
            guard let index = ids.firstIndex(of: selection) else { return }
            let next = min(ids.count - 1, max(0, index + (direction == .right ? 1 : -1)))
            selection = ids[next]
            focusedTab = selection ?? "all"
        }
    }

    private var selectedIndex: Int {
        guard let selection, let index = profiles.firstIndex(where: { $0.id == selection }) else { return 0 }
        return index + 1
    }

    private func tab<Label: View>(_ id: String?, name: String,
                                 @ViewBuilder label: () -> Label) -> some View {
        let key = id ?? "all"
        return Button { selection = id } label: {
            label().frame(width: 60, height: 38)
                .background(.primary.opacity(hoveredTab == key ? 0.06 : 0), in: .rect(cornerRadius: 8))
                .padding(.bottom, 5)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused($focusedTab, equals: key)
        .onHover { hoveredTab = $0 ? key : nil }
        .accessibilityLabel(name)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
        .help(name)
        .id(key)
    }
}
