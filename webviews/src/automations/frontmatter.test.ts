import { expect, test } from "bun:test";
import { readFrontmatter, writeFrontmatter } from "./frontmatter";

test("reads name and description, unquoting them", () => {
  expect(readFrontmatter('---\nname: x\ndescription: "a: \\"b\\""\n---\nbody')).toEqual({ name: "x", description: 'a: "b"' });
  expect(readFrontmatter("no frontmatter")).toEqual({});
});

test("writes values, quoting when plain YAML would not parse, and round-trips", () => {
  const md = "---\nname: x\ndescription: >\n  folded\n  text\nallowed-tools: Read\n---\nBody";
  const out = writeFrontmatter(md, { name: "y", description: "Use when: things #1" });
  expect(out).toBe('---\nname: y\ndescription: "Use when: things #1"\nallowed-tools: Read\n---\nBody');
  expect(readFrontmatter(out)).toEqual({ name: "y", description: "Use when: things #1" });
});

test("adds missing keys and frontmatter", () => {
  expect(writeFrontmatter("---\nname: x\n---\nB", { description: "d" })).toBe("---\nname: x\ndescription: d\n---\nB");
  expect(writeFrontmatter("Body", { name: "n" })).toBe("---\nname: n\n---\nBody");
});
