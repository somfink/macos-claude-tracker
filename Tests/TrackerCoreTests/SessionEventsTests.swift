import Foundation
import Testing
@testable import TrackerCore

private func session(_ id: String, _ status: String, name: String? = nil, nameSource: String? = nil) -> TrackedSession {
    let json = SampleSessions.make(pid: 1, sessionId: id, cwd: "/p/Proj", name: name, nameSource: nameSource, status: status)
    return TrackedSession(record: try! SessionRecord.decode(from: Data(json.utf8)), account: "private")
}

@Suite("Session transitions")
struct SessionEventsTests {
    @Test func workingToIdleIsFinished() {
        let events = SessionEvents.diff(previous: [session("a", "busy")], current: [session("a", "idle")])

        #expect(events == [.finished(id: "private/a")])
    }

    @Test func workingToShellIsFinished() {
        let events = SessionEvents.diff(previous: [session("a", "busy")], current: [session("a", "shell")])

        #expect(events == [.finished(id: "private/a")])
    }

    @Test func anythingToWaitingNeedsInput() {
        let events = SessionEvents.diff(previous: [session("a", "busy")], current: [session("a", "waiting")])

        #expect(events == [.needsInput(id: "private/a")])
    }

    @Test func stayingWaitingIsSilent() {
        let events = SessionEvents.diff(previous: [session("a", "waiting")], current: [session("a", "waiting")])

        #expect(events.isEmpty)
    }

    @Test func idleToBusyIsResumed() {
        let events = SessionEvents.diff(previous: [session("a", "idle")], current: [session("a", "busy")])

        #expect(events == [.resumed(id: "private/a")])
    }

    @Test func waitingToIdleIsNotFinished() {
        // User dismissed a dialog without a model turn: nothing new to read.
        let events = SessionEvents.diff(previous: [session("a", "waiting")], current: [session("a", "idle")])

        #expect(events.isEmpty)
    }

    @Test func newAndVanishedSessionsAreSilent() {
        let events = SessionEvents.diff(previous: [session("gone", "busy")], current: [session("new", "idle")])

        #expect(events.isEmpty)
    }
}

@Suite("Unread results")
struct UnreadStateTests {
    @Test func finishedBecomesUnread() {
        let state = UnreadState.empty.applying([.finished(id: "a")], liveIds: ["a"])

        #expect(state.contains("a"))
    }

    @Test func resumingClearsUnread() {
        let state = UnreadState(ids: ["a"]).applying([.resumed(id: "a")], liveIds: ["a"])

        #expect(!state.contains("a"))
    }

    @Test func closedSessionsAreForgotten() {
        let state = UnreadState(ids: ["a", "b"]).applying([], liveIds: ["b"])

        #expect(state.ids == ["b"])
    }

    @Test func markingReadIsImmutable() {
        let original = UnreadState(ids: ["a", "b"])

        let updated = original.markingRead("a")

        #expect(updated.ids == ["b"])
        #expect(original.ids == ["a", "b"])
    }

    @Test func markAllRead() {
        #expect(UnreadState(ids: ["a", "b"]).markingAllRead().ids.isEmpty)
    }
}

@Suite("Display title")
struct DisplayTitleTests {
    @Test func customNameWins() {
        let custom = session("a", "idle", name: "ACME-101 planowanie")

        #expect(custom.displayTitle(aiTitle: "Coś innego") == "ACME-101 planowanie")
    }

    @Test func aiTitleBeatsDerivedName() {
        let derived = session("a", "idle", name: "proj-ab", nameSource: "derived")

        #expect(derived.displayTitle(aiTitle: "Naprawa logowania") == "Naprawa logowania")
    }

    @Test func projectWhenNothingElse() {
        #expect(session("a", "idle").displayTitle(aiTitle: nil) == "Proj")
    }
}

@Suite("Unread persistence")
struct UnreadPersistenceTests {
    @Test func roundTripsThroughFile() throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "nested/unread.json")

        try UnreadState(ids: ["private/a", "acme/b"]).write(to: url)

        #expect(UnreadState.load(from: url) == UnreadState(ids: ["private/a", "acme/b"]))
    }

    @Test func missingOrCorruptFileIsEmpty() throws {
        let dir = try TempDir()
        try dir.write("bad.json", "{ nope")

        #expect(UnreadState.load(from: dir.url.appending(path: "missing.json")) == .empty)
        #expect(UnreadState.load(from: dir.url.appending(path: "bad.json")) == .empty)
    }
}
