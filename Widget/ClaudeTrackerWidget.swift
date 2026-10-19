import SwiftUI
import WidgetKit

// Built by scripts/bundle.sh together with Sources/TrackerCore/*.swift into one module,
// so core types are used directly (no `import TrackerCore`).

@main
struct ClaudeTrackerWidgets: WidgetBundle {
    var body: some Widget {
        SessionsWidget()
    }
}

struct SessionsWidget: Widget {
    static let kind = WidgetKind.sessions

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            SessionsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sesje Claude Code")
        .description("Co czeka na Ciebie, co pracuje i co już skończyło.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil until Claude Tracker has written its first snapshot.
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot the app writes to the App Group container. The app asks WidgetKit
/// to reload on changes; the 5-minute policy only backs that up.
struct SnapshotProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .preview : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let entry = SnapshotEntry(date: now, snapshot: load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }

    private func load() -> WidgetSnapshot? {
        AppGroup.snapshotURL().flatMap(WidgetSnapshot.read)
    }
}

extension WidgetSnapshot {
    /// Gallery preview: no user data.
    static let preview = WidgetSnapshot(
        generatedAt: Date(),
        waiting: 1, working: 2, ready: 3, total: 6, mood: .waiting,
        sessions: [
            Session(id: "p/1", title: "Naprawa logowania", project: "web-app", mood: .waiting,
                    statusLabel: "Czeka: dialog", isUnread: false, statusSince: Date().addingTimeInterval(-120)),
            Session(id: "p/2", title: "Refaktor API", project: "backend", mood: .working,
                    statusLabel: "Pracuje", isUnread: false, statusSince: Date().addingTimeInterval(-600)),
            Session(id: "p/3", title: "Release notes", project: "docs", mood: .ready,
                    statusLabel: "Gotowe", isUnread: true, statusSince: Date().addingTimeInterval(-3_600)),
        ],
        limits: [Limits(account: "private", fiveHourPercentage: 34, fiveHourResetsAt: Date().addingTimeInterval(9_000),
                        weeklyPercentage: 19, weeklyResetsAt: Date().addingTimeInterval(360_000))],
        monthCost: 1_092, todayCost: 111
    )
}
