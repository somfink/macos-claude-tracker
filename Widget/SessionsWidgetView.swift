import SwiftUI
import WidgetKit

struct SessionsWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily

    let entry: SnapshotEntry
    /// Previews render outside WidgetKit, where the family cannot be injected.
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: SmallLayout(snapshot: snapshot)
            case .systemLarge:
                ListLayout(snapshot: snapshot, now: entry.date, rows: 7, showsUsage: true, linksRows: familyOverride == nil)
            default:
                ListLayout(snapshot: snapshot, now: entry.date, rows: 3, showsUsage: false, linksRows: familyOverride == nil)
            }
        } else {
            VStack(spacing: 6) {
                PixelSpriteView(mood: .sleeping, pixelSize: 2)
                Text("Uruchom Claude Tracker").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Layouts

private struct SmallLayout: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                PixelSpriteView(mood: snapshot.mood, pixelSize: 2.5)
                Spacer()
                Text(PolishPlural.sessions(snapshot.total))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Counters(snapshot: snapshot, compact: true)
        }
        .widgetURL(snapshot.sessions.first.flatMap { WidgetLink.url(forSessionId: $0.id) })
    }
}

private struct ListLayout: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let rows: Int
    let showsUsage: Bool
    /// False only in offscreen previews, which cannot draw `Link`.
    let linksRows: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Counters(snapshot: snapshot, compact: false)
                Spacer()
                // Large layouts show the cost in their footer instead.
                if !showsUsage, let cost = snapshot.monthCost {
                    Text(UsageFormat.usd(cost))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if showsUsage, let limits = snapshot.limits.first {
                LimitsLine(limits: limits, now: now)
            }
            ForEach(snapshot.sessions.prefix(rows)) { session in
                if linksRows, let url = WidgetLink.url(forSessionId: session.id) {
                    Link(destination: url) { SessionLine(session: session, now: now) }
                } else {
                    SessionLine(session: session, now: now)
                }
            }
            Spacer(minLength: 0)
            if showsUsage, let month = snapshot.monthCost {
                CostFooter(month: month, today: snapshot.todayCost, now: now)
            }
        }
    }
}

private struct CostFooter: View {
    let month: Double
    let today: Double?
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(UsageFormat.usd(month)).font(.system(size: 15, weight: .bold, design: .rounded))
            Text("w \(UsageFormat.monthLocative(Calendar.current.component(.month, from: now))) wg cennika API")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer()
            if let today {
                Text("dziś \(UsageFormat.usd(today))").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Pieces

private struct Counters: View {
    let snapshot: WidgetSnapshot
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            counter(snapshot.waiting, "czeka", .orange)
            counter(snapshot.working, "pracuje", .blue)
            counter(snapshot.ready, "gotowe", .green)
        }
    }

    private func counter(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: compact ? 18 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct SessionLine: View {
    let session: WidgetSnapshot.Session
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            PixelSpriteView(mood: session.mood, pixelSize: 1)
            if session.isUnread {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
            }
            Text(session.title)
                .font(.system(size: 11, weight: session.isUnread ? .bold : .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(session.statusLabel)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
            if let since = session.statusSince {
                Text(RelativeAge.format(since, now: now))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var color: Color {
        switch session.mood {
        case .waiting: .orange
        case .working: .blue
        case .ready: .green
        case .sleeping: .secondary
        }
    }
}

private struct LimitsLine: View {
    let limits: WidgetSnapshot.Limits
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            if let five = limits.fiveHourPercentage {
                gauge("5 h", five, limits.fiveHourResetsAt)
            }
            if let weekly = limits.weeklyPercentage {
                gauge("tydz.", weekly, limits.weeklyResetsAt)
            }
        }
    }

    private func gauge(_ label: String, _ percentage: Double, _ resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
                Text("\(Int(percentage.rounded()))%").font(.system(size: 9, weight: .semibold))
            }
            ProgressView(value: min(max(percentage, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(percentage >= 90 ? .red : percentage >= 70 ? .orange : .accentColor)
            if let resetsAt {
                Text(UsageFormat.countdown(to: resetsAt, now: now)).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Draws the first frame of a mood's sprite; widgets are static, so no animation.
struct PixelSpriteView: View {
    let mood: MascotMood
    let pixelSize: CGFloat

    var body: some View {
        let sprite = MascotSprites.frames(for: mood)[0]
        Canvas { context, _ in
            for (y, row) in sprite.rows.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let rgb = MascotPalette.colors[char] else { continue }
                    let rect = CGRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize, width: pixelSize, height: pixelSize)
                    context.fill(Path(rect), with: .color(Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)))
                }
            }
        }
        .frame(width: CGFloat(sprite.width) * pixelSize, height: CGFloat(sprite.height) * pixelSize)
        .accessibilityHidden(true)
    }
}
