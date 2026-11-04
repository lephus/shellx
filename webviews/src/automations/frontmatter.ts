// Keeps the card's name and description in step with the SKILL.md frontmatter.
// Mirrors the Swift `ShellXSkillFrontmatter` reader: `key: value` lines between `---` lines.

type Front = { name?: string; description?: string };

/** The frontmatter block's line range, or null when the markdown has none. */
function block(lines: string[]): { end: number } | null {
  if (lines[0]?.trim() !== "---") return null;
  const end = lines.findIndex((line, i) => i > 0 && line.trim() === "---");
  return end === -1 ? null : { end };
}

function unquote(value: string): string {
  const v = value.trim();
  if (v.length < 2 || v[v.length - 1] !== v[0]) return v;
  if (v[0] === "'") return v.slice(1, -1).replace(/''/g, "'");
  if (v[0] === '"') return v.slice(1, -1).replace(/\\(["\\])/g, "$1");
  return v;
}

/** YAML-safe scalar for one line: quoted when plain text would not parse. */
function scalar(value: string): string {
  const v = value.replace(/\s*\n\s*/g, " ").trim();
  const plain = v !== "" && !/^[\s\-?:,[\]{}#&*!|>'"%@`]/.test(v) && !/:\s|\s#|:$/.test(v);
  return plain ? v : `"${v.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

export function readFrontmatter(markdown: string): Front {
  const lines = markdown.split(/\r?\n/);
  const range = block(lines);
  if (!range) return {};
  const front: Front = {};
  for (const line of lines.slice(1, range.end)) {
    if (line.startsWith(" ") || line.startsWith("#")) continue;
    const colon = line.indexOf(":");
    if (colon === -1) continue;
    const key = line.slice(0, colon).trim();
    if (key === "name" || key === "description") front[key] = unquote(line.slice(colon + 1));
  }
  return front;
}

/** `markdown` with its frontmatter `name`/`description` set; adds frontmatter when there is none. */
export function writeFrontmatter(markdown: string, values: Front): string {
  const lines = markdown.split(/\r?\n/);
  let end = block(lines)?.end ?? -1;
  if (end === -1) {
    lines.unshift("---", "---");
    end = 1;
  }
  for (const key of ["name", "description"] as const) {
    const value = values[key];
    if (value === undefined) continue;
    const next = `${key}: ${scalar(value)}`;
    const at = lines.findIndex((line, i) => i > 0 && i < end && line.startsWith(`${key}:`));
    if (at === -1) {
      lines.splice(end, 0, next);
      end += 1;
      continue;
    }
    // Drop indented continuation lines of a folded value.
    let stop = at + 1;
    while (stop < end && /^\s+\S/.test(lines[stop] ?? "")) stop++;
    lines.splice(at, stop - at, next);
    end -= stop - at - 1;
  }
  return lines.join("\n");
}
