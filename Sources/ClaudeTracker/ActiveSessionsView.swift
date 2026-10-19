import SwiftUI
import TrackerCore

/// "Aktywne" tab: status tiles, cost and limits, the live session list.
struct ActiveSessionsView: View {
    let store: SessionStore
    let usage: UsageMonitor
    let isSnapshot: Bool

    var body: some View {
        // Re-render every 30 s so ages, countdowns and stall labels stay current.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                StatusTiles(summary: store.summary)
                UsageSummaryView(monitor: usage, now: context.date)
                Divider()
                sessionList(now: context.date)
            }
        }
    }

    @ViewBuilder
    private func sessionList(now: Date) -> some View {
        if store.snapshot.sessions.isEmpty {
            ContentUnavailableView(
                "Brak otwartych sesji",
                systemImage: "moon.zzz",
                description: Text("Odpal `claude` w terminalu, a sesja pojawi się tutaj.")
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            PanelList(isSnapshot: isSnapshot) {
                ForEach(store.snapshot.sessions) { session in
                    SessionRowView(
                        session: session,
                        title: store.displayTitle(of: session),
                        summary: store.details[session.id]?.summary,
                        isUnread: store.unread.contains(session.id),
                        cost: usage.sessionCosts[session.sessionId],
                        contextPercentage: usage.contextUsage[session.sessionId],
                        stalledSince: Stall.since(
                            activity: session.activity, lastActivity: store.details[session.id]?.lastActivity, now: now
                        ),
                        showAccount: store.snapshot.spansMultipleAccounts,
                        now: now,
                        onOpen: { open(session) }
                    )
                }
            }
        }
    }

    private func open(_ session: TrackedSession) {
        store.markRead(session.id)
        TerminalActivator.focus(sessionPid: session.pid, tab: store.tabTargets(of: session))
    }
}

/// Three colored counters, like the left column of the reference dashboard.
private struct StatusTiles: View {
    let summary: StatusSummary

    var body: some View {
        HStack(spacing: 8) {
            tile(count: summary.waiting, label: "czeka", symbol: ActivityStyle.waitingSymbol, color: ActivityStyle.waitingColor)
            tile(count: summary.working, label: "pracuje", symbol: ActivityStyle.workingSymbol, color: ActivityStyle.workingColor)
            tile(count: summary.ready, label: "gotowe", symbol: ActivityStyle.readySymbol, color: ActivityStyle.readyColor)
        }
    }

    /// Same symbols as the menu bar item, so the two read as one system.
    private func tile(count: Int, label: String, symbol: String, color: Color) -> some View {
        let active = count > 0
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text(label).font(.caption)
            }
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .opacity(active ? 0.9 : 0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .foregroundStyle(active ? Color.white : Color.secondary)
        .background(active ? color : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
