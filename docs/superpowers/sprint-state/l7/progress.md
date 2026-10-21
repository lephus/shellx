# SDD ledger — plan: docs/superpowers/plans/2026-10-21-native-desktop-w3b-share-links.md

Spec: docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md (reachable). Branch shellx/l7-share, start b1c519dd11 (merge base with main 70a45415c8).

## Preflight scan

| Pair / task | Produces vs consumes | Finding |
| --- | --- | --- |
| B3↔B7 | `web/tests/fixtures/share-vectors.json` written by B3, read by B7 | consistent |
| B3↔B4 | ShareSecret/ShareKeys/ShareCipher/ShareMessage | consistent; B4 and B6 use `SharePermission`, B6 and B5 use `ShareLifetime`, neither defined → ruling 1 |
| B4↔B5 | `ShareTicketProvider` defined B4, `ShellXCoreShareTickets` conforms in B5 | consistent (B5 after B4) |
| B4↔B6 | `@MainActor ShareSource` implemented by `WorkspaceShareSource` | consistent; actor awaits main-actor source |
| B1↔B5 | fake-api mirrors B1 owner routes | consistent; id form → ruling 2 |
| B1↔B7 | anonymous `POST /v2/shares/:id/ticket`, CORS for https://shellx.pro | API base not specified for the viewer → ruling 3 |
| B2↔B9 | `CMUX_RELAY_ALLOWED_ORIGINS` | consistent |
| B7↔B8 | bundled xterm + inline boot script vs CSP `script-src 'self' 'unsafe-inline'`, `style-src 'unsafe-inline'` | consistent |
| B6↔B4 | stopAll → `stop(.hostQuit)` | consistent |
| B9 | adds a test-only product to ShellXBrand `Package.swift` (not in its file list) | allowed, file list incomplete only |
| B0 | docs only | self-consistent |
| B1 | id regex `[0-9a-hjkmnp-tv-z]{8}` matches the alphabet `0123456789abcdefghjkmnpqrstvwxyz` | self-consistent |
| B2 | tests vs code | self-consistent |
| B3 | fixed-nonce injection internal for tests only | self-consistent |
| B4 | hello wait 10 s < viewer relay timeout 15 s (B7) | self-consistent |
| B5, B6, B7, B8 | tests vs code | self-consistent |

Ruling: (1) `enum SharePermission: String { view, type }` and `enum ShareLifetime: String { fifteenMinutes = "15m", oneHour = "1h", untilQuit = "until_quit" }` are defined in Task B3's `ShareMessage.swift` — B4/B5/B6 all need them and B3 is first — cost if wrong: a later move of two enums.
Ruling: (2) API share ids are the 8 chars without dash; the dash is display only (URL path `xxxx-xxxx`); Swift and the viewer strip it before API calls and HKDF salt; the API route accepts both forms — cost if wrong: a normalisation helper.
Ruling: (3) The viewer's API base comes from `web/src/site.config.json` `shareApiBase` (default `https://relay.shellx.pro`) rendered into the page, so B9 dogfood can build with a LAN base — cost if wrong: one config key.

