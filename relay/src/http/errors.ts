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
  forbidden: () => new ApiError(403, "forbidden", "Not allowed"),
  deviceNotFound: () => new ApiError(404, "device_not_found", "Device not found"),
  notFound: () => new ApiError(404, "not_found", "Not found"),
  emailTaken: () => new ApiError(409, "email_taken", "Email is already registered"),
  pairingRemoved: () => new ApiError(410, "pairing_removed", "This pairing has already been removed"),
  payloadTooLarge: () => new ApiError(413, "payload_too_large", "Request body is too large"),
  upgradeRequired: () => new ApiError(426, "upgrade_required", "Expected a WebSocket upgrade"),
  rateLimited: () => new ApiError(429, "rate_limited", "Too many requests, try again later"),
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
