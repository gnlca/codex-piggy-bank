import AppKit
import SwiftUI
import UserNotifications

@main
struct TokensPiggyBankApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.providers)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let providers = ProviderStore()
    private var statusItemController: StatusItemController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        let store = providers
        statusItemController = StatusItemController(providers: store)

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak store] _ in
                Task { @MainActor in
                    await store?.refreshAll()
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
