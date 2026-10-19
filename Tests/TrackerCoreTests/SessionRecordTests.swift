import Foundation
import Testing
@testable import TrackerCore

@Suite("SessionRecord decoding")
struct SessionRecordTests {
    @Test func decodesFullRecord() throws {
        let record = try SessionRecord.decode(from: Data(SampleSessions.busy.utf8))

        #expect(record.pid == 4242)
        #expect(record.sessionId == "11111111-2222-3333-4444-555555555555")
        #expect(record.cwd == "/Users/dev/Projects/Orbit")
        #expect(record.name == "orbit-ba")
        #expect(record.status == "busy")
        #expect(record.kind == "interactive")
        #expect(record.procStart == "Sat Oct 17 18:39:33 2026")
        #expect(record.statusUpdatedAt == 1_792_312_539_873)
    }

    @Test func decodesWaitingForField() throws {
        let record = try SessionRecord.decode(from: Data(SampleSessions.waiting.utf8))

        #expect(record.status == "waiting")
        #expect(record.waitingFor == "dialog open")
    }

    @Test func toleratesMissingOptionalFields() throws {
        let json = #"{"pid": 7, "sessionId": "abc", "cwd": "/tmp/x"}"#

        let record = try SessionRecord.decode(from: Data(json.utf8))

        #expect(record.pid == 7)
        #expect(record.name == nil)
        #expect(record.status == nil)
        #expect(record.updatedAt == nil)
    }

    @Test func rejectsRecordWithoutPid() {
        let json = #"{"sessionId": "abc", "cwd": "/tmp/x"}"#

        #expect(throws: (any Error).self) {
            try SessionRecord.decode(from: Data(json.utf8))
        }
    }
}
