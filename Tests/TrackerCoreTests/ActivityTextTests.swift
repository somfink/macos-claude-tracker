import Testing
@testable import TrackerCore

@Suite("Polish activity labels")
struct ActivityTextTests {
    @Test(arguments: [
        (SessionActivity.working, "Pracuje"),
        (.ready, "Gotowe"),
        (.backgroundTask, "Gotowe · bash w tle"),
        (.waiting(reason: nil), "Czeka na Ciebie"),
        (.waiting(reason: "dialog open"), "Czeka: dialog"),
        (.waiting(reason: "input needed"), "Czeka: odpowiedź"),
        (.waiting(reason: "sandbox request"), "Czeka: sandbox"),
        (.waiting(reason: "something new"), "Czeka: something new"),
        (.unknown("parked"), "parked"),
    ])
    func label(activity: SessionActivity, expected: String) {
        #expect(ActivityText.label(for: activity) == expected)
    }
}
