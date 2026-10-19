import Foundation
import Testing
@testable import TrackerCore

@Suite("Transcript cache")
struct TranscriptCacheTests {
    private let assistantLine = #"{"type":"assistant","message":{"content":[{"type":"text","text":"**Gotowe** wszystko"}]}}"#

    private func setUp() throws -> (TempDir, ConfigRoot, TrackedSession) {
        let config = try TempDir()
        try config.makeDir("sessions")
        try config.makeDir("projects")
        let root = ConfigRoot(account: "private", sessionsDirectory: config.url.appending(path: "sessions"))
        let json = SampleSessions.make(pid: 1, sessionId: "abc", cwd: "/p/Demo")
        let session = TrackedSession(record: try SessionRecord.decode(from: Data(json.utf8)), account: "private")
        return (config, root, session)
    }

    @Test func readsCleanedSummary() throws {
        let (config, root, session) = try setUp()
        try config.makeDir("projects/-p-Demo")
        try config.write("projects/-p-Demo/abc.jsonl", assistantLine + "\n")

        let details = TranscriptCache().details(for: [session], roots: [root])

        #expect(details[session.id]?.summary == "Gotowe wszystko")
        #expect(details[session.id]?.aiTitle == nil)
        #expect(details[session.id]?.lastActivity != nil)
    }

    @Test func findsTranscriptCreatedAfterFirstLookup() throws {
        let (config, root, session) = try setUp()
        let cache = TranscriptCache()

        let before = cache.details(for: [session], roots: [root])
        try config.makeDir("projects/-p-Demo")
        try config.write("projects/-p-Demo/abc.jsonl", assistantLine + "\n")
        let after = cache.details(for: [session], roots: [root])

        #expect(before[session.id] == .empty)
        #expect(after[session.id]?.summary == "Gotowe wszystko")
    }

    @Test func picksUpAppendedAnswers() throws {
        let (config, root, session) = try setUp()
        try config.makeDir("projects/-p-Demo")
        try config.write("projects/-p-Demo/abc.jsonl", assistantLine + "\n")
        let cache = TranscriptCache()
        _ = cache.details(for: [session], roots: [root])

        let newer = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Nowa odpowiedź"}]}}"#
        try config.write("projects/-p-Demo/abc.jsonl", assistantLine + "\n" + newer + "\n")
        let details = cache.details(for: [session], roots: [root])

        #expect(details[session.id]?.summary == "Nowa odpowiedź")
    }

    @Test func dropsClosedSessions() throws {
        let (_config, root, session) = try setUp()
        _ = _config
        let cache = TranscriptCache()
        _ = cache.details(for: [session], roots: [root])

        #expect(cache.details(for: [], roots: [root]).isEmpty)
    }
}

@Suite("Transcript activity time")
struct TranscriptActivityTests {
    @Test func subagentWritesCountAsActivity() throws {
        let config = try TempDir()
        try config.makeDir("sessions")
        try config.makeDir("projects/-p-Demo/abc/subagents")
        try config.write("projects/-p-Demo/abc.jsonl", "{}\n")
        try config.write("projects/-p-Demo/abc/subagents/agent-1.jsonl", "{}\n")
        let old = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: config.url.appending(path: "projects/-p-Demo/abc.jsonl").path)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: config.url.appending(path: "projects/-p-Demo/abc/subagents/agent-1.jsonl").path)
        let root = ConfigRoot(account: "private", sessionsDirectory: config.url.appending(path: "sessions"))
        // Subagent activity is only looked up for working sessions (stall detection).
        let json = SampleSessions.make(pid: 1, sessionId: "abc", cwd: "/p/Demo", status: "busy")
        let session = TrackedSession(record: try SessionRecord.decode(from: Data(json.utf8)), account: "private")

        let detail = TranscriptCache().details(for: [session], roots: [root])[session.id]

        #expect(detail?.lastActivity == recent)
    }
}
