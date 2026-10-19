import Foundation

/// Everything the sandboxed widget shows. The app writes it into the shared App Group
/// container; the widget cannot read `~/.claude*` itself.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let project: String
        public let mood: MascotMood
        public let statusLabel: String
        public let isUnread: Bool
        public let statusSince: Date?
    }

    public struct Limits: Codable, Equatable, Sendable {
        public let account: String
        public let fiveHourPercentage: Double?
        public let fiveHourResetsAt: Date?
        public let weeklyPercentage: Double?
        public let weeklyResetsAt: Date?
    }

    public let generatedAt: Date
    public let waiting: Int
    public let working: Int
    public let ready: Int
    public let total: Int
    public let mood: MascotMood
    public let sessions: [Session]
    public let limits: [Limits]
    public let monthCost: Double?
    public let todayCost: Double?

    public static let fileName = "widget-snapshot.json"
    public static let defaultSessionLimit = 7

    /// Same as `==` minus `generatedAt`: decides whether rewriting/reloading is worth it.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        waiting == other.waiting && working == other.working && ready == other.ready
            && total == other.total && sessions == other.sessions && limits == other.limits
            && monthCost == other.monthCost && todayCost == other.todayCost
    }

    // MARK: Building

    public static func make(
        sessions: [TrackedSession],
        titles: [String: String],
        unread: UnreadState,
        rateLimits: [String: AccountRateLimits],
        report: UsageReport?,
        now: Date,
        sessionLimit: Int = defaultSessionLimit
    ) -> WidgetSnapshot {
        let summary = StatusSummary(activities: sessions.map(\.activity))
        return WidgetSnapshot(
            generatedAt: now,
            waiting: summary.waiting,
            working: summary.working,
            ready: summary.ready,
            total: summary.total,
            mood: MascotMood(summary: summary),
            sessions: sessions.prefix(sessionLimit).map { session in
                Session(
                    id: session.id,
                    title: titles[session.id] ?? session.title,
                    project: session.projectName,
                    mood: MascotMood(activity: session.activity),
                    statusLabel: ActivityText.label(for: session.activity),
                    isUnread: unread.contains(session.id),
                    statusSince: session.statusSince
                )
            },
            limits: rateLimits.keys.sorted().compactMap { account in
                rateLimits[account].map { limits in
                    Limits(
                        account: account,
                        fiveHourPercentage: limits.fiveHour?.usedPercentage,
                        fiveHourResetsAt: limits.fiveHour?.resetsAt,
                        weeklyPercentage: limits.sevenDay?.usedPercentage,
                        weeklyResetsAt: limits.sevenDay?.resetsAt
                    )
                }
            },
            monthCost: report?.monthCost,
            todayCost: report?.todayCost
        )
    }

    // MARK: Storage

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

extension MascotMood: Codable {}

/// `claudetracker://session/<url-encoded session id>`: opened by the widget, handled by the app.
public enum WidgetLink {
    public static let scheme = "claudetracker"
    private static let sessionHost = "session"

    public static func url(forSessionId id: String) -> URL? {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) else {
            return nil
        }
        return URL(string: "\(scheme)://\(sessionHost)/\(encoded)")
    }

    public static func sessionId(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == sessionHost else { return nil }
        let raw = url.path(percentEncoded: true).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty, let decoded = raw.removingPercentEncoding else { return nil }
        return decoded
    }
}

/// Info.plist key holding the App Group id (`<TeamID>.dev.claude-tracker`), filled in by
/// `scripts/bundle.sh` from the signing certificate so no team id is hard-coded.
public enum AppGroup {
    public static let infoPlistKey = "ClaudeTrackerAppGroup"

    public static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !value.isEmpty, !value.hasPrefix("__")
        else { return nil }
        return value
    }

    public static func snapshotURL() -> URL? {
        guard let identifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return container.appending(path: WidgetSnapshot.fileName)
    }
}

/// Widget kinds, shared by the extension (declaration) and the app (reload requests).
public enum WidgetKind {
    public static let sessions = "dev.claude-tracker.sessions"
}
