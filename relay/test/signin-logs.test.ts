import { afterEach, expect, it, vi } from "vitest";
import { FakeEmailGateway } from "./fake-email.js";
import { FakeAppleTokens } from "./fake-idp.js";
import { call, deviceBody, googleIdToken, googleSession, linkAppleIdByQr, makeApp, registerAccount, registerMachine, requestEmailCode } from "./helpers.js";

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

it("never logs the address, the code or the challenge id of an email sign-in, a wrong guess or a deletion by code", async () => {
  const lines: string[] = [];
  const capture = (...args: unknown[]) => void lines.push(args.map(String).join(" "));
  for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation(capture);
  const mail = new FakeEmailGateway();
  const app = makeApp({ email: mail, emailCode: () => "731946" });
  const verify = (challengeId: string, code: string) =>
    call(app, "POST", "/v1/auth/email/verify", { body: { challenge_id: challengeId, code, device: deviceBody("mobile") } });
  const first = await requestEmailCode(app, mail, "secret.mailbox@example.com");
  await verify(first.challengeId, "731947");
  const session = await (await verify(first.challengeId, "731946")).json<{ token: string }>();
  const second = await requestEmailCode(app, mail, "secret.mailbox@example.com");
  await call(app, "DELETE", "/v1/account", { token: session.token, body: { challenge_id: second.challengeId, code: "731946" } });
  const output = lines.map((line) => line.replace(/"ts":[0-9]+,?/, "")).join("\n");
  for (const event of [
    '"event":"email_code_sent"', '"event":"sign_in_refused","provider":"email","reason":"invalid_code"', '"provider":"email","via":"new_account"', '"event":"account_deleted"',
  ]) expect(output).toContain(event);
  for (const secret of ["secret.mailbox", "731946", "731947", first.challengeId, second.challengeId, session.token]) expect(output).not.toContain(secret);
  expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
});
