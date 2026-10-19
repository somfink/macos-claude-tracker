import Foundation
import Observation
import os
import TrackerCore

/// Live list of Claude Code sessions. Refreshes on FSEvents from every `sessions/` directory,
/// plus a slow poll that drops sessions whose process died without cleaning up its file.
@MainActor
@Observable
final class SessionStore {
    private static let livenessPollInterval: Duration = .seconds(5)
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "sessions")

    private(set) var snapshot: SessionSnapshot = .empty
    private(set) var roots: [ConfigRoot] = []
    private(set) var details: [String: SessionDetail] = [:]
    private(set) var unread: UnreadState = .empty
    private(set) var lastRefresh: Date?

    var summary: StatusSummary { StatusSummary(activities: snapshot.sessions.map(\.activity)) }

    /// Called after every refresh that produced transitions, with details already updated.
    @ObservationIgnored var onEvents: (([SessionEvent]) -> Void)?

    @ObservationIgnored private let loader: SessionSnapshotLoader
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let unreadURL: URL
    @ObservationIgnored private let transcripts = TranscriptCache()
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        loader: SessionSnapshotLoader = SessionSnapshotLoader(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.loader = loader
        self.home = home
        unreadURL = TrackerPaths.unreadState(home: home)
        unread = UnreadState.load(from: unreadURL)
    }

    isolated deinit { pollTask?.cancel() }

    /// Idempotent: safe to call more than once.
    func start() {
        guard pollTask == nil else { return }
        watcher = DirectoryWatcher { [weak self] in self?.refresh() }
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.livenessPollInterval)
                self?.refresh()
            }
        }
    }

    func refresh() {
        let discovered = ConfigRoots.discover(home: home, environment: ProcessInfo.processInfo.environment)
        if discovered != roots {
            roots = discovered
            watcher?.watch(discovered.map(\.sessionsDirectory))
            Self.logger.info("Watching \(discovered.count) config dirs: \(discovered.map(\.account).joined(separator: ", "))")
        }

        let next = loader.load(from: discovered)
        logNewIssues(next.issues)

        let events = SessionEvents.diff(previous: snapshot.sessions, current: next.sessions)
        let liveIds = Set(next.sessions.map(\.id))
        let nextDetails = transcripts.details(for: next.sessions, roots: discovered)
        let nextUnread = unread.applying(events, liveIds: liveIds)

        if next != snapshot { snapshot = next }
        if nextDetails != details { details = nextDetails }
        setUnread(nextUnread)
        lastRefresh = Date()

        if !events.isEmpty { onEvents?(events) }
    }

    func session(withId id: String) -> TrackedSession? {
        snapshot.sessions.first { $0.id == id }
    }

    func displayTitle(of session: TrackedSession) -> String {
        session.displayTitle(aiTitle: details[session.id]?.aiTitle)
    }

    /// What the session's terminal tab may be titled, plus the other live sessions' titles
    /// for telling apart tabs that only show a shared folder.
    func tabTargets(of session: TrackedSession) -> (target: TabTarget, others: [TabTarget]) {
        let target = { (session: TrackedSession) in TabTarget(session: session, aiTitle: self.details[session.id]?.aiTitle) }
        return (target(session), snapshot.sessions.filter { $0.id != session.id }.map(target))
    }

    func markRead(_ id: String) {
        setUnread(unread.markingRead(id))
    }

    func markAllRead() {
        setUnread(unread.markingAllRead())
    }

    /// Persists every change so unread dots survive a restart.
    private func setUnread(_ next: UnreadState) {
        guard next != unread else { return }
        unread = next
        do {
            try next.write(to: unreadURL)
        } catch {
            Self.logger.error("Saving unread state failed: \(error.localizedDescription)")
        }
    }

    private func logNewIssues(_ issues: [LoadIssue]) {
        for issue in issues where !snapshot.issues.contains(issue) {
            Self.logger.error("Unreadable session file \(issue.file.path): \(issue.message)")
        }
    }
}
