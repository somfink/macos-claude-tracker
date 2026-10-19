import Foundation

/// Synthetic session files shaped like `<config>/sessions/<pid>.json` written by Claude Code 2.1.x.
enum SampleSessions {
    static let busy = """
    {"pid":4242,"sessionId":"11111111-2222-3333-4444-555555555555",
     "cwd":"/Users/dev/Projects/Orbit","startedAt":1792262373809,
     "procStart":"Sat Oct 17 18:39:33 2026","version":"2.1.302",
     "kind":"interactive","entrypoint":"cli","name":"orbit-ba",
     "status":"busy","updatedAt":1792312539873,"statusUpdatedAt":1792312539873,
     "someFutureField":{"nested":true}}
    """

    static let waiting = """
    {"pid":5151,"sessionId":"aaaaaaaa-0000-0000-0000-000000000001",
     "cwd":"/Users/dev/Projects/Studio-WEB","procStart":"Sat Oct  7 09:05:01 2026",
     "kind":"interactive","name":"studio-web","status":"waiting",
     "waitingFor":"dialog open","statusUpdatedAt":1792312000000}
    """

    static func make(
        pid: Int32,
        sessionId: String,
        cwd: String = "/Users/dev/Projects/Demo",
        name: String? = nil,
        nameSource: String? = nil,
        status: String = "idle",
        procStart: String? = nil,
        statusUpdatedAt: Int64 = 1_792_312_000_000
    ) -> String {
        var fields: [String: Any] = [
            "pid": pid,
            "sessionId": sessionId,
            "cwd": cwd,
            "status": status,
            "statusUpdatedAt": statusUpdatedAt,
        ]
        if let name { fields["name"] = name }
        if let nameSource { fields["nameSource"] = nameSource }
        if let procStart { fields["procStart"] = procStart }
        let data = try! JSONSerialization.data(withJSONObject: fields)
        return String(decoding: data, as: UTF8.self)
    }
}
