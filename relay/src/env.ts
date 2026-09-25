export interface Env {
  DB: D1Database;
  LOGIN_IP_LIMITER: RateLimit;
  LOGIN_EMAIL_LIMITER: RateLimit;
  REGISTER_IP_LIMITER: RateLimit;
  /** "false" disables every rate limit (local dev / E2E only); any other value keeps them on. */
  RATE_LIMITS_ENABLED: string;
  MIN_AGENT: string;
  MIN_MOBILE: string;
  LATEST_AGENT_VERSION: string;
  MAC_URL: string;
  WIN_URL: string;
}
