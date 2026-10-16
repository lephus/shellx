// Its own file on purpose: the login route caches its dummy hash per process, and this file must
// be the first to ask for it (vitest runs every test file in a fresh child process).
import { describe, expect, it } from "vitest";
import { createPasswordHasher } from "../src/auth/password.js";
import { call, deviceBody, errorCode, gatedBackend, makeApp, PASSWORD, randomEmail, waitFor } from "./helpers.js";

describe("argon2 queue full (M8)", () => {
  it("answers 429 rate_limited to register and login while no hash can start or wait, then recovers", async () => {
    const gated = gatedBackend();
    // One hash at a time and no waiting room, so a second caller finds the queue full at once.
    const app = makeApp({ passwords: createPasswordHasher(gated.backend, 1, 0) });
    const running = () => waitFor(async () => (gated.started() === 1 ? true : null));
    const register = (email: string) =>
      call(app, "POST", "/v1/auth/register", { body: { email, password: PASSWORD, device: deviceBody("agent") } });
    const login = (email: string) =>
      call(app, "POST", "/v1/auth/login", { body: { email, password: PASSWORD, device: deviceBody("mobile") } });

    const alice = randomEmail();
    const first = register(alice);
    await running();

    const refused = await register(randomEmail());
    expect(refused.status).toBe(429);
    expect(await errorCode(refused)).toBe("rate_limited");
    const unknown = await login(randomEmail()); // the dummy hash for an unknown email cannot start either
    expect(unknown.status).toBe(429);
    expect(await errorCode(unknown)).toBe("rate_limited");

    gated.releaseOne();
    expect((await first).status).toBe(201);

    const occupying = register(randomEmail());
    await running();
    const known = await login(alice); // verify for a real account: busy, not "wrong password"
    expect(known.status).toBe(429);
    expect(await errorCode(known)).toBe("rate_limited");
    gated.releaseOne();
    expect((await occupying).status).toBe(201);

    // Recovered, and the refused dummy hash was not cached: an unknown email is 401 again.
    const later = login(randomEmail());
    await running(); // the dummy hash
    gated.releaseOne();
    await running(); // the verify against it
    gated.releaseOne();
    const answer = await later;
    expect(answer.status).toBe(401);
    expect(await errorCode(answer)).toBe("invalid_credentials");
  });
});
