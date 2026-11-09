import { afterEach, expect, it, vi } from "vitest";
import { FakeAppleTokens } from "./fake-idp.js";
import { call, googleIdToken, googleSession, linkAppleIdByQr, makeApp, registerAccount, registerMachine } from "./helpers.js";

afterEach(() => vi.restoreAllMocks());

it("never logs emails, subs, codes, refresh tokens, nonces, ID tokens, link tokens or session tokens", async () => {
  const lines: string[] = [];
  const capture = (...args: unknown[]) => void lines.push(args.map(String).join(" "));
  for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation(capture);
  const app = makeApp({ appleTokens: new FakeAppleTokens() });
  const desk = await googleSession(app, { kind: "desktop", sub: "g-secret-sub", email: "secret.owner@example.com" });
  const machine = await registerMachine(app, desk.token);
  const apple = await linkAppleIdByQr(app, desk.token, machine.machine_id, { sub: "a-secret-sub", email: "secret.hidden@privaterelay.appleid.com", authorizationCode: "code-secret-1" });
  const account = await registerAccount(app);
  await call(app, "POST", "/v1/auth/google/link", { token: account.agent.token, body: await googleIdToken(app, { sub: "g-secret-link", email: "secret.linked@example.com" }) });
  await call(app, "DELETE", "/v1/account", { token: desk.token, body: await googleIdToken(app, { sub: "g-secret-sub" }) });
  const output = lines.join("\n");
  expect(output).toContain('"event":"sign_in"');
  expect(output).toContain('"event":"apple_link_redeemed"');
  for (const secret of ["secret.owner", "secret.hidden", "secret.linked", "g-secret-sub", "a-secret-sub", "g-secret-link", "code-secret-1", "apple-refresh-token-1", apple.session.token]) {
    expect(output).not.toContain(secret);
  }
  expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
});
