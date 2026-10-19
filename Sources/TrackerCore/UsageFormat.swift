import Foundation

/// Polish labels for limits and API-equivalent cost.
public enum UsageFormat {
    private static let minute = 60
    private static let hour = 3_600
    private static let day = 86_400
    /// Below this, cents matter; above, whole dollars read better.
    private static let centsThreshold = 100.0
    /// Narrow no-break space, like the reference dashboard's `$3 830`.
    private static let thousandsSeparator = "\u{202F}"

    /// `za 12 min`, `za 2 h 43 min`, `za 4 d 3 h`.
    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        switch seconds {
        case ..<0: return "teraz"
        case ..<minute: return "za chwilę"
        case ..<hour: return "za \(seconds / minute) min"
        case ..<day: return "za " + pair(seconds / hour, "h", (seconds % hour) / minute, "min")
        default: return "za " + pair(seconds / day, "d", (seconds % day) / hour, "h")
        }
    }

    public static func usd(_ amount: Double) -> String {
        if amount < 0.005 { return "$0" }
        if amount < centsThreshold { return String(format: "$%.2f", amount) }
        let digits = String(Int(amount.rounded()))
        let groups = stride(from: digits.count, to: 0, by: -3).reversed().map { end in
            let start = max(end - 3, 0)
            let lower = digits.index(digits.startIndex, offsetBy: start)
            let upper = digits.index(digits.startIndex, offsetBy: end)
            return String(digits[lower..<upper])
        }
        return "$" + groups.joined(separator: thousandsSeparator)
    }

    /// Month name after "w": `w październiku`.
    public static func monthLocative(_ month: Int) -> String {
        let names = [
            "styczniu", "lutym", "marcu", "kwietniu", "maju", "czerwcu",
            "lipcu", "sierpniu", "wrześniu", "październiku", "listopadzie", "grudniu",
        ]
        return names.indices.contains(month - 1) ? names[month - 1] : "tym miesiącu"
    }

    private static func pair(_ major: Int, _ majorUnit: String, _ minor: Int, _ minorUnit: String) -> String {
        minor == 0 ? "\(major) \(majorUnit)" : "\(major) \(majorUnit) \(minor) \(minorUnit)"
    }
}
