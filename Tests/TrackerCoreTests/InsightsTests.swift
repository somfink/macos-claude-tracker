import Foundation
import Testing
@testable import TrackerCore

private let now = Date(timeIntervalSince1970: 2_000_000_000)

private func limits(five: Double?, fiveReset: TimeInterval = 3_600, weekly: Double? = nil) -> AccountRateLimits {
    AccountRateLimits(
        fiveHour: five.map { RateLimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(fiveReset), isExpired: false) },
        sevenDay: weekly.map { RateLimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(400_000), isExpired: false) },
        capturedAt: now
    )
}

@Suite("Limit alerts")
struct LimitAlertTests {
    @Test func firesOnceWhenCrossingThreshold() {
        let first = LimitAlerts.evaluate(limits: ["private": limits(five: 82)], state: .empty)
        let second = LimitAlerts.evaluate(limits: ["private": limits(five: 85)], state: first.state)

        #expect(first.alerts.map(\.threshold) == [80])
        #expect(first.alerts.first?.window == .fiveHour)
        #expect(second.alerts.isEmpty)
    }

    @Test func jumpingPastBothThresholdsAlertsOnlyTheHighest() {
        let result = LimitAlerts.evaluate(limits: ["private": limits(five: 95)], state: .empty)
        let later = LimitAlerts.evaluate(limits: ["private": limits(five: 96)], state: result.state)

        #expect(result.alerts.map(\.threshold) == [90])
        #expect(later.alerts.isEmpty)
    }

    @Test func secondThresholdFiresLater() {
        let first = LimitAlerts.evaluate(limits: ["private": limits(five: 81)], state: .empty)
        let second = LimitAlerts.evaluate(limits: ["private": limits(five: 91)], state: first.state)

        #expect(second.alerts.map(\.threshold) == [90])
    }

    @Test func newWindowRearms() {
        let first = LimitAlerts.evaluate(limits: ["private": limits(five: 85, fiveReset: 3_600)], state: .empty)
        let nextWindow = LimitAlerts.evaluate(limits: ["private": limits(five: 85, fiveReset: 20_000)], state: first.state)

        #expect(nextWindow.alerts.map(\.threshold) == [80])
    }

    @Test func weeklyAndAccountsAreIndependent() {
        let result = LimitAlerts.evaluate(
            limits: ["private": limits(five: 10, weekly: 88), "acme": limits(five: 92)],
            state: .empty
        )

        #expect(Set(result.alerts.map { "\($0.account)/\($0.window.rawValue)/\($0.threshold)" })
            == ["private/weekly/80", "acme/fiveHour/90"])
    }

    @Test func belowThresholdIsSilent() {
        #expect(LimitAlerts.evaluate(limits: ["private": limits(five: 79.9)], state: .empty).alerts.isEmpty)
    }

    @Test func stateRoundTripsThroughFile() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "alerts.json")
        let state = LimitAlerts.evaluate(limits: ["private": limits(five: 95)], state: .empty).state

        try state.write(to: url)

        #expect(LimitAlertState.load(from: url) == state)
        #expect(LimitAlertState.load(from: dir.url.appending(path: "missing.json")) == .empty)
    }
}

@Suite("Stall detection")
struct StallTests {
    @Test func workingWithoutRecentWritesIsStalled() {
        let last = now.addingTimeInterval(-20 * 60)

        #expect(Stall.since(activity: .working, lastActivity: last, now: now) == last)
    }

    @Test func recentActivityIsFine() {
        #expect(Stall.since(activity: .working, lastActivity: now.addingTimeInterval(-60), now: now) == nil)
    }

    @Test(arguments: [SessionActivity.ready, .waiting(reason: nil), .backgroundTask])
    func onlyWorkingSessionsStall(activity: SessionActivity) {
        #expect(Stall.since(activity: activity, lastActivity: now.addingTimeInterval(-3_600), now: now) == nil)
    }

    @Test func unknownActivityTimeIsNotStalled() {
        #expect(Stall.since(activity: .working, lastActivity: nil, now: now) == nil)
    }
}

@Suite("Resume command")
struct ResumeCommandTests {
    @Test func usesAccountLauncher() {
        #expect(ResumeCommand.make(account: "private", cwd: "/p/Orbit", sessionId: "abc")
            == "cd '/p/Orbit' && claude-private --resume abc")
    }

    @Test func defaultAccountUsesPlainClaude() {
        #expect(ResumeCommand.make(account: "default", cwd: "/p/x", sessionId: "abc") == "cd '/p/x' && claude --resume abc")
    }

    @Test func quotesAwkwardPaths() {
        #expect(ResumeCommand.make(account: "acme", cwd: "/p/Acme Portal v2/it's", sessionId: "abc")
            == #"cd '/p/Acme Portal v2/it'\''s' && claude-acme --resume abc"#)
    }

    /// Session ids and account names come from files any local process can write, and the
    /// command is pasted into a shell: anything beyond a plain token yields no command at all.
    @Test(arguments: [
        ("private", "abc; rm -rf ~"),
        ("private", "$(curl evil)"),
        ("x`id`", "abc"),
        ("work space", "abc"),
        ("private", ""),
    ])
    func refusesIdsThatAreNotPlainTokens(account: String, sessionId: String) {
        #expect(ResumeCommand.make(account: account, cwd: "/p/x", sessionId: sessionId) == nil)
    }

    @Test func acceptsRealSessionIds() {
        #expect(ResumeCommand.make(account: "acme.work_2", cwd: "/p/x", sessionId: "ed415905-ad38-458d-b2db-738310339a35")
            == "cd '/p/x' && claude-acme.work_2 --resume ed415905-ad38-458d-b2db-738310339a35")
    }
}
