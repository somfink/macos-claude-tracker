import Foundation

/// What the dashboard shows beyond the session file: last answer and generated title.
public struct SessionDetail: Equatable, Sendable {
    public let summary: String?
    public let aiTitle: String?
    /// Newest write to the transcript or any of its subagents' transcripts.
    public let lastActivity: Date?

    public init(summary: String?, aiTitle: String?, lastActivity: Date? = nil) {
        self.summary = summary
        self.aiTitle = aiTitle
        self.lastActivity = lastActivity
    }

    public static let empty = SessionDetail(summary: nil, aiTitle: nil)
}

/// Per-session transcript details, re-read only when the transcript's size or
/// modification date changed. Not thread-safe: use from one actor (the app's main actor).
public final class TranscriptCache {
    private struct Entry {
        let url: URL
        let stamp: FileStamp
        let detail: SessionDetail
    }

    private struct FileStamp: Equatable {
        let size: Int
        let modified: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// Details for exactly the given sessions; entries of closed sessions are dropped.
    public func details(for sessions: [TrackedSession], roots: [ConfigRoot]) -> [String: SessionDetail] {
        let configByAccount = Dictionary(
            roots.map { ($0.account, $0.sessionsDirectory.deletingLastPathComponent()) },
            uniquingKeysWith: { first, _ in first }
        )
        let fresh = sessions.compactMap { session -> (String, Entry)? in
            guard let config = configByAccount[session.account],
                  let entry = entry(for: session, configDirectory: config)
            else { return nil }
            return (session.id, entry)
        }
        entries = Dictionary(fresh, uniquingKeysWith: { first, _ in first })

        return Dictionary(uniqueKeysWithValues: sessions.map { session in
            guard let entry = entries[session.id] else { return (session.id, SessionDetail.empty) }
            // Activity time only matters for stall detection, which only applies while working.
            let subagentWrite = session.activity == .working ? Self.newestSubagentWrite(of: entry.url) : nil
            let activity = [entry.stamp.modified, subagentWrite].compactMap { $0 }.max()
            return (session.id, SessionDetail(summary: entry.detail.summary, aiTitle: entry.detail.aiTitle, lastActivity: activity))
        })
    }

    /// Subagents write to `<transcript>/subagents/*.jsonl`, not the main file; without
    /// them a session busy in a subagent would look idle. One small directory listing.
    private static func newestSubagentWrite(of transcript: URL) -> Date? {
        let directory = transcript.deletingPathExtension().appending(path: "subagents")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    /// nil while the transcript does not exist yet, so the next call looks for it again
    /// (a new session writes its status file before its first transcript line).
    private func entry(for session: TrackedSession, configDirectory: URL) -> Entry? {
        let cached = entries[session.id]
        guard let url = cached?.url
            ?? TranscriptLocator.locate(sessionId: session.sessionId, cwd: session.cwd, configDirectory: configDirectory),
            let stamp = Self.stamp(of: url)
        else { return nil }

        if let cached, cached.stamp == stamp { return cached }

        let summary = TranscriptReader.summary(of: url)
        let detail = SessionDetail(
            summary: summary.lastAssistantText.map { SummaryText.clean($0) },
            // Titles appear rarely; keep the last one seen if it scrolled out of the tail.
            aiTitle: summary.aiTitle ?? cached?.detail.aiTitle
        )
        return Entry(url: url, stamp: stamp, detail: detail)
    }

    private static func stamp(of url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return FileStamp(size: size, modified: modified)
    }
}
