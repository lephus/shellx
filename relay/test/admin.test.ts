import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { ADMIN_SECURITY_HEADERS, hostName } from "../src/admin/app.js";
import { ADMIN_SESSION_TTL_MS, AdminSessions, MAX_ADMIN_SESSIONS } from "../src/admin/sessions.js";
import type { AppDeps } from "../src/app.js";
import {
  call, type CallOptions, connect, errorCode, hubs, makeApp, registerAccount, TEST_CONFIG, tempDir, type TestApp,
  type TestResponse, upgradeStatus,
} from "./helpers.js";

const PASSWORD = "dev-only-admin-password-0123";
const ADMIN_HOST = "admin.shellx.pro";

/** A stand-in for relay/admin/ (the real UI files are not part of these tests). */
function uiFixture(): string {
  const dir = join(tempDir(), "admin-ui");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "index.html"), "<!doctype html><title>fixture</title>");
  writeFileSync(join(dir, "admin.css"), "body { color: black; }");
  writeFileSync(join(dir, "admin.js"), "console.log('fixture');");
  return dir;
}

function adminApp(password: string | null = PASSWORD, deps: Partial<AppDeps> = {}): TestApp {
  return makeApp({ config: { ...TEST_CONFIG, adminPassword: password }, adminStaticDir: uiFixture(), ...deps });
}

/** A request to the admin host, with the session cookie when given. */
function admin(app: TestApp, method: string, path: string, options: CallOptions & { cookie?: string } = {}): Promise<TestResponse> {
  const { cookie, ...rest } = options;
  return call(app, method, path, { ...rest, headers: { Host: ADMIN_HOST, ...(cookie ? { Cookie: cookie } : {}), ...rest.headers } });
}

/** Signs in and returns the `shellx_admin=<id>` pair to send back as Cookie. */
async function signIn(app: TestApp, ip?: string): Promise<string> {
  const res = await admin(app, "POST", "/api/login", { body: { password: PASSWORD }, ip });
  expect(res.status).toBe(204);
  return res.headers.get("set-cookie")!.split(";")[0]!;
}

function expectSecurityHeaders(res: TestResponse): void {
  for (const [name, value] of Object.entries(ADMIN_SECURITY_HEADERS)) expect(res.headers.get(name), name).toBe(value);
}

describe("admin host gate", () => {
  it("serves nothing of the admin app on the relay's host", async () => {
    const app = adminApp();
    for (const host of [undefined, "relay.shellx.pro", "admin.shellx.pro.evil.example", "evil-admin.shellx.pro"]) {
      for (const path of ["/", "/admin.js", "/admin.css", "/api/session", "/api/stats"]) {
        const res = await call(app, "GET", path, { headers: host === undefined ? {} : { Host: host } });
        expect(res.status, `${host} ${path}`).toBe(404);
        expect(await errorCode(res)).toBe("not_found");
        expect(res.headers.get("content-security-policy")).toBeNull();
      }
      const login = await call(app, "POST", "/api/login", { body: { password: PASSWORD }, headers: host === undefined ? {} : { Host: host } });
      expect(login.status).toBe(404);
      expect(login.headers.get("set-cookie")).toBeNull();
    }
  });

  it("serves none of the relay's routes on the admin host (404 from the admin app, WebSocket upgrade included)", async () => {
    const app = adminApp();
    const account = await registerAccount(app);
    for (const [method, path] of [["GET", "/v1/version"], ["GET", "/v1/devices"], ["POST", "/v1/auth/login"], ["GET", "/v1/ws"]] as const) {
      const res = await admin(app, method, path, { token: account.agent.token });
      expect(res.status, path).toBe(404);
      expect(await errorCode(res)).toBe("not_found");
      expectSecurityHeaders(res);
    }
    expect(await upgradeStatus(app, account.agent.token, { Host: ADMIN_HOST })).toBe(404);
    // ...while the relay host still answers normally
    expect((await call(app, "GET", "/v1/version")).status).toBe(200);
    expect(await upgradeStatus(app, account.agent.token)).toBe(101);
  });

  it("matches the Host name without port, case or a trailing dot", async () => {
    const app = adminApp();
    for (const host of ["ADMIN.shellx.pro", "admin.shellx.pro:8443", "admin.shellx.pro."]) {
      const res = await call(app, "GET", "/api/session", { headers: { Host: host } });
      expect(res.status, host).toBe(200);
    }
    expect(hostName(undefined)).toBe("");
    expect(hostName("[::1]:8080")).toBe("[::1]");
    expect(hostName("Admin.Localhost:8787")).toBe("admin.localhost");
  });

  it("uses ADMIN_HOST when it is set to another name", async () => {
    const app = makeApp({ config: { ...TEST_CONFIG, adminHost: "admin.localhost", adminPassword: PASSWORD }, adminStaticDir: uiFixture() });
    expect((await call(app, "GET", "/api/session", { headers: { Host: "admin.localhost:8787" } })).status).toBe(200);
    expect((await call(app, "GET", "/api/session", { headers: { Host: ADMIN_HOST } })).status).toBe(404);
  });
});

