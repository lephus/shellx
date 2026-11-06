// Pure model and layout of the view-only automation flowchart (drawn by FlowChart.tsx).
import { notifyOnLabel, notifyTargetLabel } from "./format";
import type { AutomationLabelResolver } from "./labels";
import type {
  AutomationFlow,
  AutomationKind,
  AutomationNotify,
  AutomationSchedule,
  AutomationStep,
  FlowEdge,
  FlowNode,
  FlowNodeType,
} from "./types";

export type ChartShape = "start" | "step" | "decision" | "askUser" | "end" | "notify";
export type ChartNode = { id: string; shape: ChartShape; label: string; number?: number; detail?: string };
/** The first node is the start node. */
export type ChartModel = { nodes: ChartNode[]; edges: FlowEdge[] };
export type ChartSource = {
  kind: AutomationKind;
  description: string;
  schedule?: AutomationSchedule | null;
  notify: AutomationNotify;
  steps: AutomationStep[];
  flow: AutomationFlow | null;
};

export type PlacedNode = ChartNode & { x: number; y: number; w: number; h: number; lines: string[] };
/** `labelAt` is the start of the label's baseline, set when the edge has a label. */
export type PlacedEdge = {
  from: string;
  to: string;
  label?: string;
  points: [number, number][];
  back: boolean;
  labelAt?: [number, number];
};
export type ChartLayout = { width: number; height: number; nodes: PlacedNode[]; edges: PlacedEdge[] };

const NODE_TYPES: readonly FlowNodeType[] = ["step", "decision", "askUser", "end"];
const START_DESCRIPTION_MAX = 80;

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null;
const optionalText = (value: unknown) => value === undefined || value === null || typeof value === "string";

/**
 * The flow when it is safe to draw, else null. Same rule as Swift `ShellXAutomationFlow.isUsable`
 * (at least one node, unique non-empty ids, every edge joins two nodes), plus known node types.
 * Null optional fields are dropped, as Swift decodes them to nil.
 */
export function usableFlow(flow: unknown): AutomationFlow | null {
  if (!isRecord(flow) || !Array.isArray(flow.nodes) || !Array.isArray(flow.edges) || !optionalText(flow.trigger)) {
    return null;
  }
  if (flow.nodes.length === 0) return null;
  const nodes: FlowNode[] = [];
  const ids = new Set<string>();
  for (const node of flow.nodes) {
    if (!isRecord(node) || typeof node.id !== "string" || node.id === "" || ids.has(node.id)) return null;
    if (!NODE_TYPES.includes(node.type as FlowNodeType) || typeof node.label !== "string") return null;
    if (!optionalText(node.detail)) return null;
    ids.add(node.id);
    nodes.push({
      id: node.id,
      type: node.type as FlowNodeType,
      label: node.label,
      ...(typeof node.detail === "string" ? { detail: node.detail } : {}),
    });
  }
  const edges: FlowEdge[] = [];
  for (const edge of flow.edges) {
    if (!isRecord(edge) || typeof edge.from !== "string" || typeof edge.to !== "string") return null;
    if (!ids.has(edge.from) || !ids.has(edge.to) || !optionalText(edge.label)) return null;
    edges.push({ from: edge.from, to: edge.to, ...(typeof edge.label === "string" ? { label: edge.label } : {}) });
  }
  return { ...(typeof flow.trigger === "string" ? { trigger: flow.trigger } : {}), nodes, edges };
}

function cut(text: string, max: number): string {
  const chars = Array.from(text.trim());
  return chars.length <= max ? chars.join("") : `${chars.slice(0, max - 1).join("").trimEnd()}…`;
}

function startLabel(source: ChartSource, flow: AutomationFlow | null, label: AutomationLabelResolver): string {
  if (source.kind === "skill") {
    const trigger = flow?.trigger?.trim();
    return trigger ? trigger : cut(source.description, START_DESCRIPTION_MAX);
  }
  const human = source.schedule?.human.trim();
  return human ? human : label("flowStartManual");
}

/**
 * The chart of an automation: a start node, its steps (workflow) or flow (skill, cronjob),
 * then a notify node (workflow, cronjob) or, for a workflow that notifies nobody, a Done node.
 * Null when a skill or cronjob has no usable flow.
 */
