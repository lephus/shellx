import { describe, expect, it } from "vitest";
import { adminStats } from "../src/admin/stats.js";
import { db } from "./helpers.js";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
/** 2026-10-15 12:00 UTC */
const NOW = Date.UTC(2026, 9, 15, 12);

function user(id: string, createdAt: number): void {
  db().run("INSERT INTO users VALUES (?, ?, 'x', 0, ?)", id, `${id}@example.com`, createdAt);
}

interface DeviceSeed {
  kind: "agent" | "mobile";
  platform: string;
  version?: string;
  lastSeen?: number;
  tokenUsed?: number;
}

function device(userId: string, id: string, seed: DeviceSeed): void {
  db().run(
    "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at, last_seen_at, app_version) VALUES (?, ?, ?, 'n', ?, ?, 0, ?, ?)",
    id, userId, seed.kind, seed.platform, new TextEncoder().encode(id), seed.lastSeen ?? null, seed.version ?? null,
  );
  if (seed.tokenUsed !== undefined) {
    db().run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at) VALUES (?, ?, 0, ?)", new TextEncoder().encode(`t-${id}`), id, seed.tokenUsed);
  }
}

describe("adminStats", () => {
  it("counts users, activity, devices, versions and daily signups", () => {
    user("u1", NOW - HOUR); //                       today
    user("u2", NOW - 3 * DAY); //                    2026-10-12
    user("u3", NOW - 20 * DAY); //                   2026-09-25
    user("u4", NOW - 40 * DAY); //                   outside every window
    user("u5", NOW - 29 * DAY - 11 * HOUR); //       2026-09-16 01:00, the first day listed
    user("u6", NOW - 29 * DAY - 13 * HOUR); //       2026-09-15 23:00: within 30 days, before the first day listed
    device("u1", "a1", { kind: "agent", platform: "macos", version: "1.1.0", lastSeen: NOW - DAY });
    device("u1", "m1", { kind: "mobile", platform: "ios", version: "1.0.2" });
    device("u2", "a2", { kind: "agent", platform: "windows", version: "1.0.0", tokenUsed: NOW - 10 * DAY });
    device("u3", "m3", { kind: "mobile", platform: "android", tokenUsed: NOW - 2 * DAY });
    device("u4", "a4", { kind: "agent", platform: "macos", version: "1.10.0", lastSeen: NOW - 60 * DAY, tokenUsed: NOW - 60 * DAY });
    device("u5", "a5", { kind: "agent", platform: "macos", version: "1.9.0" });

    const stats = adminStats(db(), NOW, [{ userId: "u4", deviceId: "a4", kind: "agent" }]);

    expect(stats.generated_at).toBe(NOW);
    // active: u1 (seen 1 day ago), u3 (token 2 days ago), u4 (online now); u2's token is 10 days old.
    expect(stats.users).toEqual({ total: 6, new_24h: 1, new_7d: 2, new_30d: 5, active_7d: 3, active_30d: 4 });
    expect(stats.devices).toEqual({
      agent: { total: 4, online: 1, by_platform: { macos: 3, windows: 1 } },
      mobile: { total: 2, online: 0, by_platform: { ios: 1, android: 1 } },
      desktop: { total: 0, online: 0, by_platform: { macos: 0, windows: 0 } },
    });
    expect(stats.versions).toEqual({
      agent: [
        { version: "1.10.0", count: 1 },
        { version: "1.9.0", count: 1 },
        { version: "1.1.0", count: 1 },
        { version: "1.0.0", count: 1 },
      ],
      mobile: [
        { version: "1.0.2", count: 1 },
        { version: null, count: 1 },
      ],
      desktop: [],
    });
    expect(stats.signups_by_day).toHaveLength(30);
    expect(stats.signups_by_day[0]).toEqual({ day: "2026-09-16", count: 1 });
    expect(stats.signups_by_day[29]).toEqual({ day: "2026-10-15", count: 1 });
    expect(stats.signups_by_day.filter((d) => d.count > 0)).toEqual([
      { day: "2026-09-16", count: 1 },
      { day: "2026-09-25", count: 1 },
      { day: "2026-10-12", count: 1 },
      { day: "2026-10-15", count: 1 },
    ]);
    const days = stats.signups_by_day.map((d) => d.day);
    expect([...days].sort()).toEqual(days); // oldest first, one entry per day
    expect(new Set(days).size).toBe(30);
  });

  it("an empty database gives zeros everywhere and 30 zero days; unknown online counts are null", () => {
    const stats = adminStats(db(), NOW, null);
    expect(stats.users).toEqual({ total: 0, new_24h: 0, new_7d: 0, new_30d: 0, active_7d: 0, active_30d: 0 });
    expect(stats.devices).toEqual({
      agent: { total: 0, online: null, by_platform: { macos: 0, windows: 0 } },
      mobile: { total: 0, online: null, by_platform: { ios: 0, android: 0 } },
      desktop: { total: 0, online: null, by_platform: { macos: 0, windows: 0 } },
    });
    expect(stats.versions).toEqual({ agent: [], mobile: [], desktop: [] });
    expect(stats.signups_by_day.every((d) => d.count === 0)).toBe(true);
    expect(stats.signups_by_day).toHaveLength(30);
  });

  it("counts a user once however many devices are active, and sorts equal-count versions newest first", () => {
    user("u1", NOW);
    device("u1", "a1", { kind: "agent", platform: "macos", version: "2.0.0", lastSeen: NOW });
    device("u1", "m1", { kind: "mobile", platform: "ios", version: "2.0.0", tokenUsed: NOW });
    device("u1", "m2", { kind: "mobile", platform: "ios", version: "10.0.0", tokenUsed: NOW });
    device("u1", "m3", { kind: "mobile", platform: "ios", version: "2.0.0" });
    const stats = adminStats(db(), NOW, [{ userId: "u1", deviceId: "a1", kind: "agent" }]);
    expect(stats.users.active_7d).toBe(1);
    expect(stats.versions.mobile).toEqual([{ version: "10.0.0", count: 1 }, { version: "2.0.0", count: 2 }]);
  });
});
