import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { createApp, type AppDeps } from "../src/app";
import type { RateLimiter, RateLimiters } from "../src/auth/rate-limit";

export const BASE = "http://relay.test";

export const allowAll: RateLimiter = { limit: async () => true };
export const unlimited: RateLimiters = { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll };

/** Fake limiter: allows `max` calls per key, then refuses; records every key it saw. */
export class CountingLimiter implements RateLimiter {
  readonly calls: string[] = [];
  private readonly counts = new Map<string, number>();
  constructor(private readonly max: number) {}
  async limit(key: string): Promise<boolean> {
    this.calls.push(key);
    const next = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, next);
    return next <= this.max;
  }
}

export type TestApp = ReturnType<typeof createApp>;

export function makeApp(deps: AppDeps = {}): TestApp {
  return createApp({ limiters: () => unlimited, ...deps });
}

export interface CallOptions {
  body?: unknown;
  token?: string;
  ip?: string;
  headers?: Record<string, string>;
  /** Overrides individual bindings/vars for this request only. */
  bindings?: Partial<typeof env>;
}

export async function call(app: TestApp, method: string, path: string, options: CallOptions = {}): Promise<Response> {
  const headers = new Headers(options.headers);
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  if (options.token !== undefined) headers.set("Authorization", `Bearer ${options.token}`);
  headers.set("CF-Connecting-IP", options.ip ?? "203.0.113.7");
  const request = new Request(`${BASE}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : typeof options.body === "string" ? options.body : JSON.stringify(options.body),
  });
  const ctx = createExecutionContext();
  const response = await app.fetch(request, { ...env, ...options.bindings }, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
