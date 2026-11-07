# ShellX Relay FCM for Android (3F) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `POST /v2/notifications` also reaches every granted Android phone, as an FCM data-only message, while the v1 FCM notification path stays exactly as it is.

**Architecture:** `FcmClient` (`relay/src/push/fcm.ts`) gains `sendData`, a data-only message with `android.priority`, `android.ttl` and `android.collapse_key`, behind a new `FcmDataGateway` interface; `send`, `PushMessage` and `PushGateway` keep today's behaviour. The app receives the same client a second time as `fcm` (beside `push` and `apns`). The v2 route selects Android recipients next to the APNs ones, sends both with `Promise.allSettled`, and deletes the tokens either service reports as gone.

**Tech Stack:** Node.js ≥ 22, TypeScript 5 (strict, ESM `.js` imports), Hono, better-sqlite3, vitest 4; FCM HTTP v1 over `fetch` + `node:crypto` (no new dependency).

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` §7.4 (S3, Vietnamese prose). Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` (this is plan 3F).

All commands run from the worktree root `/Users/lehuuphu/Documents/myProjects/shellx/.worktrees/android-3f-relay-fcm` unless a step says otherwise.

## Global Constraints

- v1 is untouched: do not edit `relay/src/routes/notifications.ts` or `relay/test/notifications.test.ts`. `FcmClient.send` keeps posting exactly `{message: {token, notification: {title, body}, data, android: {priority: "high"}, apns: {payload: {aps: {sound: "default"}}}}}` (spec: "Route v1 dùng chung client này … và phải giữ nguyên hành vi").
- Android messages are data-only: no `notification`, `apns` or `webpush` block. Every `data` value is a string. The keys come only from `kind`, `machine_id`, `request_id`, `agent`, `workspace_title` (a `resolved` carries the first three only), and a message never carries what the agent asks or a command ("không bao giờ mang nội dung câu hỏi hay lệnh của agent").
- `needs_you`: `android.priority` `high`, `android.ttl` `86400s` (24 h), `android.collapse_key` = `request_id`. `resolved`: `android.priority` `normal`, with the same TTL and collapse key (Spec note 2).
- Android recipients are the phones granted the Mac (`phone_grants`) with a live sign-in, device `platform = 'android'` and `push_tokens.apns_topic IS NULL`.
- An FCM `invalid_token` deletes that `push_tokens` row exactly as APNs does (`WHERE device_id = ? AND token = ?`). 503 `push_unavailable` only when neither APNs nor FCM is configured.
- One recipient's failure (an error answer, or a send that throws) never fails the others or the call: 202 `{sent}`.
- Logs go through `logMeta` with kinds and counts only: never the agent, the workspace title, the request id or a token.
- The rate limit is unchanged: `notifyAgent` (120 per hour), keyed by the Mac's device id, counted once per valid `needs_you` call and never for `resolved`.
- The Mac does not change: `POST /v2/notifications` keeps its body `{kind, request_id, agent?, workspace_title?}` and its validation.
- No new npm dependency. `npm run typecheck` (`strict`, `noUncheckedIndexedAccess`, tests included) must pass.
- Branch `feat/shellx-android-3f-relay-fcm` from `develop`. Land per contracts §1: merge into `develop`, push `develop`. Never `main`, never deploy. This branch ships in the same relay deploy as plan 1A; the deploy is the user's, in plan 1D.

## Review Focus

1. A phone that was off while the Mac raised and then handled a request must not show that alert when it comes back, because FCM keeps no order between messages. `resolved` therefore reuses `collapse_key` = `request_id` and the 24 h TTL. Test: Task 2 "tells Android phones a request was handled…".
2. An account with both an iPhone and an Android phone, where one service fails, throws or is not configured: the other phone still gets its push and `sent` counts only real deliveries; 503 only when both are off. Tests: Task 2 "never lets one phone's failed send…" and "answers 503 push_unavailable only when…".
3. A Mac with "Hide content" on (it sends `workspace_title: ""`), with no title at all, or with a Vietnamese/emoji title: the value reaches the phone unchanged, and empty stays empty. Test: Task 2 "passes the workspace title through…".
4. Phones that must not be reached: an iPhone's FCM-style token (device `ios`, no `apns_topic`, e.g. left by the deleted Flutter app), or an Android phone that is not granted this Mac, has no token, is idle past the sign-in lifetime, or belongs to another Mac or account. Test: Task 2 "skips Android phones…".
5. A `resolved` body that still carries `agent` / `workspace_title` (which are never validated for `resolved`): the phone gets only the three ids. Test: Task 2 "tells Android phones a request was handled…" (exact `data`).

---

### Task 0: Set up the worktree

**Files:** none (workspace only).

**Prerequisites:** none (contracts §1). Plan 1A also edits `relay/` and may land on `develop` before or after this plan; Task 4 Step 6 merges it in.

