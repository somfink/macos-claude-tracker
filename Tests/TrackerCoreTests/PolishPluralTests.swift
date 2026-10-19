import Testing
@testable import TrackerCore

@Suite("Polish plural forms")
struct PolishPluralTests {
    @Test(arguments: [
        (0, "0 sesji"), (1, "1 sesja"), (2, "2 sesje"), (4, "4 sesje"), (5, "5 sesji"),
        (12, "12 sesji"), (14, "14 sesji"), (21, "21 sesji"), (22, "22 sesje"), (25, "25 sesji"), (104, "104 sesje"),
    ])
    func sessions(count: Int, expected: String) {
        #expect(PolishPlural.sessions(count) == expected)
    }

    @Test(arguments: [(1, "1 aktywna"), (3, "3 aktywne"), (5, "5 aktywnych"), (13, "13 aktywnych"), (23, "23 aktywne")])
    func active(count: Int, expected: String) {
        #expect(PolishPlural.active(count) == expected)
    }
}
