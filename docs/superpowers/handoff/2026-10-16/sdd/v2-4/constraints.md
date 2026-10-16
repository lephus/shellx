# Binding constraints for every V2-4 implementer and reviewer (read completely)

Worktree: /Users/richard/Documents/helper/shellx/.claude/worktrees/v2-4 (branch `v2-4`). cd there for EVERY command. Never touch MAIN (/Users/richard/Documents/helper/shellx) files except writing your report into the SDD workspace; never touch another worktree (.claude/worktrees/v2-2b, v2-3, scratchpad worktrees).

## A. Session-wide constraints (from the track controller)


- Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart`. The Bash tool prints a harmless `.zshenv` "unmatched `" line: ignore it; never read, print or edit `~/.zshenv` or any dotfile or credential file.
- `pubspec.lock` files are git-ignored: never `git add` them. After any macOS desktop build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock` (`git -C <worktree> checkout -- apps/desktop/macos/Podfile.lock` only if that line is the sole change; otherwise restore just that line). The mobile iOS `Podfile.lock` keeps `COCOAPODS: 1.16.2` as the plan says.
- Product naming: "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- ShellX never reads, stores or relays credentials; never `--hide-claude-auth`; no `SHELLX_*` variable (e.g. `SHELLX_CLI_TOKEN`) in an agent's environment.
- Never auto-allow a permission request; never re-apply a remembered no-approval mode; no path in which a phone answers without a user tap.
- No content in logs; `toString()` of new messages/records is `Name(…)`, pinned by tests.
- Never `pkill`/`killall` or kill any process the agent did not start itself (other tracks run Flutter tests on this machine at the same time). If a test fails only by a timeout while the machine is busy, re-run that file once before treating it as real.
- The app is never launched on the user's real data. Any launch or integration test of the desktop app uses an isolated copy: bundle id `pro.shellx.desktop.smoketest`, a temporary HOME and `CFFIXED_USER_HOME` — recipe in `SCRATCH/smoke/run.sh` (read it before any launch).
- No destructive git: no `push` of any kind, no `--force`, no `reset --hard` on anything but the worktree's own uncommitted changes, no `git clean -fdx`, no branch deletion, no `rebase` of commits already reviewed. No merges into `shellx-v2` or `main` — the top-level controller does those.
- Commit messages: conventional style as the plan says; each ends with the committing model's own trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (sonnet), `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (opus). Where the plan writes a fixed trailer, use the committing model's own instead.
- Keep reads and writes inside `MAIN` (and its `.claude/worktrees/…`) and `SCRATCH`; reads elsewhere may be refused by the permission system. Pub-cache sources may be read with `sed -n`/`grep` through Bash when a task needs a plugin's API.
- No Artifacts, no external services, no network except `flutter pub get`/`npm ci` and what tests start locally.


## B. The plan's Global Constraints (docs/superpowers/plans/2026-10-15-v2-4-tools-phone.md)

- **Branch and scope:**
  - Worktree `.claude/worktrees/v2-4`, branch `v2-4` (from `shellx-v2`); commit there, **never push** (a push to `main` starts a desktop release; the controller merges and pushes).
  - Never touch `relay/` (no relay change in V2-4) and never the AI session model (`packages/shellx_ai`, `packages/shellx_acp`, the `ai.*` hub).
  - `packages/shellx_core/lib/src/protocol/` only gains files and lines (spec header).
