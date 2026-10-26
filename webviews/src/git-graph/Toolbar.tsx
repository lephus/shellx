import type { KeyboardEvent } from "react";
import type { GitGraphLabelResolver } from "./labels";
import type { GitGraphRef, GitGraphRefKind } from "./types";

type ToolbarProps = {
  label: GitGraphLabelResolver;
  showOpenAsTab: boolean;
  refs: GitGraphRef[];
  branch: string | null;
  includeRemotes: boolean;
  query: string;
  matchCount: number;
  matchIndex: number;
  onBranchChange: (fullName: string | null) => void;
  onIncludeRemotesChange: (includeRemotes: boolean) => void;
  onQueryChange: (query: string) => void;
  onSearchStep: (direction: 1 | -1) => void;
  onRefresh: () => void;
  onOpenAsTab: () => void;
};

const PICKER_ORDER: Record<GitGraphRefKind, number> = { localBranch: 0, remoteBranch: 1, tag: 2 };

/** Picker entries: local branches first, then remotes (when shown), then tags. */
export function pickerRefs(refs: GitGraphRef[], includeRemotes: boolean): GitGraphRef[] {
  return refs
    .filter((ref) => includeRemotes || ref.kind !== "remoteBranch")
    .map((ref, index) => ({ ref, index }))
    .sort((a, b) => PICKER_ORDER[a.ref.kind] - PICKER_ORDER[b.ref.kind] || a.index - b.index)
    .map(({ ref }) => ref);
}

export function Toolbar(props: ToolbarProps) {
  const { label, query, matchCount, matchIndex } = props;
  const onSearchKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") {
      event.preventDefault();
      props.onSearchStep(event.shiftKey ? -1 : 1);
    } else if (event.key === "Escape" && query !== "") {
      event.preventDefault();
      props.onQueryChange("");
    }
  };
  const searching = query.trim() !== "";
  const searchStatus =
    matchCount === 0
      ? label("searchNoResults")
      : label("searchCount", { current: matchIndex + 1, total: matchCount });
  return (
    <div className="gg-toolbar">
      <select
        className="gg-select"
        aria-label={label("allBranches")}
        value={props.branch ?? ""}
        onChange={(event) => props.onBranchChange(event.target.value === "" ? null : event.target.value)}
      >
        <option value="">{label("allBranches")}</option>
        {pickerRefs(props.refs, props.includeRemotes).map((ref) => (
          <option key={ref.fullName} value={ref.fullName}>
            {ref.name}
          </option>
        ))}
      </select>
      <label className="gg-toggle">
        <input
          type="checkbox"
          aria-label={label("showRemotes")}
          checked={props.includeRemotes}
          onChange={(event) => props.onIncludeRemotesChange(event.target.checked)}
        />
        <span>{label("showRemotes")}</span>
      </label>
      <div className="gg-search">
        <input
          type="search"
          className="gg-search-input"
          placeholder={label("searchPlaceholder")}
          aria-label={label("searchPlaceholder")}
          value={query}
          onChange={(event) => props.onQueryChange(event.target.value)}
          onKeyDown={onSearchKeyDown}
          spellCheck={false}
        />
        {searching ? (
          <span className="gg-search-count" aria-live="polite" title={searchStatus}>
            {searchStatus}
          </span>
        ) : null}
      </div>
      <button
        type="button"
        className="gg-icon-button"
        title={label("refresh")}
        aria-label={label("refresh")}
        onClick={props.onRefresh}
      >
        ↻
      </button>
      {props.showOpenAsTab ? (
        <button
          type="button"
          className="gg-icon-button"
          title={label("openAsTab")}
          aria-label={label("openAsTab")}
          onClick={props.onOpenAsTab}
        >
          ⤢
        </button>
      ) : null}
    </div>
  );
}
