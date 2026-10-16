# V2-4 final whole-branch review (opus, 130d8aa..1b378da) — verbatim

Reviewer agent a60146f9a8826cf8e (interrupted once by the account's usage limit, resumed by SendMessage with its context intact).

I reviewed the V2-4 branch (130d8aa..1b378da) and the verdict is **With fixes**: two functional defects I confirmed with real-socket probes need fixing before main releases the app, and one spec number needs your decision. I found nothing that weakens Review Focus 1–5.

**How I reviewed (in passes):**
1. Spec (whole), plan header, both ledgers, both hand-offs, the deferred-minor extract and the Task 16 evidence.
2. All production code: core, agent, client, mobile (plus platform config and pubspec) and the desktop wiring. For V2-3 Task 1 I checked only how V2-4 uses it.
3. Tests where a risk needed it (RF 1 sizes, the 50 MB pacing test, gate and S2 tests, e2e), a spot-check of generated code, and the EN/VI strings against spec §6.
4. Probes with real sockets, written in my temp folder and run against the worktree's existing package config. I validated candidate fixes on a scratch copy of `shellx_client`.

The checkout was never modified: HEAD 1b378da, `git status` clean. I re-ran no full suite, only three client test files against the patched copy. My temp folder is removed.

### Strengths
- **Protocol:** a bad or unknown `tool.*` message decodes to null instead of dropping the channel. Every send is size-checked at both ends (`_emit`, `enqueue`), and the largest message of each kind has a test. Core edits are additive only.
- **Flow control** is one shared implementation used by both ends (windows, shared credit, cumulative acks, token pacer). A full window pauses the source and never drops bytes; the 50 MB test checks SHA-256 at ≤150 frames/s and ≤8 MiB/s.
- **Only the tool is reachable, by construction:** the HTTP client's connection factory passes only a port to a loopback-only connect. Proxies are bypassed, redirects not followed, bodies not unpacked, URLs built with `Uri`, a `//` path after normalisation refused, and the phone flag re-checked on every stream.
- **The phone gate holds:**
  - loopback-only binding, the `Host` check, a one-time nonce, and the HttpOnly SameSite=Strict cookie compared in constant time;
  - `Origin` and `Sec-Fetch-Site` checks on unsafe requests and upgrades; `/__shellx/` reserved; gate cookies stripped at both ends;
  - the CSP ruling (with S1), S2's both-addresses-or-nothing binding, and the web view history rules.
  I tried subresources, forms, frames, workers, top-level navigation and redirects, and found no way for the gate cookie to reach a port the phone does not serve.
- **Compatibility:** the frozen decoders, the `tools` flag and `hello.caps` gating, and a 22-test matrix.
- **Privacy:** nothing is logged except `runtimeType`, and every `toString` redaction is pinned by a test.
- The ledgers are exemplary: every ruling has a cost-if-wrong, and the manual checks are enumerated.

### Critical
None.

### Important

**I1 — A response the web view abandons keeps its window until the 5-minute idle drop.** `packages/shellx_client/lib/src/tool_session.dart:1086-1091` (`_HttpStream.onResponse`), same shape at `:1278-1282` (`_WsStream._refused`).
- **What happens:** when the web view gives up mid-body, dart:io completes `response.addStream(inlet.stream)` normally and quietly cancels the inlet. So `_close` runs, neither side sends `tool.end`, and acks stop. The desktop stream keeps about 240 KiB of the phone's shared 512 KiB credit until `_checkIdle` drops it (5 minutes, checked every 75 s).
- **Probe:** I abandoned two 8 MiB downloads after 64 KiB each. Each stream was sent 589,824 bytes and acked 344,064, with no `tool.end` either way. A following 100 KiB resource got no answer within 8 s; a 10-byte one still fit. Instrumentation showed `addStream` and `response.done` both completing successfully.
- **Why it matters:** two abandoned streams leave 32 KiB of credit, so every larger response and larger WebSocket message from that computer waits up to 5 minutes. Everyday triggers: ↻ during a slow first load with big pre-bundled dependencies, navigating away, aborted fetches, video, and download hand-offs (manual check 14 will hit this). Leaving the page or backgrounding the app recovers it, but users won't know that.
- **Fix (validated):**
  - `.then((_) => done ? _close(response) : abort())` plus `.catchError((Object _) => abort())`, and the same in `_refused`;
  - this works because a normal end calls `forget()` synchronously in `onData`, before `addStream` completes;
  - with it, both streams end `aborted` and the 100 KiB resource answers in 35 ms; the three client test files (66 tests) still pass;
  - add a regression test for this case.

**I2 — A tool page in `unavailable` or `disabled` never recovers.** `tool_session.dart:321-326` (`_onListing` only re-asks when the tool is missing); `apps/mobile/.../pages/tool_page.dart:323,325` (these covers have no action); `tool_page_controller.dart:319` (↻ only reloads the blank web view).
- **Probe:** ready → no list → unavailable → list back with the tool → still unavailable after 3 s. Same for flag off → disabled → flag on.
- **Why it matters:** E5's own path (background service restarted with no window yet; the page says "Open ShellX on the computer") stays stuck after the user does exactly that. They have to leave the page and reopen it.
- **Fix (validated):** in `_onListing`, also call `_check()` when the phase is `unavailable` or `disabled`. With that, both reach ready again and the tests still pass. Add one session test per phase; optionally let ↻ re-ask in these phases.

**I3 — Spec-level (E10): the open budget turns a large dev page's module burst into 503s on fast links.** `packages/shellx_agent/lib/src/tool/tool_proxy.dart:16-17,216` implements "120 at once, then 60/s, else busy" exactly as the spec says; the research note gave those numbers only "for example".

Probe: one host, 6 connections, simulated one-way delay.

| One-way delay | Modules | 503s |
|---|---|---|
| 50 ms | 400 | 0 |
| 25 ms | 400 | 0 |
| 15 ms | 600 | 135 |
| 10 ms | 1000 | 400 |

- **Why it matters:** a failed ES-module import breaks a Vite app (criteria 2 and 4) rather than slowing it. This bites when the relay is close.
- **Options (your decision):** have the phone pace `tool.req` to the same budget so requests wait instead of failing, or raise the budget (the 32-stream cap already bounds concurrency). Add a several-hundred-module Vite app over a nearby relay to §10 check 1.

### Minor
- **M1 — serve/pause/close race** (ledger L359/L382/L522), `tool_session.dart:447-459` with `_checkOnce` and `pause()`/`close()`. Siblings bound after `_unserve()` copied the server list stay bound. After a resume, the page then reloads a blank view under a banner naming the sibling's port. After a close, the sockets stay bound until the app exits. Fix: a serve generation checked after each await.
- **M2 — resume lost during a pause in progress** (L472). The page is left paused and white in the foreground. Fix: keep the pause future and resume after it.
- **M3 — non-101 1xx** (L187/L358). Reproduced with `103 Early Hints`: the page gets 103 as the final status, and the desktop process gets one uncaught `HttpException` per request. Its text carries no URL, so this is not a privacy leak. Fix: `persistentConnection = false`, and `reject()` (502) on the phone.
- **M4 — the head timeout starts only after the upload** (`tool_proxy.dart:486-488`). A tool that neither reads the body nor answers holds the stream forever, along with the phone's upload credit (shared with WebSocket messages). E10 says 60 s.
- **M5 — alias mode plus a sibling (E3 × E4):** sibling requests keep `Origin: localhost:P′` and the reply's `Access-Control-Allow-Origin` is not rewritten, so the API's CORS check fails. The E3 banner already warns about this; note it in checks 4 and 5.
- **M6 —** EN `toolSlow` reads "(1 requests)"; use an ICU plural.

### Deferred-minor triage
- **Must fix before merge:** none of the deferred items on their own.
- **Fix in the same wave (cheap, real behaviour):**
  - L359/L382/L522 (M1), L472 (M2), L187/L358 (M3);
  - L329: test the phone outbox's token cap; a refill that never stops is exactly the Review Focus 2 failure that drops every machine;
  - L248: test that the service drops non-loopback, https and userinfo entries (Review Focus 4);
  - L229: test the bodyless HEAD/204/304 branch (304 is everyday);
  - L400: make the "nothing served" probe check `[::1]` too;
  - L426, L520, L639, L653–L658: doc and comment wording.
- **L470** is already resolved: the round-3 generation guard covers every web view callback after dispose.
- **Everything else can wait:** unreachable cases, test hygiene, items bounded by the windows or credit, device-only checks, perf and code-shape items, and the 10 s connect.

### Declined to judge
- Speculation-rules or prerender prefetch to a port the phone doesn't serve. It may bypass `connect-src`, and SameSite=Strict doesn't stop a same-site request. It depends on WebView support I couldn't verify, so I suggest adding it to manual check 10.
- E4's "502 for a sibling never turned on": this can't be done without telling phones about tools that are off (§4.2, R3). The CSP blocks those requests instead; it's a spec-internal tension.
- Tools behind HTTP Basic/Digest auth (no `onHttpAuthRequest` handler); the spec is silent.
- Device behaviour of ATS, Android per-domain cleartext, `::1` listing on phones, and `beforeunload` vetoes: these are in the 18 manual checks.
- Decryption on the UI isolate: spec §11 puts it out of scope.
- V2-3 Task 1 internals: excluded by the brief.
- Resource use by a malicious paired phone (16 MiB WebSocket assembly per stream, unpaced `tool.list`): E17 trusts paired phones and the ledger already rules on it.

### Recommendations
1. One small fix wave: I1 and I2 with tests, M1–M3, and the four test gaps above. Then re-run `shellx_client` and the mobile tool tests.
2. Put I3 to the user and record the decision in the ledger.
3. Add manual checks: ↻ during a slow first load with large bundles, then the page still loads; and the speculation-rules prefetch case on Android.

### Assessment
**Ready to merge? With fixes**

**Reasoning:** Security, protocol robustness and compatibility are strong and well pinned. But two confirmed defects on common paths should be fixed before main releases the app: an abandoned large response freezes the page's other loads for up to 5 minutes (I1), and a page never leaves `unavailable`/`disabled` (I2). Both fixes are a few lines and both were validated on a scratch copy. I3 needs a decision on E10's numbers.