- **Toolchain:** Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart` (Flutter 3.41.4 / Dart 3.11.1). After a `pubspec.yaml` change: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the repo root.
- **Pins:** `webview_flutter: 4.14.1`, `webview_flutter_android: 4.12.0`, `webview_flutter_wkwebview: 3.25.1` (exact); `cryptography: ^2.9.0` in `shellx_client` (already in the workspace).
- **Lock files:** `pubspec.lock` files are git-ignored: never `git add` them. After a macOS build, revert the `COCOAPODS:` line change in `apps/desktop/macos/Podfile.lock` (do not commit it); the same for `apps/mobile/ios/Podfile.lock` after an iOS build (Task 12 commits only the lines `pod install` adds for `webview_flutter_wkwebview`).
- **Protocol values (exact):**
  - `kToolProtocol = 1` (`tools` in `session.list.result`, only for `session.list {desktop: true}`, only while the process serves tools);
  - `kToolMaxChunkBytes = 48 * 1024` (data of `tool.data`/`tool.ws.msg`; `body` of `tool.list.result`/`tool.opened`); `kToolMaxHeadBytes = 32 * 1024` (UTF-8 of names and values); `kToolMaxHeaders = 100`; `kToolMaxTargetBytes = 8 * 1024`; `kToolMaxMethodLength = 16`;
  - wire keys: `t`, `available`, `body`, `rid`, `tool`, `ok`, `code`, `id`, `m`, `target`, `head`, `alias`, `ws`, `end`, `status`, `data`, `acks`, `text`, `fin`, `ws_code`, `ws_reason`;
  - end codes: `refused`, `disabled`, `gone`, `busy`, `too_large`, `timeout`, `desktop_closed`, `unavailable`, `aborted`, `bad_request` (an unknown one reads `aborted`);
  - every `tool.*` message is checked `encodeBatch([m]).length ≤ kMaxSealedBatchBytes` before it is queued, on both sides.
- **Flow (E7, E8):** `kToolStreamWindow = 256 * 1024` per stream per direction, `kToolPhoneWindow = 512 * 1024` per phone per direction, cumulative acks of every stream in one `tool.ack` at most every `kToolAckInterval = 50 ms`; desktop tool data ≤ 8 MiB/s (burst 1 MiB) and ≤ 150 frames/s (burst 16) for the whole computer; `AgentChannel` flushes at once when pending tool data reaches 48 KiB; phone tool frames ≤ 100/s (burst 10), collected 16 ms. A full window stops reading the source; a byte is never dropped.
- **Limits (E10):** ≤ 32 HTTP and ≤ 16 WebSocket streams per phone; stream opens (`tool.open`, `tool.req`) 120 at once then 60/s, else `busy`; request body ≤ 64 MiB (413); WebSocket message ≤ 16 MiB (close 1009); connect ≤ 5 s (`refused`); response head ≤ 60 s (`timeout`, 504); no limit once streaming; no ack for 5 min with bytes in flight: dropped.
- **Gate (E11):** the phone binds loopback only (`InternetAddress.loopbackIPv4`, `loopbackIPv6` with `v6Only: true`), never `any`; `Host` must be `localhost`, `127.0.0.1` or `[::1]` with the served port; entry URL `http://localhost:<port>/__shellx/enter?n=<one-time nonce, 10 s>&to=<start page>` answers 303 with `Set-Cookie: __shellx_<port>=<128-bit secret>; Path=/; HttpOnly; SameSite=Strict`, `Cache-Control: no-store`, `Referrer-Policy: no-referrer`; every other request needs the cookie (constant-time compare) except a CORS preflight of a served origin (R6); `/__shellx/` is never sent on; gate cookies are stripped before forwarding and a tool's `Set-Cookie` of `__shellx_*` is dropped; WebSocket upgrades and unsafe methods: an `Origin` must be a served origin, `Sec-Fetch-Site: cross-site` gets 403; `defaultResponseHeaders.clear()`, `serverHeader = null`.
- **Desktop destination (E9):** connect only to 127.0.0.1 then ::1 on the tool's port (`connectToolPort`), never resolve a name; `findProxy` DIRECT; `followRedirects = false`; `autoUncompress = false`; `userAgent = null`; URLs built with `Uri(scheme: 'http', host: '127.0.0.1', port: P, path: …, query: …)`, never concatenated; the phone flag is checked at every stream open; turning it off, deleting the tool or changing its URL ends its streams (`disabled` / `gone`).
- **Product naming:** "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **Never:** read, store or relay credentials; pass `--hide-claude-auth`; put `SHELLX_*` variables in an agent's environment; auto-allow a permission; add a JavaScript channel into the app (no `addJavaScriptChannel`); grant a web permission (camera, microphone, location).
- **Privacy (E18):** content (URLs, paths, headers, cookies, bodies) travels only inside the end-to-end channel; nothing logs it, errors included (only `error.runtimeType`). `toString()` of every `tool.*` message is `'<Type>(…)'`; of `ToolInfo`, `ToolListing`, `ToolServing`, `ServedTool`, `ToolCatalog`, `ToolForwardedHead`, `ToolSession`, `ToolLoad` it is `'<Type>(…)'`; each pinned by a test.
- **Old peers (E19):** a new message decodes to `null` on any failure and never drops the channel; the desktop sends `tool.*` only to a phone that sent `tool.*` first; `tools` in `session.list.result` and `tools` in the background service's `hello.caps` gate everything; a frozen copy of the V2-2 decoder (`d8ad686`) pins the compatibility tests.
- **Strings:**
  - mobile: `apps/mobile/lib/l10n/intl_en.arb` + `intl_vi.arb` (same keys; `test/l10n_test.dart` checks), generated with `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate`, then `PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart` (the generator writes width 80; the repo keeps width 120);
  - routes and DI: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs` in `apps/mobile`; generated files are committed;
  - the desktop gets no new string in V2-4.
- **Formatting:** format only the files a task touches (`dart format <files>`; mobile page width 120 from its `analysis_options.yaml`). Never run `dart format` on a whole directory with files the task does not own.
- **Every task ends green:** the touched packages' `analyze` clean and their tests passing. Commands (from the package directory):
  - `packages/shellx_core`, `packages/shellx_agent`, `packages/shellx_client`, `packages/shellx_e2e`: `~/fvm/versions/3.41.4/bin/dart analyze` and `~/fvm/versions/3.41.4/bin/dart test` (pure Dart packages);
  - `apps/mobile`, `apps/desktop`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`.
