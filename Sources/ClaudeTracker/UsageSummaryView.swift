import SwiftUI
import TrackerCore

/// Cost strip and limits card, stacked full-width under the status tiles.
struct UsageSummaryView: View {
    let monitor: UsageMonitor
    let now: Date

    var body: some View {
        VStack(spacing: 8) {
            CostStrip(report: monitor.report, now: now)
            LimitsCard(rateLimits: monitor.rateLimits, now: now)
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Cost

private struct CostStrip: View {
    let report: UsageReport?
    let now: Date

    var body: some View {
        Card {
            if let report {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(UsageFormat.usd(report.monthCost))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("tyle w \(UsageFormat.monthLocative(Calendar.current.component(.month, from: now))) kosztowałoby API")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let projection = report.projectedMonthCost(now: now, calendar: .current) {
                            Text("prognoza \(UsageFormat.usd(projection))")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .help("Koszt na koniec miesiąca przy dotychczasowym tempie")
                        }
                        Text("dziś \(UsageFormat.usd(report.todayCost))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Liczę koszt…").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .help("Szacunek według cennika API Anthropic (bez rabatów batch/priority), na podstawie transkryptów z ~/.claude*/projects")
    }
}

// MARK: Limits

private struct LimitsCard: View {
    let rateLimits: [String: AccountRateLimits]
    let now: Date

    var body: some View {
        Card {
            let accounts = rateLimits.keys.sorted()
            if accounts.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limity 5 h i tygodniowe pojawią się po podpięciu statusline:")
                        Text("scripts/install-statusline-tap.sh --apply").font(.caption2.monospaced())
                    }
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(accounts, id: \.self) { account in
                        if let limits = rateLimits[account] {
                            AccountLimitsView(account: accounts.count > 1 ? account : nil, limits: limits, now: now)
                        }
                    }
                }
            }
        }
    }
}

private struct AccountLimitsView: View {
    let account: String?
    let limits: AccountRateLimits
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let account {
                Text(account).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                if let fiveHour = limits.fiveHour {
                    LimitRow(title: "Limit 5 h", window: fiveHour, now: now)
                }
                if let sevenDay = limits.sevenDay {
                    LimitRow(title: "Limit tygodniowy", window: sevenDay, now: now)
                }
            }
        }
    }
}

private struct LimitRow: View {
    private static let segments = 10
    private static let warningThreshold = 70.0
    private static let criticalThreshold = 90.0

    let title: String
    let window: RateLimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(window.usedPercentage.rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            HStack(spacing: 2) {
                ForEach(0..<Self.segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < filledSegments ? color : Color.secondary.opacity(0.2))
                        .frame(height: 6)
                }
            }
            if let resetsAt = window.resetsAt {
                Text(window.isExpired ? "zresetowany" : "reset \(UsageFormat.countdown(to: resetsAt, now: now))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// At least one segment once anything is used, so 3% does not look like 0%.
    private var filledSegments: Int {
        let used = window.usedPercentage
        guard used > 0 else { return 0 }
        return max(1, min(Self.segments, Int((used / 100 * Double(Self.segments)).rounded())))
    }

    private var color: Color {
        switch window.usedPercentage {
        case Self.criticalThreshold...: .red
        case Self.warningThreshold...: .orange
        default: .primary
        }
    }
}
