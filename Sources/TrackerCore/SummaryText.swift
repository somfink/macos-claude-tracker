import Foundation

/// Flattens an assistant's markdown answer into one short line for a dashboard row.
public enum SummaryText {
    public static let defaultLimit = 180
    private static let lineJoiner = " · "
    private static let ellipsis = "…"

    public static func clean(_ markdown: String, limit: Int = defaultLimit) -> String {
        let lines = markdown
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }
        return truncate(lines.joined(separator: lineJoiner), limit: limit)
    }

    private static func cleanLine(_ line: String) -> String {
        let withoutLinks = line.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression
        )
        let withoutBlockMarkers = withoutLinks.replacingOccurrences(
            of: #"^\s*(#{1,6}\s+|>\s*|[-*+]\s+|\d+\.\s+)"#, with: "", options: .regularExpression
        )
        let withoutEmphasis = withoutBlockMarkers.replacingOccurrences(
            of: #"(\*\*|__|`|~~)"#, with: "", options: .regularExpression
        )
        return withoutEmphasis
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + ellipsis
    }
}
