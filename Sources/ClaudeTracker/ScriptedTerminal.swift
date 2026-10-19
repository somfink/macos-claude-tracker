import AppKit
import os
import TrackerCore

/// iTerm2 and Terminal.app: selects the tab attached to the session's tty through AppleScript.
/// macOS asks once for permission to control each app (Privacy & Security → Automation).
enum ScriptedTerminal {
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "terminal")
    /// The first run waits on the Automation prompt for as long as the user takes, so scripts
    /// run here rather than on the main thread; serial because NSAppleScript is not thread-safe.
    private static let queue = DispatchQueue(label: "dev.claude-tracker.applescript")

    /// False when the tab was not found or the script could not run (no tty, permission denied);
    /// the caller then just brings the app forward.
    static func select(sessionPid: Int32, in app: TerminalApp) async -> Bool {
        guard let tty = SystemProcessTable.tty(of: sessionPid),
              let source = TerminalScript.select(tty: tty, in: app)
        else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: run(source)) }
        }
    }

    private static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            logger.error("Selecting the terminal tab failed: AppleScript error \(code, privacy: .public)")
            return false
        }
        return result.booleanValue
    }
}
