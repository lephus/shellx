import { createHmac } from "node:crypto";
import { unixSeconds } from "./encoding.js";

export const TICKET_LIFETIME_SECONDS = 120;

/** Field order is the serde order of `RelayTicketClaims` in cmux-remote-protocol/src/relay.rs. */
export interface RelayTicketClaims {
  version: 2;
  issuer: string;
  permission: "register" | "connect";
  role: "daemon" | "client";
  slot: string;
  circuit: null;
  lane: null;
  generation: null;
  issued_at_unix: number;
  expires_at_unix: number;
}

export function ticketClaims(permission: "register" | "connect", slot: string, issuer: string, nowMs: number): RelayTicketClaims {
  const issued = unixSeconds(nowMs);
  return {
    version: 2,
    issuer,
    permission,
    role: permission === "register" ? "daemon" : "client",
    slot,
    circuit: null,
    lane: null,
    generation: null,
    issued_at_unix: issued,
    expires_at_unix: issued + TICKET_LIFETIME_SECONDS,
  };
}

export function signingPayload(c: RelayTicketClaims): string {
  return [
    "cmux-relay-ticket-v2", String(c.version), c.issuer, c.permission, c.role, c.slot,
    c.circuit ?? "", c.lane ?? "", c.generation ?? "", String(c.issued_at_unix), String(c.expires_at_unix),
  ].join("\n");
}

export function mintTicket(secret: Uint8Array, c: RelayTicketClaims): string {
  const body = Buffer.from(JSON.stringify(c)).toString("base64url");
  const sig = createHmac("sha256", secret).update(signingPayload(c), "utf8").digest("base64url");
  return `v2.${body}.${sig}`;
}
