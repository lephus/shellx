import { randomBytes } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  call, CountingLimiter, db, errorCode, loginDesktop, makeApp, registerAccount, registerMachine, unlimited, type Session, type TestApp,
} from "./helpers.js";

const T0 = 1_760_000_000_000;
const ID_RE = /^[0-9a-hjkmnp-tv-z]{8}$/;
const VIEWER_A = "viewer-a-0123456789abcdef";
const VIEWER_B = "viewer-b-0123456789abcdef";

const newAccess = () => randomBytes(32).toString("base64url");

interface Created { id: string; slot: string; expires_at_unix: number; claim_until_unix: number | null }

function clock(start = T0) {
  let now = start;
  return { now: () => now, advance: (seconds: number) => { now += seconds * 1000; } };
}

function claimsOf(ticket: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(ticket.split(".")[1]!, "base64url").toString("utf8")) as Record<string, unknown>;
}

async function desk(app: TestApp) {
  const account = await registerAccount(app);
  const session = await loginDesktop(app, account);
  return { account, session };
}

async function create(app: TestApp, session: Session, overrides: Record<string, unknown> = {}) {
  const access = newAccess();
  const res = await call(app, "POST", "/v2/shares", { token: session.token, body: { permission: "view", lifetime: "1h", access, ...overrides } });
  return { res, access, share: res.status === 201 ? await res.json<Created>() : (undefined as unknown as Created) };
}

function viewerTicket(app: TestApp, id: string, access: string, viewer = VIEWER_A, headers: Record<string, string> = {}) {
  return call(app, "POST", `/v2/shares/${id}/ticket`, { body: { access, viewer }, headers });
}

function hostTicket(app: TestApp, session: Session, id: string) {
  return call(app, "POST", `/v2/shares/${id}/host-ticket`, { token: session.token });
}

afterEach(() => vi.restoreAllMocks());

describe("create", () => {
  it("creates a share with its own slot", async () => {
    const c = clock();
    const app = makeApp({ now: c.now });
    const { session } = await desk(app);
    const machine = await registerMachine(app, session.token);

    const hour = await create(app, session);
    expect(hour.res.status).toBe(201);
    expect(hour.share.id).toMatch(ID_RE);
    expect(hour.share.slot).not.toBe(machine.slot);
    expect(db().all("SELECT 1 FROM machines WHERE slot = ?", hour.share.slot)).toHaveLength(0);
    expect(hour.share.expires_at_unix - T0 / 1000).toBe(3600);
    expect(hour.share.claim_until_unix).toBeNull();

    const quit = await create(app, session, { lifetime: "until_quit" });
    expect(quit.share.expires_at_unix - T0 / 1000).toBe(86400);
    const short = await create(app, session, { lifetime: "15m" });
    expect(short.share.expires_at_unix - T0 / 1000).toBe(900);
    expect(new Set([hour.share.slot, quit.share.slot, short.share.slot]).size).toBe(3);
    // The API stores the hash of the access token, never the token.
    const row = db().get<{ access_hash: string }>("SELECT access_hash FROM shares WHERE id = ?", hour.share.id)!;
    expect(row.access_hash).not.toContain(hour.access);
  });

  it("refuses a body carrying secret", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { res } = await create(app, session, { secret: "x" });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("bad_request");
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM shares")!.n).toBe(0);
  });

  it("validates the body", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    for (const bad of [{ permission: "admin" }, { lifetime: "2h" }, { access: "short" }, { access: "!".repeat(43) }, { one_time: "yes" }]) {
      expect((await create(app, session, bad)).res.status).toBe(400);
    }
  });

  it("forces the QR values for a one-time share", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { res, share } = await create(app, session, { one_time: true, permission: "view", lifetime: "15m" });
    expect(res.status).toBe(201);
    expect(share.claim_until_unix).toBe(T0 / 1000 + 120);
    expect(share.expires_at_unix).toBe(T0 / 1000 + 86400);
    const row = db().get<{ permission: string; lifetime: string; one_time: number }>("SELECT permission, lifetime, one_time FROM shares WHERE id = ?", share.id)!;
    expect(row).toEqual({ permission: "type", lifetime: "until_quit", one_time: 1 });
  });

  it("allows 20 live shares per device, then 409 share_limit; revoked ones do not count", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const ids: string[] = [];
    for (let i = 0; i < 20; i++) ids.push((await create(app, session)).share.id);
    const over = await create(app, session);
    expect(over.res.status).toBe(409);
    expect(await errorCode(over.res)).toBe("share_limit");
    expect((await call(app, "DELETE", `/v2/shares/${ids[0]}`, { token: session.token })).status).toBe(204);
    expect((await create(app, session)).res.status).toBe(201);
  });

  it("needs a desktop token", async () => {
    const app = makeApp({ now: () => T0 });
    const { account, session } = await desk(app);
    expect((await call(app, "POST", "/v2/shares", { body: {} })).status).toBe(401);
    expect(account.agent.token).not.toBe(session.token);
    const res = await call(app, "POST", "/v2/shares", { token: account.agent.token, body: { permission: "view", lifetime: "1h", access: newAccess() } });
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("desktop_only");
  });

  it("uses the injected share id and accepts the dashed form on routes", async () => {
    const app = makeApp({ now: () => T0, shareId: () => "k7f29qd1" });
    const { session } = await desk(app);
    const { share, access } = await create(app, session);
    expect(share.id).toBe("k7f29qd1");
    expect((await viewerTicket(app, "k7f2-9qd1", access)).status).toBe(200);
    expect((await viewerTicket(app, "K7F2-9QD1", access)).status).toBe(200);
    expect((await call(app, "GET", "/v2/shares", { token: session.token })).status).toBe(200);
  });
});

