import Foundation

public struct StatusSummary: Equatable, Sendable {
    public let waiting: Int
    public let working: Int
    public let ready: Int
    public let total: Int

    public init(waiting: Int, working: Int, ready: Int, total: Int) {
        self.waiting = waiting
        self.working = working
        self.ready = ready
        self.total = total
    }

    public init(activities: [SessionActivity]) {
        self.init(
            waiting: activities.filter { if case .waiting = $0 { true } else { false } }.count,
            working: activities.filter { $0 == .working }.count,
            ready: activities.filter { $0 == .ready || $0 == .backgroundTask }.count,
            total: activities.count
        )
    }
}

/// Compact Polish age labels used in session rows: `teraz`, `5 min`, `2 h`, `3 d`.
public enum RelativeAge {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    public static func format(_ date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        switch elapsed {
        case ..<minute: return "teraz"
        case ..<hour: return "\(Int(elapsed / minute)) min"
        case ..<day: return "\(Int(elapsed / hour)) h"
        default: return "\(Int(elapsed / day)) d"
        }
    }
}
