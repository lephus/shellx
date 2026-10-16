export const NIL_UUID = "00000000-0000-0000-0000-000000000000";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Returns the canonical lowercase 8-4-4-4-12 form, or null if `value` is not a UUID string. */
export function parseUuid(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const lower = value.toLowerCase();
  return UUID_RE.test(lower) ? lower : null;
}

/**
 * A pairing id: a version-7 UUID (RFC 9562: 48-bit unix-ms timestamp first) that is ALREADY in
 * canonical lower-case form, returned unchanged; null otherwise. Unlike parseUuid there is no case
 * folding: pairing ids are matched byte-for-byte on both ends, so an agent that stored another
 * spelling would never match its own events. Canonical v7 strings sort by time as strings.
 */
export function parseUuidV7(value: unknown): string | null {
  return typeof value === "string" && UUID_RE.test(value) && value[14] === "7" ? value : null;
}

/** The unix-millisecond timestamp in the first 48 bits of a (canonical) UUIDv7. */
export function uuidV7Millis(uuid: string): number {
  return Number.parseInt(uuid.slice(0, 8) + uuid.slice(9, 13), 16);
}

/** 16 bytes in textual order (the hex digits read left to right). Throws on malformed input. */
export function uuidToBytes(uuid: string): Uint8Array {
  const canonical = parseUuid(uuid);
  if (canonical === null) throw new TypeError("invalid UUID");
  const hex = canonical.replaceAll("-", "");
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function uuidFromBytes(bytes: Uint8Array): string {
  if (bytes.length !== 16) throw new TypeError("UUID must be 16 bytes");
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
