/// Minimal reader for the YAML frontmatter of a `SKILL.md`: `key: value` lines between `---` lines.
public struct ShellXSkillFrontmatter: Sendable, Equatable {
    /// Why frontmatter could not be read.
    public enum ParseError: Error, Sendable, Equatable {
        /// No leading `---` line.
        case missingOpening
        /// No closing `---` line.
        case missingClosing
        /// No `name` value.
        case missingName
    }

    /// The `name` value.
    public let name: String
    /// The `description` value, empty when absent.
    public let description: String

    /// Parses frontmatter from the start of `markdown`.
    public init(markdown: String) throws {
        let lines = markdown.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first?.trimmingSpaces() == "---" else { throw ParseError.missingOpening }
        var values: [String: String] = [:]
        var closed = false
        for line in lines.dropFirst() {
            if line.trimmingSpaces() == "---" { closed = true; break }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("#") else { continue }
            let key = String(line[..<colon]).trimmingSpaces()
            values[key] = Self.unquote(String(line[line.index(after: colon)...]).trimmingSpaces())
        }
        guard closed else { throw ParseError.missingClosing }
        guard let name = values["name"], !name.isEmpty else { throw ParseError.missingName }
        self.name = name
        self.description = values["description"] ?? ""
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

private extension String {
    func trimmingSpaces() -> String {
        var s = Substring(self)
        while let f = s.first, f == " " || f == "\t" { s = s.dropFirst() }
        while let l = s.last, l == " " || l == "\t" { s = s.dropLast() }
        return String(s)
    }
}
