import Testing
@testable import TrackerCore

@Suite("Warp quake hotkey settings")
struct WarpHotkeyTests {
    private let realSettings = #"{"keybinding":{"ctrl":true,"alt":false,"shift":false,"cmd":false,"meta":false,"key":"`"},"active_pin_position":"Top","hide_window_when_unfocused":true}"#

    @Test func parsesKeybinding() throws {
        let hotkey = try #require(WarpHotkey.parse(quakeSettingsJSON: realSettings))

        #expect(hotkey == WarpHotkey(key: "`", control: true, option: false, shift: false, command: false, hidesWhenUnfocused: true))
        #expect(hotkey.keyCode == 50)
    }

    @Test func windowStaysWhenUnfocusedUnlessSettingSaysOtherwise() throws {
        let json = #"{"keybinding":{"ctrl":true,"key":"`"}}"#

        #expect(try #require(WarpHotkey.parse(quakeSettingsJSON: json)).hidesWhenUnfocused == false)
    }

    /// Clicking the tracker's panel takes focus from Warp, so a quake window set to hide
    /// when unfocused is on its way out even while it is still listed on screen.
    @Test(arguments: [
        (false, false, true, true),
        (false, true, true, true),
        (true, false, true, true),
        (true, true, true, false),
        (true, false, false, false),
        (false, false, false, true),
    ] as [(Bool, Bool, Bool, Bool)])
    func pressesHotkeyWhenTheWindowIsHiddenOrHiding(onScreen: Bool, active: Bool, hides: Bool, expected: Bool) {
        let hotkey = WarpHotkey(key: "`", control: true, option: false, shift: false, command: false, hidesWhenUnfocused: hides)

        #expect(hotkey.shouldPress(windowOnScreen: onScreen, warpActive: active) == expected)
    }

    @Test func parsesModifierCombos() throws {
        let json = #"{"keybinding":{"ctrl":false,"alt":true,"shift":true,"cmd":true,"key":"t"}}"#

        let hotkey = try #require(WarpHotkey.parse(quakeSettingsJSON: json))

        #expect(hotkey.option && hotkey.shift && hotkey.command && !hotkey.control)
        #expect(hotkey.keyCode == 17)
    }

    @Test func unknownKeyHasNoKeyCode() throws {
        let json = #"{"keybinding":{"ctrl":true,"key":"F13"}}"#

        #expect(try #require(WarpHotkey.parse(quakeSettingsJSON: json)).keyCode == nil)
    }

    @Test(arguments: ["", "not json", #"{"keybinding":null}"#, #"{"other":1}"#])
    func rejectsMissingKeybinding(json: String) {
        #expect(WarpHotkey.parse(quakeSettingsJSON: json) == nil)
    }
}

@Suite("Terminal title matching")
struct TerminalTitleTests {
    @Test(arguments: [
        ("◐ Tracker sesji Claude Code", "Tracker sesji Claude Code"),
        ("✳ Galeria zdjęć w portfolio", "Galeria zdjęć w portfolio"),
        ("⠂ ACME-101 planowanie zadań frontendu", "acme-101 planowanie zadań frontendu"),
        ("  Repozytorium Orbit  ", "Repozytorium Orbit"),
    ])
    func matches(window: String, session: String) {
        #expect(TerminalTitle.matches(windowTitle: window, sessionTitle: session))
    }

    @Test(arguments: [
        ("◐ Tracker sesji Claude Code", "Repozytorium Orbit"),
        ("~/Documents/Projects/Private/Orbit", "Orbit"),
        ("", "Orbit"),
        ("◐ Tracker", ""),
    ])
    func rejects(window: String, session: String) {
        #expect(!TerminalTitle.matches(windowTitle: window, sessionTitle: session))
    }
}

@Suite("Tab cycling")
struct TabCyclerTests {
    /// Fake terminal: `titles[index]` is visible, `next` advances with wraparound.
    /// With `lag`, the window keeps showing the previous tab's title for that many reads
    /// after a switch, like Warp retitling its window a moment later.
    private final class FakeTabs: @unchecked Sendable {
        let titles: [String]
        let lag: Int
        var index: Int
        var presses = 0
        private var shown: String
        private var staleReads = 0

        init(_ titles: [String], start: Int = 0, lag: Int = 0) {
            self.titles = titles
            self.lag = lag
            index = start
            shown = titles[start]
        }

        func current() -> String? {
            if staleReads > 0 {
                staleReads -= 1
                return shown
            }
            shown = titles[index]
            return shown
        }

        func next() -> Bool {
            presses += 1
            index = (index + 1) % titles.count
            staleReads = lag
            return true
        }
    }

    private let fast = TabCycler.Timing(pollInterval: .milliseconds(1), retitleAttempts: 10)

    @Test func alreadyOnTargetDoesNothing() async {
        let tabs = FakeTabs(["◐ A", "✳ B"])

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["A"]), maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.presses == 0)
    }

