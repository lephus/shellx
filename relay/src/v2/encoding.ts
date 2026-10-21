import { createHash, randomBytes } from "node:crypto";

const B64_RE = /^[A-Za-z0-9+/_-]*={0,2}$/;

/** Strict base64: standard or URL alphabet (never mixed), optional padding, byte length in range. */
export function decodeB64(value: unknown, minBytes: number, maxBytes: number): Uint8Array | null {
  if (typeof value !== "string" || !B64_RE.test(value)) return null;
  const hasStd = /[+/]/.test(value);
  const hasUrl = /[-_]/.test(value);
  if (hasStd && hasUrl) return null;
  const bytes = new Uint8Array(Buffer.from(value, hasUrl ? "base64url" : "base64"));
  return bytes.length >= minBytes && bytes.length <= maxBytes ? bytes : null;
}

/** First 8 bytes of SHA-256 of the noise key, lower-case hex. */
export function fingerprint(noiseKey: Uint8Array): string {
  return createHash("sha256").update(noiseKey).digest().subarray(0, 8).toString("hex");
}

/** A fresh relay slot: 16 random bytes, base64url without padding. */
export function newSlot(): string {
  return randomBytes(16).toString("base64url");
}

export function unixSeconds(ms: number): number {
  return Math.floor(ms / 1000);
}
