import Foundation

/// A live Claude Code session as presented by the dashboard.
public struct TrackedSession: Identifiable, Equatable, Hashable, Sendable {
    /// `<account>/<sessionId>`; session ids are only unique within one config dir.
    public let id: String
    public let account: String
    public let pid: Int32
    public let sessionId: String
    public let cwd: String
    public let projectName: String
    /// Session name when Claude Code has one, otherwise the project folder.
    public let title: String
    /// True when the user named the session; false for names Claude Code derived itself.
    public let hasCustomName: Bool
    public let activity: SessionActivity
    public let statusSince: Date?
    public let isInteractive: Bool

    public init(record: SessionRecord, account: String) {
        let project = URL(filePath: record.cwd).lastPathComponent
        let sinceMillis = record.statusUpdatedAt ?? record.updatedAt ?? record.startedAt

        id = "\(account)/\(record.sessionId)"
        self.account = account
        pid = record.pid
        sessionId = record.sessionId
        cwd = record.cwd
        projectName = project
        title = TrackedSession.title(record: record, project: project)
        hasCustomName = title != project
        activity = SessionActivity(status: record.status, waitingFor: record.waitingFor)
        statusSince = sinceMillis.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
        isInteractive = (record.kind ?? "interactive") == "interactive"
    }

    /// Claude Code derives placeholder names like `orbit-ba` from the folder
    /// (`nameSource: "derived"`); those add nothing over the folder name itself.
    private static func title(record: SessionRecord, project: String) -> String {
        let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || record.nameSource == "derived" ? project : name
    }
}
