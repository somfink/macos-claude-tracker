import Foundation

/// Finds `<config>/projects/<slug>/<sessionId>.jsonl`, the transcript Claude Code appends to.
public enum TranscriptLocator {
    static let projectsDirName = "projects"
    static let transcriptExtension = "jsonl"

    /// Claude Code names project folders after the cwd with every character outside
    /// `[A-Za-z0-9]` replaced by `-` (per UTF-16 unit, like the JS regex it uses).
    public static func projectSlug(for cwd: String) -> String {
        String(decoding: cwd.utf16.map { unit in isAsciiAlphanumeric(unit) ? unit : UInt16(UInt8(ascii: "-")) }, as: UTF16.self)
    }

    /// Expected location first; otherwise scan project folders (the cwd may have changed
    /// mid-session, e.g. after entering a worktree).
    public static func locate(sessionId: String, cwd: String, configDirectory: URL) -> URL? {
        let projects = configDirectory.appending(path: projectsDirName)
        let fileName = "\(sessionId).\(transcriptExtension)"
        let expected = projects.appending(path: projectSlug(for: cwd)).appending(path: fileName)
        if FileManager.default.fileExists(atPath: expected.path) { return expected }

        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return folders
            .lazy
            .map { projects.appending(path: $0).appending(path: fileName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func isAsciiAlphanumeric(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: true
        default: false
        }
    }
}
