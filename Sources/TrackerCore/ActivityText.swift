/// Polish UI labels for session activity.
public enum ActivityText {
    /// Short forms for the `waitingFor` values Claude Code 2.1.x writes.
    private static let waitingReasons: [String: String] = [
        "dialog open": "dialog",
        "input needed": "odpowiedź",
        "sandbox request": "sandbox",
        "goal proposal": "propozycja celu",
    ]

    public static func label(for activity: SessionActivity) -> String {
        switch activity {
        case .working: "Pracuje"
        case .ready: "Gotowe"
        case .backgroundTask: "Gotowe · bash w tle"
        case .waiting(nil): "Czeka na Ciebie"
        case .waiting(let reason?): "Czeka: \(waitingReasons[reason] ?? reason)"
        case .unknown(let raw): raw
        }
    }
}
