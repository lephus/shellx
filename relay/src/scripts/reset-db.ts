import type { Db } from "../db/db.js";

/** What `resetPassword` did: `reset` (exactly one account updated) or `no_account` (nothing changed). */
export type ResetOutcome = "reset" | "no_account";

/**
 * Sets the password hash of the account `email` (already normalised) in one transaction, and with
 * `revokeTokens` deletes every device token of that account. Pairings are never touched. Sockets
 * already open stay up until they reconnect (this runs outside the relay process).
 */
export function resetPassword(db: Db, email: string, phc: string, now: number, revokeTokens: boolean): ResetOutcome {
  if (!Number.isSafeInteger(now)) throw new TypeError("now must be an integer (unix ms)");
  return db.transaction(() => {
    const user = db.get<{ id: string }>("SELECT id FROM users WHERE email = ?", email);
    if (user === undefined) return "no_account";
    db.run("UPDATE users SET password_hash = ?, password_changed_at = ? WHERE id = ?", phc, now, user.id);
    if (revokeTokens) {
      db.run("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ?)", user.id);
    }
    return "reset";
  });
}
