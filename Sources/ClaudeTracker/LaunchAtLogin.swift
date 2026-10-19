import Foundation
import Observation
import os
import ServiceManagement

/// "Open at login" via SMAppService. Only meaningful for the bundled app.
@MainActor
@Observable
final class LaunchAtLogin {
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "login-item")

    private(set) var isEnabled = false
    /// macOS asks the user to confirm new login items in System Settings → Login Items.
    private(set) var needsApproval = false

    let isAvailable = Bundle.main.bundleURL.pathExtension == "app"

    init() {
        refresh()
    }

    func toggle() {
        guard isAvailable else { return }
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Self.logger.error("Changing login item failed: \(error.localizedDescription)")
        }
        refresh()
    }

    private func refresh() {
        guard isAvailable else { return }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }
}