export function buildChart(source: ChartSource, label: AutomationLabelResolver): ChartModel | null {
  const flow = source.kind === "workflow" ? null : usableFlow(source.flow);
  if (source.kind !== "workflow" && flow === null) return null;

  const nodes: ChartNode[] = [{ id: "start", shape: "start", label: startLabel(source, flow, label) }];
  const edges: FlowEdge[] = [];
  if (flow === null) {
    source.steps.forEach((step, index) => {
      const id = `step-${index + 1}`;
      nodes.push({ id, shape: "step", label: step.title, number: index + 1 });
      edges.push({ from: index === 0 ? "start" : `step-${index}`, to: id });
    });
  } else {
    const id = chartIds(flow);
    let number = 0;
    for (const node of flow.nodes) {
      nodes.push({
        id: id(node.id),
        shape: node.type,
        label: node.label,
        ...(node.type === "step" ? { number: ++number } : {}),
        ...(node.detail !== undefined ? { detail: node.detail } : {}),
      });
    }
    edges.push(
      { from: "start", to: id(flow.nodes[0]?.id ?? "") },
      ...flow.edges.map((e) => ({ ...e, from: id(e.from), to: id(e.to) })),
    );
  }

  const tail = tailNode(source, label);
  if (tail) {
    const sources = new Set(edges.map((e) => e.from));
    for (const node of nodes) if (!sources.has(node.id)) edges.push({ from: node.id, to: tail.id });
    nodes.push(tail);
  }
  return { nodes, edges };
}

const CHART_IDS = new Set(["start", "notify", "done"]);

/** Renames flow node ids that clash with the ids the chart adds (`start`, `notify`, `done`). */
function chartIds(flow: AutomationFlow): (id: string) => string {
  const taken = new Set([...CHART_IDS, ...flow.nodes.map((n) => n.id)]);
  const renamed = new Map<string, string>();
  for (const { id } of flow.nodes) {
    if (!CHART_IDS.has(id)) continue;
    let next = `flow-${id}`;
    for (let n = 2; taken.has(next); n++) next = `flow-${id}-${n}`;
    taken.add(next);
    renamed.set(id, next);
  }
  return (id) => renamed.get(id) ?? id;
}

function tailNode(source: ChartSource, label: AutomationLabelResolver): ChartNode | null {
  if (source.kind === "skill") return null;
  if (source.notify.on.length > 0) {
    const targets = source.notify.targets.map((t) => notifyTargetLabel(label, t)).join(" + ");
    const events = source.notify.on.map((o) => notifyOnLabel(label, o)).join(", ");
    return { id: "notify", shape: "notify", label: label("flowNotify", { targets, events }) };
  }
  return source.kind === "workflow" ? { id: "done", shape: "end", label: label("flowDone") } : null;
}

// Geometry. Text width is estimated: the page renders offline and the layout stays pure.
const PAD = 12;
const RANK_GAP = 26;
const COLUMN_GAP = 48;
const LANE_OFFSET = 24;
const LANE_STEP = 10;
const MAIN_WIDTH = 300;
const SIDE_WIDTH = 170;
const DIAMOND_WIDTH = 140;
const DIAMOND_HEIGHT = 88;
const MIN_HEIGHT = 42;
const LINE_HEIGHT = 16;
const MAX_LINES = 3;
const UNIT_WIDTH = 6.8;

/** Characters per line, by shape and column. Wide (CJK) characters count twice. */
function lineUnits(shape: ChartShape, column: number): number {
  if (shape === "decision" || shape === "askUser") return 18;
  return column === 0 ? 36 : 22;
}

const charUnits = (char: string) => ((char.codePointAt(0) ?? 0) >= 0x2e80 ? 2 : 1);
const textUnits = (text: string) => Array.from(text).reduce((sum, c) => sum + charUnits(c), 0);

/** Splits `text` into at most `maxLines` lines of at most `max` units, ending with "…" when cut. */
function wrapLabel(text: string, max: number, maxLines = MAX_LINES): string[] {
  const lines: string[] = [];
  let line = "";
  for (const word of text.trim().split(/\s+/)) {
    let rest = word;
    while (textUnits(rest) > max) {
      if (line !== "") lines.push(line);
      line = "";
      let head = "";
      for (const char of rest) {
        if (textUnits(head) + charUnits(char) > max) break;
        head += char;
      }
      lines.push(head);
      rest = rest.slice(head.length);
    }
    if (rest === "") continue;
    if (line === "") line = rest;
    else if (textUnits(line) + 1 + textUnits(rest) <= max) line += ` ${rest}`;
    else {
      lines.push(line);
      line = rest;
    }
  }
  if (line !== "") lines.push(line);
  if (lines.length === 0) return [""];
  if (lines.length <= maxLines) return lines;
  const kept = lines.slice(0, maxLines);
  let last = kept[maxLines - 1] ?? "";
  while (last !== "" && textUnits(last) + 1 > max) last = Array.from(last).slice(0, -1).join("");
  kept[maxLines - 1] = `${last.trimEnd()}…`;
  return kept;
}

