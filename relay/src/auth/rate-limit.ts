import type { Env } from "../env";

/** Returns true when the call is allowed, false when the key is over its limit. */
export interface RateLimiter {
  limit(key: string): Promise<boolean>;
}

export interface RateLimiters {
  loginIp: RateLimiter;
  loginEmail: RateLimiter;
  registerIp: RateLimiter;
}

export function bindingLimiter(binding: RateLimit): RateLimiter {
  return {
    async limit(key) {
      const { success } = await binding.limit({ key });
      return success;
    },
  };
}

const allowAll: RateLimiter = { limit: async () => true };

/**
 * Production wiring: Workers rate limiting bindings (60 s period, limits set in wrangler.jsonc).
 * Only the exact string "false" in RATE_LIMITS_ENABLED turns them off (local dev for the E2E suite).
 */
export function limitersFromEnv(env: Env): RateLimiters {
  if (env.RATE_LIMITS_ENABLED === "false") {
    return { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll };
  }
  return {
    loginIp: bindingLimiter(env.LOGIN_IP_LIMITER),
    loginEmail: bindingLimiter(env.LOGIN_EMAIL_LIMITER),
    registerIp: bindingLimiter(env.REGISTER_IP_LIMITER),
  };
}