describe("admin disabled", () => {
  for (const [name, password] of [["without ADMIN_PASSWORD", null], ["with a password under 16 characters", "fifteen-chars!!"]] as const) {
    it(`${name}: /api/session says so and every other API call answers 503 admin_disabled`, async () => {
      const app = adminApp(password);
      const session = await admin(app, "GET", "/api/session");
      expect(session.status).toBe(200);
      expect(await session.json()).toEqual({ enabled: false, signed_in: false });
      const calls = [
        ["POST", "/api/login", { password: password ?? "" }],
        ["POST", "/api/logout", {}],
        ["GET", "/api/stats", undefined],
        ["GET", "/api/settings", undefined],
        ["PUT", "/api/settings", { min_agent: "9.9.9" }],
      ] as const;
      for (const [method, path, body] of calls) {
        const res = await admin(app, method, path, { body });
        expect(res.status, path).toBe(503);
        expect(await errorCode(res)).toBe("admin_disabled");
        expectSecurityHeaders(res);
      }
      // The UI itself still loads (it shows that admin is off).
      expect((await admin(app, "GET", "/")).status).toBe(200);
    });
  }

  it("is enabled with exactly 16 characters", async () => {
    const app = adminApp("sixteen-chars!!!");
    expect(await (await admin(app, "GET", "/api/session")).json()).toEqual({ enabled: true, signed_in: false });
  });
});

