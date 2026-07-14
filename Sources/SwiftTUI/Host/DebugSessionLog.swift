import Foundation

/// NDJSON debug logger for session `dde3c6`. Do not log secrets.
enum DebugSessionLog {
    static let path = "/Users/zhiyang/开发/Packges/SwiftTUI/.cursor/debug-dde3c6.log"
    static let sessionId = "dde3c6"

    @MainActor
    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:],
        runId: String = "pre"
    ) {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "runId": runId,
        ]
        if !data.isEmpty { payload["data"] = data }
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8)
        else { return }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let bytes = (line + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: bytes)
        }
    }

    @MainActor
    static func typeName(_ value: AnyObject?) -> String {
        guard let value else { return "nil" }
        return String(describing: type(of: value))
    }
}