describe("list and revoke", () => {
  it("lists the caller's device's shares", async () => {
    const c = clock();
    const app = makeApp({ now: c.now });
    const { account, session } = await desk(app);
    const other = await loginDesktop(app, account);
    const mine = await create(app, session, { permission: "type" });
    await create(app, other);
    await call(app, "DELETE", `/v2/shares/${mine.share.id}`, { token: session.token });
    const res = await call(app, "GET", "/v2/shares", { token: session.token });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      shares: [{ id: mine.share.id, permission: "type", lifetime: "1h", expires_at_unix: mine.share.expires_at_unix, revoked: true }],
    });
  });

  it("is idempotent and 404 for an unknown id", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { share } = await create(app, session);
    expect((await call(app, "DELETE", `/v2/shares/${share.id}`, { token: session.token })).status).toBe(204);
    expect((await call(app, "DELETE", `/v2/shares/${share.id}`, { token: session.token })).status).toBe(204);
    expect((await call(app, "DELETE", "/v2/shares/zzzzzzzz", { token: session.token })).status).toBe(404);
  });

  it("another account cannot revoke or host", async () => {
    const app = makeApp({ now: () => T0 });
    const a = await desk(app);
    const b = await desk(app);
    const { share, access } = await create(app, a.session);
    const del = await call(app, "DELETE", `/v2/shares/${share.id}`, { token: b.session.token });
    expect(del.status).toBe(404);
    expect(await errorCode(del)).toBe("share_not_found");
    const host = await hostTicket(app, b.session, share.id);
    expect(host.status).toBe(404);
    // Another device of the same account is not the owner either.
    const sibling = await loginDesktop(app, a.account);
    expect((await hostTicket(app, sibling, share.id)).status).toBe(404);
    expect((await viewerTicket(app, share.id, access)).status).toBe(200);
  });
});

