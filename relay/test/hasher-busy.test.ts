// Its own file on purpose: the login route caches its dummy hash per process, and this file must
// be the first to ask for it (vitest runs every test file in a fresh child process).
import { describe, expect, it } from "vitest";
import { createPasswordHasher } from "../src/auth/password.js";
import { call, deviceBody, errorCode, gatedBackend, makeApp, PASSWORD, randomEmail, seedUser, waitFor } from "./helpers.js";

describe("argon2 queue full (M8)", () => {
  it("answers 429 rate_limited to login while no hash can start or wait, then recovers", async () => {
    const gated = gatedBackend();
    // One hash at a time and no waiting room, so a second caller finds the queue full at once.
    const app = makeApp({ passwords: createPasswordHasher(gated.backend, 1, 0) });
    const running = () => waitFor(async () => (gated.started() === 1 ? true : null));
    const login = (email: string) => call(app, "POST", "/v1/auth/login", { body: { email, password: PASSWORD, device: deviceBody("mobile") } });
    const alice = randomEmail();
    await seedUser(alice, PASSWORD); // registration is closed; the gated backend accepts any stored hash
    const first = login(alice);
    await running();
    const refused = await login(randomEmail()); // the dummy hash for an unknown email cannot start
    expect([refused.status, await errorCode(refused)]).toEqual([429, "rate_limited"]);
    const known = await login(alice); // a real account's verify cannot start either
    expect([known.status, await errorCode(known)]).toEqual([429, "rate_limited"]);
    gated.releaseOne();
    expect((await first).status).toBe(200);
    const later = login(randomEmail()); // recovered, and the refused dummy hash was not cached
    await running();
    gated.releaseOne();
    await running();
    gated.releaseOne();
    const answer = await later;
    expect([answer.status, await errorCode(answer)]).toEqual([401, "invalid_credentials"]);
  });
});
