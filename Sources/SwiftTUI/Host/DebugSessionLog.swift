import Foundation

/// NDJSON debug logger for session `dde3c6`. Do not log secrets.
///
/// Nonisolated + fopen so logging never blocks ``MainActor`` (sync FileHandle
/// on MainActor previously starved the input pump → every-other click/key).
enum DebugSessionLog {
    static let path = "/Users/zhiyang/开发/Packges/SwiftTUI/.cursor/debug-dde3c6.log"
    static let sessionId = "dde3c6"

    nonisolated static func write(
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
              var line = String(data: json, encoding: .utf8)
        else { return }
        line.append("\n")
        line.withCString { cstr in
            if let fp = fopen(path, "a") {
                fputs(cstr, fp)
                fclose(fp)
            }
        }
    }

    nonisolated static func typeName(_ value: AnyObject?) -> String {
        guard let value else { return "nil" }
        return String(describing: type(of: value))
    }
}