    @Test func advancesUntilMatch() async {
        let tabs = FakeTabs(["✳ A", "✳ B", "◐ C", "✳ D"])

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["C"]), maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.index == 2)
    }

    @Test func stopsAfterFullLoopWithoutMatch() async {
        let tabs = FakeTabs(["A", "B", "C"], start: 1)

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["Z"]), maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(!found)
        #expect(tabs.presses == 3)
        #expect(tabs.index == 1)
    }

    @Test func respectsMaxTabs() async {
        let tabs = FakeTabs((0..<50).map { "T\($0)" })

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["T40"]), maxTabs: 5, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(!found)
        #expect(tabs.presses == 5)
    }

    @Test func givesUpWhenNextTabFails() async {
        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["B"]), maxTabs: 10, timing: fast, currentTitle: { "A" }, nextTab: { false })

        #expect(!found)
    }

    @Test func waitsForTheWindowToRetitle() async {
        let tabs = FakeTabs(["✳ A", "✳ B", "◐ C", "✳ D"], lag: 3)

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["C"]), maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.index == 2)
    }

    @Test func staleTitleAfterFirstSwitchIsNotAFullLoop() async {
        let tabs = FakeTabs(["A", "B", "C"], lag: 3)

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["C"]), maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.index == 2)
    }

    @Test func passesNeighboursWithTheSameTitle() async {
        let tabs = FakeTabs(["A", "X", "X", "C"])

        let found = await TabCycler.cycle(to: TabTarget(exactTitles: ["C"]), maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.index == 3)
    }

    @Test func stopsWhenCancelled() async {
        let tabs = FakeTabs(["A", "B", "C", "D"])

        let timing = fast
        let navigation = Task {
            await TabCycler.cycle(to: TabTarget(exactTitles: ["D"]), maxTabs: 10, timing: timing, currentTitle: tabs.current) {
                // A newer click cancels this navigation mid-way.
                withUnsafeCurrentTask { $0?.cancel() }
                return tabs.next()
            }
        }

        let found = await navigation.value

        #expect(!found)
        #expect(tabs.presses == 1)
    }

    @Test func untitledTabFoundByWalkingAllTabsThenComingBack() async {
        let tabs = FakeTabs(["Orbit", "◐ Tracker", "Acme Portal v2", "✳ ACME-101 plan"], start: 1)
        let brief = TabTarget(exactTitles: ["Brief ACME-102"], folders: ["Acme Portal v2", "Acme"])
        let plan = TabTarget(exactTitles: ["ACME-101 plan"], folders: ["Acme Portal v2", "Acme"])

        let found = await TabCycler.cycle(to: brief, among: [plan], maxTabs: 10, timing: fast, currentTitle: tabs.current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.index == 2)
        #expect(tabs.presses == 4 + 1)
    }

    @Test func spinnerTickingOnTheStartTabStillEndsTheLoop() async {
        let tabs = FakeTabs(["◐ Tracker", "Orbit", "Acme Portal v2"])
        let brief = TabTarget(exactTitles: ["Brief ACME-102"], folders: ["Acme Portal v2"])
        // Claude Code animates the busy glyph: the start tab reads differently once the walk is back.
        let current = {
            tabs.presses >= 3 && tabs.index == 0 ? "◓ Tracker" : tabs.current()
        }

        let found = await TabCycler.cycle(to: brief, maxTabs: 10, timing: fast, currentTitle: current, nextTab: tabs.next)

        #expect(found)
        #expect(tabs.index == 2)
        #expect(tabs.presses == 3 + 2)
    }
}