describe("admin sign-in", () => {
  it("a wrong password is 401 invalid_credentials with no cookie; the right one sets the session cookie", async () => {
    const app = adminApp();
    for (const body of [{ password: "wrong-password-0123456789" }, { password: 42 }, {}]) {
      const res = await admin(app, "POST", "/api/login", { body });
      expect(res.status).toBe(401);
      expect(await errorCode(res)).toBe("invalid_credentials");
      expect(res.headers.get("set-cookie")).toBeNull();
    }
    const res = await admin(app, "POST", "/api/login", { body: { password: PASSWORD } });
    expect(res.status).toBe(204);
    const cookie = res.headers.get("set-cookie")!;
    expect(cookie).toMatch(/^shellx_admin=[A-Za-z0-9_-]{43}; /);
    for (const attribute of ["Max-Age=43200", "Path=/", "HttpOnly", "Secure", "SameSite=Strict"]) {
      expect(cookie.split("; ")).toContain(attribute);
    }
    expectSecurityHeaders(res);
  });

  it("a malformed body is 400 invalid_body, an oversized one 413 payload_too_large", async () => {
    const app = adminApp();
    for (const body of ["{not json", "[]", "\"text\""]) {
      const res = await admin(app, "POST", "/api/login", { body });
      expect(res.status).toBe(400);
      expect(await errorCode(res)).toBe("invalid_body");
    }
    const huge = await admin(app, "POST", "/api/login", { body: { password: "x".repeat(20 * 1024) } });
    expect(huge.status).toBe(413);
    expect(await errorCode(huge)).toBe("payload_too_large");
    expectSecurityHeaders(huge);
  });

  it("the session cookie opens stats and settings; without it (or with a forged one) they are 401", async () => {
    const app = adminApp();
    const cookie = await signIn(app);
    expect(await (await admin(app, "GET", "/api/session", { cookie })).json()).toEqual({ enabled: true, signed_in: true });
    expect((await admin(app, "GET", "/api/stats", { cookie })).status).toBe(200);
    expect((await admin(app, "GET", "/api/settings", { cookie })).status).toBe(200);
    for (const other of [undefined, `shellx_admin=${"A".repeat(43)}`, "shellx_admin=short", "other=1"]) {
      for (const path of ["/api/stats", "/api/settings"]) {
        const res = await admin(app, "GET", path, { cookie: other });
        expect(res.status).toBe(401);
        expect(await errorCode(res)).toBe("unauthorized");
      }
      expect(await (await admin(app, "GET", "/api/session", { cookie: other })).json()).toEqual({ enabled: true, signed_in: false });
    }
    // A session of one relay process means nothing to another (sessions are in memory).
    expect((await admin(adminApp(), "GET", "/api/stats", { cookie })).status).toBe(401);
  });

  it("logout ends the session and clears the cookie, and is fine when not signed in", async () => {
    const app = adminApp();
    const cookie = await signIn(app);
    const res = await admin(app, "POST", "/api/logout", { cookie, body: {} });
    expect(res.status).toBe(204);
    expect(res.headers.get("set-cookie")).toMatch(/^shellx_admin=; Max-Age=0; /);
    expect((await admin(app, "GET", "/api/stats", { cookie })).status).toBe(401);
    expect((await admin(app, "POST", "/api/logout", { body: {} })).status).toBe(204);
  });

  it("a session expires 12 hours after sign-in", async () => {
    let clock = Date.now();
    const app = adminApp(PASSWORD, { now: () => clock });
    const cookie = await signIn(app);
    clock += ADMIN_SESSION_TTL_MS - 1;
    expect((await admin(app, "GET", "/api/stats", { cookie })).status).toBe(200);
    clock += 1;
    expect((await admin(app, "GET", "/api/stats", { cookie })).status).toBe(401);
    expect(await (await admin(app, "GET", "/api/session", { cookie })).json()).toEqual({ enabled: true, signed_in: false });
  });

  it("5 failed attempts from one IP within 15 minutes lock that IP out, even with the right password; successes do not count", async () => {
    let clock = Date.now();
    const app = adminApp(PASSWORD, { now: () => clock });
    for (let i = 0; i < 6; i++) await signIn(app, "198.51.100.9"); // successes never lock anyone out
    for (let i = 0; i < 5; i++) {
      expect((await admin(app, "POST", "/api/login", { body: { password: "nope" }, ip: "198.51.100.1" })).status).toBe(401);
    }
    const locked = await admin(app, "POST", "/api/login", { body: { password: PASSWORD }, ip: "198.51.100.1" });
    expect(locked.status).toBe(429);
    expect(await errorCode(locked)).toBe("rate_limited");
    expect(locked.headers.get("set-cookie")).toBeNull();
    await signIn(app, "198.51.100.2"); // another address is not affected
    clock += 15 * 60 * 1000;
    await signIn(app, "198.51.100.1");
  });

  it("parallel wrong guesses cannot get past the limit", async () => {
    const app = adminApp();
    const results = await Promise.all(
      Array.from({ length: 12 }, () => admin(app, "POST", "/api/login", { body: { password: "guess" }, ip: "198.51.100.3" })),
    );
    expect(results.filter((res) => res.status === 401)).toHaveLength(5);
    expect(results.filter((res) => res.status === 429)).toHaveLength(7);
  });
});

describe("AdminSessions", () => {
  it("keeps at most MAX_ADMIN_SESSIONS, ending the oldest first, and stores only digests", () => {
    const sessions = new AdminSessions(() => 0);
    const ids = Array.from({ length: MAX_ADMIN_SESSIONS + 1 }, () => sessions.create());
    expect(sessions.size).toBe(MAX_ADMIN_SESSIONS);
    expect(sessions.isValid(ids[0])).toBe(false);
    expect(ids.slice(1).every((id) => sessions.isValid(id))).toBe(true);
    expect(JSON.stringify([...(sessions as unknown as { sessions: Map<string, number> }).sessions.keys()])).not.toContain(ids[1]);
  });

  it("drops expired sessions when a new one starts", () => {
    let clock = 0;
    const sessions = new AdminSessions(() => clock);
    sessions.create();
    sessions.create();
    clock = ADMIN_SESSION_TTL_MS;
    sessions.create();
    expect(sessions.size).toBe(1);
  });
});

