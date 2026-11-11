import { expect, it } from "vitest";
import { Errors } from "../src/http/errors.js";

it.each([
  ["switchFromSignedInDevice", 409, "switch_from_signed_in_device"], ["emailInUse", 409, "email_in_use"],
  ["identityInUse", 409, "identity_in_use"], ["lastGoogleIdentity", 409, "last_google_identity"],
  ["registrationClosed", 410, "registration_closed"], ["passwordSignInRemoved", 410, "password_sign_in_removed"],
  ["reauthRequired", 401, "reauth_required"], ["identityNotFound", 404, "identity_not_found"],
  ["invalidCode", 401, "invalid_code"], ["codeExpired", 410, "code_expired"],
  ["emailSignInDisabled", 503, "email_sign_in_disabled"], ["emailSendFailed", 502, "email_send_failed"],
] as const)("Errors.%s() is %i %s (contracts §2)", (name, status, code) => {
  const e = Errors[name]();
  expect([e.status, e.code]).toEqual([status, code]);
});
