import Foundation

/// Warp's quake ("dedicated hotkey") window shortcut, as stored in its user defaults
/// under `QuakeModeSettings` → `keybinding`.
public struct WarpHotkey: Equatable, Sendable {
    public let key: String
    public let control: Bool
    public let option: Bool
    public let shift: Bool
    public let command: Bool
    /// Warp's "hide window when unfocused": the window slides away once another app is active.
    public let hidesWhenUnfocused: Bool

    public init(key: String, control: Bool, option: Bool, shift: Bool, command: Bool, hidesWhenUnfocused: Bool = false) {
        self.key = key
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
        self.hidesWhenUnfocused = hidesWhenUnfocused
    }

    private struct Settings: Decodable {
        struct Keybinding: Decodable {
            let key: String
            let ctrl: Bool?
            let alt: Bool?
            let shift: Bool?
            let cmd: Bool?
        }

        let keybinding: Keybinding?
        let hideWindowWhenUnfocused: Bool?

        enum CodingKeys: String, CodingKey {
            case keybinding
            case hideWindowWhenUnfocused = "hide_window_when_unfocused"
        }
    }

    public static func parse(quakeSettingsJSON json: String) -> WarpHotkey? {
        guard let settings = try? JSONDecoder().decode(Settings.self, from: Data(json.utf8)),
              let binding = settings.keybinding
        else { return nil }
        return WarpHotkey(
            key: binding.key,
            control: binding.ctrl ?? false,
            option: binding.alt ?? false,
            shift: binding.shift ?? false,
            command: binding.cmd ?? false,
            hidesWhenUnfocused: settings.hideWindowWhenUnfocused ?? false
        )
    }

    /// The hotkey toggles the window, so it is pressed only when the window is hidden or about
    /// to be: listed on screen but sliding away because Warp lost focus to the tracker's panel.
    public func shouldPress(windowOnScreen: Bool, warpActive: Bool) -> Bool {
        !windowOnScreen || (hidesWhenUnfocused && !warpActive)
    }

    /// macOS virtual key code (ANSI layout positions), nil for keys this app cannot synthesize.
    public var keyCode: UInt16? { Self.keyCodes[key.lowercased()] }

    private static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "space": 49, " ": 49, "`": 50,
    ]
}

/// Claude Code sets the terminal title to the session title behind a status glyph
/// (`◐ Tracker sesji Claude Code`, `✳ …`); Warp shows it as the window title.
public enum TerminalTitle {
    public static func normalize(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmed.drop { !$0.isLetter && !$0.isNumber }
        return content.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public static func matches(windowTitle: String, sessionTitle: String) -> Bool {
        let target = normalize(sessionTitle)
        return !target.isEmpty && normalize(windowTitle) == target
    }

    /// Same tab text, ignoring the status glyph Claude Code animates while a session works.
    public static func same(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    public static func matches(windowTitle: String, anyOf sessionTitles: [String]) -> Bool {
        sessionTitles.contains { matches(windowTitle: windowTitle, sessionTitle: $0) }
    }
}

/// Walks a terminal's tabs with "next tab" until the window title matches the session.
public enum TabCycler {
    /// How long to wait for the terminal to retitle its window after a switch.
    public struct Timing: Sendable {
        public let pollInterval: Duration
        /// Polls before accepting an unchanged title (two neighbouring tabs can share one).
        public let retitleAttempts: Int

        public init(pollInterval: Duration, retitleAttempts: Int) {
            self.pollInterval = pollInterval
            self.retitleAttempts = retitleAttempts
        }

        /// Warp usually retitles within a few frames; half a second covers a busy machine.
        public static let standard = Timing(pollInterval: .milliseconds(20), retitleAttempts: 25)
    }

    /// Walks right until a tab carries one of the target's titles. When none does, the walk
    /// goes once around, then returns to the tab `TabResolver` picks from all the titles seen
    /// (`others` are the remaining live sessions, for eliminating their tabs).
    /// Gives up after `maxTabs` switches, when switching fails, or when the task is cancelled
    /// (a newer click took over). Runs on the caller's actor so UI callbacks stay on the main thread.
    public static func cycle(
        to target: TabTarget,
        among others: [TabTarget] = [],
        maxTabs: Int,
        timing: Timing = .standard,
        isolation: isolated (any Actor)? = #isolation,
        currentTitle: () -> String?,
        nextTab: () -> Bool
    ) async -> Bool {
        guard let start = currentTitle() else { return false }
        if target.isExact(start) { return true }

        var seen = [start]
        var wrapped = false
        for _ in 0..<maxTabs {
            guard let title = await advance(from: seen[seen.count - 1], timing: timing, currentTitle: currentTitle, nextTab: nextTab)
            else { return false }
            if target.isExact(title) { return true }
            if TerminalTitle.same(title, start) {
                wrapped = true
                break
            }
            seen.append(title)
        }
        guard wrapped, let index = TabResolver.index(of: target, among: others, in: seen) else { return false }

        var previous = start
        for _ in 0..<index {
            guard let title = await advance(from: previous, timing: timing, currentTitle: currentTitle, nextTab: nextTab)
            else { return false }
            previous = title
        }
        return true
    }

    /// One "next tab" press and the title it settles on; nil when it failed or was cancelled.
    private static func advance(
        from previous: String,
        timing: Timing,
        isolation: isolated (any Actor)? = #isolation,
        currentTitle: () -> String?,
        nextTab: () -> Bool
    ) async -> String? {
        guard !Task.isCancelled, nextTab() else { return nil }
        let title = await retitled(from: previous, timing: timing, currentTitle: currentTitle)
        return Task.isCancelled ? nil : title
    }

    /// The window title once it differs from `previous` (beyond the status glyph), or the unchanged one after the
    /// last attempt. Reading too early would mistake the old tab for the new one.
    private static func retitled(
        from previous: String,
        timing: Timing,
        isolation: isolated (any Actor)? = #isolation,
        currentTitle: () -> String?
    ) async -> String? {
        var title: String?
        for _ in 0..<max(1, timing.retitleAttempts) {
            try? await Task.sleep(for: timing.pollInterval)
            title = currentTitle()
            if let title, !TerminalTitle.same(title, previous) { return title }
            if Task.isCancelled { return title }
        }
        return title
    }
}
