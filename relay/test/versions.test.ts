import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { setMinVersionOverride } from "../src/settings.js";
import { audienceOf, compareVersions, isSettableVersion, recordAppVersion } from "../src/versions.js";
import {
  call, connect, db, deviceBody, loginDevice, makeApp, PASSWORD, randomEmail, registerAccount, tempDir, type TestApp, waitFor,
} from "./helpers.js";

function appVersionOf(deviceId: string): string | null | undefined {
  return db().get<{ app_version: string | null }>("SELECT app_version FROM devices WHERE id = ?", deviceId)?.app_version;
}

async function versionBody(app: TestApp): Promise<{ min_agent: string; min_mobile: string }> {
  return (await call(app, "GET", "/v1/version")).json();
}

describe("GET /v1/version with admin overrides", () => {
  it("serves an override of min_agent / min_mobile while it exists and the env value again once it is removed", async () => {
    const app = makeApp();
    expect(await versionBody(app)).toMatchObject({ min_agent: "1.0.0", min_mobile: "1.0.0" });
    setMinVersionOverride(db(), "min_mobile", "1.4.0", Date.now());
    expect(await versionBody(app)).toMatchObject({ min_agent: "1.0.0", min_mobile: "1.4.0" });
    setMinVersionOverride(db(), "min_agent", "2.0.0", Date.now());
    setMinVersionOverride(db(), "min_mobile", "1.5.0", Date.now());
    expect(await versionBody(app)).toMatchObject({ min_agent: "2.0.0", min_mobile: "1.5.0" });
    setMinVersionOverride(db(), "min_agent", null, Date.now());
    setMinVersionOverride(db(), "min_mobile", null, Date.now());
    expect(await versionBody(app)).toMatchObject({ min_agent: "1.0.0", min_mobile: "1.0.0" });
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM app_settings")!.n).toBe(0);
  });

  it("keeps its exact shape (latest_agent stays env only)", async () => {
    setMinVersionOverride(db(), "min_agent", "3.0.0", Date.now());
    const body = await versionBody(makeApp());
    expect(Object.keys(body)).toEqual(["min_agent", "min_mobile", "latest_agent"]);
    expect((body as unknown as { latest_agent: { version: string } }).latest_agent.version).toBe("1.0.0");
  });
});

describe("X-ShellX-Version is recorded on the device", () => {
  it("at register and login, only once the request succeeded", async () => {
    const app = makeApp();
    const email = randomEmail();
    const res = await call(app, "POST", "/v1/auth/register", {
      body: { email, password: PASSWORD, device: deviceBody("agent") }, headers: { "X-ShellX-Version": "1.2.3" },
    });
    const agentId = (await res.json<{ device_id: string }>()).device_id;
    expect(appVersionOf(agentId)).toBe("1.2.3");

    const account = await registerAccount(app);
    expect(appVersionOf(account.agent.deviceId)).toBeNull(); // no header: an older build

    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: account.password, device: deviceBody("agent", { public_key: account.agent.publicKey }) },
      headers: { "X-ShellX-Version": "1.3.0" },
    });
    expect(login.status).toBe(200);
    expect(appVersionOf(account.agent.deviceId)).toBe("1.3.0");

    const wrong = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "wrong password", device: deviceBody("agent", { public_key: account.agent.publicKey }) },
      headers: { "X-ShellX-Version": "9.9.9" },
    });
    expect(wrong.status).toBe(401);
    expect(appVersionOf(account.agent.deviceId)).toBe("1.3.0");
  });

  it("on any authenticated REST call, and ignores a header that is not x.y.z (1-6 digits each)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    await call(app, "GET", "/v1/devices", { token: phone.token, headers: { "X-ShellX-Version": "1.0.2" } });
    expect(appVersionOf(phone.deviceId)).toBe("1.0.2");
    for (const ignored of ["1.0.3+7", "1.0", "1.0.3.4", "v1.0.3", "1234567.0.0", "1.0.3-beta", "", "garbage"]) {
      await call(app, "GET", "/v1/devices", { token: phone.token, headers: { "X-ShellX-Version": ignored } });
      expect(appVersionOf(phone.deviceId), ignored).toBe("1.0.2");
    }
    await call(app, "GET", "/v1/devices", { token: phone.token, headers: { "X-ShellX-Version": "123456.0.10" } });
    expect(appVersionOf(phone.deviceId)).toBe("123456.0.10");
    // Without a valid token nothing is recorded anywhere.
    await call(app, "GET", "/v1/devices", { token: "x".repeat(43), headers: { "X-ShellX-Version": "7.7.7" } });
    expect(db().get("SELECT 1 FROM devices WHERE app_version = '7.7.7'")).toBeUndefined();
  });

  it("on the WebSocket upgrade", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    await connect(app, account.agent.token, { "X-ShellX-Version": "1.1.0" });
    await waitFor(async () => (appVersionOf(account.agent.deviceId) === "1.1.0" ? true : null));
  });

  it("writes only when the version changed, and never fails the request on a database error", () => {
    const user = crypto.randomUUID();
    const device = crypto.randomUUID();
    db().run("INSERT INTO users VALUES (?, ?, 'x', 1, 1)", user, `${user}@example.com`);
    db().run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, 'agent', 'n', 'macos', x'00', 1)", device, user);
    const changes = () => db().get<{ n: number }>("SELECT total_changes() AS n")!.n;
    recordAppVersion(db(), device, "1.0.0");
    const after = changes();
    recordAppVersion(db(), device, "1.0.0");
    expect(changes()).toBe(after);
    recordAppVersion(db(), device, "1.0.1");
    expect(changes()).toBe(after + 1);

    const closed = Db.open(join(tempDir(), "closed.db"));
    closed.close();
    expect(() => recordAppVersion(closed, device, "1.0.2")).not.toThrow();
  });
});

