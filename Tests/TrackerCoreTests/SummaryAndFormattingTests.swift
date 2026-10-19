import Foundation
import Testing
@testable import TrackerCore

@Suite("Status summary")
struct StatusSummaryTests {
    @Test func countsByActivity() {
        let activities: [SessionActivity] = [.waiting(reason: nil), .working, .working, .ready, .unknown("x")]

        let summary = StatusSummary(activities: activities)

        #expect(summary == StatusSummary(waiting: 1, working: 2, ready: 1, total: 5))
    }

    @Test func backgroundTaskCountsAsReady() {
        let summary = StatusSummary(activities: [.backgroundTask, .ready, .working])

        #expect(summary == StatusSummary(waiting: 0, working: 1, ready: 2, total: 3))
    }

    @Test func emptyIsZero() {
        #expect(StatusSummary(activities: []) == StatusSummary(waiting: 0, working: 0, ready: 0, total: 0))
    }
}

@Suite("Relative age formatting")
struct RelativeAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [
        (0.0, "teraz"),
        (59.0, "teraz"),
        (60.0, "1 min"),
        (3_599.0, "59 min"),
        (3_600.0, "1 h"),
        (86_399.0, "23 h"),
        (86_400.0, "1 d"),
        (-30.0, "teraz"),
    ])
    func formats(secondsAgo: Double, expected: String) {
        #expect(RelativeAge.format(now.addingTimeInterval(-secondsAgo), now: now) == expected)
    }
}
