// Metadata-only structured logging (spec §10.5): time, device_id, error codes, frame sizes.
// NEVER pass payloads, tokens, passwords or e-mail addresses to this function.
export type LogValue = string | number | boolean | null;

export function logMeta(event: string, fields: Readonly<Record<string, LogValue>> = {}): void {
  console.log(JSON.stringify({ ts: Date.now(), event, ...fields }));
}