- [ ] **Step 1: Create the worktree** with superpowers:using-git-worktrees: branch `feat/shellx-android-3f-relay-fcm` from `develop`, at `.worktrees/android-3f-relay-fcm` (the repo's worktree directory, ignored through `.git/info/exclude`). Git fallback:

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git worktree add .worktrees/android-3f-relay-fcm -b feat/shellx-android-3f-relay-fcm develop
```

Expected: `Preparing worktree (new branch 'feat/shellx-android-3f-relay-fcm')`, and `git -C .worktrees/android-3f-relay-fcm rev-parse HEAD` equals `git rev-parse develop`. If a native tool picks its own branch name, rename the branch with `git branch -m feat/shellx-android-3f-relay-fcm`.

- [ ] **Step 2: Install the relay dependencies:** `(cd relay && npm ci)`. Expected: exit status 0.

- [ ] **Step 3: Record a baseline:** `(cd relay && npm test && npm run typecheck)`. Expected: the vitest summary has no `failed` (the tests that need the `cmux-relay` binary are skipped), and typecheck prints nothing and exits 0. Write down the `Tests` count as N. If anything is red, stop and report it; do not fix it on this branch.

- [ ] **Step 4: Keep the planning files out of the branch.** This plan and the contracts file are untracked files of the main checkout. Read them at `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/`. Never copy or commit them here: a tracked copy would block the final merge into `develop` in that checkout.

---

### Task 1: FCM data-only messages in `FcmClient`

**Files:**
- Modify: `relay/src/push/fcm.ts:18-21` (new types after `PushGateway`), `relay/src/push/fcm.ts:109-170` (`FcmClient`)
- Test: `relay/test/fcm.test.ts:4-6` (import), after `:24` (fixture), inside `describe("FcmClient")` (`:92-256`)

**Interfaces:**
- Consumes: nothing new.
- Produces (exported from `relay/src/push/fcm.ts`):

```ts
/** One data-only message to one Android phone: no `notification` block, the app builds the alert from its own strings. */
export interface FcmDataMessage {
  token: string;
  /** FCM data values are strings. */
  data: Readonly<Record<string, string>>;
  /** `android.priority`. */
  priority: "high" | "normal";
  /** `android.ttl` in whole seconds, sent as `"<n>s"`. */
  ttlSec: number;
  /** `android.collapse_key`; left out of the request when undefined. */
  collapseKey?: string;
}

/** What `POST /v2/notifications` needs for Android phones; `FcmClient` in production, a fake in tests. */
export interface FcmDataGateway {
  sendData(message: FcmDataMessage): Promise<PushResult>;
}

export class FcmClient implements PushGateway, FcmDataGateway {
  send(message: PushMessage): Promise<PushResult>; // request body unchanged
  sendData(message: FcmDataMessage): Promise<PushResult>;
}
```

The request body of `sendData` is `{"message": {"token", "data", "android": {"priority", "ttl": "<ttlSec>s", "collapse_key"?}}}`.

- [ ] **Step 1: Write the failing tests.** Add `type FcmDataMessage` to the `../src/push/fcm.js` import, this fixture after `MESSAGE`, and these four tests inside `describe("FcmClient")`. They use the file's existing `fakeFetch`, `fcmError`, `ACCOUNT` and `MESSAGE`:

```ts
const DATA_MESSAGE: FcmDataMessage = {
  token: "android-token",
  data: { kind: "needs_you", machine_id: "m-1", request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" },
  priority: "high", ttlSec: 86_400, collapseKey: "req-1",
};

it("sends a data-only message: data plus android priority, ttl and collapse_key, no notification or apns block", async () => {
  const f = fakeFetch();
  const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
  expect(await client.sendData(DATA_MESSAGE)).toBe("ok");
  const send = f.sends()[0]!;
  expect(send.url).toBe("https://fcm.googleapis.com/v1/projects/shellxpro/messages:send");
  expect(new Headers(send.init.headers).get("authorization")).toBe("Bearer access-1");
  expect(JSON.parse(String(send.init.body))).toEqual({
    message: {
      token: "android-token",
      data: { kind: "needs_you", machine_id: "m-1", request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" },
      android: { priority: "high", ttl: "86400s", collapse_key: "req-1" },
    },
  });
});

it("leaves collapse_key out of a data message without one", async () => {
  const f = fakeFetch();
  await new FcmClient({ account: ACCOUNT, fetch: f.fn })
    .sendData({ token: "android-token", data: { kind: "resolved" }, priority: "normal", ttlSec: 60 });
  expect(JSON.parse(String(f.sends()[0]!.init.body))).toEqual({
    message: { token: "android-token", data: { kind: "resolved" }, android: { priority: "normal", ttl: "60s" } },
  });
});

it("uses one cached access token for notification and data messages", async () => {
  const f = fakeFetch();
  const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
  await client.send(MESSAGE);
  await client.sendData(DATA_MESSAGE);
  expect(f.tokenCalls()).toHaveLength(1);
  expect(f.sends().map((s) => new Headers(s.init.headers).get("authorization"))).toEqual(["Bearer access-1", "Bearer access-1"]);
});

it("maps a data message's answers like a notification's: a gone token is invalid_token, a payload error or an outage is error", async () => {
  const ttlViolation = () => Response.json({
    error: { code: 400, status: "INVALID_ARGUMENT", details: [
      { "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.android.ttl", description: "bad" }] },
    ] },
  }, { status: 400 });
  for (const [reply, expected] of [
    [() => fcmError(404, "NOT_FOUND", "UNREGISTERED"), "invalid_token"],
    [ttlViolation, "error"],
    [() => fcmError(503, "UNAVAILABLE", "UNAVAILABLE"), "error"],
  ] as const) {
    const client = new FcmClient({ account: ACCOUNT, fetch: fakeFetch({ sendReply: reply }).fn });
    expect(await client.sendData(DATA_MESSAGE)).toBe(expected);
  }
});
```

- [ ] **Step 2: Run the tests to verify they fail.** Run: `(cd relay && npx vitest run test/fcm.test.ts)`. Expected: FAIL, `Tests  4 failed | 18 passed (22)`, each failure a `TypeError: … sendData is not a function`.

- [ ] **Step 3: Implement `FcmClient.sendData(message: FcmDataMessage): Promise<PushResult>` in `relay/src/push/fcm.ts`.** Add the two types after `PushGateway` and declare `FcmClient implements PushGateway, FcmDataGateway`. Move the access-token, POST and error-mapping logic of `send` (today's lines 131-169) into `private async post(message: Readonly<Record<string, unknown>>): Promise<PushResult>`, which posts `JSON.stringify({ message })` to `sendUrl`. `send` calls `post` with today's message object (`token`, `notification`, `data`, `android`, `apns`) unchanged. `sendData` passes `{ token, data, android: { priority, ttl: "<ttlSec>s" } }`, adding `collapse_key` inside `android` only when `collapseKey` is defined. The log events stay `fcm_token_failed` / `fcm_send_failed`. Extend the class comment: it never logs tokens, titles, bodies or data.

- [ ] **Step 4: Run the tests to verify they pass.** Run: `(cd relay && npx vitest run test/fcm.test.ts)`. Expected: `Tests  22 passed (22)`. The unchanged test "sends the HTTP v1 message: notification, data, android high priority, APNs default sound" is the proof that v1 still posts the same body. Then run `(cd relay && npm test && npm run typecheck)`. Expected: no `failed`, `Tests` = N + 4, and typecheck exits 0 with no output.

- [ ] **Step 5: Commit.**

```bash
git add relay/src/push/fcm.ts relay/test/fcm.test.ts
git commit -m "feat(relay): FCM data-only messages (android priority, ttl, collapse key) in FcmClient"
```

---

### Task 2: Fan `POST /v2/notifications` out to Android phones

**Files:**
- Modify: `relay/src/app.ts:26` (import), `relay/src/app.ts:41-44` (`AppDeps`), `relay/src/app.ts:60-61` (`AppVariables`), `relay/src/app.ts:100-101` (middleware)
- Modify: `relay/src/v2/notifications.ts:1-100` (the route)
- Modify: `relay/src/push/apns.ts:182-186` (doc comment only)
- Modify: `relay/README.md` (new bullet after the `POST /v1/notifications` bullet, which ends at line 188)
- Test: `relay/test/v2-notifications.test.ts`

**Interfaces:**
- Consumes: `FcmDataMessage`, `FcmDataGateway`, `PushResult` (Task 1).
- Produces:
  - `AppDeps.fcm?: FcmDataGateway | null` and `AppVariables.fcm: FcmDataGateway | null` (read with `c.get("fcm")`), set from `deps.fcm ?? null`. Task 3 passes the production client here.
  - Log events: `v2_notification {device_id, kind, recipients, fcm_recipients, sent, tokens_removed}`, where `recipients` counts APNs plus FCM recipients; and, once per send that threw, `v2_notification_send_failed {via: "apns" | "fcm", error: errorKind(reason)}`.
  - `NEEDS_YOU_EXPIRY_SEC` (value unchanged, `24 * 60 * 60`) is also the FCM `ttlSec` of both kinds.

- [ ] **Step 1: Write the failing tests** in `relay/test/v2-notifications.test.ts`.

Test scaffolding (bodies are yours; the behaviour is fixed here):
- Imports become `import { afterEach, describe, expect, it, vi } from "vitest";` and `import type { FcmDataGateway, FcmDataMessage, PushResult } from "../src/push/fcm.js";`. Add `afterEach(() => vi.restoreAllMocks());` at the top level.
- `FakeApns`: its `results` become `Record<string, PushResult | "throw">`. On `"throw"` it records the message, then rejects with `new TypeError("fetch failed")`.
- `class FakeFcm implements FcmDataGateway`: `readonly sent: FcmDataMessage[]`, and a constructor taking `results: Record<string, PushResult | "throw"> = {}`. `sendData` records the message and answers `results[message.token] ?? "ok"`, rejecting with `new TypeError("fetch failed")` on `"throw"`.
- `async function grant(app: TestApp, machine: { session: Session; machineId: string }, phone: Session): Promise<void>`: today's pairing request and approval from `grantedPhone` (lines 39-43), which `grantedPhone` now calls.
- `function loginAndroid(app: TestApp, account: Account): Promise<Session>`: returns `loginDesktop(app, account, { kind: "mobile", platform: "android", name: "Pixel 9" })`. Its comment says that `loginDesktop`'s overrides replace every field of the device body, `kind` included. Reusing the helper means the test follows any change plan 1A makes to the sign-in helpers.
- `async function grantedAndroidPhone(app, account, machine, token: string | null): Promise<Session>`: `loginAndroid`, then `grant`, then, unless `token` is null, `PUT /v1/devices/me/push-token {token, platform: "android"}` expecting 204.
- `function captureLogs(): string[]`: `vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); })`, returning `lines`.
- `function eventsOf(lines: string[]): Record<string, unknown>[]`: each line parsed as JSON, skipping lines that are not JSON objects.

Add these tests in a new `describe("POST /v2/notifications to Android phones (FCM data messages)")`. They use the file's `mac`, `grantedPhone`, `notify`, `tokenOf` and `NEEDS_YOU` (`{kind: "needs_you", request_id: "req-1", agent: "Claude Code", workspace_title: "shellx"}`):

```ts
it("sends each granted Android phone a data-only needs_you: high priority, 24 h, collapsed by request id, beside the iPhones' alert", async () => {
  const apns = new FakeApns();
  const fcm = new FakeFcm();
  const app = makeApp({ apns, fcm });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedPhone(app, account, m, tokenOf(1));
  await grantedAndroidPhone(app, account, m, "fcm-a");
  await grantedAndroidPhone(app, account, m, "fcm-b");

  const res = await notify(app, m.session.token, NEEDS_YOU);

  expect(res.status).toBe(202);
  expect(await res.json()).toEqual({ sent: 3 });
  expect(apns.sent.map((s) => s.token)).toEqual([tokenOf(1)]);
  expect(fcm.sent.map((s) => s.token).sort()).toEqual(["fcm-a", "fcm-b"]);
  expect(fcm.sent.find((s) => s.token === "fcm-a")).toEqual({
    token: "fcm-a",
    data: { kind: "needs_you", machine_id: m.machineId, request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" },
    priority: "high", ttlSec: 24 * 60 * 60, collapseKey: "req-1",
  });
});

it("passes the workspace title through as the Mac sent it, and an empty one when the Mac hides it or sends none", async () => {
  const fcm = new FakeFcm();
  const app = makeApp({ fcm });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedAndroidPhone(app, account, m, "fcm-a");
  for (const body of [
    { ...NEEDS_YOU, workspace_title: "Dự án 🚀" },
    { ...NEEDS_YOU, workspace_title: "" },
    { kind: "needs_you", request_id: "req-2", agent: "Codex" },
  ]) expect((await notify(app, m.session.token, body)).status).toBe(202);
  expect(fcm.sent.map((s) => [s.data.agent, s.data.workspace_title])).toEqual([
    ["Claude Code", "Dự án 🚀"], ["Claude Code", ""], ["Codex", ""],
  ]);
});

it("tells Android phones a request was handled: normal priority, the same collapse key and TTL, and only the ids", async () => {
  const fcm = new FakeFcm();
  const app = makeApp({ fcm });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedAndroidPhone(app, account, m, "fcm-a");

  const res = await notify(app, m.session.token, { kind: "resolved", request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" });

  expect(res.status).toBe(202);
  expect(fcm.sent).toEqual([{
    token: "fcm-a",
    data: { kind: "resolved", machine_id: m.machineId, request_id: "req-1" },
    priority: "normal", ttlSec: 24 * 60 * 60, collapseKey: "req-1",
  }]);
});

it("skips Android phones of another Mac or account, not granted, without a token or idle past the sign-in lifetime, and an iPhone's FCM-style token", async () => {
  let now = 1_800_000_000_000;
  const apns = new FakeApns();
  const fcm = new FakeFcm();
  const app = makeApp({ apns, fcm, now: () => now });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedAndroidPhone(app, account, await mac(app, account), "fcm-other-mac");
  await grantedAndroidPhone(app, account, m, null);
  const idle = await grantedAndroidPhone(app, account, m, "fcm-idle");
  await grantedPhone(app, account, m, "fcm-style-iphone-token", null);
  const notGranted = await loginAndroid(app, account);
  expect((await call(app, "PUT", "/v1/devices/me/push-token", {
    token: notGranted.token, body: { token: "fcm-not-granted", platform: "android" },
  })).status).toBe(204);
  const stranger = await registerAccount(app);
  await grantedAndroidPhone(app, stranger, await mac(app, stranger), "fcm-stranger");
  db().run("UPDATE tokens SET last_used_at = ? WHERE device_id = ?", now - TOKEN_IDLE_TTL_MS - 1, idle.deviceId);
  now += 1;

  const res = await notify(app, m.session.token, NEEDS_YOU);

  expect(await res.json()).toEqual({ sent: 0 });
  expect(fcm.sent).toEqual([]);
  expect(apns.sent).toEqual([]);
});

it("deletes the Android tokens FCM says are gone and keeps the others", async () => {
  const fcm = new FakeFcm({ "fcm-gone": "invalid_token", "fcm-flaky": "error" });
  const app = makeApp({ fcm });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  const gone = await grantedAndroidPhone(app, account, m, "fcm-gone");
  const flaky = await grantedAndroidPhone(app, account, m, "fcm-flaky");

  expect(await (await notify(app, m.session.token, NEEDS_YOU)).json()).toEqual({ sent: 0 });

  const left = db().all<{ device_id: string }>("SELECT device_id FROM push_tokens").map((r) => r.device_id);
  expect(left).toEqual([flaky.deviceId]);
  expect(left).not.toContain(gone.deviceId);
});

it("never lets one phone's failed send stop the others: a send that throws counts as not sent and is logged by kind", async () => {
  const lines = captureLogs();
  const apns = new FakeApns({ [tokenOf(2)]: "throw" });
  const fcm = new FakeFcm({ "fcm-throws": "throw" });
  const app = makeApp({ apns, fcm });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedPhone(app, account, m, tokenOf(1));
  await grantedPhone(app, account, m, tokenOf(2));
  await grantedAndroidPhone(app, account, m, "fcm-ok");
  await grantedAndroidPhone(app, account, m, "fcm-throws");

  const res = await notify(app, m.session.token, NEEDS_YOU);

  expect(res.status).toBe(202);
  expect(await res.json()).toEqual({ sent: 2 });
  expect(apns.sent.map((s) => s.token).sort()).toEqual([tokenOf(1), tokenOf(2)]);
  expect(fcm.sent.map((s) => s.token).sort()).toEqual(["fcm-ok", "fcm-throws"]);
  const events = eventsOf(lines);
  expect(events).toContainEqual({ ts: expect.any(Number), event: "v2_notification_send_failed", via: "apns", error: "TypeError" });
  expect(events).toContainEqual({ ts: expect.any(Number), event: "v2_notification_send_failed", via: "fcm", error: "TypeError" });
  expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM push_tokens")!.n).toBe(4);
});

it("answers 503 push_unavailable only when neither APNs nor FCM is set up; with one of them the other platform's phones are skipped", async () => {
  const fcmOnly = new FakeFcm();
  const a = makeApp({ fcm: fcmOnly });
  const accountA = await registerAccount(a);
  const macA = await mac(a, accountA);
  await grantedPhone(a, accountA, macA, tokenOf(1));
  await grantedAndroidPhone(a, accountA, macA, "fcm-a");
  const resA = await notify(a, macA.session.token, NEEDS_YOU);
  expect(resA.status).toBe(202);
  expect(await resA.json()).toEqual({ sent: 1 });
  expect(fcmOnly.sent.map((s) => s.token)).toEqual(["fcm-a"]);

  const apnsOnly = new FakeApns();
  const b = makeApp({ apns: apnsOnly });
  const accountB = await registerAccount(b);
  const macB = await mac(b, accountB);
  await grantedPhone(b, accountB, macB, tokenOf(2));
  await grantedAndroidPhone(b, accountB, macB, "fcm-b");
  expect(await (await notify(b, macB.session.token, NEEDS_YOU)).json()).toEqual({ sent: 1 });
  expect(apnsOnly.sent.map((s) => s.token)).toEqual([tokenOf(2)]);

  const off = makeApp();
  const offAccount = await registerAccount(off);
  const offMac = await mac(off, offAccount);
  const resOff = await notify(off, offMac.session.token, NEEDS_YOU);
  expect(resOff.status).toBe(503);
  expect(await errorCode(resOff)).toBe("push_unavailable");
});

it("counts a needs_you once against the Mac however many iPhones and Android phones it reaches, and a resolved never", async () => {
  const limiter = new CountingLimiter(10);
  const app = makeApp({ apns: new FakeApns(), fcm: new FakeFcm(), limiters: { ...unlimited, notifyAgent: limiter } });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedPhone(app, account, m, tokenOf(1));
  await grantedAndroidPhone(app, account, m, "fcm-a");
  await grantedAndroidPhone(app, account, m, "fcm-b");

  expect(await (await notify(app, m.session.token, NEEDS_YOU)).json()).toEqual({ sent: 3 });
  expect(await (await notify(app, m.session.token, { kind: "resolved", request_id: "req-1" })).json()).toEqual({ sent: 3 });
  expect(limiter.calls).toEqual([m.session.deviceId]);
});

it("logs the kind and the counts only: never the agent, the workspace, the request id or a token", async () => {
  const lines = captureLogs();
  const app = makeApp({ apns: new FakeApns(), fcm: new FakeFcm() });
  const account = await registerAccount(app);
  const m = await mac(app, account);
  await grantedPhone(app, account, m, tokenOf(1));
  await grantedAndroidPhone(app, account, m, "fcm-secret-token");

  await notify(app, m.session.token, { kind: "needs_you", request_id: "req-secret-7", agent: "Claude Code", workspace_title: "Dự án bí mật" });

  expect(eventsOf(lines).filter((e) => e.event === "v2_notification")).toEqual([{
    ts: expect.any(Number), event: "v2_notification", device_id: m.session.deviceId, kind: "needs_you",
    recipients: 2, fcm_recipients: 1, sent: 2, tokens_removed: 0,
  }]);
  const output = lines.join("\n");
  for (const secret of ["Claude Code", "Dự án bí mật", "req-secret-7", tokenOf(1), "fcm-secret-token"]) expect(output).not.toContain(secret);
});
```

- [ ] **Step 2: Run the tests to verify they fail.** Run: `(cd relay && npx vitest run test/v2-notifications.test.ts)`. Expected: FAIL, `Tests  8 failed | 12 passed (20)`. The route ignores `fcm`: Android phones get nothing, an FCM-only relay answers 503, and a throwing APNs send answers 500. "skips Android phones…" already passes (it pins the selection once the fan-out exists), and the 11 existing tests pass.

- [ ] **Step 3: Add the `fcm` dependency in `relay/src/app.ts`.** Change the import to `import type { FcmDataGateway, PushGateway } from "./push/fcm.js";`. In `AppDeps`, after `apns?`, add `fcm?: FcmDataGateway | null;`, documented as: FCM data messages to the Android app (`POST /v2/notifications`); in production the same `FcmClient` as `push`; null or absent when FCM is not configured, and with `apns` also null `/v2/notifications` answers 503 `push_unavailable`. Reword the `push` and `apns` comments to match (`push` serves `POST /v1/notifications`; `apns` alone no longer decides the 503). In `AppVariables`, after `apns`, add `fcm: FcmDataGateway | null;`. In the middleware, after line 101, add `c.set("fcm", deps.fcm ?? null);`.

- [ ] **Step 4: Fan out in `relay/src/v2/notifications.ts`.** Request parsing, validation, the limiter call and the machine lookup stay exactly as they are. The changes:
  - Imports: add `errorKind` from `../log.js`, and `type FcmDataMessage, type PushResult` from `../push/fcm.js`.
  - Rename `Recipient` to `ApnsRecipient`, and add `interface FcmRecipient { device_id: string; token: string }`.
  - 503: `const fcm = c.get("fcm");` and `if (apns === null && fcm === null) throw Errors.pushUnavailable();`, at today's line 41.
  - APNs recipients: today's query, run only when `apns !== null` (otherwise `[]`). Android recipients: run only when `fcm !== null`. It is the same query selecting `pt.device_id, pt.token`, with `AND d.platform = 'android'` added to the `devices` join and `pt.apns_topic IS NULL` in place of `pt.apns_topic IS NOT NULL AND pt.apns_env IS NOT NULL`.
  - The APNs message builder is unchanged. The FCM message for recipient `r`, where `data` is today's `{ kind, machine_id: machine.id, request_id: requestId }`:
    - `needs_you`: `{ token: r.token, data: { ...data, agent, workspace_title: workspace }, priority: "high", ttlSec: NEEDS_YOU_EXPIRY_SEC, collapseKey: requestId }`. `agent` and `workspace` are passed as received, with `workspace` defaulting to `""` as today. Both are validated strings for `needs_you`; write `agent as string`, as today's code does for `workspace`.
    - `resolved`: `{ token: r.token, data, priority: "normal", ttlSec: NEEDS_YOU_EXPIRY_SEC, collapseKey: requestId }`.
  - Sending: one `Promise.allSettled` over the APNs sends followed by the FCM sends. A rejected entry counts as `"error"` and logs `logMeta("v2_notification_send_failed", { via: "apns" | "fcm", error: errorKind(reason) })`. Then today's loop: `"ok"` increments `sent`; `"invalid_token"` runs today's `DELETE FROM push_tokens WHERE device_id = ? AND token = ?` for that recipient.
  - Summary log: `logMeta("v2_notification", { device_id: auth.deviceId, kind, recipients: <APNs + FCM recipients>, fcm_recipients: <FCM recipients>, sent, tokens_removed: removed })`.
  - Comments: `NEEDS_YOU_EXPIRY_SEC` is how long APNs and FCM keep trying to reach a phone that is off, and FCM keeps a `resolved` that long so it can still replace an undelivered alert. The route comment (lines 27-37) describes Android phones getting a data-only FCM message (the five keys, the priorities, TTL and collapse key), and the 503 only without both APNs and FCM.
  - `relay/src/push/apns.ts:182-186`: the comment ends "…push to iPhones is off, the relay keeps running and `POST /v2/notifications` reaches Android phones only (503 `push_unavailable` when FCM is off too)."

- [ ] **Step 5: Run the tests to verify they pass.** Run: `(cd relay && npx vitest run test/v2-notifications.test.ts)`. Expected: `Tests  20 passed (20)`. Then run `(cd relay && npm test && npm run typecheck)`. Expected: no `failed`, `Tests` = N + 13, and typecheck exits 0 with no output.

- [ ] **Step 6: Document the route in `relay/README.md`.** In "Push notifications", insert this bullet after the `POST /v1/notifications` bullet (after line 188):

~~~markdown
- `POST /v2/notifications {kind, request_id, agent?, workspace_title?}` (native desktops with a
  registered machine: `403 desktop_only` otherwise, `404` without a machine): `kind` is `needs_you`
  (with `agent`, 1..64 characters, and an optional `workspace_title` up to 200) or `resolved`;
  `request_id` is 1..64 bytes. Recipients are the phones granted this machine with a live sign-in.
  iPhones (a token with `apns_topic`) get APNs: for `needs_you` an alert in the phone's own words
  (`push.needsYou[.workspace]`), priority 10, `apns-collapse-id` = `request_id`, kept 24 h; for
  `resolved` a background push. Android phones (device `platform` `android`, a token without
  `apns_topic`) get an FCM data-only message (no `notification` block): `data` is `{kind,
  machine_id, request_id}`, plus `agent` and `workspace_title` (`""` when none) for `needs_you`;
  `android.priority` is `high` for `needs_you` and `normal` for `resolved`; both carry
  `android.ttl` `86400s` and `android.collapse_key` = `request_id`, so a `resolved` replaces a
  `needs_you` that has not been delivered yet. Nothing the agent asks is ever sent. Answers
  `202 {sent}` once every send has finished; one phone's failure never stops the others; tokens
  APNs or FCM report as gone are deleted. `503 push_unavailable` only when neither APNs nor FCM is
  configured (with one of them, the other platform's phones are skipped). A valid `needs_you`
  counts once against the Mac's notification limit (120 per hour, `429 rate_limited`); `resolved`
  never does. The `v2_notification` log line has the kind and counts (`recipients`,
  `fcm_recipients`, `sent`, `tokens_removed`), never the agent, the workspace, the request id or a
  token.
~~~

- [ ] **Step 7: Commit.**

```bash
git add relay/src/app.ts relay/src/v2/notifications.ts relay/src/push/apns.ts relay/test/v2-notifications.test.ts relay/README.md
git commit -m "feat(relay): POST /v2/notifications also reaches Android phones as FCM data messages"
```

---

### Task 3: Production wiring, the fake-FCM end-to-end test and the operator docs

**Files:**
- Modify: `relay/src/push/config.ts:2` (import), `relay/src/push/config.ts:7-9` (`PushSetup`), `relay/src/push/config.ts:34-38` (comment)
- Modify: `relay/src/server.ts:37-45` (comments), `relay/src/server.ts:59` (`startRelay` deps)
- Test: `relay/test/server.test.ts:15-18` (imports), `relay/test/server.test.ts:308-379` (`describe("push configuration …")`)
- Modify: `relay/README.md:47` (the `FCM_SERVICE_ACCOUNT` row, plus a new row after it), `relay/README.md:195`
- Modify: `deploy/README.md` (new subsection after line 234)
- Modify: `deploy/docker-compose.yml:35-41` (comments only)

**Interfaces:**
- Consumes: `FcmClient` (Task 1); `AppDeps.fcm` (Task 2).
- Produces: `PushSetup = { gateway: FcmClient; projectId: string } | { gateway: null; reason: PushDisabledReason }`. `server.ts` passes `push: push.gateway, fcm: push.gateway`.

- [ ] **Step 1: Write the failing end-to-end test** in `relay/test/server.test.ts`. Add `loginDesktop` and `registerMachine` to the `./helpers.js` import. Inside the `push configuration` describe, extract two helpers from the existing test "with a key and loopback FCM overrides, a notification reaches the (fake) FCM server…", and refactor that test to use them without changing any of its assertions:
  - `function writeServiceAccount(path: string, projectId: string): void` writes `{project_id, client_email: "t@<projectId>.iam", private_key}` with a fresh 2048-bit RSA PKCS#8 key.
  - `async function startFakeFcm(): Promise<{ url: string; seen: { path: string; body: string }[] }>` starts today's fake server on 127.0.0.1 (`/token` answers `{access_token: "fake", expires_in: 3600}`, any other path `{name: "m/1"}`), records each request, and closes it with `onCleanup`.

  Then add this test:

```ts
it("with only an FCM key, POST /v2/notifications reaches a granted Android phone as a data-only message", async () => {
  const keyFile = join(tempDir(), "fcm.json");
  writeServiceAccount(keyFile, "shellx-test");
  const fcm = await startFakeFcm();
  const server = startServer({
    ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(tempDir(), "relay.db"), RATE_LIMITS_ENABLED: "false",
    FCM_SERVICE_ACCOUNT: keyFile, FCM_ENDPOINT: fcm.url, FCM_TOKEN_ENDPOINT: `${fcm.url}/token`,
  });
  const port = await waitForListening(server.output);
  expect(server.output()).toContain('"event":"apns_disabled","reason":"not_configured"');
  const app = remote(port);
  const account = await registerAccount(app);
  const desktop = await loginDesktop(app, account);
  const { machine_id: machineId } = await registerMachine(app, desktop.token);
  const phone = await loginDesktop(app, account, { kind: "mobile", platform: "android", name: "Pixel 9" });
  const key = Buffer.alloc(32, 7).toString("base64");
  const request = await call(app, "POST", "/v2/phone-pairings", { token: phone.token, body: { machine_id: machineId, client_key_b64: key, proof_b64: key } });
  const { pairing_id: pairingId } = await request.json<{ pairing_id: string }>();
  expect((await call(app, "POST", `/v2/phone-pairings/${pairingId}/approve`, { token: desktop.token })).status).toBe(204);
  expect((await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "android-fcm-token", platform: "android" } })).status).toBe(204);

  const res = await call(app, "POST", "/v2/notifications", {
    token: desktop.token, body: { kind: "needs_you", request_id: "req-1", agent: "Claude Code", workspace_title: "Dự án" },
  });

  expect(res.status).toBe(202);
  expect(await res.json()).toEqual({ sent: 1 });
  expect(fcm.seen.map((s) => s.path)).toEqual(["/token", "/v1/projects/shellx-test/messages:send"]);
  expect(JSON.parse(fcm.seen[1]!.body)).toEqual({
    message: {
      token: "android-fcm-token",
      data: { kind: "needs_you", machine_id: machineId, request_id: "req-1", agent: "Claude Code", workspace_title: "Dự án" },
      android: { priority: "high", ttl: "86400s", collapse_key: "req-1" },
    },
  });
  server.child.kill("SIGTERM");
  const result = await server.exit;
  expect(result.code).toBe(0);
  for (const secret of ["Claude Code", "Dự án", "android-fcm-token"]) expect(result.stdout).not.toContain(secret);
});
```

- [ ] **Step 2: Run the test to verify it fails.** Run: `(cd relay && npx vitest run test/server.test.ts -t "with only an FCM key")`. Expected: FAIL, `AssertionError: expected 503 to be 202`, `Tests  1 failed | 13 skipped (14)`. `server.ts` does not pass `fcm` yet.

- [ ] **Step 3: Wire the client.** In `relay/src/push/config.ts`, type `PushSetup`'s gateway as `FcmClient` (drop the now unused `type PushGateway` import), and end the `loadPush` comment with: "`POST /v1/notifications` then answers 503 `push_unavailable`, and `POST /v2/notifications` reaches iPhones only." In `relay/src/server.ts`, line 59 passes `push: push.gateway, fcm: push.gateway, apns: apns.gateway`. The comments at lines 37 and 41-42 say that the one FCM client serves v1 notifications and the Android app's data messages, and that without APNs `POST /v2/notifications` reaches Android phones only (503 only when FCM is off too).

- [ ] **Step 4: Run the tests to verify they pass.** Run: `(cd relay && npx vitest run test/server.test.ts -t "push configuration")`. Expected: `Tests  3 passed | 11 skipped (14)`, which includes the two existing push tests after the helper extraction.

- [ ] **Step 5: Update the operator docs.**
  - `relay/README.md:47`: replace the `FCM_SERVICE_ACCOUNT` row, and add the APNs row after it:

~~~markdown
| `FCM_SERVICE_ACCOUNT` | unset | Path of the Firebase service account JSON key (push through FCM: `POST /v1/notifications`, and the Android phones of `POST /v2/notifications`). Unset, unreadable or invalid → FCM push is off, the relay runs normally, logs `push_disabled` with the reason once, `POST /v1/notifications` answers 503 `push_unavailable` and `POST /v2/notifications` reaches iPhones only (503 when APNs is off too) |
| `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID` | unset | The APNs provider key (`.p8` file path), its key id and the Apple team id (push to the native iPhone app through `POST /v2/notifications`). Any unset, or a file that is not a key → iPhone push is off, the relay runs normally and logs `apns_disabled` with the reason once; `POST /v2/notifications` then reaches Android phones only (503 `push_unavailable` when FCM is off too) |
~~~

  - `relay/README.md:195`: replace "`packages/shellx_e2e/test/push_e2e_test.dart` runs that fake server on port 8788." with "`test/server.test.ts` (\"push configuration\") runs the relay process against such a fake server for `POST /v1/notifications` and for `POST /v2/notifications` to an Android phone."
  - `deploy/README.md`: after line 234 ("…and the relay sends each token to its own host."), insert:

~~~markdown
### Android push (FCM)

The Android app gets its "needs you" alerts from the same `POST /v2/notifications` call that
reaches iPhones: the relay sends each Android phone granted that Mac an FCM data-only message with
the service account key above. Nothing else is set up on the VPS. Check it after a deploy:

```bash
cd ~/phu/shellx && docker compose logs relay | grep push_   # push_enabled {"project":"shellxpro"}
```

With `push_disabled` instead, Android phones get nothing (iPhones still get APNs): do steps 1–2
above. Both Android apps, `com.shellx.prod` and `com.shellx.dev`, must be apps of Firebase project
`shellxpro`; FCM refuses a token from another project (`fcm_send_failed` with `SENDER_ID_MISMATCH`)
and the relay keeps such a token. `POST /v2/notifications` answers 503 `push_unavailable` only when
both the FCM and the APNs key are missing. Each call logs one `v2_notification` line with
`recipients`, `fcm_recipients`, `sent` and `tokens_removed`, never what the alert says or a token.
~~~

  - `deploy/docker-compose.yml:35-41`: replace the two comment blocks, leaving the variable lines as they are:

```yaml
      # Push notifications (push spec §5): path of the Firebase service account key inside the
      # container, e.g. /secrets/fcm.json, set once by hand in .env (deploy/README.md, "Push
      # notifications"). It also carries the Android app's alerts (POST /v2/notifications). Empty →
      # no FCM push and the relay runs as before.
