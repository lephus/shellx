// Metadata-only structured logging (spec §10.5): time, device_id, error codes, frame sizes.
// NEVER pass payloads, tokens, passwords, e-mail or IP addresses to this function.
export type LogValue = string | number | boolean | null;

export function logMeta(event: string, fields: Readonly<Record<string, LogValue>> = {}): void {
  console.log(JSON.stringify({ ts: Date.now(), event, ...fields }));
}

/**
 * A loggable kind for an unknown error: an upper-case code such as `SQLITE_BUSY` when it has one,
 * else the error's class name. Never the message, which may quote SQL or user input.
 */
export function errorKind(err: unknown): string {
  if (typeof err === "object" && err !== null) {
    const code = (err as { code?: unknown }).code;
    if (typeof code === "string" && /^[A-Z][A-Z0-9_]*$/.test(code)) return code;
    const name = (err as { name?: unknown }).name;
    if (typeof name === "string" && /^[A-Za-z][A-Za-z0-9_]*$/.test(name)) return name;
  }
  return "unknown";
}
