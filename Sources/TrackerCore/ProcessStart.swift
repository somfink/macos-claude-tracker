import Darwin
import Foundation

public protocol ProcessInspecting: Sendable {
    /// Start time of a running process, or nil when no such process exists.
    func startTime(of pid: Int32) -> Date?
}

/// Reads process start times from the kernel via `sysctl(KERN_PROC_PID)`.
public struct SystemProcessInspector: ProcessInspecting {
    public init() {}

    public func startTime(of pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        guard info.kp_proc.p_pid == pid else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}

/// Guards against stale session files: a crashed Claude Code leaves its file behind,
/// and the pid may since belong to an unrelated process.
public enum ProcessStart {
    /// `ps -o lstart` has one-second resolution; allow a little slack on top.
    static let matchTolerance: TimeInterval = 2

    public static func parse(_ value: String) -> Date? {
        let normalized = value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return makeFormatter().date(from: normalized)
    }

    public static func isSameProcess(pid: Int32, procStart: String?, inspector: some ProcessInspecting) -> Bool {
        guard let actual = inspector.startTime(of: pid) else { return false }
        // Older files lack procStart: the live pid is the best evidence available.
        guard let procStart else { return true }
        // Present but unreadable means the format drifted; trusting the pid alone would
        // silently disable reuse protection, so fail closed like Claude Code's own check.
        guard let recorded = parse(procStart) else { return false }
        return abs(actual.timeIntervalSince(recorded)) <= matchTolerance
    }

    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }
}