```

```yaml
      # Push to the native iPhone app (APNs, no Firebase): the .p8 provider key inside the container,
      # e.g. /secrets/apns.p8, with its key id and the Apple team id, set once by hand in .env
      # (deploy/README.md, "iPhone push (APNs)"). Any empty → no iPhone push; POST /v2/notifications
      # answers 503 only when FCM_SERVICE_ACCOUNT is empty too.
```

- [ ] **Step 6: Check the deploy files.** Run: `node --test deploy/tests/compose.test.mjs`. Expected: the summary ends with `# fail 0`.

- [ ] **Step 7: Run the full relay suite.** Run: `(cd relay && npm test && npm run typecheck)`. Expected: no `failed`, `Tests` = N + 14, and typecheck exits 0 with no output.

- [ ] **Step 8: Commit.**

```bash
git add relay/src/push/config.ts relay/src/server.ts relay/test/server.test.ts relay/README.md deploy/README.md deploy/docker-compose.yml
git commit -m "feat(relay): send the Android app's data messages with the FCM client; e2e test and push runbook"
```

---

### Task 4: Verify and hand off

**Files:** none changed (verification and landing).

- [ ] **Step 1: Run the relay suite:** `(cd relay && npm test && npm run typecheck)`. Expected: no `failed`, `Tests` = N + 14, and typecheck exits 0 with no output.

