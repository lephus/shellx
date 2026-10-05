import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";

export const NOTIFICATION_TITLE_MAX_CHARS = 200;
export const NOTIFICATION_BODY_MAX_CHARS = 1000;
export const NOTIFICATION_DATA_MAX_KEYS = 10;
export const NOTIFICATION_DATA_VALUE_MAX_CHARS = 256;
/**
 * FCM refuses messages over 4096 bytes of payload; title + body + data keys and values (UTF-8)
 * stay under this, leaving room for `agent_id` and the rest of the message.
 */
export const NOTIFICATION_MAX_PAYLOAD_BYTES = 3584;
const DATA_KEY = /^[a-z0-9_]{1,64}$/;
const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;

/** False for a string with a lone UTF-16 surrogate (it has no UTF-8 form; FCM would refuse it). */
function isWellFormed(text: string): boolean {
  return !LONE_SURROGATE.test(text);
}

function utf8Bytes(text: string): number {
  return Buffer.byteLength(text, "utf8");
}

/**
 * Keys FCM refuses in `data` with INVALID_ARGUMENT — which would make the relay delete the phone's
 * token — so they are refused here with 400 instead. `agent_id` is set by the relay itself.
 */
function isReservedDataKey(key: string): boolean {
  return ["from", "notification", "message_type", "collapse_key", "agent_id"].includes(key) || /^(google|gcm)/i.test(key);
}

function codePoints(text: string): number {
  return [...text].length;
}

function parseData(value: unknown): Record<string, string> | null {
  if (value === undefined || value === null) return {};
  if (typeof value !== "object" || Array.isArray(value)) return null;
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > NOTIFICATION_DATA_MAX_KEYS) return null;
  const data: Record<string, string> = {};
  for (const [key, item] of entries) {
    if (!DATA_KEY.test(key) || isReservedDataKey(key) || typeof item !== "string") return null;
    if (!isWellFormed(item) || codePoints(item) > NOTIFICATION_DATA_VALUE_MAX_CHARS) return null;
    data[key] = item;
  }
  return data;
}

interface Recipient {
  device_id: string;
  token: string;
}

export const notificationRoutes = new Hono<AppEnv>();

/**
 * POST /v1/notifications {title, body, data?} — agents only (push spec §5). Sends one push to every
 * phone of the account that has a pairing record with this agent, a push token and a live sign-in.
 * `data` (at most 10 keys `[a-z0-9_]{1,64}`, string values ≤ 256 characters) is passed through with `agent_id` added by the relay.
 * Answers `202 {sent}` once FCM has answered for every phone; tokens FCM reports as gone are deleted.
 * 503 `push_unavailable` when the relay has no Firebase configuration; 429 past 120 per agent per
 * hour (N10). 400 for anything FCM would refuse as a payload error (too large — title, body and
 * data over 3.5 KB of UTF-8 —, lone surrogates), so such a request never reaches FCM and never costs
 * a phone its token. Neither the content nor the tokens are ever logged.
 */
notificationRoutes.post("/", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const push = c.get("push");
  if (push === null) throw Errors.pushUnavailable();
  if (!(await c.get("limiters").notifyAgent.limit(auth.deviceId))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const { title, body: text } = body;
  if (typeof title !== "string" || title.trim() === "" || codePoints(title) > NOTIFICATION_TITLE_MAX_CHARS) throw Errors.badRequest();
  if (typeof text !== "string" || text.trim() === "" || codePoints(text) > NOTIFICATION_BODY_MAX_CHARS) throw Errors.badRequest();
  if (!isWellFormed(title) || !isWellFormed(text)) throw Errors.badRequest();
  const data = parseData(body.data);
  if (data === null) throw Errors.badRequest();
  const payloadBytes =
    utf8Bytes(title) + utf8Bytes(text) + Object.entries(data).reduce((n, [k, v]) => n + utf8Bytes(k) + utf8Bytes(v), 0);
  if (payloadBytes > NOTIFICATION_MAX_PAYLOAD_BYTES) throw Errors.badRequest();

  const db = c.get("db");
  const recipients = db.all<Recipient>(
    `SELECT pt.device_id, pt.token
       FROM pairings p
       JOIN devices d ON d.id = p.mobile_id AND d.user_id = ? AND d.kind = 'mobile'
       JOIN push_tokens pt ON pt.device_id = p.mobile_id
      WHERE p.agent_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)`,
    auth.userId,
    auth.deviceId,
    c.get("now")() - TOKEN_IDLE_TTL_MS,
  );
  const message = { title, body: text, data: { ...data, agent_id: auth.deviceId } };
  const results = await Promise.all(recipients.map((r) => push.send({ ...message, token: r.token })));
  let sent = 0;
  let removed = 0;
  results.forEach((result, i) => {
    if (result === "ok") sent++;
    if (result === "invalid_token") {
      const r = recipients[i]!;
      removed += db.run("DELETE FROM push_tokens WHERE device_id = ? AND token = ?", r.device_id, r.token).changes;
    }
  });
  logMeta("notification", { device_id: auth.deviceId, recipients: recipients.length, sent, tokens_removed: removed });
  return c.json({ sent }, 202);
});