function nodeSize(shape: ChartShape, column: number, lines: string[]): { w: number; h: number } {
  const units = Math.max(...lines.map(textUnits));
  const textHeight = lines.length * LINE_HEIGHT;
  const columnWidth = column === 0 ? MAIN_WIDTH : SIDE_WIDTH;
  if (shape === "decision" || shape === "askUser") {
    // Text of width tw and height th fits inside a diamond W × H when tw / W + th / H ≤ 1.
    const h = lines.length <= 2 ? DIAMOND_HEIGHT : DIAMOND_HEIGHT + LINE_HEIGHT;
    const w = Math.ceil((units * UNIT_WIDTH) / (1 - textHeight / h)) + 12;
    return { w: Math.min(MAIN_WIDTH, Math.max(DIAMOND_WIDTH, w)), h };
  }
  const h = Math.max(MIN_HEIGHT, textHeight + 20);
  if (shape === "end") return { w: Math.min(columnWidth, Math.max(104, Math.ceil(units * UNIT_WIDTH) + 48)), h };
  return { w: columnWidth, h };
}

type Ranked = { ranks: Map<string, number>; dfsBack: Set<number> };

/** Back edges (DFS from start, in edge order) and ranks (longest path over the other edges). */
function rankNodes(model: ChartModel, out: Map<string, number[]>): Ranked {
  const { nodes, edges } = model;
  const dfsBack = new Set<number>();
  const state = new Map<string, "open" | "done">();
  const postorder: string[] = [];
  const visit = (id: string) => {
    state.set(id, "open");
    for (const index of out.get(id) ?? []) {
      const to = edges[index]?.to ?? "";
      const seen = state.get(to);
      if (seen === "open") dfsBack.add(index);
      else if (seen === undefined) visit(to);
    }
    state.set(id, "done");
    postorder.push(id);
  };
  const start = nodes[0]?.id;
  if (start !== undefined) visit(start);

  const ranks = new Map<string, number>();
  if (start !== undefined) ranks.set(start, 0);
  for (const id of postorder.reverse()) {
    const rank = ranks.get(id) ?? 0;
    for (const index of out.get(id) ?? []) {
      if (dfsBack.has(index)) continue;
      const to = edges[index]?.to ?? "";
      ranks.set(to, Math.max(ranks.get(to) ?? 0, rank + 1));
    }
  }
  let next = Math.max(-1, ...ranks.values()) + 1;
  for (const node of nodes) if (!ranks.has(node.id)) ranks.set(node.id, next++);
  return { ranks, dfsBack };
}

/** Column 0 is the main path (first edges from start); other children go right, keeping their first column. */
function assignColumns(model: ChartModel, out: Map<string, number[]>, ranked: Ranked, order: ChartNode[]) {
  const { edges } = model;
  const { ranks, dfsBack } = ranked;
  const columns = new Map<string, number>();
  const taken = new Map<number, Set<number>>();
  const take = (id: string, from: number) => {
    const rank = ranks.get(id) ?? 0;
    const used = taken.get(rank) ?? new Set<number>();
    let column = from;
    while (used.has(column)) column++;
    used.add(column);
    taken.set(rank, used);
    columns.set(id, column);
  };
  const forward = (id: string) => (out.get(id) ?? []).filter((index) => !dfsBack.has(index));

  let current: string | undefined = model.nodes[0]?.id;
  while (current !== undefined && !columns.has(current)) {
    take(current, 0);
    const first = forward(current)[0];
    current = first === undefined ? undefined : edges[first]?.to;
  }
  for (const node of order) {
    if (!columns.has(node.id)) take(node.id, 0);
    const column = columns.get(node.id) ?? 0;
    forward(node.id).forEach((index, position) => {
      const to = edges[index]?.to ?? "";
      if (!columns.has(to)) take(to, position === 0 ? column : column + 1);
    });
  }
  return columns;
}

type Point = [number, number];

/** True when the axis-aligned segment a–b passes through the inside of the node's box. */
function segmentHitsBox(a: Point, b: Point, n: PlacedNode): boolean {
  return (
    Math.max(a[0], b[0]) > n.x &&
    Math.min(a[0], b[0]) < n.x + n.w &&
    Math.max(a[1], b[1]) > n.y &&
    Math.min(a[1], b[1]) < n.y + n.h
  );
}

