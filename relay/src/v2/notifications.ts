import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import type { ApnsEnvironment, ApnsMessage } from "../push/apns.js";
import { ownMachine, requireDesktop } from "./guard.js";

export const notificationRoutesV2 = new Hono<AppEnv>();

/** `apns-collapse-id` takes at most 64 bytes, and the request id is used as one. */
export const REQUEST_ID_MAX_BYTES = 64;
export const AGENT_MAX_CHARS = 64;
export const WORKSPACE_TITLE_MAX_CHARS = 200;
/** How long APNs keeps trying to reach a phone that is off. */
export const NEEDS_YOU_EXPIRY_SEC = 24 * 60 * 60;

interface Recipient {
  device_id: string;
  token: string;
  apns_topic: string;
  apns_env: ApnsEnvironment;
}

/**
 * POST /v2/notifications {kind, request_id, agent?, workspace_title?} — the Mac only. Pushes to every
 * phone of the account granted this Mac that has an APNs token and a live sign-in:
 * - `needs_you`: an agent waits for the user. The alert names the agent and the workspace (words from
 *   the phone's own strings, `push.needsYou[.workspace]`), never what the agent asks; tapping it opens
 *   that request. It replaces an earlier one for the same request (`apns-collapse-id`).
 * - `resolved`: the request was handled; a background push lets the phone take the alert away.
 * 202 `{sent}`; tokens APNs reports as gone are deleted. 503 `push_unavailable` without APNs set up,
 * 404 for a desktop without a machine, 429 past the per-device limit (`needs_you` only; `resolved` is not counted). Nothing about the request is
 * logged but its kind and counts.
 */
notificationRoutesV2.post("/", requireAuth, requireDesktop, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const apns = c.get("apns");
  if (apns === null) throw Errors.pushUnavailable();
  const body = await readJsonObject(c.req.raw);
  const { kind, request_id: requestId, agent, workspace_title: workspace = "" } = body;
  if (kind !== "needs_you" && kind !== "resolved") throw Errors.badRequest();
  if (typeof requestId !== "string" || requestId === "" || Buffer.byteLength(requestId) > REQUEST_ID_MAX_BYTES) throw Errors.badRequest();
  if (kind === "needs_you") {
    if (typeof agent !== "string" || agent.trim() === "" || [...agent].length > AGENT_MAX_CHARS) throw Errors.badRequest();
    if (typeof workspace !== "string" || [...workspace].length > WORKSPACE_TITLE_MAX_CHARS) throw Errors.badRequest();
  }
  // Only an alert counts against the limit, and only once its body is valid: a resolved takes an alert away.
  if (kind === "needs_you" && !(await c.get("limiters").notifyAgent.limit(auth.deviceId))) throw Errors.rateLimited();
  const db = c.get("db");
  const machine = ownMachine(db, auth.deviceId);
  if (machine === undefined) throw Errors.notFound();
  const now = c.get("now")();
  const recipients = db.all<Recipient>(
    `SELECT pt.device_id, pt.token, pt.apns_topic, pt.apns_env
       FROM phone_grants g
       JOIN devices d ON d.id = g.device_id AND d.user_id = ? AND d.kind = 'mobile'
       JOIN push_tokens pt ON pt.device_id = g.device_id AND pt.apns_topic IS NOT NULL AND pt.apns_env IS NOT NULL
      WHERE g.machine_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)`,
    auth.userId, machine.id, now - TOKEN_IDLE_TTL_MS,
  );
  const data = { kind, machine_id: machine.id, request_id: requestId };
  const message = (r: Recipient): ApnsMessage => {
    const base = { token: r.token, topic: r.apns_topic, environment: r.apns_env };
    if (kind === "resolved") {
      return { ...base, pushType: "background", priority: 5, payload: { aps: { "content-available": 1 }, shellx: data } };
    }
    const named = (workspace as string).trim() !== "";
    return {
      ...base, pushType: "alert", priority: 10, collapseId: requestId,
      expiresAtSec: Math.floor(now / 1000) + NEEDS_YOU_EXPIRY_SEC,
      payload: {
        aps: {
          alert: {
            "title-loc-key": "push.title",
            "loc-key": named ? "push.needsYou.workspace" : "push.needsYou",
            "loc-args": named ? [agent, workspace] : [agent],
          },
          sound: "default", "thread-id": machine.id,
        },
        shellx: data,
      },
    };
  };
  const results = await Promise.all(recipients.map((r) => apns.send(message(r))));
  let sent = 0;
  let removed = 0;
  results.forEach((result, i) => {
    if (result === "ok") sent++;
    if (result === "invalid_token") {
      const r = recipients[i]!;
      removed += db.run("DELETE FROM push_tokens WHERE device_id = ? AND token = ?", r.device_id, r.token).changes;
    }
  });
  logMeta("v2_notification", { device_id: auth.deviceId, kind, recipients: recipients.length, sent, tokens_removed: removed });
  return c.json({ sent }, 202);
});
