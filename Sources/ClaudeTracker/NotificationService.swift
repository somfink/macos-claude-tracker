import AppKit
import os
import TrackerCore
@preconcurrency import UserNotifications

/// macOS notifications for "finished" and "needs input" transitions.
///
/// UNUserNotificationCenter crashes in a process without an app bundle, so outside
/// `Claude Tracker.app` (e.g. `swift run`) the service stays inert.
@MainActor
@Observable
final class NotificationService: NSObject {
    static let enabledDefaultsKey = "notificationsEnabled"
    private nonisolated static let logger = Logger(subsystem: "dev.claude-tracker", category: "notifications")

    /// System Settings → Notifications → Claude Tracker.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=dev.claude-tracker.app")!

    @ObservationIgnored private let center: UNUserNotificationCenter?
    @ObservationIgnored private let defaults: UserDefaults

    /// True when macOS will not show our banners: notifications denied, or the alert style set
    /// to None. Posting still "succeeds" then, so without this nothing would ever appear.
    private(set) var blockedBySystem = false

    var isAvailable: Bool { center != nil }

    /// Called with the session id when the user clicks one of our notifications;
    /// the owner marks it read and jumps to its terminal.
    @ObservationIgnored var onOpen: ((String) -> Void)?

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.enabledDefaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.enabledDefaultsKey: true])
        center = Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error as NSError? {
                Self.logger.error("Notification authorization failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            } else if !granted {
                Self.logger.info("Notifications denied by user")
            }
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    /// Re-reads what the user allowed in System Settings; called whenever the panel opens.
    func refreshStatus() {
        center?.getNotificationSettings { [weak self] settings in
            let blocked = settings.authorizationStatus == .denied || settings.alertStyle == .none
            Self.logger.info("Notification status \(settings.authorizationStatus.rawValue, privacy: .public), style \(settings.alertStyle.rawValue, privacy: .public)")
            Task { @MainActor in self?.blockedBySystem = blocked }
        }
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    func post(_ events: [SessionEvent], store: SessionStore) {
        guard isEnabled, let center else { return }
        for event in events {
            guard let request = request(for: event, store: store) else { continue }
            center.add(request) { error in
                if let error { Self.logger.error("Posting notification failed: \(error.localizedDescription)") }
            }
        }
    }

    private func request(for event: SessionEvent, store: SessionStore) -> UNNotificationRequest? {
        guard let session = store.session(withId: event.sessionId) else { return nil }
        let title = store.displayTitle(of: session)
        let summary = store.details[session.id]?.summary

        let content = UNMutableNotificationContent()
        switch event {
        case .finished:
            content.title = "✅ \(title)"
            content.body = summary ?? "Gotowe"
        case .needsInput:
            content.title = "⏳ \(title)"
            content.body = ActivityText.label(for: session.activity)
        case .resumed:
            return nil
        }
        content.subtitle = session.projectName == title ? "" : session.projectName
        content.sound = .default
        content.threadIdentifier = session.id
        content.userInfo = ["sessionId": session.id]
        // Stable id per session and kind: a newer banner replaces the older one instead of piling up.
        return UNNotificationRequest(identifier: "\(session.id)#\(kind(of: event))", content: content, trigger: nil)
    }
}

extension NotificationService {
    /// `⚠️ Limit 5 h: 82%` with the reset countdown; one banner per account window,
    /// replaced (not stacked) when the next threshold fires.
    /// A sample banner, to check how ours look without waiting for a session to finish.
    func postTest() {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "✅ Próbne powiadomienie"
        content.body = "Tak wygląda powiadomienie Claude Tracker, gdy sesja skończy pracę."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: nil)) { error in
            if let error { Self.logger.error("Posting test notification failed: \(error.localizedDescription)") }
        }
    }

    func post(limitAlerts alerts: [LimitAlert], showAccount: Bool) {
        guard isEnabled, let center else { return }
        for alert in alerts {
            let content = UNMutableNotificationContent()
            let window = alert.window == .fiveHour ? "Limit 5 h" : "Limit tygodniowy"
            content.title = "⚠️ \(window): \(Int(alert.usedPercentage.rounded()))%"
            content.subtitle = showAccount ? alert.account : ""
            content.body = alert.resetsAt.map { "Reset \(UsageFormat.countdown(to: $0))" } ?? "Zbliżasz się do limitu"
            content.sound = .default
            content.threadIdentifier = "limits"
            let request = UNNotificationRequest(
                identifier: "limit#\(alert.account)#\(alert.window.rawValue)", content: content, trigger: nil
            )
            center.add(request) { error in
                if let error { Self.logger.error("Posting limit alert failed: \(error.localizedDescription)") }
            }
        }
    }
}

private func kind(of event: SessionEvent) -> String {
    switch event {
    case .finished: "finished"
    case .needsInput: "needsInput"
    case .resumed: "resumed"
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Show banners even though the app is technically active while its panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking a notification hands the session to `onOpen`.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        guard let sessionId else { return }
        await MainActor.run { onOpen?(sessionId) }
    }
}
