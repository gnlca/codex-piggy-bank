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
        button.wantsLayer = true
        button.layer?.cornerCurve = .continuous
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 340)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store)
        )
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let presentation = store.statusPresentation()
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .medium
        )
        let textColor = NSColor.labelColor
        let title = NSMutableAttributedString()

        if !presentation.showsBankSummary {
            title.append(
                NSAttributedString(
                    string: "\(presentation.leadingText) · ",
                    attributes: [
                        .font: font,
                        .foregroundColor: textColor,
                    ]
                )
            )
        }

        if let image = statusIcon(for: presentation) {
            image.isTemplate = false
            let attachment = NSTextAttachment()
            attachment.image = image
            let iconSize: CGFloat = presentation.showsBankSummary ? 17 : 15
            attachment.bounds = NSRect(
                x: 0,
                y: presentation.showsBankSummary ? -3 : -2,
                width: iconSize,
                height: iconSize
            )
            title.append(NSAttributedString(attachment: attachment))
        }

        if presentation.showsBankSummary {
            title.append(
                NSAttributedString(
                    string: " \(presentation.leadingText)",
                    attributes: [
                        .font: font,
                        .foregroundColor: textColor,
                    ]
                )
            )
        } else if !presentation.deadline.isEmpty {
            title.append(
                NSAttributedString(
                    string: " \(presentation.deadline)",
                    attributes: [
                        .font: font,
                        .foregroundColor: textColor,
                    ]
                )
            )
        }

        button.image = nil
        button.attributedTitle = title
        button.toolTip = "\(store.availableResetCount) resets available"
    }

    private func statusIcon(for presentation: StatusPresentation) -> NSImage? {
        if presentation.showsBankSummary {
            guard let source = NSImage(named: "NucleoPiggyBank") else {
                return nil
            }

            return NSImage(size: NSSize(width: 17, height: 17), flipped: false) { rect in
                presentation.symbolColor.setFill()
                rect.fill()
                source.draw(
                    in: rect,
                    from: .zero,
                    operation: .destinationIn,
                    fraction: 1
                )
                return true
            }
        }

        return NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: NSFont.systemFontSize,
                weight: .medium
            ).applying(
                NSImage.SymbolConfiguration(
                    paletteColors: [presentation.symbolColor]
                )
            )
        )
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

        button.highlight(false)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        button.layer?.backgroundColor = isSelected
            ? NSColor.labelColor.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        CATransaction.commit()
    }
}
