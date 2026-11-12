// Holds the relay to relay/contract/desktop-api.json: the answers and request rules the desktop apps rely
// on. shellx-core/tests/relay_contract.rs holds the fake relay to the same file. When this test fails, the
// file is wrong: correct the file, never the relay.
//
// Shapes: an object has exactly these keys (a key ending in `?` may be absent); a one-element array is a
// non-empty array whose every element matches; a string is type tokens (`string`, `integer`, `number`,
// `boolean`, `null`) joined by `|`; `null` is an empty body.
import { describe, expect, it } from "vitest";
import contract from "../contract/desktop-api.json" with { type: "json" };
import { FakeEmailGateway } from "./fake-email.js";
import {
  approvePairing, call, emailSession, loginDesktop, makeApp, randomEmail, randomPublicKey, registerAccount, registerMachine,
  requestPairing, signInEmail, type TestApp, type TestResponse,
} from "./helpers.js";

type Shape = string | null | Shape[] | { [key: string]: Shape };
interface ResponseEntry { route: string; case?: string; status?: number; body: Shape }
interface RequestCase { label: string; set: Record<string, unknown>; status: number; error?: string }
interface RequestRoute { route: string; base: Record<string, unknown>; cases: RequestCase[] }
interface Contract { about: string; responses: ResponseEntry[]; requests: RequestRoute[] }

const file = contract as unknown as Contract;

function typeMatches(value: unknown, token: string): boolean {
  switch (token) {
    case "string": return typeof value === "string";
    case "integer": return Number.isInteger(value);
    case "number": return typeof value === "number" && Number.isFinite(value);
    case "boolean": return typeof value === "boolean";
    case "null": return value === null;
    default: throw new Error(`unknown type token ${token}`);
  }
}

/** Every way `value` differs from `shape` (empty when it matches). */
function checkShape(value: unknown, shape: Shape, path: string): string[] {
  if (shape === null) return [`${path}: null is only a whole (empty) body`];
  if (typeof shape === "string") {
    return shape.split("|").some((token) => typeMatches(value, token)) ? [] : [`${path}: ${JSON.stringify(value)} is not ${shape}`];
  }
  if (Array.isArray(shape)) {
    const item = shape[0];
    if (shape.length !== 1 || item === undefined) return [`${path}: an array shape has exactly one element`];
    if (!Array.isArray(value) || value.length === 0) return [`${path}: ${JSON.stringify(value)} is not a non-empty array`];
    return value.flatMap((v, i) => checkShape(v, item, `${path}[${i}]`));
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) return [`${path}: ${JSON.stringify(value)} is not an object`];
  const object = value as Record<string, unknown>;
  const problems: string[] = [];
  const names = new Set<string>();
  for (const [key, sub] of Object.entries(shape)) {
    const optional = key.endsWith("?");
    const name = optional ? key.slice(0, -1) : key;
    names.add(name);
    if (!Object.hasOwn(object, name)) {
      if (!optional) problems.push(`${path}.${name}: missing`);
      continue;
    }
    problems.push(...checkShape(object[name], sub, `${path}.${name}`));
  }
  for (const key of Object.keys(object)) if (!names.has(key)) problems.push(`${path}.${key}: not in the contract`);
  return problems;
}

async function bodyProblems(res: TestResponse, shape: Shape): Promise<string[]> {
  const text = await res.text();
  if (shape === null) return text === "" ? [] : [`body: expected none, got ${text}`];
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return [`body: not JSON: ${text}`];
  }
  return checkShape(value, shape, "body");
}

const CODE = "004217";
function emailApp(): { app: TestApp; mail: FakeEmailGateway } {
  const mail = new FakeEmailGateway();
  return { mail, app: makeApp({ email: mail, emailCode: () => CODE }) };
}

const machineBody = () => ({ name: "Mac", platform: "macos", os_version: "15.2", app_version: "1.0.0", noise_public_key_b64: randomPublicKey() });

async function desktop(app: TestApp) {
  return loginDesktop(app, await registerAccount(app));
}

/** Two desktops of one account, each with its machine. */
async function twoDesktops(app: TestApp) {
  const account = await registerAccount(app);
  const one = await loginDesktop(app, account);
  const two = await loginDesktop(app, account);
  const m1 = await registerMachine(app, one.token);
  const m2 = await registerMachine(app, two.token);
  return { one, two, m1, m2 };
}

const key = (entry: { route: string; case?: string }) => `${entry.route}|${entry.case ?? ""}`;

