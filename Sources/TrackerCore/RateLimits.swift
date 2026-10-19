import Foundation

/// One usage window (5-hour or weekly) as Claude Code reports it to the statusline.
public struct RateLimitWindow: Equatable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Date?
    /// The reset time has passed since the snapshot: the window started over.
    public let isExpired: Bool
}

public struct AccountRateLimits: Equatable, Sendable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?
    public let capturedAt: Date
}

/// Reads snapshots written by `scripts/statusline-tap.sh`:
/// `<directory>/<account>/<session_id>.json`, each the raw statusline input JSON.
/// Rate limits are per account, so the newest snapshot of each account wins.
public enum RateLimitReader {
    private struct Snapshot: Decodable {
        struct Limits: Decodable {
            let fiveHour: Window?
            let sevenDay: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
            }
        }

        struct Window: Decodable {
            let usedPercentage: Double?
            /// Unix seconds.
            let resetsAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case resetsAt = "resets_at"
            }
        }

        let rateLimits: Limits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }

    public static func read(directory: URL, now: Date) -> [String: AccountRateLimits] {
        let accounts = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        let pairs = accounts.compactMap { accountDir -> (String, AccountRateLimits)? in
            newest(in: accountDir, now: now).map { (accountDir.lastPathComponent, $0) }
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private static func newest(in accountDir: URL, now: Date) -> AccountRateLimits? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: accountDir, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (Date, Snapshot.Limits)? in
                guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      let data = try? Data(contentsOf: url),
                      let limits = (try? JSONDecoder().decode(Snapshot.self, from: data))?.rateLimits
                else { return nil }
                return (modified, limits)
            }
            .max { $0.0 < $1.0 }
            .map { modified, limits in
                AccountRateLimits(
                    fiveHour: window(limits.fiveHour, now: now),
                    sevenDay: window(limits.sevenDay, now: now),
                    capturedAt: modified
                )
            }
    }

    private static func window(_ raw: Snapshot.Window?, now: Date) -> RateLimitWindow? {
        guard let raw, let used = raw.usedPercentage else { return nil }
        let resetsAt = raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
        let expired = resetsAt.map { $0 <= now } ?? false
        return RateLimitWindow(usedPercentage: expired ? 0 : used, resetsAt: resetsAt, isExpired: expired)
    }
}

/// Context window usage per session, from the same statusline tap snapshots.
public enum ContextUsageReader {
    private struct Snapshot: Decodable {
        struct ContextWindow: Decodable {
            let usedPercentage: Double?
            let totalInputTokens: Double?
            let contextWindowSize: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case totalInputTokens = "total_input_tokens"
                case contextWindowSize = "context_window_size"
            }

            /// Older Claude Code versions omit the percentage but send the raw counts.
            var percentage: Double? {
                if let usedPercentage { return usedPercentage }
                guard let used = totalInputTokens, let size = contextWindowSize, size > 0 else { return nil }
                return used / size * 100
            }
        }

        let sessionId: String?
        let contextWindow: ContextWindow?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case contextWindow = "context_window"
        }
    }

    /// Keyed by Claude Code session id; sessions without context data are absent.
    public static func read(directory: URL) -> [String: Double] {
        let accounts = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let pairs = accounts
            .flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (String, Double)? in
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                      let id = snapshot.sessionId,
                      let percentage = snapshot.contextWindow?.percentage
                else { return nil }
                return (id, percentage)
            }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}
