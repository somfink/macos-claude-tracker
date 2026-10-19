import Foundation
import os
import TrackerCore
import WidgetKit

/// Feeds the desktop widget: writes a `WidgetSnapshot` into the App Group container and
/// asks WidgetKit to reload. Inert when the app runs without the App Group entitlement
/// (e.g. `swift run`), since the sandboxed widget could not read the file anyway.
@MainActor
final class WidgetPublisher {
    private static let tick: Duration = .seconds(10)
    /// WidgetKit budgets reloads; status changes faster than this are batched.
    private static let minReloadInterval: TimeInterval = 60
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "widget")

    private let snapshotURL: URL?
    private var lastPublished: WidgetSnapshot?
    private var lastReload = Date.distantPast
    /// A newer snapshot is on disk but its reload was throttled; flushed by a later tick.
    private var pendingReload = false
    private var loop: Task<Void, Never>?

    init(snapshotURL: URL? = AppGroup.snapshotURL()) {
        self.snapshotURL = snapshotURL
        if snapshotURL == nil { Self.logger.info("No App Group container: widget publishing disabled") }
    }

    isolated deinit { loop?.cancel() }

    /// Idempotent.
    func start(store: SessionStore, usage: UsageMonitor) {
        guard loop == nil, snapshotURL != nil else { return }
        loop = Task { [weak self, weak store, weak usage] in
            while !Task.isCancelled {
                guard let self, let store, let usage else { return }
                publish(store: store, usage: usage)
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    func publish(store: SessionStore, usage: UsageMonitor) {
        guard let snapshotURL else { return }
        let sessions = store.snapshot.sessions
        let snapshot = WidgetSnapshot.make(
            sessions: sessions,
            titles: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, store.displayTitle(of: $0)) }),
            unread: store.unread,
            rateLimits: usage.rateLimits,
            report: usage.report,
            now: Date()
        )
        if lastPublished?.hasSameContent(as: snapshot) != true {
            do {
                try snapshot.write(to: snapshotURL)
                lastPublished = snapshot
                pendingReload = true
            } catch {
                Self.logger.error("Writing widget snapshot failed: \(error.localizedDescription)")
                return
            }
        }
        if pendingReload { reloadIfAllowed() }
    }

    private func reloadIfAllowed() {
        let now = Date()
        guard now.timeIntervalSince(lastReload) >= Self.minReloadInterval else { return }
        lastReload = now
        pendingReload = false
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.sessions)
    }
}
