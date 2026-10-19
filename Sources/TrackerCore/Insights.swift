import Foundation

// MARK: Limit alerts

/// A usage window crossing an alert threshold, e.g. the 5-hour window passing 80%.
public struct LimitAlert: Equatable, Sendable {
    public enum Window: String, Codable, Sendable {
        case fiveHour
        case weekly
    }

    public let account: String
    public let window: Window
    public let threshold: Int
    public let usedPercentage: Double
    public let resetsAt: Date?
}

/// Thresholds already announced per account window. Keyed `<account>/<window>`; a new
/// `resetsAt` means a new window, which re-arms every threshold.
public struct LimitAlertState: Codable, Equatable, Sendable {
    public struct Fired: Codable, Equatable, Sendable {
        public let resetsAt: Date?
        public let thresholds: [Int]
    }

    public let fired: [String: Fired]

    public static let empty = LimitAlertState(fired: [:])

    public static func load(from url: URL) -> LimitAlertState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(LimitAlertState.self, from: data)
        else { return .empty }
        return state
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

public enum LimitAlerts {
    public static let defaultThresholds = [80, 90]

    /// One alert per window at most: when usage jumps past several thresholds at once,
    /// only the highest is announced, and all of them count as fired.
    public static func evaluate(
        limits: [String: AccountRateLimits],
        state: LimitAlertState,
        thresholds: [Int] = defaultThresholds
    ) -> (alerts: [LimitAlert], state: LimitAlertState) {
        let windows = limits.flatMap { account, limits in
            [(LimitAlert.Window.fiveHour, limits.fiveHour), (.weekly, limits.sevenDay)].compactMap { kind, window in
                window.map { (account, kind, $0) }
            }
        }
        let evaluated = windows.map { account, kind, window in
            evaluateWindow(account: account, kind: kind, window: window, state: state, thresholds: thresholds)
        }
        let nextFired = state.fired.merging(evaluated.map { ($0.key, $0.fired) }) { _, latest in latest }
        return (evaluated.compactMap(\.alert), LimitAlertState(fired: nextFired))
    }

    private static func evaluateWindow(
        account: String, kind: LimitAlert.Window, window: RateLimitWindow,
        state: LimitAlertState, thresholds: [Int]
    ) -> (key: String, fired: LimitAlertState.Fired, alert: LimitAlert?) {
        let key = "\(account)/\(kind.rawValue)"
        let previous = state.fired[key].flatMap { $0.resetsAt == window.resetsAt ? $0 : nil }
        let already = Set(previous?.thresholds ?? [])
        let crossed = window.isExpired ? [] : thresholds.filter { window.usedPercentage >= Double($0) }
        let fresh = crossed.filter { !already.contains($0) }

        let fired = LimitAlertState.Fired(resetsAt: window.resetsAt, thresholds: already.union(crossed).sorted())
        let alert = fresh.max().map {
            LimitAlert(account: account, window: kind, threshold: $0, usedPercentage: window.usedPercentage, resetsAt: window.resetsAt)
        }
        return (key, fired, alert)
    }
}

// MARK: Stall detection

/// "Working" with nothing written to the transcript (or its subagents) for a while.
/// Informational only: a long build legitimately writes nothing until it ends.
public enum Stall {
    public static let defaultThreshold: TimeInterval = 15 * 60

    /// When the silence started, or nil when the session is not stalled.
    public static func since(
        activity: SessionActivity, lastActivity: Date?, now: Date, threshold: TimeInterval = defaultThreshold
    ) -> Date? {
        guard activity == .working, let lastActivity, now.timeIntervalSince(lastActivity) >= threshold else { return nil }
        return lastActivity
    }
}

// MARK: Resume command

/// Shell command that reopens a finished session in its folder with the account's launcher
/// (`claude-private`, `claude-acme`; plain `claude` for `~/.claude`).
public enum ResumeCommand {
    /// nil when the session id or account is not a plain token. Both come from files any local
    /// process can write, and the user pastes the command into a shell, so nothing else is
    /// interpolated unquoted.
    public static func make(account: String, cwd: String, sessionId: String) -> String? {
        guard isPlainToken(account), isPlainToken(sessionId) else { return nil }
        let launcher = account == "default" ? "claude" : "claude-\(account)"
        return "cd \(shellQuoted(cwd)) && \(launcher) --resume \(sessionId)"
    }

    private static let tokenCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    private static func isPlainToken(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy(tokenCharacters.contains)
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
