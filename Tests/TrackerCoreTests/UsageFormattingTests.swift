import Foundation
import Testing
@testable import TrackerCore

@Suite("Usage formatting")
struct UsageFormattingTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test(arguments: [
        (30.0, "za chwilę"),
        (720.0, "za 12 min"),
        (9_780.0, "za 2 h 43 min"),
        (10_800.0, "za 3 h"),
        (356_400.0, "za 4 d 3 h"),
        (172_800.0, "za 2 d"),
        (-10.0, "teraz"),
    ] as [(Double, String)])
    func countdown(seconds: Double, expected: String) {
        #expect(UsageFormat.countdown(to: now.addingTimeInterval(seconds), now: now) == expected)
    }

    @Test(arguments: [
        (0.0, "$0"),
        (0.004, "$0"),
        (7.456, "$7.46"),
        (99.99, "$99.99"),
        (108.05, "$108"),
        (1_088.92, "$1 089"),
        (3_830.0, "$3 830"),
        (1_234_567.0, "$1 234 567"),
    ] as [(Double, String)])
    func money(amount: Double, expected: String) {
        // Expected values use a plain space for readability; the formatter uses U+202F.
        #expect(UsageFormat.usd(amount) == expected.replacingOccurrences(of: " ", with: "\u{202F}"))
    }

    @Test(arguments: [(1, "styczniu"), (2, "lutym"), (10, "październiku"), (11, "listopadzie"), (12, "grudniu")])
    func monthLocative(month: Int, expected: String) {
        #expect(UsageFormat.monthLocative(month) == expected)
    }

    @Test func monthLocativeOutOfRange() {
        #expect(UsageFormat.monthLocative(13) == "tym miesiącu")
    }
}

@Suite("Month-end cost projection")
struct CostProjectionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func extrapolatesCurrentPace() throws {
        // October has 31 days; noon on the 16th is exactly halfway (15.5 days).
        let report = UsageReport(monthCost: 1_000, todayCost: 0, monthCostByAccount: [:])

        let projection = try #require(report.projectedMonthCost(now: date("2026-10-16T12:00:00Z"), calendar: calendar))

        #expect(abs(projection - 2_000) < 0.01)
    }

    @Test func tooEarlyInMonthHasNoProjection() {
        let report = UsageReport(monthCost: 50, todayCost: 50, monthCostByAccount: [:])

        #expect(report.projectedMonthCost(now: date("2026-10-01T10:00:00Z"), calendar: calendar) == nil)
    }

    @Test func neverBelowSpentSoFar() throws {
        let report = UsageReport(monthCost: 900, todayCost: 0, monthCostByAccount: [:])

        let projection = try #require(report.projectedMonthCost(now: date("2026-10-31T23:59:00Z"), calendar: calendar))

        #expect(projection >= 900)
    }
}
