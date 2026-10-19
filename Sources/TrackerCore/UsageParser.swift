import Foundation

/// Priced usage of one assistant message.
public struct UsageRecord: Codable, Equatable, Sendable {
    public let messageId: String
    /// Local calendar day, `yyyy-MM-dd`.
    public let day: String
    public let cost: Double
    public let model: String
}

/// Extracts priced usage from transcript JSONL. Each content block of a response is its
/// own line carrying the same `message.id` and usage; callers dedupe by id.
public enum UsageParser {
    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let usageMarker = Data(#""usage""#.utf8)

    private struct Line: Decodable {
        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: TokenUsage?
        }

        let timestamp: String?
        let cwd: String?
        let entrypoint: String?
        let message: Message?
    }

    /// Context of the newest parsed assistant line in a chunk.
    public struct ChunkInfo: Equatable, Sendable {
        public let cwd: String?
        /// `cli` for terminal sessions, `sdk-*` for scripted Agent SDK runs.
        public let entrypoint: String?
    }

    /// `data` must contain whole lines; unparseable lines and unpriced models are skipped.
    public static func records(in data: Data, calendar: Calendar) -> [UsageRecord] {
        parse(data, calendar: calendar).records
    }

    /// Records plus where and how the newest parsed assistant line ran.
    public static func parse(_ data: Data, calendar: Calendar) -> (records: [UsageRecord], info: ChunkInfo) {
        let parser = TimestampParser()
        let decoder = JSONDecoder()
        let lines = data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .compactMap { line in decodeLine(line, decoder: decoder) }
        let records = lines.compactMap { record(from: $0, parser: parser, calendar: calendar) }
        let info = ChunkInfo(
            cwd: lines.last { $0.cwd != nil }?.cwd,
            entrypoint: lines.last { $0.entrypoint != nil }?.entrypoint
        )
        return (records, info)
    }

    private static let entrypointMarker = Data(#""entrypoint""#.utf8)

    private struct InfoLine: Decodable {
        let cwd: String?
        let entrypoint: String?
    }

    /// cwd / entrypoint from the first lines of any type that carry them. Only used while a
    /// transcript's metadata is still unknown, so the extra decoding stays rare.
    public static func firstInfo(in data: Data) -> ChunkInfo {
        let decoder = JSONDecoder()
        let lines = data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .lazy
            .filter { $0.range(of: entrypointMarker) != nil }
            .compactMap { try? decoder.decode(InfoLine.self, from: Data($0)) }
        let first = lines.first { $0.entrypoint != nil || $0.cwd != nil }
        return ChunkInfo(cwd: first?.cwd, entrypoint: first?.entrypoint)
    }

    private static func decodeLine(_ line: Data.SubSequence, decoder: JSONDecoder) -> Line? {
        guard line.range(of: assistantMarker) != nil, line.range(of: usageMarker) != nil else { return nil }
        return try? decoder.decode(Line.self, from: Data(line))
    }

    private static func record(from decoded: Line, parser: TimestampParser, calendar: Calendar) -> UsageRecord? {
        guard let message = decoded.message,
              let id = message.id, let model = message.model, let usage = message.usage,
              let cost = Pricing.cost(of: usage, model: model),
              let timestamp = decoded.timestamp.flatMap(parser.date)
        else { return nil }
        return UsageRecord(messageId: id, day: dayKey(timestamp, calendar: calendar), cost: cost, model: model)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// ISO-8601 with or without fractional seconds (`2026-10-18T09:00:00.123Z`).
private struct TimestampParser {
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let whole = ISO8601DateFormatter()

    func date(_ value: String) -> Date? {
        fractional.date(from: value) ?? whole.date(from: value)
    }
}
