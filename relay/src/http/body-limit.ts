import { bodyLimit } from "hono/body-limit";
import { Errors } from "./errors.js";

/** Largest JSON request body any route accepts; real bodies are well under 1 KiB. */
export const MAX_JSON_BODY_BYTES = 16 * 1024;

/**
 * Refuses a request body over MAX_JSON_BODY_BYTES with 413 `payload_too_large` (the usual JSON
 * error shape) before a handler reads it (final review I2). Checks Content-Length when present and
 * otherwise counts a streamed body as it arrives. Placed after `requireAuth` on authenticated
 * routes, so a missing/invalid token still gets 401 first.
 */
export const jsonBodyLimit = bodyLimit({
  maxSize: MAX_JSON_BODY_BYTES,
  onError: () => {
    throw Errors.payloadTooLarge();
  },
});
