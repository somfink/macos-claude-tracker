import Foundation
import Testing
@testable import TrackerCore

@Suite("procStart parsing and process identity")
struct ProcessStartTests {
    @Test func parsesUtcProcStart() throws {
        let date = try #require(ProcessStart.parse("Sat Oct 17 18:39:33 2026"))

        #expect(date == utc(2026, 10, 17, 18, 39, 33))
    }

    @Test func parsesSingleDigitDayWithDoubleSpace() throws {
        let date = try #require(ProcessStart.parse("Sat Oct  7 09:05:01 2026"))

        #expect(date == utc(2026, 10, 7, 9, 5, 1))
    }

    @Test func rejectsGarbage() {
        #expect(ProcessStart.parse("yesterday-ish") == nil)
    }

    @Test func liveWhenStartTimesMatch() {
        let started = utc(2026, 10, 17, 18, 39, 33)
        let inspector = FakeProcessInspector(startTimes: [42: started.addingTimeInterval(0.4)])

        #expect(ProcessStart.isSameProcess(pid: 42, procStart: "Sat Oct 17 18:39:33 2026", inspector: inspector))
    }

    @Test func deadWhenProcessGone() {
        let inspector = FakeProcessInspector(startTimes: [:])

        #expect(!ProcessStart.isSameProcess(pid: 42, procStart: "Sat Oct 17 18:39:33 2026", inspector: inspector))
    }

    @Test func deadWhenPidWasReused() {
        let reused = utc(2026, 10, 18, 7, 0, 0)
        let inspector = FakeProcessInspector(startTimes: [42: reused])

        #expect(!ProcessStart.isSameProcess(pid: 42, procStart: "Sat Oct 17 18:39:33 2026", inspector: inspector))
    }

    @Test func unparseableProcStartFailsClosed() {
        let inspector = FakeProcessInspector(startTimes: [42: Date()])

        #expect(!ProcessStart.isSameProcess(pid: 42, procStart: "Sob paź 17 18:39:33 2026", inspector: inspector))
    }

    @Test func liveWithoutProcStartWhenPidExists() {
        let inspector = FakeProcessInspector(startTimes: [42: Date()])

        #expect(ProcessStart.isSameProcess(pid: 42, procStart: nil, inspector: inspector))
    }

    @Test func systemInspectorSeesCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier

        #expect(SystemProcessInspector().startTime(of: pid) != nil)
    }
}

func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

struct FakeProcessInspector: ProcessInspecting {
    let startTimes: [Int32: Date]

    func startTime(of pid: Int32) -> Date? { startTimes[pid] }
}