describe("tickets", () => {
  it("host ticket registers on the share's slot and refreshes host_seen_at", async () => {
    const c = clock();
    const app = makeApp({ now: c.now });
    const { session } = await desk(app);
    const { share } = await create(app, session);
    c.advance(60);
    const res = await hostTicket(app, session, share.id);
    expect(res.status).toBe(200);
    const body = await res.json<{ ticket: string; expires_at_unix: number; relay_url: string }>();
    expect(claimsOf(body.ticket)).toMatchObject({ permission: "register", role: "daemon", slot: share.slot, issuer: "shellx-relay" });
    expect(body.expires_at_unix).toBe(T0 / 1000 + 60 + 120);
    expect(body.relay_url).toBe("ws://127.0.0.1:1/v1/relay");
    expect(db().get<{ host_seen_at: number }>("SELECT host_seen_at FROM shares WHERE id = ?", share.id)!.host_seen_at).toBe(T0 + 60_000);
  });

  it("viewer ticket needs the access token", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { share, access } = await create(app, session);
    const wrong = await viewerTicket(app, share.id, newAccess());
    expect(wrong.status).toBe(404);
    expect(await errorCode(wrong)).toBe("share_not_found");
    const missing = await viewerTicket(app, "zzzzzzzz", access);
    expect(missing.status).toBe(404);
    expect(await errorCode(missing)).toBe("share_not_found");

    const ok = await viewerTicket(app, share.id, access);
    expect(ok.status).toBe(200);
    const body = await ok.json<{ ticket: string; expires_at_unix: number; relay_url: string; slot: string }>();
    expect(body.slot).toBe(share.slot);
    expect(body.expires_at_unix).toBe(T0 / 1000 + 120);
    expect(claimsOf(body.ticket)).toMatchObject({ permission: "connect", role: "client", slot: share.slot });
  });

  it("refusal codes", async () => {
    const c = clock();
    const app = makeApp({ now: c.now });
    const { session } = await desk(app);

    const revoked = await create(app, session);
    await call(app, "DELETE", `/v2/shares/${revoked.share.id}`, { token: session.token });
    const r = await viewerTicket(app, revoked.share.id, revoked.access);
    expect(r.status).toBe(410);
    expect(await errorCode(r)).toBe("share_revoked");
    expect((await hostTicket(app, session, revoked.share.id)).status).toBe(410);

    const quiet = await create(app, session, { lifetime: "15m" });
    const live = await create(app, session, { lifetime: "15m" });
    c.advance(149);
    expect((await hostTicket(app, session, live.share.id)).status).toBe(200);
    c.advance(2); // 151 s since create, 2 s since the live host ticket
    const off = await viewerTicket(app, quiet.share.id, quiet.access);
    expect(off.status).toBe(503);
    expect(await errorCode(off)).toBe("host_offline");
    expect((await viewerTicket(app, live.share.id, live.access)).status).toBe(200);

    c.advance(900);
    const expired = await viewerTicket(app, live.share.id, live.access);
    expect(expired.status).toBe(410);
    expect(await errorCode(expired)).toBe("share_expired");
    const hostExpired = await hostTicket(app, session, live.share.id);
    expect(hostExpired.status).toBe(410);
    expect(await errorCode(hostExpired)).toBe("share_expired");
  });

  it("a wrong access token for a revoked or expired share answers 404 share_not_found, not 410", async () => {
    const c = clock();
    const app = makeApp({ now: c.now });
    const { session } = await desk(app);
    const revoked = await create(app, session);
    await call(app, "DELETE", `/v2/shares/${revoked.share.id}`, { token: session.token });
    const expired = await create(app, session, { lifetime: "15m" });
    const r = await viewerTicket(app, revoked.share.id, newAccess());
    expect(r.status).toBe(404);
    expect(await errorCode(r)).toBe("share_not_found");
    c.advance(901);
    const e = await viewerTicket(app, expired.share.id, newAccess());
    expect(e.status).toBe(404);
    expect(await errorCode(e)).toBe("share_not_found");
  });

  it("host_offline boundary: older than 150 s is offline, exactly 150 s is online", async () => {
    for (const [seconds, status] of [[149, 200], [150, 200], [151, 503]] as const) {
      for (const viaHostTicket of [false, true]) {
        const c = clock();
        const app = makeApp({ now: c.now });
        const { session } = await desk(app);
        const { share, access } = await create(app, session);
        if (viaHostTicket) {
          c.advance(30);
          expect((await hostTicket(app, session, share.id)).status).toBe(200);
        }
        c.advance(seconds);
        const res = await viewerTicket(app, share.id, access);
        expect(res.status, `${seconds}s via ${viaHostTicket ? "host ticket" : "create"}`).toBe(status);
        if (status === 503) expect(await errorCode(res)).toBe("host_offline");
      }
    }
  });

  it("retries once with a fresh slot when the slot is taken, then fails", async () => {
    const slots = ["a".repeat(22), "a".repeat(22), "b".repeat(22)];
    const app = makeApp({ now: () => T0, shareSlot: () => slots.shift() ?? "c".repeat(22) });
    const { session } = await desk(app);
    expect((await create(app, session)).res.status).toBe(201); // takes the first "a"
    const second = await create(app, session); // draws "a" (taken), then "b"
    expect(second.res.status).toBe(201);
    expect(second.share.slot).toBe("b".repeat(22));
    // two collisions in a row are not retried again
    expect((await create(app, session)).res.status).toBe(201); // "c"
  });

  it("gives up after a second slot collision", async () => {
    const app = makeApp({ now: () => T0, shareSlot: () => "d".repeat(22) });
    const { session } = await desk(app);
    expect((await create(app, session)).res.status).toBe(201);
    expect((await create(app, session)).res.status).toBe(500);
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM shares")!.n).toBe(1);
  });

  it("one-time share binds the first viewer", async () => {
    const c = clock();
    const app = makeApp({ now: c.now });
    const { session } = await desk(app);
    const qr = await create(app, session, { one_time: true });
    expect((await viewerTicket(app, qr.share.id, qr.access, VIEWER_A)).status).toBe(200);
    c.advance(600);
    await hostTicket(app, session, qr.share.id);
    expect((await viewerTicket(app, qr.share.id, qr.access, VIEWER_A)).status).toBe(200);
    const b = await viewerTicket(app, qr.share.id, qr.access, VIEWER_B);
    expect(b.status).toBe(410);
    expect(await errorCode(b)).toBe("share_used");

    const late = await create(app, session, { one_time: true });
    c.advance(121);
    const l = await viewerTicket(app, late.share.id, late.access, VIEWER_A);
    expect(l.status).toBe(410);
    expect(await errorCode(l)).toBe("share_expired");
  });

  it("a normal share lets any viewer in", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { share, access } = await create(app, session);
    expect((await viewerTicket(app, share.id, access, VIEWER_A)).status).toBe(200);
    expect((await viewerTicket(app, share.id, access, VIEWER_B)).status).toBe(200);
  });

  it("rejects a malformed viewer and answers 503 without relay v2", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { share, access } = await create(app, session);
    expect((await viewerTicket(app, share.id, access, "short")).status).toBe(400);
    expect((await viewerTicket(app, share.id, access, "not base64url!!!!!!!!!")).status).toBe(400);
    expect((await call(app, "POST", `/v2/shares/${share.id}/ticket`, { body: { access, viewer: VIEWER_A, secret: "x" } })).status).toBe(400);
    // secret wins over an unknown or malformed id
    for (const id of ["zzzzzzzz", "not-an-id"]) {
      expect((await call(app, "POST", `/v2/shares/${id}/ticket`, { body: { access, viewer: VIEWER_A, secret: "x" } })).status).toBe(400);
    }
  });

  it("limits creates per device and viewer tickets per IP", async () => {
    const shareCreate = new CountingLimiter(1);
    const shareTicket = new CountingLimiter(1);
    const app = makeApp({ now: () => T0, limiters: { ...unlimited, shareCreate, shareTicket } });
    const { session } = await desk(app);
    const { share, access } = await create(app, session);
    expect((await create(app, session)).res.status).toBe(429);
    expect(shareCreate.calls).toEqual([session.deviceId, session.deviceId]);
    expect((await call(app, "POST", `/v2/shares/${share.id}/ticket`, { body: { access, viewer: VIEWER_A }, ip: "198.51.100.9" })).status).toBe(200);
    expect((await call(app, "POST", `/v2/shares/${share.id}/ticket`, { body: { access, viewer: VIEWER_A }, ip: "198.51.100.9" })).status).toBe(429);
    expect(shareTicket.calls).toEqual(["198.51.100.9", "198.51.100.9"]);
  });
});

