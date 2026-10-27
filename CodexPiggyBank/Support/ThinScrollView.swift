import AppKit
import SwiftUI

struct ThinScrollView<Content: View>: NSViewRepresentable {
    @Binding var verticalOffset: CGFloat
    let content: Content

    init(verticalOffset: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        _verticalOffset = verticalOffset
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = OverlayScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini

        let document = NSHostingView(rootView: HostedContent(content: content, environment: context.environment))
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        context.coordinator.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.verticalOffset = $verticalOffset
        if let document = scrollView.documentView as? NSHostingView<HostedContent> {
            document.rootView = HostedContent(content: content, environment: context.environment)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(verticalOffset: $verticalOffset) }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private struct HostedContent: View {
        let content: Content
        let environment: EnvironmentValues

        var body: some View {
            content.environment(\.self, environment).fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var verticalOffset: Binding<CGFloat>
        private weak var scrollView: NSScrollView?

        init(verticalOffset: Binding<CGFloat>) {
            self.verticalOffset = verticalOffset
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func attach(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(boundsDidChange), name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            scrollView = nil
        }

        @objc private func boundsDidChange() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView else { return }
                let offset = max(scrollView.contentView.bounds.origin.y, 0)
                if verticalOffset.wrappedValue != offset { verticalOffset.wrappedValue = offset }
            }
        }
    }
}

private final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
}