/** How each answer of the contract is produced on a real relay. */
const recipes: Record<string, () => Promise<TestResponse>> = {
  "error|": async () => call(makeApp(), "GET", "/v2/machines"),
  "GET /v2/machines|": async () => {
    const app = makeApp();
    const { one, two, m2 } = await twoDesktops(app);
    // One machine has a heartbeat and one has none: last_seen_unix is an integer and null.
    expect((await call(app, "POST", `/v2/machines/${m2.machine_id}/heartbeat`, { token: two.token })).status).toBe(204);
    const res = await call(app, "GET", "/v2/machines", { token: one.token });
    expect((await res.json<{ machines: unknown[] }>()).machines).toHaveLength(2);
    return res;
  },
  "POST /v2/machines|new": async () => {
    const app = makeApp();
    return call(app, "POST", "/v2/machines", { token: (await desktop(app)).token, body: machineBody() });
  },
  "POST /v2/machines|again": async () => {
    const app = makeApp();
    const d = await desktop(app);
    const body = machineBody();
    expect((await call(app, "POST", "/v2/machines", { token: d.token, body })).status).toBe(201);
    return call(app, "POST", "/v2/machines", { token: d.token, body });
  },
  "POST /v2/machines/:id/heartbeat|": async () => {
    const app = makeApp();
    const d = await desktop(app);
    const m = await registerMachine(app, d.token);
    return call(app, "POST", `/v2/machines/${m.machine_id}/heartbeat`, { token: d.token });
  },
  "POST /v2/pairings|": async () => {
    const app = makeApp();
    const { one, m1, m2 } = await twoDesktops(app);
    return call(app, "POST", "/v2/pairings", {
      token: one.token,
      body: { from_machine_id: m1.machine_id, to_machine_id: m2.machine_id, requester_x25519_b64: m1.noiseKey },
    });
  },
  "GET /v2/pairings?role=requester|approved": async () => {
    const app = makeApp();
    const { one, two, m1, m2 } = await twoDesktops(app);
    const pairing = await requestPairing(app, one.token, m1.machine_id, m2.machine_id);
    await approvePairing(app, two.token, pairing.pairing_id);
    return call(app, "GET", "/v2/pairings?role=requester", { token: one.token });
  },
  "POST /v2/relay/tickets|register": async () => {
    const app = makeApp();
    const d = await desktop(app);
    const m = await registerMachine(app, d.token);
    return call(app, "POST", "/v2/relay/tickets", { token: d.token, body: { machine_id: m.machine_id, permission: "register" } });
  },
  "GET /v1/version|": async () =>
    call(makeApp(), "GET", "/v1/version", { headers: { "X-ShellX-Platform": "windows", "X-ShellX-OS-Version": "10.0.26100" } }),
  "POST /v1/auth/email/code|": async () => call(emailApp().app, "POST", "/v1/auth/email/code", { body: { email: randomEmail(), locale: "en" } }),
  "POST /v1/auth/email/verify|": async () => {
    const { app, mail } = emailApp();
    return signInEmail(app, mail);
  },
  "GET /v1/account/identities|email sign-in": async () => {
    const { app, mail } = emailApp();
    const session = await emailSession(app, mail);
    return call(app, "GET", "/v1/account/identities", { token: session.token });
  },
};

/** How each request route of the contract is sent: a fresh account (and relay) per case. */
const senders: Record<string, (body: Record<string, unknown>) => Promise<TestResponse>> = {
  "POST /v2/machines": async (body) => {
    const app = makeApp();
    return call(app, "POST", "/v2/machines", { token: (await desktop(app)).token, body: { noise_public_key_b64: randomPublicKey(), ...body } });
  },
  "POST /v1/auth/email/code": async (body) => call(emailApp().app, "POST", "/v1/auth/email/code", { body }),
};

const errorShape = file.responses.find((r) => r.route === "error")?.body ?? null;

describe("desktop contract: the checker", () => {
  it("finds a missing key, an extra key, a wrong type, an empty list and a body where none belongs", () => {
    const shape: Shape = { a: "string", "b?": "integer|null", c: [{ d: "boolean" }] };
    expect(checkShape({ a: "x", c: [{ d: true }] }, shape, "v")).toEqual([]);
    expect(checkShape({ a: "x", b: null, c: [{ d: false }] }, shape, "v")).toEqual([]);
    expect(checkShape({ c: [{ d: true }] }, shape, "v")).toEqual(["v.a: missing"]);
    expect(checkShape({ a: "x", c: [{ d: true }], e: 1 }, shape, "v")).toEqual(["v.e: not in the contract"]);
    expect(checkShape({ a: "x", b: 1.5, c: [{ d: true }] }, shape, "v")).toEqual(["v.b: 1.5 is not integer|null"]);
    expect(checkShape({ a: "x", c: [] }, shape, "v")).toEqual(["v.c: [] is not a non-empty array"]);
  });
});

describe("desktop contract: answers", () => {
  it("has one recipe per answer", () => {
    expect(file.responses.map(key).sort()).toEqual(Object.keys(recipes).sort());
  });

  for (const entry of file.responses) {
    it(`${entry.route}${entry.case === undefined ? "" : ` (${entry.case})`}`, async () => {
      const recipe = recipes[key(entry)];
      if (recipe === undefined) throw new Error(`no recipe for ${key(entry)}`);
      const res = await recipe();
      if (entry.status !== undefined) expect(res.status, await res.text()).toBe(entry.status);
      expect(await bodyProblems(res, entry.body)).toEqual([]);
    });
  }
});

describe("desktop contract: requests", () => {
  it("has one sender per request route", () => {
    expect(file.requests.map((r) => r.route).sort()).toEqual(Object.keys(senders).sort());
  });

  describe.each(file.requests)("$route", (route) => {
    it.each(route.cases)("$label: $status", async (c) => {
      const send = senders[route.route];
      if (send === undefined) throw new Error(`no sender for ${route.route}`);
      const res = await send({ ...route.base, ...c.set });
      expect(res.status, await res.text()).toBe(c.status);
      if (c.error !== undefined) {
        expect(await bodyProblems(res, errorShape)).toEqual([]);
        expect((await res.json<{ error: { code: string } }>()).error.code).toBe(c.error);
      }
    });
  });
});
