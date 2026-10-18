import type { Db } from "./db/db.js";
import { errorKind, logMeta } from "./log.js";

/** Request header in which the apps send their own `x.y.z` (shellx_core `clientVersionHeader`). */
export const CLIENT_VERSION_HEADER = "X-ShellX-Version";

/** Request headers of GET /v1/version that tell the relay which app asks (K6). */
export const PLATFORM_HEADER = "X-ShellX-Platform";
export const OS_VERSION_HEADER = "X-ShellX-OS-Version";

export type Audience = "native-macos" | "native-windows" | "flutter-macos-14" | "flutter-windows" | "legacy";

/** Which answer a client gets: exact, case-sensitive platform match; anything unknown is `legacy`. */
export function audienceOf(platform: string | undefined, osVersion: string | undefined): Audience {
  switch (platform) {
    case "macos":
      return "native-macos";
    case "windows":
      return "native-windows";
    case "flutter-windows":
      return "flutter-windows";
    case "flutter-macos": {
      const major = osVersion === undefined ? null : /^(\d{1,6})(\.|$)/.exec(osVersion)?.[1];
      return major !== undefined && major !== null && Number(major) >= 14 ? "flutter-macos-14" : "legacy";
    }
    default:
      return "legacy";
  }
}

/** What a reported version must look like to be stored; anything else in the header is ignored. */
const REPORTED_VERSION_RE = /^\d{1,6}\.\d{1,6}\.\d{1,6}$/;

/**
 * A version the admin may set as `min_agent` / `min_mobile`: `x.y.z` that is also valid semver (no
 * leading zeros) with parts that are safe integers. The apps compare with a strict semver parser
 * and treat anything it rejects as "nothing to compare against", which would silently switch the
 * force update off.
 */
export function isSettableVersion(value: string): boolean {
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.exec(value);
  return match !== null && match.slice(1).every((part) => Number.isSafeInteger(Number(part)));
}

/** Compares two `x.y.z` strings by their numeric parts (negative, zero or positive). */
export function compareVersions(a: string, b: string): number {
  const left = a.split(".").map(Number);
  const right = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    const diff = (left[i] ?? 0) - (right[i] ?? 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

/**
 * Stores the version a known device reported in X-ShellX-Version (called by requireAuth, the
 * WebSocket auth and register/login once the device row exists). Writes only when it changed, so an
 * ordinary request costs one indexed no-op UPDATE. Best-effort: this is statistics for the admin
 * dashboard, so a database error is logged by kind and never fails the request it rode on.
 */
export function recordAppVersion(db: Db, deviceId: string, header: string | undefined): void {
  if (header === undefined || !REPORTED_VERSION_RE.test(header)) return;
  try {
    db.run("UPDATE devices SET app_version = ? WHERE id = ? AND app_version IS NOT ?", header, deviceId, header);
  } catch (err) {
    logMeta("app_version_write_failed", { device_id: deviceId, error: errorKind(err) });
  }
}