## Tasks
Ruling: run tasks in parallel waves, each in its own worktree/branch `shellx/l7-<task>` off shellx/l7-share, merged back --no-ff after its review — user asked to speed up (2026-10-21) and the waves touch disjoint files (wave 1: B1 relay/, B2 cmux-relay + deploy compose, B3 ShellXRemoteCore/Share + web/tests/fixtures, B8 deploy/web; wave 2: B4, B5, B7; wave 3: B6; then B9) — cost if wrong: merge conflicts resolved at merge time.
Task B0: complete (commits b1c519dd11..f24057f44c, review clean)
Task B0: minor (deferred): ledger one-liners R5 (QR stream until_quit, same viewer may reconnect), R6 (90 s re-register), R7 (desktop split deferred) condensed; plan carries the full text
Wave 1 dispatched off f24057f44c: B1 (shellx/l7-b1), B2 (shellx/l7-b2), B3 (shellx/l7-b3), B8 (shellx/l7-b8)
Ruling: wave 2 (B4, B5, B7) starts off B3 head 6c2baaaa86 before B3's review returns — speed; cost if wrong: B3 fixes must be merged into those branches.
Ruling: `public protocol ShareTicketProvider: Sendable { func hostTicket(shareID: String) async throws -> (ticket: String, relayURL: URL, expiresAt: Date) }` is created by B5 in `ShellXRemoteCore/Share/ShareTicketProvider.swift` (not B4) so B4 and B5 run in parallel without both defining it; B4 consumes it and declares a local test fake — cost if wrong: a duplicate-definition merge conflict.
Task B2: complete (commits f24057f44c..aeccf13e95, review clean; merged into shellx/l7-share)
Task B2: minor (deferred): `--allowed-origin ""` not trimmed/rejected like the env path; no test pins `Origin: null` rejection
Task B3: review: spec ✅, quality approved; Important plan-mandated: cross-connection replay by the relay (static keys, seq restarts, AAD binds only circuit).
Ruling: (4) Wire amendment A1 in constraints.md — fresh 16-byte nonces in hello/welcome, staged AAD `…|circuit[|vn[|hn]]`, 64 KiB drop before decrypt, host caps `in` 4 KiB / label 40 — closes relay replay without changing keys or framing; cost if wrong: one more wire revision across B3/B4/B7 before anything ships.
Task B3: fix round 1/5 dispatched (A1 + minors 1 seq decode, 2 strict base64url, 3 open >64 KiB, 8 drop-path tests); remaining minors 4-7, 9 deferred
Task B3: minor (deferred): str() JSONEncoder per call and `?? ""`; Codable encode is non-wire; keys(shareID:) does not validate id; fixedNonce internal not #if DEBUG; permanently skipped generator test + vectors file lacks trailing newline
Note: deploy/tests/backup.test.mjs 'keeps only the 14 newest' fails on the base (expected 14, got 46) — pre-existing, not L7; flag to user
Task B8: fix round 1/5 dispatched (Important: /s/ without id served headerless 200 via location /; minors: brittle block-end detection, CSP pin comment)
Task B1: complete (commits f24057f44c..ad8bdb4f73, review clean; merged into shellx/l7-share)
Task B1: minor (deferred): no test that wrong access on revoked/expired share answers 404; host_offline 149/150 s boundary not pinned; requestIp imported from routes/auth.ts; bind UPDATE ignores changes; no SHARE_ALLOWED_ORIGIN override test; secret check after id parse on viewer route; slot UNIQUE collision → 500
Task B3: fix round 1 committed b691fca919 (A1 + strict seq/secret + tests); re-review dispatched
Task B5: review: spec ✅; Important: fake-api ignores one-time forcing (R5) and non-boolean one_time; fix round 1/5 dispatched (plus minors: id alphabet/lowercase, fake list order/filter, test naming)
Task B5: minor (deferred): create/list/revoke Swift wrappers block — callers (B6) must call off-main; fake models no requireDesktop/device cap
Task B3: fix round 1/5 (4 addressed, 0 open — A1 replay binding, strict seq, strict secret, drop-path tests; commits 6c2baaaa86..b691fca919)
Task B3: complete (commits f24057f44c..b691fca919, review clean; merged into shellx/l7-share)
Task B3: minor (deferred): setViewerNonce re-callable in stage 3, setters don't check 16 bytes; AAD uses re-encoded nonce (non-canonical peer base64 fails closed — B7 must send canonical); seq token check fail-open with nested seq (key holder only); fixedNonce cleared before size guard
Task B5: fix round 1/5 (4 addressed, 0 open; commits 584b05a5b6..f72704470e)
Task B5: complete (commits 6c2baaaa86..f72704470e, review clean; merged into shellx/l7-share)
Task B5: minor (deferred): 3 tests bind unused `fake` (warnings); no tests for non-boolean one_time 400, fake list expiry filter/order
Ruling: B8 fix round re-review done by the controller with a live nginx:alpine run of the branch's nginx.conf (curl: /s/k7f2-9qd1 and trailing slash → 200 with Referrer-Policy, CSP, Cache-Control no-store; /s/ → 404; /s/index.html → 301 → /s/ → 404; /s/k7f2 → 404) instead of a reviewer subagent — direct behavioural evidence for the single finding; cost if wrong: the test file's brace counting unreviewed (Minor).
Task B8: fix round 1/5 (3 addressed, 0 open; commits 6d366966bb..9c8cd02239)
Task B8: complete (commits f24057f44c..9c8cd02239, review clean; merged into shellx/l7-share)
Ruling: B6 starts off shellx/l7-share 086124d2b7 before B4 lands, coding against B4's brief interfaces (ShareSource, ShareHost, ShareSocketFactory) and merging shellx/l7-b4 once B4 is reviewed — speed; cost if wrong: adaptation when B4's final API differs.
Task B4: review: spec ✅; Important: unbounded output backlog for slow viewer; select(unknown pane) tears down stream. Fix round 1/5 dispatched (+ M1 paused pump, M3 pong timeout, M4 isExpired guards, M7 socket identity, M11 rotation-with-viewer test)
Task B4: minor (deferred): ticket retry until expiry after server revoke; type `in` accepted for any terminal pane; onPanesChanged single callback (B6 told: one source per host); no ready timeout; shared knownPanes size races; encoded() empty-string fallback; snapshot/subscribe atomicity belongs to B6 source
Ruling: (5) Wire amendment A2 — host keepalive `{"t":"ka","seq"}` after 60 s idle per circuit (relay idle close is 300 s); added to B4's fix round and B7's — cost if wrong: quiet view-only shares drop every 5 min.
Ruling: user asked again to speed up with more agents (2026-10-21). B9 starts now off shellx/l7-share 086124d2b7, merging shellx/l7-b4 / l7-b7 / l7-b6 as they are reviewed; a parallel "minors sweep" (branch shellx/l7-minors) fixes deferred minors of B1, B2, B5 (relay/, cmux-relay, shellx-core — files no running task touches) — cost if wrong: merge conflicts at integration.
Task B7: review: spec ✅ except gradient CTA (plan-mandated by "use Base"); Important: ticket fetch has no deadline (infinite spinner); xterm tap focuses its own textarea (keyboard on view-only, lost keys on type). Fix round 1/5 dispatched (+ A2 ka, gradient, Ctrl+V paste, swallowed errors, retry flash)
Ruling: the Base header's gradient "Tải về" CTA is hidden on /s/ via a Base prop — spec §7.4/plan "no gradients" outranks the brief's "use Base"; cost if wrong: one prop.
Task B7: minor (deferred): circuit closed before welcome → error not host_offline; relay_url accepts ws://; reload loses key (plan-mandated, mention in copy); shareApiBase vs B8 CSP connect-src cross-check test owed at integration
Minors sweep (B1/B2/B5): complete (commits 086124d2b7..7c5ba07378, review clean; merged into shellx/l7-share)
Minors sweep: minor (deferred): wrong comment v2-shares.test.ts:512; unreachable changes!==1 branch; body-first order 400 vs 404 unpinned; import placement app.ts; type-only import cycle client-ip.ts↔app.ts
Task B7: fix round 1/5 (7 addressed, 0 open; commits a81e7a4b1f..236c449ae7)
Task B7: complete (commits b691fca919..236c449ae7, review clean; merged into shellx/l7-share)
Task B7: minor (deferred): emit() stops at first throwing listener; isMac via navigator.platform; no-gradient check only on /s/ HTML not linked CSS; viewer can encode ka but never sends
Task B4: fix round 1/5 (8 addressed, 1 new Important — viewer select lost to concurrent internal reselect; commits 394a1fa24f..4f29fcf9b6)
Task B4: fix round 2/5 dispatched (select race + keepalive skip when backlog, resync on vanished pane)
Task B4: minor (deferred): non-droppable frames (replay tail, panes, size, ka) not counted against 1 MiB cap; select during resync can trip another resync
Task B4: fix round 2/5 (3 addressed, 0 open; commits 4f29fcf9b6..6cb4f6bc15)
Task B4: complete (commits b691fca919..6cb4f6bc15, review clean; merged into shellx/l7-share, duplicate ShareTicketProvider removed per ruling; package swift test 47 XCTest + 303 Swift Testing pass)
Task B4: minor (deferred): setSelectHook / isResyncing test seams not #if DEBUG
Task B9: DONE (8f8951939f..ccb801e737), 23/23 e2e checks; found BLOCKING interop bug: POST /v2/shares needs `access` derived from the id the API only returns afterwards.
Ruling: (6) the client proposes the share id — `POST /v2/shares` body gains required `id` (8 chars of the alphabet, dash optional); the API answers 409 `share_id_taken` on collision and the client retries with a new id (max 3); the HKDF salt stays the id (no wire/vector change). Done as Task B1b on branch shellx/l7-b1b (off l7-b9: API, shellx-core + fake, Swift createShare(id:), harness drops the shareId hook) — cost if wrong: API contract change before anything shipped.
Task B9: review: spec ✅ (Steps 1,2,4); Important: harness leaks cmux-relay + secret temp dir on SIGINT/timeout/uncaught; viewer one-line fix lacks deterministic unit test; revoke scenario scripts host stop (must be documented; app path is B6's). Fix round 1/5 dispatched (+ minors relay log, cargo PATH, tautological checks, redact tickets)
Task B9: minor (deferred): --secret/--token visible in argv (throwaway); API expiry rounded to seconds (≤1 s host_offline instead of expired)
Task B9: fix round 1/5 (4 addressed, 0 open; commits ccb801e737..bed26a8cac)
Task B9: complete (commits 2c09dc931e..bed26a8cac, review clean; Step 3 phone dogfood not done — needs user + tagged build; merged into shellx/l7-share)
Task B9: minor (deferred): exit code race 1 vs 130/143; double Ctrl-C to node directly can leak; A2 keepalive not exercised e2e
Task B1b: review: spec ✅; Important: no-retry-on-other-errors test asserts nothing; fix round 1/5 dispatched (+ comment truth, PK→409 mapping, fake check order, stale docs)
Task B1b: minor (deferred): alphabet/generator duplicated in relay test + e2e harness; no RED commits before fixes (process note); flaky ShareHostTests.testExpiredShareRefusesWelcomeAndInput once under full load
Task B1b: fix round 1/5 (5 addressed, 0 open; commits 96cf5a183e..702fff2509)
Task B1b: complete (commits dad7bb3ac6..702fff2509, review clean; merged into shellx/l7-share)
Task B1b: minor (deferred): route-level PK race catch covered only via predicate test
User (2026-10-21): finish B6 (1) + final review (2), merge into main LOCALLY, do NOT push main — user runs the G2 FK pre-check on a copy of relay.db, then pushes main (or tells me to). Phone dogfood (3) and production gates (4) are the user's, later.
Task B6: DONE_WITH_CONCERNS (a54acf75b2..cde7ceaca0); review: Important — quit cleanup never runs on deferred quit path; sign-in tied to remote gate (R1 gap); links don't resume after relaunch (§7.3, plan-mandated omission); expired shares linger in list.
Ruling: (R1b) until account/sign-in moves out of ShellXRemoteService, ShellXShareGate also requires ShellXRemoteGate — the alternative (splitting account out) is a larger refactor; cost if wrong: flipping shareLinks needs remoteMachines too.
Ruling: (7) §7.3 resume-after-relaunch is binding though the plan omitted it — added to B6 fix round: Keychain-persisted 15m/1h shares re-hosted on launch; until_quit/one-time never persisted — cost if wrong: one store type.
Task B6: fix round 1/5 dispatched (I1-I4 + M1, M3, M4, M6, M7, M8)
Task B6: minor (deferred): claimed phone share has no revoke UI and sleeping phone revoked on popover close (M2); closing a workspace leaves its shares running (M5); §7.3 layout freezes permission/lifetime after create (M9, product ruling); snapshot/subscribe byte gap (known limitation); not yet seen in a running tagged build (user dogfood, item 3)
Final review (non-B6, b1c519dd11..3d254b10e7): Ready after fixes — I1 relay2 compose pin 57dd520ccf predates the Origin allowlist (prod viewers 403); I2 viewer adopts host `panes.active` as its selection + host accepts `in` for any terminal pane (blind typing); owed B7 CSP connect-src cross-check test. Minors: no live-viewer traffic watchdog; CSP lacks base-uri. All other deferred minors triaged can-wait.
Final fix wave dispatched on shellx/l7-final (one fixer, all findings)
Task B6: fix round 1/5 (10 addressed, 2 new Important — resumed share revoked server-side retries forever as ghost; orphan revoke races deferred session restore; commits cde7ceaca0..a7e8f44041)
Task B6: fix round 2/5 dispatched (+ sign-out stops shares / per-account store; quit during in-flight revoke)
Task B6: minor (deferred): gate-off launches never purge stale Keychain entries; no app-level RED run; Keychain path untested (-34018 on unsigned builds degrades to no resume)
Final fix wave: 5 addressed, 0 open (commits 3d254b10e7..eae05fd9a1); merged into shellx/l7-share
Final: minor (deferred): viewer stuck with active=null if its selected pane closes while select in flight (recover by clicking a pane); keystrokes for new pane dropped while superseded reselect commits; App Nap vs 30 s watchdog slack unverified (dogfood with host hidden); HANDOFF-native-desktop.md:41 stale 57dd pin note; compose ancestry test fails in shallow clones
Task B6: fix round 2/5 (4 addressed, 0 open; commits a7e8f44041..631747b910, merge e8647ea436)
Task B6: complete (commits 3d254b10e7..e8647ea436, review clean; merged into shellx/l7-share)
Task B6: minor (deferred): create awaiting mint during sign-out attaches ghost host; signedOut doesn't API-revoke until_quit/one-time shares; saveOwner failure keeps previous account owner; pre-change Keychain item "active-share-links" never deleted
