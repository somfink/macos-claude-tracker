/// What a session is doing, reduced to the states the dashboard cares about.
public enum SessionActivity: Equatable, Hashable, Sendable {
    /// Blocked on the user: permission dialog, question, sandbox request.
    case waiting(reason: String?)
    /// Model turn in progress.
    case working
    /// Turn finished, prompt is free.
    case ready
    /// Turn finished but a background bash task (dev server, watcher) is still running.
    /// The prompt is free, so the dashboard groups it with `ready`.
    case backgroundTask
    /// Status Claude Code wrote that this app does not know yet.
    case unknown(String)

    public init(status: String?, waitingFor: String?) {
        switch status {
        case "waiting": self = .waiting(reason: waitingFor)
        case "busy": self = .working
        case "shell": self = .backgroundTask
        case "idle": self = .ready
        case let other?: self = .unknown(other)
        case nil: self = .unknown("—")
        }
    }

    /// Lower sorts first: what needs attention goes on top.
    public var sortPriority: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .ready, .backgroundTask: 2
        case .unknown: 3
        }
    }
}
