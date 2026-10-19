import Foundation
import os
import TrackerCore

/// A session that ended today, for the "Zakończone dziś" tab.
struct FinishedSession: Identifiable, Equatable, Sendable {
    /// `<account>/<sessionId>`, like `TrackedSession.id`.
    let id: String
    let sessionId: String
    let account: String
    let cwd: String?
    let project: String
    let title: String
    let summary: String?
    let endedAt: Date
    let cost: Double?
    /// Ended by `/clear` in a terminal that may still be running, rather than by closing it.
    let endedByClear: Bool

    var resumeCommand: String? {
        cwd.flatMap { ResumeCommand.make(account: account, cwd: $0, sessionId: sessionId) }
    }
}

/// Result of one background cost scan.
struct UsageScanResult: Sendable {
    let report: UsageReport
    /// API-equivalent cost per session id, subagents included.
    let sessionCosts: [String: Double]
    let finishedToday: [FinishedSession]
}

/// Owns the usage ledger off the main thread: the first scan of a month's transcripts
/// takes seconds, later passes only read appended bytes.
actor UsageScanner {
    /// Rewriting a multi-megabyte ledger on every pass is wasteful; changes since the last
    /// write are at most this old when the app quits.
    private static let persistInterval: TimeInterval = 300
    private static let finishedLimit = 30
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "usage")

    private let ledgerURL: URL
    private var ledger: UsageLedger
    private var lastPersist = Date.distantPast
    /// Transcript tails of finished sessions, keyed by path, valid while `modified` matches.
    private var summaries: [String: (modified: Date, summary: TranscriptSummary)] = [:]

    init(ledgerURL: URL) {
        self.ledgerURL = ledgerURL
        ledger = Self.load(from: ledgerURL)
    }

    func scan(roots: [ConfigRoot], sessionIds: [String]) -> UsageScanResult {
        let calendar = Calendar.current
        let now = Date()
        let since = UsageReport.scanWindowStart(now: now, calendar: calendar)
        let next = ledger.updated(roots: roots, calendar: calendar, since: since)

        if next != ledger {
            ledger = next
            if now.timeIntervalSince(lastPersist) >= Self.persistInterval { persist(now: now) }
        }
        let attributed = next.attributedCosts()
        let costs = sessionIds.compactMap { id in attributed[id].map { (id, $0) } }
        let finished = next.finishedTranscripts(on: now, calendar: calendar, liveSessionIds: Set(sessionIds))
        return UsageScanResult(
            report: UsageReport(ledger: next, now: now, calendar: calendar),
            sessionCosts: Dictionary(costs, uniquingKeysWith: { first, _ in first }),
            finishedToday: finished.prefix(Self.finishedLimit).map(finishedSession)
        )
    }

    private func finishedSession(_ transcript: FinishedTranscript) -> FinishedSession {
        let summary = cachedSummary(path: transcript.path, modified: transcript.modified)
        let project = transcript.cwd.map { URL(filePath: $0).lastPathComponent } ?? transcript.sessionId
        return FinishedSession(
            id: "\(transcript.account)/\(transcript.sessionId)",
            sessionId: transcript.sessionId,
            account: transcript.account,
            cwd: transcript.cwd,
            project: project,
            title: summary.aiTitle ?? project,
            summary: summary.lastAssistantText.map { SummaryText.clean($0) },
            endedAt: transcript.modified,
            cost: transcript.cost,
            endedByClear: transcript.endedByClear
        )
    }

    private func cachedSummary(path: String, modified: Date) -> TranscriptSummary {
        if let cached = summaries[path], cached.modified == modified { return cached.summary }
        let summary = TranscriptReader.summary(of: URL(filePath: path))
        summaries[path] = (modified, summary)
        return summary
    }

    private func persist(now: Date) {
        do {
            try FileManager.default.createDirectory(
                at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
            lastPersist = now
        } catch {
            Self.logger.error("Saving usage ledger failed: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> UsageLedger {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        guard let ledger = UsageLedger.decodeCurrent(from: data) else {
            // Older format or damaged file: one full rescan rebuilds it.
            logger.info("Discarding outdated or unreadable usage ledger")
            return .empty
        }
        return ledger
    }
}
