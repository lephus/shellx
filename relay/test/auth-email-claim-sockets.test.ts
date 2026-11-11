import { expect, it } from "vitest";
import { FakeEmailGateway } from "./fake-email.js";
import { connect, emailSession, googleSession, loginDevice, makeApp, registerAccount, TEST_CONFIG } from "./helpers.js";

// Not from the plan's test list: the plan's Ruling 12 removes "every session" of an account a code claims,
// and its tests check the tokens. A device that is connected to /v1/ws keeps its socket after its token is
// deleted, so the claim also has to close the sockets (as a password change does).

async function settle<T>(promise: Promise<T>, ms = 1500): Promise<T | "open"> {
  return Promise.race([promise, new Promise<"open">((resolve) => setTimeout(() => resolve("open"), ms))]);
}

it("closes the live sockets (4002) of the sessions it removed when a code claims an account; a link into a Google account closes none", async () => {
  const mail = new FakeEmailGateway();
  const app = makeApp({ email: mail, config: { ...TEST_CONFIG, passwordLogin: false } });
  const account = await registerAccount(app);
  const phone = await loginDevice(makeApp(), account, "mobile");
  const bystander = await registerAccount(app);
  const agentSocket = await connect(app, account.agent.token);
  const phoneSocket = await connect(app, phone.token);
  const bystanderSocket = await connect(app, bystander.agent.token);

  const claimed = await emailSession(app, mail, { email: account.email });
  expect(claimed.userId).toBe(account.agent.userId);
  expect(await settle(agentSocket.closed)).toEqual({ code: 4002, reason: "revoked" });
  expect(await settle(phoneSocket.closed)).toEqual({ code: 4002, reason: "revoked" });
  expect(await settle(bystanderSocket.closed, 300)).toBe("open");

  const google = await googleSession(app, { email: "ann.lee@example.com", kind: "mobile" });
  const googleSocket = await connect(app, google.token);
  const linked = await emailSession(app, mail, { email: "ann.lee@example.com" });
  expect(linked.userId).toBe(google.userId);
  expect(await settle(googleSocket.closed, 300)).toBe("open");
});
