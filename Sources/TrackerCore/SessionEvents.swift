import Foundation

/// A status change worth reacting to (notification, unread badge).
public enum SessionEvent: Equatable, Hashable, Sendable {
    /// A model turn ended: there is a new answer to read.
    case finished(id: String)
    /// The session just started blocking on the user.
    case needsInput(id: String)
    /// The session went back to work; whatever it said before is superseded.
    case resumed(id: String)

    public var sessionId: String {
        switch self {
        case .finished(let id), .needsInput(let id), .resumed(let id): id
        }
    }
}

public enum SessionEvents {
    /// Compares two consecutive snapshots. Sessions that appear or vanish produce nothing:
    /// only transitions observed while the app was watching count.
    public static func diff(previous: [TrackedSession], current: [TrackedSession]) -> [SessionEvent] {
        let before = Dictionary(previous.map { ($0.id, $0.activity) }, uniquingKeysWith: { first, _ in first })
        return current.compactMap { session in
            before[session.id].flatMap { event(from: $0, to: session.activity, id: session.id) }
        }
    }

    private static func event(from old: SessionActivity, to new: SessionActivity, id: String) -> SessionEvent? {
        switch (old, new) {
        case (.waiting, .waiting):
            nil
        case (_, .waiting):
            .needsInput(id: id)
        case (.working, .ready), (.working, .backgroundTask):
            .finished(id: id)
        case (.working, .working):
            nil
        case (_, .working):
            .resumed(id: id)
        default:
            nil
        }
    }
}

/// Sessions with an answer the user has not looked at yet. Immutable: every change returns a copy.
public struct UnreadState: Equatable, Sendable {
    public let ids: Set<String>

    public static let empty = UnreadState(ids: [])

    public init(ids: Set<String>) {
        self.ids = ids
    }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    public func applying(_ events: [SessionEvent], liveIds: Set<String>) -> UnreadState {
        let finished = Set(events.compactMap { if case .finished(let id) = $0 { id } else { nil } })
        let resumed = Set(events.compactMap { if case .resumed(let id) = $0 { id } else { nil } })
        return UnreadState(ids: ids.union(finished).subtracting(resumed).intersection(liveIds))
    }

    public func markingRead(_ id: String) -> UnreadState {
        UnreadState(ids: ids.subtracting([id]))
    }

    public func markingAllRead() -> UnreadState { .empty }
}

extension TrackedSession {
    /// User-set session name, else Claude's generated title, else the project folder.
    public func displayTitle(aiTitle: String?) -> String {
        if hasCustomName { return title }
        return aiTitle ?? projectName
    }
}

extension UnreadState: Codable {
    private enum CodingKeys: String, CodingKey { case ids }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ids: try container.decode(Set<String>.self, forKey: .ids))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ids.sorted(), forKey: .ids)
    }

    /// Unread dots survive app restarts; a missing or damaged file just means nothing unread.
    public static func load(from url: URL) -> UnreadState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(UnreadState.self, from: data)
        else { return .empty }
        return state
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
