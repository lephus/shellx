import type { CustomTableRow, CustomTableRowProps } from "@tomplum/react-git-log";
import { createContext, useContext, type HTMLAttributes } from "react";
import { formatDate, formatRelative, shortSha } from "./format";
import type { GitGraphLabelResolver } from "./labels";
import { visibleChips, type GitGraphLayout, type RefChip } from "./model";
import { INDEX_SHA } from "./store";
import type { GitGraphWorkingTree } from "./types";

export type CommitRowContextValue = {
  chipsByCommit: Map<string, RefChip[]>;
  layout: GitGraphLayout;
  matches: ReadonlySet<string>;
  currentMatch: string | null;
  workingTree: GitGraphWorkingTree | null;
  label: GitGraphLabelResolver;
  now: number;
};

export const CommitRowContext = createContext<CommitRowContextValue | null>(null);

// react-git-log clones the row element with its own `id`, `onClick`,
// `onMouseOver`, `onMouseOut` and `data-testid`; they land in `rest` and must
// reach the root element, or selection and hover stop working.
type CommitRowViewProps = CustomTableRowProps & HTMLAttributes<HTMLDivElement>;

function CommitRowView({ commit, selected, previewed, backgroundColour, ...rest }: CommitRowViewProps) {
  const context = useContext(CommitRowContext);
  if (!context) return null;
  const { chipsByCommit, layout, matches, currentMatch, workingTree, label, now } = context;
  const isIndex = commit.hash === INDEX_SHA;
  const highlighted = backgroundColour !== "transparent" && (selected || previewed);
  return (
    <div
      {...rest}
      className="gg-row"
      data-sha={commit.hash}
      data-merge={commit.parents.length > 1 ? "true" : undefined}
      data-match={matches.has(commit.hash) ? "true" : undefined}
      data-current-match={currentMatch === commit.hash ? "true" : undefined}
      style={highlighted ? { backgroundColor: backgroundColour } : undefined}
    >
      {isIndex ? (
        <>
          <span className="gg-msg gg-wip">{label("uncommitted")}</span>
          {workingTree ? (
            <span className="gg-counts">
              <span className="gg-add">+{workingTree.added}</span>
              <span className="gg-mod">~{workingTree.modified}</span>
              <span className="gg-del">−{workingTree.deleted}</span>
            </span>
          ) : null}
        </>
      ) : (
        <>
          <Chips chips={chipsByCommit.get(commit.hash) ?? []} layout={layout} />
          <span className="gg-msg" title={commit.message}>
            {commit.message}
          </span>
          {layout === "wide" ? (
            <>
              <span className="gg-cell gg-cell-date">{formatDate(commit.committerDate)}</span>
              <span className="gg-cell gg-cell-author" title={commit.author?.email}>
                {commit.author?.name}
              </span>
              <span className="gg-cell gg-cell-hash">{shortSha(commit.hash)}</span>
            </>
          ) : (
            <span className="gg-cell gg-cell-age" title={formatDate(commit.committerDate)}>
              {formatRelative(commit.committerDate, now)}
            </span>
          )}
        </>
      )}
    </div>
  );
}

function Chips({ chips, layout }: { chips: RefChip[]; layout: GitGraphLayout }) {
  if (chips.length === 0) return null;
  const { shown, overflow } = visibleChips(chips, layout);
  const hidden = chips.slice(shown.length).map((chip) => chip.label).join(", ");
  return (
    <span className="gg-chips">
      {shown.map((chip) => (
        <span key={`${chip.kind}:${chip.label}`} className={`gg-chip gg-chip-${chip.kind}`} title={chip.label}>
          {chip.label}
        </span>
      ))}
      {overflow > 0 ? (
        <span className="gg-chip gg-chip-more" title={hidden}>
          +{overflow}
        </span>
      ) : null}
    </span>
  );
}

/** The `row` renderer for `GitLog.Table`; its data comes from `CommitRowContext`. */
export const CommitRow: CustomTableRow = (props) => <CommitRowView {...props} />;