/** Drops repeated points and the middle point of three in a line. */
function simplify(points: Point[]): Point[] {
  const unique = points.filter((p, i) => i === 0 || p[0] !== points[i - 1]?.[0] || p[1] !== points[i - 1]?.[1]);
  return unique.filter((p, i) => {
    const prev = unique[i - 1];
    const next = unique[i + 1];
    if (!prev || !next) return true;
    return !((prev[0] === p[0] && p[0] === next[0]) || (prev[1] === p[1] && p[1] === next[1]));
  });
}

const direction = (points: Point[]): Point => {
  const [a, b] = points;
  return a && b ? [Math.sign(b[0] - a[0]), Math.sign(b[1] - a[1])] : [0, 0];
};

/** True when two routes leave from the same point in the same direction. */
function sameStart(a: Point[], b: Point[]): boolean {
  const [da, db] = [direction(a), direction(b)];
  return a[0]?.[0] === b[0]?.[0] && a[0]?.[1] === b[0]?.[1] && da[0] === db[0] && da[1] === db[1];
}

/** Where an edge label goes: beside segment `index` (or the last one), near its start. */
function labelPoint(points: Point[], index: number): Point {
  const i = Math.min(index, points.length - 2);
  const [ax, ay] = points[i] ?? [0, 0];
  const [bx, by] = points[i + 1] ?? [ax, ay];
  if (ay === by) return [Math.min(ax, bx) + 6, ay - 6];
  return [ax + 8, by > ay ? ay + 14 : ay - 6];
}

