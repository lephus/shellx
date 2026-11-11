import { afterEach, expect, it, vi } from "vitest";
import { FakeEmailGateway } from "./fake-email.js";
import { call, makeApp } from "./helpers.js";

// Not from the plan's test list: the plan logs a gateway's `error` as it comes. `ResendClient` only ever
// answers an error kind (`errorKind`), but the route does not rely on that: a gateway that answered a
// message, an address or a token-shaped string must not get it into a log line.

afterEach(() => vi.restoreAllMocks());

it("logs the error of a failed send only when it looks like an error kind: never a message, an address or a 43-character string", async () => {
  const lines: string[] = [];
  for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
  const mail = new FakeEmailGateway();
  const app = makeApp({ email: mail });
  for (const error of ["secret.mailbox@example.com could not be reached", "n".repeat(43), "ECONNRESET"]) {
    mail.result = { ok: false, error };
    expect((await call(app, "POST", "/v1/auth/email/code", { body: { email: "secret.mailbox@example.com" } })).status).toBe(502);
  }
  const failed = lines.filter((line) => line.includes('"event":"email_send_failed"')).map((line) => line.replace(/"ts":[0-9]+,?/, ""));
  expect(failed).toEqual([
    '{"event":"email_send_failed","error":"unknown"}', '{"event":"email_send_failed","error":"unknown"}', '{"event":"email_send_failed","error":"ECONNRESET"}',
  ]);
  const output = lines.join("\n");
  expect(output).not.toContain("secret.mailbox");
  expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
});
