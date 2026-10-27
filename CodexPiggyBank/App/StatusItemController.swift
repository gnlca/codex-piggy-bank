import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let providers: ProviderStore
    private var providersWindow: NSWindowController?
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(providers: ProviderStore) {
        self.providers = providers
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()

        providers.onStatusChange = { [weak self] in
            self?.renderStatusItem()
            self?.updatePopoverSize()
        }
        renderStatusItem()
    }

    func stop() {
        providers.stop()
        providers.onStatusChange = nil
        popover.close()
        providersWindow?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Tokens Piggy Bank"
        button.setAccessibilityLabel("Tokens Piggy Bank")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        updatePopoverSize()
        popover.contentViewController = NSHostingController(
            rootView: ProviderPopoverView(providers: providers, openProviders: { [weak self] in self?.showProviders() })
        )
    }

    private func updatePopoverSize() {
        let size = PopoverView.contentSize(for: providers)
        if popover.contentSize != size { popover.contentSize = size }
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let bank = BankResets(stores: providers.enabledStores)
        let usage = providers.usageSummary
        let presentation = bank.status()
        var summary = "\(bank.count) resets available"
        if let remaining = usage.remainingPercent {
            summary += ", weekly limit: \(remaining)% left, \(usage.coverageLabel)"
        }
        if !presentation.deadline.isEmpty { summary += ", next reset expiry: \(presentation.deadline)" }
        if presentation.state == .stale { summary += ", data out of date" }
        button.image = StatusItemContentImage.make(presentation: presentation, weeklyWindow: usage.window)
        button.toolTip = summary
        button.setAccessibilityLabel("Tokens Piggy Bank, \(summary)")
    }

    private func showProviders() {
        popover.performClose(nil)
        if providersWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.contentViewController = NSHostingController(rootView: SettingsView(store: providers))
            window.title = "Tokens Piggy Bank — Settings"
            window.setContentSize(NSSize(width: 700, height: 560))
            window.minSize = NSSize(width: 660, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            providersWindow = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        providersWindow?.showWindow(nil)
        providersWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
        setStatusItemSelected(true)
        Task {
            await providers.refreshAll()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        setStatusItemSelected(false)
    }

    private func setStatusItemSelected(_ isSelected: Bool) {
        guard let button = statusItem.button else {
            return
        }

        button.highlight(isSelected)
    }
}
