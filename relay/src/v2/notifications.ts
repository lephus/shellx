import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { errorKind, logMeta } from "../log.js";
import type { ApnsEnvironment, ApnsMessage } from "../push/apns.js";
import type { FcmDataMessage, PushResult } from "../push/fcm.js";
import { ownMachine, requireDesktop } from "./guard.js";

export const notificationRoutesV2 = new Hono<AppEnv>();

/** `apns-collapse-id` takes at most 64 bytes, and the request id is used as one. */
export const REQUEST_ID_MAX_BYTES = 64;
export const AGENT_MAX_CHARS = 64;
export const WORKSPACE_TITLE_MAX_CHARS = 200;
/**
 * How long APNs and FCM keep trying to reach a phone that is off. FCM keeps a `resolved` that long
 * too, so it can still replace an undelivered alert of the same collapse key.
 */
export const NEEDS_YOU_EXPIRY_SEC = 24 * 60 * 60;

interface ApnsRecipient {
  device_id: string;
  token: string;
  apns_topic: string;
  apns_env: ApnsEnvironment;
}

interface FcmRecipient {
  device_id: string;
  token: string;
}

/**
 * POST /v2/notifications {kind, request_id, agent?, workspace_title?} — the Mac only. Pushes to every
 * phone of the account granted this Mac that has a push token and a live sign-in:
 * - `needs_you`: an agent waits for the user. An iPhone (APNs token) gets an alert in the phone's own
 *   words (`push.needsYou[.workspace]`); an Android phone (device platform `android`, a token without
 *   `apns_topic`) gets an FCM data-only message `{kind, machine_id, request_id, agent,
 *   workspace_title}` with priority high, a 24 h TTL and `collapse_key` = `request_id`. Never what the
 *   agent asks; tapping opens that request. It replaces an earlier one for the same request.
 * - `resolved`: the request was handled; iPhones get a background push, Android phones a normal-priority
 *   data message `{kind, machine_id, request_id}` with the same collapse key and TTL, so the phone
 *   takes the alert away (or never shows it).
 * 202 `{sent}` once every send has finished; one phone's failure never stops the others; tokens APNs
 * or FCM report as gone are deleted. 503 `push_unavailable` only without both APNs and FCM set up,
 * 404 for a desktop without a machine, 429 past the per-device limit (`needs_you` only; `resolved` is
 * not counted). Nothing about the request is logged but its kind and counts.
 */
notificationRoutesV2.post("/", requireAuth, requireDesktop, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const apns = c.get("apns");
  const fcm = c.get("fcm");
  if (apns === null && fcm === null) throw Errors.pushUnavailable();
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
  const apnsRecipients = apns === null ? [] : db.all<ApnsRecipient>(
    `SELECT pt.device_id, pt.token, pt.apns_topic, pt.apns_env
       FROM phone_grants g
       JOIN devices d ON d.id = g.device_id AND d.user_id = ? AND d.kind = 'mobile'
       JOIN push_tokens pt ON pt.device_id = g.device_id AND pt.apns_topic IS NOT NULL AND pt.apns_env IS NOT NULL
      WHERE g.machine_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)`,
    auth.userId, machine.id, now - TOKEN_IDLE_TTL_MS,
  );
  const fcmRecipients = fcm === null ? [] : db.all<FcmRecipient>(
    `SELECT pt.device_id, pt.token
       FROM phone_grants g
       JOIN devices d ON d.id = g.device_id AND d.user_id = ? AND d.kind = 'mobile' AND d.platform = 'android'
       JOIN push_tokens pt ON pt.device_id = g.device_id AND pt.apns_topic IS NULL
      WHERE g.machine_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)`,
    auth.userId, machine.id, now - TOKEN_IDLE_TTL_MS,
  );
  const data = { kind, machine_id: machine.id, request_id: requestId };
  const message = (r: ApnsRecipient): ApnsMessage => {
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
  const fcmMessage = (r: FcmRecipient): FcmDataMessage => kind === "resolved"
    ? { token: r.token, data, priority: "normal", ttlSec: NEEDS_YOU_EXPIRY_SEC, collapseKey: requestId }
    : {
      token: r.token, data: { ...data, agent: agent as string, workspace_title: workspace as string },
      priority: "high", ttlSec: NEEDS_YOU_EXPIRY_SEC, collapseKey: requestId,
    };
  // A send that throws (a bug, not an APNs or FCM answer) counts as not sent and never fails the others.
  const settled = await Promise.allSettled([
    ...apnsRecipients.map((r) => apns!.send(message(r))),
    ...fcmRecipients.map((r) => fcm!.sendData(fcmMessage(r))),
  ]);
  const recipients: { device_id: string; token: string }[] = [...apnsRecipients, ...fcmRecipients];
  let sent = 0;
  let removed = 0;
  settled.forEach((outcome, i) => {
    let result: PushResult = "error";
    if (outcome.status === "fulfilled") result = outcome.value;
    else logMeta("v2_notification_send_failed", { via: i < apnsRecipients.length ? "apns" : "fcm", error: errorKind(outcome.reason) });
    if (result === "ok") sent++;
    if (result === "invalid_token") {
      const r = recipients[i]!;
      removed += db.run("DELETE FROM push_tokens WHERE device_id = ? AND token = ?", r.device_id, r.token).changes;
    }
  });
  logMeta("v2_notification", {
    device_id: auth.deviceId, kind, recipients: recipients.length, fcm_recipients: fcmRecipients.length, sent, tokens_removed: removed,
  });
  return c.json({ sent }, 202);
});
