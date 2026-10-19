import Foundation
import Testing
@testable import TrackerCore

@Suite("Transcript location")
struct TranscriptLocatorTests {
    @Test(arguments: [
        ("/Users/dev/Projects/Orbit", "-Users-dev-Projects-Orbit"),
        ("/Users/dev/Acme/Acme Portal v2", "-Users-dev-Acme-Acme-Portal-v2"),
        ("/w/Acme Portal v2/.worktrees/admin-ACME-103", "-w-Acme-Portal-v2--worktrees-admin-ACME-103"),
        ("/tmp/zażółć_x", "-tmp-za-----x"),
    ])
    func projectSlug(cwd: String, expected: String) {
        #expect(TranscriptLocator.projectSlug(for: cwd) == expected)
    }

    @Test func prefersExpectedPath() throws {
        let config = try TempDir()
        try config.makeDir("projects/-p-Demo")
        try config.write("projects/-p-Demo/abc.jsonl", "{}\n")

        let url = TranscriptLocator.locate(sessionId: "abc", cwd: "/p/Demo", configDirectory: config.url)

        #expect(url?.lastPathComponent == "abc.jsonl")
        #expect(url?.deletingLastPathComponent().lastPathComponent == "-p-Demo")
    }

    @Test func fallsBackToSearchingProjects() throws {
        let config = try TempDir()
        try config.makeDir("projects/-somewhere-else")
        try config.write("projects/-somewhere-else/abc.jsonl", "{}\n")

        let url = TranscriptLocator.locate(sessionId: "abc", cwd: "/p/Moved", configDirectory: config.url)

        #expect(url?.deletingLastPathComponent().lastPathComponent == "-somewhere-else")
    }

    @Test func nilWhenMissing() throws {
        let config = try TempDir()
        try config.makeDir("projects")

        #expect(TranscriptLocator.locate(sessionId: "nope", cwd: "/p", configDirectory: config.url) == nil)
    }
}

@Suite("Transcript reading")
struct TranscriptReaderTests {
    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func assistant(_ blocks: [[String: Any]], sidechain: Bool = false) -> String {
        line(["type": "assistant", "isSidechain": sidechain, "message": ["role": "assistant", "content": blocks]])
    }

    private func write(_ lines: [String]) throws -> (TempDir, URL) {
        let dir = try TempDir()
        try dir.write("t.jsonl", lines.joined(separator: "\n") + "\n")
        return (dir, dir.url.appending(path: "t.jsonl"))
    }

    @Test func findsLastMainThreadAssistantText() throws {
        let (_dir, url) = try write([
            assistant([["type": "text", "text": "old answer"]]),
            line(["type": "ai-title", "aiTitle": "Naprawa logowania"]),
            assistant([["type": "text", "text": "Gotowe: commit wypchnięty"]]),
            assistant([["type": "tool_use", "name": "Bash"]]),
            assistant([["type": "text", "text": "subagent chatter"]], sidechain: true),
            line(["type": "user", "message": ["role": "user", "content": "plain string content"]]),
        ])
        _ = _dir

        let summary = TranscriptReader.summary(of: url)

        #expect(summary.lastAssistantText == "Gotowe: commit wypchnięty")
        #expect(summary.aiTitle == "Naprawa logowania")
    }

    @Test func picksNewestTitle() throws {
        let (_dir, url) = try write([
            line(["type": "ai-title", "aiTitle": "Pierwszy"]),
            line(["type": "ai-title", "aiTitle": "Drugi"]),
        ])
        _ = _dir

        #expect(TranscriptReader.summary(of: url).aiTitle == "Drugi")
    }

    @Test func ignoresCorruptAndPartialLines() throws {
        let (_dir, url) = try write([
            assistant([["type": "text", "text": "valid"]]),
            "{ this is not json",
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"trunc"#,
        ])
        _ = _dir

        #expect(TranscriptReader.summary(of: url).lastAssistantText == "valid")
    }

    @Test func readsOnlyTailButExpandsWhenNeeded() throws {
        let padding = (0..<400).map { _ in line(["type": "attachment", "pad": String(repeating: "x", count: 1_000)]) }
        let (_dir, url) = try write([assistant([["type": "text", "text": "deep answer"]])] + padding)
        _ = _dir

        let summary = TranscriptReader.summary(of: url, initialTailBytes: 4_096, maxTailBytes: 1_024 * 1_024)

        #expect(summary.lastAssistantText == "deep answer")
    }

    @Test func givesUpBeyondMaxTail() throws {
        let padding = (0..<400).map { _ in line(["type": "attachment", "pad": String(repeating: "x", count: 1_000)]) }
        let (_dir, url) = try write([assistant([["type": "text", "text": "too deep"]])] + padding)
        _ = _dir

        let summary = TranscriptReader.summary(of: url, initialTailBytes: 4_096, maxTailBytes: 16_384)

        #expect(summary.lastAssistantText == nil)
    }

    @Test func missingFileIsEmpty() {
        #expect(TranscriptReader.summary(of: URL(filePath: "/nonexistent/x.jsonl")) == .empty)
    }
}

@Suite("Summary text cleanup")
struct SummaryTextTests {
    @Test(arguments: [
        ("**Gotowe.** Commit `4cca852` wypchnięty.", "Gotowe. Commit 4cca852 wypchnięty."),
        ("## Wynik\n\n- punkt pierwszy\n- punkt drugi", "Wynik · punkt pierwszy · punkt drugi"),
        ("  wiele    spacji\n\n\nlinii  ", "wiele spacji · linii"),
        ("> cytat [link](https://x.y) koniec", "cytat link koniec"),
        ("", ""),
    ])
    func cleans(raw: String, expected: String) {
        #expect(SummaryText.clean(raw) == expected)
    }

    @Test func truncatesLongText() {
        let long = String(repeating: "słowo ", count: 100)

        let cleaned = SummaryText.clean(long, limit: 40)

        #expect(cleaned.count <= 41)
        #expect(cleaned.hasSuffix("…"))
    }
}