describe("migration 0004_admin", () => {
  it("adds devices.app_version (NULL for existing devices) and the app_settings table", () => {
    const columns = db().all<{ name: string; type: string; notnull: number }>("PRAGMA table_info(devices)");
    expect(columns.at(-1)).toMatchObject({ name: "app_version", type: "TEXT", notnull: 0 });
    const settings = db().all<{ name: string; type: string; notnull: number; pk: number }>("PRAGMA table_info(app_settings)");
    expect(settings.map((c) => [c.name, c.type, c.notnull, c.pk])).toEqual([
      ["key", "TEXT", 0, 1],
      ["value", "TEXT", 1, 0],
      ["updated_at", "INTEGER", 1, 0],
    ]);
  });

  it("applies to a database that already has devices (the VPS before this release), keeping them", () => {
    const dir = join(tempDir(), "migrations-0003");
    mkdirSync(dir);
    for (const name of ["0001_init.sql", "0002_hub_state.sql", "0003_push_tokens.sql"]) copyFileSync(join(MIGRATIONS_DIR, name), join(dir, name));
    const old = Db.open(join(tempDir(), "upgrade.db"));
    try {
      expect(migrate(old, dir)).toHaveLength(3);
      old.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      old.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES ('d1', 'u1', 'agent', 'n', 'macos', x'00', 1)");
      expect(migrate(old)).toEqual(["0004_admin.sql", "0005_relay_v2.sql", "0006_shares.sql", "0007_link_slot.sql"]);
      expect(old.get("SELECT id, app_version FROM devices")).toEqual({ id: "d1", app_version: null });
    } finally {
      old.close();
    }
  });
});

describe("version helpers", () => {
  it("isSettableVersion accepts x.y.z semver only", () => {
    for (const ok of ["0.0.0", "1.2.3", "10.20.30", "9007199254740991.0.0"]) expect(isSettableVersion(ok), ok).toBe(true);
    for (const bad of ["1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.3-rc.1", "1.2.3+5", "a.b.c", " 1.2.3", "9007199254740992.0.0"]) {
      expect(isSettableVersion(bad), bad).toBe(false);
    }
  });

  it("compareVersions compares numerically, not as text", () => {
    expect(compareVersions("1.10.0", "1.9.0")).toBeGreaterThan(0);
    expect(compareVersions("1.0.0", "1.0.1")).toBeLessThan(0);
    expect(compareVersions("2.0.0", "2.0.0")).toBe(0);
  });
});

describe("audienceOf", () => {
  const rows: [string | undefined, string | undefined, string][] = [
    ["flutter-macos", "14.0", "flutter-macos-14"],
    ["flutter-macos", "15.1.2", "flutter-macos-14"],
    ["flutter-macos", "13.6", "legacy"],
    ["flutter-macos", "abc", "legacy"],
    ["flutter-macos", undefined, "legacy"],
    ["flutter-windows", "10.0.22631", "flutter-windows"],
    ["macos", "14.5", "native-macos"],
    ["windows", undefined, "native-windows"],
    [undefined, undefined, "legacy"],
    ["FLUTTER-MACOS", "14.0", "legacy"],
    ["Macos", "14.0", "legacy"],
  ];
  for (const [platform, os, expected] of rows) {
    it(`(${platform}, ${os}) is ${expected}`, () => expect(audienceOf(platform, os)).toBe(expected));
  }
});

