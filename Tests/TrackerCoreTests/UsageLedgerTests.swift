import Foundation
import Testing
@testable import TrackerCore

@Suite("Usage ledger and report")
struct UsageLedgerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func line(id: String, day: String, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"\(day)T10:00:00.000Z","message":{"id":"\(id)","model":"claude-opus-5-5",\
        "usage":{"input_tokens":0,"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    private func setUp() throws -> (TempDir, ConfigRoot) {
        let config = try TempDir()
        try config.makeDir("sessions")
        try config.makeDir("projects/-p-Demo")
        return (config, ConfigRoot(account: "private", sessionsDirectory: config.url.appending(path: "sessions")))
    }

    private func now(_ day: String) -> Date {
        ISO8601DateFormatter().date(from: "\(day)T12:00:00Z")!
    }

    @Test func sumsMonthAndTodayDedupingAcrossFiles() throws {
        let (config, root) = try setUp()
        let shared = line(id: "dup", day: "2026-10-18", output: 1_000_000)
        try config.write("projects/-p-Demo/a.jsonl", [
            line(id: "sep", day: "2026-09-30", output: 1_000_000),
            line(id: "oct1", day: "2026-10-01", output: 1_000_000),
            shared,
        ].joined(separator: "\n") + "\n")
        // A resumed session copies history into a new file: must not double count.
        try config.write("projects/-p-Demo/b.jsonl", shared + "\n")

        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)
        let report = UsageReport(ledger: ledger, now: now("2026-10-18"), calendar: calendar)

        #expect(abs(report.monthCost - 40) < 0.0001)
        #expect(abs(report.todayCost - 20) < 0.0001)
        #expect(report.monthCostByAccount["private"].map { abs($0 - 40) < 0.0001 } == true)
    }

    @Test func readsOnlyAppendedBytes() throws {
        let (config, root) = try setUp()
        let path = "projects/-p-Demo/a.jsonl"
        try config.write(path, line(id: "m1", day: "2026-10-18", output: 1_000_000) + "\n")
        let first = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let appended = [line(id: "m1", day: "2026-10-18", output: 1_000_000), line(id: "m2", day: "2026-10-18", output: 500_000)]
        try config.write(path, appended.joined(separator: "\n") + "\n" + #"{"type":"assistant","partial"#)
        let second = first.updated(roots: [root], calendar: calendar, since: .distantPast)

        let fileURL = config.url.appending(path: path).resolvingSymlinksInPath().path
        let entry = try #require(second.files[fileURL] ?? second.files.values.first)
        #expect(entry.records.count == 2)
        // Partial trailing line is left for the next pass.
        #expect(entry.offset == Int64(appended.joined(separator: "\n").utf8.count + 1))
    }

    @Test func countsUnterminatedFinalLineOnce() throws {
        let (config, root) = try setUp()
        // Claude Code died mid-session: the last line is complete JSON but has no newline.
        try config.write("projects/-p-Demo/a.jsonl", line(id: "m1", day: "2026-10-18", output: 1_000_000) + "\n"
            + line(id: "m2", day: "2026-10-18", output: 1_000_000))

        let first = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)
        let second = first.updated(roots: [root], calendar: calendar, since: .distantPast)

        #expect(first.files.values.first?.records.count == 2)
        #expect(second.cost(ofSessionId: "a").map { abs($0 - 40) < 0.0001 } == true)
    }

    @Test func rescansTruncatedFile() throws {
        let (config, root) = try setUp()
        let path = "projects/-p-Demo/a.jsonl"
        try config.write(path, (0..<5).map { line(id: "m\($0)", day: "2026-10-18", output: 1) }.joined(separator: "\n") + "\n")
        let first = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        try config.write(path, line(id: "x", day: "2026-10-18", output: 1) + "\n")
        let second = first.updated(roots: [root], calendar: calendar, since: .distantPast)

        #expect(second.files.values.first?.records.keys.sorted() == ["x"])
    }

    @Test func sessionCostIsPerTranscript() throws {
        let (config, root) = try setUp()
        try config.write("projects/-p-Demo/abc.jsonl", line(id: "m1", day: "2026-10-18", output: 2_000_000) + "\n")

        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        #expect(ledger.cost(ofSessionId: "abc").map { abs($0 - 40) < 0.0001 } == true)
        #expect(ledger.cost(ofSessionId: "missing") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let (config, root) = try setUp()
        try config.write("projects/-p-Demo/a.jsonl", line(id: "m1", day: "2026-10-18", output: 1) + "\n")
        let ledger = UsageLedger.empty.updated(roots: [root], calendar: calendar, since: .distantPast)

        let decoded = try JSONDecoder().decode(UsageLedger.self, from: JSONEncoder().encode(ledger))

        #expect(decoded == ledger)
    }
}

