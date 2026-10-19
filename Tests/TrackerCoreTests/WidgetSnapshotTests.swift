import Foundation
import Testing
@testable import TrackerCore

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(_ id: String, _ status: String, name: String? = nil) -> TrackedSession {
        let json = SampleSessions.make(pid: 1, sessionId: id, cwd: "/p/Proj\(id)", name: name, status: status)
        return TrackedSession(record: try! SessionRecord.decode(from: Data(json.utf8)), account: "private")
    }

    private func make(sessions: [TrackedSession], limit: Int = 7) -> WidgetSnapshot {
        WidgetSnapshot.make(
            sessions: sessions,
            titles: ["private/b": "Naprawa logowania"],
            unread: UnreadState(ids: ["private/a"]),
            rateLimits: [
                "private": AccountRateLimits(
                    fiveHour: RateLimitWindow(usedPercentage: 34, resetsAt: now.addingTimeInterval(600), isExpired: false),
                    sevenDay: nil,
                    capturedAt: now
                ),
            ],
            report: UsageReport(monthCost: 1_092, todayCost: 111, monthCostByAccount: [:]),
            now: now,
            sessionLimit: limit
        )
    }

    @Test func summarizesCountsAndSessions() throws {
        let snapshot = make(sessions: [session("w", "waiting"), session("b", "busy"), session("a", "idle")])

        #expect(snapshot.waiting == 1 && snapshot.working == 1 && snapshot.ready == 1)
        #expect(snapshot.mood == .waiting)
        #expect(snapshot.sessions.map(\.title) == ["Projw", "Naprawa logowania", "Proja"])
        #expect(snapshot.sessions.map(\.isUnread) == [false, false, true])
        #expect(snapshot.sessions[0].statusLabel == "Czeka na Ciebie")
        #expect(snapshot.sessions[1].mood == .working)
        #expect(snapshot.monthCost == 1_092)
        #expect(snapshot.limits.first?.fiveHourPercentage == 34)
        #expect(snapshot.limits.first?.weeklyPercentage == nil)
    }

    @Test func capsSessionList() {
        let many = (0..<20).map { session("s\($0)", "idle") }

        let snapshot = make(sessions: many, limit: 7)

        #expect(snapshot.sessions.count == 7)
        #expect(snapshot.total == 20)
    }

    @Test func contentEqualityIgnoresTimestamp() {
        let first = make(sessions: [session("a", "idle")])
        let later = WidgetSnapshot.make(
            sessions: [session("a", "idle")], titles: ["private/b": "Naprawa logowania"],
            unread: UnreadState(ids: ["private/a"]),
            rateLimits: [:], report: nil, now: now.addingTimeInterval(60), sessionLimit: 7
        )

        #expect(first.hasSameContent(as: first))
        #expect(!first.hasSameContent(as: later))
    }

    @Test func roundTripsThroughFile() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "widget.json")
        let snapshot = make(sessions: [session("a", "idle")])

        try snapshot.write(to: url)

        #expect(WidgetSnapshot.read(from: url) == snapshot)
        #expect(WidgetSnapshot.read(from: dir.url.appending(path: "missing.json")) == nil)
    }

    @Test(arguments: [
        ("claudetracker://session/private%2Fabc-123", "private/abc-123"),
        ("claudetracker://session/acme%2Fx", "acme/x"),
    ])
    func sessionLinksRoundTrip(link: String, id: String) throws {
        #expect(WidgetLink.url(forSessionId: id)?.absoluteString == link)
        #expect(WidgetLink.sessionId(from: try #require(URL(string: link))) == id)
    }

    @Test(arguments: ["https://session/x", "claudetracker://other/x", "claudetracker://session/"])
    func rejectsForeignLinks(link: String) throws {
        #expect(WidgetLink.sessionId(from: try #require(URL(string: link))) == nil)
    }
}