describe("admin mutating calls need JSON and, when sent, the admin Origin", () => {
  it("refuses another Content-Type or a missing one with 403 forbidden", async () => {
    const app = adminApp();
    const cookie = await signIn(app);
    for (const type of ["text/plain", "application/x-www-form-urlencoded", "multipart/form-data; boundary=x", "application/jsonx"]) {
      for (const [method, path, body] of [
        ["POST", "/api/login", { password: PASSWORD }],
        ["POST", "/api/logout", {}],
        ["PUT", "/api/settings", { min_agent: "2.0.0" }],
      ] as const) {
        const res = await admin(app, method, path, { cookie, body, headers: { "Content-Type": type } });
        expect(res.status, `${type} ${path}`).toBe(403);
        expect(await errorCode(res)).toBe("forbidden");
      }
    }
    expect((await admin(app, "POST", "/api/logout", { cookie })).status).toBe(403); // no body, no Content-Type
    // Still signed in, and nothing changed.
    expect(await (await admin(app, "GET", "/api/settings", { cookie })).json()).toMatchObject({ min_agent: { overridden: false } });
    const charset = await admin(app, "POST", "/api/login", {
      body: { password: PASSWORD }, headers: { "Content-Type": "Application/JSON; charset=utf-8" },
    });
    expect(charset.status).toBe(204);
  });

  it("refuses a foreign Origin with 403, and accepts the admin origin (https, or http with a port for dev) or none", async () => {
    const app = adminApp();
    for (const origin of ["https://evil.example", "null", "https://relay.shellx.pro", "https://admin.shellx.pro:443", "http://admin.shellx.pro:x",
      "https://admin.shellx.pro.evil.example", "http://admin.shellx.pro:8787/"]) {
      const res = await admin(app, "POST", "/api/login", { body: { password: PASSWORD }, headers: { Origin: origin } });
      expect(res.status, origin).toBe(403);
      expect(await errorCode(res)).toBe("forbidden");
    }
    for (const origin of ["https://admin.shellx.pro", "http://admin.shellx.pro", "http://admin.shellx.pro:8787"]) {
      const res = await admin(app, "POST", "/api/login", { body: { password: PASSWORD }, headers: { Origin: origin } });
      expect(res.status, origin).toBe(204);
    }
  });
});

