// Minimal CBOR (RFC 8949) encoder for the only structure the relay emits:
// a map (major type 5) whose keys and values are all text strings (major type 3).
// Keys are written in insertion order; definite lengths only; no tags.

const utf8 = new TextEncoder();

function header(majorType: number, length: number): number[] {
  const mt = majorType << 5;
  if (length < 24) return [mt | length];
  if (length < 0x100) return [mt | 24, length];
  if (length < 0x10000) return [mt | 25, length >> 8, length & 0xff];
  return [mt | 26, (length >>> 24) & 0xff, (length >>> 16) & 0xff, (length >>> 8) & 0xff, length & 0xff];
}

function textString(value: string): number[] {
  const bytes = utf8.encode(value);
  return [...header(3, bytes.length), ...bytes];
}

export function encodeTextMap(map: Readonly<Record<string, string>>): Uint8Array {
  const entries = Object.entries(map);
  const out: number[] = header(5, entries.length);
  for (const [key, value] of entries) out.push(...textString(key), ...textString(value));
  return Uint8Array.from(out);
}
