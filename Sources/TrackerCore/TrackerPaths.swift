import Foundation

/// Where Claude Tracker keeps its own files. `scripts/statusline-tap.sh` writes to the
/// same statusline directory, so the two must stay in sync.
public enum TrackerPaths {
    public static func applicationSupport(home: URL) -> URL {
        home.appending(path: "Library/Application Support/ClaudeTracker")
    }

    /// `<account>/<session_id>.json` snapshots written by the statusline tap.
    public static func statuslineSnapshots(home: URL) -> URL {
        applicationSupport(home: home).appending(path: "statusline")
    }

    /// Persisted `UsageLedger`, so a restart does not rescan every transcript.
    public static func usageLedger(home: URL) -> URL {
        applicationSupport(home: home).appending(path: "usage-ledger.json")
    }
}

extension TrackerPaths {
    /// Persisted `UnreadState`.
    public static func unreadState(home: URL) -> URL {
        applicationSupport(home: home).appending(path: "unread.json")
    }
}

extension TrackerPaths {
    /// Persisted `LimitAlertState`, so a restart does not repeat alerts for the same window.
    public static func limitAlerts(home: URL) -> URL {
        applicationSupport(home: home).appending(path: "limit-alerts.json")
    }
}
