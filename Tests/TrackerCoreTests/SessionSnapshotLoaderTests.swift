import Foundation
import Testing
@testable import TrackerCore

@Suite("Loading live sessions from disk")
struct SessionSnapshotLoaderTests {
    private let liveStart = "Sat Oct 17 18:39:33 2026"

    private func loader(alive: [Int32]) -> SessionSnapshotLoader {
        let start = utc(2026, 10, 17, 18, 39, 33)
        let times = Dictionary(uniqueKeysWithValues: alive.map { ($0, start) })
        return SessionSnapshotLoader(inspector: FakeProcessInspector(startTimes: times))
    }

    @Test func loadsLiveSessionsAndDropsDeadOnes() throws {
        let home = try TempDir()
        try home.makeDir(".claude-private/sessions")
        try home.write(".claude-private/sessions/1.json", SampleSessions.make(pid: 1, sessionId: "s1", procStart: liveStart))
        try home.write(".claude-private/sessions/2.json", SampleSessions.make(pid: 2, sessionId: "s2", procStart: liveStart))
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let snapshot = loader(alive: [1]).load(from: roots)

        #expect(snapshot.sessions.map(\.sessionId) == ["s1"])
        #expect(snapshot.issues.isEmpty)
    }

    @Test func skipsNonJsonAndReportsCorruptFiles() throws {
        let home = try TempDir()
        try home.makeDir(".claude/sessions")
        try home.write(".claude/sessions/1.json", SampleSessions.make(pid: 1, sessionId: "s1", procStart: liveStart))
        try home.write(".claude/sessions/1.abc.key", "secret-ish")
        try home.write(".claude/sessions/9.json", "{ not json")
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let snapshot = loader(alive: [1, 9]).load(from: roots)

        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.issues.count == 1)
        #expect(snapshot.issues.first?.file.lastPathComponent == "9.json")
    }

    @Test func mapsRecordToTrackedSession() throws {
        let home = try TempDir()
        try home.makeDir(".claude-acme/sessions")
        try home.write(
            ".claude-acme/sessions/3.json",
            SampleSessions.make(pid: 3, sessionId: "s3", cwd: "/w/Acme Portal v2", status: "waiting", procStart: liveStart)
        )
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let session = try #require(loader(alive: [3]).load(from: roots).sessions.first)

        #expect(session.id == "acme/s3")
        #expect(session.account == "acme")
        #expect(session.projectName == "Acme Portal v2")
        #expect(session.title == "Acme Portal v2")
        #expect(session.activity == .waiting(reason: nil))
        #expect(session.statusSince == Date(timeIntervalSince1970: 1_792_312_000))
    }

    @Test func prefersExplicitNameAsTitle() throws {
        let home = try TempDir()
        try home.makeDir(".claude/sessions")
        try home.write(".claude/sessions/4.json", SampleSessions.make(pid: 4, sessionId: "s4", name: "ACME-101 planowanie", procStart: liveStart))
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let session = try #require(loader(alive: [4]).load(from: roots).sessions.first)

        #expect(session.title == "ACME-101 planowanie")
    }

    @Test func derivedNameFallsBackToProjectFolder() throws {
        let home = try TempDir()
        try home.makeDir(".claude/sessions")
        try home.write(
            ".claude/sessions/6.json",
            SampleSessions.make(pid: 6, sessionId: "s6", cwd: "/p/Orbit", name: "orbit-ba", nameSource: "derived", procStart: liveStart)
        )
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let session = try #require(loader(alive: [6]).load(from: roots).sessions.first)

        #expect(session.title == "Orbit")
    }

    @Test func sortsWaitingThenWorkingThenReadyNewestFirst() throws {
        let home = try TempDir()
        try home.makeDir(".claude/sessions")
        let files: [(Int32, String, Int64)] = [
            (1, "idle", 1_000), (2, "busy", 2_000), (3, "waiting", 3_000), (4, "idle", 4_000), (5, "busy", 5_000),
        ]
        for (pid, status, at) in files {
            try home.write(
                ".claude/sessions/\(pid).json",
                SampleSessions.make(pid: pid, sessionId: "s\(pid)", status: status, procStart: liveStart, statusUpdatedAt: at)
            )
        }
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let snapshot = loader(alive: [1, 2, 3, 4, 5]).load(from: roots)

        #expect(snapshot.sessions.map(\.sessionId) == ["s3", "s5", "s2", "s4", "s1"])
    }

    @Test func skipsScriptedSdkProcesses() throws {
        let home = try TempDir()
        try home.makeDir(".claude/sessions")
        try home.write(".claude/sessions/1.json", SampleSessions.make(pid: 1, sessionId: "human", procStart: liveStart))
        try home.write(
            ".claude/sessions/2.json",
            #"{"pid":2,"sessionId":"bot","cwd":"/p","entrypoint":"sdk-py","status":"busy","procStart":"Sat Oct 17 18:39:33 2026"}"#
        )
        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        let snapshot = loader(alive: [1, 2]).load(from: roots)

        #expect(snapshot.sessions.map(\.sessionId) == ["human"])
    }

    @Test func missingSessionsDirectoryIsNotAnError() {
        let root = ConfigRoot(account: "ghost", sessionsDirectory: URL(filePath: "/nonexistent/claude/sessions"))

        let snapshot = loader(alive: []).load(from: [root])

        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.issues.isEmpty)
    }
}
