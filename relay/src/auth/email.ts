import disposableDomains from "./disposable-domains.json" with { type: "json" };

const DISPOSABLE = new Set<string>(disposableDomains);

// Pragmatic subset of RFC 5322: dot-atom local part, LDH domain labels, alphabetic TLD.
// Applied to the already-normalised (trimmed, lowercased) address.
const EMAIL_RE =
  /^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

export function isValidEmail(email: string): boolean {
  if (email.length > 254) return false;
  const at = email.lastIndexOf("@");
  if (at < 1 || at > 64) return false;
  return EMAIL_RE.test(email);
}

/** True if `domain` or any parent domain (x.yopmail.com → yopmail.com → com) is on the blocklist. */
export function isDisposableDomain(domain: string): boolean {
  const labels = domain.toLowerCase().split(".");
  for (let i = 0; i < labels.length; i++) {
    if (DISPOSABLE.has(labels.slice(i).join("."))) return true;
  }
  return false;
}

export type EmailCheck =
  | { ok: true; email: string }
  | { ok: false; code: "invalid_email" | "disposable_email" };

export function checkEmail(raw: unknown): EmailCheck {
  if (typeof raw !== "string") return { ok: false, code: "invalid_email" };
  const email = normalizeEmail(raw);
  if (!isValidEmail(email)) return { ok: false, code: "invalid_email" };
  if (isDisposableDomain(email.slice(email.lastIndexOf("@") + 1))) return { ok: false, code: "disposable_email" };
  return { ok: true, email };
}
