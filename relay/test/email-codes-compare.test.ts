import { expect, it, vi } from "vitest";

const compared = vi.hoisted(() => ({ calls: [] as [number, number][] }));
vi.mock("node:crypto", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:crypto")>();
  return {
    ...actual,
    timingSafeEqual: (a: NodeJS.ArrayBufferView, b: NodeJS.ArrayBufferView) => {
      compared.calls.push([a.byteLength, b.byteLength]);
      return actual.timingSafeEqual(a, b);
    },
  };
});

import { issueEmailCode, redeemEmailCode } from "../src/auth/email-codes.js";
import { db } from "./helpers.js";

it("compares code hashes with timingSafeEqual: once per guess at a live challenge, right or wrong, on two 32-byte digests", async () => {
  const T0 = 1_800_000_000_000;
  const { challengeId } = (await issueEmailCode(db(), "ann.lee@example.com", "048213", T0))!;
  await redeemEmailCode(db(), "n".repeat(43), "048213", T0); // unknown challenge: nothing to compare
  expect(compared.calls).toEqual([]);
  expect(await redeemEmailCode(db(), challengeId, "048214", T0)).toEqual({ ok: false, reason: "invalid_code" }); // last digit off
  expect(await redeemEmailCode(db(), challengeId, "948213", T0)).toEqual({ ok: false, reason: "invalid_code" }); // first digit off
  expect(await redeemEmailCode(db(), challengeId, "048213", T0)).toEqual({ ok: true, email: "ann.lee@example.com" });
  expect(compared.calls).toEqual([[32, 32], [32, 32], [32, 32]]);
});
