import type { Context } from "hono";
import type { AppEnv } from "../app";
import type { AuthContext } from "../auth/session";
import { authenticate } from "../auth/session";
import { parseBearer } from "../auth/tokens";
import { DEVICE_ID_HEADER, DEVICE_KIND_HEADER, hubFor } from "../hub/user-hub";
import { Errors } from "../http/errors";

/**
 * The only client headers forwarded to the Durable Object: what the WebSocket upgrade itself
 * needs. Everything else the client sent (Authorization in particular) is dropped rather than
 * allowlisted-out, so a hostile client cannot smuggle anything through the hub's own headers
 * (e.g. spoofing X-Shellx-Device-Id/-Kind, which are instead set below from the validated token).
 */
const UPGRADE_HEADERS = [
  "Upgrade",
  "Connection",
  "Sec-WebSocket-Key",
  "Sec-WebSocket-Version",
  "Sec-WebSocket-Protocol",
  "Sec-WebSocket-Extensions",
] as const;

/**
 * Builds the headers forwarded to the account's UserHub: only `UPGRADE_HEADERS` from the client
 * (whatever it sent for anything else — Cookie, X-Forwarded-For, its own X-Shellx-* headers, in
 * any letter case — is ignored, never copied), plus the two X-Shellx-* identity headers set from
 * the already-validated token. Exported so the allowlist itself can be unit-tested directly.
 */
export function buildHubHeaders(clientHeaders: Headers, auth: Pick<AuthContext, "deviceId" | "kind">): Headers {
  const headers = new Headers();
  for (const name of UPGRADE_HEADERS) {
    const value = clientHeaders.get(name);
    if (value !== null) headers.set(name, value);
  }
  headers.set(DEVICE_ID_HEADER, auth.deviceId);
  headers.set(DEVICE_KIND_HEADER, auth.kind);
  return headers;
}

/**
 * GET /v1/ws — validates the bearer token, then hands the upgrade to the account's UserHub.
 * A missing/revoked/expired token is refused with plain HTTP 401 `unauthorized` before any
 * upgrade happens (shellx_core maps that to the `revoked` state).
 */
export async function webSocketRoute(c: Context<AppEnv>): Promise<Response> {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") throw Errors.upgradeRequired();
  const auth = await authenticate(c.env.DB, parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();

  const headers = buildHubHeaders(c.req.raw.headers, auth);
  return hubFor(c.env, auth.userId).fetch(new Request("https://user-hub/connect", { headers }));
}
