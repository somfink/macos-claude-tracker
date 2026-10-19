import Foundation

/// API-equivalent spend for the dashboard.
public struct UsageReport: Equatable, Sendable {
    public struct DayCost: Equatable, Sendable, Identifiable {
        /// `yyyy-MM-dd`, local calendar.
        public let day: String
        public let cost: Double

        public var id: String { day }
    }

    public struct ProjectCost: Equatable, Sendable, Identifiable {
        public let project: String
        public let cost: Double

        public var id: String { project }
    }

    public let monthCost: Double
    public let todayCost: Double
    public let monthCostByAccount: [String: Double]
    /// Days of the current month with any spend, ascending.
    public let dailyCosts: [DayCost]
    /// Current month per project folder, highest first.
    public let projectCosts: [ProjectCost]

    public static let empty = UsageReport(monthCost: 0, todayCost: 0, monthCostByAccount: [:])

    private static let unknownProject = "inne"

    public init(
        monthCost: Double, todayCost: Double, monthCostByAccount: [String: Double],
        dailyCosts: [DayCost] = [], projectCosts: [ProjectCost] = []
    ) {
        self.monthCost = monthCost
        self.todayCost = todayCost
        self.monthCostByAccount = monthCostByAccount
        self.dailyCosts = dailyCosts
        self.projectCosts = projectCosts
    }

    public init(ledger: UsageLedger, now: Date, calendar: Calendar) {
        let today = UsageParser.dayKey(now, calendar: calendar)
        let monthPrefix = String(today.prefix(7))
        let inMonth: ([UsageLedger.FileEntry]) -> [UsageRecord] = { entries in
            UsageLedger.deduplicated(entries).values.filter { $0.day.hasPrefix(monthPrefix) }
        }

        // Dedupe per account: the same message id never spans accounts.
        let byAccount = Dictionary(grouping: ledger.files.values, by: \.account).mapValues(inMonth)
        let monthRecords = Array(byAccount.values.joined())

        let byDay = Dictionary(grouping: monthRecords, by: \.day)
            .map { DayCost(day: $0.key, cost: $0.value.reduce(0) { $0 + $1.cost }) }
            .sorted { $0.day < $1.day }
        let byProject = Dictionary(grouping: ledger.files.values) { entry in
            entry.cwd.map { URL(filePath: $0).lastPathComponent } ?? Self.unknownProject
        }
        .map { ProjectCost(project: $0.key, cost: inMonth($0.value).reduce(0) { $0 + $1.cost }) }
        .filter { $0.cost > 0 }
        .sorted { $0.cost > $1.cost }

        self.init(
            monthCost: monthRecords.reduce(0) { $0 + $1.cost },
            todayCost: monthRecords.filter { $0.day == today }.reduce(0) { $0 + $1.cost },
            monthCostByAccount: byAccount.mapValues { $0.reduce(0) { $0 + $1.cost } },
            dailyCosts: byDay,
            projectCosts: byProject
        )
    }

    /// First instant of the previous month: older transcripts cannot affect this month,
    /// and keeping one month back lets the ledger survive a month boundary cheaply.
    public static func scanWindowStart(now: Date, calendar: Calendar) -> Date {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
    }
}

extension UsageReport {
    /// Before this much of the month has passed, extrapolation is mostly noise.
    static let minimumElapsedForProjection: TimeInterval = 24 * 3_600

    /// Month-end spend if the pace so far continues; nil during the first day.
    public func projectedMonthCost(now: Date, calendar: Calendar) -> Double? {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        let elapsed = now.timeIntervalSince(month.start)
        guard elapsed >= Self.minimumElapsedForProjection, month.duration > 0 else { return nil }
        return max(monthCost, monthCost / min(elapsed / month.duration, 1))
    }
}
