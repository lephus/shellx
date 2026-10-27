import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { accountMachine, ownMachine, phoneGrant } from "./guard.js";
import { hasGrant } from "./pairings.js";
import { mintTicket, ticketClaims } from "./tickets.js";

export const relayTicketRoutes = new Hono<AppEnv>();

/** POST /v2/relay/tickets {machine_id, permission, target_machine_id?, lane?: "link"} — a 120 s cmux-relay ticket. */
relayTicketRoutes.post("/", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const config = c.get("config");
  if (auth.kind !== "desktop" && auth.kind !== "mobile") throw Errors.desktopOnly();
  if (config.relayHmacSecret === null) throw Errors.relayV2Unavailable();
  if (!(await c.get("limiters").ticketMint.limit(auth.deviceId))) throw Errors.rateLimited();

  const body = await readJsonObject(c.req.raw);
  const permission = body.permission;

  if (auth.kind === "mobile") {
    // A phone only ever connects to the link slot of a machine of its account that approved it.
    if (permission !== "connect") throw permission === "register" ? Errors.forbidden() : Errors.badRequest();
    if (body.lane !== "link" || body.target_machine_id === undefined) throw Errors.badRequest();
    const target = accountMachine(db, auth.userId, body.target_machine_id);
    if (target === undefined) throw Errors.machineNotFound();
    if (phoneGrant(db, auth.deviceId, target.id) === undefined) throw Errors.notGranted();
    const claims = ticketClaims("connect", target.link_slot, config.relayIssuer, c.get("now")());
    logMeta("relay_ticket", { device_id: auth.deviceId, permission });
    return c.json({
      ticket: mintTicket(config.relayHmacSecret, claims),
      expires_at_unix: claims.expires_at_unix,
      relay_url: config.relayV2Url,
    });
  }

  if (permission !== "register" && permission !== "connect") throw Errors.badRequest();

  // `link` selects the machine's ShellX Link slot; no lane is the cmux-tui slot. Nothing else is valid.
  const lane = body.lane;
  if (lane !== undefined && lane !== "link") throw Errors.badRequest();
  const slotOf = (m: { slot: string; link_slot: string }) => (lane === "link" ? m.link_slot : m.slot);

  const machine = accountMachine(db, auth.userId, body.machine_id);
  if (machine === undefined) throw Errors.machineNotFound();
  const own = ownMachine(db, auth.deviceId);
  if (own === undefined || own.id !== machine.id) throw Errors.forbidden();

  let slot = slotOf(own);
  if (permission === "connect") {
    const target = accountMachine(db, auth.userId, body.target_machine_id);
    if (body.target_machine_id === undefined) throw Errors.badRequest();
    if (target === undefined) throw Errors.machineNotFound();
    // D3: a machine may connect to itself without a grant (enrollment invites); others need an approved pairing.
    if (target.id !== own.id) {
      if (!hasGrant(db, own.id, target.id)) throw Errors.notGranted();
      slot = slotOf(target);
    }
  }

  const claims = ticketClaims(permission, slot, config.relayIssuer, c.get("now")());
  logMeta("relay_ticket", { device_id: auth.deviceId, permission });
  return c.json({
    ticket: mintTicket(config.relayHmacSecret, claims),
    expires_at_unix: claims.expires_at_unix,
    relay_url: config.relayV2Url,
  });
});
