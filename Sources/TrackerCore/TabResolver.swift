import Foundation

/// What a session's terminal tab may be titled. Claude Code retitles the tab with the
/// session name or its generated title; a tab it has not retitled keeps a folder name,
/// usually the working directory's, sometimes its parent when the tab was opened there.
public struct TabTarget: Equatable, Sendable {
    public let exactTitles: [String]
    /// Most specific first: the project folder, then its parent.
    public let folders: [String]

    public init(exactTitles: [String], folders: [String] = []) {
        self.exactTitles = exactTitles.filter { !TerminalTitle.normalize($0).isEmpty }
        self.folders = folders.filter { !TerminalTitle.normalize($0).isEmpty }
    }

    public init(session: TrackedSession, aiTitle: String?) {
        let folder = URL(filePath: session.cwd)
        let parent = folder.deletingLastPathComponent().lastPathComponent
        self.init(
            exactTitles: [session.hasCustomName ? session.title : nil, aiTitle].compactMap { $0 },
            folders: [folder.lastPathComponent, parent == "/" ? "" : parent]
        )
    }

    public func isExact(_ windowTitle: String) -> Bool {
        TerminalTitle.matches(windowTitle: windowTitle, anyOf: exactTitles)
    }
}

/// Picks a session's tab from the titles of every tab in the window.
public enum TabResolver {
    /// A tab titled after the session wins. Otherwise a folder-titled tab no other session
    /// claims by title: with two sessions in one folder, the one whose tab Claude Code
    /// retitled is eliminated. Path-like titles belong to plain shells and never match.
    public static func index(of target: TabTarget, among others: [TabTarget], in tabTitles: [String]) -> Int? {
        if let exact = tabTitles.firstIndex(where: target.isExact) { return exact }

        let claimed = Set(tabTitles.indices.filter { index in others.contains { $0.isExact(tabTitles[index]) } })
        for folder in target.folders {
            let name = TerminalTitle.normalize(folder)
            let match = tabTitles.indices.first { index in
                !claimed.contains(index)
                    && !tabTitles[index].contains("/")
                    && TerminalTitle.normalize(tabTitles[index]) == name
            }
            if let match { return match }
        }
        return nil
    }
}
