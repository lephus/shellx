// Post-deploy smoke test for relay v2: log in as a throwaway desktop, register a machine, mint a
// `register` ticket and let the real cmux-relay accept it. Prints only the two lines below; never a
// token, ticket, slot or password.
//   npm run relay2:smoke
import { randomBytes } from "node:crypto";
import { pathToFileURL } from "node:url";
import { WebSocket } from "ws";
import { createTtyPrompter } from "../src/scripts/prompter.js";

export type SmokeResult =
  | { ok: true; lease: number }
  | { ok: false; step: string; status?: number; code?: string };

export interface SmokeOptions {
  base: string;
  email: string;
  password: string;
  fetch?: typeof fetch;
  WebSocket?: typeof WebSocket;
  /** How long the relay may take to answer `register` (ms). */
  registerTimeoutMs?: number;
}

class StepFailure extends Error {
  constructor(readonly step: string, readonly status?: number, readonly code?: string) {
    super(step);
  }
}

async function api(
  f: typeof fetch, base: string, step: string, method: string, path: string, token?: string, body?: unknown,
): Promise<Record<string, unknown>> {
  let res: Response;
  try {
    res = await f(new URL(path, base), {
      method,
      headers: {
        ...(token === undefined ? {} : { Authorization: `Bearer ${token}` }),
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  } catch {
    throw new StepFailure(step);
  }
  const text = await res.text();
  let json: Record<string, unknown> = {};
  try {
    const parsed: unknown = text === "" ? {} : JSON.parse(text);
    if (typeof parsed === "object" && parsed !== null) json = parsed as Record<string, unknown>;
  } catch { /* not JSON */ }
  if (!res.ok) {
    const error = json.error;
    const code = typeof error === "object" && error !== null ? (error as { code?: unknown }).code : undefined;
    throw new StepFailure(step, res.status, typeof code === "string" ? code : undefined);
  }
  return json;
}

function str(value: unknown, step: string): string {
  if (typeof value !== "string" || value === "") throw new StepFailure(step);
  return value;
}

function registerOnRelay(Ws: typeof WebSocket, url: string, slot: string, ticket: string, timeoutMs: number): Promise<number> {
  return new Promise((resolve, reject) => {
    const fail = () => reject(new StepFailure("register"));
    let ws: WebSocket;
    try {
      ws = new Ws(url); // no Origin header: cmux-relay answers 403 to any browser origin
    } catch {
      fail();
      return;
    }
    const timer = setTimeout(() => { ws.terminate(); fail(); }, timeoutMs);
    const done = (settle: () => void) => { clearTimeout(timer); ws.terminate(); settle(); };
    ws.on("open", () => ws.send(JSON.stringify({ type: "register", protocol: 5, slot, ticket })));
    ws.on("message", (data) => {
      let msg: { type?: unknown; lease_seconds?: unknown } = {};
      try { msg = JSON.parse(data.toString()) as typeof msg; } catch { /* ignore */ }
      if (msg.type === "registered" && typeof msg.lease_seconds === "number") {
        const lease = msg.lease_seconds;
        done(() => resolve(lease));
      } else {
        done(fail);
      }
    });
    ws.on("error", () => done(fail));
    ws.on("close", () => done(fail));
  });
}

/** https anywhere, plain http only to this machine (local runs): the password must never cross the network in clear. */
export function isSecureBase(base: string): boolean {
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    return false;
  }
  if (url.protocol === "https:") return true;
  return url.protocol === "http:" && url.username === "" && (url.hostname === "127.0.0.1" || url.hostname === "localhost");
}

export async function runRelay2Smoke(options: SmokeOptions): Promise<SmokeResult> {
  const f = options.fetch ?? fetch;
  const Ws = options.WebSocket ?? WebSocket;
  const base = options.base;
  if (!isSecureBase(base)) return { ok: false, step: "base", code: "insecure URL" };
  let token: string | undefined;
  let machineId: string | undefined;
  try {
    const login = await api(f, base, "login", "POST", "/v1/auth/login", undefined, {
      email: options.email,
      password: options.password,
      device: { kind: "desktop", name: "relay2-smoke", platform: "macos", public_key: randomBytes(32).toString("base64url") },
    });
    token = str(login.token, "login");
    const machine = await api(f, base, "machine", "POST", "/v2/machines", token, {
      name: "relay2-smoke", platform: "macos", os_version: "1.0", app_version: "1.0.0",
      noise_public_key_b64: randomBytes(32).toString("base64url"),
    });
    machineId = str(machine.machine_id, "machine");
    const slot = str(machine.slot, "machine");
    const minted = await api(f, base, "ticket", "POST", "/v2/relay/tickets", token, { machine_id: machineId, permission: "register" });
    const ticket = str(minted.ticket, "ticket");
    const relayUrl = str(minted.relay_url, "ticket");
    const lease = await registerOnRelay(Ws, relayUrl, slot, ticket, options.registerTimeoutMs ?? 5000);
    return { ok: true, lease };
  } catch (err) {
    if (err instanceof StepFailure) {
      return { ok: false, step: err.step, ...(err.status === undefined ? {} : { status: err.status }), ...(err.code === undefined ? {} : { code: err.code }) };
    }
    return { ok: false, step: "unexpected" };
  } finally {
    if (token !== undefined) {
      if (machineId !== undefined) await api(f, base, "cleanup", "DELETE", `/v2/machines/${machineId}`, token).catch(() => undefined);
      await api(f, base, "cleanup", "POST", "/v1/auth/logout", token).catch(() => undefined);
    }
  }
}

export function formatResult(result: SmokeResult): string {
  if (result.ok) return `relay2 smoke: OK (registered, lease ${result.lease} s)`;
  const detail = [result.status, result.code].filter((x) => x !== undefined).join(" ");
  return `relay2 smoke: FAIL at ${result.step}${detail === "" ? "" : ` (${detail})`}`;
}

async function main(): Promise<number> {
  const prompter = createTtyPrompter();
  let base: string, email: string, password: string;
  try {
    base = (await prompter.ask("API base [https://relay.shellx.pro]: ")).trim() || "https://relay.shellx.pro";
    if (!isSecureBase(base)) {
      console.log(formatResult({ ok: false, step: "base", code: "insecure URL" }));
      return 1;
    }
    email = (await prompter.ask("E-mail: ")).trim();
    password = await prompter.ask("Password: ", { hidden: true });
  } catch {
    console.log("relay2 smoke: FAIL at prompt");
    return 1;
  } finally {
    prompter.close();
  }
  const result = await runRelay2Smoke({ base, email, password });
  console.log(formatResult(result));
  return result.ok ? 0 : 1;
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main();
}
