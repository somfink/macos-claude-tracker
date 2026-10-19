import Foundation

/// Raw contents of `<config>/sessions/<pid>.json`, written by every running Claude Code process.
///
/// The format is internal to Claude Code and undocumented, so everything except the
/// identity fields is optional and unknown keys are ignored.
public struct SessionRecord: Decodable, Equatable, Sendable {
    public let pid: Int32
    public let sessionId: String
    public let cwd: String
    public let name: String?
    /// `derived` when Claude Code generated the name from the folder, otherwise user-set.
    public let nameSource: String?
    public let status: String?
    public let waitingFor: String?
    public let kind: String?
    public let entrypoint: String?
    public let version: String?
    /// Process start time as printed by `ps -o lstart` in UTC, e.g. `Sat Oct 17 18:39:33 2026`.
    public let procStart: String?
    /// Unix epoch milliseconds.
    public let startedAt: Int64?
    public let updatedAt: Int64?
    public let statusUpdatedAt: Int64?

    public static func decode(from data: Data) throws -> SessionRecord {
        try JSONDecoder().decode(SessionRecord.self, from: data)
    }
}
