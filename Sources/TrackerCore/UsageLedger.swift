import Foundation

/// Incremental, persistable index of priced usage across all transcripts.
///
/// Transcripts are append-only, so each file remembers how many bytes were consumed and
/// only new complete lines are parsed on the next pass. A file that shrank is rescanned.
public struct UsageLedger: Codable, Equatable, Sendable {
    public struct FileEntry: Codable, Equatable, Sendable {
        public let account: String
        /// Session the transcript belongs to; subagent transcripts count toward their parent.
        public let sessionId: String
        public let isSubagent: Bool
        /// Working directory the session ran in, from the transcript lines.
        public let cwd: String?
        /// `cli`, `claude-desktop`, … for people; `sdk-py`, `sdk-ts`, … for scripted runs.
        public let entrypoint: String?

        /// Scripted Agent SDK runs (hooks, reviewers) are spend, not sessions anyone opened.
        public var isInteractive: Bool { !(entrypoint?.hasPrefix("sdk") ?? false) }
        public let modified: Date
        public let offset: Int64
        public let records: [String: UsageRecord]
    }

    /// Bump when `FileEntry` gains data that older ledgers lack: they are discarded and
    /// rebuilt by one full scan.
    public static let currentVersion = 4

    public let version: Int
    /// Keyed by canonical transcript path.
    public let files: [String: FileEntry]

    public static let empty = UsageLedger(files: [:])

    public init(files: [String: FileEntry]) {
        version = Self.currentVersion
        self.files = files
    }

    /// nil for unreadable data or a ledger written by an older format.
    public static func decodeCurrent(from data: Data) -> UsageLedger? {
        guard let ledger = try? JSONDecoder().decode(UsageLedger.self, from: data),
              ledger.version == currentVersion
        else { return nil }
        return ledger
    }

    private static let projectsDirName = "projects"
    private static let transcriptExtension = "jsonl"
    private static let readChunkBytes = 8 * 1_024 * 1_024

    /// Scans transcripts modified at or after `since`; entries for older files are dropped.
    public func updated(roots: [ConfigRoot], calendar: Calendar, since: Date) -> UsageLedger {
        let transcripts = roots.flatMap { root in
            Self.transcripts(in: root, since: since).map { (root.account, $0) }
        }
        let next = transcripts.map { account, file in
            (file.path, entry(for: file, account: account, calendar: calendar))
        }
        return UsageLedger(files: Dictionary(next, uniquingKeysWith: { _, latest in latest }))
    }

    /// Sum over the session's own transcript and its subagents; nil when nothing is indexed.
    public func cost(ofSessionId sessionId: String) -> Double? {
        let entries = files.values.filter { $0.sessionId == sessionId }
        guard !entries.isEmpty else { return nil }
        return Self.deduplicated(entries).values.reduce(0) { $0 + $1.cost }
    }

    /// Cost per session id where every message counts once, for the session whose transcript
    /// was written first. A resumed session copies earlier history into a new file; this way
    /// it shows only what it spent itself instead of the whole conversation again.
    public func attributedCosts() -> [String: Double] {
        let owners = files.values.reduce(into: [String: (modified: Date, sessionId: String, cost: Double)]()) { owners, entry in
            for (id, record) in entry.records {
                let candidate = (modified: entry.modified, sessionId: entry.sessionId, cost: record.cost)
                guard let current = owners[id] else {
                    owners[id] = candidate
                    continue
                }
                let earlier = candidate.modified < current.modified ? candidate : current
                owners[id] = (earlier.modified, earlier.sessionId, max(current.cost, candidate.cost))
            }
        }
        return owners.values.reduce(into: [String: Double]()) { costs, owner in
            costs[owner.sessionId, default: 0] += owner.cost
        }
    }

    /// Main transcripts last written on `now`'s day whose session is no longer running,
    /// newest first. Covers sessions that ended while the tracker was not running too.
    public func finishedTranscripts(on now: Date, calendar: Calendar, liveSessionIds: Set<String>) -> [FinishedTranscript] {
        let costs = attributedCosts()
        return files
            .filter { !$0.value.isSubagent && $0.value.isInteractive && !liveSessionIds.contains($0.value.sessionId) }
            .filter { calendar.isDate($0.value.modified, inSameDayAs: now) }
            .map { path, entry in
                FinishedTranscript(
                    sessionId: entry.sessionId, account: entry.account, path: path,
                    cwd: entry.cwd, modified: entry.modified, cost: costs[entry.sessionId]
                )
            }
            .sorted { $0.modified > $1.modified }
    }

    /// One record per message id across files (resumed sessions copy history),
    /// keeping the costliest copy in case a streamed line carried partial usage.
    static func deduplicated(_ entries: some Sequence<FileEntry>) -> [String: UsageRecord] {
        entries.reduce(into: [String: UsageRecord]()) { merged, entry in
            merged.merge(entry.records) { current, candidate in candidate.cost > current.cost ? candidate : current }
        }
    }

    // MARK: Scanning

    private struct Transcript {
        let path: String
        let url: URL
        let sessionId: String
        let isSubagent: Bool
        let size: Int64
        let modified: Date
    }

