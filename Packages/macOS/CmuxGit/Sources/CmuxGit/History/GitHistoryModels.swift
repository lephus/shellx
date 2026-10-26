import Foundation

/// One commit row in the Git Graph history list.
public struct GitHistoryCommit: Codable, Equatable, Sendable {
    public var sha: String
    public var parents: [String]
    /// Short ref name reported by `git log --source`, without `refs/heads/`, `refs/remotes/` or `refs/tags/`.
    public var source: String
    public var authorName: String
    public var authorEmail: String
    /// Strict ISO-8601 (`%aI`).
    public var authorDate: String
    /// Strict ISO-8601 (`%cI`).
    public var committerDate: String
    public var subject: String

    public init(
        sha: String,
        parents: [String],
        source: String,
        authorName: String,
        authorEmail: String,
        authorDate: String,
        committerDate: String,
        subject: String
    ) {
        self.sha = sha
        self.parents = parents
        self.source = source
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.committerDate = committerDate
        self.subject = subject
    }
}

public enum GitHistoryRefKind: String, Codable, Equatable, Sendable {
    case localBranch
    case remoteBranch
    case tag
}

/// A branch or tag that points at a commit.
public struct GitHistoryRef: Codable, Equatable, Sendable {
    public var kind: GitHistoryRefKind
    /// Short name such as `main`, `origin/main` or `v1.0`.
    public var name: String
    /// Full name such as `refs/heads/main`.
    public var fullName: String
    /// Commit sha. Annotated tags are peeled to the commit they point at.
    public var target: String

    public init(kind: GitHistoryRefKind, name: String, fullName: String, target: String) {
        self.kind = kind
        self.name = name
        self.fullName = fullName
        self.target = target
    }
}

public struct GitHistoryHead: Codable, Equatable, Sendable {
    public var sha: String?
    /// `nil` when HEAD is detached or the branch is unborn.
    public var branch: String?

    public init(sha: String?, branch: String?) {
        self.sha = sha
        self.branch = branch
    }
}

public struct GitHistoryPage: Codable, Equatable, Sendable {
    public var commits: [GitHistoryCommit]
    public var hasMore: Bool
    public var reachedLimit: Bool

    public init(commits: [GitHistoryCommit], hasMore: Bool, reachedLimit: Bool) {
        self.commits = commits
        self.hasMore = hasMore
        self.reachedLimit = reachedLimit
    }
}

public enum GitHistoryFileStatus: String, Codable, Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case unknown
}

public struct GitHistoryFileChange: Codable, Equatable, Sendable {
    public var path: String
    public var oldPath: String?
    public var status: GitHistoryFileStatus
    public var additions: Int?
    /// `nil` for binary files, together with `additions`.
    public var deletions: Int?

    public init(
        path: String,
        oldPath: String?,
        status: GitHistoryFileStatus,
        additions: Int?,
        deletions: Int?
    ) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
    }
}

/// Counts of uncommitted changes. Untracked files count as added.
public struct GitHistoryWorkingTreeStatus: Codable, Equatable, Sendable {
    public var added: Int
    public var modified: Int
    public var deleted: Int

    public var isClean: Bool { added == 0 && modified == 0 && deleted == 0 }

    public init(added: Int, modified: Int, deleted: Int) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }
}

public struct GitHistoryQuery: Codable, Equatable, Sendable {
    public var includeRemotes: Bool
    /// Must be the `fullName` of a ref returned by the service.
    public var branchFullName: String?

    public init(includeRemotes: Bool, branchFullName: String?) {
        self.includeRemotes = includeRemotes
        self.branchFullName = branchFullName
    }
}

public enum GitHistoryLimits {
    public static let pageSize = 300
    public static let maximumCommits = 5_000
}

public enum GitHistoryError: Error, Equatable, Sendable {
    case notARepository
    case gitUnavailable
    case timedOut
    case outputTooLarge
    case invalidArgument(String)
    case failed(exitCode: Int32)
}
