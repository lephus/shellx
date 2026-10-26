import { FILE_STATUS_LETTER, formatDate } from "./format";
import type { GitGraphLabelResolver } from "./labels";
import { INDEX_SHA } from "./store";
import type { GitGraphCommit, GitGraphFileChange, GitGraphWorkingTree } from "./types";

type DetailPanelProps = {
  label: GitGraphLabelResolver;
  selectedSha: string | null;
  commit: GitGraphCommit | null;
  workingTree: GitGraphWorkingTree | null;
  files: GitGraphFileChange[] | null;
  filesState: "idle" | "loading" | "failed";
  onOpenFile: (path: string) => void;
};

export function DetailPanel({ label, selectedSha, commit, workingTree, files, filesState, onOpenFile }: DetailPanelProps) {
  if (selectedSha === INDEX_SHA) {
    return (
      <section className="gg-detail">
        <div className="gg-detail-info">
          <h2 className="gg-detail-subject">{label("uncommitted")}</h2>
          {workingTree ? (
            <div className="gg-counts">
              <span className="gg-add">+{workingTree.added}</span>
              <span className="gg-mod">~{workingTree.modified}</span>
              <span className="gg-del">−{workingTree.deleted}</span>
            </div>
          ) : null}
        </div>
      </section>
    );
  }
  if (selectedSha === null || commit === null) {
    return (
      <section className="gg-detail gg-detail-empty">
        <p className="gg-muted">{label("selectCommit")}</p>
      </section>
    );
  }
  return (
    <section className="gg-detail">
      <div className="gg-detail-info">
        <h2 className="gg-detail-subject">{commit.subject}</h2>
        <div className="gg-detail-meta">
          <span className="gg-mono">{commit.sha.slice(0, 10)}</span>
          <span>
            {commit.authorName} &lt;{commit.authorEmail}&gt;
          </span>
          <span>{formatDate(commit.authorDate)}</span>
        </div>
        {commit.parents.length > 1 ? <p className="gg-detail-note">{label("mergeNote")}</p> : null}
      </div>
      <div className="gg-detail-files">
        {filesState === "loading" ? <p className="gg-muted">{label("loading")}</p> : null}
        {filesState === "failed" ? <p className="gg-muted">{label("failed")}</p> : null}
        {files ? (
          <>
            <p className="gg-muted">{label("filesChanged", { count: files.length })}</p>
            <ul className="gg-file-list">
              {files.map((file) => {
                const name = file.oldPath ? `${file.oldPath} → ${file.path}` : file.path;
                return (
                  <li key={`${file.status}:${file.oldPath ?? ""}:${file.path}`}>
                    <button type="button" className="gg-file" title={name} onClick={() => onOpenFile(file.path)}>
                      <span className={`gg-file-status gg-file-status-${file.status}`}>
                        {FILE_STATUS_LETTER[file.status] ?? "?"}
                      </span>
                      <span className="gg-file-path">{name}</span>
                      {file.additions === null || file.deletions === null ? (
                        <span className="gg-muted">{label("binary")}</span>
                      ) : (
                        <>
                          <span className="gg-add">+{file.additions}</span>
                          <span className="gg-del">−{file.deletions}</span>
                        </>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          </>
        ) : null}
      </div>
    </section>
  );
}
