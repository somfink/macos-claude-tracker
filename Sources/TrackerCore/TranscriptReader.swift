import Foundation

public struct TranscriptSummary: Equatable, Sendable {
    /// Text of the newest main-thread assistant block, raw markdown.
    public let lastAssistantText: String?
    /// Session title Claude Code generated (`ai-title` entries); newest wins.
    public let aiTitle: String?

    public static let empty = TranscriptSummary(lastAssistantText: nil, aiTitle: nil)
}

/// Pulls the last answer and the AI title out of a transcript by reading only its tail.
/// Transcripts reach many megabytes; the newest entries are all the dashboard needs.
public enum TranscriptReader {
    public static let defaultInitialTailBytes = 256 * 1_024
    public static let defaultMaxTailBytes = 2 * 1_024 * 1_024

    /// The window doubles until an assistant text shows up or `maxTailBytes` is reached.
    public static func summary(
        of url: URL,
        initialTailBytes: Int = defaultInitialTailBytes,
        maxTailBytes: Int = defaultMaxTailBytes
    ) -> TranscriptSummary {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd() else { return .empty }

        return scan(handle: handle, fileSize: Int(fileSize), window: initialTailBytes, maxWindow: maxTailBytes)
    }

    private static func scan(handle: FileHandle, fileSize: Int, window: Int, maxWindow: Int) -> TranscriptSummary {
        let length = min(window, fileSize)
        guard (try? handle.seek(toOffset: UInt64(fileSize - length))) != nil,
              let data = try? handle.read(upToCount: length)
        else { return .empty }

        let summary = parse(tail: data, startsMidLine: length < fileSize)
        let canGrow = length < fileSize && window < maxWindow
        guard summary.lastAssistantText == nil, canGrow else { return summary }
        return scan(handle: handle, fileSize: fileSize, window: min(window * 2, maxWindow), maxWindow: maxWindow)
    }

    static func parse(tail: Data, startsMidLine: Bool) -> TranscriptSummary {
        let lines = tail.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        let complete = startsMidLine ? lines.dropFirst() : lines[...]
        let newestFirst = complete.reversed()

        let text = newestFirst.lazy.compactMap(assistantText).first
        let title = newestFirst.lazy.compactMap(aiTitle).first
        return TranscriptSummary(lastAssistantText: text, aiTitle: title)
    }

    // MARK: Line decoding

    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let titleMarker = Data(#""type":"ai-title""#.utf8)

    private struct AssistantLine: Decodable {
        struct Message: Decodable { let content: [Block]? }
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let isSidechain: Bool?
        let message: Message?
    }

    private struct TitleLine: Decodable { let aiTitle: String? }

    /// Cheap byte search before JSON decoding: most tail lines are tool output and attachments.
    private static func assistantText(_ line: Data.SubSequence) -> String? {
        guard line.range(of: assistantMarker) != nil,
              let decoded = try? JSONDecoder().decode(AssistantLine.self, from: Data(line)),
              decoded.isSidechain != true
        else { return nil }
        let text = (decoded.message?.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func aiTitle(_ line: Data.SubSequence) -> String? {
        guard line.range(of: titleMarker) != nil,
              let title = (try? JSONDecoder().decode(TitleLine.self, from: Data(line)))?.aiTitle?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return title
    }
}
