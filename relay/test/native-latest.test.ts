import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { readNativeLatest } from "../src/native-latest.js";
import { tempDir } from "./helpers.js";

const GOOD = {
  version: "2.0.0",
  url: "https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg",
  sha256: "a".repeat(64),
  min_os: "14.0",
  published_at_unix: 1790000000,
};

function dirWith(file: string, content: unknown): string {
  const dir = join(tempDir(), "m");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, file), typeof content === "string" ? content : JSON.stringify(content));
  return dir;
}

afterEach(() => vi.restoreAllMocks());

describe("readNativeLatest", () => {
  it("reads a valid manifest", () => {
    const dir = dirWith("latest-macos.json", GOOD);
    expect(readNativeLatest(dir, "macos", 1000)).toEqual({ version: "2.0.0", url: GOOD.url, sha256: GOOD.sha256, minOs: "14.0" });
  });

  it("a missing file is null without a log line", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    expect(readNativeLatest(join(tempDir(), "none"), "windows", 1000)).toBeNull();
    expect(log).not.toHaveBeenCalled();
  });

  const invalid: [string, unknown][] = [
    ["version not semver", { ...GOOD, version: "2.0" }],
    ["url outside the version folder", { ...GOOD, url: "https://download.shellx.pro/desktop/1.0.0/ShellX-2.0.0.dmg" }],
    ["url on another host", { ...GOOD, url: "https://evil.example/desktop/2.0.0/ShellX-2.0.0.dmg" }],
    ["file over 4 KB", { ...GOOD, extra: "x".repeat(5000) }],
    ["invalid JSON", "{nope"],
    ["bad sha256", { ...GOOD, sha256: "zz" }],
  ];
  for (const [name, content] of invalid) {
    it(`${name} is null and logs native_latest_invalid with the platform only`, () => {
      const log = vi.spyOn(console, "log").mockImplementation(() => {});
      const dir = dirWith("latest-macos.json", content);
      expect(readNativeLatest(dir, "macos", 1000)).toBeNull();
      expect(log).toHaveBeenCalledTimes(1);
      const line = JSON.parse(String(log.mock.calls[0]![0]));
      expect(line).toMatchObject({ event: "native_latest_invalid", platform: "macos" });
      expect(Object.keys(line).sort()).toEqual(["event", "platform", "ts"]);
    });
  }

  it("caches per platform for 60 s, then reads again", () => {
    const dir = join(tempDir(), "cache");
    const read = vi.fn((path: string) => (path.endsWith("latest-macos.json") ? JSON.stringify(GOOD) : null));
    expect(readNativeLatest(dir, "macos", 1000, read)?.version).toBe("2.0.0");
    expect(readNativeLatest(dir, "macos", 60_999, read)?.version).toBe("2.0.0");
    expect(read).toHaveBeenCalledTimes(1);
    expect(readNativeLatest(dir, "windows", 1000, read)).toBeNull();
    expect(read).toHaveBeenCalledTimes(2);
    readNativeLatest(dir, "macos", 61_000, read);
    expect(read).toHaveBeenCalledTimes(3);
  });
});
