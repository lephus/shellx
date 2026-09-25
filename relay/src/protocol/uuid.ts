export const NIL_UUID = "00000000-0000-0000-0000-000000000000";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Returns the canonical lowercase 8-4-4-4-12 form, or null if `value` is not a UUID string. */
export function parseUuid(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const lower = value.toLowerCase();
  return UUID_RE.test(lower) ? lower : null;
}

/**
 * Like parseUuid, but only accepts version 7 (RFC 9562: 48-bit unix-ms timestamp first), the form
 * of every pairing id. Canonical v7 strings of equal length sort by time when compared as strings.
 */
export function parseUuidV7(value: unknown): string | null {
  const uuid = parseUuid(value);
  return uuid !== null && uuid[14] === "7" ? uuid : null;
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
