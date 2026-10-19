import Testing
@testable import TrackerCore

@Suite("Mascot mood")
struct MascotMoodTests {
    @Test func waitingWinsOverEverything() {
        let summary = StatusSummary(waiting: 1, working: 3, ready: 2, total: 6)

        #expect(MascotMood(summary: summary) == .waiting)
    }

    @Test func workingWhenNothingWaits() {
        #expect(MascotMood(summary: StatusSummary(waiting: 0, working: 1, ready: 4, total: 5)) == .working)
    }

    @Test func readyWhenAllDone() {
        #expect(MascotMood(summary: StatusSummary(waiting: 0, working: 0, ready: 2, total: 2)) == .ready)
    }

    @Test func sleepingWithoutSessions() {
        #expect(MascotMood(summary: StatusSummary(waiting: 0, working: 0, ready: 0, total: 0)) == .sleeping)
    }

    @Test(arguments: [
        (SessionActivity.waiting(reason: "dialog open"), MascotMood.waiting),
        (.working, .working),
        (.ready, .ready),
        (.backgroundTask, .ready),
        (.unknown("parked"), .sleeping),
    ])
    func moodPerSession(activity: SessionActivity, expected: MascotMood) {
        #expect(MascotMood(activity: activity) == expected)
    }

    @Test func onlyActiveMoodsAnimate() {
        #expect(MascotMood.working.frameInterval != nil)
        #expect(MascotMood.waiting.frameInterval != nil)
        #expect(MascotMood.ready.frameInterval == nil)
        #expect(MascotMood.sleeping.frameInterval == nil)
    }
}

@Suite("Mascot sprites")
struct MascotSpriteTests {
    @Test(arguments: MascotMood.allCases)
    func everyFrameHasCanvasSize(mood: MascotMood) {
        for frame in MascotSprites.frames(for: mood) {
            #expect(frame.width == MascotSprites.width)
            #expect(frame.height == MascotSprites.height)
            #expect(frame.rows.allSatisfy { $0.count == MascotSprites.width })
        }
    }

    @Test func appIconIsThePlainCrab() {
        let icon = MascotSprites.appIcon

        #expect(icon.rows.allSatisfy { $0.count == MascotSprites.width })
        // Just the body and eyes: no status badge, so it reads the same in every context.
        #expect(Set(icon.rows.joined()) == [".", "O", "E"])
    }

    @Test(arguments: MascotMood.allCases)
    func usesOnlyPaletteCharacters(mood: MascotMood) {
        let used = Set(MascotSprites.frames(for: mood).flatMap { $0.rows.joined() })

        #expect(used.isSubset(of: MascotSprites.paletteCharacters))
    }

    @Test(arguments: MascotMood.allCases)
    func animatedMoodsHaveSeveralFrames(mood: MascotMood) {
        let frames = MascotSprites.frames(for: mood)

        #expect(frames.count == (mood.frameInterval == nil ? 1 : 2))
        #expect(Set(frames).count == frames.count)
    }

    @Test func pixelLookup() {
        let sprite = PixelSprite(rows: ["ab", "cd"])

        #expect(sprite.pixel(x: 1, y: 0) == "b")
        #expect(sprite.pixel(x: 0, y: 1) == "c")
        #expect(sprite.pixel(x: 5, y: 5) == nil)
    }
}