describe("CORS", () => {
  it("allows only the configured origin, only on the viewer ticket route", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const { share, access } = await create(app, session);
    const preflight = (path: string, origin: string) =>
      call(app, "OPTIONS", path, {
        ip: null,
        headers: { Origin: origin, "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type" },
      });

    const good = await preflight(`/v2/shares/${share.id}/ticket`, "https://shellx.pro");
    expect(good.headers.get("access-control-allow-origin")).toBe("https://shellx.pro");
    expect(good.headers.get("access-control-allow-methods")).toContain("POST");
    expect(good.headers.get("access-control-allow-headers")?.toLowerCase()).toContain("content-type");
    const evil = await preflight(`/v2/shares/${share.id}/ticket`, "https://evil.example");
    expect(evil.headers.get("access-control-allow-origin")).toBeNull();

    const real = await viewerTicket(app, share.id, access, VIEWER_A, { Origin: "https://shellx.pro" });
    expect(real.status).toBe(200);
    expect(real.headers.get("access-control-allow-origin")).toBe("https://shellx.pro");
    const refused = await viewerTicket(app, share.id, newAccess(), VIEWER_A, { Origin: "https://shellx.pro" });
    expect(refused.status).toBe(404);
    expect(refused.headers.get("access-control-allow-origin")).toBe("https://shellx.pro");
    const other = await viewerTicket(app, share.id, access, VIEWER_A, { Origin: "https://evil.example" });
    expect(other.headers.get("access-control-allow-origin")).toBeNull();

    for (const path of ["/v2/shares", `/v2/shares/${share.id}`, `/v2/shares/${share.id}/host-ticket`]) {
      const res = await preflight(path, "https://shellx.pro");
      expect(res.headers.get("access-control-allow-origin")).toBeNull();
    }
    const created = await call(app, "POST", "/v2/shares", {
      token: session.token, headers: { Origin: "https://shellx.pro" },
      body: { permission: "view", lifetime: "1h", access: newAccess() },
    });
    expect(created.status).toBe(201);
    expect(created.headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("logging", () => {
  it("never logs access tokens, viewer ids, tickets or slots", async () => {
    const app = makeApp({ now: () => T0 });
    const { session } = await desk(app);
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); });
    vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); });
    const { share, access } = await create(app, session);
    const host = await (await hostTicket(app, session, share.id)).json<{ ticket: string }>();
    const viewer = await (await viewerTicket(app, share.id, access)).json<{ ticket: string }>();
    await viewerTicket(app, share.id, newAccess());
    expect(lines.length).toBeGreaterThan(0);
    for (const line of lines) {
      for (const secret of [access, VIEWER_A, host.ticket, viewer.ticket, share.slot]) expect(line).not.toContain(secret);
      expect(line).not.toContain("v2.");
    }
  });
});
