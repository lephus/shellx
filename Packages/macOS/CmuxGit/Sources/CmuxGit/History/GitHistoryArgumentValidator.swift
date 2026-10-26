import Foundation

/// Syntactic checks for values that originate in the Git Graph web page.
///
/// Semantic checks (a path belongs to the commit, a branch is a real ref) live in
/// ``GitHistoryService``; they need a git lookup. Everything here runs before any
/// git process starts.
enum GitHistoryArgumentValidator {
    static let skipRange = 0...5_000
    static let maximumPathByteCount = 4_096

    static func validateSHA(_ sha: String) throws {
        let utf8 = sha.utf8
        guard utf8.count == 40 || utf8.count == 64,
              utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }) else {
            throw GitHistoryError.invalidArgument("sha")
        }
    }

    static func validateSkip(_ skip: Int) throws {
        guard skipRange.contains(skip) else { throw GitHistoryError.invalidArgument("skip") }
    }

    /// A branch filter must be a full ref name; whether it exists is checked against `refs`.
    static func validateBranchFullName(_ name: String?) throws {
        guard let name else { return }
        guard name.hasPrefix("refs/"), !name.contains("\0"), !name.contains("\n") else {
            throw GitHistoryError.invalidArgument("branchFullName")
        }
    }

    static func validatePath(_ path: String) throws {
        guard !path.isEmpty,
              path.utf8.count <= maximumPathByteCount,
              !path.contains("\0") else {
            throw GitHistoryError.invalidArgument("path")
        }
    }
}
