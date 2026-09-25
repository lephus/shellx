export const TOKEN_BYTES = 32;
export const TOKEN_IDLE_TTL_MS = 90 * 24 * 60 * 60 * 1000;
export const TOKEN_TOUCH_INTERVAL_MS = 60 * 60 * 1000;

const BASE64URL_RE = /^[A-Za-z0-9_-]*$/;
const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** Strict unpadded base64url; null on any invalid input. */
export function base64UrlDecode(input: string): Uint8Array | null {
  if (!BASE64URL_RE.test(input) || input.length % 4 === 1) return null;
  const padded = input.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (input.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
}

/** 32 random bytes, base64url without padding (43 characters). */
export function generateToken(): string {
  return base64UrlEncode(crypto.getRandomValues(new Uint8Array(TOKEN_BYTES)));
}

/** SHA-256 of the token string; this is the only form stored in D1. */
export async function hashToken(token: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
}

export function parseBearer(header: string | null | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([A-Za-z0-9_-]+)$/.exec(header.trim());
  if (!match || !TOKEN_RE.test(match[1]!)) return null;
  return match[1]!;
}