    private func entry(for file: Transcript, account: String, calendar: Calendar) -> FileEntry {
        let existing = files[file.path].flatMap { $0.offset <= file.size ? $0 : nil }
        let start = existing?.offset ?? 0
        guard file.size > start else {
            return FileEntry(
                account: account, sessionId: file.sessionId, isSubagent: file.isSubagent, cwd: existing?.cwd,
                entrypoint: existing?.entrypoint, modified: file.modified,
                offset: existing?.offset ?? 0, records: existing?.records ?? [:]
            )
        }
        let known = UsageParser.ChunkInfo(cwd: existing?.cwd, entrypoint: existing?.entrypoint)
        let chunk = Self.read(file.url, from: start, calendar: calendar, known: known)
        let merged = (existing?.records ?? [:]).merging(chunk.records) { current, candidate in
            candidate.cost > current.cost ? candidate : current
        }
        return FileEntry(
            account: account, sessionId: file.sessionId, isSubagent: file.isSubagent,
            cwd: chunk.info.cwd ?? existing?.cwd, entrypoint: chunk.info.entrypoint ?? existing?.entrypoint,
            modified: file.modified, offset: start + chunk.consumed, records: merged
        )
    }

    private struct Chunk {
        let records: [String: UsageRecord]
        let consumed: Int64
        let info: UsageParser.ChunkInfo
    }

    /// Parses complete lines from `offset`; returns records keyed by message id, the
    /// number of bytes consumed (a trailing partial line is left for the next pass) and where
    /// and how the newest line ran (cwd, entrypoint).
    private static func read(_ url: URL, from offset: Int64, calendar: Calendar, known: UsageParser.ChunkInfo) -> Chunk {
        let nothing = Chunk(records: [:], consumed: 0, info: UsageParser.ChunkInfo(cwd: nil, entrypoint: nil))
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nothing }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return nothing }

        var records: [String: UsageRecord] = [:]
        var consumed: Int64 = 0
        var cwd: String?
        var entrypoint: String?
        var carry = Data()
        while let chunk = try? handle.read(upToCount: readChunkBytes), !chunk.isEmpty {
            let buffer = carry + chunk
            guard let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) else {
                carry = buffer
                continue
            }
            let complete = buffer[buffer.startIndex...lastNewline]
            let parsed = UsageParser.parse(Data(complete), calendar: calendar)
            for record in parsed.records {
                records[record.messageId] = record
            }
            cwd = parsed.info.cwd ?? cwd
            entrypoint = parsed.info.entrypoint ?? entrypoint
            // Sessions that never got a billed reply carry their metadata only on other lines.
            if (entrypoint ?? known.entrypoint) == nil || (cwd ?? known.cwd) == nil {
                let fallback = UsageParser.firstInfo(in: Data(complete))
                cwd = cwd ?? fallback.cwd
                entrypoint = entrypoint ?? fallback.entrypoint
            }
            consumed += Int64(complete.count)
            carry = Data(buffer[buffer.index(after: lastNewline)...])
        }
        // An unterminated last line may be complete JSON (writer died before the newline).
        // Count it now but leave the offset before it: if the line was only half-written it
        // fails to decode, and re-reading a complete one is harmless since records are
        // keyed by message id.
        let tail = UsageParser.parse(carry, calendar: calendar)
        for record in tail.records {
            records[record.messageId] = record
        }
        let info = UsageParser.ChunkInfo(cwd: tail.info.cwd ?? cwd, entrypoint: tail.info.entrypoint ?? entrypoint)
        return Chunk(records: records, consumed: consumed, info: info)
    }

    private static func transcripts(in root: ConfigRoot, since: Date) -> [Transcript] {
        let projects = root.sessionsDirectory.deletingLastPathComponent().appending(path: projectsDirName)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: projects, includingPropertiesForKeys: keys) else {
            return []
        }
        let projectsDepth = projects.resolvingSymlinksInPath().pathComponents.count

        return enumerator.compactMap { item -> Transcript? in
            guard let url = item as? URL, url.pathExtension == transcriptExtension,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= since,
                  let size = values.fileSize
            else { return nil }
            let canonical = url.resolvingSymlinksInPath()
            let relativeDepth = canonical.pathComponents.count - projectsDepth
            return Transcript(
                path: canonical.path,
                url: canonical,
                sessionId: sessionId(of: canonical, projectsDepth: projectsDepth),
                isSubagent: relativeDepth > 2,
                size: Int64(size),
                modified: modified
            )
        }
    }

    /// `projects/<slug>/<id>.jsonl` → id; `projects/<slug>/<id>/subagents/agent-x.jsonl` → id.
    private static func sessionId(of url: URL, projectsDepth: Int) -> String {
        let relative = url.pathComponents.dropFirst(projectsDepth)
        return relative.count > 2 ? relative[relative.startIndex + 1] : url.deletingPathExtension().lastPathComponent
    }
}

/// A transcript of a session that ended today (see `UsageLedger.finishedTranscripts`).
public struct FinishedTranscript: Equatable, Sendable {
    public let sessionId: String
    public let account: String
    public let path: String
    public let cwd: String?
    public let modified: Date
    public let cost: Double?
}
