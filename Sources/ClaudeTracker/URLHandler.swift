import AppKit
import TrackerCore

/// Handles `claudetracker://session/<id>` opened from the widget: marks the session read
/// and jumps to its terminal tab. `claudetracker://test-notification` posts a sample banner. A MenuBarExtra has no window to attach `onOpenURL` to,
/// so the Apple Event is handled directly.
@MainActor
final class URLHandler: NSObject {
    private static let testNotificationHost = "test-notification"

    private let onSession: (String) -> Void
    private let onTestNotification: () -> Void

    init(onSession: @escaping (String) -> Void, onTestNotification: @escaping () -> Void) {
        self.onSession = onSession
        self.onTestNotification = onTestNotification
        super.init()
        install()
    }

    /// Safe to call repeatedly; the latest registration for the event wins.
    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string),
              url.scheme == WidgetLink.scheme
        else { return }
        if url.host() == Self.testNotificationHost {
            onTestNotification()
        } else if let sessionId = WidgetLink.sessionId(from: url) {
            onSession(sessionId)
        }
    }
}