describe("admin settings", () => {
  const envSettings = {
    min_agent: { value: "1.0.0", env: "1.0.0", overridden: false },
    min_mobile: { value: "1.0.0", env: "1.0.0", overridden: false },
    latest_agent: { version: TEST_CONFIG.latestAgentVersion, mac_url: TEST_CONFIG.macUrl, win_url: TEST_CONFIG.winUrl },
  };

  it("GET shows env values; PUT overrides what /v1/version serves on the relay host; null goes back to env", async () => {
    const app = adminApp();
    const cookie = await signIn(app);
    expect(await (await admin(app, "GET", "/api/settings", { cookie })).json()).toEqual(envSettings);

    const put = await admin(app, "PUT", "/api/settings", { cookie, body: { min_mobile: "1.2.0" } });
    expect(put.status).toBe(200);
    const overridden = { ...envSettings, min_mobile: { value: "1.2.0", env: "1.0.0", overridden: true } };
    expect(await put.json()).toEqual(overridden);
    expect(await (await admin(app, "GET", "/api/settings", { cookie })).json()).toEqual(overridden);
    expect(await (await call(app, "GET", "/v1/version")).json()).toMatchObject({ min_agent: "1.0.0", min_mobile: "1.2.0" });

    const both = await admin(app, "PUT", "/api/settings", { cookie, body: { min_agent: "2.0.0", min_mobile: null } });
    expect(await both.json()).toEqual({ ...envSettings, min_agent: { value: "2.0.0", env: "1.0.0", overridden: true } });
    expect(await (await call(app, "GET", "/v1/version")).json()).toMatchObject({ min_agent: "2.0.0", min_mobile: "1.0.0" });

    expect(await (await admin(app, "PUT", "/api/settings", { cookie, body: {} })).json()).toMatchObject({ min_agent: { value: "2.0.0" } });
    await admin(app, "PUT", "/api/settings", { cookie, body: { min_agent: null } });
    expect(await (await call(app, "GET", "/v1/version")).json()).toMatchObject({ min_agent: "1.0.0", min_mobile: "1.0.0" });
  });

  it("refuses anything but x.y.z semver (400 invalid_version) or a malformed body (400 invalid_body), changing nothing", async () => {
    const app = adminApp();
    const cookie = await signIn(app);
    for (const version of ["1.2", "1.2.3.4", "01.2.3", "1.2.3-beta", "1.2.3+4", " 1.2.3", "v1.2.3", "", "99999999999999999.0.0"]) {
      const res = await admin(app, "PUT", "/api/settings", { cookie, body: { min_agent: "3.0.0", min_mobile: version } });
      expect(res.status, version).toBe(400);
      expect(await errorCode(res)).toBe("invalid_version");
    }
    for (const body of [{ min_agent: 2 }, { min_agent: ["2.0.0"] }, { latest_agent: "2.0.0" }, { min_agent: "3.0.0", extra: null }, [], "{bad"]) {
      const res = await admin(app, "PUT", "/api/settings", { cookie, body });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(await errorCode(res)).toBe("invalid_body");
    }
    expect(await (await admin(app, "GET", "/api/settings", { cookie })).json()).toEqual(envSettings);
  });

  it("needs a session", async () => {
    const app = adminApp();
    const res = await admin(app, "PUT", "/api/settings", { body: { min_agent: "2.0.0" } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
    expect(await (await call(app, "GET", "/v1/version")).json()).toMatchObject({ min_agent: "1.0.0" });
  });
});

describe("admin stats endpoint", () => {
  it("counts a live WebSocket as online and its user as active, with the version the app reported", async () => {
    const app = adminApp();
    const account = await registerAccount(app);
    await call(app, "GET", "/v1/devices", { token: account.agent.token, headers: { "X-ShellX-Version": "1.2.3" } });
    await connect(app, account.agent.token);
    await hubs().forUser(account.agent.userId).idle(); // the socket has joined its hub
    const cookie = await signIn(app);
    const res = await admin(app, "GET", "/api/stats", { cookie });
    expect(res.status).toBe(200);
    const stats = await res.json();
    expect(stats.devices.agent).toEqual({ total: 1, online: 1, by_platform: { macos: 1, windows: 0 } });
    expect(stats.devices.mobile).toEqual({ total: 0, online: 0, by_platform: { ios: 0, android: 0 } });
    expect(stats.versions).toEqual({ agent: [{ version: "1.2.3", count: 1 }], mobile: [], desktop: [] });
    expect(stats.users).toMatchObject({ total: 1, new_24h: 1, active_7d: 1, active_30d: 1 });
    expect(stats.signups_by_day).toHaveLength(30);
    expectSecurityHeaders(res);
  });
});

describe("admin static files", () => {
  it("serves the three UI files with their content types and the security headers", async () => {
    const app = adminApp();
    for (const [path, type, body] of [
      ["/", "text/html; charset=utf-8", "<!doctype html><title>fixture</title>"],
      ["/admin.css", "text/css; charset=utf-8", "body { color: black; }"],
      ["/admin.js", "text/javascript; charset=utf-8", "console.log('fixture');"],
    ] as const) {
      const res = await admin(app, "GET", path);
      expect(res.status, path).toBe(200);
      expect(res.headers.get("content-type")).toBe(type);
      expect(await res.text()).toBe(body);
      expectSecurityHeaders(res);
    }
  });

  it("anything else is 404 (with the security headers), including other files of the folder and traversal attempts", async () => {
    const app = adminApp();
    writeFileSync(join(tempDir(), "admin-ui", "secret.txt"), "not served");
    for (const path of ["/index.html", "/secret.txt", "/favicon.ico", "/admin.js/", "/..%2fpackage.json", "/%2e%2e/package.json", "/api", "/api/nope"]) {
      const res = await admin(app, "GET", path);
      expect(res.status, path).toBe(404);
      expectSecurityHeaders(res);
    }
  });

  it("a missing UI file is a 404, not an error", async () => {
    const app = makeApp({ config: { ...TEST_CONFIG, adminPassword: PASSWORD }, adminStaticDir: join(tempDir(), "nowhere") });
    const res = await admin(app, "GET", "/admin.js");
    expect(res.status).toBe(404);
    expect(await errorCode(res)).toBe("not_found");
  });
});
