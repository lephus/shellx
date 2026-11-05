import { useId } from "react";
import type { ChartLayout, PlacedEdge, PlacedNode } from "./flowChartModel";
import type { AutomationLabelResolver } from "./labels";

type Props = {
  layout: ChartLayout;
  label: AutomationLabelResolver;
  /** The node drawn as running, e.g. `step-2` of a workflow. */
  runningNodeId?: string;
  /** Dims the chart while Claude rewrites the draft. */
  busy?: boolean;
};

const LINE_HEIGHT = 16;

const isDiamond = (node: PlacedNode) => node.shape === "decision" || node.shape === "askUser";

function baselines(node: PlacedNode): number[] {
  const first = node.y + node.h / 2 - ((node.lines.length - 1) * LINE_HEIGHT) / 2 + 4.5;
  return node.lines.map((_, index) => first + index * LINE_HEIGHT);
}

function ChartNodeShape({ node, running, runningText }: { node: PlacedNode; running: boolean; runningText: string }) {
  const cx = node.x + node.w / 2;
  const cy = node.y + node.h / 2;
  const numbered = node.number !== undefined;
  const ys = baselines(node);
  const badgeWidth = Array.from(runningText).length * 6.2 + 16;
  return (
    <g className="au-flow-node" data-node={node.id} data-shape={node.shape} data-running={running ? "true" : undefined}>
      {node.detail ? <title>{node.detail}</title> : null}
      {isDiamond(node) ? (
        <polygon
          className="au-flow-frame"
          points={`${cx},${node.y} ${node.x + node.w},${cy} ${cx},${node.y + node.h} ${node.x},${cy}`}
        />
      ) : (
        <rect
          className="au-flow-frame"
          x={node.x}
          y={node.y}
          width={node.w}
          height={node.h}
          rx={node.shape === "step" ? 9 : Math.min(21, node.h / 2)}
        />
      )}
      {numbered ? (
        <text className="au-flow-number" x={node.x + 16} y={ys[0]}>
          {node.number}
        </text>
      ) : null}
      {node.lines.map((line, index) => (
        <text
          key={`${index}:${line}`}
          className="au-flow-text"
          x={numbered ? node.x + 34 : cx}
          y={ys[index]}
          textAnchor={numbered ? "start" : "middle"}
        >
          {line}
        </text>
      ))}
      {running ? (
        <g className="au-flow-badge">
          <rect x={node.x + node.w - 10 - badgeWidth} y={node.y - 9} width={badgeWidth} height={18} rx={9} />
          <text x={node.x + node.w - 10 - badgeWidth / 2} y={node.y + 4} textAnchor="middle">
            {runningText}
          </text>
        </g>
      ) : null}
    </g>
  );
}

function EdgeLine({ edge, marker }: { edge: PlacedEdge; marker: string }) {
  const d = edge.points.map(([x, y], index) => `${index === 0 ? "M" : "L"}${x} ${y}`).join(" ");
  return (
    <g className="au-flow-link" data-back={edge.back ? "true" : undefined}>
      <path className="au-flow-edge" d={d} markerEnd={`url(#${marker})`} />
      {edge.label && edge.labelAt ? (
        <text className="au-flow-edge-label" x={edge.labelAt[0]} y={edge.labelAt[1]}>
          {edge.label}
        </text>
      ) : null}
    </g>
  );
}

/**
 * Lines for the text alternative, as "Approve? → No: Stop": branches, labelled edges, loops, and a
 * lone edge whose target is not `nextId`, the node listed right after this one.
 */
function branchTexts(layout: ChartLayout, node: PlacedNode, nextId: string | undefined): string[] {
  const outgoing = layout.edges.filter((e) => e.from === node.id);
  const labels = new Map(layout.nodes.map((n) => [n.id, n.label]));
  return outgoing
    .filter((e) => outgoing.length > 1 || e.label !== undefined || e.back || e.to !== nextId)
    .map((e) => `${node.label} → ${e.label !== undefined ? `${e.label}: ` : ""}${labels.get(e.to) ?? e.to}`);
}

/** The view-only flowchart as SVG, with a visually hidden ordered list for screen readers. */
export function FlowChart({ layout, label, runningNodeId, busy = false }: Props) {
  const marker = `au-flow-arrow-${useId().replace(/[^\w-]/g, "")}`;
  const runningText = label("flowRunning");
  return (
    <div className="au-flow" data-busy={busy ? "true" : undefined} aria-busy={busy || undefined}>
      <svg
        className="au-flow-svg"
        viewBox={`0 0 ${layout.width} ${layout.height}`}
        width={layout.width}
        height={layout.height}
        aria-hidden="true"
        focusable="false"
      >
        <defs>
          <marker id={marker} viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
            <path className="au-flow-arrow" d="M0,0 L10,5 L0,10 z" />
          </marker>
        </defs>
        {layout.edges.map((edge, index) => (
          <EdgeLine key={`${index}:${edge.from}:${edge.to}`} edge={edge} marker={marker} />
        ))}
        {layout.nodes.map((node) => (
          <ChartNodeShape key={node.id} node={node} running={node.id === runningNodeId} runningText={runningText} />
        ))}
      </svg>
      <ol className="au-visually-hidden">
        {layout.nodes.map((node, index) => {
          const branches = branchTexts(layout, node, layout.nodes[index + 1]?.id);
          const extra = [node.detail, node.id === runningNodeId ? runningText : undefined].filter(Boolean).join(" · ");
          return (
            <li key={node.id}>
              <span className="au-flow-a11y-node">{node.label}</span>
              {extra ? ` (${extra})` : null}
              {branches.length > 0 ? (
                <ul>
                  {branches.map((text) => (
                    <li key={text}>{text}</li>
                  ))}
                </ul>
              ) : null}
            </li>
          );
        })}
      </ol>
    </div>
  );
}
