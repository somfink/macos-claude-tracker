import Foundation

/// What the menu bar mascot shows, derived from the whole dashboard.
public enum MascotMood: String, CaseIterable, Sendable {
    case sleeping
    case ready
    case working
    case waiting

    /// Attention order: anything waiting beats work in progress beats finished work.
    public init(summary: StatusSummary) {
        if summary.waiting > 0 {
            self = .waiting
        } else if summary.working > 0 {
            self = .working
        } else if summary.total > 0 {
            self = .ready
        } else {
            self = .sleeping
        }
    }

    /// Mood of a single session row. A finished turn with a background bash task is
    /// still "done" from the user's point of view; unknown statuses doze.
    public init(activity: SessionActivity) {
        switch activity {
        case .waiting: self = .waiting
        case .working: self = .working
        case .ready, .backgroundTask: self = .ready
        case .unknown: self = .sleeping
        }
    }

    /// Seconds per animation frame; nil for static moods (no timer, no wakeups).
    public var frameInterval: TimeInterval? {
        switch self {
        case .working: 0.22
        case .waiting: 0.55
        case .ready, .sleeping: nil
        }
    }
}

/// Pixel-art bitmap: one character per pixel, `.` is transparent.
public struct PixelSprite: Hashable, Sendable {
    public let rows: [String]

    public init(rows: [String]) {
        self.rows = rows
    }

    public var width: Int { rows.first?.count ?? 0 }
    public var height: Int { rows.count }

    public func pixel(x: Int, y: Int) -> Character? {
        guard rows.indices.contains(y) else { return nil }
        let row = rows[y]
        guard x >= 0, x < row.count else { return nil }
        return row[row.index(row.startIndex, offsetBy: x)]
    }
}