/** Places the chart top to bottom, branches to the right, loops through a lane right of every node. */
export function layoutChart(model: ChartModel): ChartLayout {
  const ids = new Set(model.nodes.map((n) => n.id));
  const edges = model.edges.filter((e) => ids.has(e.from) && ids.has(e.to));
  const clean: ChartModel = { nodes: model.nodes, edges };
  const out = new Map<string, number[]>();
  edges.forEach((edge, index) => out.set(edge.from, [...(out.get(edge.from) ?? []), index]));

  const ranked = rankNodes(clean, out);
  const { ranks } = ranked;
  const input = new Map(model.nodes.map((n, i) => [n.id, i]));
  const byRank = [...model.nodes].sort(
    (a, b) => (ranks.get(a.id) ?? 0) - (ranks.get(b.id) ?? 0) || (input.get(a.id) ?? 0) - (input.get(b.id) ?? 0),
  );
  const columns = assignColumns(clean, out, ranked, byRank);
  const columnOf = (id: string) => columns.get(id) ?? 0;
  const rankOf = (id: string) => ranks.get(id) ?? 0;

  const sized = byRank.map((node) => {
    const lines = wrapLabel(node.label, lineUnits(node.shape, columnOf(node.id)));
    return { node, lines, ...nodeSize(node.shape, columnOf(node.id), lines) };
  });
  const columnWidths: number[] = [];
  const rowHeights: number[] = [];
  for (const { node, w, h } of sized) {
    const column = columnOf(node.id);
    const rank = rankOf(node.id);
    columnWidths[column] = Math.max(columnWidths[column] ?? 0, w, column === 0 ? MAIN_WIDTH : SIDE_WIDTH);
    rowHeights[rank] = Math.max(rowHeights[rank] ?? 0, h);
  }
  const columnLeft: number[] = [];
  for (let c = 0, left = PAD; c < columnWidths.length; c++) {
    columnLeft[c] = left;
    left += (columnWidths[c] ?? 0) + COLUMN_GAP;
  }
  const rowTop: number[] = [];
  for (let r = 0, top = PAD; r < rowHeights.length; r++) {
    rowTop[r] = top;
    top += (rowHeights[r] ?? 0) + RANK_GAP;
  }

  const nodes: PlacedNode[] = sized.map(({ node, lines, w, h }) => {
    const column = columnOf(node.id);
    const rank = rankOf(node.id);
    const centerX = (columnLeft[column] ?? PAD) + (columnWidths[column] ?? w) / 2;
    const y = (rowTop[rank] ?? PAD) + ((rowHeights[rank] ?? h) - h) / 2;
    return { ...node, x: centerX - w / 2, y, w, h, lines };
  });
  const placed = new Map(nodes.map((n) => [n.id, n]));
  const maxRight = Math.max(...nodes.map((n) => n.x + n.w));
  const maxBottom = Math.max(...nodes.map((n) => n.y + n.h));

  const columnChannel = (column: number) =>
    (columnLeft[column] ?? PAD) + (columnWidths[column] ?? 0) + COLUMN_GAP / 2;
  const gapBelow = (rank: number) => (rowTop[rank] ?? PAD) + (rowHeights[rank] ?? 0) + RANK_GAP / 2;
  const gapAbove = (rank: number) => Math.max(PAD / 2, (rowTop[rank] ?? PAD) - RANK_GAP / 2);
  const blocked = (points: Point[], s: PlacedNode, t: PlacedNode) =>
    points.some((p, i) => i > 0 && nodes.some((n) => n !== s && n !== t && segmentHitsBox(points[i - 1] as Point, p, n)));

  /**
   * A route through the gaps between rows and columns, where no box sits. It leaves the source by its
   * right edge or its bottom, runs along `via` between the rows, and enters the target by its right edge or top.
   */
  const gapRoute = (s: PlacedNode, t: PlacedNode, exitRight: boolean, enterRight: boolean, via: number): Point[] => {
    const below = gapBelow(rankOf(s.id));
    const above = gapAbove(rankOf(t.id));
    const sChannel = columnChannel(columnOf(s.id));
    const tChannel = columnChannel(columnOf(t.id));
    const exit: Point[] = exitRight
      ? [[s.x + s.w, s.y + s.h / 2], [sChannel, s.y + s.h / 2], [sChannel, below]]
      : [[s.x + s.w / 2, s.y + s.h], [s.x + s.w / 2, below]];
    const entry: Point[] = enterRight
      ? [[tChannel, above], [tChannel, t.y + t.h / 2], [t.x + t.w, t.y + t.h / 2]]
      : [[t.x + t.w / 2, above], [t.x + t.w / 2, t.y]];
    const between: Point[] = below === above ? [] : [[via, below], [via, above]];
    return simplify([...exit, ...between, ...entry]);
  };

  let lanes = 0;
  const routed = edges.map((edge) => {
    const s = placed.get(edge.from) as PlacedNode;
    const t = placed.get(edge.to) as PlacedNode;
    const back = rankOf(edge.to) <= rankOf(edge.from);
    const sRight: Point = [s.x + s.w, s.y + s.h / 2];
    const tRight: Point = [t.x + t.w, t.y + t.h / 2];
    const sCenter = s.x + s.w / 2;
    const tCenter = t.x + t.w / 2;
    const from = columnOf(edge.from);
    const to = columnOf(edge.to);
    let direct: Point[];
    let fallback: () => Point[];
    if (back) {
      const lane = maxRight + LANE_OFFSET + LANE_STEP * lanes++;
      direct =
        s === t
          ? [[sRight[0], sRight[1] - 8], [lane, sRight[1] - 8], [lane, sRight[1] + 8], [sRight[0], sRight[1] + 8]]
          : [sRight, [lane, sRight[1]], [lane, tRight[1]], tRight];
      fallback = () => gapRoute(s, t, true, true, lane);
    } else if (to > from) {
      direct = [sRight, [tCenter, sRight[1]], [tCenter, t.y]];
      fallback = () => gapRoute(s, t, true, false, columnChannel(from));
    } else if (to < from) {
      direct = [[sCenter, s.y + s.h], [sCenter, tRight[1]], tRight];
      fallback = () => gapRoute(s, t, false, true, columnChannel(to));
    } else {
      direct = [[sCenter, s.y + s.h], [sCenter, t.y]];
      fallback = () => gapRoute(s, t, true, true, columnChannel(from));
    }
    // Any box in the way would read as a step the edge runs through: go round it through the gaps.
    const points = blocked(direct, s, t) ? fallback() : direct;
    return { edge, points, back };
  });

  const placedEdges: PlacedEdge[] = routed.map(({ edge, points, back }) => {
    if (edge.label === undefined) return { from: edge.from, to: edge.to, points, back };
    // Branches that leave by the same point and way share their first segment: label the next one instead.
    const shared = routed.some(
      (other) => other.edge !== edge && other.edge.from === edge.from && sameStart(other.points, points),
    );
    return { from: edge.from, to: edge.to, label: edge.label, points, back, labelAt: labelPoint(points, shared ? 1 : 0) };
  });

  const right = Math.max(maxRight, ...placedEdges.flatMap((e) => e.points.map(([x]) => x)));
  const bottom = Math.max(maxBottom, ...placedEdges.flatMap((e) => e.points.map(([, y]) => y)));
  // Reading order for the text alternative: rank, then column.
  nodes.sort((a, b) => rankOf(a.id) - rankOf(b.id) || columnOf(a.id) - columnOf(b.id));
  return { width: Math.ceil(right + PAD), height: Math.ceil(bottom + PAD), nodes, edges: placedEdges };
}
