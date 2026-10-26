import Foundation

/// Parses the delimited Git output used by the Git Graph history service.
enum GitHistoryParser {
    static let logFormat = "%H%x1f%P%x1f%S%x1f%an%x1f%ae%x1f%aI%x1f%cI%x1f%s%x1e"
    static let refFormat = "%(refname)%x1f%(objectname)%x1f%(*objectname)%x1e"

    private static let fieldSeparator: Character = "\u{1f}"
    private static let recordSeparator: Character = "\u{1e}"

    static func commits(fromLog data: Data) -> [GitHistoryCommit] {
        records(in: data).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 8, !fields[0].isEmpty else { return nil }
            return GitHistoryCommit(
                sha: String(fields[0]),
                parents: fields[1].split(separator: " ").map(String.init),
                source: shortSource(String(fields[2])),
                authorName: String(fields[3]),
                authorEmail: String(fields[4]),
                authorDate: String(fields[5]),
                committerDate: String(fields[6]),
                subject: String(fields[7])
            )
        }
    }

    static func refs(fromForEachRef data: Data) -> [GitHistoryRef] {
        records(in: data).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            let fullName = String(fields[0])
            let peeled = String(fields[2])
            let target = peeled.isEmpty ? String(fields[1]) : peeled
            guard !target.isEmpty else { return nil }
            if let name = fullName.dropping(prefix: "refs/heads/") {
                return GitHistoryRef(kind: .localBranch, name: name, fullName: fullName, target: target)
            }
            if let name = fullName.dropping(prefix: "refs/remotes/") {
                if name.hasSuffix("/HEAD") { return nil }
                return GitHistoryRef(kind: .remoteBranch, name: name, fullName: fullName, target: target)
            }
            if let name = fullName.dropping(prefix: "refs/tags/") {
                return GitHistoryRef(kind: .tag, name: name, fullName: fullName, target: target)
            }
            return nil
        }
    }

    static func fileChanges(nameStatusZ: Data, numstatZ: Data) -> [GitHistoryFileChange] {
        var stats: [String: (additions: Int?, deletions: Int?)] = [:]
        var numstatTokens = nulFields(in: numstatZ)[...]
        while let token = numstatTokens.popFirst() {
            let parts = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            var path = String(parts[2])
            if path.isEmpty {
                // Rename or copy: the old and new paths follow as separate fields.
                guard numstatTokens.popFirst() != nil, let newPath = numstatTokens.popFirst() else { break }
                path = newPath
            }
            stats[path] = (Int(parts[0]), Int(parts[1]))
        }

        var changes: [GitHistoryFileChange] = []
        var tokens = nulFields(in: nameStatusZ)[...]
        while let code = tokens.popFirst() {
            guard let letter = code.first else { continue }
            let status = fileStatus(letter)
            var oldPath: String?
            var path: String
            if letter == "R" || letter == "C" {
                guard let old = tokens.popFirst(), let new = tokens.popFirst() else { break }
                oldPath = old
                path = new
            } else {
                guard let single = tokens.popFirst() else { break }
                path = single
            }
            let stat = stats[path]
            changes.append(GitHistoryFileChange(
                path: path,
                oldPath: oldPath,
                status: status,
                additions: stat?.additions,
                deletions: stat?.deletions
            ))
        }
        return changes
    }

    static func workingTreeStatus(porcelainV1Z data: Data) -> GitHistoryWorkingTreeStatus {
        var added = 0
        var modified = 0
        var deleted = 0
        var tokens = nulFields(in: data)[...]
        while let entry = tokens.popFirst() {
            let chars = Array(entry.prefix(2))
            guard chars.count == 2 else { continue }
            let (x, y) = (chars[0], chars[1])
            if x == "R" || x == "C" || y == "R" || y == "C" {
                _ = tokens.popFirst()
            }
            if x == "?" && y == "?" || x == "A" || y == "A" {
                added += 1
            } else if x == "D" || y == "D" {
                deleted += 1
            } else if x == "!" {
                continue
            } else {
                modified += 1
            }
        }
        return GitHistoryWorkingTreeStatus(added: added, modified: modified, deleted: deleted)
    }

    // MARK: - Helpers

    /// Splits on the record separator and trims the newline Git prints after each record.
    private static func records(in data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
    }

    private static func nulFields(in data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func shortSource(_ source: String) -> String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] {
            if let stripped = source.dropping(prefix: prefix) { return stripped }
        }
        return source
    }

    private static func fileStatus(_ letter: Character) -> GitHistoryFileStatus {
        switch letter {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        case "U": .unmerged
        default: .unknown
        }
    }
}

private extension String {
    func dropping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
