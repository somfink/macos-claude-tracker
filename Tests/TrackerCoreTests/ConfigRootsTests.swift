import Foundation
import Testing
@testable import TrackerCore

@Suite("Claude config root discovery")
struct ConfigRootsTests {
    @Test func findsEveryClaudeDirWithSessionsFolder() throws {
        let home = try TempDir()
        try home.makeDir(".claude/sessions")
        try home.makeDir(".claude-private/sessions")
        try home.makeDir(".claude-acme/sessions")
        try home.makeDir(".claude-pilot")            // no sessions folder
        try home.write(".claude.json", "{}")         // file, not a dir
        try home.makeDir(".config/sessions")         // unrelated dir

        let roots = ConfigRoots.discover(home: home.url, environment: [:])

        #expect(roots.map(\.account) == ["acme", "default", "private"])
        #expect(roots.allSatisfy { $0.sessionsDirectory.lastPathComponent == "sessions" })
    }

    @Test func includesConfigDirFromEnvironment() throws {
        let home = try TempDir()
        let custom = try TempDir()
        try custom.makeDir("sessions")

        let roots = ConfigRoots.discover(home: home.url, environment: ["CLAUDE_CONFIG_DIR": custom.url.path])

        #expect(roots.count == 1)
        #expect(roots.first?.sessionsDirectory.path == custom.url.appending(path: "sessions").resolvingSymlinksInPath().path)
    }

    @Test func deduplicatesEnvironmentDirAlreadyInHome() throws {
        let home = try TempDir()
        try home.makeDir(".claude-private/sessions")

        let roots = ConfigRoots.discover(
            home: home.url,
            environment: ["CLAUDE_CONFIG_DIR": home.url.appending(path: ".claude-private").path]
        )

        #expect(roots.map(\.account) == ["private"])
    }
}

/// Self-deleting temporary directory for filesystem tests.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "claude-tracker-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func makeDir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: url.appending(path: relative), withIntermediateDirectories: true)
    }

    func write(_ relative: String, _ contents: String) throws {
        try Data(contents.utf8).write(to: url.appending(path: relative))
    }
}
