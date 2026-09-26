import { randomUUID } from "node:crypto";
import { upgradeWebSocket } from "@hono/node-server";
import type { Context, MiddlewareHandler } from "hono";
import type { WebSocket } from "ws";
import type { AppEnv } from "../app.js";
import { clientIp } from "../auth/client-ip.js";
import { authenticate } from "../auth/session.js";
import { parseBearer } from "../auth/tokens.js";
import type { HubSocket } from "../hub/user-hub.js";
import { Errors } from "../http/errors.js";
import { errorKind, logMeta } from "../log.js";
import { CloseCode } from "../protocol/frames.js";

/** Close code for a connection the hub could not admit (its tombstones could not be read). */
export const INTERNAL_ERROR_CLOSE = 1011;

function hasUpgradeToken(connection: string | undefined): boolean {
  return (connection ?? "").split(",").some((token) => token.trim().toLowerCase() === "upgrade");
}

/**
 * GET /v1/ws, step 1 — validates the bearer token before any upgrade. Every upgrade attempt first
 * counts against its IP's limit (60 per 60 s, `upgradeIp`), valid token or not: over it, HTTP 429
 * `rate_limited` (shellx_core retries with backoff). A missing/revoked/expired token is refused with
 * HTTP 401 `unauthorized` (shellx_core maps it to the `revoked` state). A plain GET — or one carrying
 * `Upgrade: websocket` without `Connection: upgrade`, which Node never treats as an upgrade — gets
 * 426 `upgrade_required`.
 */
export const webSocketAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") throw Errors.upgradeRequired();
  const ip = clientIp(c.req.header("X-Real-IP"), c.env.incoming.socket.remoteAddress);
  if (!(await c.get("limiters").upgradeIp.limit(ip))) throw Errors.rateLimited();
  const auth = await authenticate(c.get("db"), parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();
  if (!hasUpgradeToken(c.req.header("Connection"))) throw Errors.upgradeRequired();
  c.set("auth", auth);
  await next();
};

/**
 * GET /v1/ws, step 2 — @hono/node-server completes the upgrade with `ws` and calls these handlers.
 * The socket joins the account's hub; `ping` is answered at once, outside the hub's queue (spec
 * §4.2), within the device's frame budget and only while at most 64 KiB wait to be sent to it (see
 * `UserHub.ping`). Only the validated token decides the device id and kind; nothing the client sends
 * in headers reaches the hub.
 */
export const webSocketUpgrade = upgradeWebSocket(
  (context) => {
    const c = context as Context<AppEnv>; // node-server types the context loosely
    const auth = c.get("auth");
    const db = c.get("db");
    const hubs = c.get("hubs");
    const now = c.get("now");
    const token = parseBearer(c.req.header("Authorization"));
    const connId = randomUUID();
    let socket: HubSocket | null = null;

    const admit = async (joined: HubSocket): Promise<void> => {
      try {
        await hubs.forUser(auth.userId).connect(joined, { deviceId: auth.deviceId, kind: auth.kind, connId });
      } catch {
        logMeta("ws_join_failed", { device_id: auth.deviceId });
        try {
          joined.close(INTERNAL_ERROR_CLOSE, "internal_error");
        } catch {
          // already closed
        }
        return;
      }
      // TOCTOU guard: a revocation (password change, account deletion) can commit — and run its own
      // disconnect — between the authenticate() above and this socket joining the hub. Re-validate
      // the same token now that the socket is live, and close exactly this connection (never
      // whatever socket the device has by now) if it is no longer valid. A re-check that cannot
      // complete (database error) fails closed, the same as "revoked".
      try {
        if ((await authenticate(db, token, now())) === null) {
          await hubs.forUser(auth.userId).closeConnection(connId, CloseCode.revoked);
        }
      } catch (err) {
        logMeta("ws_recheck_failed", { device_id: auth.deviceId, error: errorKind(err) });
        try {
          await hubs.forUser(auth.userId).closeConnection(connId, CloseCode.revoked);
        } catch {
          // Nothing more to do; the hub logged the failure by kind.
        }
      }
    };

    return {
      onOpen(_event, ws) {
        socket = ws.raw as unknown as WebSocket;
        void admit(socket);
      },
      onMessage(event) {
        if (socket === null) return;
        if (event.data === "ping") {
          hubs.forUser(auth.userId).ping(socket, auth.deviceId); // "pong" right away, outside the queue
          return;
        }
        const data = event.data;
        hubs.forUser(auth.userId).receive(socket, typeof data === "string" || data instanceof ArrayBuffer ? data : "");
      },
      onClose() {
        if (socket !== null) hubs.forUser(auth.userId).disconnected(socket);
      },
    };
  },
  { onError: (err) => logMeta("ws_handler_error", { error: errorKind(err) }) },
);
