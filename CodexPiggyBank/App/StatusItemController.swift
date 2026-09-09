import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: ResetStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(store: ResetStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()

        store.onStatusChange = { [weak self] in
            self?.renderStatusItem()
        }
        renderStatusItem()
    }

    func stop() {
        store.stop()
        store.onStatusChange = nil
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "Codex Piggy Bank"
        button.setAccessibilityLabel("Codex Piggy Bank")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 380)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store)
        )
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let presentation = store.statusPresentation()
        var summary = "\(store.availableResetCount) resets available"
        if let weekly = store.weeklyWindow {
            summary += ", weekly limit: \(weekly.remainingPercent)% left"
        }
        if !presentation.deadline.isEmpty {
            summary += ", next reset expiry: \(presentation.deadline)"
        }
        if store.isStale {
            summary += ", data out of date"
        }

        button.image = StatusItemContentImage.make(
            presentation: presentation,
            weeklyWindow: store.weeklyWindow
        )
        button.toolTip = summary
        button.setAccessibilityLabel("Codex Piggy Bank, \(summary)")
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
            await store.refresh()
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
