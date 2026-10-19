import Foundation

/// One Claude Code config directory (`CLAUDE_CONFIG_DIR`), e.g. `~/.claude-private`.
public struct ConfigRoot: Equatable, Hashable, Sendable {
    /// Short label shown in the UI: `default` for `~/.claude`, `private` for `~/.claude-private`.
    public let account: String
    public let sessionsDirectory: URL

    public init(account: String, sessionsDirectory: URL) {
        self.account = account
        self.sessionsDirectory = sessionsDirectory
    }
}

public enum ConfigRoots {
    static let defaultDirName = ".claude"
    static let sessionsDirName = "sessions"

    /// Every `~/.claude` / `~/.claude-*` directory that has a `sessions` folder,
    /// plus `CLAUDE_CONFIG_DIR` when it points elsewhere. Sorted by account label.
    public static func discover(home: URL, environment: [String: String]) -> [ConfigRoot] {
        let fromHome = homeConfigDirs(home: home)
        let fromEnv = environment["CLAUDE_CONFIG_DIR"].map { [URL(filePath: $0)] } ?? []

        // Compare canonical paths: URLs differ on trailing slashes and /var vs /private/var.
        let uniquePaths = (fromHome + fromEnv)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .reduce(into: [String]()) { acc, path in if !acc.contains(path) { acc.append(path) } }

        return uniquePaths
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { isDirectory($0.appending(path: sessionsDirName)) }
            .map { ConfigRoot(account: accountLabel(for: $0), sessionsDirectory: $0.appending(path: sessionsDirName)) }
            .sorted { $0.account < $1.account }
    }

    private static func homeConfigDirs(home: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        return names
            .filter { $0 == defaultDirName || $0.hasPrefix(defaultDirName + "-") }
            .map { home.appending(path: $0) }
            .filter(isDirectory)
    }

    static func accountLabel(for configDir: URL) -> String {
        let name = configDir.lastPathComponent
        if name == defaultDirName { return "default" }
        if name.hasPrefix(defaultDirName + "-") { return String(name.dropFirst(defaultDirName.count + 1)) }
        return name
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