- [ ] **Step 2: Run the deploy check:** `node --test deploy/tests/compose.test.mjs`. Expected: `# fail 0`.

- [ ] **Step 3: Run the repository preflight:** `python3 scripts/verify-local.py`. Expected: exit status 0, and every check line reads `PASSED …` or `SKIPPED …`, never `FAILED`. If a check fails, run the same command in the main checkout on `develop`. A failure there too is pre-existing: note it in the hand-off and do not fix it here.

- [ ] **Step 4: Check the diff scope:** `git diff --stat develop...HEAD`. Expected: exactly these 12 files. `relay/src/push/{fcm,config,apns}.ts`, `relay/src/app.ts`, `relay/src/server.ts`, `relay/src/v2/notifications.ts`, `relay/test/{fcm,v2-notifications,server}.test.ts`, `relay/README.md`, `deploy/README.md`, `deploy/docker-compose.yml`. `relay/src/routes/notifications.ts` and `relay/test/notifications.test.ts` must not appear.

- [ ] **Step 5: Review.** Follow `skills/cmux-review/SKILL.md` (default pre-merge review). Give a review subagent this plan's Goal and Global Constraints, the base `git merge-base develop HEAD`, the head `git rev-parse HEAD`, and `git diff <base>..HEAD`, and ask for correctness first. Fix each confirmed finding test-first, one commit per finding with explicit `git add <paths>`, then repeat Steps 1–4. Get a fresh review of the repair delta if a fix was non-trivial.

