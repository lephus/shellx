export const PASSWORD_MIN_CHARS = 8;
export const PASSWORD_MAX_CHARS = 128;

/** 8–128 characters, counted as Unicode code points after NFC normalisation. */
export function isAcceptablePassword(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const length = [...value.normalize("NFC")].length;
  return length >= PASSWORD_MIN_CHARS && length <= PASSWORD_MAX_CHARS;
}
