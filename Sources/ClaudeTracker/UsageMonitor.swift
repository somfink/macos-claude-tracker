import Foundation
import Observation
import os
import TrackerCore

/// Rate limits, API-equivalent cost and today's finished sessions for the dashboard.
@MainActor
@Observable
final class UsageMonitor {
    private static let tick: Duration = .seconds(15)
    /// Cost scans run every `scanEveryTicks` ticks (1 min); limits are re-read every tick.
    private static let scanEveryTicks = 4
    private static let logger = Logger(subsystem: "dev.claude-tracker", category: "usage")

    private(set) var report: UsageReport?
    private(set) var sessionCosts: [String: Double] = [:]
    private(set) var finishedToday: [FinishedSession] = []
    private(set) var rateLimits: [String: AccountRateLimits] = [:]
    /// Context window usage in percent, keyed by Claude Code session id.
    private(set) var contextUsage: [String: Double] = [:]

    /// Called with limit thresholds crossed since the last check (80% / 90%).
    @ObservationIgnored var onLimitAlerts: (([LimitAlert]) -> Void)?

    @ObservationIgnored let scanner: UsageScanner
    @ObservationIgnored private let snapshotsDirectory: URL
    @ObservationIgnored private let alertStateURL: URL
    @ObservationIgnored private var alertState: LimitAlertState
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        scanner = UsageScanner(ledgerURL: TrackerPaths.usageLedger(home: home))
        snapshotsDirectory = TrackerPaths.statuslineSnapshots(home: home)
        alertStateURL = TrackerPaths.limitAlerts(home: home)
        alertState = LimitAlertState.load(from: alertStateURL)
    }

    isolated deinit { loop?.cancel() }

    /// Idempotent. Reads roots and live sessions from `store` on every pass.
    func start(store: SessionStore) {
        guard loop == nil else { return }
        loop = Task { [weak self, weak store] in
            var tickCount = 0
            while !Task.isCancelled {
                guard let self, let store else { return }
                refreshRateLimits()
                checkLimitAlerts()
                if tickCount % Self.scanEveryTicks == 0 { await scanCosts(store: store) }
                tickCount += 1
                try? await Task.sleep(for: Self.tick)
            }
        }
    }

    /// Re-reads the statusline tap snapshots: limits per account, context per session.
    func refreshRateLimits() {
        let next = RateLimitReader.read(directory: snapshotsDirectory, now: Date())
        if next != rateLimits { rateLimits = next }
        let context = ContextUsageReader.read(directory: snapshotsDirectory)
        if context != contextUsage { contextUsage = context }
    }

    func apply(_ result: UsageScanResult) {
        if result.report != report { report = result.report }
        if result.sessionCosts != sessionCosts { sessionCosts = result.sessionCosts }
        if result.finishedToday != finishedToday { finishedToday = result.finishedToday }
    }

    private func checkLimitAlerts() {
        let result = LimitAlerts.evaluate(limits: rateLimits, state: alertState)
        guard result.state != alertState else { return }
        alertState = result.state
        do {
            try result.state.write(to: alertStateURL)
        } catch {
            Self.logger.error("Saving limit alert state failed: \(error.localizedDescription)")
        }
        if !result.alerts.isEmpty { onLimitAlerts?(result.alerts) }
    }

    private func scanCosts(store: SessionStore) async {
        apply(await scanner.scan(roots: store.roots, sessionIds: store.snapshot.sessions.map(\.sessionId)))
    }
}