@Suite("Rate limits from statusline snapshots")
struct RateLimitTests {
    private func snapshot(fiveHour: Double, fiveReset: Int, weekly: Double, weekReset: Int) -> String {
        """
        {"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":\(fiveHour),"resets_at":\(fiveReset)},\
        "seven_day":{"used_percentage":\(weekly),"resets_at":\(weekReset)}},"context_window":{"used_percentage":28}}
        """
    }

    @Test func readsNewestSnapshotPerAccount() throws {
        let dir = try TempDir()
        try dir.makeDir("private")
        try dir.write("private/old.json", snapshot(fiveHour: 10, fiveReset: 2_000_000_000, weekly: 5, weekReset: 2_000_000_000))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: dir.url.appending(path: "private/old.json").path
        )
        try dir.write("private/new.json", snapshot(fiveHour: 34, fiveReset: 2_000_000_000, weekly: 19, weekReset: 2_000_000_000))

        let limits = RateLimitReader.read(directory: dir.url, now: Date(timeIntervalSince1970: 1_900_000_000))

        let privateLimits = try #require(limits["private"])
        #expect(privateLimits.fiveHour?.usedPercentage == 34)
        #expect(privateLimits.sevenDay?.usedPercentage == 19)
        #expect(privateLimits.fiveHour?.resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test func expiredWindowReadsAsZero() throws {
        let dir = try TempDir()
        try dir.makeDir("private")
        try dir.write("private/s.json", snapshot(fiveHour: 90, fiveReset: 1_000, weekly: 50, weekReset: 2_000_000_000))

        let limits = RateLimitReader.read(directory: dir.url, now: Date(timeIntervalSince1970: 5_000))

        #expect(limits["private"]?.fiveHour?.usedPercentage == 0)
        #expect(limits["private"]?.fiveHour?.isExpired == true)
        #expect(limits["private"]?.sevenDay?.usedPercentage == 50)
    }

    @Test func snapshotsWithoutLimitsAreIgnored() throws {
        let dir = try TempDir()
        try dir.makeDir("acme")
        try dir.write("acme/s.json", #"{"session_id":"x","rate_limits":null}"#)

        #expect(RateLimitReader.read(directory: dir.url, now: Date()).isEmpty)
    }

    @Test func missingDirectoryIsEmpty() {
        #expect(RateLimitReader.read(directory: URL(filePath: "/nonexistent/tap"), now: Date()).isEmpty)
    }
}

@Suite("Context usage from statusline snapshots")
struct ContextUsageTests {
    @Test func readsPercentagePerSession() throws {
        let dir = try TempDir()
        try dir.makeDir("private")
        try dir.makeDir("acme")
        try dir.write("private/s1.json", #"{"session_id":"s1","context_window":{"used_percentage":28.4}}"#)
        try dir.write("acme/s2.json", #"{"session_id":"s2","context_window":{"used_percentage":null,"total_input_tokens":150000,"context_window_size":200000}}"#)
        try dir.write("acme/s3.json", #"{"session_id":"s3"}"#)

        let usage = ContextUsageReader.read(directory: dir.url)

        #expect(usage["s1"] == 28.4)
        #expect(usage["s2"] == 75)
        #expect(usage["s3"] == nil)
    }

    @Test func missingDirectoryIsEmpty() {
        #expect(ContextUsageReader.read(directory: URL(filePath: "/nonexistent/tap")).isEmpty)
    }
}
