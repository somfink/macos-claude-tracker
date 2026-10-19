import Foundation
import Testing
@testable import TrackerCore

@Suite("Account visibility")
struct SessionGroupingTests {
    private func session(_ id: String, account: String) throws -> TrackedSession {
        let json = SampleSessions.make(pid: 1, sessionId: id)
        return TrackedSession(record: try SessionRecord.decode(from: Data(json.utf8)), account: account)
    }

    @Test func hiddenWhenAllSessionsShareAccount() throws {
        let sessions = [try session("a", account: "private"), try session("b", account: "private")]

        #expect(!SessionSnapshot(sessions: sessions, issues: []).spansMultipleAccounts)
    }

    @Test func shownWhenSessionsComeFromSeveralAccounts() throws {
        let sessions = [try session("a", account: "private"), try session("b", account: "acme")]

        #expect(SessionSnapshot(sessions: sessions, issues: []).spansMultipleAccounts)
    }
}
