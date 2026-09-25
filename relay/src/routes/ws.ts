import type { Context } from "hono";
import type { AppEnv } from "../app";
import { authenticate } from "../auth/session";
import { parseBearer } from "../auth/tokens";
import { DEVICE_ID_HEADER, DEVICE_KIND_HEADER, hubFor } from "../hub/user-hub";
import { Errors } from "../http/errors";

/**
 * GET /v1/ws — validates the bearer token, then hands the upgrade to the account's UserHub.
 * A missing/revoked/expired token is refused with plain HTTP 401 `unauthorized` before any
 * upgrade happens (shellx_core maps that to the `revoked` state).
 */
export async function webSocketRoute(c: Context<AppEnv>): Promise<Response> {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") throw Errors.upgradeRequired();
  const auth = await authenticate(c.env.DB, parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();

  const headers = new Headers(c.req.raw.headers);
  headers.delete("Authorization");
  headers.set(DEVICE_ID_HEADER, auth.deviceId);
  headers.set(DEVICE_KIND_HEADER, auth.kind);
  return hubFor(c.env, auth.userId).fetch(new Request("https://user-hub/connect", { headers }));
}
