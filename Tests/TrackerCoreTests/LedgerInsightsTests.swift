import Foundation
import Testing
@testable import TrackerCore

@Suite("Ledger insights: finished sessions and cost breakdown")
struct LedgerInsightsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func line(id: String, day: String, cwd: String, output: Int = 1_000_000, entrypoint: String = "cli") -> String {
        """
        {"type":"assistant","entrypoint":"\(entrypoint)","cwd":"\(cwd)","timestamp":"\(day)T10:00:00.000Z",\
        "message":{"id":"\(id)","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":\(output)}}}
        """
    }

    private func setUp() throws -> (TempDir, ConfigRoot) {
        let config = try TempDir()
        try config.makeDir("sessions")
        try config.makeDir("projects/-p-Alpha/s1/subagents")
        try config.makeDir("projects/-p-Beta")
        return (config, ConfigRoot(account: "private", sessionsDirectory: config.url.appending(path: "sessions")))
    }

    private func touch(_ dir: TempDir, _ path: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dir.url.appending(path: path).path)
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func recordsCwdAndSubagentFlag() throws {
        let (config, root) = try setUp()
        try config.write("projects/-p-Alpha/s1.jsonl", line(id: "a", day: "2026-10-18", cwd: "/p/Alpha") + "\n")
        try config.write("projects/-p-Alpha/s1/subagents/agent-x.jsonl", line(id: "b", day: "2026-10-18", cwd: "/p/Alpha") + "\n")

        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let entries = ledger.files.values.sorted { $0.isSubagent && !$1.isSubagent }
        #expect(entries.map(\.cwd) == ["/p/Alpha", "/p/Alpha"])
        #expect(entries.map(\.isSubagent).sorted { !$0 && $1 } == [false, true])
        #expect(Set(entries.map(\.sessionId)) == ["s1"])
    }

    @Test func finishedTodayExcludesLiveSubagentsAndOlderFiles() throws {
        let (config, root) = try setUp()
        try config.write("projects/-p-Alpha/s1.jsonl", line(id: "a", day: "2026-10-18", cwd: "/p/Alpha") + "\n")
        try config.write("projects/-p-Alpha/s1/subagents/agent-x.jsonl", line(id: "b", day: "2026-10-18", cwd: "/p/Alpha") + "\n")
        try config.write("projects/-p-Beta/live.jsonl", line(id: "c", day: "2026-10-18", cwd: "/p/Beta") + "\n")
        try config.write("projects/-p-Beta/old.jsonl", line(id: "d", day: "2026-10-17", cwd: "/p/Beta") + "\n")
        try touch(config, "projects/-p-Alpha/s1.jsonl", date("2026-10-18T09:00:00Z"))
        try touch(config, "projects/-p-Beta/live.jsonl", date("2026-10-18T09:30:00Z"))
        try touch(config, "projects/-p-Beta/old.jsonl", date("2026-10-17T22:00:00Z"))
        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let finished = ledger.finishedTranscripts(on: date("2026-10-18T12:00:00Z"), calendar: calendar, liveSessionIds: ["live"])

        #expect(finished.map(\.sessionId) == ["s1"])
        #expect(finished.first?.cwd == "/p/Alpha")
        #expect(finished.first.map { abs(($0.cost ?? 0) - 40) < 0.0001 } == true)
    }

    @Test func finishedTodaySkipsSdkRunsButCostsKeepThem() throws {
        let (config, root) = try setUp()
        try config.write("projects/-p-Beta/human.jsonl", line(id: "h", day: "2026-10-18", cwd: "/p/Beta") + "\n")
        try config.write("projects/-p-Beta/bot.jsonl", line(id: "b", day: "2026-10-18", cwd: "/p/Beta", entrypoint: "sdk-py") + "\n")
        try touch(config, "projects/-p-Beta/human.jsonl", date("2026-10-18T09:00:00Z"))
        try touch(config, "projects/-p-Beta/bot.jsonl", date("2026-10-18T09:05:00Z"))
        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let finished = ledger.finishedTranscripts(on: date("2026-10-18T12:00:00Z"), calendar: calendar, liveSessionIds: [])
        let report = UsageReport(ledger: ledger, now: date("2026-10-18T12:00:00Z"), calendar: calendar)

        #expect(finished.map(\.sessionId) == ["human"])
        #expect(abs(report.monthCost - 40) < 0.0001)
    }

    @Test func resumedSessionOnlyCostsItsNewMessages() throws {
        let (config, root) = try setUp()
        let shared = line(id: "shared", day: "2026-10-18", cwd: "/p/Beta")
        try config.write("projects/-p-Beta/first.jsonl", shared + "\n")
        try config.write("projects/-p-Beta/resumed.jsonl", shared + "\n" + line(id: "new", day: "2026-10-18", cwd: "/p/Beta", output: 500_000) + "\n")
        try touch(config, "projects/-p-Beta/first.jsonl", date("2026-10-18T08:00:00Z"))
        try touch(config, "projects/-p-Beta/resumed.jsonl", date("2026-10-18T10:00:00Z"))
        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let costs = ledger.attributedCosts()
        let finished = ledger.finishedTranscripts(on: date("2026-10-18T12:00:00Z"), calendar: calendar, liveSessionIds: [])

        #expect(costs["first"].map { abs($0 - 20) < 0.0001 } == true)
        #expect(costs["resumed"].map { abs($0 - 10) < 0.0001 } == true)
        #expect(finished.compactMap(\.cost).reduce(0, +) - 30 < 0.0001)
    }

    @Test func entrypointFromNonAssistantLine() throws {
        let (config, root) = try setUp()
        // SDK run that failed before any billed reply: only a user line carries the metadata.
        try config.write(
            "projects/-p-Beta/failed.jsonl",
            #"{"type":"user","entrypoint":"sdk-py","cwd":"/p/Beta","message":{"role":"user","content":"hi"}}"# + "\n"
        )
        try touch(config, "projects/-p-Beta/failed.jsonl", date("2026-10-18T09:00:00Z"))
        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        #expect(ledger.files.values.first?.entrypoint == "sdk-py")
        #expect(ledger.files.values.first?.cwd == "/p/Beta")
        #expect(ledger.finishedTranscripts(on: date("2026-10-18T12:00:00Z"), calendar: calendar, liveSessionIds: []).isEmpty)
    }

    @Test func dailyAndProjectBreakdown() throws {
        let (config, root) = try setUp()
        try config.write("projects/-p-Alpha/s1.jsonl", [
            line(id: "a1", day: "2026-10-01", cwd: "/p/Alpha"),
            line(id: "a2", day: "2026-10-18", cwd: "/p/Alpha"),
            line(id: "old", day: "2026-09-30", cwd: "/p/Alpha"),
        ].joined(separator: "\n") + "\n")
        try config.write("projects/-p-Beta/b.jsonl", line(id: "b1", day: "2026-10-18", cwd: "/p/Beta", output: 500_000) + "\n")
        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let report = UsageReport(ledger: ledger, now: date("2026-10-18T12:00:00Z"), calendar: calendar)

        #expect(report.dailyCosts.map(\.day) == ["2026-10-01", "2026-10-18"])
        #expect(report.dailyCosts.map { ($0.cost * 100).rounded() / 100 } == [20, 30])
        #expect(report.projectCosts.map(\.project) == ["Alpha", "Beta"])
        #expect(report.projectCosts.map { ($0.cost * 100).rounded() / 100 } == [40, 10])
    }

    @Test func olderLedgerVersionIsDiscarded() throws {
        let json = #"{"files":{}}"#

        #expect(UsageLedger.decodeCurrent(from: Data(json.utf8)) == nil)
        let current = try JSONEncoder().encode(UsageLedger.empty)
        #expect(UsageLedger.decodeCurrent(from: current) == .empty)
    }
}
