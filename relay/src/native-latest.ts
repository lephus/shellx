import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { logMeta } from "./log.js";
import { isSettableVersion } from "./versions.js";

/** The latest native build of one platform, from `latest-<platform>.json` (K6). */
export interface NativeLatest {
  version: string;
  url: string;
  sha256: string;
  minOs: string;
}

export type NativePlatform = "macos" | "windows";

export const NATIVE_MANIFEST_MAX_BYTES = 4096;
export const NATIVE_MANIFEST_CACHE_MS = 60_000;
const DOWNLOAD_PREFIX = "https://download.shellx.pro/desktop/";

/** Returns the file's text, or null when it does not exist; throws on any other problem. */
export type ManifestReader = (path: string) => string | null;

export const diskManifestReader: ManifestReader = (path) => {
  try {
    if (statSync(path).size > NATIVE_MANIFEST_MAX_BYTES) return "x".repeat(NATIVE_MANIFEST_MAX_BYTES + 1);
    return readFileSync(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
};

const cache = new Map<string, { at: number; value: NativeLatest | null }>();

function parse(text: string): NativeLatest | null {
  if (Buffer.byteLength(text, "utf8") > NATIVE_MANIFEST_MAX_BYTES) return null;
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const { version, url, sha256, min_os: minOs } = raw as Record<string, unknown>;
  if (typeof version !== "string" || !isSettableVersion(version)) return null;
  if (typeof url !== "string" || !url.startsWith(`${DOWNLOAD_PREFIX}${version}/`)) return null;
  if (typeof sha256 !== "string" || !/^[0-9a-fA-F]{64}$/.test(sha256)) return null;
  if (typeof minOs !== "string" || minOs === "" || minOs.length > 32) return null;
  return { version, url, sha256, minOs };
}

/**
 * The native latest manifest of a platform, or null when there is none or it is invalid (logged
 * once per cache period with the platform only). Cached for 60 s per platform and directory.
 */
export function readNativeLatest(
  dir: string,
  platform: NativePlatform,
  now: number,
  read: ManifestReader = diskManifestReader,
): NativeLatest | null {
  const key = `${dir}\0${platform}`;
  const hit = cache.get(key);
  if (hit !== undefined && now - hit.at >= 0 && now - hit.at < NATIVE_MANIFEST_CACHE_MS) return hit.value;
  let value: NativeLatest | null = null;
  try {
    const text = read(join(dir, `latest-${platform}.json`));
    if (text !== null) {
      value = parse(text);
      if (value === null) logMeta("native_latest_invalid", { platform });
    }
  } catch {
    logMeta("native_latest_invalid", { platform });
  }
  cache.set(key, { at: now, value });
  return value;
}
