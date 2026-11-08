import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requestIp } from "../auth/client-ip.js";
import { issueNonce, NONCE_TTL_MS } from "../auth/nonces.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors } from "../http/errors.js";

/** Sign-in routes mounted at /v1/auth (S1 §6): nonce, Google, Apple. */
export const signInRoutes = new Hono<AppEnv>();

/** POST /v1/auth/nonce — a single-use nonce for the next ID token; the body is not read. */
signInRoutes.post("/nonce", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").nonceIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const nonce = await issueNonce(c.get("db"), c.get("now")());
  return c.json({ nonce, expires_in: NONCE_TTL_MS / 1000 }, 201);
});
