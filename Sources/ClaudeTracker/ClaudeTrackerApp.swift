import AppKit
import SwiftUI

@main
struct ClaudeTrackerApp: App {
    @State private var store: SessionStore
    @State private var notifications: NotificationService
    @State private var usage: UsageMonitor
    @State private var widget = WidgetPublisher()
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var urlHandler: URLHandler

    init() {
        DevSnapshot.runIfRequested()
        // Menu bar only: no Dock icon, no app switcher entry, even when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.accessory)

        let store = SessionStore()
        let notifications = NotificationService()
        let usage = UsageMonitor()
        usage.onLimitAlerts = { [weak notifications, weak usage] alerts in
            notifications?.post(limitAlerts: alerts, showAccount: (usage?.rateLimits.count ?? 0) > 1)
        }
        let openSession: (String) -> Void = { [weak store] id in
            guard let store, let session = store.session(withId: id) else { return }
            store.markRead(id)
            TerminalActivator.focus(sessionPid: session.pid, tab: store.tabTargets(of: session))
        }
        store.onEvents = { [weak store, weak notifications] events in
            guard let store, let notifications else { return }
            notifications.post(events, store: store)
        }
        notifications.onOpen = openSession
        notifications.requestAuthorization()

        _store = State(initialValue: store)
        _notifications = State(initialValue: notifications)
        _usage = State(initialValue: usage)
        _urlHandler = State(initialValue: URLHandler(onSession: openSession, onTestNotification: { [weak notifications] in notifications?.postTest() }))
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                store: store,
                usage: usage,
                launchAtLogin: launchAtLogin,
                notifications: notifications.isAvailable ? notifications : nil
            )
                .task { startMonitoring() }
                .onAppear { notifications.refreshStatus() }
        } label: {
            MenuBarLabel(summary: store.summary)
                .task { startMonitoring() }
        }
        .menuBarExtraStyle(.window)
    }

    private func startMonitoring() {
        store.start()
        usage.start(store: store)
        widget.start(store: store, usage: usage)
        // SwiftUI installs its own URL handler during launch; claim the event again after it.
        urlHandler.install()
    }
}
