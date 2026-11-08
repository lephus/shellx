import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { revokeAppleTokens } from "../auth/apple-rest.js";
import { requireAuth } from "../auth/session.js";
import { Errors } from "../http/errors.js";
import { logMeta } from "../log.js";
import { parseUuid } from "../protocol/uuid.js";
import { unixSeconds } from "../v2/encoding.js";

/** The sign-in methods of the caller's account (S1 §8), mounted at /v1/account/identities. */
export const identityRoutes = new Hono<AppEnv>();

interface IdentityListRow {
  id: string;
  provider: string;
  email: string;
  is_private_email: number;
  linked_via_device_name: string | null;
  created_at: number;
}

/** GET / — the Google sign-in and each Apple ID, with the iPhone that linked it. */
identityRoutes.get("/", requireAuth, (c) => {
  const rows = c.get("db").all<IdentityListRow>(
    `SELECT i.id, i.provider, i.email, i.is_private_email, d.name AS linked_via_device_name, i.created_at
       FROM identities i LEFT JOIN devices d ON d.id = i.linked_via_device_id
      WHERE i.user_id = ? ORDER BY i.created_at, i.rowid`,
    c.get("auth").userId,
  );
  return c.json({
    identities: rows.map((r) => ({
      identity_id: r.id,
      provider: r.provider,
      email: r.email,
      is_private_email: r.is_private_email === 1,
      linked_via_device_name: r.linked_via_device_name,
      created_at_unix: unixSeconds(r.created_at),
    })),
  });
});

/** DELETE /:id — removes one sign-in; its tokens go with it. The Google sign-in cannot be removed. */
identityRoutes.delete("/:id", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const id = parseUuid(c.req.param("id"));
  const row =
    id === null
      ? undefined
      : db.get<{ id: string; provider: string; apple_client_id: string | null; apple_refresh_token: string | null }>(
          "SELECT id, provider, apple_client_id, apple_refresh_token FROM identities WHERE id = ? AND user_id = ?", id, auth.userId,
        );
  if (row === undefined) throw Errors.identityNotFound();
  if (row.provider !== "apple") {
    const primaries = db.get<{ n: number }>("SELECT COUNT(*) AS n FROM identities WHERE user_id = ? AND provider != 'apple'", auth.userId)!.n;
    if (primaries <= 1) throw Errors.lastGoogleIdentity();
  }
  db.run("DELETE FROM identities WHERE id = ?", row.id);
  if (row.provider === "apple") await revokeAppleTokens(c.get("appleTokens"), [row]);
  logMeta("identity_removed", { device_id: auth.deviceId, identity_id: row.id });
  return c.body(null, 204);
});
