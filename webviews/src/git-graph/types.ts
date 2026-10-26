// TS mirrors of the Swift Codable structs in CmuxGit/History/GitHistoryModels.swift.

export type GitGraphCommit = {
  sha: string;
  parents: string[];
  source: string;
  authorName: string;
  authorEmail: string;
  authorDate: string;
  committerDate: string;
  subject: string;
};

export type GitGraphRefKind = "localBranch" | "remoteBranch" | "tag";

export type GitGraphRef = {
  kind: GitGraphRefKind;
  name: string;
  fullName: string;
  target: string;
};

export type GitGraphHead = {
  sha: string | null;
  branch: string | null;
};

export type GitGraphPage = {
  commits: GitGraphCommit[];
  hasMore: boolean;
  reachedLimit: boolean;
};

export type GitGraphFileStatus =
  | "added"
  | "modified"
  | "deleted"
  | "renamed"
  | "copied"
  | "typeChanged"
  | "unmerged"
  | "unknown";

export type GitGraphFileChange = {
  path: string;
  oldPath: string | null;
  status: GitGraphFileStatus;
  additions: number | null;
  deletions: number | null;
};

export type GitGraphWorkingTree = {
  added: number;
  modified: number;
  deleted: number;
};

/** `history.message`: one commit's full message, as `git log -1 --format=%B` prints it. */
export type GitGraphCommitMessage = {
  message: string;
};

// Bridge contract shared with the bridge client and the Swift side.

export type GitGraphMethod =
  | "app.context"
  | "repo.state"
  | "history.refs"
  | "history.page"
  | "history.files"
  | "history.message"
  | "history.workingTree"
  | "history.openFileDiff"
  | "history.openWorkingTreeDiff"
  | "history.openAsTab";

export type GitGraphReply<T> =
  | { ok: true; result: T; generation: number }
  | { ok: false; error: { code: string; message: string }; generation: number };

export type GitGraphEvent = {
  type: "repo.changed" | "history.invalidated";
  generation: number;
};

export type GitGraphRepoStatus =
  | "loading"
  | "ready"
  | "notRepository"
  | "remote"
  | "noDirectory"
  | "gitUnavailable"
  | "empty";

export type GitGraphRepoState = {
  status: GitGraphRepoStatus;
  repositoryName?: string;
  head?: GitGraphHead;
};

export type GitGraphContext = {
  labels: Record<string, string>;
  placement: "sidebar" | "tab";
  appearance: "dark" | "light";
};
