import { describe, expect, it } from "vitest";
import { mintTicket, signingPayload, ticketClaims, TICKET_LIFETIME_SECONDS } from "../src/v2/tickets.js";

const SECRET = new TextEncoder().encode("0123456789abcdef0123456789abcdef");
const SLOT = "AAAAAAAAAAAAAAAAAAAAAA";

describe("v2 tickets", () => {
  it("matches the cmux-relay golden register ticket", () => {
    expect(TICKET_LIFETIME_SECONDS).toBe(120);
    const register = ticketClaims("register", SLOT, "shellx-relay", 1_760_000_000_999);
    expect(register).toEqual({ version: 2, issuer: "shellx-relay", permission: "register", role: "daemon", slot: SLOT,
      circuit: null, lane: null, generation: null, issued_at_unix: 1760000000, expires_at_unix: 1760000120 });
    expect(signingPayload(register)).toBe("cmux-relay-ticket-v2\n2\nshellx-relay\nregister\ndaemon\nAAAAAAAAAAAAAAAAAAAAAA\n\n\n\n1760000000\n1760000120");
    expect(mintTicket(SECRET, register)).toBe("v2.eyJ2ZXJzaW9uIjoyLCJpc3N1ZXIiOiJzaGVsbHgtcmVsYXkiLCJwZXJtaXNzaW9uIjoicmVnaXN0ZXIiLCJyb2xlIjoiZGFlbW9uIiwic2xvdCI6IkFBQUFBQUFBQUFBQUFBQUFBQUFBQUEiLCJjaXJjdWl0IjpudWxsLCJsYW5lIjpudWxsLCJnZW5lcmF0aW9uIjpudWxsLCJpc3N1ZWRfYXRfdW5peCI6MTc2MDAwMDAwMCwiZXhwaXJlc19hdF91bml4IjoxNzYwMDAwMTIwfQ.VInR0V5-tlMiyx-l9LHTof_G3y2N8ltcwULy2OqiiVY");
    expect(mintTicket(SECRET, register).length).toBeLessThanOrEqual(4096);
  });
  it("matches the golden connect signature", () => {
    const connect = ticketClaims("connect", SLOT, "shellx-relay", 1_760_000_000_000);
    expect(connect.role).toBe("client");
    expect(mintTicket(SECRET, connect).split(".")[2]).toBe("bC7VtVqsFdcI6ldQ9BhFFH5OL_e6hFJTzVCQGbZLXnY");
  });
});
