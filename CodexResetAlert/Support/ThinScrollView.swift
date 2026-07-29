import AppKit
import SwiftUI

struct ThinScrollViewConfigurator: NSViewRepresentable {
    @Binding var verticalOffset: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureAfterLayout(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.verticalOffset = $verticalOffset
        configureAfterLayout(from: nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(verticalOffset: $verticalOffset)
    }

    private func configureAfterLayout(
        from view: NSView,
        coordinator: Coordinator
    ) {
        DispatchQueue.main.async {
            var ancestor = view.superview

            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    scrollView.scrollerStyle = .overlay
                    scrollView.autohidesScrollers = true
                    scrollView.verticalScroller?.controlSize = .mini
                    coordinator.attach(to: scrollView)
                    return
                }
                ancestor = current.superview
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var verticalOffset: Binding<CGFloat>

        private weak var scrollView: NSScrollView?
        private var topOriginY: CGFloat?

        init(verticalOffset: Binding<CGFloat>) {
            self.verticalOffset = verticalOffset
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else {
                updateOffset()
                return
            }

            NotificationCenter.default.removeObserver(self)
            self.scrollView = scrollView
            topOriginY = scrollView.contentView.bounds.origin.y
            scrollView.contentView.postsBoundsChangedNotifications = true

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            updateOffset()
        }

        @objc
        private func boundsDidChange() {
            updateOffset()
        }

        private func updateOffset() {
            guard let scrollView else {
                return
            }

            let originY = scrollView.contentView.bounds.origin.y
            let baseline = topOriginY ?? originY
            verticalOffset.wrappedValue = max(originY - baseline, 0)
        }
    }
}

extension View {
    func thinScrollIndicator(verticalOffset: Binding<CGFloat>) -> some View {
        background {
            ThinScrollViewConfigurator(verticalOffset: verticalOffset)
                .frame(width: 0, height: 0)
        }
    }
}