describe("legacy audiences keep today's body", () => {
  const TODAY = {
    min_agent: "1.0.0",
    min_mobile: "1.0.0",
    latest_agent: {
      version: "1.0.0",
      mac_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
      win_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
    },
  };
  const MAC_MANIFEST = {
    version: "2.0.0",
    url: "https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg",
    sha256: "b".repeat(64),
    min_os: "14.0",
    published_at_unix: 1790000000,
  };

  function get(app: TestApp, headers: Record<string, string>) {
    return call(app, "GET", "/v1/version", { headers });
  }
  function writeManifest(file: string, body: unknown): void {
    const dir = join(tempDir(), "desktop");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, file), JSON.stringify(body));
  }

  const legacyClients: [string, Record<string, string>][] = [
    ["no headers", {}],
    ["flutter-macos 13.6", { "X-ShellX-Platform": "flutter-macos", "X-ShellX-OS-Version": "13.6" }],
    ["flutter-macos with an unparsable OS", { "X-ShellX-Platform": "flutter-macos", "X-ShellX-OS-Version": "abc" }],
    ["flutter-windows", { "X-ShellX-Platform": "flutter-windows", "X-ShellX-OS-Version": "10.0.22631" }],
  ];
  for (const [name, headers] of legacyClients) {
    it(`${name}: the body is byte-for-byte today's, even with new settings and manifests present`, async () => {
      writeManifest("latest-macos.json", MAC_MANIFEST);
      setMinVersionOverride(db(), "min_agent", "1.0.0", Date.now());
      db().run("INSERT INTO app_settings (key, value, updated_at) VALUES ('min_flutter_macos14', '2.0.0', 0)");
      const app = makeApp();
      const res = await get(app, headers);
      const body = await res.json();
      expect(body).toEqual(TODAY);
      expect(Object.keys(body)).toEqual(["min_agent", "min_mobile", "latest_agent"]);
      expect(Object.keys(body.latest_agent)).toEqual(["version", "mac_url", "win_url"]);
    });
  }

  it("native macos 14.5 gets the 2.0.0 default minimum", async () => {
    const body = await (await get(makeApp(), { "X-ShellX-Platform": "macos", "X-ShellX-OS-Version": "14.5" })).json();
    expect(body).toMatchObject({ min_agent: "2.0.0", min_mobile: "1.0.0" });
    expect(body.latest_agent).toEqual(TODAY.latest_agent);
  });

  it("native windows uses MIN_WINDOWS, the min_windows setting and the windows manifest", async () => {
    writeManifest("latest-windows.json", {
      ...MAC_MANIFEST, url: "https://download.shellx.pro/desktop/2.0.0/ShellX-Setup-2.0.0.exe", min_os: "10.0.17763",
    });
    db().run("INSERT INTO app_settings (key, value, updated_at) VALUES ('min_windows', '2.1.0', 0)");
    const body = await (await get(makeApp(), { "X-ShellX-Platform": "windows" })).json();
    expect(body).toEqual({
      min_agent: "2.1.0",
      min_mobile: "1.0.0",
      latest_agent: { version: "2.0.0", mac_url: TODAY.latest_agent.mac_url, win_url: "https://download.shellx.pro/desktop/2.0.0/ShellX-Setup-2.0.0.exe" },
    });
  });

  it("flutter-macos 15.0 follows min_flutter_macos14 and the macos manifest", async () => {
    writeManifest("latest-macos.json", MAC_MANIFEST);
    db().run("INSERT INTO app_settings (key, value, updated_at) VALUES ('min_flutter_macos14', '2.0.0', 0)");
    const body = await (await get(makeApp(), { "X-ShellX-Platform": "flutter-macos", "X-ShellX-OS-Version": "15.0" })).json();
    expect(body).toMatchObject({
      min_agent: "2.0.0",
      latest_agent: { version: "2.0.0", mac_url: "https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg" },
    });
  });

  it("flutter-macos 15.0 without a manifest keeps the legacy latest_agent and min_agent follows the setting", async () => {
    db().run("INSERT INTO app_settings (key, value, updated_at) VALUES ('min_flutter_macos14', '2.0.0', 0)");
    const body = await (await get(makeApp(), { "X-ShellX-Platform": "flutter-macos", "X-ShellX-OS-Version": "15.0" })).json();
    expect(body).toEqual({ ...TODAY, min_agent: "2.0.0" });
  });

  it("flutter-windows follows min_flutter_windows but keeps the legacy latest_agent", async () => {
    db().run("INSERT INTO app_settings (key, value, updated_at) VALUES ('min_flutter_windows', '1.5.0', 0)");
    const body = await (await get(makeApp(), { "X-ShellX-Platform": "flutter-windows" })).json();
    expect(body).toEqual({ ...TODAY, min_agent: "1.5.0" });
  });
});
