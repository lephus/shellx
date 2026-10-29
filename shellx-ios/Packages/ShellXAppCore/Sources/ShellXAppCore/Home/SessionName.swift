import Foundation
import ShellXLinkCore

/// The name a session row shows: the session's own title, so rows of one workspace tell apart.
public enum SessionName {
    /// The first non-blank line of `title` that has text left, with every `<…>` tag removed (and a tag
    /// the Mac cut in the middle), a leading `/command` word dropped (not a path such as `/Users/x`),
    /// and runs of whitespace collapsed to one space; nil when nothing is left.
    public static func cleaned(_ title: String?) -> String? {
        guard let title else { return nil }
        for line in title.split(whereSeparator: \.isNewline) {
            let untagged = String(line)
                .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]*$", with: " ", options: .regularExpression)
            var words = untagged.split(whereSeparator: \.isWhitespace)
            if let first = words.first, first.hasPrefix("/"), !first.dropFirst().contains("/") {
                words.removeFirst()
            }
            let text = words.joined(separator: " ")
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// `cleaned(title)`, else "<AgentLabel> · HH:mm" from `lastActivityMs` (then `stateSinceMs`), else the label.
    public static func base(of session: AgentSession, timeZone: TimeZone = .current) -> String {
        if let name = cleaned(session.title) { return name }
        let label = AgentLabel(agent: session.agent).text
        guard let ms = session.lastActivityMs ?? session.stateSinceMs else { return label }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return [label, formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))]
            .joined(separator: " · ")
    }

    /// The name each session shows in one list: equal bases get " · #2", " · #3"… in (machineID, sessionId) order.
    public static func distinct(_ sessions: [MachineSession], timeZone: TimeZone = .current) -> [SessionRef: String] {
        let ordered = sessions.sorted {
            ($0.machineID, $0.session.sessionId) < ($1.machineID, $1.session.sessionId)
        }
        var seen: [String: Int] = [:]
        var names: [SessionRef: String] = [:]
        for machineSession in ordered {
            let base = base(of: machineSession.session, timeZone: timeZone)
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            names[machineSession.ref] = count == 1 ? base : "\(base) · #\(count)"
        }
        return names
    }
}
