import type { ContentfulStatusCode } from "hono/utils/http-status";

/** Every API error is rendered as `{"error": {"code", "message"}}` (overview §4.3). */
export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const Errors = {
  badRequest: () => new ApiError(400, "bad_request", "Malformed request body"),
  invalidEmail: () => new ApiError(400, "invalid_email", "Email address is not valid"),
  disposableEmail: () => new ApiError(400, "disposable_email", "Disposable email addresses are not allowed"),
  weakPassword: () => new ApiError(400, "weak_password", "Password must be 8-128 characters"),
  invalidDevice: () => new ApiError(400, "invalid_device", "Device information is not valid"),
  unauthorized: () => new ApiError(401, "unauthorized", "Missing, invalid or expired token"),
  invalidCredentials: () => new ApiError(401, "invalid_credentials", "Email or password is incorrect"),
  agentOnly: () => new ApiError(403, "agent_only", "Only a desktop agent may do this"),
  mobileOnly: () => new ApiError(403, "mobile_only", "Only a phone may do this"),
  desktopOnly: () => new ApiError(403, "desktop_only", "Only a desktop app may do this"),
  invalidMachine: () => new ApiError(400, "invalid_machine", "Machine information is not valid"),
  machineNotFound: () => new ApiError(404, "machine_not_found", "Machine not found"),
  pairingNotFound: () => new ApiError(404, "pairing_not_found", "Pairing not found"),
  notGranted: () => new ApiError(403, "not_granted", "This device has no access to that machine"),
  pairingNotPending: () => new ApiError(409, "pairing_not_pending", "This pairing is not pending"),
  pairingExpired: () => new ApiError(410, "pairing_expired", "This pairing has expired"),
  plaintextInvite: () => new ApiError(400, "plaintext_invite", "The invite must be encrypted"),
  relayV2Unavailable: () => new ApiError(503, "relay_v2_unavailable", "Relay v2 is not configured on this relay"),
  forbidden: () => new ApiError(403, "forbidden", "Not allowed"),
  deviceNotFound: () => new ApiError(404, "device_not_found", "Device not found"),
  notFound: () => new ApiError(404, "not_found", "Not found"),
  shareNotFound: () => new ApiError(404, "share_not_found", "Share not found"),
  shareRevoked: () => new ApiError(410, "share_revoked", "This share was revoked"),
  shareExpired: () => new ApiError(410, "share_expired", "This share has expired"),
  shareUsed: () => new ApiError(410, "share_used", "This share is bound to another viewer"),
  shareLimit: () => new ApiError(409, "share_limit", "Too many active shares on this device"),
  hostOffline: () => new ApiError(503, "host_offline", "The host is not online"),
  emailTaken: () => new ApiError(409, "email_taken", "Email is already registered"),
  pairingRemoved: () => new ApiError(410, "pairing_removed", "This pairing has already been removed"),
  payloadTooLarge: () => new ApiError(413, "payload_too_large", "Request body is too large"),
  upgradeRequired: () => new ApiError(426, "upgrade_required", "Expected a WebSocket upgrade"),
  rateLimited: () => new ApiError(429, "rate_limited", "Too many requests, try again later"),
  pushUnavailable: () => new ApiError(503, "push_unavailable", "Push notifications are not configured on this relay"),
} as const;

export function errorBody(code: string, message: string): { error: { code: string; message: string } } {
  return { error: { code, message } };
}

export async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw Errors.badRequest();
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) throw Errors.badRequest();
  return body as Record<string, unknown>;
}
