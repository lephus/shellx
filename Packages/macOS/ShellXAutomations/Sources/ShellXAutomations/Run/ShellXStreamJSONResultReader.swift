public import Foundation

/// Reads `claude --output-format stream-json` lines and keeps the session id and the final result.
public struct ShellXStreamJSONResultReader: Sendable {
    /// The result gathered so far; `resultText` stays `nil` until a `result` event arrives.
    public private(set) var result = ShellXClaudeResult()

    /// Creates an empty reader.
    public init() {}

    /// Feeds one output line; lines that are not JSON objects are ignored.
    public mutating func ingest(line: String) {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return }
        if type == "system", object["subtype"] as? String == "init" {
            if let id = object["session_id"] as? String { result.sessionId = id }
        } else if type == "result" {
            if let id = object["session_id"] as? String { result.sessionId = id }
            result.resultText = object["result"] as? String ?? ""
            result.isError = object["is_error"] as? Bool ?? false
            let denials = object["permission_denials"] as? [[String: Any]] ?? []
            result.permissionDenials = denials.compactMap { $0["tool_name"] as? String }
        }
    }
}
