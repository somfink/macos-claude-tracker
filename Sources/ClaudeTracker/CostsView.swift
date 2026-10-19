import Charts
import SwiftUI
import TrackerCore

/// "Koszty" tab: month total and projection, spend per day, top projects.
/// Single series, so one hue and no legend; text stays in text colors.
struct CostsView: View {
    private static let topProjects = 8

    let report: UsageReport?
    let now: Date

    var body: some View {
        if let report {
            VStack(alignment: .leading, spacing: 14) {
                headline(report)
                DailyChart(days: report.dailyCosts, now: now)
                ProjectList(projects: Array(report.projectCosts.prefix(Self.topProjects)), total: report.monthCost)
                if report.monthCostByAccount.count > 1 {
                    accounts(report)
                }
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Liczę koszt…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private func headline(_ report: UsageReport) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(UsageFormat.usd(report.monthCost))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("w \(UsageFormat.monthLocative(Calendar.current.component(.month, from: now))) wg cennika API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let projection = report.projectedMonthCost(now: now, calendar: .current) {
                    Text("prognoza \(UsageFormat.usd(projection))").font(.callout.weight(.semibold)).monospacedDigit()
                }
                Text("dziś \(UsageFormat.usd(report.todayCost))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func accounts(_ report: UsageReport) -> some View {
        HStack(spacing: 12) {
            ForEach(report.monthCostByAccount.sorted { $0.value > $1.value }, id: \.key) { account, cost in
                Text("\(account): \(UsageFormat.usd(cost))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DailyChart: View {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    let days: [UsageReport.DayCost]
    let now: Date

    @State private var selectedDay: Date?

    private var points: [(date: Date, cost: Double)] {
        days.compactMap { day in Self.parser.date(from: day.day).map { ($0, day.cost) } }
    }

    private var monthRange: ClosedRange<Date> {
        let month = Calendar.current.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 1)
        return month.start...month.end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Dziennie").font(.caption.weight(.semibold))
                Spacer()
                if let selected = selectedPoint {
                    Text("\(selected.date.formatted(.dateTime.day().month(.wide))): \(UsageFormat.usd(selected.cost))")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            Chart(points, id: \.date) { point in
                BarMark(
                    x: .value("Dzień", point.date, unit: .day),
                    y: .value("Koszt", point.cost),
                    width: .ratio(0.7)
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                .foregroundStyle(Color.accentColor.opacity(isDimmed(point.date) ? 0.35 : 1))
            }
            .chartXScale(domain: monthRange)
            .chartXSelection(value: $selectedDay)
            .chartXAxis {
                AxisMarks(values: weeklyTicks) { _ in
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel { if let cost = value.as(Double.self) { Text(UsageFormat.usd(cost)) } }
                }
            }
            .frame(height: 120)
        }
    }

    /// Days 1, 8, 15, 22, 29 at noon: a label sits under the middle of its day's bar
    /// (stride marks with `centered` would center over the whole week instead).
    private var weeklyTicks: [Date] {
        let calendar = Calendar.current
        let start = monthRange.lowerBound
        return stride(from: 0, to: 31, by: 7).compactMap { offset in
            calendar.date(byAdding: DateComponents(day: offset, hour: 12), to: start)
        }
        .filter { $0 < monthRange.upperBound }
    }

    private var selectedPoint: (date: Date, cost: Double)? {
        guard let selectedDay else { return nil }
        return points.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
    }

    /// While hovering, the other days recede so the selected one stands out.
    private func isDimmed(_ date: Date) -> Bool {
        guard let selectedDay else { return false }
        return !Calendar.current.isDate(date, inSameDayAs: selectedDay)
    }
}

private struct ProjectList: View {
    let projects: [UsageReport.ProjectCost]
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projekty w tym miesiącu").font(.caption.weight(.semibold))
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(project.project).font(.caption).lineLimit(1)
                        Spacer()
                        Text(UsageFormat.usd(project.cost)).font(.caption.weight(.medium)).monospacedDigit()
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: max(2, geometry.size.width * share(project)))
                    }
                    .frame(height: 3)
                }
            }
        }
    }

    private func share(_ project: UsageReport.ProjectCost) -> CGFloat {
        total > 0 ? CGFloat(project.cost / total) : 0
    }
}
