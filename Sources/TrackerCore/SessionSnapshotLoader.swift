import Foundation

/// A session file that exists but could not be read.
public struct LoadIssue: Equatable, Sendable {
    public let file: URL
    public let message: String
}

public struct SessionSnapshot: Equatable, Sendable {
    public let sessions: [TrackedSession]
    public let issues: [LoadIssue]

    public static let empty = SessionSnapshot(sessions: [], issues: [])

    /// Account labels only add information when sessions come from more than one config dir.
    public var spansMultipleAccounts: Bool {
        Set(sessions.map(\.account)).count > 1
    }
}

/// Reads every `<root>/sessions/*.json`, keeps those whose process is still alive,
/// and orders them so sessions needing attention come first.
public struct SessionSnapshotLoader: Sendable {
    private let inspector: any ProcessInspecting

    public init(inspector: any ProcessInspecting = SystemProcessInspector()) {
        self.inspector = inspector
    }

    public func load(from roots: [ConfigRoot]) -> SessionSnapshot {
        let results = roots.flatMap(loadRoot)
        let sessions = results.compactMap { try? $0.get() }
        let issues = results.compactMap { result -> LoadIssue? in
            if case .failure(let issue) = result { return issue }
            return nil
        }
        return SessionSnapshot(sessions: sessions.sorted(by: Self.dashboardOrder), issues: issues)
    }

    private func loadRoot(_ root: ConfigRoot) -> [Result<TrackedSession, LoadIssue>] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root.sessionsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in loadFile(file, account: root.account) }
    }

    /// nil = file is fine but its process is gone (stale leftover, not an error).
    private func loadFile(_ file: URL, account: String) -> Result<TrackedSession, LoadIssue>? {
        switch readRecord(file) {
        case .failure(let issue):
            return .failure(issue)
        case .success(let record):
            // Scripted Agent SDK runs (hooks, reviewers) are not sessions anyone sits in front of.
            if record.entrypoint?.hasPrefix("sdk") == true { return nil }
            guard ProcessStart.isSameProcess(pid: record.pid, procStart: record.procStart, inspector: inspector) else {
                return nil
            }
            return .success(TrackedSession(record: record, account: account))
        }
    }

    /// Claude Code may rewrite the file in place; a read that lands mid-write sees truncated
    /// JSON, so one quick retry keeps a healthy session from flickering out of the list.
    private func readRecord(_ file: URL, attemptsLeft: Int = Self.readAttempts) -> Result<SessionRecord, LoadIssue> {
        do {
            return .success(try SessionRecord.decode(from: Data(contentsOf: file)))
        } catch {
            guard attemptsLeft > 1 else {
                return .failure(LoadIssue(file: file, message: String(describing: error)))
            }
            usleep(Self.retryDelayMicroseconds)
            return readRecord(file, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static let readAttempts = 2
    private static let retryDelayMicroseconds: useconds_t = 15_000

    static func dashboardOrder(_ lhs: TrackedSession, _ rhs: TrackedSession) -> Bool {
        if lhs.activity.sortPriority != rhs.activity.sortPriority {
            return lhs.activity.sortPriority < rhs.activity.sortPriority
        }
        let lhsSince = lhs.statusSince ?? .distantPast
        let rhsSince = rhs.statusSince ?? .distantPast
        if lhsSince != rhsSince { return lhsSince > rhsSince }
        return lhs.id < rhs.id
    }
}

extension LoadIssue: Error {}
