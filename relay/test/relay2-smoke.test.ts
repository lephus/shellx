import { describe, expect, it, vi } from "vitest";
import { formatResult, runRelay2Smoke } from "../scripts/relay2-smoke.js";

const run = (base: string, fetchFn: typeof fetch) =>
  runRelay2Smoke({ base, token: "t".repeat(43), fetch: fetchFn, registerTimeoutMs: 50 });

describe("relay2 smoke refuses to send the token over an insecure URL", () => {
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
      expect(result).toMatchObject({ ok: false, step: "machine" });
    },
  );
});

it("sends the minted token as the bearer of its first request and never logs in", async () => {
  const fetchFn = vi.fn().mockRejectedValue(new Error("offline"));
  await run("https://relay.shellx.pro", fetchFn as unknown as typeof fetch);
  const [url, init] = fetchFn.mock.calls[0]! as [URL, RequestInit];
  expect(url.pathname).toBe("/v2/machines");
  expect((init.headers as Record<string, string>).Authorization).toBe(`Bearer ${"t".repeat(43)}`);
  expect(fetchFn.mock.calls.some(([u]) => String(u).includes("/v1/auth/login"))).toBe(false);
});
