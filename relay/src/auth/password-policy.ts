export const PASSWORD_MIN_CHARS = 8;
export const PASSWORD_MAX_CHARS = 128;

/** Unicode code points after NFC normalisation: how every password length here is counted. */
function passwordLength(value: string): number {
  return [...value.normalize("NFC")].length;
}

/** 8–128 characters, counted as Unicode code points after NFC normalisation. */
export function isAcceptablePassword(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const length = passwordLength(value);
  return length >= PASSWORD_MIN_CHARS && length <= PASSWORD_MAX_CHARS;
}

/**
 * True for a password no account can have (more than 128 code points after NFC). Login and
 * account deletion refuse it as invalid_credentials before argon2 ever sees it: the argon2 WASM
 * memory the password is copied into grows and never shrinks (final review I2).
 */
export function isOverlongPassword(value: string): boolean {
  return passwordLength(value) > PASSWORD_MAX_CHARS;
}
