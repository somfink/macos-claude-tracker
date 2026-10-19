import Foundation
import Testing
@testable import TrackerCore

@Suite("Finding the terminal app a session runs in")
struct TerminalHostTests {
    /// Fake process table: pid → (parent, executable path).
    private func tree(_ nodes: [Int32: (Int32, String)]) -> (Int32) -> ProcessNode? {
        { pid in nodes[pid].map { ProcessNode(parent: $0.0, executablePath: $0.1) } }
    }

    private let bundles = [
        "/Applications/Warp.app": "dev.warp.Warp-Stable",
        "/Applications/iTerm.app": "com.googlecode.iterm2",
        "/System/Applications/Utilities/Terminal.app": "com.apple.Terminal",
        "/Applications/Ghostty.app": "com.mitchellh.ghostty",
        "/Applications/Claude.app": "com.anthropic.claudefordesktop",
    ]

    private func host(of pid: Int32, in nodes: [Int32: (Int32, String)]) -> TerminalApp? {
        TerminalHost.app(hosting: pid, node: tree(nodes), bundleIdentifier: { bundles[$0] })
    }

    @Test func warpThroughItsTerminalServerChild() {
        let nodes: [Int32: (Int32, String)] = [
            18418: (26091, "/Users/me/.local/bin/claude"),
            26091: (20445, "/bin/zsh"),
            20445: (20444, "/Applications/Warp.app/Contents/MacOS/stable"),
            20444: (1, "/Applications/Warp.app/Contents/MacOS/stable"),
        ]

        #expect(host(of: 18418, in: nodes) == .warp)
    }

    @Test func iTermAndTerminal() {
        let iTerm: [Int32: (Int32, String)] = [
            10: (11, "/opt/homebrew/bin/claude"), 11: (12, "/bin/zsh"), 12: (13, "/usr/bin/login"),
            13: (1, "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
        ]
        let terminal: [Int32: (Int32, String)] = [
            10: (11, "/opt/homebrew/bin/claude"), 11: (12, "/bin/zsh"),
            12: (1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
        ]

        #expect(host(of: 10, in: iTerm) == .iTerm2)
        #expect(host(of: 10, in: terminal) == .appleTerminal)
    }

    @Test func otherAppsAreReportedByBundleId() {
        let nodes: [Int32: (Int32, String)] = [
            10: (11, "/opt/homebrew/bin/claude"), 11: (12, "/bin/zsh"),
            12: (1, "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
        ]

        #expect(host(of: 10, in: nodes) == .other(bundleIdentifier: "com.mitchellh.ghostty"))
    }

    /// A claude binary bundled inside some app says nothing about where it runs: the walk
    /// starts at its parent.
    @Test func skipsTheSessionProcessItself() {
        let nodes: [Int32: (Int32, String)] = [
            10: (11, "/Applications/Claude.app/Contents/Resources/claude"), 11: (12, "/bin/zsh"),
            12: (1, "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
        ]

        #expect(host(of: 10, in: nodes) == .iTerm2)
    }

    @Test func unknownWhenTheChainReachesLaunchdWithoutAnApp() {
        let nodes: [Int32: (Int32, String)] = [
            10: (11, "/opt/homebrew/bin/claude"), 11: (12, "/bin/zsh"),
            12: (1, "/Users/me/Library/Application Support/iTerm2/iTermServer-3.5"),
        ]

        #expect(host(of: 10, in: nodes) == nil)
        #expect(host(of: 99, in: nodes) == nil)
    }

    @Test func survivesAParentLoop() {
        let nodes: [Int32: (Int32, String)] = [10: (11, "/bin/claude"), 11: (12, "/bin/zsh"), 12: (11, "/bin/zsh")]

        #expect(host(of: 10, in: nodes) == nil)
    }

    @Test func appBundleIsTheOutermostDotApp() {
        #expect(TerminalHost.appBundlePath(ofExecutable: "/Applications/Warp.app/Contents/MacOS/stable") == "/Applications/Warp.app")
        #expect(TerminalHost.appBundlePath(ofExecutable: "/Applications/iTerm.app/Contents/Frameworks/x.app/Contents/MacOS/x")
            == "/Applications/iTerm.app")
        #expect(TerminalHost.appBundlePath(ofExecutable: "/usr/bin/login") == nil)
    }
}

@Suite("AppleScript that selects a terminal tab by tty")
struct TerminalScriptTests {
    @Test func selectsTheITermSessionWithThatTTY() throws {
        let script = try #require(TerminalScript.select(tty: "/dev/ttys003", in: .iTerm2))

        #expect(script.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(script.contains(#"if tty of aSession is "/dev/ttys003" then"#))
    }

    @Test func selectsTheTerminalTabWithThatTTY() throws {
        let script = try #require(TerminalScript.select(tty: "/dev/ttys012", in: .appleTerminal))

        #expect(script.contains(#"tell application id "com.apple.Terminal""#))
        #expect(script.contains(#"if tty of aTab is "/dev/ttys012" then"#))
    }

    /// The tty is spliced into AppleScript source, so only the device path shape is accepted.
    @Test(arguments: ["", "/dev/ttys", "ttys003", #"/dev/ttys003" & (do shell script "id") & ""#, "/dev/ttys003\n"])
    func rejectsAnythingButATTYPath(tty: String) {
        #expect(TerminalScript.select(tty: tty, in: .iTerm2) == nil)
    }

    @Test func noScriptForTerminalsWithoutOne() {
        #expect(TerminalScript.select(tty: "/dev/ttys003", in: .warp) == nil)
        #expect(TerminalScript.select(tty: "/dev/ttys003", in: .other(bundleIdentifier: "com.mitchellh.ghostty")) == nil)
    }
}
