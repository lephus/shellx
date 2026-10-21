import { describe, expect, it, vi } from "vitest";
import { formatResult, runRelay2Smoke } from "../scripts/relay2-smoke.js";

const run = (base: string, fetchFn: typeof fetch) =>
  runRelay2Smoke({ base, email: "a@b.c", password: "pw", fetch: fetchFn, registerTimeoutMs: 50 });

describe("relay2 smoke refuses to send a password over an insecure URL", () => {
  it.each([
    "http://relay.shellx.pro",
    "http://127.0.0.1.evil.example",
    "http://localhost.evil.example",
    "http://user@evil.example:80",
    "ws://127.0.0.1:1234",
    "ftp://127.0.0.1",
    "not a url",
  ])("%s: FAIL at base, fetch never called", async (base) => {
    const fetchFn = vi.fn();
    const result = await run(base, fetchFn as unknown as typeof fetch);
    expect(result).toMatchObject({ ok: false, step: "base" });
    expect(fetchFn).not.toHaveBeenCalled();
    expect(formatResult(result)).toBe("relay2 smoke: FAIL at base (insecure URL)");
  });

  it.each(["https://relay.shellx.pro", "http://127.0.0.1:1234", "http://127.0.0.1", "http://localhost:8080"])(
    "%s is accepted (the first request goes out)", async (base) => {
      const fetchFn = vi.fn().mockRejectedValue(new Error("offline"));
      const result = await run(base, fetchFn as unknown as typeof fetch);
      expect(fetchFn).toHaveBeenCalled();
      expect(result).toMatchObject({ ok: false, step: "login" });
    },
  );
});
