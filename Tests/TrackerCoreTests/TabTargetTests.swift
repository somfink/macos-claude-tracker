import Foundation
import Testing
@testable import TrackerCore

@Suite("Working out which Warp tab belongs to a session")
struct TabTargetTests {
    private func session(_ id: String, cwd: String, name: String? = nil, nameSource: String? = nil) -> TrackedSession {
        let json = SampleSessions.make(pid: 1, sessionId: id, cwd: cwd, name: name, nameSource: nameSource)
        return TrackedSession(record: try! SessionRecord.decode(from: Data(json.utf8)), account: "private")
    }

    /// Tab titles shaped like the ones Warp reports: Claude Code retitles some tabs,
    /// others keep their folder, and a plain shell shows its abbreviated path.
    private let tabs = [
        "Orbit",
        "..jects/Private/Orbit",
        "◐ Tracker sesji Claude Code",
        "Studio",
        "Acme Portal v2",
        "✳ ACME-101 planowanie zadań frontendu po zmianach w API",
    ]

    private var targets: [String: TabTarget] {
        let root = "/Users/me/Documents/Projects"
        let sessions: [(String, TrackedSession, String?)] = [
            ("orbit", session("g", cwd: "\(root)/Private/Orbit", name: "orbit-91", nameSource: "derived"), "Repozytorium Orbit"),
            ("tracker", session("t", cwd: "\(root)/Private/claude-tracker"), "Tracker sesji Claude Code"),
            ("studio", session("b", cwd: "\(root)/Private/Studio/Studio-WEB"), "Galeria zdjęć w portfolio"),
            ("brief", session("s1", cwd: "\(root)/Acme/Acme Portal v2"), "Brief ACME-102 dla nowego klienta"),
            ("plan", session("s2", cwd: "\(root)/Acme/Acme Portal v2",
                             name: "ACME-101 planowanie zadań frontendu po zmianach w API", nameSource: "user"), "Planowanie"),
        ]
        return Dictionary(uniqueKeysWithValues: sessions.map { ($0.0, TabTarget(session: $0.1, aiTitle: $0.2)) })
    }

    private func resolve(_ key: String) -> Int? {
        let all = targets
        let target = all[key]!
        let others = all.filter { $0.key != key }.map(\.value)
        return TabResolver.index(of: target, among: others, in: tabs)
    }

    @Test func titledTabsMatchDirectly() {
        #expect(resolve("tracker") == 2)
        #expect(resolve("plan") == 5)
    }

    @Test func folderTitledTabSkipsPlainShellPaths() {
        #expect(resolve("orbit") == 0)
    }

    @Test func parentFolderWhenTheTabWasOpenedOneLevelUp() {
        #expect(resolve("studio") == 3)
    }

    @Test func sharedFolderResolvedByEliminatingTheTitledSibling() {
        #expect(resolve("brief") == 4)
    }

    @Test func noCandidateTabMeansNoGuess() {
        let lone = TabTarget(session: session("x", cwd: "/p/Elsewhere"), aiTitle: "Coś innego")

        #expect(TabResolver.index(of: lone, among: [], in: tabs) == nil)
    }

    @Test func exactTitlesComeFromNameAndAiTitle() {
        let named = TabTarget(
            session: session("n", cwd: "/p/A", name: "Mój tytuł", nameSource: "user"),
            aiTitle: "Wygenerowany"
        )

        #expect(named.isExact("✳ Mój tytuł"))
        #expect(named.isExact("⠂ Wygenerowany"))
        #expect(!named.isExact("A"))
    }
}