- [ ] **Step 6: Catch up with `develop`:** `git merge --no-edit develop` in the worktree (merge, never rebase, never force-push). If it brought commits (for example plan 1A), repeat Steps 1–4. On conflicts in `relay/src/app.ts`, `relay/src/server.ts`, `relay/README.md`, `deploy/docker-compose.yml` or `relay/test/helpers.ts`, keep both sides' additions. If 1A changed the sign-in helpers, keep calling whatever `registerAccount` / `loginDesktop` now are; the assertions of this plan's tests do not change.

- [ ] **Step 7: Land (contracts §1).** In the main checkout:

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git branch --show-current                  # develop
git status --short --untracked-files=no    # must print nothing; otherwise stop and ask the user
git merge --no-ff --no-edit feat/shellx-android-3f-relay-fcm
(cd relay && npm test && npm run typecheck)
git push origin develop
```

Expected: the merge succeeds, the tests and typecheck pass as in Step 1, and the push is accepted. Never merge to `main`, never deploy, never run `deploy/vps-deploy.sh`.

- [ ] **Step 8: Hand off to the user, in Vietnamese.** Include:
  - the merge SHA on `develop` and the test counts;
  - that nothing is deployed, and that this branch goes out in the same relay deploy as plan 1A, which the user runs in plan 1D;
  - that before that deploy the user checks `FCM_SERVICE_ACCOUNT` on the VPS (`deploy/README.md` "Android push (FCM)"), and that adding `com.shellx.dev` to Firebase `shellxpro` is still the user's step (S3 §10);
  - the localization audit: no user-facing string changed (the relay sends ids and the Mac's names, the Android app owns the wording, and both READMEs are English-only operator docs);
  - any pre-existing failure from Step 3.

- [ ] **Step 9: Clean up.** Remove the worktree with the mechanism that created it (`ExitWorktree` for a native one, otherwise `git -C /Users/lehuuphu/Documents/myProjects/shellx worktree remove .worktrees/android-3f-relay-fcm`). Keep the branch.

---

## Contract additions

Proposed contracts §8 "Relay FCM push to Android (owner 3F; consumers 3E, 1D)". Not edited into the contracts file by this plan.

- **Registration** (existing routes): the phone signs in with `device.kind` `mobile` and `device.platform` `android`. It sends `PUT /v1/devices/me/push-token {token, platform: "android"}` (no `apns_topic` / `apns_env`) whenever its FCM token changes, and `DELETE /v1/devices/me/push-token` on sign-out.
- **Recipients:** Android phones granted the Mac (`/v2/phone-grants`) with a live sign-in.
- **Message:** FCM HTTP v1, data-only. There is no `notification` block, so `RemoteMessage.getNotification()` is null and `FirebaseMessagingService.onMessageReceived` runs in the foreground and in the background.
  - `needs_you`: `android.priority` `high`, `android.ttl` `86400s`, `android.collapse_key` = `request_id`. `data` = `{kind: "needs_you", machine_id, request_id, agent, workspace_title}`.
  - `resolved`: `android.priority` `normal`, `android.ttl` `86400s`, `android.collapse_key` = `request_id`. `data` = `{kind: "resolved", machine_id, request_id}`.
  - Values (all strings): `machine_id` is the Mac's lower-case UUID; `request_id` is opaque, 1..64 UTF-8 bytes; `agent` is 1..64 characters, a display name such as `Claude Code`; `workspace_title` is 0..200 characters, and `""` means none or hidden.
- **App rules** (3E, mirroring `shellx-ios/ShellX/Platform/PushAppDelegate.swift` and `ShellXAppCore/Push/PushPayload.swift`):
  - Ignore an unknown `kind`, or a message without `machine_id` / `request_id`.
  - Tag the notification with `request_id` and group it by `machine_id` (the iPhone's `thread-id`).
  - The title is `push_title`. The text is `push_needs_you_workspace(agent, workspace_title)` when `workspace_title.trim()` is not empty, otherwise `push_needs_you(agent)`. These are the contracts §5 names of `push.title`, `push.needsYou.workspace` and `push.needsYou`.
  - `resolved` cancels the notification tagged `request_id`.
  - A tap opens the waiting requests (route `pending`).
- **Ops** (1D): Android push uses the existing `FCM_SERVICE_ACCOUNT`. After the deploy, `docker compose logs relay | grep push_` must show `push_enabled {"project":"shellxpro"}`. `com.shellx.dev` must be an app of Firebase project `shellxpro`.

## Spec notes

1. The spec's references match the code. `fcm.ts:5-10` is `PushMessage` (title and body required), `fcm.ts:143-151` builds the body that always has `notification` and has no TTL or collapse key, and `routes/notifications.ts:102-103` is the v1 call site. There was nothing to reconcile.
2. The spec fixes only `resolved`'s priority. The plan gives it `collapse_key` = `request_id` and `ttl` `86400s`, like `needs_you`, because FCM keeps no order between messages. While a phone is off, a `resolved` with the same key replaces the stored `needs_you`, so a request handled meanwhile never pops up on reconnect (S3 §4: notifications and desktop state must not drift apart). The removal also lives as long as the alert it removes.
3. FCM keeps at most four distinct collapse keys per offline device and does not say which ones survive. A phone that stays off through more than four distinct requests may miss some of those alerts. This is accepted as the cost of the spec's per-request key; the app lists every waiting request when opened.
4. `agent` and `workspace_title` travel only with `needs_you`, because the route validates them only for that kind. `workspace_title` is forwarded as received, `""` when absent; the Mac sends `""` under "Hide content" (`Sources/ShellX/Remote/Link/ShellXPhonePushForwarder.swift:84-85`). The app picks the no-workspace wording when the title is blank after trimming, the rule the relay already applies to the iPhone's `loc-key` (`relay/src/v2/notifications.ts:71`).
5. "Thiết bị `platform = 'android'`" is read as `devices.platform`, the platform the phone signed in with. `push_tokens.platform` is not consulted.
6. The spec says "mở rộng" (extend) `fcm.ts`. The plan adds `sendData` and `FcmDataGateway` and leaves `PushMessage` and `PushGateway` as they are, so v1 and its test fake need no edit. The app gets the same client twice: `push` for v1, `fcm` for v2.
7. A send that throws (a bug, not an FCM or APNs answer) counts as not sent and is logged by kind. Today, `Promise.all` would turn one rejected send into a 500 for the whole call.
8. Stale docs are fixed on the way: `deploy/docker-compose.yml:41` ("Any empty → POST /v2/notifications answers 503"); `relay/README.md` never documented `POST /v2/notifications` or the `APNS_*` variables; and `relay/README.md:195` points at `packages/shellx_e2e/test/push_e2e_test.dart`, which was deleted with the Flutter app.
