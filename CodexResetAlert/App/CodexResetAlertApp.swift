import AppKit
import SwiftUI
import UserNotifications

@main
struct CodexResetAlertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItemController: StatusItemController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        let store = ResetStore.live()
        statusItemController = StatusItemController(store: store)

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak store] _ in
                Task { @MainActor in
                    await store?.refresh()
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak store] _ in
                Task { @MainActor in
                    store?.timeZoneDidChange()
                }
            }
        )

        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
