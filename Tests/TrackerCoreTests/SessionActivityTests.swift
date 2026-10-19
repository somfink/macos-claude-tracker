import Testing
@testable import TrackerCore

@Suite("SessionActivity mapping")
struct SessionActivityTests {
    @Test func busyIsWorking() {
        #expect(SessionActivity(status: "busy", waitingFor: nil) == .working)
    }

    @Test func shellIsBackgroundTask() {
        #expect(SessionActivity(status: "shell", waitingFor: nil) == .backgroundTask)
    }

    @Test func backgroundTaskSortsWithReady() {
        #expect(SessionActivity.backgroundTask.sortPriority == SessionActivity.ready.sortPriority)
    }

    @Test func waitingCarriesReason() {
        #expect(SessionActivity(status: "waiting", waitingFor: "dialog open") == .waiting(reason: "dialog open"))
    }

    @Test func waitingWithoutReason() {
        #expect(SessionActivity(status: "waiting", waitingFor: nil) == .waiting(reason: nil))
    }

    @Test func idleIsReady() {
        #expect(SessionActivity(status: "idle", waitingFor: nil) == .ready)
    }

    @Test func unknownStatusIsPreserved() {
        #expect(SessionActivity(status: "parked", waitingFor: nil) == .unknown("parked"))
    }

    @Test func missingStatusIsUnknown() {
        #expect(SessionActivity(status: nil, waitingFor: nil) == .unknown("—"))
    }

    @Test func sortPriorityPutsWaitingFirst() {
        let ordered = [SessionActivity.ready, .unknown("x"), .working, .waiting(reason: nil)]
            .sorted { $0.sortPriority < $1.sortPriority }

        #expect(ordered == [.waiting(reason: nil), .working, .ready, .unknown("x")])
    }
}