- **Commits:** `feat(v2-tools): …` / `test(v2-tools): …` / `docs(v2-tools): …`, at least one per task, ending with the implementer's model trailer (e.g. `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).
- **No real data:** any app launch or integration test uses a copy with another bundle id and a temporary HOME (the session's `scratchpad/smoke/run.sh` recipe: bundle id `pro.shellx.desktop.smoketest`, `CFFIXED_USER_HOME`). Never `pkill`/`killall`: stop only processes you started, by PID.

## C. The plan's Review Focus (spec §9)

Spec §9, each pinned by tests in the task that owns the code.

1. **One oversized message drops the whole channel** (terminals and AI too): a very long header, a big cookie, a large WebSocket message. Pinned by: Task 1 "the largest message of each kind fits one sealed batch (RF 1)"; Task 5 "a response head over 32 KiB: too_large", Task 6 "a message over the limit closes with 1009, either way"; Task 8 "a message over one sealed batch is refused; the channel stays"; Task 9 "a head over the limits is answered 431 here; nothing goes to the computer"; Task 10 "no frame over 64 KiB".
2. **The relay closes a connection for more than 500 frames a second**, on the desktop (every phone drops) or the phone (every machine drops): a Vite page with hundreds of modules, a big download on a fast network. Pinned by: Task 3 "≤ 150 frames and ≤ 8 MiB per second, whatever is asked", "small frames are limited by count"; Task 5 "50 MB arrive whole … ≤ 150 frames and ≤ 8 MiB a second"; Task 8 "at most 100 tool frames a second, in order, none lost"; Task 10 "the computer well under the relay's 500 frames a second" (in-process) and the real-relay test.
3. **Data lost when a window is full** (the terminal's "ring, then reset" copied by mistake). Pinned by: Task 3 "never more than the window in flight; the source pauses and every byte arrives once, in order", "streams share the phone's 512 KiB"; Task 5 "50 MB arrive whole (SHA-256)"; Task 10 "8 MB through the tunnel: whole" and 50 MB over the real relay.
4. **Reaching something that is not the tool** through the request target, `Host`, a redirect or `http_proxy`. Pinned by: Task 2 target, method and head rules; Task 5 "a target that is not origin form, a forbidden method, CRLF in a header", "a foreign Host is replaced", "http_proxy is ignored", "a 3xx is not followed", "a tool on ::1 only is reached; a name is never resolved", "a tool not on the list: disabled when its flag is off, gone otherwise; never by URL".
5. **Another app on the phone** calling the loopback port, or a page of another origin (DNS rebinding). Pinned by: Task 9 "without the cookie, with another Host, or with an expired entry: 403", "/__shellx/ is the phone's own", "an unsafe request from another origin, or cross-site, is refused", "a WebSocket without the cookie: 403"; Task 13 "another site asks first", "a local port that is not served is named".

## D. Harness and chunk-2 rules (binding)

- Run every test, analyze and build command in the foreground (Bash timeout up to 600000 ms; if a suite would take longer, split it by directory). Never use `run_in_background`, and never end your turn while a command you started is still running. End your run only by delivering your report.
- No launches: never launch the desktop app or a mobile simulator/device app unless your task's own text requires it (none of Tasks 8–14 does). Never touch the `pro.shellx.desktop` preferences domain.
- iOS `apps/mobile/ios/Podfile.lock` keeps `COCOAPODS: 1.16.2`; new pod lines from `webview_flutter` are committed; revert any change to the `COCOAPODS:` line.
- Counts run above the plan's totals (earlier tasks added controller-ruled tests): shellx_core 404 (plan 395), shellx_agent 962 (plan 955), shellx_client from Task 9 on (Task 9 adds tests beyond the plan). Treat the plan's "a → b" counts as deltas; run the suite once before you start and note the number.
- Flakes: other tracks run Flutter/Dart suites on this machine. A failure that is only a timeout gets one re-run of that file alone before it counts (notably shellx_core "path performance" and the shellx_agent Task 5 fix-A idle test).
- Name clash: `ToolEnd` (shellx_core message) vs `enum ToolEnd` in `packages/shellx_ai/lib/src/model/timeline.dart`; a file importing both that names `ToolEnd` needs `hide ToolEnd` on the shellx_ai-side import.
- Scratch hygiene (top-level, binding from 2026-10-15 23:40), with SCRATCH = /private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad: Make your own temp folder with `mktemp -d "$SCRATCH/tmp.XXXXXX"` (SCRATCH as given), keep every temporary file (backups, mutation copies, logs) inside it, and remove only that folder. Never `rm -rf` or overwrite a path you did not create in this dispatch, and never write loose files at the SCRATCH root. Back up files under test with `git stash`/`git checkout -- <file>`, or copy them into that temp folder; never rely on a fixed shared name such as `SCRATCH/bak`.

## E. Chunk 3 (Task 14b, Tasks 15–16, final review) — added 2026-10-16

- HEAD at chunk start: 50cfd1b (chunk 2 end d127c04 + V2-3 Task 1 cherry-picked: ab82735, 50cfd1b — V2-3's own files; reviewed on V2-3).
- Counts at 50cfd1b: shellx_core 404, shellx_agent 962, shellx_client 218, shellx_e2e 16 passed + 10 skipped (no relay), apps/mobile 1355 (+ the pre-existing info), apps/desktop: see the ledger's "Chunk 3 baseline" (3581 + 6 skipped at d127c04, plus V2-3 Task 1's tests). The plan's "a → b" counts are deltas; reviewers must not flag the offsets.
- Top-level rulings S1 and S2 (verbatim: `s1-s2-rulings.md` in this workspace) amend the CSP (`form-action` without `https:`) and the phone's binding (IPv4 alone only when no `::1` is listed).
- No launches. Only Task 16 builds the apps (`flutter build apk --debug`, `flutter build ios --debug --no-codesign`) and never runs them. Never touch `~/Library/Preferences/pro.shellx.desktop*`.
- iOS `apps/mobile/ios/Podfile.lock` keeps `COCOAPODS: 1.16.2`; revert any change to that line.
- Section D's harness and scratch-hygiene rules apply unchanged.
