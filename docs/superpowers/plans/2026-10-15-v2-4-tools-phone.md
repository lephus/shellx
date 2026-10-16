# ShellX V2-4 — Personal web tools on the phone (`tool.*` tunnel) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Away from the desk, the user opens a personal web tool of the computer (a board, a dashboard, the dev build of the product running on `localhost`) on the phone and uses it like on the computer — clicks, typing, live updates over WebSocket — through the existing end-to-end encrypted channel only: the computer reaches nothing but the port of a tool the user turned on for the phone, the phone serves the page on its own loopback to its own web view only, and old phones and old desktops keep working exactly as today.

**Architecture:**
- **Protocol (`shellx_core`).** Eleven flat `tool.*` messages, a `part` of `messages.dart` like `ai.*`: headers are a flat `head` list `[name, value, …]`, bodies and WebSocket payloads are CBOR byte strings, so the transport sees depth 3 and never a float. A `tool.*` message this version cannot read is skipped, never fatal. `session.list.result` gains `tools: 1`. Shared by both ends (also in `lib/src/protocol/`): the request rules of E9 (method, origin-form target, head limits, hop-by-hop headers, the gate cookie, loopback spellings) and the flow control of E7 (per-stream 256 KiB and per-phone 512 KiB windows with cumulative acks, acks of every stream in one `tool.ack` per 50 ms, a token pacer, byte and WebSocket outlets that **stop reading their source** when they cannot send and inlets that report what their sink took). `splitIntoBatches` moves here so the phone's tool outbox and the desktop's channel share it.
- **Desktop proxy (`shellx_agent`, pure Dart).** `ToolProxy` implements `ToolEndpoint`: it lists the tools the window serves (`ToolCatalog`), checks the phone flag at every stream, and carries HTTP requests and WebSockets to the tool's port on this computer only — a pinned `HttpClient` (127.0.0.1 then ::1, never a name, `findProxy` DIRECT, no redirects, no unpacking), validated method/target/head, `Host`/`Origin`/`Referer`/`Location`/`Access-Control-Allow-Origin` rewritten in alias mode (E3), all tool data paced for the whole computer (≤ 8 MiB/s, ≤ 150 frames/s), the limits of E10, its own WebSocket handshake (so a refusal reaches the phone as HTTP and an abort can drop the socket). `SessionRouter` routes `tool.*` to an optional `ToolEndpoint`; `ToolEndpointSlot` lives for the process in `SessionCore`. The proxy runs in the process that holds the relay (E5): the window in-process, the background service otherwise, which takes the window's list over the mux (`tool.serve`, no `q`) and says `tools` in `hello.caps`.
- **Phone (`shellx_client`).** `MachineTools` (on `MachineClient`): the list (`tool.list`), `tool.open`, routing of stream messages, and the tool outbox (16 ms, `splitIntoBatches`, ≤ 100 frames/s). `ToolSession` (pure `dart:io`, unit-tested with real sockets): the phone's loopback servers for one open tool (127.0.0.1 and [::1] on the tool's own port, else another, E3; the other tools of its workspace on their ports, E4), the one-time entry URL and HttpOnly/SameSite gate cookie, `Host`/`Origin`/`Sec-Fetch-Site` checks, `/__shellx/` reserved, default headers cleared, HTTP and WebSocket bridged through `MachineTools`, and its life (E13).
- **Mobile (`apps/mobile`).** `webview_flutter` 4.14.1: the tool page `ToolRoute` (bar, thin progress, states of E16, navigation policy of E12, lifecycle of E13, the page's dialogs titled with the tool's name, no JavaScript channel, permissions denied), the Tool group in the session picker, Settings › "Xóa dữ liệu của tool"; iOS `NSAllowsLocalNetworking`, Android cleartext only for `localhost` and `127.0.0.1`.
- **Desktop window (`apps/desktop`).** The agent side gets the slot and the background service its proxy (independent of V2-3). The window's wiring (Task 15) builds the phone list from V2-3's `toolRegistryProvider` and serves it in-process or pushes it to the background service.

**Tech Stack:** Dart 3.11.1 / Flutter 3.41.4 (`~/fvm/versions/3.41.4/bin`, not on PATH); `dart:io` `HttpServer`, `HttpClient`, `WebSocket`; `package:test`, `fake_async`, `flutter_test`; `cryptography` 2.9 (SHA-1 for the phone's WebSocket accept, SHA-256 in a test); `webview_flutter` 4.14.1 + `webview_flutter_android` 4.12.0 + `webview_flutter_wkwebview` 3.25.1 (the newest on Flutter 3.41.4); signals + get_it + injectable + auto_route + intl_utils on mobile (generated code is committed); Riverpod on desktop.

**Spec:** `docs/superpowers/specs/2026-10-15-v2-4-tools-phone-design.md` (binding, Vietnamese; decisions E1–E22, §4 protocol, §5 request flow, §6 strings, §7 edges, §8 tests, §9 Review Focus, §10 manual checks). Also binding: spec V2-3 `docs/superpowers/specs/2026-10-15-v2-3-tools-desktop-design.md` D1, D2, D15 (the tool model and the phone flag; its interface is copied in "Shared interface with V2-3" below) and spec V2-2 `docs/superpowers/specs/2026-10-14-v2-2-phone-ai-design.md` §4 (the `ai.*` family this copies). Research notes with `file:line` pointers: `.superpowers/sdd/2026-10-15-v2-4-tools-phone/v2-4.md` (§1.7, §1.10 hook points; §6 security checklist).

## Prerequisite and how this plan was made

Work in the worktree `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-4` on branch `v2-4`, made from `shellx-v2` (the plan was written against `38a786d`; `shellx-v2` has since gained only a release workflow and docs, which this plan does not touch). **Never push:** a push to `main` starts a desktop release (`release-desktop.yml`); the controller merges and pushes.

**Tasks 1–14 and 16 do not need V2-3.** Task 15 (the desktop window's wiring) **needs V2-3 Task 1** (`apps/desktop/lib/src/tools/tool_entry.dart` and `tool_registry.dart`, interface below): before Task 15 starts, the controller cherry-picks V2-3 Task 1's commit into `v2-4`. Task 15 is placed after every task that does not need it. If V2-3 landed with other names, change the call in Task 15, not V2-3, and record it in the ledger.

V2-2b and V2-3 are implemented in parallel and touch some of the same files: V2-2b `ai_messages.dart`/`messages.dart` (`kAiProtocol` 2), `machine_client.dart`, the mobile picker and terminal page; V2-3 adds `webview_flutter` 4.14.1 and `webview_flutter_wkwebview` 3.25.1 to the desktop (the same pins as here: one workspace resolution). Every edit below is additive; if they landed first, put the V2-4 lines next to theirs, never revert theirs.

**How this plan was checked (2026-10-15).** Every task was written and run in a throw-away worktree at `38a786d` (`flutter pub get --offline`); the code below is that code, formatted with `dart format`. Task 15 was checked against stand-ins of V2-3's two files written exactly to the interface below. Results with all tasks applied:
- `shellx_core` 351 → 395 tests;
- `shellx_agent` 916 → 955;
- `shellx_client` 159 → 185 (includes the in-process end to end);
- `shellx_e2e` 16 passed, 10 skipped without a relay; the new real-relay test passed against `npm run dev` (50 MB through the tunnel in 17 s, no rate-limit event in the relay log);
- `apps/mobile` 1262 → 1285 (analyze: only the pre-existing `unnecessary_import` info in `test/features/terminal/ime_in_place_edit_test.dart`);
- `apps/desktop` 3574 → 3580, 10 skipped; analyze clean;
- `shellx_acp` 87 and `shellx_ai` 576, unchanged;
- both apps build: `flutter build apk --debug` (70 s) and `flutter build ios --debug --no-codesign` (60 s); nothing was launched.

Timing-sensitive pre-existing test: `packages/shellx_core/test/util/terminal_links_test.dart` "path performance" can fail on a busy machine; rerun it alone before suspecting a change.

## Shared interface with V2-3 (consumed by Task 15, produced by V2-3 Task 1)

`apps/desktop/lib/src/tools/tool_entry.dart`:

````dart
/// V2-3 D1/D2: a personal tool — a name and an http(s) URL in a workspace.
final class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.ws,
    required this.name,
    required this.url,
    this.phone = false,
  });

  final String id;   // 10 chars [a-z0-9], stable for the tool's life
  final String ws;   // workspace id (Workspace.id)
  final String name; // ≤ 60 chars, never empty
  final String url;  // normalised by parseToolUrl: http/https, host, no userinfo, no fragment
  final bool phone;  // V2-3 D15 flag

  Uri get uri;
  String get origin;        // scheme://host:port (port always explicit)
  int get port;             // effective port
  bool get isLocal;         // V2-3 D11 local class
  bool get phoneAllowed;    // http and host in {localhost, 127.0.0.1, ::1}
  bool get phoneOn => phone && phoneAllowed;

  ToolEntry copyWith({String? name, String? url, bool? phone});
  Map<String, Object?> toJson();
  static ToolEntry? fromJson(Object? json); // never throws; null for a bad entry
  @override String toString() => 'ToolEntry(…)';
}
````

`apps/desktop/lib/src/tools/tool_registry.dart`:

````dart
final toolRegistryProvider =
    NotifierProvider<ToolRegistry, List<ToolEntry>>(ToolRegistry.new);

class ToolRegistry extends Notifier<List<ToolEntry>> {
  // persisted in SettingKeys.workspaceTools ('workspace_tools'), a UI-owned key
  ToolEntry? add({required String ws, required String name, required String url, bool phone = false});
  void update(ToolEntry entry);
  void remove(String id);
  void removeWorkspace(String ws);
  ToolEntry? byId(String id);
  List<ToolEntry> inWorkspace(String ws);
}
````

V2-4 builds the phone list from `ref.watch(toolRegistryProvider)` filtered by `phoneOn`, with each tool's workspace name from `sidebarWorkspacesProvider` (`Workspace.displayName`).

## Rulings (each with "cost if wrong")

Task 1 copies these into the ledger.

- **R1 — the shared rules and flow control live in `shellx_core/lib/src/protocol/`** (the only `shellx_core` directory the spec lets V2-4 change, additions only): `tool_messages.dart` (part), `tool_rules.dart`, `tool_flow.dart`, `batches.dart`. Both ends use one implementation of E7 and E9. *Cost if wrong:* two files to move later.
- **R2 — `ToolEndpoint.serving`:** `session.list.result` carries `tools` only while the process's slot has a proxy (E6 "chỉ khi tiến trình có proxy tool"). Until Task 15 lands, an in-process window advertises nothing; a background service (Task 11) advertises and answers `available: false` until a window pushes a list. *Cost if wrong:* between Task 11 and Task 15, a phone on a background-service computer shows "Mở ShellX trên máy tính để dùng tool.".
- **R3 — `tool.serve` also carries `off`: the ids of the tools that exist with the phone flag off** (never their URLs or names, never sent to phones), so a stream of one of them ends `disabled`, of an unknown id `gone` (§7). An older service ignores the key. *Cost if wrong:* a disabled tool reads "deleted".
- **R4 — a tool page learns that its tool was turned off or deleted from the list:** while a page is open the phone watches `tool.list`; when its tool leaves the list (or changes port) the page asks `tool.open` again and shows the computer's answer (`disabled`, `gone`, `refused`…). Criterion 5 (≤ 1 s) then holds with no request in flight. *Cost if wrong:* one `tool.open` per list change.
- **R5 — binding (E2, E3, E4):** the phone binds 127.0.0.1 on the tool's port and, when it can, [::1] on the same port (`v6Only`); if 127.0.0.1 is taken (or the port is below 1024 where the OS forbids it) it binds an ephemeral port P′ (E3). The other tools of the workspace are served only on their own ports, skipped when taken. *Cost if wrong:* a sibling whose port is taken on the phone is unreachable from the page.
- **R6 — one gate per page:** one 128-bit secret and one cookie name `__shellx_<served port>` for every server of the page (cookies ignore ports, RFC 6265). A CORS preflight (`OPTIONS` with an `Origin` of a served port and `Access-Control-Request-Method`) passes without the cookie — preflights never carry cookies, and E4 cross-port calls need them. A cross-port call that sends no credentials (`fetch` without `credentials: 'include'`) gets 403, like E11's `credentials: 'omit'`. *Cost if wrong:* a local app can send an `OPTIONS` request to a served tool; a frontend calling its API port without credentials must use its dev server's proxy (most Vite apps do).
- **R7 — the desktop makes its own WebSocket handshake** (pinned `HttpClient` request with `Upgrade`, its own `Sec-WebSocket-Key`, then `detachSocket` and `WebSocket.fromUpgradedSocket`), and the phone writes its own `101` (accept computed with SHA-1) and detaches the socket: a refusal reaches the webview as the tool's HTTP answer, an abort can destroy the socket, and permessage-deflate is off on both hops. *Cost if wrong:* ~40 lines instead of `WebSocket.connect`.
- **R8 — headers through `dart:io`:** names arrive lower-cased; a value with a byte outside visible ASCII and tab is left out when written (`HttpHeaders.add` throws on obs-text); several `Cookie` values are joined with `; ` into one header (`dart:io` folds with `, `, which breaks cookies). *Cost if wrong:* a header with raw non-ASCII bytes does not reach the tool.
- **R9 — pacing (E7):** every `tool.data`/`tool.ws.msg` the desktop sends with bytes costs one frame token (150/s, burst 16) and its bytes (8 MiB/s, burst 1 MiB, may go one frame into debt); control messages ride the channel's batches free. Requests are granted in order. *Cost if wrong:* a WebSocket of many tiny messages gets at most 150 messages a second across the computer.
- **R10 — the phone's tool outbox** collects for 16 ms, splits with `splitIntoBatches`, and sends at most 100 batches a second (a token comes back every 10 ms, burst 10); a message that would not fit one sealed batch is refused, never queued. *Cost if wrong:* uploads top out near 4.8 MiB/s.
- **R11 — `bufferOutput = false`** on every response the phone writes to the web view and every upload the desktop writes to a tool: `dart:io` otherwise holds up to 8 KiB until the end, and SSE or a slow page would stall. *Cost if wrong:* more, smaller socket writes.
- **R12 — a WebSocket message over 16 MiB (E10) is refused once received:** `dart:io` 3.11 has no `maxPayloadLength` and gives a message only whole. *Cost if wrong:* one huge message is in memory once before it is refused; use `maxPayloadLength` after a Flutter upgrade.
- **R13 — `too_large` before a response head means the tool's head was over 32 KiB** (§7): the phone answers 502 "Phản hồi của tool quá lớn."; the phone answers 413 itself for a body over 64 MiB (from `Content-Length`, or counted as it streams). *Cost if wrong:* none known.
- **R14 — strings:** §6's keys and words, plus `toolReload`, `toolReconnecting` (E15, E16), `toolResponseTooLarge` (§7), `toolDialogTitle` and `toolClearDataPhoneConfirm` (V2-3's wording for the same things). Vietnamese puts the tone of an open "oa" on its first vowel ("xóa"), as every other mobile string does (V2-2's l10n test enforces it for AI texts); the spec writes "xoá". *Cost if wrong:* five more keys; one accent placed the app's way.
- **R15 — `webview_flutter` 4.14.1, `webview_flutter_android` 4.12.0, `webview_flutter_wkwebview` 3.25.1 pinned exactly** (newer ones need Dart 3.12); the platform packages are direct dependencies for their settings (Android file chooser, geolocation off). *Cost if wrong:* bump all three with Flutter.
- **R16 — navigation (E12):** a main-frame navigation to another loopback spelling of a served port (`127.0.0.1`, `[::1]`) is loaded as `localhost` instead (the gate cookie lives there); one to an unserved local port is stopped and named in a toast ("Tool ở cổng 8000 chưa bật cho điện thoại."); frames inside the page go where the page says. *Cost if wrong:* none known.
- **R17 — what cannot be done on the phone yet (E12):** a response with `Content-Disposition: attachment` shows "Tải tệp chưa làm được trên điện thoại." (the page still gets it); Android's file chooser gets no file and the same toast; iOS's WKWebView file input is not intercepted (no API); a crashed web content process reloads on iOS (`webContentProcessTerminated`) — `webview_flutter_android` 4.12.0 exposes no `onRenderProcessGone`. *Cost if wrong:* §10 manual checks find the gaps.
- **R18 — a lost channel keeps the page and its servers:** requests get 503 meanwhile, the page shows "Đang kết nối lại…"; a new channel asks `tool.open` again and reloads the page. Servers close only when the app goes to the background, the page is left, or the tool is off/gone/unavailable. *Cost if wrong:* a page open over a long outage keeps its ports.
- **R19 — refused:** a request of the page's tool answered `refused` makes the page ask `tool.open` again; while the port refuses the page shows E16's text and tries again after 1, 2, 4, 8 s, then every 10 s (V2-3 D13), and reloads when it answers. *Cost if wrong:* one `tool.open` per refused request at most (one at a time).
- **R20 — end to end in two places:** `packages/shellx_client/test/tools_e2e_test.dart` (both sides in one process over the in-memory relay and the real encrypted channel, always run) and `packages/shellx_e2e/test/tools_e2e_test.dart` (the same flow plus 50 MB over the real relay, run when `SHELLX_E2E_RELAY` is set, like every relay test there). *Cost if wrong:* one more test file.
- **R21 — one machine plays both sides in tests:** the tool listens on [::1] and the proxy reaches [::1] only (`ToolProxy(connect: …)`), so the phone's server can hold 127.0.0.1 on the tool's own port (same-port mode, E2); alias mode is tested with the tool on 127.0.0.1. *Cost if wrong:* none (production uses `connectToolPort`).
- **R22 — Settings › "Xóa dữ liệu của tool"** asks first, then clears the web view's cookies, cache and local storage (the app's web views are only tool pages). The new row moves "Đăng xuất" below the fold of `test/app_test.dart`'s phone: that test now scrolls rows until they can be tapped (`.hitTestable()`). *Cost if wrong:* none.
- **R23 — the tool page is one page at a time:** a `ToolRoute` is pushed over the machine page, and leaving it closes its servers, so two machines' tools never compete for one port in practice (§7). *Cost if wrong:* opening a second machine's tool on the same port while the first page is still open would take another port (E3) instead of closing the first.

## Global Constraints

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

## Review Focus

Spec §9, each pinned by tests in the task that owns the code.

1. **One oversized message drops the whole channel** (terminals and AI too): a very long header, a big cookie, a large WebSocket message. Pinned by: Task 1 "the largest message of each kind fits one sealed batch (RF 1)"; Task 5 "a response head over 32 KiB: too_large", Task 6 "a message over the limit closes with 1009, either way"; Task 8 "a message over one sealed batch is refused; the channel stays"; Task 9 "a head over the limits is answered 431 here; nothing goes to the computer"; Task 10 "no frame over 64 KiB".
2. **The relay closes a connection for more than 500 frames a second**, on the desktop (every phone drops) or the phone (every machine drops): a Vite page with hundreds of modules, a big download on a fast network. Pinned by: Task 3 "≤ 150 frames and ≤ 8 MiB per second, whatever is asked", "small frames are limited by count"; Task 5 "50 MB arrive whole … ≤ 150 frames and ≤ 8 MiB a second"; Task 8 "at most 100 tool frames a second, in order, none lost"; Task 10 "the computer well under the relay's 500 frames a second" (in-process) and the real-relay test.
3. **Data lost when a window is full** (the terminal's "ring, then reset" copied by mistake). Pinned by: Task 3 "never more than the window in flight; the source pauses and every byte arrives once, in order", "streams share the phone's 512 KiB"; Task 5 "50 MB arrive whole (SHA-256)"; Task 10 "8 MB through the tunnel: whole" and 50 MB over the real relay.
4. **Reaching something that is not the tool** through the request target, `Host`, a redirect or `http_proxy`. Pinned by: Task 2 target, method and head rules; Task 5 "a target that is not origin form, a forbidden method, CRLF in a header", "a foreign Host is replaced", "http_proxy is ignored", "a 3xx is not followed", "a tool on ::1 only is reached; a name is never resolved", "a tool not on the list: disabled when its flag is off, gone otherwise; never by URL".
5. **Another app on the phone** calling the loopback port, or a page of another origin (DNS rebinding). Pinned by: Task 9 "without the cookie, with another Host, or with an expired entry: 403", "/__shellx/ is the phone's own", "an unsafe request from another origin, or cross-site, is refused", "a WebSocket without the cookie: 403"; Task 13 "another site asks first", "a local port that is not served is named".

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| Create `packages/shellx_core/lib/src/protocol/tool_messages.dart` (part of `messages.dart`) | the 11 `tool.*` messages, sizes, end codes, `toolHeadBytes` | 1 |
| Modify `packages/shellx_core/lib/src/protocol/messages.dart` | `part`, `tool.` dispatch, `SessionListResult.tools` | 1 |
| Create `packages/shellx_core/lib/src/protocol/batches.dart`; Modify `lib/shellx_core.dart`, `packages/shellx_agent/lib/src/service/agent_channel.dart`, `packages/shellx_agent/test/service/agent_channel_test.dart` | `splitIntoBatches` moved to the core | 1 |
| Create `packages/shellx_core/test/protocol/frozen/messages_v2.dart`, `frozen/ai_messages_v2.dart` | the V2-2 decoder at `d8ad686`, frozen | 1 |
| Create `packages/shellx_core/test/protocol/tool_messages_test.dart`, `batches_test.dart` | maps, redaction, skipping, sizes, compatibility | 1 |
| Create `docs/superpowers/ledgers/v2-4-tools-phone.md` | rulings, then results | 1, 16 |
| Create `packages/shellx_core/lib/src/protocol/tool_rules.dart`, `test/protocol/tool_rules_test.dart` | E9/E11 rules both ends apply | 2 |
| Create `packages/shellx_core/lib/src/protocol/tool_flow.dart`, `test/protocol/tool_flow_test.dart` | windows, ack book, pacer, outlets, inlets | 3 |
| Create `packages/shellx_agent/lib/src/tool/tool_endpoint.dart`; Modify `lib/src/session/session_router.dart`, `lib/src/service/agent_channel.dart`, `lib/shellx_agent.dart`; Create `test/tool/tool_router_test.dart`; Modify `test/service/agent_channel_test.dart` | endpoint, slot, router case, `tools` flag, tool-data flush | 4 |
| Create `packages/shellx_agent/lib/src/tool/tool_catalog.dart`, `tool_forwarding.dart`, `tool_proxy.dart`; Create `test/support/tool_rig.dart`, `test/tool/tool_proxy_http_test.dart` | the desktop proxy: list, open, HTTP | 5 |
| Modify `packages/shellx_agent/lib/src/tool/tool_proxy.dart`; Create `test/tool/tool_proxy_ws_test.dart` | WebSocket streams | 6 |
| Modify `packages/shellx_agent/lib/src/mux/mux_messages.dart`, `mux_server.dart`; Create `test/mux/mux_tools_test.dart` | `tool.serve` (window → background service) | 7 |
| Create `packages/shellx_client/lib/src/machine_tools.dart`; Modify `lib/src/machine_client.dart`, `lib/shellx_client.dart`, `test/support/harness.dart`; Create `test/tools_test.dart` | list, open, stream routing, tool outbox | 8 |
| Create `packages/shellx_client/lib/src/tool_session.dart`, `test/support/test_tool.dart`, `test/support/tool_pipe.dart`, `test/tool_session_test.dart`; Modify `pubspec.yaml`, `lib/shellx_client.dart` | the phone's loopback server | 9 |
| Create `packages/shellx_client/test/tools_e2e_test.dart`, `packages/shellx_e2e/test/tools_e2e_test.dart`; Modify `packages/shellx_e2e/test/support/e2e_world.dart` | end to end | 10 |
| Modify `apps/desktop/lib/src/agent/session_core.dart`, `agent_runtime.dart`, `apps/desktop/lib/daemon_main.dart`; Create `apps/desktop/lib/src/agent/daemon_tools.dart`, `apps/desktop/test/agent/tool_slot_test.dart` | the slot in every runtime; the proxy in the background service | 11 |
| Modify `apps/mobile/pubspec.yaml`, `ios/Podfile.lock`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`; Create `android/app/src/main/res/xml/network_security_config.xml`; Modify `test/platform_config_test.dart`, `lib/l10n/intl_{en,vi}.arb` (+ generated `lib/shared/src/{l10n,intl/messages_en,intl/messages_vi}.dart`), `lib/core/backend/{backend,client_backend}.dart`, `test/support/fakes.dart` | mobile foundation | 12 |
| Create `apps/mobile/lib/features/tools/domain/{tool_navigation,tool_texts}.dart`, `presentation/{tool_web_engine,controllers/tool_page_controller,pages/tool_page}.dart`; Modify `lib/core/router/app_router.dart` (+ generated `app_router.gr.dart`, `lib/core/dependency/dependency.config.dart`), `lib/features/settings/presentation/pages/settings_page.dart`; Create `test/support/fake_tool_engine.dart`, `test/features/tools/{tool_navigation,tool_page}_test.dart`; Modify `test/features/settings/settings_page_test.dart`, `test/app_test.dart` | the tool page; Settings › clear tool data | 13 |
| Modify `apps/mobile/lib/features/terminal/presentation/{controllers/terminal_workspace,widgets/session_picker,pages/terminal_page}.dart`; Create `test/features/tools/tool_entry_test.dart` | the Tool group in the picker; opening a tool | 14 |
| Create `apps/desktop/lib/src/tools/tool_phone.dart`, `apps/desktop/test/tools/tool_phone_test.dart`; Modify `apps/desktop/lib/main.dart` | the window's phone list, served or pushed (needs V2-3 Task 1) | 15 |
| Modify `docs/superpowers/ledgers/v2-4-tools-phone.md` | verification, compatibility matrix, privacy sweep, manual checks | 16 |

---

### Task 1: `tool.*` messages, the `tools` flag, a frozen V2-2 decoder, and `splitIntoBatches` in the core

The eleven messages of spec §4.1 as a `part` of `messages.dart`, so they extend the sealed `AppMessage` like `ai.*` (V2-2 Task 1).
- **Envelope:** flat; `head` is a flat list of strings `[name, value, …]` (a Latin-1 byte travels as its character), bodies and WebSocket payloads are byte strings. Depth 3, never a float.
- **Bad input:** a malformed `tool.*` message (a wrong type, a `head` of odd length, an `acks` with a non-integer) or a newer `tool.*` type decodes to `null`: skipped, the channel and its terminals stay.
- **`toString()`:** only the type (E18).
- **`session.list.result`:** gains `tools` (written only when set).
- **Old peers (E19):** a frozen copy of the V2-2 decoder (`d8ad686`) and the V1 one already in the repo prove that every released phone and desktop skips the new messages and keeps its neighbours.
- **`splitIntoBatches`** moves to the core unchanged (E8): the phone's tool outbox (Task 8) and the desktop's channel share it.

**Files:**
- Create: `packages/shellx_core/test/protocol/frozen/messages_v2.dart`, `packages/shellx_core/test/protocol/frozen/ai_messages_v2.dart` (generated by Step 1, never edited)
- Create: `packages/shellx_core/lib/src/protocol/tool_messages.dart`
- Modify: `packages/shellx_core/lib/src/protocol/messages.dart`
- Create: `packages/shellx_core/lib/src/protocol/batches.dart`
- Modify: `packages/shellx_core/lib/shellx_core.dart`
- Modify: `packages/shellx_agent/lib/src/service/agent_channel.dart` (its `splitIntoBatches` is removed)
- Modify: `packages/shellx_agent/test/service/agent_channel_test.dart` (the moved test is removed)
- Test: `packages/shellx_core/test/protocol/tool_messages_test.dart`, `packages/shellx_core/test/protocol/batches_test.dart`
- Create: `docs/superpowers/ledgers/v2-4-tools-phone.md`

**Interfaces:**
- Consumes: nothing new.
- Produces (exported from `package:shellx_core/shellx_core.dart`):
  - `const int kToolProtocol = 1`, `kToolMaxChunkBytes = 48 * 1024`, `kToolMaxHeadBytes = 32 * 1024`, `kToolMaxHeaders = 100`, `kToolMaxTargetBytes = 8 * 1024`, `kToolMaxMethodLength = 16`;
  - `abstract final class ToolCode { static const refused, disabled, gone, busy, tooLarge, timeout, desktopClosed, unavailable, aborted, badRequest; static const Set<String> all; }` (the wire words of §4.1);
  - `String? toolEndCode(String? code)` (null stays null, an unknown word is `aborted`); `int toolHeadBytes(List<String> head)` (UTF-8 bytes of every name and value);
  - `sealed class ToolMessage extends AppMessage` (`toString()` → `'<Type>(…)'`) with:
    - `ToolList()`;
    - `ToolListResult({required bool available, required Uint8List body})`;
    - `ToolOpen({required int rid, required String tool})`;
    - `ToolOpened({required int rid, required bool ok, String? code, Uint8List? body})`;
    - `ToolClose({required String tool})`;
    - `ToolRequest({required int id, required String tool, required String method, required String target, required List<String> head, int? alias, bool ws = false, required bool end})` (`method` is `m` on the wire);
    - `ToolResponse({required int id, required int status, required List<String> head, required bool end})`;
    - `ToolData({required int id, required Uint8List data, required bool end})`;
    - `ToolAck(List<int> acks)` (flat `[id, total, …]`);
    - `ToolWsMessage({required int id, required Uint8List data, required bool text, required bool fin})`;
    - `ToolEnd({required int id, String? code, int? wsCode, String? wsReason})`;
  - `SessionListResult(List<SessionInfo> sessions, {bool? desktopSharing, int? ai, int? tools})` with `final int? tools`;
  - `List<List<AppMessage>> splitIntoBatches(List<AppMessage> messages)` (from `shellx_agent`, unchanged).

- [ ] **Step 1: Freeze the V2-2 decoder**

From the repo root:

````bash
mkdir -p packages/shellx_core/test/protocol/frozen
{ printf '%s\n' "// Frozen copy of lib/src/protocol/messages.dart at d8ad686 (the decoder of" \
    "// every phone and desktop with V2-2 AI sessions, before V2-4). Never edit:" \
    "// tests decode what this version sends with it (V2-4 E19)." \
    "// ignore_for_file: type=lint"
  git show d8ad686:packages/shellx_core/lib/src/protocol/messages.dart \
    | sed -e "s#import '../util/cbor_values.dart';#import 'package:shellx_core/src/util/cbor_values.dart';#" \
          -e "s#^part 'ai_messages.dart';#part 'ai_messages_v2.dart';#"
} > packages/shellx_core/test/protocol/frozen/messages_v2.dart
{ printf '%s\n' "// Frozen copy of lib/src/protocol/ai_messages.dart at d8ad686 (part of" \
    "// messages_v2.dart). Never edit." \
    "// ignore_for_file: type=lint"
  git show d8ad686:packages/shellx_core/lib/src/protocol/ai_messages.dart \
    | sed -e "s#^part of 'messages.dart';#part of 'messages_v2.dart';#"
} > packages/shellx_core/test/protocol/frozen/ai_messages_v2.dart
grep -n "^part\|^import 'package" packages/shellx_core/test/protocol/frozen/messages_v2.dart packages/shellx_core/test/protocol/frozen/ai_messages_v2.dart
````

Expected: `messages_v2.dart` imports `package:shellx_core/src/util/cbor_values.dart` and says `part 'ai_messages_v2.dart';`; `ai_messages_v2.dart` says `part of 'messages_v2.dart';`.

- [ ] **Step 2: Write the failing tests**

`packages/shellx_core/test/protocol/tool_messages_test.dart`:

````dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'frozen/messages_v1.dart' as v1;
import 'frozen/messages_v2.dart' as v2;

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// V2-4 §4: the `tool.*` messages, and what every older peer does with them.
void main() {
  final body = _json({'v': 1});
  final bytes = Uint8List.fromList([1, 2, 3]);
  final samples = <ToolMessage, Map<String, Object?>>{
    const ToolList(): {'t': 'tool.list'},
    ToolListResult(available: true, body: body): {
      't': 'tool.list.result',
      'available': true,
      'body': body,
    },
    const ToolOpen(rid: 1, tool: 'k3f9za7q1m'): {
      't': 'tool.open',
      'rid': 1,
      'tool': 'k3f9za7q1m',
    },
    ToolOpened(rid: 1, ok: true, body: body): {
      't': 'tool.opened',
      'rid': 1,
      'ok': true,
      'body': body,
    },
    const ToolOpened(rid: 2, ok: false, code: 'refused'): {
      't': 'tool.opened',
      'rid': 2,
      'ok': false,
      'code': 'refused',
    },
    const ToolClose(tool: 'k3f9za7q1m'): {
      't': 'tool.close',
      'tool': 'k3f9za7q1m',
    },
    const ToolRequest(
      id: 7,
      tool: 'k3f9za7q1m',
      method: 'GET',
      target: '/src/main.ts?t=1',
      head: ['accept', '*/*', 'cookie', 'sid=Bảng'],
      end: true,
    ): {
      't': 'tool.req',
      'id': 7,
      'tool': 'k3f9za7q1m',
      'm': 'GET',
      'target': '/src/main.ts?t=1',
      'head': ['accept', '*/*', 'cookie', 'sid=Bảng'],
      'end': true,
    },
    const ToolRequest(
      id: 8,
      tool: 'k3f9za7q1m',
      method: 'GET',
      target: '/',
      head: [],
      alias: 49152,
      ws: true,
      end: true,
    ): {
      't': 'tool.req',
      'id': 8,
      'tool': 'k3f9za7q1m',
      'm': 'GET',
      'target': '/',
      'head': <String>[],
      'alias': 49152,
      'ws': true,
      'end': true,
    },
    const ToolResponse(
      id: 7,
      status: 200,
      head: ['content-type', 'text/html'],
      end: false,
    ): {
      't': 'tool.res',
      'id': 7,
      'status': 200,
      'head': ['content-type', 'text/html'],
      'end': false,
    },
    ToolData(id: 7, data: bytes, end: true): {
      't': 'tool.data',
      'id': 7,
      'data': bytes,
      'end': true,
    },
    const ToolAck([7, 65536, 8, 12]): {
      't': 'tool.ack',
      'acks': [7, 65536, 8, 12],
    },
    ToolWsMessage(id: 8, data: bytes, text: false, fin: true): {
      't': 'tool.ws.msg',
      'id': 8,
      'data': bytes,
      'text': false,
      'fin': true,
    },
    const ToolEnd(id: 7, code: 'disabled'): {
      't': 'tool.end',
      'id': 7,
      'code': 'disabled',
    },
    const ToolEnd(id: 8, wsCode: 1000, wsReason: 'bye'): {
      't': 'tool.end',
      'id': 8,
      'ws_code': 1000,
      'ws_reason': 'bye',
    },
  };

  test('every tool.* message has the exact map and round-trips', () {
    for (final MapEntry(key: message, value: map) in samples.entries) {
      expect(message.toMap(), map, reason: message.type);
      expect(decodeBatch(encodeBatch([message])), [
        message,
      ], reason: message.type);
    }
  });

  test('toString never shows a URL, a header or a body (E18)', () {
    for (final message in samples.keys) {
      final text = message.toString();
      expect(text, isNot(contains('main.ts')));
      expect(text, isNot(contains('cookie')));
      expect(text, isNot(contains('k3f9za7q1m')));
      expect(text, isNot(contains('bytes')));
      expect(text, '${message.runtimeType}(…)');
    }
  });

  test('a malformed or unknown tool.* message is skipped, never fatal', () {
    final batch = encodeCbor([
      {'t': 'ack', 'id': 1, 'seq': 2},
      {'t': 'tool.req', 'id': 'x', 'tool': 'a', 'm': 'GET', 'target': '/'},
      {
        't': 'tool.req',
        'id': 1,
        'tool': 'a',
        'm': 'GET',
        'target': '/',
        'head': ['only-a-name'], // odd: a name without its value
        'end': true,
      },
      {
        't': 'tool.res',
        'id': 1,
        'status': 200,
        'head': ['a', 5],
        'end': true,
      },
      {
        't': 'tool.ack',
        'acks': [1, 'x'],
      },
      {
        't': 'tool.ack',
        'acks': [1],
      },
      {'t': 'tool.data', 'id': 1, 'data': 'text, not bytes', 'end': true},
      {'t': 'tool.future', 'x': 1},
      {'t': 'session.reset', 'id': 1},
    ]);
    expect(decodeBatch(batch), [
      const AckMessage(id: 1, seq: 2),
      const SessionReset(id: 1),
    ]);
  });

  test('an end code this version does not know reads as aborted', () {
    expect(toolEndCode(null), isNull);
    expect(toolEndCode('refused'), 'refused');
    expect(toolEndCode('quota_exceeded'), 'aborted');
  });

  test('head bytes count UTF-8 (a Latin-1 byte above 0x7F takes two)', () {
    expect(toolHeadBytes(['ab', 'c']), 3);
    expect(toolHeadBytes(['é']), 2);
    expect(toolHeadBytes(['ả']), 3);
    expect(toolHeadBytes(['😀']), 4);
  });

  group('the largest message of each kind fits one sealed batch (RF 1)', () {
    // A head at the limit, made of many short pairs (the CBOR string headers
    // cost the most then) and of one long value (the other extreme).
    List<String> manyPairs() {
      final head = <String>[];
      var bytes = 0;
      var i = 0;
      while (head.length < kToolMaxHeaders * 2) {
        final name = 'h${i++}';
        final value = 'v' * 300;
        if (bytes + name.length + value.length > kToolMaxHeadBytes) break;
        head.addAll([name, value]);
        bytes += name.length + value.length;
      }
      return head;
    }

    final oneLong = ['cookie', 'ÿ' * ((kToolMaxHeadBytes - 6) ~/ 2)];
    const id = 0xFFFFFFFF;

    test('tool.req and tool.res', () {
      for (final head in [manyPairs(), oneLong]) {
        expect(toolHeadBytes(head), lessThanOrEqualTo(kToolMaxHeadBytes));
        final req = ToolRequest(
          id: id,
          tool: 'k' * 64,
          method: 'M' * kToolMaxMethodLength,
          target: '/${'x' * (kToolMaxTargetBytes - 1)}',
          head: head,
          alias: 65535,
          ws: true,
          end: false,
        );
        final res = ToolResponse(id: id, status: 999, head: head, end: false);
        expect(encodeBatch([req]).length, lessThan(kMaxSealedBatchBytes));
        expect(encodeBatch([res]).length, lessThan(kMaxSealedBatchBytes));
      }
    });

    test('tool.data, tool.ws.msg, tool.list.result and tool.opened', () {
      final full = Uint8List(kToolMaxChunkBytes);
      for (final message in <ToolMessage>[
        ToolData(id: id, data: full, end: true),
        ToolWsMessage(id: id, data: full, text: true, fin: true),
        ToolListResult(available: true, body: full),
        ToolOpened(rid: id, ok: true, code: 'unavailable', body: full),
      ]) {
        expect(
          encodeBatch([message]).length,
          lessThan(kMaxSealedBatchBytes),
          reason: message.type,
        );
      }
    });

    test('tool.ack for every stream a phone may hold, tool.end', () {
      final acks = [
        for (var i = 0; i < 48; i++) ...[id - i, 1 << 50],
      ];
      expect(
        encodeBatch([ToolAck(acks)]).length,
        lessThan(kMaxSealedBatchBytes),
      );
      final end = ToolEnd(
        id: id,
        code: 'desktop_closed',
        wsCode: 4999,
        wsReason: 'ả' * 41, // 123 UTF-8 bytes, a close frame's limit
      );
      expect(encodeBatch([end]).length, lessThan(kMaxSealedBatchBytes));
    });
  });

  group('session.list.result carries the tools protocol (E6)', () {
    test('written only when set; read back', () {
      const without = SessionListResult([], desktopSharing: true, ai: 1);
      expect(without.toMap().containsKey('tools'), isFalse);
      const with1 = SessionListResult(
        [],
        desktopSharing: true,
        ai: kAiProtocol,
        tools: kToolProtocol,
      );
      expect(with1.toMap()['tools'], 1);
      final decoded = decodeBatch(encodeBatch([with1])).single;
      expect((decoded as SessionListResult).tools, 1);
      expect(decoded.ai, 1);
    });

    test('an older desktop sends none: null', () {
      final batch = encodeCbor([
        {'t': 'session.list.result', 'sessions': [], 'ai': 1},
      ]);
      expect((decodeBatch(batch).single as SessionListResult).tools, isNull);
    });
  });

  group('compatibility with every released peer (E19)', () {
    final neighbours = <AppMessage>[
      const AckMessage(id: 1, seq: 2),
      ...samples.keys,
      const AiList(),
      const SessionReset(id: 1),
    ];

    test('a V2-2 phone or desktop (frozen at d8ad686) skips every tool.* '
        'message and keeps its neighbours', () {
      final decoded = v2.decodeBatch(encodeBatch(neighbours));
      expect(decoded.map((m) => m.type), ['ack', 'ai.list', 'session.reset']);
    });

    test('a V1 peer (frozen at 5e04dc8) skips them too', () {
      final decoded = v1.decodeBatch(encodeBatch(neighbours));
      expect(decoded.map((m) => m.type), ['ack', 'session.reset']);
    });

    test('a V2-2 phone reads session.list.result with tools as before', () {
      final batch = encodeBatch([
        const SessionListResult(
          [
            SessionInfo(
              id: 1,
              index: 1,
              shell: 'zsh',
              createdAt: 1,
              attached: false,
            ),
          ],
          desktopSharing: true,
          ai: kAiProtocol,
          tools: kToolProtocol,
        ),
      ]);
      final decoded = v2.decodeBatch(batch).single as v2.SessionListResult;
      expect(decoded.sessions.single.id, 1);
      expect(decoded.ai, 1);
      expect(decoded.desktopSharing, isTrue);
    });
  });
}
````

`packages/shellx_core/test/protocol/batches_test.dart` (the test that moves from `shellx_agent`, plus one with tool chunks):

````dart
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

OutputMessage _output(int seq, int size) =>
    OutputMessage(id: 1, seq: seq, data: Uint8List(size));

/// V2-4 E8: the batching rule the desktop's channel and the phone's tool
/// outbox share.
void main() {
  test('measures encoded sizes: three full 16 KiB outputs fit a batch', () {
    final small = [for (var i = 0; i < 50; i++) SessionAttached(id: i)];
    expect(splitIntoBatches(small), hasLength(1));
    final big = [for (var i = 0; i < 7; i++) _output(i, 16 * 1024)];
    final batches = splitIntoBatches(big);
    expect([for (final b in batches) b.length], [3, 3, 1]);
    for (final batch in batches) {
      expect(
        encodeBatch(batch).length,
        lessThanOrEqualTo(kMaxSealedBatchBytes),
      );
    }
  });

  test('full tool chunks go one per batch, in order, small ones with them', () {
    final messages = <AppMessage>[
      for (var i = 0; i < 3; i++)
        ToolData(id: i, data: Uint8List(kToolMaxChunkBytes), end: false),
      const ToolAck([1, 2]),
      const ToolEnd(id: 9, code: 'aborted'),
    ];
    final batches = splitIntoBatches(messages);
    expect([for (final b in batches) b.length], [1, 1, 3]);
    expect([for (final b in batches) ...b], messages);
    for (final batch in batches) {
      expect(
        encodeBatch(batch).length,
        lessThanOrEqualTo(kMaxSealedBatchBytes),
      );
    }
  });
}
````

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test test/protocol/tool_messages_test.dart test/protocol/batches_test.dart`
Expected: FAIL to compile — `ToolMessage`, `ToolList`, `kToolMaxChunkBytes`, `splitIntoBatches` … are not defined.

- [ ] **Step 4: Write the messages**

`packages/shellx_core/lib/src/protocol/tool_messages.dart`:

````dart
part of 'messages.dart';

/// V2-4 E6: the `tool.*` protocol a desktop reports in `session.list.result`
/// (`tools`). A phone shows the Tool group only when it is at least 1.
const int kToolProtocol = 1;

/// V2-4 E7: the largest `data` of a `tool.data` or a `tool.ws.msg`, and the
/// largest `body` of a `tool.list.result` or a `tool.opened`. One sealed
/// batch ([kMaxSealedBatchBytes], 65 493 bytes) holds it with its envelope,
/// so a tool message never makes `SecureChannel.seal` throw (which would
/// drop the whole channel, terminals and AI included).
const int kToolMaxChunkBytes = 48 * 1024;

/// V2-4 E7, E9: the largest `head` of a `tool.req` or a `tool.res`: the
/// UTF-8 bytes of every name and value ([toolHeadBytes]).
const int kToolMaxHeadBytes = 32 * 1024;

/// V2-4 E9: at most this many headers (name/value pairs) in a `head`.
const int kToolMaxHeaders = 100;

/// V2-4 E9: the longest request target, in UTF-8 bytes.
const int kToolMaxTargetBytes = 8 * 1024;

/// V2-4 E9: the longest method.
const int kToolMaxMethodLength = 16;

/// V2-4 §4.1: how a stream ended (`tool.end`'s `code`). A newer peer may send
/// another word: [toolEndCode] reads it as [aborted].
abstract final class ToolCode {
  static const refused = 'refused';
  static const disabled = 'disabled';
  static const gone = 'gone';
  static const busy = 'busy';
  static const tooLarge = 'too_large';
  static const timeout = 'timeout';
  static const desktopClosed = 'desktop_closed';
  static const unavailable = 'unavailable';
  static const aborted = 'aborted';
  static const badRequest = 'bad_request';

  static const all = {
    refused,
    disabled,
    gone,
    busy,
    tooLarge,
    timeout,
    desktopClosed,
    unavailable,
    aborted,
    badRequest,
  };
}

/// [code] as this version reads it: null stays null (a WebSocket that
/// closed normally), a word it does not know is [ToolCode.aborted].
String? toolEndCode(String? code) =>
    code == null || ToolCode.all.contains(code) ? code : ToolCode.aborted;

/// The UTF-8 bytes of every name and value of [head] (what the transport
/// carries; a Latin-1 value byte above 0x7F takes two).
int toolHeadBytes(List<String> head) {
  var total = 0;
  for (final s in head) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x80) {
        total += 1;
      } else if (c < 0x800) {
        total += 2;
      } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        total += 4; // a surrogate pair
        i++;
      } else {
        total += 3;
      }
    }
  }
  return total;
}

/// V2-4: messages between a phone and the personal web tools a desktop lets
/// it open (spec V2-4 §4). Headers travel as a flat `head` list `[name,
/// value, …]`, bodies and WebSocket payloads as byte strings, so the
/// transport sees depth 3 and never a float.
///
/// A `tool.*` message this version cannot read is skipped ([AppMessage.
/// fromMap] returns null), never fatal: only that stream ends, the channel
/// and its terminals stay. [toString] never shows a URL, a header or a body
/// (V2-4 E18).
sealed class ToolMessage extends AppMessage {
  const ToolMessage();

  @override
  String toString() => '$runtimeType(…)';

  /// The `tool.*` types this version reads; anything else under `tool.` is
  /// a newer peer's and is skipped.
  static ToolMessage? _fromMap(String t, _Fields f) {
    try {
      return switch (t) {
        'tool.list' => const ToolList(),
        'tool.list.result' => ToolListResult(
          available: f.boolean('available'),
          body: f.bytes('body'),
        ),
        'tool.open' => ToolOpen(rid: f.integer('rid'), tool: f.string('tool')),
        'tool.opened' => ToolOpened(
          rid: f.integer('rid'),
          ok: f.boolean('ok'),
          code: f.optionalString('code'),
          body: f.optionalBytes('body'),
        ),
        'tool.close' => ToolClose(tool: f.string('tool')),
        'tool.req' => ToolRequest(
          id: f.integer('id'),
          tool: f.string('tool'),
          method: f.string('m'),
          target: f.string('target'),
          head: f._strings('head'),
          alias: f.optionalInteger('alias'),
          ws: f.optionalBoolean('ws') ?? false,
          end: f.boolean('end'),
        ),
        'tool.res' => ToolResponse(
          id: f.integer('id'),
          status: f.integer('status'),
          head: f._strings('head'),
          end: f.boolean('end'),
        ),
        'tool.data' => ToolData(
          id: f.integer('id'),
          data: f.bytes('data'),
          end: f.boolean('end'),
        ),
        'tool.ack' => ToolAck(f._integers('acks')),
        'tool.ws.msg' => ToolWsMessage(
          id: f.integer('id'),
          data: f.bytes('data'),
          text: f.boolean('text'),
          fin: f.boolean('fin'),
        ),
        'tool.end' => ToolEnd(
          id: f.integer('id'),
          code: f.optionalString('code'),
          wsCode: f.optionalInteger('ws_code'),
          wsReason: f.optionalString('ws_reason'),
        ),
        _ => null,
      };
    } on FormatException {
      return null; // Skipped, never fatal (see [ToolMessage]).
    }
  }
}

extension on _Fields {
  /// A flat list of strings with an even length (`[name, value, …]`).
  List<String> _strings(String key) {
    final list = this.list(key);
    if (list.length.isOdd) throw FormatException('"$key" has an odd length');
    return [
      for (final item in list)
        item is String ? item : throw FormatException('"$key" not strings'),
    ];
  }

  /// A flat list of integers with an even length (`[id, n, …]`).
  List<int> _integers(String key) {
    final list = this.list(key);
    if (list.length.isOdd) throw FormatException('"$key" has an odd length');
    return [
      for (final item in list)
        item is int ? item : throw FormatException('"$key" not integers'),
    ];
  }
}

/// Phone → desktop: list the tools this phone may open and keep the list
/// current (the desktop sends `tool.list.result` again whenever it changes,
/// until the channel ends).
final class ToolList extends ToolMessage {
  const ToolList();
  @override
  String get type => 'tool.list';
  @override
  Map<String, Object?> toMap() => {'t': type};
}

/// Desktop → phone: the tools ([body], UTF-8 JSON, V2-4 §4.2). [available]
/// is false while the process that holds the relay has no list yet (a
/// background service that restarted before the window pushed one).
final class ToolListResult extends ToolMessage {
  const ToolListResult({required this.available, required this.body});
  final bool available;
  final Uint8List body;
  @override
  String get type => 'tool.list.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'available': available,
    'body': body,
  };
}

/// Phone → desktop: about to open [tool] (an id from the list, never a
/// URL): the desktop checks its flag and tries its port.
final class ToolOpen extends ToolMessage {
  const ToolOpen({required this.rid, required this.tool});
  final int rid;
  final String tool;
  @override
  String get type => 'tool.open';
  @override
  Map<String, Object?> toMap() => {'t': type, 'rid': rid, 'tool': tool};
}

/// Desktop → phone: how `tool.open` [rid] went. [code] when not [ok]
/// (`refused`, `disabled`, `gone`, `busy`, `unavailable`); [body] when [ok]:
/// UTF-8 JSON `{"v": 1, "tools": [{"id", "port", "path"}]}`, the tools of
/// the same workspace to serve on their ports (V2-4 E4), this one first.
final class ToolOpened extends ToolMessage {
  const ToolOpened({required this.rid, required this.ok, this.code, this.body});
  final int rid;
  final bool ok;
  final String? code;
  final Uint8List? body;
  @override
  String get type => 'tool.opened';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'ok': ok,
    if (code != null) 'code': code,
    if (body != null) 'body': body,
  };
}

/// Phone → desktop: the page of [tool] was left; every stream of it from
/// this phone ends.
final class ToolClose extends ToolMessage {
  const ToolClose({required this.tool});
  final String tool;
  @override
  String get type => 'tool.close';
  @override
  Map<String, Object?> toMap() => {'t': type, 'tool': tool};
}

/// Phone → desktop: open stream [id] (a number the phone picks, unique on
/// its channel) to [tool]: [method] (`m` on the wire) on [target] (origin
/// form, `/path?query`) with [head]. [alias]: the port the phone serves the
/// tool on when it is not the tool's own (V2-4 E3). [ws]: a WebSocket
/// upgrade. [end]: there is no body (else `tool.data` follows).
final class ToolRequest extends ToolMessage {
  const ToolRequest({
    required this.id,
    required this.tool,
    required this.method,
    required this.target,
    required this.head,
    this.alias,
    this.ws = false,
    required this.end,
  });
  final int id;
  final String tool;
  final String method;
  final String target;
  final List<String> head;
  final int? alias;
  final bool ws;
  final bool end;
  @override
  String get type => 'tool.req';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'tool': tool,
    'm': method,
    'target': target,
    'head': head,
    if (alias != null) 'alias': alias,
    if (ws) 'ws': true,
    'end': end,
  };
}

/// Desktop → phone: the response head of stream [id]; 101 when its
/// WebSocket is open. [end]: no body follows.
final class ToolResponse extends ToolMessage {
  const ToolResponse({
    required this.id,
    required this.status,
    required this.head,
    required this.end,
  });
  final int id;
  final int status;
  final List<String> head;
  final bool end;
  @override
  String get type => 'tool.res';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'status': status,
    'head': head,
    'end': end,
  };
}

/// Both ways: a piece of the body of stream [id] (≤ [kToolMaxChunkBytes]);
/// [end]: the last one (it may be empty).
final class ToolData extends ToolMessage {
  const ToolData({required this.id, required this.data, required this.end});
  final int id;
  final Uint8List data;
  final bool end;
  @override
  String get type => 'tool.data';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'data': data,
    'end': end,
  };
}

/// Both ways: `[id₁, n₁, id₂, n₂, …]`: every byte of stream idₖ up to nₖ
/// (cumulative) was taken; it opens the sender's window again.
final class ToolAck extends ToolMessage {
  const ToolAck(this.acks);
  final List<int> acks;
  @override
  String get type => 'tool.ack';
  @override
  Map<String, Object?> toMap() => {'t': type, 'acks': acks};
}

/// Both ways: a piece of a WebSocket message of stream [id] (UTF-8 for
/// [text]); a long message comes in several, the last with [fin].
final class ToolWsMessage extends ToolMessage {
  const ToolWsMessage({
    required this.id,
    required this.data,
    required this.text,
    required this.fin,
  });
  final int id;
  final Uint8List data;
  final bool text;
  final bool fin;
  @override
  String get type => 'tool.ws.msg';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'data': data,
    'text': text,
    'fin': fin,
  };
}

/// Both ways: stream [id] is over. [code] ([ToolCode]) when it failed or was
/// cut; none when a WebSocket closed with [wsCode] and [wsReason].
final class ToolEnd extends ToolMessage {
  const ToolEnd({required this.id, this.code, this.wsCode, this.wsReason});
  final int id;
  final String? code;
  final int? wsCode;
  final String? wsReason;
  @override
  String get type => 'tool.end';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    if (code != null) 'code': code,
    if (wsCode != null) 'ws_code': wsCode,
    if (wsReason != null) 'ws_reason': wsReason,
  };
}
````

In `packages/shellx_core/lib/src/protocol/messages.dart`:

1. After `part 'ai_messages.dart';` add:

````dart
part 'tool_messages.dart';
````

2. In `AppMessage.fromMap`, the `'session.list.result'` case, after `ai: f.optionalInteger('ai'),` add:

````dart
        tools: f.optionalInteger('tools'),
````

3. In `AppMessage.fromMap`, after `_ when t.startsWith('ai.') => AiMessage._fromMap(t, f),` add:

````dart
      // V2-4: never fatal either, see [ToolMessage].
      _ when t.startsWith('tool.') => ToolMessage._fromMap(t, f),
````

4. In `SessionListResult`, replace the constructor `const SessionListResult(this.sessions, {this.desktopSharing, this.ai});` with:

````dart
  const SessionListResult(
    this.sessions, {
    this.desktopSharing,
    this.ai,
    this.tools,
  });
````

   after the field `final int? ai;` add:

````dart

  /// V2-4 E6: the `tool.*` protocol this desktop speaks ([kToolProtocol]);
  /// only in answers to `session.list {desktop: true}`, only when the process
  /// that holds the relay has a tool proxy, only written when set. Null: a
  /// desktop without tools for phones (every older one).
  final int? tools;
````

   and in its `toMap()`, after `if (ai != null) 'ai': ai,` add:

````dart
    if (tools != null) 'tools': tools,
````

- [ ] **Step 5: Move `splitIntoBatches`**

`packages/shellx_core/lib/src/protocol/batches.dart`:

````dart
import '../channel/secure_channel.dart';
import 'messages.dart';

/// Upper bound for a CBOR array header of up to 65535 items.
const int _arrayHeaderAllowance = 3;

/// Splits [messages], in order, into batches whose encoded CBOR array stays
/// within [kMaxSealedBatchBytes] (so each sealed DATA frame is ≤ 64 KiB).
/// Sizes are measured with [encodeBatch]; three full 16 KiB outputs fit in
/// one batch, four do not. A single message over the limit ends up alone in
/// its batch (sealing it throws: check sizes before queueing). Shared by the
/// desktop's channel and the phone's tool outbox (V2-4 E8).
List<List<AppMessage>> splitIntoBatches(List<AppMessage> messages) {
  final batches = <List<AppMessage>>[];
  var current = <AppMessage>[];
  var size = _arrayHeaderAllowance;
  for (final message in messages) {
    final messageSize = encodeBatch([message]).length - 1;
    if (current.isNotEmpty && size + messageSize > kMaxSealedBatchBytes) {
      batches.add(current);
      current = <AppMessage>[];
      size = _arrayHeaderAllowance;
    }
    current.add(message);
    size += messageSize;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}
````

In `packages/shellx_core/lib/shellx_core.dart`, after `export 'src/protocol/messages.dart';` add:

````dart
export 'src/protocol/batches.dart';
````

In `packages/shellx_agent/lib/src/service/agent_channel.dart`, delete the constant `_arrayHeaderAllowance` and the function `splitIntoBatches` (from `/// Upper bound for a CBOR array header of up to 65535 items.` to the end of the function); the file keeps importing `package:shellx_core/shellx_core.dart`, which now provides it. Nothing else changes there in this task.

In `packages/shellx_agent/test/service/agent_channel_test.dart`, delete the test `'splitIntoBatches measures encoded sizes'` (it moved to `batches_test.dart`).

- [ ] **Step 6: Run the tests to verify they pass**

````bash
cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart format lib/src/protocol/tool_messages.dart lib/src/protocol/messages.dart lib/src/protocol/batches.dart test/protocol/tool_messages_test.dart test/protocol/batches_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
cd ../shellx_agent && ~/fvm/versions/3.41.4/bin/dart format lib/src/service/agent_channel.dart test/service/agent_channel_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test test/service
````

Expected: no analyzer issue in either package (the frozen files carry `// ignore_for_file: type=lint`); `shellx_core` 351 → 366 tests pass; `shellx_agent` `test/service` passes (one test fewer in `agent_channel_test.dart`).

- [ ] **Step 7: Start the ledger**

Create `docs/superpowers/ledgers/v2-4-tools-phone.md` with a title `# V2-4 — tools on the phone — ledger` and a heading `## Planning rulings`, under which you copy this plan's rulings R1–R23, one line each with its cost if wrong.

- [ ] **Step 8: Commit**

````bash
git add packages/shellx_core/lib/src/protocol/tool_messages.dart packages/shellx_core/lib/src/protocol/messages.dart packages/shellx_core/lib/src/protocol/batches.dart packages/shellx_core/lib/shellx_core.dart packages/shellx_core/test/protocol/frozen/messages_v2.dart packages/shellx_core/test/protocol/frozen/ai_messages_v2.dart packages/shellx_core/test/protocol/tool_messages_test.dart packages/shellx_core/test/protocol/batches_test.dart packages/shellx_agent/lib/src/service/agent_channel.dart packages/shellx_agent/test/service/agent_channel_test.dart docs/superpowers/ledgers/v2-4-tools-phone.md
git commit -m "feat(v2-tools): tool.* messages (never fatal), the tools flag, a frozen V2-2 decoder, splitIntoBatches in the core

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 2: The tunnel's request and header rules, shared by both ends

E9 and E11 as pure functions both ends apply (R1): the desktop before it reaches a tool, the phone before it sends anything.
- **Method:** a token of at most 16 characters, never `CONNECT`, `TRACE`, `TRACK`.
- **Target:** origin form only: one leading `/` (never `//`), at most 8 KiB, no CR, LF, NUL, space, `#`, backslash or DEL.
- **Head:** token names, values without CR/LF/NUL, ≤ 100 pairs, ≤ 32 KiB; what `dart:io` can write (R8).
- **Dropped headers:** hop-by-hop, `Forwarded`, `X-Forwarded-*`, `Via`, `Expect`, and what `Connection` lists.
- **Gate cookie:** `__shellx_<port>`; stripped from `Cookie`; a tool may not set it.
- **Loopback spellings:** `localhost`, `127.0.0.1`, `[::1]` with a port (or none for 80), and the origin prefix rewritten in alias mode (E3).
- **Limits of E10** as constants.

**Files:**
- Create: `packages/shellx_core/lib/src/protocol/tool_rules.dart`
- Modify: `packages/shellx_core/lib/shellx_core.dart`
- Test: `packages/shellx_core/test/protocol/tool_rules_test.dart`

**Interfaces:**
- Consumes (Task 1): `kToolMaxMethodLength`, `kToolMaxTargetBytes`, `kToolMaxHeaders`, `kToolMaxHeadBytes`, `toolHeadBytes`.
- Produces (exported from `package:shellx_core/shellx_core.dart`):
  - `const int kToolMaxHttpStreams = 32`, `kToolMaxWsStreams = 16`, `kToolMaxRequestBodyBytes = 64 * 1024 * 1024`, `kToolMaxWsMessageBytes = 16 * 1024 * 1024`; `const String kToolReservedPrefix = '/__shellx/'`, `kToolGateCookiePrefix = '__shellx_'`;
  - `String toolGateCookieName(int port)`;
  - `bool isToolToken(String s)`, `bool isToolHeaderValue(String s)`, `bool isWritableHeaderValue(String s)`, `bool isToolMethod(String method)`, `bool isToolTarget(String target)`, `bool isToolHead(List<String> head)`;
  - `const Set<String> kToolHopByHop`; `Set<String> toolDroppedNames(List<String> head)`; `List<String> toolHeadValues(List<String> head, String name)`;
  - `String? stripToolGateCookies(String cookie)`, `bool setsToolGateCookie(String setCookie)`;
  - `bool isToolLoopbackAuthority(String authority, int port)`, `String? toolLoopbackPrefix(String url, int port)`.

- [ ] **Step 1: Write the failing test**

`packages/shellx_core/test/protocol/tool_rules_test.dart`:

````dart
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// V2-4 E9, E11: the request and header rules both ends apply.
void main() {
  group('method (E9)', () {
    test('a token of at most 16 characters', () {
      for (final ok in ['GET', 'POST', 'PROPFIND', 'patch', 'M-SEARCH']) {
        expect(isToolMethod(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'GET POST', 'G\r\nET', 'A' * 17, 'GÉT', 'G(ET']) {
        expect(isToolMethod(bad), isFalse, reason: bad);
      }
    });

    test('never CONNECT, TRACE or TRACK, in any case', () {
      for (final bad in ['CONNECT', 'connect', 'TRACE', 'Trace', 'TRACK']) {
        expect(isToolMethod(bad), isFalse, reason: bad);
      }
    });
  });

  group('target (E9, RF 4)', () {
    test('origin form only', () {
      for (final ok in ['/', '/src/main.ts?t=1', '/@vite/client', '/a@b']) {
        expect(isToolTarget(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '',
        '*',
        'http://evil.com/',
        '@evil.com/',
        '//evil.com/x',
        'evil.com:80',
      ]) {
        expect(isToolTarget(bad), isFalse, reason: bad);
      }
    });

    test('no CR, LF, NUL, space, #, backslash or DEL; at most 8 KiB', () {
      for (final bad in [
        '/a\r\nHost: evil',
        '/a\nb',
        '/a\u0000',
        '/a b',
        '/a#frag',
        '/a\\..\\b',
        '/a\u007f',
        '/${'x' * kToolMaxTargetBytes}',
      ]) {
        expect(isToolTarget(bad), isFalse, reason: bad);
      }
      expect(isToolTarget('/${'x' * (kToolMaxTargetBytes - 1)}'), isTrue);
    });
  });

  group('head (E9)', () {
    test('pairs of a token name and a value without CR, LF or NUL', () {
      expect(isToolHead(['accept', '*/*', 'x-a', '']), isTrue);
      expect(isToolHead(['accept']), isFalse);
      expect(isToolHead(['bad name', 'v']), isFalse);
      expect(isToolHead(['x', 'a\r\nInjected: 1']), isFalse);
      expect(isToolHead(['x', 'a\u0000']), isFalse);
      expect(isToolHead(['x', 'Bảng việc']), isTrue); // carried; see writable
    });

    test('at most 100 headers and 32 KiB', () {
      final hundred = [
        for (var i = 0; i < 100; i++) ...['h$i', 'v'],
      ];
      expect(isToolHead(hundred), isTrue);
      expect(isToolHead([...hundred, 'one', 'more']), isFalse);
      expect(isToolHead(['big', 'x' * (kToolMaxHeadBytes - 3)]), isTrue);
      expect(isToolHead(['big', 'x' * (kToolMaxHeadBytes - 2)]), isFalse);
    });

    test('dart:io writes only visible ASCII, space and tab', () {
      expect(isWritableHeaderValue('text/html; charset=utf-8\t'), isTrue);
      expect(isWritableHeaderValue('attachment; filename="résumé"'), isFalse);
      expect(isWritableHeaderValue('a\u0001'), isFalse);
    });
  });

  test('hop-by-hop, forwarding headers and what Connection names are '
      'dropped (E9)', () {
    final dropped = toolDroppedNames([
      'Connection',
      'keep-alive, X-Secret',
      'X-Forwarded-For',
      '10.0.0.1',
      'accept',
      '*/*',
    ]);
    for (final name in [
      'connection',
      'keep-alive',
      'transfer-encoding',
      'te',
      'trailer',
      'upgrade',
      'proxy-authorization',
      'forwarded',
      'via',
      'x-forwarded-for',
      'x-secret',
      'expect',
    ]) {
      expect(dropped, contains(name));
    }
    expect(dropped, isNot(contains('accept')));
  });

  group('gate cookie (E11)', () {
    test('its name carries the port', () {
      expect(toolGateCookieName(5173), '__shellx_5173');
    });

    test('every __shellx_ pair is stripped from Cookie', () {
      expect(
        stripToolGateCookies('a=1; __shellx_5173=s3cr3t; b=2'),
        'a=1; b=2',
      );
      expect(stripToolGateCookies('__shellx_5173=s; __shellx_80=t'), isNull);
      expect(stripToolGateCookies('sid=__shellx_5173'), 'sid=__shellx_5173');
    });

    test('a tool cannot set a __shellx_ cookie', () {
      expect(setsToolGateCookie('__shellx_5173=x; Path=/'), isTrue);
      expect(setsToolGateCookie(' __shellx_1=x'), isTrue);
      expect(setsToolGateCookie('sid=1; Path=/'), isFalse);
    });
  });

  test('values of a header, in order, whatever the case', () {
    expect(
      toolHeadValues([
        'Cookie',
        'a=1',
        'accept',
        '*/*',
        'cookie',
        'b=2',
      ], 'cookie'),
      ['a=1', 'b=2'],
    );
  });

  group('loopback spellings (E2, E3)', () {
    test(
      'localhost, 127.0.0.1 and [::1] with the port; 80 may be left out',
      () {
        for (final ok in [
          'localhost:5173',
          '127.0.0.1:5173',
          '[::1]:5173',
          'LOCALHOST:5173',
        ]) {
          expect(isToolLoopbackAuthority(ok, 5173), isTrue, reason: ok);
        }
        for (final bad in [
          'localhost:5174',
          'evil.com:5173',
          'localhost',
          '::1:5173',
          'localhost.evil.com:5173',
        ]) {
          expect(isToolLoopbackAuthority(bad, 5173), isFalse, reason: bad);
        }
        expect(isToolLoopbackAuthority('localhost', 80), isTrue);
      },
    );

    test('the origin at the start of a URL, for the rewrite of E3', () {
      expect(
        toolLoopbackPrefix('http://localhost:49152/a?b#c', 49152),
        'http://localhost:49152',
      );
      expect(
        toolLoopbackPrefix('http://localhost:49152', 49152),
        'http://localhost:49152',
      );
      expect(
        toolLoopbackPrefix('http://127.0.0.1:5173?x', 5173),
        'http://127.0.0.1:5173',
      );
      expect(toolLoopbackPrefix('https://localhost:5173/', 5173), isNull);
      expect(toolLoopbackPrefix('http://localhost:5174/', 5173), isNull);
      expect(
        toolLoopbackPrefix('http://localhost:5173@evil.com/', 5173),
        isNull,
      );
    });
  });
}
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test test/protocol/tool_rules_test.dart`
Expected: FAIL to compile — `isToolMethod`, `isToolTarget` … are not defined.

- [ ] **Step 3: Write the rules**

`packages/shellx_core/lib/src/protocol/tool_rules.dart`:

````dart
import 'messages.dart';

/// V2-4 E10: at most this many HTTP streams per phone at once.
const int kToolMaxHttpStreams = 32;

/// V2-4 E10: at most this many WebSocket streams per phone at once.
const int kToolMaxWsStreams = 16;

/// V2-4 E10: the largest request body (413 above it).
const int kToolMaxRequestBodyBytes = 64 * 1024 * 1024;

/// V2-4 E10: the largest WebSocket message (close 1009 above it).
const int kToolMaxWsMessageBytes = 16 * 1024 * 1024;

/// V2-4 E11: the reserved path prefix of the phone's server; never sent on.
const String kToolReservedPrefix = '/__shellx/';

/// V2-4 E11: every gate cookie's name starts with this (`__shellx_<port>`).
const String kToolGateCookiePrefix = '__shellx_';

/// The gate cookie of the phone server on [port] (V2-4 E11).
String toolGateCookieName(int port) => '$kToolGateCookiePrefix$port';

/// RFC 9110 `tchar`: what a method or a header name is made of.
bool isToolToken(String s) {
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final ok =
        (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        '!#\$%&\'*+-.^_`|~'.codeUnits.contains(c);
    if (!ok) return false;
  }
  return true;
}

/// V2-4 E9: a header value carries no CR, LF or NUL.
bool isToolHeaderValue(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x0D || c == 0x0A || c == 0x00) return false;
  }
  return true;
}

/// What `dart:io` can write as a header value: visible ASCII, space and tab.
/// A value with any other byte (obs-text above 0x7E) is dropped when written,
/// never sent half (`HttpHeaders.add` throws on it).
bool isWritableHeaderValue(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (!((c >= 0x20 && c <= 0x7E) || c == 0x09)) return false;
  }
  return true;
}

/// V2-4 E9: a method is a token of at most 16 characters, and never one that
/// would turn the tool's server into a tunnel or reflect the request.
bool isToolMethod(String method) =>
    method.length <= kToolMaxMethodLength &&
    isToolToken(method) &&
    !const {'CONNECT', 'TRACE', 'TRACK'}.contains(method.toUpperCase());

/// V2-4 E9: origin form only (`/path?query`): starts with one `/` (never
/// `//`, an authority), at most [kToolMaxTargetBytes], and no CR, LF, NUL,
/// space, `#` or backslash.
bool isToolTarget(String target) {
  if (!target.startsWith('/') || target.startsWith('//')) return false;
  if (toolHeadBytes([target]) > kToolMaxTargetBytes) return false;
  for (var i = 0; i < target.length; i++) {
    final c = target.codeUnitAt(i);
    if (c <= 0x20 || c == 0x23 || c == 0x5C || c == 0x7F) return false;
  }
  return true;
}

/// V2-4 E9: a `head` is pairs of a token name and a value without CR, LF or
/// NUL; at most [kToolMaxHeaders] pairs and [kToolMaxHeadBytes] bytes.
bool isToolHead(List<String> head) {
  if (head.length.isOdd || head.length > kToolMaxHeaders * 2) return false;
  if (toolHeadBytes(head) > kToolMaxHeadBytes) return false;
  for (var i = 0; i < head.length; i += 2) {
    if (!isToolToken(head[i]) || !isToolHeaderValue(head[i + 1])) return false;
  }
  return true;
}

/// Hop-by-hop headers (RFC 9110 §7.6.1) and the ones a proxy must not pass
/// on (V2-4 E9), lower case. `connection` also names more, see
/// [toolDroppedNames].
const Set<String> kToolHopByHop = {
  'connection',
  'keep-alive',
  'proxy-connection',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'forwarded',
  'via',
  'expect',
};

/// The lower-case names of [head] that are never passed on: [kToolHopByHop],
/// `x-forwarded-*`, and every name its `connection` headers list.
Set<String> toolDroppedNames(List<String> head) {
  final dropped = {...kToolHopByHop};
  for (var i = 0; i < head.length; i += 2) {
    final name = head[i].toLowerCase();
    if (name.startsWith('x-forwarded-')) dropped.add(name);
    if (name == 'connection') {
      for (final token in head[i + 1].split(',')) {
        final listed = token.trim().toLowerCase();
        if (listed.isNotEmpty) dropped.add(listed);
      }
    }
  }
  return dropped;
}

/// The values of header [name] (lower case) in [head], in order.
List<String> toolHeadValues(List<String> head, String name) => [
  for (var i = 0; i < head.length; i += 2)
    if (head[i].toLowerCase() == name) head[i + 1],
];

/// A `Cookie` value without any `__shellx_*` pair (V2-4 E11); null when no
/// pair is left.
String? stripToolGateCookies(String cookie) {
  final kept = [
    for (final pair in cookie.split(';'))
      if (pair.trim().isNotEmpty &&
          !pair.trim().startsWith(kToolGateCookiePrefix))
        pair.trim(),
  ];
  return kept.isEmpty ? null : kept.join('; ');
}

/// Whether a `Set-Cookie` value sets a `__shellx_*` cookie (dropped, V2-4
/// E11: a tool must not overwrite the phone's gate).
bool setsToolGateCookie(String setCookie) =>
    setCookie.trimLeft().startsWith(kToolGateCookiePrefix);

/// [authority] (a `Host` value) is `localhost`, `127.0.0.1` or `[::1]` with
/// [port] (written, or 80 left out).
bool isToolLoopbackAuthority(String authority, int port) {
  final a = authority.toLowerCase();
  for (final host in const ['localhost', '127.0.0.1', '[::1]']) {
    if (a == '$host:$port' || (port == 80 && a == host)) return true;
  }
  return false;
}

/// `http://host[:port]` at the start of [url] when host is a loopback
/// spelling and the port is [port] (V2-4 E3: the origin the desktop and the
/// phone rewrite); null otherwise.
String? toolLoopbackPrefix(String url, int port) {
  if (!url.toLowerCase().startsWith('http://')) return null;
  final rest = url.substring(7);
  final end = rest.indexOf(RegExp('[/?#]'));
  final authority = end < 0 ? rest : rest.substring(0, end);
  return isToolLoopbackAuthority(authority, port)
      ? url.substring(0, 7 + authority.length)
      : null;
}
````

In `packages/shellx_core/lib/shellx_core.dart`, after `export 'src/protocol/batches.dart';` add:

````dart
export 'src/protocol/tool_rules.dart';
````

- [ ] **Step 4: Run the test to verify it passes**

````bash
cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart format lib/src/protocol/tool_rules.dart test/protocol/tool_rules_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (366 → 380).

- [ ] **Step 5: Commit**

````bash
git add packages/shellx_core/lib/src/protocol/tool_rules.dart packages/shellx_core/lib/shellx_core.dart packages/shellx_core/test/protocol/tool_rules_test.dart
git commit -m "feat(v2-tools): the tunnel's request and header rules (E9, E11), shared by both ends

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 3: Flow control shared by both ends: windows, acks, pacing, outlets and inlets

E7 and E8 in pure Dart (`dart:async`), so the desktop proxy (Tasks 5–6) and the phone's server (Task 9) move bytes the same way. **No byte is ever dropped**: an outlet that cannot send stops reading its source (`StreamSubscription.pause`), so back-pressure reaches the tool's or the web view's socket (Review Focus 3).
- **`ToolCredit` / `ToolSendWindow`:** a stream sends while its own 256 KiB window and its phone's 512 KiB have room; acks are cumulative; an ack beyond what was sent is refused (the caller ends the stream); a stream waiting on the shared window is woken by any other stream's ack.
- **`ToolAckBook`:** what this side took of every stream, in one `tool.ack` 50 ms after the first unacknowledged byte (so at most one per 50 ms).
- **`ToolPacer`:** `acquire(send)` grants one frame — at once when tokens are there and nobody waits, else in order; `send` returns the bytes it sent (charged then) or null (nothing charged). `ToolTokenPacer` (desktop: 8 MiB/s burst 1 MiB, 150 frames/s burst 16, injectable clock) and `ToolUnpaced` (phone: its outbox limits frames).
- **`ToolBytesOut`:** a byte stream as `tool.data` pieces ≤ 48 KiB, the last with `end`; reads ahead at most one piece; optional size limit.
- **`ToolBytesIn`:** pieces in order to a sink that takes them at its pace (`sink.addStream(inlet.stream)`); what the sink took is reported (to be acknowledged); refuses a piece past its window, its limit, or after its end; `fail` cuts the sink.
- **`ToolWsOut` / `ToolWsIn`:** WebSocket messages as `tool.ws.msg` pieces (`text`, `fin`); the inlet writes whole messages with `ws.addStream(Stream.value(m))` and holds acknowledgements while a message waits for the socket, so the sender stops after its window (bounded memory); a message over the limit is refused (close 1009); `discard()` stops sending but keeps reading so a closing WebSocket can finish its handshake.

**Files:**
- Create: `packages/shellx_core/lib/src/protocol/tool_flow.dart`
- Modify: `packages/shellx_core/lib/shellx_core.dart`
- Test: `packages/shellx_core/test/protocol/tool_flow_test.dart`

**Interfaces:**
- Consumes (Tasks 1, 2): `ToolMessage`, `ToolData`, `ToolAck`, `ToolWsMessage`, `kToolMaxChunkBytes`, `kToolMaxWsMessageBytes`.
- Produces (exported from `package:shellx_core/shellx_core.dart`):
  - `const int kToolStreamWindow = 256 * 1024`, `kToolPhoneWindow = 512 * 1024`; `const Duration kToolAckInterval = Duration(milliseconds: 50)`;
  - `final class ToolCredit { ToolCredit({int limit = kToolPhoneWindow}); int get inFlight; }`;
  - `final class ToolSendWindow { ToolSendWindow(ToolCredit credit, {int limit = kToolStreamWindow}); int get sent; int get acked; int get inFlight; bool canSend(int bytes); void onSent(int bytes); bool onAck(int total); void close(); }`;
  - `abstract interface class ToolPacer { void Function() acquire(int? Function() send); }`; `final class ToolUnpaced implements ToolPacer { const ToolUnpaced(); }`; `final class ToolTokenPacer implements ToolPacer { ToolTokenPacer({int bytesPerSecond = 8 * 1024 * 1024, int byteBurst = 1024 * 1024, int framesPerSecond = 150, int frameBurst = 16, int Function()? clock}); }` (`clock`: microseconds, monotonic);
  - `final class ToolAckBook { ToolAckBook(void Function(ToolAck ack) send, {Duration interval = kToolAckInterval}); void consumed(int id, int total); void forget(int id); void clear(); }`;
  - `final class ToolBytesOut { ToolBytesOut({required int id, required Stream<List<int>> source, required ToolSendWindow window, required ToolPacer pacer, required void Function(ToolMessage message) send, int? maxBytes, void Function()? onTooLarge, void Function(Object error)? onError, void Function()? onDone}); bool get finished; void start(); bool onAck(int total); void cancel(); }`;
  - `final class ToolBytesIn { ToolBytesIn({required void Function(int total) onConsumed, int window = kToolStreamWindow, int? maxBytes}); int get received; bool get ended; late final Stream<List<int>> stream; bool add(Uint8List data, {required bool end}); void fail(Object error); }`;
  - `final class ToolWsOut { ToolWsOut({required int id, required Stream<Object?> source, required ToolSendWindow window, required ToolPacer pacer, required void Function(ToolMessage message) send, int maxMessage = kToolMaxWsMessageBytes, void Function()? onTooBig, void Function()? onDone}); void start(); bool onAck(int total); void stop(); void cancel(); void discard(); }`;
  - `final class ToolWsIn { ToolWsIn({required Future<void> Function(Object message) write, required void Function(int total) onConsumed, int window = kToolStreamWindow, int maxMessage = kToolMaxWsMessageBytes}); bool get busy; Future<void> get idle; bool add(ToolWsMessage piece); }`.

- [ ] **Step 1: Write the failing test**

`packages/shellx_core/test/protocol/tool_flow_test.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

Uint8List _bytes(int length, [int seed = 0]) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) & 0xFF,
]);

/// V2-4 E7, E8: windows, acknowledgements, pacing; byte and WebSocket
/// streams in and out.
void main() {
  group('windows (E7)', () {
    test('a stream stops at 256 KiB in flight, a phone at 512 KiB', () {
      final credit = ToolCredit();
      final a = ToolSendWindow(credit);
      final b = ToolSendWindow(credit);
      final c = ToolSendWindow(credit);
      a.onSent(kToolStreamWindow);
      expect(a.canSend(1), isFalse);
      b.onSent(kToolStreamWindow);
      expect(c.canSend(1), isFalse, reason: 'the phone has 512 KiB in flight');
      expect(a.onAck(1024), isTrue);
      expect(c.canSend(1024), isTrue);
      expect(c.canSend(1025), isFalse);
    });

    test(
      'an ack beyond what was sent is refused; closing frees the window',
      () {
        final credit = ToolCredit();
        final a = ToolSendWindow(credit)..onSent(100);
        expect(a.onAck(101), isFalse);
        expect(a.onAck(50), isTrue);
        expect(a.onAck(40), isTrue, reason: 'an old ack changes nothing');
        expect(credit.inFlight, 50);
        a.close();
        expect(credit.inFlight, 0);
        expect(a.canSend(1), isFalse, reason: 'a closed stream sends nothing');
      },
    );
  });

  group('ack book (E8)', () {
    test('every stream in one tool.ack, at most one per 50 ms', () {
      fakeAsync((async) {
        final sent = <ToolAck>[];
        final book = ToolAckBook(sent.add);
        book.consumed(1, 10);
        book.consumed(2, 5);
        book.consumed(1, 30);
        book.consumed(1, 20); // older: ignored
        async.elapse(const Duration(milliseconds: 49));
        expect(sent, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(sent.single.acks, [1, 30, 2, 5]);
        book.consumed(2, 9);
        book.forget(2);
        book.consumed(3, 1);
        async.elapse(const Duration(milliseconds: 50));
        expect(sent.last.acks, [3, 1]);
        expect(sent, hasLength(2));
        book.consumed(4, 1);
        book.clear();
        async.elapse(const Duration(seconds: 1));
        expect(sent, hasLength(2));
      });
    });
  });

  group('token pacer (E7, RF 2)', () {
    test('≤ 150 frames and ≤ 8 MiB per second, whatever is asked', () {
      fakeAsync((async) {
        final pacer = ToolTokenPacer(clock: () => async.elapsed.inMicroseconds);
        final grants = <Duration>[];
        var bytes = 0;
        // Three greedy streams of full frames for 10 s.
        void stream() {
          pacer.acquire(() {
            grants.add(async.elapsed);
            bytes += kToolMaxChunkBytes;
            scheduleMicrotask(stream);
            return kToolMaxChunkBytes;
          });
        }

        stream();
        stream();
        stream();
        async.elapse(const Duration(seconds: 10));
        expect(grants.length, lessThanOrEqualTo(16 + 150 * 10));
        expect(
          bytes,
          lessThanOrEqualTo((1 + 8 * 10) * 1024 * 1024 + kToolMaxChunkBytes),
        );
        // Busy, it still sends: at least 90% of the rate (full frames reach
        // 150 × 48 KiB a second, a little under 8 MiB).
        const rate = 150 * kToolMaxChunkBytes;
        expect(bytes, greaterThan(rate * 10 * 0.9));
        // Any one second holds at most a burst over the rate.
        for (var s = 0; s < 9; s++) {
          final inSecond = grants
              .where(
                (t) =>
                    t >= Duration(seconds: s) && t < Duration(seconds: s + 1),
              )
              .length;
          expect(inSecond, lessThanOrEqualTo(150 + 16), reason: 'second $s');
        }
      });
    });

    test('small frames are limited by count: 150 per second', () {
      fakeAsync((async) {
        final pacer = ToolTokenPacer(clock: () => async.elapsed.inMicroseconds);
        var frames = 0;
        void stream() {
          pacer.acquire(() {
            frames++;
            scheduleMicrotask(stream);
            return 10;
          });
        }

        stream();
        async.elapse(const Duration(seconds: 4));
        expect(frames, lessThanOrEqualTo(16 + 150 * 4));
        expect(frames, greaterThan(150 * 4 * 0.9));
      });
    });

    test('in order; a withdrawn request is never granted; nothing sent, '
        'nothing charged', () {
      fakeAsync((async) {
        final pacer = ToolTokenPacer(
          framesPerSecond: 10,
          frameBurst: 1,
          clock: () => async.elapsed.inMicroseconds,
        );
        final order = <String>[];
        pacer.acquire(() {
          order.add('a');
          return 1;
        });
        pacer.acquire(() {
          order.add('b');
          return 1;
        });
        final withdraw = pacer.acquire(() {
          order.add('c');
          return 1;
        });
        pacer.acquire(() {
          order.add('d');
          return null; // sent nothing: the next one gets this frame
        });
        pacer.acquire(() {
          order.add('e');
          return 1;
        });
        withdraw();
        async.elapse(const Duration(milliseconds: 100));
        expect(order, ['a', 'b'], reason: 'one frame per 100 ms');
        async.elapse(const Duration(milliseconds: 100));
        expect(order, ['a', 'b', 'd', 'e']);
      });
    });
  });

  group('bytes out (E7, RF 3)', () {
    test('never more than the window in flight; the source pauses and every '
        'byte arrives once, in order', () {
      fakeAsync((async) {
        final source = StreamController<List<int>>();
        var pauses = 0;
        source.onPause = () => pauses++;
        final body = _bytes(1024 * 1024 + 17);
        final credit = ToolCredit();
        final window = ToolSendWindow(credit);
        final got = BytesBuilder();
        var ended = false;
        var maxInFlight = 0;
        late ToolBytesOut out;
        out = ToolBytesOut(
          id: 3,
          source: source.stream,
          window: window,
          pacer: const ToolUnpaced(),
          send: (m) {
            final data = m as ToolData;
            expect(data.data.length, lessThanOrEqualTo(kToolMaxChunkBytes));
            got.add(data.data);
            ended = data.end;
            if (window.inFlight > maxInFlight) maxInFlight = window.inFlight;
          },
        )..start();
        for (var at = 0; at < body.length; at += 7000) {
          source.add(
            body.sublist(at, at + 7000 > body.length ? body.length : at + 7000),
          );
        }
        unawaited(source.close());
        async.flushMicrotasks();
        // The peer acknowledges slowly, a little at a time.
        var acked = 0;
        while (!ended) {
          async.elapse(const Duration(milliseconds: 10));
          acked = got.length < acked + 40000 ? got.length : acked + 40000;
          expect(out.onAck(acked), isTrue);
          async.flushMicrotasks();
        }
        expect(maxInFlight, lessThanOrEqualTo(kToolStreamWindow));
        expect(pauses, greaterThan(0));
        expect(got.takeBytes(), body);
      });
    });

    test('streams share the phone\'s 512 KiB', () {
      fakeAsync((async) {
        final credit = ToolCredit();
        final windows = [
          ToolSendWindow(credit),
          ToolSendWindow(credit),
          ToolSendWindow(credit),
        ];
        var peak = 0;
        for (final (i, window) in windows.indexed) {
          final source = StreamController<List<int>>();
          ToolBytesOut(
            id: i,
            source: source.stream,
            window: window,
            pacer: const ToolUnpaced(),
            send: (_) {
              if (credit.inFlight > peak) peak = credit.inFlight;
            },
          ).start();
          source.add(_bytes(400 * 1024));
        }
        async.flushMicrotasks();
        expect(peak, lessThanOrEqualTo(kToolPhoneWindow));
        expect(
          credit.inFlight,
          greaterThan(kToolPhoneWindow - kToolMaxChunkBytes),
        );
        // One stream's ack lets another go on.
        windows[0].onAck(windows[0].sent);
        async.flushMicrotasks();
        expect(peak, lessThanOrEqualTo(kToolPhoneWindow));
        expect(
          windows[1].sent + windows[2].sent,
          greaterThan(kToolPhoneWindow - windows[0].sent),
        );
      });
    });

    test('an empty body is one empty piece with end; a body over its limit '
        'stops reading', () {
      fakeAsync((async) {
        final sent = <ToolData>[];
        final empty = StreamController<List<int>>();
        ToolBytesOut(
          id: 1,
          source: empty.stream,
          window: ToolSendWindow(ToolCredit()),
          pacer: const ToolUnpaced(),
          send: (m) => sent.add(m as ToolData),
        ).start();
        unawaited(empty.close());
        async.flushMicrotasks();
        expect(sent.single.end, isTrue);
        expect(sent.single.data, isEmpty);

        final big = StreamController<List<int>>();
        var cancelled = false;
        big.onCancel = () => cancelled = true;
        var tooLarge = false;
        ToolBytesOut(
          id: 2,
          source: big.stream,
          window: ToolSendWindow(ToolCredit()),
          pacer: const ToolUnpaced(),
          send: (_) {},
          maxBytes: 1000,
          onTooLarge: () => tooLarge = true,
        ).start();
        big.add(_bytes(600));
        big.add(_bytes(600));
        async.flushMicrotasks();
        expect(tooLarge, isTrue);
        expect(cancelled, isTrue);
      });
    });
  });

  group('bytes in (E7)', () {
    test('what the sink takes is reported; more than the window, after the '
        'end or past the limit is refused', () async {
      final consumed = <int>[];
      final inlet = ToolBytesIn(onConsumed: consumed.add, maxBytes: 100);
      final sink = <int>[];
      final done = inlet.stream.forEach(sink.addAll);
      expect(inlet.add(_bytes(60), end: false), isTrue);
      expect(inlet.add(_bytes(40), end: true), isTrue);
      expect(inlet.add(_bytes(1), end: true), isFalse);
      await done;
      expect(sink, hasLength(100));
      expect(consumed.last, 100);

      final small = ToolBytesIn(onConsumed: (_) {}, window: 10);
      // Nobody takes the bytes yet: 11 in flight is more than the window.
      expect(small.add(_bytes(10), end: false), isTrue);
      expect(small.add(_bytes(1), end: false), isFalse);

      final limited = ToolBytesIn(onConsumed: (_) {}, maxBytes: 5);
      expect(limited.add(_bytes(6), end: false), isFalse);
    });

    test('fail cuts the sink with an error', () async {
      final inlet = ToolBytesIn(onConsumed: (_) {});
      final done = inlet.stream.drain<void>();
      inlet.add(_bytes(3), end: false);
      inlet.fail(StateError('cut'));
      await expectLater(done, throwsStateError);
    });
  });

  group('WebSocket out and in (E7, E10)', () {
    test(
      'a long message goes in pieces, the last with fin; text stays text',
      () {
        fakeAsync((async) {
          final source = StreamController<Object?>();
          final window = ToolSendWindow(ToolCredit());
          final pieces = <ToolWsMessage>[];
          final out = ToolWsOut(
            id: 5,
            source: source.stream,
            window: window,
            pacer: const ToolUnpaced(),
            send: (m) => pieces.add(m as ToolWsMessage),
          )..start();
          final long = 'ả' * 100000; // 300 000 UTF-8 bytes
          source
            ..add(long)
            ..add(Uint8List.fromList([1, 2]));
          async.flushMicrotasks();
          // 256 KiB went out; the rest waits for an ack.
          expect(window.inFlight, lessThanOrEqualTo(kToolStreamWindow));
          out.onAck(window.sent);
          async.flushMicrotasks();
          expect(pieces.where((p) => p.fin), hasLength(2));
          final text = pieces.where((p) => p.text).toList();
          expect(
            text.every((p) => p.data.length <= kToolMaxChunkBytes),
            isTrue,
          );
          expect(text.last.fin, isTrue);
          expect(utf8.decode([for (final p in text) ...p.data]), long);
          expect(pieces.last.text, isFalse);
          expect(pieces.last.data, [1, 2]);
        });
      },
    );

    test('a message over 16 MiB stops the stream (close 1009)', () {
      fakeAsync((async) {
        final source = StreamController<Object?>();
        var tooBig = false;
        ToolWsOut(
          id: 1,
          source: source.stream,
          window: ToolSendWindow(ToolCredit()),
          pacer: const ToolUnpaced(),
          send: (_) {},
          onTooBig: () => tooBig = true,
        ).start();
        source.add(Uint8List(kToolMaxWsMessageBytes + 1));
        async.flushMicrotasks();
        expect(tooBig, isTrue);
      });
    });

    test('pieces are put together and written in order; what follows a '
        'message waiting to be written is not acknowledged', () async {
      final written = <Object>[];
      final consumed = <int>[];
      final gate = Completer<void>();
      final inlet = ToolWsIn(
        write: (m) async {
          written.add(m);
          if (written.length == 1) await gate.future;
        },
        onConsumed: consumed.add,
      );
      final hello = utf8.encode('hello');
      expect(
        inlet.add(
          ToolWsMessage(
            id: 1,
            data: Uint8List.sublistView(hello, 0, 2),
            text: true,
            fin: false,
          ),
        ),
        isTrue,
      );
      expect(consumed, [2], reason: 'a message being put together is taken');
      expect(
        inlet.add(
          ToolWsMessage(
            id: 1,
            data: Uint8List.sublistView(hello, 2),
            text: true,
            fin: true,
          ),
        ),
        isTrue,
      );
      expect(written, ['hello']);
      expect(
        inlet.add(
          ToolWsMessage(id: 1, data: Uint8List(4), text: false, fin: true),
        ),
        isTrue,
      );
      expect(consumed, [2], reason: 'held while "hello" waits for the socket');
      gate.complete();
      await inlet.idle;
      expect(written, hasLength(2));
      expect(consumed.last, 9);
    });

    test('a piece that changes the kind, or a message over the limit, is '
        'refused', () {
      final inlet = ToolWsIn(
        write: (_) async {},
        onConsumed: (_) {},
        maxMessage: 10,
      );
      expect(
        inlet.add(
          ToolWsMessage(id: 1, data: Uint8List(4), text: true, fin: false),
        ),
        isTrue,
      );
      expect(
        inlet.add(
          ToolWsMessage(id: 1, data: Uint8List(4), text: false, fin: true),
        ),
        isFalse,
      );
      final small = ToolWsIn(
        write: (_) async {},
        onConsumed: (_) {},
        maxMessage: 10,
      );
      expect(
        small.add(
          ToolWsMessage(id: 1, data: Uint8List(6), text: false, fin: false),
        ),
        isTrue,
      );
      expect(
        small.add(
          ToolWsMessage(id: 1, data: Uint8List(6), text: false, fin: true),
        ),
        isFalse,
      );
    });
  });
}
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test test/protocol/tool_flow_test.dart`
Expected: FAIL to compile — `ToolCredit`, `ToolSendWindow`, `ToolTokenPacer` … are not defined.

- [ ] **Step 3: Write the flow control**

`packages/shellx_core/lib/src/protocol/tool_flow.dart`:

````dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'messages.dart';
import 'tool_rules.dart';

/// V2-4 E7: the unacknowledged bytes one stream may have in flight, per
/// direction.
const int kToolStreamWindow = 256 * 1024;

/// V2-4 E7: the unacknowledged bytes all the streams of one phone may have in
/// flight, per direction (the relay then never holds much for it, and its
/// heartbeat is still answered).
const int kToolPhoneWindow = 512 * 1024;

/// V2-4 E8, §5: one `tool.ack` (for every stream) at most this often.
const Duration kToolAckInterval = Duration(milliseconds: 50);

/// V2-4 E7: the bytes in flight to one peer over all its streams, in one
/// direction. A stream sends only while its own window and this one have
/// room; a stream blocked here is woken when another stream's bytes are
/// acknowledged.
final class ToolCredit {
  ToolCredit({this.limit = kToolPhoneWindow});

  final int limit;
  int _inFlight = 0;
  final _waiting = <void Function()>{};

  int get inFlight => _inFlight;

  bool _hasRoom(int bytes) => _inFlight + bytes <= limit;

  void _release(int bytes) {
    if (bytes <= 0) return;
    _inFlight -= bytes;
    if (_waiting.isEmpty) return;
    final waiting = [..._waiting];
    _waiting.clear();
    for (final wake in waiting) {
      wake();
    }
  }
}

/// V2-4 E7: one stream's bytes in flight in one direction, against its own
/// window and its peer's [credit]. Acknowledgements are cumulative.
final class ToolSendWindow {
  ToolSendWindow(this.credit, {this.limit = kToolStreamWindow});

  final ToolCredit credit;
  final int limit;
  int _sent = 0;
  int _acked = 0;
  bool _closed = false;

  int get sent => _sent;
  int get acked => _acked;
  int get inFlight => _sent - _acked;

  /// Room for [bytes] more in this window and in the peer's.
  bool canSend(int bytes) =>
      !_closed && inFlight + bytes <= limit && credit._hasRoom(bytes);

  void onSent(int bytes) {
    _sent += bytes;
    credit._inFlight += bytes;
  }

  /// [total] bytes were taken. False when that is more than was sent: the
  /// peer breaks the protocol (the caller ends the stream).
  bool onAck(int total) {
    if (total > _sent) return false;
    if (total <= _acked || _closed) return true;
    final freed = total - _acked;
    _acked = total;
    credit._release(freed);
    return true;
  }

  /// The stream is over: what it had in flight no longer counts.
  void close() {
    if (_closed) return;
    _closed = true;
    final freed = inFlight;
    _acked = _sent;
    credit._release(freed);
  }

  void _waitForCredit(void Function() wake) => credit._waiting.add(wake);
  void _stopWaiting(void Function() wake) => credit._waiting.remove(wake);
}

/// What lets a stream send one frame of data (V2-4 E7).
abstract interface class ToolPacer {
  /// [send] runs once a frame is granted: at once when the tokens are there
  /// and nobody waits, else in turn. It returns the bytes it sent, which are
  /// charged then, or null when it sent nothing (nothing is charged). The
  /// returned function withdraws a request not granted yet.
  void Function() acquire(int? Function() send);
}

/// No pacing: the phone's tool outbox limits its own frames (V2-4 E8).
final class ToolUnpaced implements ToolPacer {
  const ToolUnpaced();

  @override
  void Function() acquire(int? Function() send) {
    send();
    return () {};
  }
}

/// V2-4 E7: all the tool data of a computer stays under [bytesPerSecond]
/// and [framesPerSecond] (token buckets of [byteBurst] and [frameBurst]),
/// so terminals, AI and heartbeats keep room under the relay's 500 frames
/// per second. Requests are granted in order. The byte bucket may go into
/// debt by one frame (a grant charges what was sent).
final class ToolTokenPacer implements ToolPacer {
  ToolTokenPacer({
    this.bytesPerSecond = 8 * 1024 * 1024,
    this.byteBurst = 1024 * 1024,
    this.framesPerSecond = 150,
    this.frameBurst = 16,
    int Function()? clock,
  }) : _clock = clock ?? _stopwatch() {
    _frames = frameBurst * _unit;
    _bytes = byteBurst * _unit;
    _last = _clock();
  }

  final int bytesPerSecond;
  final int byteBurst;
  final int framesPerSecond;
  final int frameBurst;

  /// Microseconds from any fixed start (monotonic).
  final int Function() _clock;

  /// Tokens are kept ×1e6, so a microsecond adds the per-second rate.
  static const _unit = 1000000;
  late int _frames;
  late int _bytes;
  late int _last;
  final _queue = Queue<_Grant>();
  Timer? _timer;

  static int Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  void _refill() {
    final now = _clock();
    final elapsed = now - _last;
    _last = now;
    if (elapsed <= 0) return;
    _frames = min(frameBurst * _unit, _frames + elapsed * framesPerSecond);
    _bytes = min(byteBurst * _unit, _bytes + elapsed * bytesPerSecond);
  }

  bool get _grantable => _frames >= _unit && _bytes > 0;

  void _charge(int? bytes) {
    if (bytes == null) return;
    _frames -= _unit;
    _bytes -= bytes * _unit;
  }

  @override
  void Function() acquire(int? Function() send) {
    _refill();
    if (_queue.isEmpty && _grantable) {
      _charge(send());
      return () {};
    }
    final grant = _Grant(send);
    _queue.add(grant);
    _schedule();
    return () => _queue.remove(grant);
  }

  void _schedule() {
    if (_timer != null || _queue.isEmpty) return;
    final frames = max(0, _unit - _frames);
    final bytes = max(0, 1 - _bytes);
    final wait = max(
      (frames + framesPerSecond - 1) ~/ framesPerSecond,
      (bytes + bytesPerSecond - 1) ~/ bytesPerSecond,
    );
    _timer = Timer(Duration(microseconds: wait), _fire);
  }

  void _fire() {
    _timer = null;
    _refill();
    while (_queue.isNotEmpty && _grantable) {
      _charge(_queue.removeFirst().send());
    }
    _schedule();
  }
}

final class _Grant {
  _Grant(this.send);
  final int? Function() send;
}

/// V2-4 E8, §5: what this side took of each stream, acknowledged together in
/// one `tool.ack` [interval] after the first unacknowledged byte (so at most
/// one per [interval]: each ack is a relay frame).
final class ToolAckBook {
  ToolAckBook(this._send, {this.interval = kToolAckInterval});

  final void Function(ToolAck ack) _send;
  final Duration interval;
  final _pending = <int, int>{};
  Timer? _timer;

  /// Every byte of stream [id] up to [total] was taken.
  void consumed(int id, int total) {
    final before = _pending[id];
    if (before != null && before >= total) return;
    _pending[id] = total;
    _timer ??= Timer(interval, _flush);
  }

  /// Stream [id] is over: nothing more is acknowledged for it.
  void forget(int id) => _pending.remove(id);

  /// The channel is gone: nothing pending is sent.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void _flush() {
    _timer = null;
    if (_pending.isEmpty) return;
    final acks = [
      for (final MapEntry(:key, :value) in _pending.entries) ...[key, value],
    ];
    _pending.clear();
    _send(ToolAck(acks));
  }
}

/// Pieces of the bytes [take] removes from the front of a queue of chunks.
final class _ByteQueue {
  final _chunks = Queue<Uint8List>();
  int length = 0;

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    length += chunk.length;
  }

  Uint8List take(int count) {
    final out = Uint8List(count);
    var at = 0;
    while (at < count) {
      final head = _chunks.first;
      final n = min(head.length, count - at);
      out.setRange(at, at + n, head);
      at += n;
      if (n == head.length) {
        _chunks.removeFirst();
      } else {
        _chunks
          ..removeFirst()
          ..addFirst(Uint8List.sublistView(head, n));
      }
    }
    length -= count;
    return out;
  }
}

/// V2-4 E7: a byte stream (a response body on the desktop, a request body on
/// the phone) sent as `tool.data` pieces of at most [kToolMaxChunkBytes],
/// within [window] and as [pacer] allows. When it cannot send, it stops
/// reading [source] (never drops a byte); acknowledgements ([onAck]) let it
/// go on. The last piece carries `end`.
final class ToolBytesOut {
  ToolBytesOut({
    required this.id,
    required Stream<List<int>> source,
    required this.window,
    required this.pacer,
    required void Function(ToolMessage message) send,
    this.maxBytes,
    this.onTooLarge,
    this.onError,
    this.onDone,
  }) : _source = source,
       _send = send;

  final int id;
  final ToolSendWindow window;
  final ToolPacer pacer;
  final void Function(ToolMessage message) _send;
  final Stream<List<int>> _source;

  /// Past this many bytes the source is dropped and [onTooLarge] called.
  final int? maxBytes;
  final void Function()? onTooLarge;

  /// The source failed: nothing more is sent (the caller ends the stream).
  final void Function(Object error)? onError;

  /// The last piece went out.
  final void Function()? onDone;

  final _buffer = _ByteQueue();
  StreamSubscription<List<int>>? _subscription;
  bool _paused = false;

  /// A frame was asked of [pacer] and not granted yet.
  bool _asked = false;
  void Function()? _withdraw;
  int _total = 0;
  bool _ended = false;
  bool _finished = false;
  bool _cancelled = false;

  bool get finished => _finished;

  void start() {
    _subscription = _source.listen(
      _onData,
      onError: (Object error) {
        _stop();
        onError?.call(error);
      },
      onDone: () {
        _ended = true;
        _pump();
      },
      cancelOnError: true,
    );
  }

  void _onData(List<int> chunk) {
    if (_cancelled) return;
    _total += chunk.length;
    final limit = maxBytes;
    if (limit != null && _total > limit) {
      _stop();
      onTooLarge?.call();
      return;
    }
    _buffer.add(chunk);
    if (_buffer.length >= kToolMaxChunkBytes && !_paused) {
      _paused = true; // a full piece waits: read no more (never drop)
      _subscription?.pause();
    }
    _pump();
  }

  /// The peer took [total] bytes. False when that is more than was sent.
  bool onAck(int total) {
    if (!window.onAck(total)) return false;
    _pump();
    return true;
  }

  void _pump() {
    if (_cancelled || _finished || _asked) return;
    if (_buffer.length == 0) {
      if (_ended) _finish(Uint8List(0));
      return;
    }
    final size = min(_buffer.length, kToolMaxChunkBytes);
    if (!window.canSend(size)) {
      // Our own window opens with our acks; the shared one with anyone's.
      window._waitForCredit(_pump);
      return;
    }
    _asked = true;
    final withdraw = pacer.acquire(_sendOne);
    if (_asked) _withdraw = withdraw; // not granted at once
  }

  int? _sendOne() {
    _asked = false;
    _withdraw = null;
    if (_cancelled || _finished || _buffer.length == 0) return null;
    final size = min(_buffer.length, kToolMaxChunkBytes);
    if (!window.canSend(size)) {
      scheduleMicrotask(_pump);
      return null;
    }
    final data = _buffer.take(size);
    final last = _ended && _buffer.length == 0;
    window.onSent(size);
    _send(ToolData(id: id, data: data, end: last));
    if (last) {
      _finished = true;
      onDone?.call();
    } else {
      if (_paused && _buffer.length < kToolMaxChunkBytes) {
        _paused = false;
        _subscription?.resume();
      }
      scheduleMicrotask(_pump);
    }
    return size;
  }

  void _finish(Uint8List data) {
    _finished = true;
    _send(ToolData(id: id, data: data, end: true));
    onDone?.call();
  }

  void _stop() {
    _cancelled = true;
    _asked = false;
    _withdraw?.call();
    _withdraw = null;
    window._stopWaiting(_pump);
    unawaited(_subscription?.cancel());
  }

  /// Stops reading and sending; the window no longer counts it.
  void cancel() {
    _stop();
    window.close();
  }
}

/// V2-4 E7: the bytes of a stream as they arrive (`tool.data`), handed on in
/// order through [stream] to a sink that takes them at its own pace (an HTTP
/// request or response: `sink.addStream(inlet.stream)`). What the sink took
/// is reported to [onConsumed] (cumulative), which acknowledges it.
final class ToolBytesIn {
  ToolBytesIn({
    required void Function(int total) onConsumed,
    this.window = kToolStreamWindow,
    this.maxBytes,
  }) : _onConsumed = onConsumed;

  final void Function(int total) _onConsumed;
  final int window;

  /// More than this in all: [add] says no (413 on the phone, `too_large`
  /// from the desktop).
  final int? maxBytes;
  final _controller = StreamController<List<int>>();
  int _received = 0;
  int _consumed = 0;
  bool _ended = false;

  int get received => _received;
  bool get ended => _ended;

  /// Listen once.
  late final Stream<List<int>> stream = _controller.stream.map((chunk) {
    _consumed += chunk.length;
    _onConsumed(_consumed);
    return chunk;
  });

  /// A piece arrived. False when it breaks the rules (after the end, more in
  /// flight than [window], past [maxBytes]): the caller ends the stream.
  bool add(Uint8List data, {required bool end}) {
    if (_ended) return false;
    _received += data.length;
    if (_received - _consumed > window) return false;
    final limit = maxBytes;
    if (limit != null && _received > limit) return false;
    if (data.isNotEmpty) _controller.add(data);
    if (end) {
      _ended = true;
      unawaited(_controller.close());
    }
    return true;
  }

  /// Cuts the sink: [error] ends [stream] (an HTTP response the webview gets
  /// is then incomplete, never a clean end).
  void fail(Object error) {
    if (_controller.isClosed) return;
    _ended = true;
    _controller.addError(error);
    unawaited(_controller.close());
  }
}

/// V2-4 E7: the messages of a WebSocket ([source]: `String` or bytes) sent as
/// `tool.ws.msg` pieces of at most [kToolMaxChunkBytes], the last with
/// `fin`, within [window] and as [pacer] allows. While a message waits to go
/// it stops reading [source]. A message over [maxMessage] calls [onTooBig]
/// (the caller closes with 1009). [onDone]: the source ended and everything
/// went out.
final class ToolWsOut {
  ToolWsOut({
    required this.id,
    required Stream<Object?> source,
    required this.window,
    required this.pacer,
    required void Function(ToolMessage message) send,
    this.maxMessage = kToolMaxWsMessageBytes,
    this.onTooBig,
    this.onDone,
  }) : _source = source,
       _send = send;

  final int id;
  final ToolSendWindow window;
  final ToolPacer pacer;
  final void Function(ToolMessage message) _send;
  final Stream<Object?> _source;
  final int maxMessage;
  final void Function()? onTooBig;
  final void Function()? onDone;

  final _messages = Queue<({Uint8List bytes, bool text})>();
  int _offset = 0; // into the first message
  int _queued = 0;
  StreamSubscription<Object?>? _subscription;
  bool _paused = false;
  bool _asked = false;
  void Function()? _withdraw;
  bool _ended = false;
  bool _stopped = false;

  void start() {
    _subscription = _source.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: () {
        _ended = true;
        _pump();
      },
    );
  }

  void _onMessage(Object? message) {
    if (_stopped) return;
    final text = message is String;
    final bytes = switch (message) {
      final String s => utf8.encode(s),
      final Uint8List b => b,
      final List<int> b => Uint8List.fromList(b),
      _ => null,
    };
    if (bytes == null) return;
    if (bytes.length > maxMessage) {
      stop();
      onTooBig?.call();
      return;
    }
    _messages.add((bytes: bytes, text: text));
    _queued += bytes.length;
    if (_queued >= kToolMaxChunkBytes && !_paused) {
      _paused = true;
      _subscription?.pause();
    }
    _pump();
  }

  bool onAck(int total) {
    if (!window.onAck(total)) return false;
    _pump();
    return true;
  }

  int get _nextSize =>
      min(_messages.first.bytes.length - _offset, kToolMaxChunkBytes);

  void _pump() {
    if (_stopped || _asked) return;
    if (_messages.isEmpty) {
      if (_ended) {
        _stopped = true;
        onDone?.call();
      }
      return;
    }
    if (!window.canSend(_nextSize)) {
      window._waitForCredit(_pump);
      return;
    }
    _asked = true;
    final withdraw = pacer.acquire(_sendOne);
    if (_asked) _withdraw = withdraw; // not granted at once
  }

  int? _sendOne() {
    _asked = false;
    _withdraw = null;
    if (_stopped || _messages.isEmpty) return null;
    final size = _nextSize;
    if (!window.canSend(size)) {
      scheduleMicrotask(_pump);
      return null;
    }
    final message = _messages.first;
    final piece = Uint8List.sublistView(message.bytes, _offset, _offset + size);
    _offset += size;
    final fin = _offset == message.bytes.length;
    if (fin) {
      _messages.removeFirst();
      _offset = 0;
    }
    _queued -= size;
    window.onSent(size);
    _send(ToolWsMessage(id: id, data: piece, text: message.text, fin: fin));
    if (_paused && _queued < kToolMaxChunkBytes) {
      _paused = false;
      _subscription?.resume();
    }
    scheduleMicrotask(_pump);
    return size;
  }

  /// Stops reading and sending (the window still counts what was sent).
  void stop() {
    _stopped = true;
    _asked = false;
    _withdraw?.call();
    _withdraw = null;
    window._stopWaiting(_pump);
    unawaited(_subscription?.cancel());
  }

  /// [stop], and the window no longer counts it.
  void cancel() {
    stop();
    window.close();
  }

  /// Stops sending but keeps reading [source], dropping what comes, so a
  /// closing WebSocket can finish its handshake.
  void discard() {
    _stopped = true;
    _asked = false;
    _withdraw?.call();
    _withdraw = null;
    window._stopWaiting(_pump);
    _messages.clear();
    _queued = 0;
    if (_paused) {
      _paused = false;
      _subscription?.resume();
    }
  }
}

/// V2-4 E7: WebSocket pieces as they arrive (`tool.ws.msg`), put together and
/// written in order with [write] (`ws.addStream(Stream.value(message))`,
/// which completes once the socket took it). Bytes are acknowledged
/// ([onConsumed]) while nothing waits to be written; while a message waits,
/// what follows is held unacknowledged, so the sender stops after its
/// window. A message over [maxMessage], a piece that changes the kind of
/// its message, or more in flight than [window]: [add] says no.
final class ToolWsIn {
  ToolWsIn({
    required Future<void> Function(Object message) write,
    required void Function(int total) onConsumed,
    this.window = kToolStreamWindow,
    this.maxMessage = kToolMaxWsMessageBytes,
  }) : _write = write,
       _onConsumed = onConsumed;

  final Future<void> Function(Object message) _write;
  final void Function(int total) _onConsumed;
  final int window;
  final int maxMessage;
  final _parts = BytesBuilder(copy: false);
  bool _text = false;
  final _queue = Queue<Object>();
  Future<void>? _writing;
  int _received = 0;
  int _consumed = 0;
  bool _failed = false;
  Completer<void>? _idle;

  /// Whether a message is still waiting to be written (or being written).
  bool get busy => _writing != null || _queue.isNotEmpty;

  /// Completes once everything that arrived was written.
  Future<void> get idle {
    if (!busy) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  bool add(ToolWsMessage piece) {
    if (_failed) return false;
    _received += piece.data.length;
    if (_received - _consumed > window) return false;
    if (_parts.isEmpty) {
      _text = piece.text;
    } else if (piece.text != _text) {
      return false;
    }
    if (_parts.length + piece.data.length > maxMessage) return false;
    _parts.add(piece.data);
    if (piece.fin) {
      final bytes = _parts.takeBytes();
      _queue.add(_text ? utf8.decode(bytes, allowMalformed: true) : bytes);
    }
    _writeNext();
    _report();
    return true;
  }

  void _writeNext() {
    if (_writing != null || _queue.isEmpty || _failed) return;
    _writing = _write(_queue.removeFirst()).then(
      (_) {
        _writing = null;
        _writeNext();
        _report();
      },
      onError: (Object _) {
        _writing = null;
        _failed = true;
        _queue.clear();
        _report();
      },
    );
  }

  void _report() {
    if (busy) return;
    final idle = _idle;
    _idle = null;
    idle?.complete();
    if (_failed || _consumed == _received) return;
    _consumed = _received;
    _onConsumed(_consumed);
  }
}
````

In `packages/shellx_core/lib/shellx_core.dart`, after `export 'src/protocol/batches.dart';` add:

````dart
export 'src/protocol/tool_flow.dart';
````

- [ ] **Step 4: Run the test to verify it passes**

````bash
cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart format lib/src/protocol/tool_flow.dart test/protocol/tool_flow_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (380 → 395). The pacer tests run in fake time (`fakeAsync` with `clock: () => async.elapsed.inMicroseconds`), so they take milliseconds.

- [ ] **Step 5: Commit**

````bash
git add packages/shellx_core/lib/src/protocol/tool_flow.dart packages/shellx_core/lib/shellx_core.dart packages/shellx_core/test/protocol/tool_flow_test.dart
git commit -m "feat(v2-tools): flow control both ends share (E7, E8): windows, coalesced acks, token pacing, sources paused, never a byte dropped

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 4: `ToolEndpoint`, its process-lifetime slot, the router's `tool.*` case, and the channel's tool-data flush

The `ai.*` pattern of V2-2 Task 3, for tools.
- **`ToolEndpoint`:** `outbound`, `serving`, `handle` (synchronous: E9 "handle không bao giờ await I/O" — `AgentService` handles one message at a time), `phoneGone`, `allPhonesGone`.
- **`ToolEndpointSlot`:** lives for the process (`SessionCore`, Task 11); forwards to its target, else is not `serving` and answers "unavailable" (`tool.list.result {available: false}`, `tool.opened {ok: false, code: unavailable}`, `tool.end {unavailable}`).
- **`SessionRouter`:** an optional `tools` endpoint; `case ToolMessage(): _tools?.handle(…)`; `tools: 1` in `session.list.result` only for `desktop: true` and only while the endpoint `serving` (R2); a phone leaving, a revoke, a stop and a quit reach the endpoint. Without an endpoint `tool.*` is ignored, like an older agent.
- **`AgentChannel`:** pending tool data (`tool.data`, `tool.ws.msg`) reaching 48 KiB flushes at once (E7), like terminal output at 16 KiB.

**Files:**
- Create: `packages/shellx_agent/lib/src/tool/tool_endpoint.dart`
- Modify: `packages/shellx_agent/lib/src/session/session_router.dart`
- Modify: `packages/shellx_agent/lib/src/service/agent_channel.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/tool/tool_router_test.dart`; Modify: `packages/shellx_agent/test/service/agent_channel_test.dart`

**Interfaces:**
- Consumes (Task 1): `ToolMessage` and its kinds, `ToolCode`, `kToolProtocol`, `kToolMaxChunkBytes`.
- Produces (exported from `package:shellx_agent/shellx_agent.dart`):
  - `abstract interface class ToolEndpoint { Stream<OutboundMessage> get outbound; bool get serving; void handle(String mobileId, ToolMessage message); void phoneGone(String mobileId); void allPhonesGone(); }`;
  - `final Uint8List emptyToolListingBody` (`{"v":1,"tools":[]}`); `ToolMessage? toolUnavailableReply(ToolMessage message)`;
  - `final class ToolEndpointSlot implements ToolEndpoint { ToolEndpoint? target; }` (settable `target`);
  - `SessionRouter({…, AiEndpoint? ai, ToolEndpoint? tools})`;
  - `const int kToolFlushThresholdBytes = kToolMaxChunkBytes` (in `agent_channel.dart`, not exported, like `kFlushThresholdBytes`).

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/tool/tool_router_test.dart`:

````dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// Records every call; answers nothing.
final class _SpyEndpoint implements ToolEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final handled = <(String, ToolMessage)>[];
  final gone = <String>[];
  var allGone = 0;

  @override
  bool serving = true;

  void say(String mobileId, ToolMessage m) =>
      _out.add(OutboundMessage(mobileId, m));

  @override
  Stream<OutboundMessage> get outbound => _out.stream;
  @override
  void handle(String mobileId, ToolMessage message) =>
      handled.add((mobileId, message));
  @override
  void phoneGone(String mobileId) => gone.add(mobileId);
  @override
  void allPhonesGone() => allGone++;
}

(SessionRouter, List<OutboundMessage>) _router({ToolEndpoint? tools}) {
  var next = 10;
  int ids() => next++;
  final router = SessionRouter(
    shells: SessionManager(
      ptyFactory: FakePtyFactory(),
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      nextId: ids,
    ),
    desktop: DesktopSessionManager(nextId: ids),
    desktopSharing: () => true,
    tools: tools,
  );
  final sent = <OutboundMessage>[];
  router.outbound.listen(sent.add);
  return (router, sent);
}

/// V2-4 E5, E6: the session router routes `tool.*`; the slot answers while
/// no proxy serves.
void main() {
  group('session router', () {
    test('tools: 1 only while an endpoint serves, only to a desktop: true '
        'list', () {
      fakeAsync((async) {
        final spy = _SpyEndpoint();
        final (withTools, sentA) = _router(tools: spy);
        withTools.handle(phone, const SessionList(desktop: true));
        withTools.handle(phone, const SessionList());
        spy.serving = false;
        withTools.handle(phone, const SessionList(desktop: true));
        final (without, sentB) = _router();
        without.handle(phone, const SessionList(desktop: true));
        async.flushMicrotasks();
        final a = sentA.map((o) => o.message as SessionListResult).toList();
        expect(a.map((r) => r.tools), [kToolProtocol, null, null]);
        expect((sentB.single.message as SessionListResult).tools, isNull);
      });
    });

    test('tool.* goes to the endpoint, its answers to the phone; a phone '
        'leaving, a revoke and a stop are told', () {
      final spy = _SpyEndpoint();
      final (router, sent) = _router(tools: spy);
      router.handle(phone, const ToolList());
      spy.say(phone, const ToolEnd(id: 1, code: 'aborted'));
      router.mobileDisconnected(phone);
      router.closeSessionsAttachedTo(phone);
      router.disconnectAllPhones();
      router.closeAll();
      expect(spy.handled.single.$2, isA<ToolList>());
      expect(sent.single.message, isA<ToolEnd>());
      expect(spy.gone, [phone, phone]);
      expect(spy.allGone, 2);
    });

    test('without an endpoint tool.* is ignored, like an older agent', () {
      final (router, sent) = _router();
      router.handle(phone, const ToolOpen(rid: 1, tool: 'k3f9za7q1m'));
      expect(sent, isEmpty);
    });
  });

  group('slot', () {
    test('not serving and answers unavailable until a proxy is set, then '
        'forwards', () {
      final slot = ToolEndpointSlot();
      final out = <OutboundMessage>[];
      slot.outbound.listen(out.add);
      expect(slot.serving, isFalse);
      slot.handle(phone, const ToolList());
      slot.handle(phone, const ToolOpen(rid: 4, tool: 'k3f9za7q1m'));
      slot.handle(
        phone,
        const ToolRequest(
          id: 9,
          tool: 'k3f9za7q1m',
          method: 'GET',
          target: '/',
          head: [],
          end: true,
        ),
      );
      slot.handle(phone, const ToolAck([9, 1]));
      expect(out.map((o) => o.message), [
        ToolListResult(available: false, body: emptyToolListingBody),
        const ToolOpened(rid: 4, ok: false, code: 'unavailable'),
        const ToolEnd(id: 9, code: 'unavailable'),
      ]);
      final spy = _SpyEndpoint();
      slot.target = spy;
      expect(slot.serving, isTrue);
      slot.handle(phone, const ToolList());
      spy.say(phone, const ToolEnd(id: 2));
      expect(spy.handled, hasLength(1));
      expect(out.last.message, const ToolEnd(id: 2));
      slot.phoneGone(phone);
      slot.allPhonesGone();
      expect(spy.gone, [phone]);
      expect(spy.allGone, 1);
      slot.target = null;
      expect(slot.serving, isFalse);
      spy.say(phone, const ToolEnd(id: 3));
      expect(out.last.message, const ToolEnd(id: 2), reason: 'unplugged');
    });
  });
}
````

In `packages/shellx_agent/test/service/agent_channel_test.dart`, add before the test `'a burst of full chunks is split into payloads that fit a frame'`:

````dart
  test(
    'pending tool data reaching 48 KiB is flushed immediately (V2-4 E7)',
    () {
      fakeAsync((async) {
        final (agentSide, phoneSide) = drive(async, securePair());
        final sent = <DataFrame>[];
        final channel = newChannel(agentSide, sent);
        channel.enqueue(
          ToolData(id: 1, data: Uint8List(30 * 1024), end: false),
        );
        async.flushMicrotasks();
        expect(sent, isEmpty, reason: 'below 48 KiB the 16 ms timer sends it');
        channel.enqueue(
          ToolWsMessage(
            id: 2,
            data: Uint8List(18 * 1024),
            text: false,
            fin: true,
          ),
        );
        async.flushMicrotasks();
        expect(sent, hasLength(1));
        expect(openFrame(async, phoneSide, sent.single).map((m) => m.type), [
          'tool.data',
          'tool.ws.msg',
        ]);
        channel.enqueue(
          ToolData(id: 1, data: Uint8List(kToolMaxChunkBytes), end: false),
        );
        async.flushMicrotasks();
        expect(sent, hasLength(2), reason: 'a full chunk goes at once');
      });
    },
  );
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/tool/tool_router_test.dart test/service/agent_channel_test.dart`
Expected: FAIL to compile — `ToolEndpoint`, `ToolEndpointSlot` and `SessionRouter`'s `tools` are not defined.

- [ ] **Step 3: Write the endpoint and its slot**

`packages/shellx_agent/lib/src/tool/tool_endpoint.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';

/// V2-4 E5: where the `tool.*` messages of phones go, and where the answers
/// come from. The process that holds the relay serves them with a
/// `ToolProxy` (the window in-process, the background service otherwise);
/// the session router only routes.
abstract interface class ToolEndpoint {
  /// Messages to phones, in order (a synchronous broadcast stream: a
  /// listener must not call back into the endpoint from its callback).
  Stream<OutboundMessage> get outbound;

  /// Whether this process serves tools to phones (E6: only then does
  /// `session.list.result` carry `tools`).
  bool get serving;

  /// One `tool.*` message from phone [mobileId] (paired and trusted: only an
  /// established channel delivers messages). Returns at once: every network
  /// step runs in the background (the agent handles one message at a time).
  void handle(String mobileId, ToolMessage message);

  /// The channel to [mobileId] is gone, or the phone was revoked.
  void phoneGone(String mobileId);

  /// Every phone is gone (the relay link stopped).
  void allPhonesGone();
}

/// The list body when nobody serves tools.
final Uint8List emptyToolListingBody = Uint8List.fromList(
  utf8.encode('{"v":1,"tools":[]}'),
);

/// What a desktop answers when no proxy serves tools (V2-4 E5): the list is
/// unavailable, an open and a stream end `unavailable`. Null for messages
/// that need no answer.
ToolMessage? toolUnavailableReply(ToolMessage message) => switch (message) {
  ToolList() => ToolListResult(available: false, body: emptyToolListingBody),
  ToolOpen(:final rid) => ToolOpened(
    rid: rid,
    ok: false,
    code: ToolCode.unavailable,
  ),
  ToolRequest(:final id) => ToolEnd(id: id, code: ToolCode.unavailable),
  _ => null,
};

/// The router's [ToolEndpoint] for the life of a process (V2-4 E5): forwards
/// to [target]; without one it is not [serving] and answers
/// [toolUnavailableReply].
final class ToolEndpointSlot implements ToolEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  ToolEndpoint? _target;
  StreamSubscription<OutboundMessage>? _forward;

  ToolEndpoint? get target => _target;

  set target(ToolEndpoint? endpoint) {
    if (identical(endpoint, _target)) return;
    unawaited(_forward?.cancel());
    _target = endpoint;
    _forward = endpoint?.outbound.listen(_out.add);
  }

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  bool get serving => _target?.serving ?? false;

  @override
  void handle(String mobileId, ToolMessage message) {
    final target = _target;
    if (target != null) return target.handle(mobileId, message);
    final reply = toolUnavailableReply(message);
    if (reply != null) _out.add(OutboundMessage(mobileId, reply));
  }

  @override
  void phoneGone(String mobileId) => _target?.phoneGone(mobileId);

  @override
  void allPhonesGone() => _target?.allPhonesGone();
}
````

In `packages/shellx_agent/lib/shellx_agent.dart`, after `export 'src/term/terminal_sharing.dart';` add:

````dart
export 'src/tool/tool_endpoint.dart';
````

- [ ] **Step 4: Route `tool.*`**

In `packages/shellx_agent/lib/src/session/session_router.dart`:

1. After `import '../term/desktop_session_manager.dart';` add `import '../tool/tool_endpoint.dart';`.
2. Replace the constructor's tail:

````dart
    AiEndpoint? ai,
  }) : _shells = shells,
       _desktop = desktop,
       _desktopSharing = desktopSharing,
       _ai = ai {
````

with:

````dart
    AiEndpoint? ai,
    ToolEndpoint? tools,
  }) : _shells = shells,
       _desktop = desktop,
       _desktopSharing = desktopSharing,
       _ai = ai,
       _tools = tools {
````

   and in its subscription list, after `?ai?.outbound.listen(_outbound.add),` add `?tools?.outbound.listen(_outbound.add),`.
3. After the field `final AiEndpoint? _ai;` add:

````dart

  /// V2-4 E5: where `tool.*` messages go; null: this agent has no tools for
  /// phones (they are ignored, `session.list.result` carries no `tools`).
  final ToolEndpoint? _tools;
````

4. In `handle`, the `SessionList` case, after `ai: desktop && _ai != null ? kAiProtocol : null,` add:

````dart
            // V2-4 E6: and only while this process serves tools.
            tools: desktop && (_tools?.serving ?? false) ? kToolProtocol : null,
````

   and after the case `case AiMessage(): _ai?.handle(mobileId, message);` add:

````dart
      case ToolMessage():
        _tools?.handle(mobileId, message);
````

5. Add `_tools?.phoneGone(mobileId);` after `_ai?.phoneGone(mobileId);` in both `mobileDisconnected` and `closeSessionsAttachedTo`, and `_tools?.allPhonesGone();` after `_ai?.allPhonesGone();` in both `closeAll` and `disconnectAllPhones`.

- [ ] **Step 5: Flush full tool chunks at once**

In `packages/shellx_agent/lib/src/service/agent_channel.dart`:

1. After the constant `kFlushThresholdBytes` add:

````dart

/// Pending tool data that triggers an immediate flush (V2-4 E7): a full
/// `tool.data` or `tool.ws.msg` goes out at once, in a frame of its own.
const int kToolFlushThresholdBytes = kToolMaxChunkBytes;
````

2. In the class doc comment, replace "pending `output` data reaches [kFlushThresholdBytes]. A flush produces as" with "pending `output` data reaches [kFlushThresholdBytes], or pending tool data (`tool.data`, `tool.ws.msg`) [kToolFlushThresholdBytes]. A flush produces as".
3. After the field `int _pendingOutputBytes = 0;` add `int _pendingToolBytes = 0;`.
4. In `enqueue`, replace:

````dart
    if (message is OutputMessage) _pendingOutputBytes += message.data.length;
    if (_pendingOutputBytes >= kFlushThresholdBytes) {
````

with:

````dart
    switch (message) {
      case OutputMessage(:final data):
        _pendingOutputBytes += data.length;
      case ToolData(:final data) || ToolWsMessage(:final data):
        _pendingToolBytes += data.length;
      default:
        break;
    }
    if (_pendingOutputBytes >= kFlushThresholdBytes ||
        _pendingToolBytes >= kToolFlushThresholdBytes) {
````

5. In `flush`, after `_pendingOutputBytes = 0;` add `_pendingToolBytes = 0;`.

- [ ] **Step 6: Run the tests to verify they pass**

````bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format lib/src/tool/tool_endpoint.dart lib/src/session/session_router.dart lib/src/service/agent_channel.dart lib/shellx_agent.dart test/tool/tool_router_test.dart test/service/agent_channel_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (915 after Task 1 → 920).

- [ ] **Step 7: Commit**

````bash
git add packages/shellx_agent/lib/src/tool/tool_endpoint.dart packages/shellx_agent/lib/src/session/session_router.dart packages/shellx_agent/lib/src/service/agent_channel.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/tool/tool_router_test.dart packages/shellx_agent/test/service/agent_channel_test.dart
git commit -m "feat(v2-tools): ToolEndpoint and its slot, the router's tool.* case and tools flag, full tool chunks flushed at once

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 5: The desktop proxy: the list, opening, and HTTP to the tool's port only

`ToolProxy` (pure Dart, `shellx_agent`) implements `ToolEndpoint` for HTTP; a WebSocket request is answered `bad_request` until Task 6.
- **`ToolCatalog` / `ServedTool`** (`tool_catalog.dart`): the window's list as `tool.serve` carries it (`{"v": 1, "tools": [{"id", "name", "ws", "group", "url"}], "off": [ids]}`, at most 60 KiB and 1000 `off` ids, R3), checked again here (only `http` on `localhost`, `127.0.0.1` or `[::1]` with a port, V2-3 D15); `listingBody` (§4.2, ≤ 48 KiB), `openedBody` (E4: the tool, then one tool of its workspace per other port), `endCodeFor` (`disabled` for an `off` id, else `gone`).
- **`tool_forwarding.dart`** (E9): `connectToolPort` (127.0.0.1, then ::1, 5 s; never a name), `toolHttpClient` (every connection through that function, `findProxy` DIRECT, no unpacking, no `User-Agent` of its own), `toolUri` (built with `Uri(...)`, never concatenated), `forwardRequestHead` (E2/E3/E9: hop-by-hop, `Forwarded`, `X-Forwarded-*`, `Via` and gate cookies dropped; `Host` kept only when it names the tool's own port on a loopback spelling; `Origin`/`Referer` of the phone's origin rewritten in alias mode; cookies joined with `; `, R8), `forwardResponseHead` (E3/E11: `Location`/`Access-Control-Allow-Origin` rewritten in alias mode, `Set-Cookie: __shellx_*` dropped; null over 100 headers or 32 KiB → `too_large`, R13).
- **`ToolProxy`:**
  - `handle` returns at once; the phone flag is checked at every stream (`tool.open` and `tool.req`); the method, target and head are validated (Task 2);
  - E10: 32 HTTP streams per phone, 120 opens at once then 60 a second, a request body ≤ 64 MiB, a head within 60 s, a stream with bytes in flight and no ack for 5 min dropped;
  - each request opens a fresh connection to the tool's port: `followRedirects = false`, `bufferOutput = false` (R11);
  - the response flows through `ToolBytesOut` within the stream's and the phone's windows, paced for the whole computer (`ToolTokenPacer`, R9); the request body through `ToolBytesIn`, acknowledged as the tool takes it;
  - `serve` ends the streams of a tool that left the list (`disabled`/`gone`) or changed URL (`gone`) and sends phones that list the new list (once per change); `close` ends everything `desktop_closed`;
  - every message goes through `_emit`, which never sends one over a sealed batch (RF 1).
- **The test rig:**
  - a real tool on loopback (`TestTool`: routes, plus a WebSocket echo at `/ws` used from Task 6);
  - a phone in front of the proxy (`ToolPhone`): every message goes through the wire's encoding both ways and is delivered in a microtask, like the channel, because a listener of the proxy's broadcast stream must not call back into it synchronously;
  - `ToolPhone` acknowledges at once, or on demand to test windows.

**Files:**
- Create: `packages/shellx_agent/lib/src/tool/tool_catalog.dart`, `packages/shellx_agent/lib/src/tool/tool_forwarding.dart`, `packages/shellx_agent/lib/src/tool/tool_proxy.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/support/tool_rig.dart`, `packages/shellx_agent/test/tool/tool_proxy_http_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: the `tool.*` messages, `ToolCode`, `toolHeadBytes`, `kToolMaxChunkBytes`, `kToolMaxHeaders`, `kToolMaxHeadBytes`;
  - Task 2: `isToolMethod`, `isToolTarget`, `isToolHead`, `isWritableHeaderValue`, `toolDroppedNames`, `stripToolGateCookies`, `setsToolGateCookie`, `isToolLoopbackAuthority`, `toolLoopbackPrefix`, `kToolMaxHttpStreams`, `kToolMaxRequestBodyBytes`, `kToolMaxWsMessageBytes`;
  - Task 3: `ToolCredit`, `ToolSendWindow`, `ToolPacer`, `ToolTokenPacer`, `ToolAckBook`, `ToolBytesOut`, `ToolBytesIn`;
  - Task 4: `ToolEndpoint`, `emptyToolListingBody`, `toolUnavailableReply`.
- Produces (exported):
  - `tool_catalog.dart`:
    - `const int kToolServeMaxBytes = 60 * 1024; const int kToolServeMaxOff = 1000;`
    - `final class ServedTool { final String id, name, ws, group, url, host; final int port; final String path; String get hostHeader; String get origin; static ServedTool? fromJson(Object? json); Map<String, Object?> toJson(); }`
    - `final class ToolCatalog { ToolCatalog(List<ServedTool> tools, {Set<String> off = const {}}); final List<ServedTool> tools; final Set<String> off; static ToolCatalog? fromServeBody(Uint8List body); static Uint8List serveBody(List<Map<String, Object?>> tools, {Iterable<String> off = const []}); ServedTool? byId(String id); String endCodeFor(String id); Uint8List listingBody(); Uint8List openedBody(ServedTool tool); }`
  - `tool_forwarding.dart`:
    - `const Duration kToolConnectTimeout = Duration(seconds: 5), kToolHeadTimeout = Duration(seconds: 60), kToolIdleTimeout = Duration(minutes: 5);` (three declarations)
    - `Future<Socket> connectToolPort(int port, {Duration timeout = kToolConnectTimeout});`
    - `typedef ToolConnect = Future<Socket> Function(int port);`
    - `HttpClient toolHttpClient(ToolConnect connect);`
    - `Uri toolUri(ServedTool tool, String target);`
    - `final class ToolForwardedHead { final String host; final List<(String, String)> headers; final int? contentLength; void applyTo(HttpClientRequest request); }`
    - `ToolForwardedHead forwardRequestHead(List<String> head, ServedTool tool, {int? alias, bool ws = false});`
    - `List<String> flatHeaders(HttpHeaders headers);`
    - `List<String>? forwardResponseHead(List<String> raw, ServedTool tool, {int? alias});`
  - `tool_proxy.dart`:
    - `const int kToolOpenBurst = 120; const int kToolOpensPerSecond = 60;`
    - `final class ToolProxy implements ToolEndpoint { ToolProxy({ToolPacer? pacer, ToolConnect? connect, Duration headTimeout = kToolHeadTimeout, Duration idleTimeout = kToolIdleTimeout, int maxRequestBody = kToolMaxRequestBodyBytes, int maxWsMessage = kToolMaxWsMessageBytes}); final ToolPacer pacer; ToolCatalog? get catalog; void serve(ToolCatalog? catalog); void close(); }`

- [ ] **Step 1: Write the test rig**

`packages/shellx_agent/test/support/tool_rig.dart`:

````dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// Polls [condition] every 10 ms until it holds (fails after [timeout]).
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// One request a [TestTool] got.
final class ToolHit {
  ToolHit(this.method, this.uri, this.headers);
  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
}

/// A personal web tool on this computer: HTTP routes on a real loopback
/// server, and a WebSocket echo at `/ws` (a `close:<code>` text closes with
/// that code).
final class TestTool {
  TestTool._(this.server, this.routes) {
    server.listen(_serve);
  }

  static Future<TestTool> start({
    Map<String, Future<void> Function(HttpRequest request)> routes = const {},
    InternetAddress? address,
  }) async => TestTool._(
    await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, 0),
    {...routes},
  );

  final HttpServer server;
  final Map<String, Future<void> Function(HttpRequest request)> routes;
  final hits = <ToolHit>[];

  /// The close code and reason of each WebSocket that closed.
  final wsClosed = <(int?, String?)>[];
  final _sockets = <WebSocket>[];

  int get port => server.port;

  Future<void> _serve(HttpRequest request) async {
    final headers = <String, List<String>>{};
    request.headers.forEach((name, values) => headers[name] = values);
    hits.add(ToolHit(request.method, request.uri, headers));
    final route = routes[request.uri.path];
    if (route != null) return route(request);
    if (request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final ws = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (offered) => offered.first,
      );
      _sockets.add(ws);
      ws.listen((message) {
        if (message is String && message.startsWith('close:')) {
          unawaited(ws.close(int.parse(message.substring(6)), 'by tool'));
        } else {
          ws.add(message);
        }
      }, onDone: () => wsClosed.add((ws.closeCode, ws.closeReason)));
      return;
    }
    request.response
      ..headers.contentType = ContentType.html
      ..write('<h1>${request.uri.path}</h1>');
    await request.response.close();
  }

  /// The JSON entry the window would serve for this tool.
  Map<String, Object?> entry({
    String id = 'k3f9za7q1m',
    String name = 'Bảng việc',
    String host = 'localhost',
    String path = '/',
    String group = 'ws:a',
  }) => {
    'id': id,
    'name': name,
    'ws': 'shop-web',
    'group': group,
    'url': 'http://$host:$port$path',
  };

  Future<void> close() async {
    for (final ws in _sockets) {
      await ws.close().catchError((Object _) => null);
    }
    await server.close(force: true);
  }
}

/// [tools] as the window would serve them.
ToolCatalog catalogOf(
  List<Map<String, Object?>> tools, {
  Iterable<String> off = const [],
}) => ToolCatalog.fromServeBody(ToolCatalog.serveBody(tools, off: off))!;

/// A phone in front of a [ToolProxy]: every message goes through the wire's
/// encoding both ways; the bodies it gets are acknowledged at once unless
/// [autoAck] is off.
final class ToolPhone {
  ToolPhone(this.proxy, {this.mobileId = phone}) {
    // In a microtask, like the channel: a listener of the proxy's stream
    // must not call back into it (its acks would).
    proxy.outbound
        .where((o) => o.mobileId == mobileId)
        .listen(
          (o) => scheduleMicrotask(
            () => _receive(_wire(o.message) as ToolMessage),
          ),
        );
  }

  final ToolProxy proxy;
  final String mobileId;
  bool autoAck = true;
  final messages = <ToolMessage>[];
  final _bodies = <int, BytesBuilder>{};
  final _received = <int, int>{};
  final _acked = <int, int>{};
  final _ends = <int, Completer<void>>{};
  final _responses = <int, Completer<ToolResponse>>{};
  final _listings = StreamController<ToolListResult>.broadcast();

  /// The most this phone had received and not acknowledged, per stream.
  final maxUnacked = <int, int>{};

  /// When each `tool.data` and `tool.ws.msg` with bytes arrived.
  final dataTimes = <Duration>[];
  final clock = Stopwatch()..start();
  int nextId = 1;

  static AppMessage _wire(AppMessage m) => decodeBatch(encodeBatch([m])).single;

  void send(ToolMessage message) =>
      proxy.handle(mobileId, _wire(message) as ToolMessage);

  Stream<ToolListResult> get listings => _listings.stream;

  void _receive(ToolMessage message) {
    messages.add(message);
    switch (message) {
      case ToolListResult():
        _listings.add(message);
      case ToolResponse(:final id, :final end):
        (_responses[id] ??= Completer()).complete(message);
        if (end) (_ends[id] ??= Completer()).complete();
      case ToolData(:final id, :final data, :final end):
        if (data.isNotEmpty) dataTimes.add(clock.elapsed);
        (_bodies[id] ??= BytesBuilder(copy: false)).add(data);
        _count(id, data.length);
        if (end) (_ends[id] ??= Completer()).complete();
      case ToolWsMessage(:final id, :final data):
        if (data.isNotEmpty) dataTimes.add(clock.elapsed);
        _count(id, data.length);
      case ToolEnd(:final id):
        final done = _ends[id] ??= Completer();
        if (!done.isCompleted) done.complete();
        final res = _responses[id];
        if (res != null && !res.isCompleted) {
          res.completeError(StateError('ended before a response'));
        }
      default:
        break;
    }
  }

  void _count(int id, int bytes) {
    final received = _received[id] = (_received[id] ?? 0) + bytes;
    final unacked = received - (_acked[id] ?? 0);
    if (unacked > (maxUnacked[id] ?? 0)) maxUnacked[id] = unacked;
    if (autoAck) ackAll();
  }

  /// Acknowledges everything received so far.
  void ackAll() {
    final acks = <int>[
      for (final MapEntry(:key, :value) in _received.entries)
        if ((_acked[key] ?? 0) < value) ...[key, value],
    ];
    if (acks.isEmpty) return;
    for (var i = 0; i < acks.length; i += 2) {
      _acked[acks[i]] = acks[i + 1];
    }
    send(ToolAck(acks));
  }

  /// Sends a request; its id.
  int request(
    String tool, {
    String method = 'GET',
    String target = '/',
    List<String> head = const [],
    int? alias,
    bool ws = false,
    bool end = true,
  }) {
    final id = nextId++;
    send(
      ToolRequest(
        id: id,
        tool: tool,
        method: method,
        target: target,
        head: head,
        alias: alias,
        ws: ws,
        end: end,
      ),
    );
    return id;
  }

  Future<ToolResponse> response(int id) => (_responses[id] ??= Completer())
      .future
      .timeout(const Duration(seconds: 10));

  /// Waits for the stream to end (its last piece, or `tool.end`).
  Future<void> ended(int id) =>
      (_ends[id] ??= Completer()).future.timeout(const Duration(seconds: 60));

  Uint8List body(int id) => _bodies[id]?.toBytes() ?? Uint8List(0);

  ToolEnd? endOf(int id) =>
      messages.whereType<ToolEnd>().where((m) => m.id == id).firstOrNull;

  List<ToolWsMessage> wsPieces(int id) =>
      messages.whereType<ToolWsMessage>().where((m) => m.id == id).toList();
}
````

- [ ] **Step 2: Write the failing tests**

`packages/shellx_agent/test/tool/tool_proxy_http_test.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/tool_rig.dart';

const _id = 'k3f9za7q1m';

/// V2-4 E9, E10, §8: the desktop proxy against a real tool on loopback.
void main() {
  late TestTool tool;
  late ToolProxy proxy;
  late ToolPhone phone;

  Future<void> setUpWith({
    Map<String, Future<void> Function(HttpRequest)> routes = const {},
    ToolProxy? withProxy,
  }) async {
    tool = await TestTool.start(routes: routes);
    proxy = withProxy ?? ToolProxy();
    proxy.serve(catalogOf([tool.entry()]));
    phone = ToolPhone(proxy);
  }

  tearDown(() async {
    proxy.close();
    await tool.close();
  });

  group('a page', () {
    test('GET goes to the tool; head and body come back; Host is the '
        "phone's own when it names the tool's port (E2)", () async {
      await setUpWith();
      final id = phone.request(
        _id,
        target: '/src/main.ts?t=1',
        head: ['host', 'localhost:${tool.port}', 'accept', '*/*'],
      );
      final response = await phone.response(id);
      await phone.ended(id);
      expect(response.status, 200);
      expect(
        toolHeadValues(response.head, 'content-type').single,
        contains('text/html'),
      );
      expect(utf8.decode(phone.body(id)), '<h1>/src/main.ts</h1>');
      final hit = tool.hits.single;
      expect(hit.uri.toString(), '/src/main.ts?t=1');
      expect(hit.headers['host'], ['localhost:${tool.port}']);
      expect(hit.headers['accept'], ['*/*']);
      expect(hit.headers['user-agent'], isNull, reason: 'no Dart user agent');
    });

    test('a 3xx is not followed: the phone gets it as is (RF 4)', () async {
      await setUpWith(
        routes: {
          '/go': (request) async {
            request.response
              ..statusCode = 302
              ..headers.set('location', 'http://evil.com/');
            await request.response.close();
          },
        },
      );
      final id = phone.request(_id, target: '/go');
      final response = await phone.response(id);
      expect(response.status, 302);
      expect(toolHeadValues(response.head, 'location'), ['http://evil.com/']);
      await phone.ended(id);
      expect(tool.hits, hasLength(1));
    });

    test('a body is passed through untouched (no unpacking)', () async {
      final gzipped = gzip.encode(utf8.encode('x' * 10000));
      await setUpWith(
        routes: {
          '/z': (request) async {
            request.response.headers.set('content-encoding', 'gzip');
            request.response.add(gzipped);
            await request.response.close();
          },
        },
      );
      final id = phone.request(
        _id,
        target: '/z',
        head: ['accept-encoding', 'gzip, br'],
      );
      await phone.ended(id);
      expect(phone.body(id), gzipped);
      expect(tool.hits.single.headers['accept-encoding'], ['gzip, br']);
    });

    test(
      'a POST body streams to the tool; what it took is acknowledged',
      () async {
        final got = Completer<List<int>>();
        final answer = Completer<void>();
        await setUpWith(
          routes: {
            '/up': (request) async {
              got.complete(
                await request.fold<List<int>>([], (a, b) => a..addAll(b)),
              );
              await answer.future;
              await request.response.close();
            },
          },
        );
        final id = phone.request(
          _id,
          method: 'POST',
          target: '/up',
          head: ['content-type', 'application/json'],
          end: false,
        );
        final body = utf8.encode('{"title":"Bảng việc"}');
        phone.send(
          ToolData(id: id, data: Uint8List.sublistView(body, 0, 5), end: false),
        );
        phone.send(
          ToolData(id: id, data: Uint8List.sublistView(body, 5), end: true),
        );
        expect(await got.future, body);
        await until(() => phone.messages.whereType<ToolAck>().isNotEmpty);
        expect(phone.messages.whereType<ToolAck>().last.acks, [
          id,
          body.length,
        ]);
        answer.complete();
        await phone.ended(id);
      },
    );
  });

  group('only the tool, nothing else (E9, RF 4)', () {
    test('a target that is not origin form, a forbidden method, CRLF in a '
        'header: bad_request, nothing reaches the tool', () async {
      await setUpWith();
      final ids = [
        phone.request(_id, target: '@evil.com/'),
        phone.request(_id, target: 'http://evil.com/'),
        phone.request(_id, target: '//evil.com/x'),
        phone.request(_id, method: 'CONNECT', target: '/'),
        phone.request(_id, method: 'TRACE', target: '/'),
        phone.request(_id, head: ['x-a', 'b\r\nHost: evil.com']),
        phone.request(_id, head: ['bad name', 'v']),
      ];
      await pumpEventQueue();
      for (final id in ids) {
        expect(phone.endOf(id)?.code, 'bad_request', reason: 'stream $id');
      }
      expect(tool.hits, isEmpty);
    });

    test('a foreign Host is replaced with the tool\'s; hop-by-hop, '
        'forwarding headers and the gate cookie are dropped; cookies are '
        'joined', () async {
      await setUpWith();
      final id = phone.request(
        _id,
        head: [
          'host',
          'evil.com',
          'connection',
          'keep-alive, x-secret',
          'x-secret',
          '1',
          'x-forwarded-for',
          '10.0.0.1',
          'forwarded',
          'for=10.0.0.1',
          'via',
          '1.1 phone',
          'cookie',
          'sid=1; __shellx_${tool.port}=s3cr3t',
          'cookie',
          'theme=dark',
          'x-latin',
          'café',
        ],
      );
      await phone.ended(id);
      final headers = tool.hits.single.headers;
      expect(headers['host'], ['localhost:${tool.port}']);
      for (final name in [
        'x-secret',
        'x-forwarded-for',
        'forwarded',
        'via',
        'x-latin',
      ]) {
        expect(headers[name], isNull, reason: name);
      }
      expect(headers['cookie'], ['sid=1; theme=dark']);
    });

    test('http_proxy is ignored: the request never goes to a proxy', () async {
      await setUpWith();
      final trap = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var trapped = 0;
      trap.listen((r) {
        trapped++;
        r.response.close();
      });
      addTearDown(() => trap.close(force: true));
      await HttpOverrides.runZoned(() async {
        // The override works: a plain client in this zone goes to the trap.
        final plain = HttpClient();
        final r = await (await plain.get('localhost', tool.port, '/')).close();
        await r.drain<void>();
        plain.close();
        expect(trapped, 1);
        final id = phone.request(_id, target: '/through');
        await phone.ended(id);
      }, findProxyFromEnvironment: (_, _) => 'PROXY 127.0.0.1:${trap.port}');
      expect(trapped, 1, reason: 'the proxy went to the tool, not the trap');
      expect(tool.hits.map((h) => h.uri.path), contains('/through'));
    });

    test('a tool on ::1 only is reached; a name is never resolved', () async {
      await setUpWith();
      final six = await TestTool.start(address: InternetAddress.loopbackIPv6);
      addTearDown(six.close);
      proxy.serve(catalogOf([six.entry(host: '[::1]')]));
      final id = phone.request(_id, target: '/six');
      await phone.ended(id);
      expect(six.hits.single.headers['host'], ['[::1]:${six.port}']);
    });

    test('a tool not on the list: disabled when its flag is off, gone '
        'otherwise; never by URL', () async {
      await setUpWith();
      proxy.serve(catalogOf([tool.entry()], off: ['offtool111']));
      final a = phone.request('offtool111');
      final b = phone.request('unknown111');
      await pumpEventQueue();
      expect(phone.endOf(a)?.code, 'disabled');
      expect(phone.endOf(b)?.code, 'gone');
      expect(tool.hits, isEmpty);
    });

    test('nothing listens on the port: refused', () async {
      await setUpWith();
      final port = tool.port;
      await tool.server.close(force: true);
      final id = phone.request(_id);
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'refused');
      expect(port, greaterThan(0));
    });
  });

  group('the flag is checked at every stream (E9)', () {
    test('turning the flag off ends a stream that is open; removing the '
        'tool or changing its URL too', () async {
      final hold = <HttpResponse>[];
      await setUpWith(
        routes: {
          '/events': (request) async {
            request.response
              ..bufferOutput = false
              ..headers.contentType = ContentType('text', 'event-stream')
              ..write('data: 1\n\n');
            await request.response.flush();
            hold.add(request.response); // never closed: an endless stream
          },
        },
      );
      final a = phone.request(_id, target: '/events');
      await phone.response(a);
      proxy.serve(catalogOf([], off: [_id]));
      await phone.ended(a);
      expect(phone.endOf(a)?.code, 'disabled');
      final refused = phone.request(_id);
      await pumpEventQueue();
      expect(phone.endOf(refused)?.code, 'disabled', reason: 'checked again');

      proxy.serve(catalogOf([tool.entry()]));
      final b = phone.request(_id, target: '/events');
      await phone.response(b);
      proxy.serve(catalogOf([tool.entry(path: '/other')]));
      await phone.ended(b);
      expect(phone.endOf(b)?.code, 'gone', reason: 'its URL changed');

      final c = phone.request(_id, target: '/events');
      await phone.response(c);
      proxy.serve(catalogOf([]));
      await phone.ended(c);
      expect(phone.endOf(c)?.code, 'gone', reason: 'deleted');
    });
  });

  group('windows and pacing (E7, RF 2, RF 3)', () {
    test('50 MB arrive whole (SHA-256), ≤ 256 KiB unacknowledged, the tool '
        'paused, ≤ 150 frames and ≤ 8 MiB a second', () async {
      const size = 50 * 1000 * 1000;
      final sent = const DartSha256().newHashSink();
      await setUpWith(
        routes: {
          '/big': (request) async {
            request.response.contentLength = size;
            var seed = 1;
            for (var at = 0; at < size; at += 65536) {
              final chunk = Uint8List(at + 65536 > size ? size - at : 65536);
              for (var i = 0; i < chunk.length; i++) {
                seed = (seed * 1103515245 + 12345) & 0x7fffffff;
                chunk[i] = seed >> 16;
              }
              sent.add(chunk);
              request.response.add(chunk);
              await request.response.flush(); // honours back-pressure
            }
            await request.response.close();
          },
        },
      );
      phone.autoAck = false;
      final acking = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => phone.ackAll(),
      );
      addTearDown(acking.cancel);
      final id = phone.request(_id, target: '/big');
      await phone.ended(id);
      acking.cancel();
      final got = const DartSha256().newHashSink()..add(phone.body(id));
      sent.close();
      got.close();
      expect(phone.body(id).length, size);
      expect((await got.hash()).bytes, (await sent.hash()).bytes);
      expect(phone.maxUnacked[id], lessThanOrEqualTo(kToolStreamWindow));
      // Pacing over the whole transfer (a token bucket's burst on top).
      final seconds = phone.dataTimes.last.inMicroseconds / 1e6;
      expect(phone.dataTimes.length, lessThanOrEqualTo(16 + 150 * seconds));
      expect(size, lessThanOrEqualTo(1024 * 1024 + 8 * 1024 * 1024 * seconds));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('limits (E10)', () {
    test('more than 32 HTTP streams: busy', () async {
      final waiting = <HttpRequest>[];
      await setUpWith(
        routes: {'/hang': (request) async => waiting.add(request)},
      );
      final ids = [
        for (var i = 0; i < 33; i++) phone.request(_id, target: '/hang'),
      ];
      await pumpEventQueue();
      expect(phone.endOf(ids.last)?.code, 'busy');
      expect(ids.take(32).where((id) => phone.endOf(id) != null), isEmpty);
      for (final request in waiting) {
        unawaited(request.response.close());
      }
    });

    test('opens beyond 120 at once: busy', () async {
      await setUpWith();
      for (var rid = 1; rid <= 121; rid++) {
        phone.send(ToolOpen(rid: rid, tool: 'unknown111'));
      }
      await pumpEventQueue();
      final opened = phone.messages.whereType<ToolOpened>().toList();
      expect(
        opened.where((o) => o.code == 'busy').length,
        greaterThanOrEqualTo(1),
      );
    });

    test('a request body past the limit: too_large', () async {
      await setUpWith(
        routes: {
          '/up': (request) async {
            await request.drain<void>();
            await request.response.close();
          },
        },
        withProxy: ToolProxy(maxRequestBody: 1000),
      );
      final id = phone.request(_id, method: 'POST', target: '/up', end: false);
      phone.send(ToolData(id: id, data: Uint8List(600), end: false));
      phone.send(ToolData(id: id, data: Uint8List(600), end: true));
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'too_large');
    });

    test(
      'a response head over 32 KiB: too_large (the phone shows 502)',
      () async {
        await setUpWith(
          routes: {
            '/fat': (request) async {
              request.response.headers.set(
                'x-big',
                'x' * (kToolMaxHeadBytes + 1),
              );
              await request.response.close();
            },
          },
        );
        final id = phone.request(_id, target: '/fat');
        await phone.ended(id);
        expect(phone.endOf(id)?.code, 'too_large');
      },
    );

    test('no response head within the limit: timeout', () async {
      await setUpWith(
        routes: {'/slow': (request) async {}},
        withProxy: ToolProxy(headTimeout: const Duration(milliseconds: 200)),
      );
      final id = phone.request(_id, target: '/slow');
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'timeout');
    });

    test('bytes in flight and no ack for the idle limit: aborted', () async {
      await setUpWith(
        routes: {
          '/drip': (request) async {
            request.response
              ..bufferOutput = false
              ..add(Uint8List(1000));
            await request.response.flush();
          },
        },
        withProxy: ToolProxy(idleTimeout: const Duration(milliseconds: 300)),
      );
      phone.autoAck = false;
      final id = phone.request(_id, target: '/drip');
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'aborted');
    });
  });

  group('alias mode (E3): the phone serves on another port', () {
    test('Host is the tool\'s; Origin and Referer of the phone\'s origin '
        'become the tool\'s; Location and ACAO of the tool\'s come back as '
        'the phone\'s; a tool cookie named __shellx_ is dropped', () async {
      await setUpWith(
        routes: {
          '/login': (request) async {
            request.response
              ..statusCode = 303
              ..headers.set(
                'location',
                'http://localhost:${tool.port}/home?x=1',
              )
              ..headers.set(
                'access-control-allow-origin',
                'http://localhost:${tool.port}',
              )
              ..headers.add('set-cookie', 'sid=1; Path=/')
              ..headers.add(
                'set-cookie',
                '__shellx_${tool.port}=stolen; Path=/',
              );
            await request.response.close();
          },
        },
      );
      const alias = 49152;
      final id = phone.request(
        _id,
        target: '/login',
        alias: alias,
        head: [
          'host',
          'localhost:$alias',
          'origin',
          'http://localhost:$alias',
          'referer',
          'http://localhost:$alias/form?a=1',
        ],
      );
      final response = await phone.response(id);
      await phone.ended(id);
      final headers = tool.hits.single.headers;
      expect(headers['host'], ['localhost:${tool.port}']);
      expect(headers['origin'], ['http://localhost:${tool.port}']);
      expect(headers['referer'], ['http://localhost:${tool.port}/form?a=1']);
      expect(toolHeadValues(response.head, 'location'), [
        'http://localhost:$alias/home?x=1',
      ]);
      expect(toolHeadValues(response.head, 'access-control-allow-origin'), [
        'http://localhost:$alias',
      ]);
      expect(toolHeadValues(response.head, 'set-cookie'), ['sid=1; Path=/']);
    });

    test('another origin is passed through untouched', () async {
      await setUpWith();
      final id = phone.request(
        _id,
        alias: 49152,
        head: [
          'origin',
          'http://other.example',
          'referer',
          'http://other.example/x',
        ],
      );
      await phone.ended(id);
      final headers = tool.hits.single.headers;
      expect(headers['origin'], ['http://other.example']);
      expect(headers['referer'], ['http://other.example/x']);
    });
  });

  group('the list (§4.2) and opening (E4)', () {
    test('only tools on the list; again whenever it changes; nothing '
        'before the window said', () async {
      tool = await TestTool.start();
      proxy = ToolProxy();
      phone = ToolPhone(proxy);
      final listings = <ToolListResult>[];
      phone.listings.listen(listings.add);
      phone.send(const ToolList());
      await pumpEventQueue();
      expect(listings.single.available, isFalse);
      proxy.serve(
        catalogOf([tool.entry(), tool.entry(id: 'api0000001', name: 'API')]),
      );
      proxy.serve(
        catalogOf([tool.entry(), tool.entry(id: 'api0000001', name: 'API')]),
      );
      await pumpEventQueue();
      expect(
        listings,
        hasLength(2),
        reason: 'an unchanged list is not sent again',
      );
      final json =
          jsonDecode(utf8.decode(listings.last.body)) as Map<String, Object?>;
      expect(json['v'], 1);
      expect((json['tools']! as List).map((t) => (t as Map)['name']), [
        'Bảng việc',
        'API',
      ]);
      expect((json['tools']! as List).first, {
        'id': _id,
        'name': 'Bảng việc',
        'ws': 'shop-web',
        'port': tool.port,
        'path': '/',
        'group': 'ws:a',
      });
    });

    test('open: refused while nothing listens; then the tool and its '
        'workspace\'s other tools, one per port', () async {
      await setUpWith();
      final api = await TestTool.start();
      addTearDown(api.close);
      proxy.serve(
        catalogOf([
          tool.entry(path: '/app'),
          api.entry(id: 'api0000001', name: 'API', path: '/v1'),
          api.entry(id: 'api0000002', name: 'API 2'),
          tool.entry(id: 'other00001', group: 'ws:b'),
        ]),
      );
      phone.send(const ToolOpen(rid: 1, tool: _id));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final opened = phone.messages.whereType<ToolOpened>().single;
      expect(opened.ok, isTrue);
      final json =
          jsonDecode(utf8.decode(opened.body!)) as Map<String, Object?>;
      expect(json['tools'], [
        {'id': _id, 'port': tool.port, 'path': '/app'},
        {'id': 'api0000001', 'port': api.port, 'path': '/v1'},
      ]);
      await api.server.close(force: true);
      phone.send(const ToolOpen(rid: 2, tool: 'api0000001'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(phone.messages.whereType<ToolOpened>().last.code, 'refused');
    });
  });

  test('a phone that goes, and the window that quits (E5, E17)', () async {
    final hold = <HttpResponse>[];
    await setUpWith(
      routes: {
        '/events': (request) async {
          request.response
            ..bufferOutput = false
            ..write('data: 1\n\n');
          await request.response.flush();
          hold.add(request.response);
        },
      },
    );
    final a = phone.request(_id, target: '/events');
    await phone.response(a);
    proxy.phoneGone(phone.mobileId);
    await pumpEventQueue();
    expect(
      phone.endOf(a),
      isNull,
      reason: 'a phone that is gone hears nothing',
    );
    final other = ToolPhone(
      proxy,
      mobileId: 'b0000000-0000-4000-8000-000000000003',
    );
    other.send(const ToolList());
    final b = other.request(_id, target: '/events');
    await other.response(b);
    proxy.close();
    await pumpEventQueue();
    expect(other.endOf(b)?.code, 'desktop_closed');
    expect(other.messages.whereType<ToolListResult>().last.available, isFalse);
    expect(proxy.serving, isFalse);
  });

  test('toString never shows a URL or a name (E18)', () async {
    await setUpWith(); // the tear-down closes what it starts
    final catalog = catalogOf([
      {
        'id': _id,
        'name': 'Bảng việc',
        'ws': 'w',
        'group': 'g',
        'url': 'http://localhost:1/secret',
      },
    ]);
    expect(catalog.toString(), 'ToolCatalog(…)');
    expect(catalog.tools.single.toString(), 'ServedTool(…)');
    expect(
      forwardRequestHead(const [
        'cookie',
        'session=secret',
      ], catalog.tools.single).toString(),
      'ToolForwardedHead(…)',
    );
  });
}
````

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/tool/tool_proxy_http_test.dart`
Expected: FAIL to compile — `ToolProxy`, `ToolCatalog`, `ServedTool` and `connectToolPort` are not defined.

- [ ] **Step 4: Write the list the window serves**

`packages/shellx_agent/lib/src/tool/tool_catalog.dart`:

````dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// V2-4 E5: the largest `tool.serve` body (one mux frame holds 64 KiB).
const int kToolServeMaxBytes = 60 * 1024;

/// At most this many ids of tools with the phone flag off in a `tool.serve`
/// (one past it ends a stream `gone` rather than `disabled`).
const int kToolServeMaxOff = 1000;

/// V2-4 E1, E5: one tool the window lets phones open, as `tool.serve` carries
/// it: `{"id", "name", "ws", "group", "url"}`. Only `http` on `localhost`,
/// `127.0.0.1` or `[::1]` with a port 1–65535, no user info, no fragment
/// (V2-3 D15 `phoneAllowed`); the background service checks again what the
/// window sends.
final class ServedTool {
  const ServedTool._({
    required this.id,
    required this.name,
    required this.ws,
    required this.group,
    required this.url,
    required this.host,
    required this.port,
    required this.path,
  });

  /// V2-3 D2: 10 characters `[a-z0-9]`; any 1–64 of `[A-Za-z0-9_-]` here.
  final String id;
  final String name;

  /// The workspace's name, for the phone's row ("shop-web · localhost:5173").
  final String ws;

  /// The workspace's key: tools of one group are served together (E4).
  final String group;
  final String url;

  /// `localhost`, `127.0.0.1` or `::1`.
  final String host;
  final int port;

  /// The start page: path and query, `/` at least.
  final String path;

  /// What the tool sees in `Host` when the request does not name it itself.
  String get hostHeader => host == '::1' ? '[::1]:$port' : '$host:$port';

  /// `http://host:port`, the port always written.
  String get origin => 'http://$hostHeader';

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Null for an entry this version does not take (never throws).
  static ServedTool? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final ws = json['ws'];
    final group = json['group'];
    final url = json['url'];
    if (id is! String || !_id.hasMatch(id)) return null;
    if (name is! String || name.isEmpty || name.length > 200) return null;
    if (ws is! String || ws.length > 200) return null;
    if (group is! String || group.length > 200) return null;
    if (url is! String || url.length > 2048) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !const {'localhost', '127.0.0.1', '::1'}.contains(uri.host) ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    final path =
        (uri.path.isEmpty ? '/' : uri.path) +
        (uri.hasQuery ? '?${uri.query}' : '');
    if (!isToolTarget(path)) return null;
    return ServedTool._(
      id: id,
      name: name,
      ws: ws,
      group: group,
      url: url,
      host: uri.host,
      port: uri.port,
      path: path,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'ws': ws,
    'group': group,
    'url': url,
  };

  @override
  String toString() => 'ServedTool(…)';
}

/// V2-4 E5: the tools a phone may open now, and the ids of those that exist
/// with the phone flag off ([off]: a stream of one of them ends `disabled`,
/// of any other unknown id `gone`).
final class ToolCatalog {
  ToolCatalog(List<ServedTool> tools, {Set<String> off = const {}})
    : tools = List.unmodifiable(tools),
      off = Set.unmodifiable(off),
      _byId = {for (final tool in tools) tool.id: tool};

  final List<ServedTool> tools;
  final Set<String> off;
  final Map<String, ServedTool> _byId;

  /// `tool.serve`'s `b`: `{"v": 1, "tools": [...], "off": [...]}`. Entries
  /// this version does not take are left out; null when [body] is not such
  /// an object (never throws).
  static ToolCatalog? fromServeBody(Uint8List body) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
    if (json is! Map || json['v'] != 1 || json['tools'] is! List) return null;
    final tools = <ServedTool>[];
    final seen = <String>{};
    for (final entry in json['tools'] as List) {
      final tool = ServedTool.fromJson(entry);
      if (tool != null && seen.add(tool.id)) tools.add(tool);
    }
    final off = json['off'];
    return ToolCatalog(
      tools,
      off: {
        if (off is List)
          for (final id in off)
            if (id is String && !seen.contains(id)) id,
      },
    );
  }

  /// What the window sends (`tool.serve`'s `b`, or the in-process proxy's
  /// list): the same bytes either way. At most [kToolServeMaxBytes] (a mux
  /// frame is 64 KiB): the tools past that are left out, in order.
  static Uint8List serveBody(
    List<Map<String, Object?>> tools, {
    Iterable<String> off = const [],
  }) {
    final offIds = off.take(kToolServeMaxOff).toList();
    final kept = <Map<String, Object?>>[];
    var size = utf8
        .encode(jsonEncode({'v': 1, 'tools': [], 'off': offIds}))
        .length;
    for (final tool in tools) {
      final length = utf8.encode(jsonEncode(tool)).length + 1;
      if (size + length > kToolServeMaxBytes) break;
      size += length;
      kept.add(tool);
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'tools': kept, 'off': offIds})),
    );
  }

  ServedTool? byId(String id) => _byId[id];

  /// Why a stream of [id], not in [tools], ends.
  String endCodeFor(String id) =>
      off.contains(id) ? ToolCode.disabled : ToolCode.gone;

  /// V2-4 §4.2: `{"v": 1, "tools": [{"id", "name", "ws", "port", "path",
  /// "group"}]}`, at most [kToolMaxChunkBytes]: the tools past that are left
  /// out (in the window's order).
  Uint8List listingBody() {
    final entries = <Map<String, Object?>>[];
    var size = 20;
    for (final tool in tools) {
      final entry = {
        'id': tool.id,
        'name': tool.name,
        'ws': tool.ws,
        'port': tool.port,
        'path': tool.path,
        'group': tool.group,
      };
      final length = utf8.encode(jsonEncode(entry)).length + 1;
      if (size + length > kToolMaxChunkBytes) break;
      size += length;
      entries.add(entry);
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'tools': entries})),
    );
  }

  /// V2-4 E4: what a phone serves when it opens [tool]: [tool] first, then
  /// the other tools of its workspace, one per port, at most
  /// [kToolMaxChunkBytes] in all (the main tool always fits: its path is at
  /// most 8 KiB).
  Uint8List openedBody(ServedTool tool) {
    final ports = <int>{tool.port};
    final served = [
      {'id': tool.id, 'port': tool.port, 'path': tool.path},
    ];
    var size = utf8.encode(jsonEncode(served.first)).length + 20;
    for (final other in tools) {
      if (other.group != tool.group || ports.contains(other.port)) continue;
      final entry = {'id': other.id, 'port': other.port, 'path': other.path};
      final length = utf8.encode(jsonEncode(entry)).length + 1;
      if (size + length > kToolMaxChunkBytes) break;
      size += length;
      ports.add(other.port);
      served.add(entry);
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'tools': served})),
    );
  }

  @override
  String toString() => 'ToolCatalog(…)';
}
````

- [ ] **Step 5: Write the destination and the header rewriting**

`packages/shellx_agent/lib/src/tool/tool_forwarding.dart`:

````dart
import 'dart:io';

import 'package:shellx_core/shellx_core.dart';

import 'tool_catalog.dart';

/// V2-4 E10: connecting to a tool's port gives up after this (`refused`).
const Duration kToolConnectTimeout = Duration(seconds: 5);

/// V2-4 E10: a response head that takes longer ends the stream (`timeout`).
/// Once the body streams there is no limit (SSE, long polling).
const Duration kToolHeadTimeout = Duration(seconds: 60);

/// V2-4 E10: a stream with bytes in flight and no acknowledgement for this
/// long is dropped.
const Duration kToolIdleTimeout = Duration(minutes: 5);

/// V2-4 E9: a socket to [port] on this computer: 127.0.0.1, then ::1. A name
/// is never resolved, so nothing but this computer's loopback is reached.
Future<Socket> connectToolPort(
  int port, {
  Duration timeout = kToolConnectTimeout,
}) async {
  try {
    return await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: timeout,
    );
  } on SocketException {
    return Socket.connect(InternetAddress.loopbackIPv6, port, timeout: timeout);
  }
}

/// How the proxy reaches a tool's port ([connectToolPort] by default).
typedef ToolConnect = Future<Socket> Function(int port);

/// V2-4 E9: an [HttpClient] that only reaches what [connect] opens (this
/// computer's loopback, on the port of the URL it is given); it never uses a
/// proxy (`http_proxy` and the like are ignored), never unpacks a body and
/// sends no `User-Agent` of its own. Redirects are turned off per request.
HttpClient toolHttpClient(ToolConnect connect) => HttpClient()
  ..findProxy = ((_) => 'DIRECT')
  ..autoUncompress = false
  ..userAgent = null
  ..connectionFactory = (uri, proxyHost, proxyPort) async =>
      ConnectionTask.fromSocket(connect(uri.port), () {});

/// The URL a request for [tool] goes to: the loopback address and the
/// tool's port, with [target]'s path and query (built, never concatenated:
/// V2-4 E9).
Uri toolUri(ServedTool tool, String target) {
  final q = target.indexOf('?');
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: tool.port,
    path: q < 0 ? target : target.substring(0, q),
    query: q < 0 ? null : target.substring(q + 1),
  );
}

/// V2-4 E9, E2, E3: what the tool gets of a phone's request head.
final class ToolForwardedHead {
  const ToolForwardedHead({
    required this.host,
    required this.headers,
    this.contentLength,
  });

  /// `Host`: the phone's when it names the tool's own port on a loopback
  /// spelling (E2), else the tool's.
  final String host;
  final List<(String, String)> headers;

  /// The body's length when the phone said it.
  final int? contentLength;

  /// Writes it on [request]: no `Accept-Encoding` but the phone's.
  void applyTo(HttpClientRequest request) {
    request.headers
      ..removeAll(HttpHeaders.acceptEncodingHeader)
      ..set(HttpHeaders.hostHeader, host);
    for (final (name, value) in headers) {
      request.headers.add(name, value);
    }
    final length = contentLength;
    if (length != null) request.contentLength = length;
  }

  @override
  String toString() => 'ToolForwardedHead(…)';
}

/// V2-4 E9, E2, E3: a phone's request head as the tool gets it. Hop-by-hop
/// headers, `Forwarded`, `X-Forwarded-*`, `Via` and every `__shellx_` cookie
/// are dropped, cookies go in one `Cookie` (`; `), and in alias mode
/// ([alias]: the port the phone serves the tool on) `Origin` and `Referer`
/// of the phone's origin become the tool's. For a WebSocket ([ws]) the
/// phone's handshake headers are dropped too: the desktop makes its own.
/// A value `dart:io` cannot write is left out.
ToolForwardedHead forwardRequestHead(
  List<String> head,
  ServedTool tool, {
  int? alias,
  bool ws = false,
}) {
  final dropped = toolDroppedNames(head);
  if (ws) {
    dropped.addAll(const [
      'sec-websocket-key',
      'sec-websocket-version',
      'sec-websocket-extensions',
    ]);
  }
  final headers = <(String, String)>[];
  final cookies = <String>[];
  String? host;
  int? contentLength;
  for (var i = 0; i + 1 < head.length; i += 2) {
    final name = head[i].toLowerCase();
    var value = head[i + 1];
    if (dropped.contains(name)) continue;
    switch (name) {
      case 'host':
        host ??= value;
        continue;
      case 'content-length':
        final length = int.tryParse(value);
        if (length != null && length >= 0) contentLength = length;
        continue;
      case 'cookie':
        final kept = stripToolGateCookies(value);
        if (kept != null) cookies.add(kept);
        continue;
      case 'origin' when alias != null:
        if (toolLoopbackPrefix(value, alias) == value) value = tool.origin;
      case 'referer' when alias != null:
        final prefix = toolLoopbackPrefix(value, alias);
        if (prefix != null) {
          value = tool.origin + value.substring(prefix.length);
        }
    }
    if (isWritableHeaderValue(value)) headers.add((name, value));
  }
  if (cookies.isNotEmpty) {
    final cookie = cookies.join('; ');
    if (isWritableHeaderValue(cookie)) headers.add(('cookie', cookie));
  }
  final keep =
      alias == null && host != null && isToolLoopbackAuthority(host, tool.port);
  return ToolForwardedHead(
    host: keep ? host : tool.hostHeader,
    headers: headers,
    contentLength: contentLength,
  );
}

/// `[name, value, …]` of [headers] (lower-case names, one pair per value).
List<String> flatHeaders(HttpHeaders headers) {
  final out = <String>[];
  headers.forEach((name, values) {
    for (final value in values) {
      out
        ..add(name)
        ..add(value);
    }
  });
  return out;
}

/// V2-4 E9, E3, E11: the tool's response head as the phone gets it (from
/// [flatHeaders]). Hop-by-hop headers and a `Set-Cookie` of a `__shellx_`
/// cookie are dropped; in alias mode a `Location` and an
/// `Access-Control-Allow-Origin` that name the tool's origin name the
/// phone's (`http://localhost:<alias>`). Null when what is left is over
/// [kToolMaxHeaders] or [kToolMaxHeadBytes] (the phone answers 502).
List<String>? forwardResponseHead(
  List<String> raw,
  ServedTool tool, {
  int? alias,
}) {
  final dropped = toolDroppedNames(raw);
  final out = <String>[];
  for (var i = 0; i + 1 < raw.length; i += 2) {
    final name = raw[i].toLowerCase();
    var value = raw[i + 1];
    if (dropped.contains(name)) continue;
    if (name == 'set-cookie' && setsToolGateCookie(value)) continue;
    if (alias != null) {
      final prefix = toolLoopbackPrefix(value, tool.port);
      if (name == 'location' && prefix != null) {
        value = 'http://localhost:$alias${value.substring(prefix.length)}';
      } else if (name == 'access-control-allow-origin' && prefix == value) {
        value = 'http://localhost:$alias';
      }
    }
    if (!isWritableHeaderValue(value)) continue;
    out
      ..add(name)
      ..add(value);
  }
  if (out.length > kToolMaxHeaders * 2 ||
      toolHeadBytes(out) > kToolMaxHeadBytes) {
    return null;
  }
  return out;
}
````

- [ ] **Step 6: Write the proxy (HTTP)**

`packages/shellx_agent/lib/src/tool/tool_proxy.dart` (Task 6 adds WebSockets: the line `if (request.ws) return refuse(ToolCode.badRequest); // Task 6` is where they go):

````dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';
import 'tool_catalog.dart';
import 'tool_endpoint.dart';
import 'tool_forwarding.dart';

/// V2-4 E10: stream opens (`tool.open`, `tool.req`) a phone may make at once,
/// then [kToolOpensPerSecond] a second; more are answered `busy`.
const int kToolOpenBurst = 120;
const int kToolOpensPerSecond = 60;

/// V2-4 E5, E9: the desktop's side of the `tool.*` tunnel, in the process
/// that holds the relay. It lists the tools the window lets phones open
/// ([serve]), checks each open against that list, and carries HTTP requests
/// and WebSockets to the tool's port on this computer only
/// ([toolHttpClient]). Bodies and messages flow within windows (E7), paced
/// for the whole computer by [pacer]; a full window stops reading the tool
/// (never drops a byte).
///
/// [handle] returns at once: every network step runs in the background.
/// Nothing it carries is ever logged.
final class ToolProxy implements ToolEndpoint {
  ToolProxy({
    ToolPacer? pacer,
    ToolConnect? connect,
    this.headTimeout = kToolHeadTimeout,
    this.idleTimeout = kToolIdleTimeout,
    this.maxRequestBody = kToolMaxRequestBodyBytes,
    this.maxWsMessage = kToolMaxWsMessageBytes,
  }) : pacer = pacer ?? ToolTokenPacer(),
       _connect = connect ?? connectToolPort {
    _client = toolHttpClient(_connect);
  }

  final ToolPacer pacer;
  final Duration headTimeout;
  final Duration idleTimeout;

  /// E10: a larger request body ends `too_large`.
  final int maxRequestBody;

  /// E10: a larger WebSocket message, either way, closes with 1009.
  final int maxWsMessage;

  /// Opens a socket to a tool's port (E9: loopback only, never a name).
  final ToolConnect _connect;
  late final HttpClient _client;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final _phones = <String, _Phone>{};
  ToolCatalog? _catalog;
  bool _closed = false;
  Timer? _idleCheck;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  bool get serving => !_closed;

  /// The tools phones may open now; null before the window said.
  ToolCatalog? get catalog => _catalog;

  /// V2-4 E5, E9: the tools phones may open from now on. A stream of a tool
  /// that left the list ends `disabled` (its flag is off) or `gone`; one
  /// whose URL changed ends `gone`. Phones that list hear the new list.
  void serve(ToolCatalog? catalog) {
    if (_closed) return;
    _catalog = catalog;
    for (final phone in [..._phones.values]) {
      for (final stream in [...phone.streams.values]) {
        final tool = catalog?.byId(stream.tool.id);
        if (catalog == null) {
          stream.abort(ToolCode.unavailable);
        } else if (tool == null) {
          stream.abort(catalog.endCodeFor(stream.tool.id));
        } else if (tool.url != stream.tool.url) {
          stream.abort(ToolCode.gone);
        }
      }
      if (phone.listing) _sendListing(phone);
    }
  }

  /// The window quits (in-process, E5): every stream ends `desktop_closed`,
  /// phones that list hear `available: false`; from now on this proxy does
  /// not serve.
  void close() {
    if (_closed) return;
    for (final phone in [..._phones.values]) {
      for (final stream in [...phone.streams.values]) {
        stream.abort(ToolCode.desktopClosed);
      }
      if (phone.listing) {
        _emit(
          phone,
          ToolListResult(available: false, body: emptyToolListingBody),
        );
      }
      phone.dispose();
    }
    _phones.clear();
    _closed = true;
    _idleCheck?.cancel();
    _client.close(force: true);
  }

  @override
  void handle(String mobileId, ToolMessage message) {
    if (_closed) {
      final reply = toolUnavailableReply(message);
      if (reply != null) _out.add(OutboundMessage(mobileId, reply));
      return;
    }
    final phone = _phones[mobileId] ??= _Phone(mobileId, this);
    switch (message) {
      case ToolList():
        phone.listing = true;
        phone.listed = null; // the phone asked: answer even when unchanged
        _sendListing(phone);
      case ToolOpen(:final rid, :final tool):
        unawaited(_open(phone, rid, tool));
      case ToolClose(:final tool):
        for (final stream in [...phone.streams.values]) {
          if (stream.tool.id == tool) stream.abort(null);
        }
      case ToolRequest():
        _request(phone, message);
      case ToolData(:final id):
        phone.streams[id]?.onData(message);
      case ToolWsMessage(:final id):
        phone.streams[id]?.onWsMessage(message);
      case ToolAck(:final acks):
        for (var i = 0; i + 1 < acks.length; i += 2) {
          phone.streams[acks[i]]?.onAck(acks[i + 1]);
        }
      case ToolEnd(:final id):
        phone.streams[id]?.onPhoneEnd(message);
      case ToolListResult() || ToolOpened() || ToolResponse():
        break; // the desktop's own kinds never come from a phone
    }
  }

  @override
  void phoneGone(String mobileId) => _phones.remove(mobileId)?.dispose();

  @override
  void allPhonesGone() {
    for (final phone in _phones.values) {
      phone.dispose();
    }
    _phones.clear();
  }

  void _sendListing(_Phone phone) {
    final catalog = _catalog;
    final body = catalog?.listingBody() ?? emptyToolListingBody;
    final listed = phone.listed;
    if (listed != null && _same(listed, body)) return;
    phone.listed = body;
    _emit(phone, ToolListResult(available: catalog != null, body: body));
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _open(_Phone phone, int rid, String id) async {
    ToolOpened answer(String code) =>
        ToolOpened(rid: rid, ok: false, code: code);
    if (!phone.budget.take()) return _emit(phone, answer(ToolCode.busy));
    final catalog = _catalog;
    if (catalog == null) return _emit(phone, answer(ToolCode.unavailable));
    final tool = catalog.byId(id);
    if (tool == null) return _emit(phone, answer(catalog.endCodeFor(id)));
    try {
      final socket = await _connect(tool.port);
      socket.destroy();
    } on Object {
      if (phone.live) _emit(phone, answer(ToolCode.refused));
      return;
    }
    // The list may have changed meanwhile: answer from the one of now.
    final now = _catalog?.byId(id);
    if (!phone.live) return;
    if (now == null || now.url != tool.url) {
      return _emit(phone, answer(_catalog?.endCodeFor(id) ?? ToolCode.gone));
    }
    _emit(
      phone,
      ToolOpened(rid: rid, ok: true, body: _catalog!.openedBody(now)),
    );
  }

  void _request(_Phone phone, ToolRequest request) {
    final id = request.id;
    void refuse(String code) => _emit(phone, ToolEnd(id: id, code: code));
    if (phone.streams.containsKey(id)) return; // a number in use: ignored
    if (!phone.budget.take()) return refuse(ToolCode.busy);
    final catalog = _catalog;
    if (catalog == null) return refuse(ToolCode.unavailable);
    // E9: the flag is checked at every stream, never from an older list.
    final tool = catalog.byId(request.tool);
    if (tool == null) return refuse(catalog.endCodeFor(request.tool));
    final alias = request.alias;
    if (!isToolMethod(request.method) ||
        !isToolTarget(request.target) ||
        !isToolHead(request.head) ||
        (alias != null && (alias < 1 || alias > 65535)) ||
        (request.ws && request.method.toUpperCase() != 'GET')) {
      return refuse(ToolCode.badRequest);
    }
    if (request.ws) return refuse(ToolCode.badRequest); // Task 6
    if (phone.streams.length >= kToolMaxHttpStreams) {
      return refuse(ToolCode.busy);
    }
    final stream = _HttpStream(this, phone, tool, request);
    phone.streams[id] = stream;
    _idleCheck ??= Timer.periodic(
      Duration(microseconds: max(1, idleTimeout.inMicroseconds ~/ 4)),
      (_) => _checkIdle(),
    );
    stream.start();
  }

  /// E10: a stream with bytes in flight and no acknowledgement for
  /// [idleTimeout] is dropped.
  void _checkIdle() {
    var any = false;
    for (final phone in [..._phones.values]) {
      for (final stream in [...phone.streams.values]) {
        any = true;
        if (stream.stalledFor >= idleTimeout) stream.abort(ToolCode.aborted);
      }
    }
    if (!any) {
      _idleCheck?.cancel();
      _idleCheck = null;
    }
  }

  /// Every message to a phone goes through here: one over a sealed batch
  /// would make `SecureChannel.seal` throw and drop the channel (terminals and
  /// AI too), so it is never sent (RF 1).
  void _emit(_Phone phone, ToolMessage message) {
    if (!phone.live) return;
    if (encodeBatch([message]).length > kMaxSealedBatchBytes) return;
    _out.add(OutboundMessage(phone.id, message));
  }
}

/// One phone's tools: what it was told, its streams, its windows.
final class _Phone {
  _Phone(this.id, this.proxy) {
    acks = ToolAckBook((ack) => proxy._emit(this, ack));
  }

  final String id;
  final ToolProxy proxy;
  bool listing = false;
  Uint8List? listed;
  bool live = true;

  /// Desktop → phone bytes in flight over all its streams (E7).
  final credit = ToolCredit();

  /// What the desktop took of the phone's bodies and messages.
  late final ToolAckBook acks;
  final budget = _Bucket(kToolOpenBurst, kToolOpensPerSecond);
  final streams = <int, _Stream>{};

  /// Gone (channel lost, revoked, relay stopped): its streams end without a
  /// word to it.
  void dispose() {
    for (final stream in [...streams.values]) {
      stream.abort(null);
    }
    live = false;
    acks.clear();
  }
}

/// E10: [burst] at once, then [perSecond].
final class _Bucket {
  _Bucket(this.burst, this.perSecond) : _tokens = burst.toDouble();
  final int burst;
  final int perSecond;
  double _tokens;
  final _watch = Stopwatch()..start();
  int _last = 0;

  bool take() {
    final now = _watch.elapsedMicroseconds;
    _tokens = min(burst.toDouble(), _tokens + (now - _last) * perSecond / 1e6);
    _last = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}

/// A response nobody takes: its connection is closed.
void _drop(HttpClientResponse response) => unawaited(
  response.detachSocket().then((s) => s.destroy(), onError: (Object _) {}),
);

/// One phone stream to a tool.
sealed class _Stream {
  _Stream(this.proxy, this.phone, this.tool, this.request)
    : window = ToolSendWindow(phone.credit);

  final ToolProxy proxy;
  final _Phone phone;
  final ServedTool tool;
  final ToolRequest request;
  final ToolSendWindow window;
  bool ended = false;
  final _sinceAck = Stopwatch()..start();
  int get id => request.id;

  /// How long bytes have waited in flight without an acknowledgement.
  Duration get stalledFor =>
      window.inFlight == 0 ? Duration.zero : _sinceAck.elapsed;

  void start();
  void onData(ToolData message);
  void onWsMessage(ToolWsMessage message);
  void onPhoneEnd(ToolEnd message);

  void onAck(int total) {
    if (ended) return;
    _sinceAck.reset();
    if (!acked(total)) abort(ToolCode.badRequest);
  }

  /// Passes the acknowledgement on; false when it is beyond what was sent.
  bool acked(int total);

  void send(ToolMessage message) {
    if (window.inFlight == 0) _sinceAck.reset();
    proxy._emit(phone, message);
  }

  /// Ends the stream: the phone hears [code] (nothing when null), the tool's
  /// connection is dropped.
  void abort(String? code) {
    if (ended) return;
    _finish();
    release();
    if (code != null) proxy._emit(phone, ToolEnd(id: id, code: code));
  }

  /// Drops what is held toward the tool.
  void release();

  /// The stream is over (both ways): forget it.
  void _finish() {
    ended = true;
    window.close();
    phone.acks.forget(id);
    if (identical(phone.streams[id], this)) phone.streams.remove(id);
  }
}

/// An HTTP request: its body to the tool, the response to the phone.
final class _HttpStream extends _Stream {
  _HttpStream(super.proxy, super.phone, super.tool, super.request);

  HttpClientRequest? _upstream;
  ToolBytesIn? _body;
  ToolBytesOut? _response;

  @override
  void start() {
    if (!request.end) {
      _body = ToolBytesIn(
        onConsumed: (total) => phone.acks.consumed(id, total),
        maxBytes: proxy.maxRequestBody,
      );
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    final HttpClientRequest upstream;
    try {
      upstream = await proxy._client.openUrl(
        request.method,
        toolUri(tool, request.target),
      );
    } on Object {
      abort(ToolCode.refused); // nothing listens, or not within 5 s (E10)
      return;
    }
    if (ended) {
      upstream.abort();
      return;
    }
    final HttpClientResponse response;
    try {
      _upstream = upstream;
      // E9: a 3xx goes to the phone as is; an upload goes as it comes.
      upstream
        ..followRedirects = false
        ..bufferOutput = false;
      final head = forwardRequestHead(request.head, tool, alias: request.alias);
      head.applyTo(upstream);
      final body = _body;
      if (body != null) {
        if (head.contentLength == null) {
          upstream.headers.chunkedTransferEncoding = true;
        }
        await upstream.addStream(body.stream);
      }
      response = await upstream.close().timeout(proxy.headTimeout);
    } on TimeoutException {
      abort(ToolCode.timeout);
      return;
    } on Object {
      abort(ToolCode.aborted);
      return;
    }
    if (ended) {
      _drop(response);
      return;
    }
    final head = forwardResponseHead(
      flatHeaders(response.headers),
      tool,
      alias: request.alias,
    );
    if (head == null) {
      _drop(response);
      abort(ToolCode.tooLarge);
      return;
    }
    final status = response.statusCode;
    final bodyless =
        request.method.toUpperCase() == 'HEAD' ||
        status == 204 ||
        status == 304 ||
        (status >= 100 && status < 200);
    send(ToolResponse(id: id, status: status, head: head, end: bodyless));
    if (bodyless) {
      _drop(response);
      _finish();
      return;
    }
    _response = ToolBytesOut(
      id: id,
      source: response,
      window: window,
      pacer: proxy.pacer,
      send: send,
      onError: (_) => abort(ToolCode.aborted),
      onDone: _finish,
    )..start();
  }

  @override
  void onData(ToolData message) {
    final body = _body;
    if (ended || body == null) return;
    if (!body.add(message.data, end: message.end)) {
      abort(
        body.received > proxy.maxRequestBody
            ? ToolCode.tooLarge
            : ToolCode.badRequest,
      );
    }
  }

  @override
  void onWsMessage(ToolWsMessage message) => abort(ToolCode.badRequest);

  @override
  void onPhoneEnd(ToolEnd message) => abort(null);

  @override
  bool acked(int total) => _response?.onAck(total) ?? total == 0;

  @override
  void release() {
    _response?.cancel();
    _body?.fail(const SocketException('ended'));
    _upstream?.abort();
  }
}
````

In `packages/shellx_agent/lib/shellx_agent.dart`, after `export 'src/tool/tool_endpoint.dart';` (Task 4) the block of tool exports reads:

````dart
export 'src/tool/tool_catalog.dart';
export 'src/tool/tool_endpoint.dart';
export 'src/tool/tool_forwarding.dart';
export 'src/tool/tool_proxy.dart';
````

- [ ] **Step 7: Run the tests to verify they pass**

````bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format lib/src/tool/tool_catalog.dart lib/src/tool/tool_forwarding.dart lib/src/tool/tool_proxy.dart lib/shellx_agent.dart test/support/tool_rig.dart test/tool/tool_proxy_http_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (920 → 944). The 50 MB test takes about 7 s: it is paced at 8 MiB/s, as in production.

- [ ] **Step 8: Commit**

````bash
git add packages/shellx_agent/lib/src/tool/tool_catalog.dart packages/shellx_agent/lib/src/tool/tool_forwarding.dart packages/shellx_agent/lib/src/tool/tool_proxy.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/support/tool_rig.dart packages/shellx_agent/test/tool/tool_proxy_http_test.dart
git commit -m "feat(v2-tools): the desktop tool proxy — the window's list, opening, HTTP to the tool's loopback port only, windows and pacing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 6: WebSockets through the desktop proxy

The desktop makes its own upgrade to the tool (R7):
- a pinned `HttpClient` `GET` with `Connection: Upgrade`, `Upgrade: websocket`, its own `Sec-WebSocket-Key` and version 13; the phone's `Sec-WebSocket-Key`, `-Version` and `-Extensions` are dropped, so permessage-deflate is never negotiated;
- on `101`, `detachSocket` and `WebSocket.fromUpgradedSocket`; a subprotocol the webview did not offer is an error;
- any other status reaches the phone as plain HTTP (the tool's refusal, with its body), so the webview sees the tool's answer.

Messages flow both ways:
- `ToolWsOut` (Task 3): tool → phone, within the windows, paced, pausing the tool's socket when full;
- `ToolWsIn`: phone → tool, acknowledged once written;
- a message over 16 MiB either way closes both sides with 1009 (R12).

Close codes cross both ways:
- the webview's close reaches the tool once everything the phone sent was written (its reason cut to 123 bytes), and the tool's close reaches the phone;
- an abort (the flag turned off, the phone gone) destroys the socket;
- E10: at most 16 WebSockets per phone.

**Files:**
- Modify: `packages/shellx_agent/lib/src/tool/tool_proxy.dart`
- Test: `packages/shellx_agent/test/tool/tool_proxy_ws_test.dart`

**Interfaces:**
- Consumes: Task 2 `toolHeadValues`, `kToolMaxWsStreams`; Task 3 `ToolWsOut` (with `discard()`), `ToolWsIn` (with `idle`); Task 5 `ToolProxy` and its private `_Stream`/`_HttpStream`.
- Produces: no new public API. A `tool.req` with `ws: true` now opens a WebSocket stream (before: `bad_request`).

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/tool/tool_proxy_ws_test.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/tool_rig.dart';

const _id = 'k3f9za7q1m';

/// V2-4 §5, E7, E10: WebSockets through the desktop proxy, against a real
/// tool on loopback.
void main() {
  late TestTool tool;
  late ToolProxy proxy;
  late ToolPhone phone;

  Future<void> setUpWith({
    Map<String, Future<void> Function(HttpRequest)> routes = const {},
    ToolProxy? withProxy,
  }) async {
    tool = await TestTool.start(routes: routes);
    proxy = withProxy ?? ToolProxy();
    proxy.serve(catalogOf([tool.entry()]));
    phone = ToolPhone(proxy);
  }

  tearDown(() async {
    proxy.close();
    await tool.close();
  });

  /// Opens `/ws` offering `vite-hmr`; its stream id once it is open.
  Future<int> open() async {
    final id = phone.request(
      _id,
      target: '/ws?token=abc',
      ws: true,
      head: [
        'host',
        'localhost:${tool.port}',
        'upgrade',
        'websocket',
        'connection',
        'Upgrade',
        'sec-websocket-key',
        'dGhlIHNhbXBsZSBub25jZQ==',
        'sec-websocket-version',
        '13',
        'sec-websocket-protocol',
        'vite-hmr',
        'origin',
        'http://localhost:${tool.port}',
      ],
    );
    final response = await phone.response(id);
    expect(response.status, 101);
    expect(toolHeadValues(response.head, 'sec-websocket-protocol'), [
      'vite-hmr',
    ]);
    return id;
  }

  void say(int id, Object message) {
    final bytes = message is String
        ? utf8.encode(message)
        : message as Uint8List;
    phone.send(
      ToolWsMessage(id: id, data: bytes, text: message is String, fin: true),
    );
  }

  test('the tool sees the request as from the page; messages go both ways, '
      'text stays text', () async {
    await setUpWith();
    final id = await open();
    final hit = tool.hits.single;
    expect(hit.uri.query, 'token=abc');
    expect(hit.headers['origin'], ['http://localhost:${tool.port}']);
    expect(hit.headers['host'], ['localhost:${tool.port}']);
    expect(
      hit.headers['sec-websocket-key'],
      isNot(['dGhlIHNhbXBsZSBub25jZQ==']),
      reason: 'the desktop makes its own handshake',
    );
    say(id, 'hello');
    say(id, Uint8List.fromList([1, 2, 3]));
    await until(() => phone.wsPieces(id).length == 2);
    final pieces = phone.wsPieces(id);
    expect(pieces[0].text, isTrue);
    expect(utf8.decode(pieces[0].data), 'hello');
    expect(pieces[1].text, isFalse);
    expect(pieces[1].data, [1, 2, 3]);
  });

  test(
    'a 1 MiB message goes in pieces of ≤ 48 KiB and comes back whole',
    () async {
      await setUpWith();
      final id = await open();
      final big = Uint8List.fromList([
        for (var i = 0; i < 1024 * 1024; i++) i & 0xFF,
      ]);
      // The phone sends it in pieces, within the window the desktop opens.
      var at = 0;
      while (at < big.length) {
        final end = at + kToolMaxChunkBytes > big.length
            ? big.length
            : at + kToolMaxChunkBytes;
        phone.send(
          ToolWsMessage(
            id: id,
            data: Uint8List.sublistView(big, at, end),
            text: false,
            fin: end == big.length,
          ),
        );
        at = end;
        await pumpEventQueue();
      }
      await until(() => phone.wsPieces(id).any((p) => p.fin));
      final pieces = phone.wsPieces(id);
      expect(pieces.every((p) => p.data.length <= kToolMaxChunkBytes), isTrue);
      expect([for (final p in pieces) ...p.data], big);
    },
  );

  test('close codes cross both ways', () async {
    await setUpWith();
    final a = await open();
    say(a, 'close:4001');
    await phone.ended(a);
    expect(phone.endOf(a)?.wsCode, 4001);
    expect(phone.endOf(a)?.wsReason, 'by tool');
    expect(phone.endOf(a)?.code, isNull);

    final b = await open();
    phone.send(ToolEnd(id: b, wsCode: 4002, wsReason: 'bye'));
    await until(() => tool.wsClosed.length == 2);
    expect(tool.wsClosed.last, (4002, 'bye'));
  });

  test(
    'a tool that does not upgrade: its answer goes to the phone as HTTP',
    () async {
      await setUpWith(
        routes: {
          '/ws': (request) async {
            request.response
              ..statusCode = 403
              ..write('Invalid token');
            await request.response.close();
          },
        },
      );
      final id = phone.request(
        _id,
        target: '/ws',
        ws: true,
        head: ['upgrade', 'websocket'],
      );
      final response = await phone.response(id);
      await phone.ended(id);
      expect(response.status, 403);
      expect(utf8.decode(phone.body(id)), 'Invalid token');
    },
  );

  test('a message over the limit closes with 1009, either way (E10)', () async {
    await setUpWith(withProxy: ToolProxy(maxWsMessage: 1000));
    final a = await open();
    say(a, Uint8List(1001));
    await phone.ended(a);
    expect(phone.endOf(a)?.wsCode, 1009);
    await until(() => tool.wsClosed.isNotEmpty);
    expect(tool.wsClosed.single.$1, 1009);

    final b = await open();
    // The tool echoes 900 bytes, then a message over the limit.
    say(b, Uint8List(900));
    await until(() => phone.wsPieces(b).isNotEmpty);
    phone.send(
      ToolWsMessage(id: b, data: Uint8List(600), text: false, fin: false),
    );
    phone.send(
      ToolWsMessage(id: b, data: Uint8List(600), text: false, fin: true),
    );
    await phone.ended(b);
    expect(phone.endOf(b)?.wsCode, 1009);
  });

  test('more than 16 WebSockets: busy', () async {
    await setUpWith();
    for (var i = 0; i < 16; i++) {
      await open();
    }
    final id = phone.request(_id, target: '/ws', ws: true);
    await pumpEventQueue();
    expect(phone.endOf(id)?.code, 'busy');
  });

  test('turning the flag off drops the WebSocket on both sides (E9)', () async {
    await setUpWith();
    final id = await open();
    proxy.serve(catalogOf([], off: [_id]));
    await phone.ended(id);
    expect(phone.endOf(id)?.code, 'disabled');
    await until(() => tool.wsClosed.isNotEmpty);
  });

  test('a WebSocket upgrade must be a GET', () async {
    await setUpWith();
    final id = phone.request(_id, method: 'POST', target: '/ws', ws: true);
    await pumpEventQueue();
    expect(phone.endOf(id)?.code, 'bad_request');
    expect(tool.hits, isEmpty);
  });
}
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/tool/tool_proxy_ws_test.dart`
Expected: FAIL — every WebSocket request ends `bad_request` (`phone.response(id)` fails with "ended before a response"), except "a WebSocket upgrade must be a GET".

- [ ] **Step 3: Carry WebSockets**

In `packages/shellx_agent/lib/src/tool/tool_proxy.dart`:

1. Add `import 'dart:convert';` after `import 'dart:async';`.
2. In `_request`, replace:

````dart
    if (request.ws) return refuse(ToolCode.badRequest); // Task 6
    if (phone.streams.length >= kToolMaxHttpStreams) {
      return refuse(ToolCode.busy);
    }
    final stream = _HttpStream(this, phone, tool, request);
````

with:

````dart
    final ws = phone.streams.values.whereType<_WsStream>().length;
    final http = phone.streams.length - ws;
    if (request.ws ? ws >= kToolMaxWsStreams : http >= kToolMaxHttpStreams) {
      return refuse(ToolCode.busy);
    }
    final stream = request.ws
        ? _WsStream(this, phone, tool, request)
        : _HttpStream(this, phone, tool, request);
````

3. At the end of the file, after `_HttpStream`, add:

````dart
/// A WebSocket: the desktop makes its own upgrade to the tool (pinned like
/// any request), then carries messages both ways.
final class _WsStream extends _Stream {
  _WsStream(super.proxy, super.phone, super.tool, super.request);

  Socket? _socket;
  WebSocket? _ws;
  ToolWsOut? _out;
  ToolWsIn? _in;
  ToolBytesOut? _refusal;

  @override
  void start() => unawaited(_run());

  Future<void> _run() async {
    final key = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final protocols = [
      for (final value in toolHeadValues(
        request.head,
        'sec-websocket-protocol',
      ))
        for (final p in value.split(','))
          if (p.trim().isNotEmpty) p.trim(),
    ];
    final HttpClientRequest upstream;
    try {
      upstream = await proxy._client.openUrl(
        'GET',
        toolUri(tool, request.target),
      );
    } on Object {
      abort(ToolCode.refused);
      return;
    }
    if (ended) {
      upstream.abort();
      return;
    }
    final HttpClientResponse response;
    try {
      upstream.followRedirects = false;
      forwardRequestHead(
        request.head,
        tool,
        alias: request.alias,
        ws: true,
      ).applyTo(upstream);
      upstream.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('sec-websocket-key', key)
        ..set('sec-websocket-version', '13');
      response = await upstream.close().timeout(proxy.headTimeout);
    } on TimeoutException {
      abort(ToolCode.timeout);
      return;
    } on Object {
      abort(ToolCode.aborted);
      return;
    }
    if (ended) {
      _drop(response);
      return;
    }
    if (response.statusCode != HttpStatus.switchingProtocols) {
      return _refused(response);
    }
    final protocol = response.headers.value('sec-websocket-protocol');
    if (protocol != null && !protocols.contains(protocol)) {
      _drop(response);
      abort(ToolCode.aborted); // a protocol the webview did not offer
      return;
    }
    final Socket socket;
    try {
      socket = await response.detachSocket();
    } on Object {
      abort(ToolCode.aborted);
      return;
    }
    if (ended) {
      socket.destroy();
      return;
    }
    _socket = socket;
    final ws = _ws = WebSocket.fromUpgradedSocket(
      socket,
      protocol: protocol,
      serverSide: false,
    );
    send(
      ToolResponse(
        id: id,
        status: HttpStatus.switchingProtocols,
        head: [
          if (protocol != null) ...['sec-websocket-protocol', protocol],
        ],
        end: false,
      ),
    );
    _in = ToolWsIn(
      write: (message) => ws.addStream(Stream.value(message)),
      onConsumed: (total) => phone.acks.consumed(id, total),
      maxMessage: proxy.maxWsMessage,
    );
    _out = ToolWsOut(
      id: id,
      source: ws,
      window: window,
      pacer: proxy.pacer,
      send: send,
      maxMessage: proxy.maxWsMessage,
      onTooBig: () => _closeBoth(WebSocketStatus.messageTooBig, null),
      onDone: () => _closed(ws.closeCode, ws.closeReason),
    )..start();
  }

  /// The tool did not upgrade: the phone gets its answer as plain HTTP.
  void _refused(HttpClientResponse response) {
    final head = forwardResponseHead(
      flatHeaders(response.headers),
      tool,
      alias: request.alias,
    );
    if (head == null) {
      _drop(response);
      abort(ToolCode.tooLarge);
      return;
    }
    send(
      ToolResponse(id: id, status: response.statusCode, head: head, end: false),
    );
    _refusal = ToolBytesOut(
      id: id,
      source: response,
      window: window,
      pacer: proxy.pacer,
      send: send,
      onError: (_) => abort(ToolCode.aborted),
      onDone: _finish,
    )..start();
  }

  /// The tool closed: the phone hears its code.
  void _closed(int? code, String? reason) {
    if (ended) return;
    _finish();
    release();
    proxy._emit(phone, ToolEnd(id: id, wsCode: code, wsReason: reason));
  }

  /// Ends the stream with a close frame to the tool ([code], once what the
  /// phone sent was written); the phone hears [code] too unless it closed
  /// first ([tellPhone]).
  void _closeBoth(int? code, String? reason, {bool tellPhone = true}) {
    if (ended) return;
    _finish();
    _out?.discard(); // keep reading: the tool's close frame must come in
    _refusal?.cancel();
    _closeTool(code, reason);
    if (tellPhone) {
      proxy._emit(phone, ToolEnd(id: id, wsCode: code, wsReason: reason));
    }
  }

  void _closeTool(int? code, String? reason) {
    final ws = _ws;
    if (ws == null) return;
    final valid = code != null && _sendable(code);
    unawaited(
      (_in?.idle ?? Future<void>.value())
          .timeout(const Duration(seconds: 5))
          .then((_) => valid ? ws.close(code, reason) : ws.close())
          .catchError((Object _) => _socket?.destroy()),
    );
  }

  /// A close code an endpoint may send (RFC 6455 §7.4).
  static bool _sendable(int code) =>
      (code >= 1000 && code <= 1003) ||
      (code >= 1007 && code <= 1011) ||
      (code >= 3000 && code <= 4999);

  @override
  void onData(ToolData message) => abort(ToolCode.badRequest);

  @override
  void onWsMessage(ToolWsMessage message) {
    final input = _in;
    if (ended || input == null) return;
    if (!input.add(message)) _closeBoth(WebSocketStatus.messageTooBig, null);
  }

  @override
  void onPhoneEnd(ToolEnd message) {
    if (ended) return;
    if (message.code != null || _ws == null) {
      abort(null);
      return;
    }
    // The webview closed: the tool hears the same code once everything the
    // phone sent was written.
    _closeBoth(message.wsCode, _truncate(message.wsReason), tellPhone: false);
  }

  static String? _truncate(String? reason) {
    if (reason == null) return null;
    var out = reason;
    while (utf8.encode(out).length > 123) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  @override
  bool acked(int total) =>
      (_out?.onAck(total) ?? _refusal?.onAck(total)) ?? total == 0;

  @override
  void release() {
    _out?.cancel();
    _refusal?.cancel();
    _socket?.destroy();
  }
}
````

- [ ] **Step 4: Run the tests to verify they pass**

````bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format lib/src/tool/tool_proxy.dart test/tool/tool_proxy_ws_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (944 → 952).

- [ ] **Step 5: Commit**

````bash
git add packages/shellx_agent/lib/src/tool/tool_proxy.dart packages/shellx_agent/test/tool/tool_proxy_ws_test.dart
git commit -m "feat(v2-tools): WebSockets through the desktop proxy — its own upgrade, refusals as HTTP, close codes both ways, 1009 over 16 MiB

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 7: `tool.serve` — the window tells the background service which tools phones may open

E5: when the background service holds the relay, the proxy runs there, and the window pushes its list over the mux.
- **Message:** `tool.serve` `{b: <the same JSON bytes ToolCatalog.serveBody makes>}`, window → service, no `q`, never answered.
- **The service:** `MuxServer.tools` (a `ToolProxy?`) serves each list it can read; an unreadable or missing body changes nothing. The last list stays when the window goes: tools stay open like shells, and the service answers phones while the window is closed.
- **Old peers:** an older service ignores the message (the unknown-type path of its `switch` answers only messages with a `q`); an older window never sends it.
- **Ordering:** the message is handled before the link counts as primed, like `ai.*` (a list is not a request the window waits on).

**Files:**
- Modify: `packages/shellx_agent/lib/src/mux/mux_messages.dart`
- Modify: `packages/shellx_agent/lib/src/mux/mux_server.dart`
- Test: `packages/shellx_agent/test/mux/mux_tools_test.dart`

**Interfaces:**
- Consumes: Task 5 `ToolProxy.serve`, `ToolCatalog.fromServeBody`, `ToolCatalog.serveBody`, `kToolServeMaxBytes`.
- Produces:
  - `MuxType.toolServe = 'tool.serve'`;
  - `ToolProxy? MuxServer.tools` (settable, null by default; Task 11 sets it in the background service).

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/mux/mux_tools_test.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/mux_fixtures.dart';
import '../support/session_rig.dart';

const _self = MuxPeerInfo(
  protocol: kMuxProtocol,
  app: '2.0.0',
  instance: 'inst1',
  pid: 42,
  caps: ['agent', 'cli', 'tools'],
);
const _phone = 'b0000000-0000-4000-8000-000000000002';

Future<MuxConnection> _window(TestListener l) async {
  final (client, daemonSide) = MemoryMuxTransport.pair();
  l.push(daemonSide);
  await clientHandshake(client, secret: secret, app: '2.0.0', role: 'ui');
  return client;
}

Uint8List _body(List<String> ids, {List<String> off = const []}) =>
    ToolCatalog.serveBody([
      for (final id in ids)
        {
          'id': id,
          'name': 'Tool $id',
          'ws': 'shop-web',
          'group': 'ws:a',
          'url': 'http://localhost:5173/',
        },
    ], off: off);

/// V2-4 E5: the window tells the background service which tools phones may
/// open; the service's proxy serves them, also after the window quits.
void main() {
  late SessionRig rig;
  late TestListener listener;
  late MuxServer server;
  late ToolProxy proxy;
  late List<ToolMessage> toPhone;

  setUp(() {
    rig = SessionRig();
    listener = TestListener();
    proxy = ToolProxy();
    toPhone = [];
    proxy.outbound.listen((o) => toPhone.add(o.message as ToolMessage));
  });

  tearDown(() async {
    proxy.close();
    await server.close();
  });

  List<String> listed() {
    final result = toPhone.whereType<ToolListResult>().last;
    final json = jsonDecode(utf8.decode(result.body)) as Map<String, Object?>;
    return [for (final t in json['tools']! as List) (t as Map)['id'] as String];
  }

  test('tool.serve reaches the proxy; the list stays when the window goes; '
      'an unreadable list changes nothing', () async {
    server = MuxServer(
      sessions: rig.manager,
      secret: secret,
      self: _self,
      onQuit: () async {},
    )..tools = proxy;
    server.serve(listener);
    proxy.handle(_phone, const ToolList());
    expect(toPhone.whereType<ToolListResult>().single.available, isFalse);

    final window = await _window(listener);
    window.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': _body(['aaaaaaaaa1']),
        },
      ),
    );
    await pumpEventQueue();
    expect(listed(), ['aaaaaaaaa1']);
    expect(toPhone.whereType<ToolListResult>().last.available, isTrue);

    window.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': Uint8List.fromList([1, 2]),
        },
      ),
    );
    window.send(const MuxMessage(MuxType.toolServe));
    await pumpEventQueue();
    expect(listed(), ['aaaaaaaaa1']);

    await window.close();
    await pumpEventQueue();
    expect(proxy.catalog?.tools.single.id, 'aaaaaaaaa1');
    final again = await _window(listener);
    again.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': _body(['bbbbbbbbb2']),
        },
      ),
    );
    await pumpEventQueue();
    expect(listed(), ['bbbbbbbbb2']);
  });

  test(
    'an older service (no proxy) ignores tool.serve and keeps answering',
    () async {
      server = MuxServer(
        sessions: rig.manager,
        secret: secret,
        self: _self,
        onQuit: () async {},
      )..serve(listener);
      final window = await _window(listener);
      window.send(
        MuxMessage(
          MuxType.toolServe,
          fields: {
            'b': _body(['aaaaaaaaa1']),
          },
        ),
      );
      final reply = window.messages.firstWhere((m) => m.q == 1);
      window.send(const MuxMessage(MuxType.sessionsList, q: 1));
      expect((await reply).type, MuxType.result);
    },
  );

  test('a list over one mux frame is cut to fit, in order', () {
    final body = ToolCatalog.serveBody([
      for (var i = 0; i < 100; i++)
        {
          'id': 'tool${i.toString().padLeft(6, '0')}',
          'name': 'x',
          'ws': 'w',
          'group': 'g',
          'url': 'http://localhost:5173/${'p' * 1500}',
        },
    ]);
    expect(body.length, lessThanOrEqualTo(kToolServeMaxBytes));
    final catalog = ToolCatalog.fromServeBody(body)!;
    expect(catalog.tools.first.id, 'tool000000');
    expect(catalog.tools.length, lessThan(100));
  });
}
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/mux/mux_tools_test.dart`
Expected: FAIL to compile — `MuxType.toolServe` and `MuxServer.tools` are not defined.

- [ ] **Step 3: Add the message and serve it**

In `packages/shellx_agent/lib/src/mux/mux_messages.dart`, at the end of `abstract final class MuxType`, after `static const aiServe = 'ai.serve', aiPush = 'ai.push';` add:

````dart

  /// V2-4 E5 (additive): the tools phones may open (`tool.serve`, `{b: JSON
  /// bytes}`, window → service, never answered). The service's proxy serves
  /// them and keeps the last list when the window goes. An older service
  /// ignores it; an older window never sends it.
  static const toolServe = 'tool.serve';
````

In `packages/shellx_agent/lib/src/mux/mux_server.dart`:

1. After `import '../term/term_frames.dart';` add:

````dart
import '../tool/tool_catalog.dart';
import '../tool/tool_proxy.dart';
````

2. After the field `MuxAiForwarder? ai;` add:

````dart

  /// V2-4 E5: the proxy the window's `tool.serve` lists go to; null: they are
  /// ignored (like an older service).
  ToolProxy? tools;
````

3. In `_UiLink._onMessage`, after the block

````dart
    if (m.type == MuxType.aiOut || m.type == MuxType.aiPush) {
      server.ai?.fromUi(this, m);
      return;
    }
````

   add:

````dart
    // V2-4 E5: kept when the window goes (tools stay open like shells).
    if (m.type == MuxType.toolServe) {
      final body = m.get<Uint8List>('b');
      final catalog = body == null ? null : ToolCatalog.fromServeBody(body);
      if (catalog != null) server.tools?.serve(catalog);
      return;
    }
````

- [ ] **Step 4: Run the tests to verify they pass**

````bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format lib/src/mux/mux_messages.dart lib/src/mux/mux_server.dart test/mux/mux_tools_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (952 → 955).

- [ ] **Step 5: Commit**

````bash
git add packages/shellx_agent/lib/src/mux/mux_messages.dart packages/shellx_agent/lib/src/mux/mux_server.dart packages/shellx_agent/test/mux/mux_tools_test.dart
git commit -m "feat(v2-tools): tool.serve — the window's phone list reaches the background service's proxy and stays when the window goes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 8: The phone's `MachineTools`: the list, opening, stream routing, and the tool outbox

The phone side of `tool.*`, on `MachineClient` like `MachineAi` (V2-2).
- **Flag and list:** `supported` comes from `tools` in the answer to `session.list {desktop: true}`. `watch()` asks `tool.list` now and on every new channel; `listing`/`listings` carry the answer and each change. `hold()` is a tool page keeping the channel and the list (R4).
- **Opening and streams:** `open(tool)` sends `tool.open` and waits for `tool.opened` like any request (timeout, `MachineConnectionException`). Stream ids come from `newStreamId()`; `listen(id, listener)` routes `tool.resp`/`tool.data`/`tool.ws.msg`/acks/`tool.end` to a `ToolStreamListener`.
- **Credit and acks:** `credit` is the phone → desktop window over all streams; `acks` (`ToolAckBook`) acknowledges what the page took, every stream in one `tool.ack` per 50 ms.
- **The outbox (E8, R10):** every `tool.*` message the phone sends goes through it.
  - Collected for 16 ms, then split with `splitIntoBatches`.
  - At most 100 frames a second (a token every 10 ms, burst 10, timer-based so `fake_async` drives it); over the budget the rest waits, in order.
  - A message over one sealed batch is refused (false), never queued (RF 1).
- **A lost channel:** opens in flight fail, every stream hears `onLost`, nothing queued goes out, `credit` starts again. A new channel asks for the list again if it is watched or held, and `wantsChannel` makes `MachineClient` reconnect for an open tool page even without a terminal tab.
- **Never logs:** `ToolInfo`, `ToolListing` and `ToolServing` print `Type(…)`.

**Files:**
- Create: `packages/shellx_client/lib/src/machine_tools.dart`
- Modify: `packages/shellx_client/lib/src/machine_client.dart`
- Modify: `packages/shellx_client/lib/shellx_client.dart`
- Modify: `packages/shellx_client/test/support/harness.dart`
- Test: `packages/shellx_client/test/tools_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: the `tool.*` messages, `SessionListResult.tools`, `splitIntoBatches`, `kToolMaxChunkBytes`;
  - Task 2: `isToolTarget`;
  - Task 3: `ToolCredit`, `ToolAckBook`;
  - tests only: Task 4 `ToolEndpoint`, `SessionRouter(tools:)`; Task 5 `ToolProxy`, `ToolCatalog`.
- Produces (exported from `package:shellx_client/shellx_client.dart`):
  - `final class ToolInfo { const ToolInfo({required String id, required String name, required String ws, required int port, required String path, required String group}); }` (value equality);
  - `final class ToolListing { const ToolListing({bool available = true, List<ToolInfo> tools = const []}); final bool available; final List<ToolInfo> tools; static ToolListing fromBody(Uint8List body, {required bool available}); }`;
  - `final class ToolServing { const ToolServing({required String id, required int port, required String path}); static List<ToolServing> fromBody(Uint8List? body); }`;
  - `abstract interface class ToolStreamListener { void onResponse(ToolResponse message); void onData(ToolData message); void onWsMessage(ToolWsMessage message); void onAck(int total); void onEnd(ToolEnd message); void onLost(); }`;
  - `const int kToolPhoneFramesPerSecond = 100; const int kToolPhoneFrameBurst = 10;`;
  - `final class MachineTools`:
    - state: `bool? get supported; ToolListing? get listing; Stream<ToolListing> get listings; Stream<bool> get links; bool get connected; bool get wantsChannel;`
    - list: `Future<void> watch(); void unwatch(); void Function() hold();`
    - streams: `Future<ToolOpened> open(String tool); int newStreamId(); void listen(int id, ToolStreamListener listener); void release(int id);`
    - sending: `bool enqueue(ToolMessage message); ToolCredit credit; late final ToolAckBook acks;`
    - `@internal` for `MachineClient`: `noteListResult`, `handle`, `channelReady`, `channelLost`, `dispose`;
  - `late final MachineTools MachineClient.tools`;
  - test support: `Harness(async, keys, {bool paired = true, AiEndpoint? ai, ToolEndpoint? tools})`.

- [ ] **Step 1: Write the failing tests**

In `packages/shellx_client/test/support/harness.dart`:

1. Replace the constructor's first line `Harness(this.async, this.keys, {bool paired = true, this.ai}) {` with:

````dart
  Harness(this.async, this.keys, {bool paired = true, this.ai, this.tools}) {
````

2. After the field `final AiEndpoint? ai;` add:

````dart

  /// V2-4: the agent's tool endpoint; null: an agent without tools for
  /// phones (every older desktop).
  final ToolEndpoint? tools;
````

3. In the `SessionRouter(...)` it builds, after `ai: ai,` add `tools: tools,`.

`packages/shellx_client/test/tools_test.dart`:

````dart
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

/// Records what phones send; says what a test makes it say.
final class _Spy implements ToolEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final handled = <ToolMessage>[];

  void say(ToolMessage m) => _out.add(OutboundMessage(phoneId, m));

  @override
  Stream<OutboundMessage> get outbound => _out.stream;
  @override
  bool get serving => true;
  @override
  void handle(String mobileId, ToolMessage message) => handled.add(message);
  @override
  void phoneGone(String mobileId) {}
  @override
  void allPhonesGone() {}
}

/// Records what a stream hears.
final class _Listener implements ToolStreamListener {
  final heard = <String>[];
  @override
  void onResponse(ToolResponse message) => heard.add('response');
  @override
  void onData(ToolData message) => heard.add('data');
  @override
  void onWsMessage(ToolWsMessage message) => heard.add('ws');
  @override
  void onAck(int total) => heard.add('ack $total');
  @override
  void onEnd(ToolEnd message) => heard.add('end ${message.code}');
  @override
  void onLost() => heard.add('lost');
}

ToolCatalog _catalog() => ToolCatalog.fromServeBody(
  ToolCatalog.serveBody([
    {
      'id': 'k3f9za7q1m',
      'name': 'Bảng việc',
      'ws': 'shop-web',
      'group': 'ws:a',
      'url': 'http://localhost:5173/app',
    },
  ]),
)!;

int _framesFromPhone(Harness h) =>
    h.relay.delivered.where((d) => d.from == phoneId).length;

/// V2-4 E6, E8, E19: the phone's `MachineTools` over the real encrypted
/// channel and the fake relay.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('the tools flag, the list and its changes, and an open', () {
    fakeAsync((async) {
      final proxy = ToolProxy()..serve(_catalog());
      final h = Harness(async, keys, tools: proxy);
      final tools = h.phoneMachine.tools;
      h.run(h.phoneMachine.listSessions(includeDesktop: true));
      expect(tools.supported, isTrue);
      h.run(tools.watch());
      settle(async);
      final tool = tools.listing!.tools.single;
      expect(tool.name, 'Bảng việc');
      expect(tool.port, 5173);
      expect(tool.path, '/app');
      expect(tool.ws, 'shop-web');
      proxy.serve(ToolCatalog([]));
      settle(async);
      expect(tools.listing!.tools, isEmpty);
      final opened = h.run(tools.open('unknown111'));
      expect(opened.ok, isFalse);
      expect(opened.code, 'gone');
      proxy.close();
    });
  });

  test('tool messages within 16 ms go in one frame; acks of every stream in '
      'one tool.ack per 50 ms (E8)', () {
    fakeAsync((async) {
      final spy = _Spy();
      final h = Harness(async, keys, tools: spy);
      final tools = h.phoneMachine.tools;
      h.run(h.phoneMachine.connect());
      settle(async);
      final before = _framesFromPhone(h);
      tools.enqueue(const ToolEnd(id: 1, code: 'aborted'));
      async.elapse(const Duration(milliseconds: 5));
      tools.enqueue(const ToolEnd(id: 2, code: 'aborted'));
      tools.enqueue(const ToolClose(tool: 'k3f9za7q1m'));
      async.elapse(const Duration(milliseconds: 11));
      settle(async);
      expect(_framesFromPhone(h) - before, 1);
      expect(spy.handled.map((m) => m.type), [
        'tool.end',
        'tool.end',
        'tool.close',
      ]);

      tools.acks.consumed(7, 100);
      tools.acks.consumed(8, 50);
      tools.acks.consumed(7, 300);
      async.elapse(const Duration(milliseconds: 49));
      expect(spy.handled.whereType<ToolAck>(), isEmpty);
      settle(async);
      expect(spy.handled.whereType<ToolAck>().single.acks, [7, 300, 8, 50]);
    });
  });

  test('at most 100 tool frames a second, in order, none lost (E8, RF 2)', () {
    fakeAsync((async) {
      final spy = _Spy();
      final h = Harness(async, keys, tools: spy);
      final tools = h.phoneMachine.tools;
      h.run(h.phoneMachine.connect());
      settle(async);
      final before = _framesFromPhone(h);
      for (var i = 0; i < 250; i++) {
        tools.enqueue(
          ToolData(id: i, data: Uint8List(kToolMaxChunkBytes), end: false),
        );
      }
      async.elapse(const Duration(seconds: 1));
      expect(_framesFromPhone(h) - before, lessThanOrEqualTo(10 + 100));
      async.elapse(const Duration(seconds: 2));
      settle(async);
      expect(_framesFromPhone(h) - before, 250);
      expect(
        [for (final m in spy.handled.whereType<ToolData>()) m.id],
        [for (var i = 0; i < 250; i++) i],
      );
    });
  });

  test(
    'a message over one sealed batch is refused; the channel stays (RF 1)',
    () {
      fakeAsync((async) {
        final spy = _Spy();
        final h = Harness(async, keys, tools: spy);
        final machine = h.phoneMachine;
        h.run(machine.connect());
        expect(
          machine.tools.enqueue(
            ToolData(id: 1, data: Uint8List(kMaxSealedBatchBytes), end: false),
          ),
          isFalse,
        );
        settle(async);
        expect(machine.state, isA<MachineReady>());
      });
    },
  );

  test('a lost channel: opens fail, streams hear it, nothing queued goes '
      'out; the new one asks for the list again', () {
    fakeAsync((async) {
      final spy = _Spy();
      final h = Harness(async, keys, tools: spy);
      final tools = h.phoneMachine.tools;
      h.run(tools.watch());
      settle(async);
      final listener = _Listener();
      tools.listen(5, listener);
      spy.say(const ToolAck([5, 10]));
      settle(async);
      expect(listener.heard, ['ack 10']);
      final opening = tools.open('k3f9za7q1m');
      Object? failure;
      opening.catchError((Object e) {
        failure = e;
        return const ToolOpened(rid: 0, ok: false);
      });
      tools.enqueue(const ToolEnd(id: 9, code: 'aborted'));
      final lists = spy.handled.whereType<ToolList>().length;
      h.disconnectPhone();
      settle(async);
      expect(listener.heard.last, 'lost');
      expect(failure, isA<MachineConnectionException>());
      h.reconnectPhone();
      settle(async, const Duration(seconds: 1));
      expect(spy.handled.whereType<ToolList>().length, lists + 1);
      expect(spy.handled.whereType<ToolEnd>().where((m) => m.id == 9), isEmpty);
    });
  });

  group('compatibility (E19, mandatory)', () {
    test('new phone, old desktop: no tools flag; a tool.* sent anyway is '
        'ignored, nothing waits forever, terminals fine', () {
      fakeAsync((async) {
        final h = Harness(async, keys); // an agent without tools for phones
        final machine = h.phoneMachine;
        h.run(machine.listSessions(includeDesktop: true));
        expect(machine.tools.supported, isFalse);
        expect(
          () => h.run(machine.tools.open('k3f9za7q1m')),
          throwsA(isA<MachineConnectionException>()),
        );
        final tab = h.run(machine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        h.pty.emit('still here\r\n');
        settle(async);
        expect(recorder.text, contains('still here'));
      });
    });

    test('old phone, new desktop: a phone that never asks gets no tool.*', () {
      fakeAsync((async) {
        final proxy = ToolProxy()..serve(_catalog());
        final toPhones = <OutboundMessage>[];
        proxy.outbound.listen(toPhones.add);
        final h = Harness(async, keys, tools: proxy);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        proxy.serve(ToolCatalog([]));
        h.pty.emit('ok\r\n');
        settle(async, const Duration(seconds: 1));
        expect(toPhones, isEmpty);
        expect(recorder.text, contains('ok'));
        proxy.close();
      });
    });
  });
}
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart test test/tools_test.dart`
Expected: FAIL to compile — `MachineClient.tools` and `ToolStreamListener` are not defined.

- [ ] **Step 3: Write `MachineTools`**

`packages/shellx_client/lib/src/machine_tools.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';

/// V2-4 §4.2: one tool a computer lets this phone open.
final class ToolInfo {
  const ToolInfo({
    required this.id,
    required this.name,
    required this.ws,
    required this.port,
    required this.path,
    required this.group,
  });

  final String id;
  final String name;

  /// The workspace's name ("shop-web").
  final String ws;
  final int port;

  /// The start page (path and query).
  final String path;

  /// The workspace's key: tools of one group are served together (E4).
  final String group;

  @override
  bool operator ==(Object other) =>
      other is ToolInfo &&
      other.id == id &&
      other.name == name &&
      other.ws == ws &&
      other.port == port &&
      other.path == path &&
      other.group == group;

  @override
  int get hashCode => Object.hash(id, name, ws, port, path, group);

  @override
  String toString() => 'ToolInfo(…)';
}

/// V2-4 §4.2: what `tool.list.result` says. [available] is false while the
/// computer has no list yet ("Mở ShellX trên máy tính để dùng tool.").
final class ToolListing {
  const ToolListing({this.available = true, this.tools = const []});

  final bool available;
  final List<ToolInfo> tools;

  /// Never throws: an entry this version cannot read is left out.
  static ToolListing fromBody(Uint8List body, {required bool available}) {
    final json = _json(body);
    final list = json is Map ? json['tools'] : null;
    return ToolListing(
      available: available,
      tools: [
        if (list is List)
          for (final entry in list) ?_tool(entry),
      ],
    );
  }

  static ToolInfo? _tool(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['name'];
    final ws = entry['ws'];
    final port = entry['port'];
    final path = entry['path'];
    final group = entry['group'];
    if (id is! String || name is! String || ws is! String) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    if (path is! String || !isToolTarget(path) || group is! String) {
      return null;
    }
    return ToolInfo(
      id: id,
      name: name,
      ws: ws,
      port: port,
      path: path,
      group: group,
    );
  }

  @override
  String toString() => 'ToolListing(…)';
}

/// V2-4 E4: one tool a phone serves while a tool is open, from
/// `tool.opened`'s body (the opened tool first).
final class ToolServing {
  const ToolServing({required this.id, required this.port, required this.path});
  final String id;
  final int port;
  final String path;

  /// Never throws; empty when [body] is not readable.
  static List<ToolServing> fromBody(Uint8List? body) {
    final json = body == null ? null : _json(body);
    final list = json is Map ? json['tools'] : null;
    return [
      if (list is List)
        for (final entry in list)
          if (entry is Map &&
              entry['id'] is String &&
              entry['port'] is int &&
              (entry['port'] as int) >= 1 &&
              (entry['port'] as int) <= 65535 &&
              entry['path'] is String &&
              isToolTarget(entry['path'] as String))
            ToolServing(
              id: entry['id'] as String,
              port: entry['port'] as int,
              path: entry['path'] as String,
            ),
    ];
  }

  @override
  String toString() => 'ToolServing(…)';
}

Object? _json(Uint8List body) {
  try {
    return jsonDecode(utf8.decode(body));
  } on FormatException {
    return null;
  }
}

/// What a stream of a tool page hears from the computer.
abstract interface class ToolStreamListener {
  void onResponse(ToolResponse message);
  void onData(ToolData message);
  void onWsMessage(ToolWsMessage message);

  /// The computer took [total] bytes of what this phone sent.
  void onAck(int total);

  /// The computer ended the stream (after this nothing more comes for it).
  void onEnd(ToolEnd message);

  /// The channel is gone: the stream is over.
  void onLost();
}

/// V2-4 E8: tool frames per second this phone sends at most (of the relay's
/// 500 per device), and at once.
const int kToolPhoneFramesPerSecond = 100;
const int kToolPhoneFrameBurst = 10;

/// The personal web tools of one machine (V2-4): their list, opening one,
/// the streams of the open tool page, and the tool outbox (E8) every `tool.*`
/// message goes through: collected for [flushInterval], split with
/// [splitIntoBatches], at most [kToolPhoneFramesPerSecond] frames a second;
/// acknowledgements of every stream in one `tool.ack` per 50 ms. Part of
/// [MachineClient]. Never logs what it carries.
final class MachineTools {
  @internal
  MachineTools({
    required bool Function(List<AppMessage> messages) send,
    required Future<void> Function() connect,
    required Duration timeout,
    this.flushInterval = const Duration(milliseconds: 16),
    int framesPerSecond = kToolPhoneFramesPerSecond,
    int frameBurst = kToolPhoneFrameBurst,
  }) : _sendRaw = send,
       _connect = connect,
       _timeout = timeout,
       _frameEvery = Duration(microseconds: 1000000 ~/ framesPerSecond),
       _frameBurst = frameBurst,
       _frames = frameBurst {
    acks = ToolAckBook(enqueue);
  }

  final bool Function(List<AppMessage>) _sendRaw;
  final Future<void> Function() _connect;
  final Duration _timeout;
  final Duration flushInterval;

  /// One frame token comes back this often (E8: 100 a second), up to
  /// [_frameBurst].
  final Duration _frameEvery;
  final int _frameBurst;
  bool? _supported;
  ToolListing? _listing;
  final _listings = StreamController<ToolListing>.broadcast(sync: true);
  final _links = StreamController<bool>.broadcast(sync: true);
  var _watching = false;
  var _connected = false;
  var _disposed = false;
  final _opens = <int, Completer<ToolOpened>>{};
  var _nextRid = 1;
  var _nextStream = 1;
  final _streams = <int, ToolStreamListener>{};

  /// Phone → desktop bytes in flight over all streams (E7).
  ToolCredit credit = ToolCredit();

  /// What this phone took of the computer's bodies and messages.
  late final ToolAckBook acks;

  // The outbox.
  final _outbox = <AppMessage>[];
  Timer? _flush;
  int _frames;
  Timer? _refill;

  /// Pages keeping the channel: an open tool page wants it back after a loss.
  int _holders = 0;

  /// Whether the computer has tools for phones (`tools` in
  /// `session.list.result`); null before the first desktop list.
  bool? get supported => _supported;

  ToolListing? get listing => _listing;

  /// Every list as it comes (the first answer, then each change).
  Stream<ToolListing> get listings => _listings.stream;

  /// True when a channel is installed, false when it is lost.
  Stream<bool> get links => _links.stream;

  bool get connected => _connected;

  /// The list is watched or a tool page is open: a lost channel must come
  /// back even without a terminal tab.
  bool get wantsChannel => _watching || _holders > 0;

  /// Keeps the list current: asks now (connecting first when there is no
  /// channel) and again on every new channel.
  Future<void> watch() async {
    _watching = true;
    if (!enqueue(const ToolList())) await _connect(); // channelReady asks
  }

  /// The inverse of [watch]; a no-op when nothing is watched.
  void unwatch() => _watching = false;

  /// A tool page holds the channel, and the list (its changes tell the page
  /// its tool was turned off or deleted, E16), until the returned function is
  /// called.
  void Function() hold() {
    _holders++;
    if (_holders == 1 && !_watching) enqueue(const ToolList());
    var held = true;
    return () {
      if (!held) return;
      held = false;
      _holders--;
    };
  }

  /// `tool.open` [tool] (an id from the list): the computer checks its flag
  /// and tries its port. Connects first; throws
  /// [MachineConnectionException] like every request.
  Future<ToolOpened> open(String tool) async {
    await _connect();
    final rid = _nextRid++;
    final done = _opens[rid] = Completer<ToolOpened>();
    if (!enqueue(ToolOpen(rid: rid, tool: tool))) {
      _opens.remove(rid);
      throw const MachineConnectionException(
        MachineConnectionFailure.agentOffline,
      );
    }
    return done.future.timeout(
      _timeout,
      onTimeout: () {
        _opens.remove(rid);
        throw const MachineConnectionException(
          MachineConnectionFailure.timeout,
        );
      },
    );
  }

  /// A new stream number on this channel.
  int newStreamId() => _nextStream++;

  /// The computer's messages for stream [id] go to [listener] until it ends,
  /// the channel goes, or [release].
  void listen(int id, ToolStreamListener listener) => _streams[id] = listener;

  void release(int id) {
    _streams.remove(id);
    acks.forget(id);
  }

  /// Queues [message] in the tool outbox. False (nothing queued) without a
  /// channel, or for a message that would not fit one sealed batch (it would
  /// drop the channel, RF 1).
  bool enqueue(ToolMessage message) {
    if (!_connected || _disposed) return false;
    if (encodeBatch([message]).length > kMaxSealedBatchBytes) return false;
    _outbox.add(message);
    _flush ??= Timer(flushInterval, _send);
    return true;
  }

  void _send() {
    _flush = null;
    if (!_connected || _outbox.isEmpty) return;
    final batches = splitIntoBatches(_outbox);
    _outbox.clear();
    var sent = 0;
    for (final batch in batches) {
      if (_frames < 1) break;
      if (!_sendRaw(batch)) {
        sent = batches.length; // the channel is gone: drop the rest
        break;
      }
      _spend();
      sent++;
    }
    // Over the frame budget: the rest waits, in order, for the next token.
    _outbox.addAll([for (final batch in batches.skip(sent)) ...batch]);
  }

  void _spend() {
    _frames--;
    _refill ??= Timer.periodic(_frameEvery, (_) {
      _frames++;
      if (_frames >= _frameBurst) {
        _refill?.cancel();
        _refill = null;
      }
      if (_outbox.isNotEmpty && _flush == null) _send();
    });
  }

  // ------------------------------------------------- from MachineClient --

  /// The answer to a `session.list {desktop: true}`.
  @internal
  void noteListResult(SessionListResult result) {
    final tools = result.tools;
    _supported = tools != null && tools >= 1;
  }

  @internal
  void handle(ToolMessage message) {
    if (_disposed) return;
    switch (message) {
      case ToolListResult(:final available, :final body):
        _supported = true;
        final listing = ToolListing.fromBody(body, available: available);
        _listing = listing;
        _listings.add(listing);
      case ToolOpened(:final rid):
        _opens.remove(rid)?.complete(message);
      case ToolResponse(:final id):
        _streams[id]?.onResponse(message);
      case ToolData(:final id):
        _streams[id]?.onData(message);
      case ToolWsMessage(:final id):
        _streams[id]?.onWsMessage(message);
      case ToolAck(:final acks):
        for (var i = 0; i + 1 < acks.length; i += 2) {
          _streams[acks[i]]?.onAck(acks[i + 1]);
        }
      case ToolEnd(:final id):
        final listener = _streams.remove(id);
        acks.forget(id);
        listener?.onEnd(message);
      case ToolList() || ToolOpen() || ToolClose() || ToolRequest():
        break; // a phone's own kinds never come from the computer
    }
  }

  @internal
  void channelReady() {
    if (_disposed) return;
    _connected = true;
    if (wantsChannel) enqueue(const ToolList());
    _links.add(true);
  }

  /// The channel is gone: opens in flight fail (never sent again), every
  /// stream ends, nothing queued goes out.
  @internal
  void channelLost() {
    _connected = false;
    _flush?.cancel();
    _flush = null;
    _refill?.cancel();
    _refill = null;
    _frames = _frameBurst;
    _outbox.clear();
    acks.clear();
    credit = ToolCredit();
    final opens = [..._opens.values];
    _opens.clear();
    for (final open in opens) {
      open.completeError(
        const MachineConnectionException(MachineConnectionFailure.agentOffline),
      );
    }
    final streams = [..._streams.values];
    _streams.clear();
    for (final stream in streams) {
      stream.onLost();
    }
    if (!_disposed) _links.add(false);
  }

  @internal
  void dispose() {
    if (_disposed) return;
    channelLost();
    _disposed = true;
    unawaited(_listings.close());
    unawaited(_links.close());
  }
}
````

In `packages/shellx_client/lib/shellx_client.dart`, after `export 'src/machine_client.dart';` add:

````dart
export 'src/machine_tools.dart';
````

- [ ] **Step 4: Wire it into `MachineClient`**

In `packages/shellx_client/lib/src/machine_client.dart`:

1. After `import 'machine_ai.dart';` add `import 'machine_tools.dart';`.
2. After the field `late final MachineAi ai = MachineAi(...);` add:

````dart

  /// V2-4: the machine's tools for phones (listing, opening, the tunnel's
  /// outbox).
  late final MachineTools tools = MachineTools(
    send: _send,
    connect: connect,
    timeout: _timeout,
  );
````

3. In `shutdown()`, after `ai.dispose();` add `tools.dispose();`.
4. In the handshake's success path, after `ai.channelReady();` add `tools.channelReady();`.
5. In `_dispatch`, the `SessionListResult` case, replace `if (pending.desktop) ai.noteListResult(message);` with:

````dart
        if (pending.desktop) {
          ai.noteListResult(message);
          tools.noteListResult(message);
        }
````

6. In `_dispatch`, after the case `case AiMessage(): ai.handle(message);` add:

````dart
      case ToolMessage():
        tools.handle(message);
````

7. In `_resumeOnce`, replace `!ai.wantsChannel) {` with:

````dart
        !ai.wantsChannel &&
        !tools.wantsChannel) {
````

8. In `_channelLost`, after `ai.channelLost();` add `tools.channelLost();`.

- [ ] **Step 5: Run the tests to verify they pass**

````bash
cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart format lib/src/machine_tools.dart lib/src/machine_client.dart lib/shellx_client.dart test/support/harness.dart test/tools_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (159 → 166).

- [ ] **Step 6: Commit**

````bash
git add packages/shellx_client/lib/src/machine_tools.dart packages/shellx_client/lib/src/machine_client.dart packages/shellx_client/lib/shellx_client.dart packages/shellx_client/test/support/harness.dart packages/shellx_client/test/tools_test.dart
git commit -m "feat(v2-tools): MachineTools on the phone — the tools flag and list, tool.open, stream routing, a paced tool outbox

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 9: The phone's loopback server for one open tool (`ToolSession`)

**Why `shellx_client`, pure Dart:** the server needs only `dart:io` and `MachineTools`, so it is tested in `dart test` with real sockets: a real tool, the real `ToolProxy` and a stand-in webview (an `HttpClient` that, like the webview, always reaches 127.0.0.1 and keeps cookies). The same code then runs in the in-process end to end (Task 10). The app (Tasks 12–13) only adds the web view and the strings.

What it does:
- **Serving (R5, E2–E4):**
  - `start()` asks `tool.open`;
  - on `ok` it binds 127.0.0.1 on the tool's own port and [::1] on the same port when it can (`v6Only`); if the port is taken, an ephemeral port (E3, `alias`);
  - it binds each other tool of the workspace on its own port when that is free (E4); never `any`.
- **The gate (E11, R6):**
  - one 128-bit secret per page;
  - the one-time entry URL (`/__shellx/enter?n=…&to=…`, 10 s) answers 303 with the HttpOnly, SameSite=Strict gate cookie;
  - every other request needs the cookie (constant-time compare) and a loopback `Host` with the served port; a CORS preflight of a served origin is the one exception;
  - `/__shellx/` is never sent on;
  - unsafe methods and upgrades need a served `Origin` and no `Sec-Fetch-Site: cross-site`;
  - `defaultResponseHeaders` are cleared and `serverHeader` is null.
- **Request checks before anything is sent:** origin-form target (414 when too long), method (405), head limits (431, RF 1), body length (413), stream limits (503).
- **Bridging:**
  - HTTP and WebSockets go through `MachineTools`: the request body by `ToolBytesOut` within the phone → desktop windows, the answer by `ToolBytesIn`, acknowledged as the webview takes it;
  - `bufferOutput = false` on every response (R11);
  - a `Content-Disposition: attachment` raises `ToolDownloadBlocked` (E12).
- **WebSockets (R7):** the phone writes its own `101` with `Sec-WebSocket-Accept` (SHA-1 from `package:cryptography`'s `DartSha1`), detaches the socket and wraps it; a refusal reaches the webview as the tool's HTTP answer; close codes cross both ways.
- **Its life:**
  - E13: `pause()` closes everything, `resume()` serves again, maybe on another port, and loads;
  - E15, R18: a lost channel → `reconnecting` (503 meanwhile), and a new channel asks `tool.open` again and reloads;
  - R4: a list where its tool is gone → ask again;
  - R19: `refused`/`busy` → retried after 1, 2, 4, 8 s, then every 10 s;
  - `disabled`/`gone`/`unavailable` → servers closed, phase set;
  - `close()` sends `tool.close`.
- **The page's answers when the computer ends a stream before a response:** 502 with `ToolHostTexts` (the app gives them in its language), 503, 504, 400.
- **E20:** `requests` counts what a page asked since `resetRequests()`.

**Files:**
- Create: `packages/shellx_client/lib/src/tool_session.dart`
- Modify: `packages/shellx_client/pubspec.yaml`, `packages/shellx_client/lib/shellx_client.dart`
- Test: `packages/shellx_client/test/support/test_tool.dart`, `packages/shellx_client/test/support/tool_pipe.dart`, `packages/shellx_client/test/tool_session_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: the `tool.*` messages, `ToolCode`, `toolEndCode`;
  - Task 2: `kToolReservedPrefix`, `toolGateCookieName`, `isToolLoopbackAuthority`, `toolLoopbackPrefix`, `isToolTarget`, `isToolMethod`, `isToolHead`, `toolDroppedNames`, `stripToolGateCookies`, `kToolHopByHop`, `isWritableHeaderValue`, `toolHeadValues`, `kToolMaxHttpStreams`, `kToolMaxWsStreams`, `kToolMaxRequestBodyBytes`, `kToolMaxWsMessageBytes`;
  - Task 3: `ToolSendWindow`, `ToolBytesOut` (`maxBytes`, `onTooLarge`), `ToolBytesIn`, `ToolWsOut`, `ToolWsIn`, `ToolUnpaced`;
  - Task 8: `MachineTools` (`hold`, `links`, `listings`, `open`, `newStreamId`, `listen`, `release`, `enqueue`, `connected`, `credit`, `acks`), `ToolServing`, `ToolStreamListener`, `ToolListing`;
  - existing: `base64UrlNoPad`, `constantTimeEquals` (`shellx_core`);
  - tests only: Task 5 `ToolProxy`, `ToolCatalog`.
- Produces (exported):
  - `enum ToolPhase { opening, ready, refused, disabled, gone, unavailable, busy, reconnecting, paused, closed }`;
  - `sealed class ToolPageEvent`, with:
    - `final class ToolLoad extends ToolPageEvent { const ToolLoad(this.url); final Uri url; }`;
    - `final class ToolReload extends ToolPageEvent { const ToolReload(); }`;
    - `final class ToolSiblingOff extends ToolPageEvent { const ToolSiblingOff(this.port); final int port; }`;
    - `final class ToolDownloadBlocked extends ToolPageEvent { const ToolDownloadBlocked(); }`;
  - `class ToolHostTexts { const ToolHostTexts(); String refused(int port); String siblingOff(int port); String get disabled; String get gone; String get needsDesktop; String get tooLarge; }`;
  - `const List<Duration> kToolRetryDelays` (1, 2, 4, 8, 10 s); `String webSocketAccept(String key)`;
  - `final class ToolSession`:
    - constructor: `ToolSession({required String tool, required int port, required String path, required MachineTools link, ToolHostTexts texts = const ToolHostTexts(), Duration nonceLife = const Duration(seconds: 10), int maxRequestBody = kToolMaxRequestBodyBytes, int maxWsMessage = kToolMaxWsMessageBytes, List<Duration> retryDelays = kToolRetryDelays})`;
    - state: `final String tool; ToolPhase get phase; int get port; int? get servedPort; int? get alias; Set<String> get origins;`
    - E20: `int get requests; void resetRequests();`
    - streams: `Stream<ToolPageEvent> get events; Stream<void> get changes;`
    - life: `void start(); void home(); Future<void> pause(); void resume(); Future<void> close();`
  - test support (Task 10 uses them): `ToolPipe`, `ipv6Only`, `Webview`, `Page`, `until` (`test/support/tool_pipe.dart`), `TestTool`, `ToolHit`, `catalogOf` (`test/support/test_tool.dart`).

- [ ] **Step 1: Write the test support**

`packages/shellx_client/test/support/test_tool.dart`:

````dart
import 'dart:async';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';

/// One request a [TestTool] got.
final class ToolHit {
  ToolHit(this.method, this.uri, this.headers);
  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
}

/// A personal web tool on the computer: HTTP routes on a real loopback
/// server, a page at any other path, and a WebSocket echo at `/ws` (a
/// `close:<code>` text closes it with that code).
final class TestTool {
  TestTool._(this.server, this.routes) {
    // Only what a route sets: the phone's own headers would show.
    server.defaultResponseHeaders.clear();
    server.listen(_serve);
  }

  static Future<TestTool> start({
    Map<String, Future<void> Function(HttpRequest request)> routes = const {},
    InternetAddress? address,
    int port = 0,
  }) async => TestTool._(
    await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, port),
    {...routes},
  );

  final HttpServer server;
  final Map<String, Future<void> Function(HttpRequest request)> routes;
  final hits = <ToolHit>[];
  final wsClosed = <(int?, String?)>[];
  final _sockets = <WebSocket>[];

  int get port => server.port;

  Future<void> _serve(HttpRequest request) async {
    final headers = <String, List<String>>{};
    request.headers.forEach((name, values) => headers[name] = values);
    hits.add(ToolHit(request.method, request.uri, headers));
    final route = routes[request.uri.path];
    if (route != null) return route(request);
    if (request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final ws = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (offered) => offered.first,
      );
      _sockets.add(ws);
      ws.listen((message) {
        if (message is String && message.startsWith('close:')) {
          unawaited(ws.close(int.parse(message.substring(6)), 'by tool'));
        } else {
          ws.add(message);
        }
      }, onDone: () => wsClosed.add((ws.closeCode, ws.closeReason)));
      return;
    }
    request.response
      ..headers.contentType = ContentType.html
      ..write('<h1>${request.uri.path}</h1>');
    await request.response.close();
  }

  /// The entry the window would serve for this tool.
  Map<String, Object?> entry({
    String id = 'k3f9za7q1m',
    String name = 'Bảng việc',
    String host = 'localhost',
    String path = '/',
    String group = 'ws:a',
  }) => {
    'id': id,
    'name': name,
    'ws': 'shop-web',
    'group': group,
    'url': 'http://$host:$port$path',
  };

  Future<void> close() async {
    for (final ws in _sockets) {
      await ws.close().catchError((Object _) => null);
    }
    await server.close(force: true);
  }
}

/// [tools] as the window would serve them.
ToolCatalog catalogOf(
  List<Map<String, Object?>> tools, {
  Iterable<String> off = const [],
}) => ToolCatalog.fromServeBody(ToolCatalog.serveBody(tools, off: off))!;
````

`packages/shellx_client/test/support/tool_pipe.dart`:

````dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

const pipePhone = 'b0000000-0000-4000-8000-000000000002';

/// Polls [condition] every 10 ms until it holds (fails after [timeout]).
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

AppMessage _wire(AppMessage m) => decodeBatch(encodeBatch([m])).single;

/// A phone's [MachineTools] and a desktop's [ToolProxy] joined in memory, as
/// an established channel would: every message crosses the wire's encoding,
/// delivery is in a microtask, the batches the phone sends are counted.
final class ToolPipe {
  ToolPipe(this.proxy) {
    tools = MachineTools(
      send: _toDesktop,
      connect: () async {
        if (!connected) {
          throw const MachineConnectionException(
            MachineConnectionFailure.agentOffline,
          );
        }
      },
      timeout: const Duration(seconds: 5),
    );
    proxy.outbound
        .where((o) => o.mobileId == pipePhone)
        .listen(
          (o) => scheduleMicrotask(() {
            if (connected) tools.handle(_wire(o.message) as ToolMessage);
          }),
        );
    tools.channelReady();
  }

  final ToolProxy proxy;
  late final MachineTools tools;
  bool connected = true;

  /// When each batch (one relay frame) left the phone.
  final batches = <Duration>[];
  final _clock = Stopwatch()..start();

  bool _toDesktop(List<AppMessage> batch) {
    if (!connected) return false;
    batches.add(_clock.elapsed);
    final messages = decodeBatch(encodeBatch(batch));
    scheduleMicrotask(() {
      for (final m in messages) {
        if (connected) proxy.handle(pipePhone, m as ToolMessage);
      }
    });
    return true;
  }

  /// The channel drops (relay gone, app in the background).
  void drop() {
    connected = false;
    tools.channelLost();
    proxy.phoneGone(pipePhone);
  }

  /// A new channel.
  void restore() {
    connected = true;
    tools.channelReady();
  }
}

/// Reaches [::1] only: the desktop's side of a test where the phone's server
/// holds 127.0.0.1 on the same port (one machine plays both).
Future<Socket> ipv6Only(int port) =>
    Socket.connect(InternetAddress.loopbackIPv6, port);

/// One answer the [Webview] got.
final class Page {
  Page(this.status, this.headers, this.body);
  final int status;
  final Map<String, List<String>> headers;
  final Uint8List body;
  String get text => String.fromCharCodes(body);
}

/// The phone's webview, as far as the server can tell: it always reaches
/// 127.0.0.1 (this phone's loopback), sends the `Host` of the URL, keeps the
/// cookies it is given (by name; HttpOnly ones too) and follows nothing.
final class Webview {
  final _client = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..autoUncompress = false
    ..connectionFactory = (uri, _, _) async => ConnectionTask.fromSocket(
      Socket.connect(InternetAddress.loopbackIPv4, uri.port),
      () {},
    );
  final cookies = <String, String>{};

  String get cookieHeader =>
      [for (final e in cookies.entries) '${e.key}=${e.value}'].join('; ');

  Future<Page> request(
    Uri url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    List<int>? body,
    bool withCookies = true,
  }) async {
    final request = await _client.openUrl(method, url);
    request.followRedirects = false;
    if (withCookies && cookies.isNotEmpty) {
      request.headers.set('cookie', cookieHeader);
    }
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    final response = await request.close();
    final got = <String, List<String>>{};
    response.headers.forEach((name, values) => got[name] = values);
    for (final cookie in got['set-cookie'] ?? const <String>[]) {
      final pair = cookie.split(';').first;
      final at = pair.indexOf('=');
      cookies[pair.substring(0, at)] = pair.substring(at + 1);
    }
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return Page(response.statusCode, got, Uint8List.fromList(bytes));
  }

  /// Loads the entry URL, then where it sends the webview.
  Future<Page> enter(Uri entry) async {
    final first = await request(entry);
    final location = first.headers['location']?.single;
    if (first.status != 303 || location == null) return first;
    return request(entry.resolve(location));
  }

  Future<WebSocket> socket(
    Uri url, {
    List<String>? protocols,
    String? origin,
  }) => WebSocket.connect(
    url.toString(),
    protocols: protocols,
    headers: {
      if (cookies.isNotEmpty) 'cookie': cookieHeader,
      'origin': ?origin,
    },
    customClient: _client,
  );

  void close() => _client.close(force: true);
}
````

- [ ] **Step 2: Write the failing tests**

`packages/shellx_client/test/tool_session_test.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/test_tool.dart';
import 'support/tool_pipe.dart';

const _id = 'k3f9za7q1m';

/// V2-4 E2, E3, E4, E11, E13, §8: the phone's loopback server for one open
/// tool, with real sockets: a tool, the desktop's proxy, the phone's
/// session, and a webview stand-in.
void main() {
  late TestTool tool;
  late ToolProxy proxy;
  late ToolPipe pipe;
  late ToolSession session;
  late Webview webview;
  late List<ToolPageEvent> events;

  /// The tool on [::1] only and the proxy reaching [::1] only, so the phone
  /// can hold 127.0.0.1 on the tool's own port (one machine plays both).
  Future<void> openSamePort({
    Map<String, Future<void> Function(HttpRequest)> routes = const {},
    List<Map<String, Object?>> Function(TestTool tool)? catalog,
    List<Duration> retry = kToolRetryDelays,
  }) async {
    tool = await TestTool.start(
      routes: routes,
      address: InternetAddress.loopbackIPv6,
    );
    proxy = ToolProxy(connect: ipv6Only);
    proxy.serve(catalogOf(catalog?.call(tool) ?? [tool.entry(host: '[::1]')]));
    pipe = ToolPipe(proxy);
    session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: pipe.tools,
      retryDelays: retry,
    );
    events = [];
    session.events.listen(events.add);
    webview = Webview();
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
  }

  Uri at(String path, {int? port}) =>
      Uri.parse('http://localhost:${port ?? session.servedPort}$path');

  tearDown(() async {
    await session.close();
    webview.close();
    proxy.close();
    await tool.close();
  });

  group('the gate (E11, RF 5)', () {
    test('the entry URL sets the gate cookie once, then the page comes '
        'through the tunnel on the tool\'s own port (E2)', () async {
      await openSamePort();
      expect(session.phase, ToolPhase.ready);
      expect(
        session.servedPort,
        tool.port,
        reason: 'the same port as the tool',
      );
      expect(session.alias, isNull);
      final entry = events.whereType<ToolLoad>().single.url;
      expect(entry.path, '/__shellx/enter');
      final first = await webview.request(entry);
      expect(first.status, 303);
      expect(first.headers['location'], ['/']);
      expect(first.headers['cache-control'], ['no-store']);
      expect(first.headers['referrer-policy'], ['no-referrer']);
      final cookie = first.headers['set-cookie']!.single;
      expect(cookie, startsWith('__shellx_${tool.port}='));
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Strict'));
      expect(cookie, contains('Path=/'));
      final page = await webview.request(at('/'));
      expect(page.status, 200);
      expect(page.text, '<h1>/</h1>');
      final hit = tool.hits.single;
      expect(hit.headers['host'], ['localhost:${tool.port}']);
      expect(
        hit.headers['cookie'],
        isNull,
        reason: 'the gate cookie stays on the phone',
      );
      // Used once: the same entry URL is refused now.
      final again = await webview.request(entry, withCookies: false);
      expect(again.status, 403);
    });

    test('without the cookie, with another Host, or with an expired entry: '
        '403, and nothing reaches the tool', () async {
      await openSamePort();
      expect((await webview.request(at('/'))).status, 403);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      final rebinding = await webview.request(
        at('/'),
        headers: {'host': 'evil.com:${session.servedPort}'},
      );
      expect(rebinding.status, 403, reason: 'DNS rebinding');
      final other = Webview();
      addTearDown(other.close);
      expect((await other.request(at('/'))).status, 403, reason: 'another app');
      expect(tool.hits, isEmpty);
    });

    test('/__shellx/ is the phone\'s own: never sent on', () async {
      await openSamePort();
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      expect((await webview.request(at('/__shellx/other'))).status, 404);
      expect((await webview.request(at('/__shellx/enter?n=x'))).status, 403);
      expect(tool.hits, isEmpty);
    });

    test('an unsafe request from another origin, or cross-site, is refused; '
        'a tool cannot set the gate cookie; the phone adds no header of its '
        'own', () async {
      await openSamePort(
        routes: {
          '/post': (request) async {
            await request.drain<void>();
            request.response.headers.add(
              'set-cookie',
              '__shellx_${request.connectionInfo!.localPort}=stolen; Path=/',
            );
            request.response.headers.add('set-cookie', 'sid=1; Path=/');
            await request.response.close();
          },
        },
      );
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final evil = await webview.request(
        at('/post'),
        method: 'POST',
        headers: {'origin': 'http://evil.com'},
        body: [1],
      );
      expect(evil.status, 403);
      final crossSite = await webview.request(
        at('/post'),
        method: 'POST',
        headers: {'sec-fetch-site': 'cross-site'},
        body: [1],
      );
      expect(crossSite.status, 403);
      final ok = await webview.request(
        at('/post'),
        method: 'POST',
        headers: {'origin': 'http://localhost:${session.servedPort}'},
        body: [1],
      );
      expect(ok.status, 200);
      expect(ok.headers['set-cookie'], ['sid=1; Path=/']);
      for (final name in [
        'x-frame-options',
        'x-content-type-options',
        'x-xss-protection',
        'server',
      ]) {
        expect(ok.headers[name], isNull, reason: name);
      }
    });
  });

  test('a head over the limits is answered 431 here; nothing goes to the '
      'computer (RF 1)', () async {
    await openSamePort();
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final before = pipe.batches.length;
    final big = await webview.request(
      at('/'),
      headers: {'x-big': 'x' * (kToolMaxHeadBytes + 1)},
    );
    expect(big.status, 431);
    expect(pipe.batches.length, before);
    expect(tool.hits, hasLength(1), reason: 'only the entry page');
  });

  test('the tool\'s port is taken on the phone: another port, and the '
      'desktop rewrites Host and Origin (E3)', () async {
    tool = await TestTool.start(); // on 127.0.0.1: the phone cannot have it
    proxy = ToolProxy();
    proxy.serve(catalogOf([tool.entry()]));
    pipe = ToolPipe(proxy);
    session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: pipe.tools,
    );
    events = [];
    session.events.listen(events.add);
    webview = Webview();
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    expect(session.alias, isNotNull);
    expect(session.alias, isNot(tool.port));
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final page = await webview.request(
      at('/form'),
      method: 'POST',
      headers: {'origin': 'http://localhost:${session.alias}'},
      body: utf8.encode('a=1'),
    );
    expect(page.status, 200);
    final hit = tool.hits.last;
    expect(hit.headers['host'], ['localhost:${tool.port}']);
    expect(hit.headers['origin'], ['http://localhost:${tool.port}']);
  });

  test('a WebSocket through the gate: upgrade, echo, close', () async {
    await openSamePort();
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final ws = await webview.socket(
      Uri.parse('ws://localhost:${session.servedPort}/ws'),
      protocols: ['vite-hmr'],
      origin: 'http://localhost:${session.servedPort}',
    );
    expect(ws.protocol, 'vite-hmr');
    final got = <Object?>[];
    ws.listen(got.add);
    ws.add('ping');
    await until(() => got.isNotEmpty);
    expect(got.single, 'ping');
    ws.add('close:4001');
    await ws.done;
    expect(ws.closeCode, 4001);
  });

  test('a WebSocket without the cookie: 403', () async {
    await openSamePort();
    await expectLater(
      webview.socket(Uri.parse('ws://localhost:${session.servedPort}/ws')),
      throwsA(isA<WebSocketException>()),
    );
    expect(tool.hits, isEmpty);
  });

  group('life of the page (E13)', () {
    test(
      'paused: nothing is served; resumed: served again and loaded',
      () async {
        await openSamePort();
        final port = session.servedPort!;
        await session.pause();
        expect(session.phase, ToolPhase.paused);
        await expectLater(
          webview.request(at('/', port: port)),
          throwsA(isA<SocketException>()),
        );
        session.resume();
        await until(() => events.whereType<ToolLoad>().length == 2);
        expect(session.phase, ToolPhase.ready);
        final page = await webview.enter(events.whereType<ToolLoad>().last.url);
        expect(page.status, 200);
      },
    );

    test('the channel goes: reconnecting, requests get 503; back: ready and '
        'reloaded', () async {
      await openSamePort();
      await webview.enter(events.whereType<ToolLoad>().single.url);
      pipe.drop();
      expect(session.phase, ToolPhase.reconnecting);
      expect((await webview.request(at('/'))).status, 503);
      pipe.restore();
      await until(() => session.phase == ToolPhase.ready);
      expect(events.last, isA<ToolReload>());
      expect((await webview.request(at('/'))).status, 200);
    });

    test('leaving the page tells the computer and ends its streams', () async {
      final held = <HttpResponse>[];
      await openSamePort(
        routes: {
          '/events': (request) async {
            request.response
              ..bufferOutput = false
              ..write('data: 1\n\n');
            await request.response.flush();
            held.add(request.response);
          },
        },
      );
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final request = webview.request(at('/events'));
      await until(() => held.isNotEmpty);
      await session.close();
      await expectLater(request, throwsA(anything));
      expect(session.phase, ToolPhase.closed);
    });
  });

  group('the computer changes things (E9, E16)', () {
    test('the flag turned off: disabled within a second, even with no '
        'request (success criterion 5)', () async {
      await openSamePort();
      final clock = Stopwatch()..start();
      proxy.serve(catalogOf([], off: [_id]));
      await until(() => session.phase == ToolPhase.disabled);
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('the tool deleted: gone', () async {
      await openSamePort();
      proxy.serve(catalogOf([]));
      await until(() => session.phase == ToolPhase.gone);
    });

    test('nothing runs on the port: refused, tried again, ready when it is '
        'back', () async {
      await openSamePort(retry: const [Duration(milliseconds: 100)]);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final port = tool.port;
      await tool.server.close(force: true);
      final failed = await webview.request(at('/'));
      expect(failed.status, 502);
      expect(failed.text, contains('localhost:$port'));
      await until(() => session.phase == ToolPhase.refused);
      tool = await TestTool.start(
        address: InternetAddress.loopbackIPv6,
        port: port,
      );
      await until(() => session.phase == ToolPhase.ready);
      expect(events.last, isA<ToolReload>());
    });
  });

  test('the other tools of the workspace on their own ports (E4); one '
      'turned off answers 502 and is told', () async {
    late TestTool api;
    await openSamePort(catalog: (tool) => [tool.entry(host: '[::1]')]);
    api = await TestTool.start(address: InternetAddress.loopbackIPv6);
    addTearDown(api.close);
    await session.close();
    proxy.serve(
      catalogOf([
        tool.entry(host: '[::1]'),
        api.entry(id: 'api0000001', name: 'API', host: '[::1]'),
      ]),
    );
    events.clear();
    session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: pipe.tools,
    );
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    expect(session.origins, {
      'http://localhost:${tool.port}',
      'http://localhost:${api.port}',
    });
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final fromApi = await webview.request(at('/v1', port: api.port));
    expect(fromApi.status, 200);
    expect(api.hits.single.headers['host'], ['localhost:${api.port}']);
    // A CORS preflight carries no cookie: let through for a served origin.
    final preflight = await webview.request(
      at('/v1', port: api.port),
      method: 'OPTIONS',
      withCookies: false,
      headers: {
        'origin': 'http://localhost:${tool.port}',
        'access-control-request-method': 'POST',
      },
    );
    expect(preflight.status, 200);
    proxy.serve(catalogOf([tool.entry(host: '[::1]')], off: ['api0000001']));
    final off = await webview.request(at('/v1', port: api.port));
    expect(off.status, 502);
    await until(() => events.whereType<ToolSiblingOff>().isNotEmpty);
    expect(events.whereType<ToolSiblingOff>().single.port, api.port);
  });

  test('a download is told; requests are counted (E12, E20)', () async {
    await openSamePort(
      routes: {
        '/file': (request) async {
          request.response.headers.set(
            'content-disposition',
            'attachment; filename="a.csv"',
          );
          request.response.write('a,b');
          await request.response.close();
        },
      },
    );
    await webview.enter(events.whereType<ToolLoad>().single.url);
    session.resetRequests();
    await webview.request(at('/file'));
    await webview.request(at('/'));
    expect(session.requests, 2);
    expect(events.whereType<ToolDownloadBlocked>(), hasLength(1));
  });

  test('toString never shows a URL (E18)', () async {
    await openSamePort();
    expect(session.toString(), 'ToolSession(…)');
    expect(events.whereType<ToolLoad>().single.toString(), 'ToolLoad(…)');
    const info = ToolInfo(
      id: _id,
      name: 'Bảng việc',
      ws: 'shop-web',
      port: 1,
      path: '/secret',
      group: 'g',
    );
    expect(info.toString(), 'ToolInfo(…)');
    expect(const ToolListing(tools: [info]).toString(), 'ToolListing(…)');
    expect(
      const ToolServing(id: _id, port: 1, path: '/secret').toString(),
      'ToolServing(…)',
    );
  });
}
````

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart test test/tool_session_test.dart`
Expected: FAIL to compile — `ToolSession`, `ToolPhase`, `ToolLoad` and `kToolRetryDelays` are not defined.

- [ ] **Step 4: Add the SHA-1 dependency**

In `packages/shellx_client/pubspec.yaml`, under `dependencies:`, before `meta: ^1.16.0`, add:

````yaml
  cryptography: ^2.9.0
````

Run at the repo root: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` (the workspace already resolves `cryptography` 2.9 for `shellx_core` and `shellx_agent`; `pubspec.lock` is never added).

- [ ] **Step 5: Write the session**

`packages/shellx_client/lib/src/tool_session.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';
import 'machine_tools.dart';

/// V2-4 E15, E16: where the page of an open tool is.
enum ToolPhase {
  /// Asking the computer (first open, or again after a change).
  opening,

  /// Served: the webview shows the page.
  ready,

  /// Nothing listens on the tool's port on the computer: tried again by
  /// itself (1, 2, 4, 8 s, then every 10 s).
  refused,

  /// Its phone flag was turned off.
  disabled,

  /// Deleted on the computer, or its URL changed.
  gone,

  /// The computer has no list yet (only the background service runs).
  unavailable,

  /// The computer has too many streams of this phone; tried again.
  busy,

  /// The channel is gone: the page stays, and reloads when it is back.
  reconnecting,

  /// The app is in the background: nothing is served (Apple TN2277).
  paused,

  /// The page was left.
  closed,
}

/// What the page must do (the webview's side of E13, E3, E12).
sealed class ToolPageEvent {
  const ToolPageEvent();
}

/// Load [url]: the phone's one-time entry page, which sets the gate cookie
/// and goes on to the start page.
final class ToolLoad extends ToolPageEvent {
  const ToolLoad(this.url);
  final Uri url;
  @override
  String toString() => 'ToolLoad(…)';
}

/// Reload the page (the channel or the tool came back).
final class ToolReload extends ToolPageEvent {
  const ToolReload();
}

/// A page asked for the tool on [port] of the same workspace, which is not
/// on for the phone any more (E4).
final class ToolSiblingOff extends ToolPageEvent {
  const ToolSiblingOff(this.port);
  final int port;
}

/// The tool sent a file to download (E12: not on the phone yet).
final class ToolDownloadBlocked extends ToolPageEvent {
  const ToolDownloadBlocked();
}

/// The plain-text bodies the phone's server answers with itself; the app
/// gives them in the phone's language.
class ToolHostTexts {
  const ToolHostTexts();
  String refused(int port) =>
      'Nothing is running at localhost:$port on the computer.';
  String siblingOff(int port) => "The tool on port $port isn't on for phone.";
  String get disabled => 'This tool can no longer be opened on the phone.';
  String get gone => 'This tool was deleted on the computer.';
  String get needsDesktop => 'Open ShellX on the computer to use tools.';
  String get tooLarge => "The tool's response is too large.";
}

/// The delays between tries while the tool's port refuses (V2-3 D13).
const List<Duration> kToolRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 10),
];

const _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// RFC 6455: the `Sec-WebSocket-Accept` for [key].
String webSocketAccept(String key) => base64Encode(
  const DartSha1().hashSync(utf8.encode('$key$_webSocketGuid')).bytes,
);

/// V2-4 E2, E3, E11, E13: the phone's side of one open tool. It serves the
/// tool (and the other tools of its workspace, E4) on this phone's loopback
/// only, on the tool's own port when it can (else another, E3), and carries
/// every request through [link] to the computer. Only the page's webview
/// gets in: a one-time entry URL ([ToolLoad]) sets an HttpOnly, SameSite
/// gate cookie, and every request must carry it and name a loopback host.
/// Pure Dart (`dart:io`); never logs what it carries.
final class ToolSession {
  ToolSession({
    required this.tool,
    required int port,
    required String path,
    required this.link,
    this.texts = const ToolHostTexts(),
    this.nonceLife = const Duration(seconds: 10),
    this.maxRequestBody = kToolMaxRequestBodyBytes,
    this.maxWsMessage = kToolMaxWsMessageBytes,
    this.retryDelays = kToolRetryDelays,
  }) : _port = port,
       _path = path;

  /// The tool's id (never its URL: E1).
  final String tool;
  final MachineTools link;
  final ToolHostTexts texts;
  final Duration nonceLife;
  final int maxRequestBody;
  final int maxWsMessage;
  final List<Duration> retryDelays;

  final int _port;
  String _path;
  ToolPhase _phase = ToolPhase.opening;
  final _servers = <_Served>[];
  final _streams = <_Stream>{};
  String _secret = '';
  String? _nonce;
  DateTime? _nonceAt;
  int _requests = 0;
  final _events = StreamController<ToolPageEvent>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast(sync: true);
  void Function()? _release;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _retry;
  int _tries = 0;
  bool _checking = false;
  bool _checkAgain = false;

  ToolPhase get phase => _phase;

  /// The tool's port on the computer.
  int get port => _port;

  /// The port this phone serves the tool on; null while nothing is served.
  int? get servedPort => _servers.isEmpty ? null : _servers.first.port;

  /// The served port when it is not the tool's own (E3); null otherwise.
  int? get alias {
    final served = servedPort;
    return served != null && served != _port ? served : null;
  }

  /// The origins this phone serves now (the webview may go there, E12).
  Set<String> get origins => {
    for (final served in _servers) 'http://localhost:${served.port}',
  };

  /// Requests served since [resetRequests] (E20).
  int get requests => _requests;
  void resetRequests() => _requests = 0;

  Stream<ToolPageEvent> get events => _events.stream;

  /// After every change of [phase].
  Stream<void> get changes => _changes.stream;

  /// Opens the tool: asks the computer, then serves it.
  void start() {
    _release ??= link.hold();
    _subscriptions
      ..add(link.links.listen(_onLink))
      ..add(link.listings.listen(_onListing));
    unawaited(_check());
  }

  /// "Về trang đầu": the start page.
  void home() {
    final served = servedPort;
    if (served != null && _phase == ToolPhase.ready) {
      _events.add(ToolLoad(Uri.parse('http://localhost:$served$_path')));
    }
  }

  /// The app goes to the background (E13): nothing is served until
  /// [resume]; every stream ends.
  Future<void> pause() async {
    if (_phase == ToolPhase.closed) return;
    _retry?.cancel();
    await _unserve();
    _set(ToolPhase.paused);
  }

  /// The app is back: served again (the port may change), then loaded.
  void resume() {
    if (_phase != ToolPhase.paused) return;
    _set(ToolPhase.opening);
    unawaited(_check());
  }

  /// The page was left (E13): nothing is served, the computer is told.
  Future<void> close() async {
    if (_phase == ToolPhase.closed) return;
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _unserve();
    link.enqueue(ToolClose(tool: tool));
    _release?.call();
    _release = null;
    _set(ToolPhase.closed);
    unawaited(_events.close());
    unawaited(_changes.close());
  }

  void _set(ToolPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    if (!_changes.isClosed) _changes.add(null);
  }

  void _onLink(bool up) {
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    if (!up) {
      _set(ToolPhase.reconnecting);
    } else {
      unawaited(_check());
    }
  }

  void _onListing(ToolListing listing) {
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    final me = listing.tools.where((t) => t.id == tool).firstOrNull;
    if (!listing.available || me == null || me.port != _port) {
      unawaited(_check());
    }
  }

  /// Asks the computer about the tool (`tool.open`) and acts on the answer.
  Future<void> _check() async {
    if (_checking) {
      _checkAgain = true;
      return;
    }
    _checking = true;
    try {
      do {
        _checkAgain = false;
        await _checkOnce();
      } while (_checkAgain);
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkOnce() async {
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    final ToolOpened opened;
    try {
      opened = await link.open(tool);
    } on MachineConnectionException {
      _set(ToolPhase.reconnecting); // asked again when the channel is back
      return;
    }
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    if (!opened.ok) {
      final code = toolEndCode(opened.code) ?? ToolCode.gone;
      switch (code) {
        case ToolCode.refused || ToolCode.busy:
          _set(code == ToolCode.busy ? ToolPhase.busy : ToolPhase.refused);
          _scheduleRetry();
        case ToolCode.disabled:
          await _unserve();
          _set(ToolPhase.disabled);
        case ToolCode.unavailable || ToolCode.desktopClosed:
          await _unserve();
          _set(ToolPhase.unavailable);
        default:
          await _unserve();
          _set(ToolPhase.gone);
      }
      return;
    }
    final serving = ToolServing.fromBody(opened.body);
    final main = serving.isEmpty ? null : serving.first;
    if (main == null || main.id != tool || main.port != _port) {
      // §7: its URL changed on the computer; the user opens it again.
      await _unserve();
      _set(ToolPhase.gone);
      return;
    }
    _tries = 0;
    _path = main.path;
    final wasReady = _phase == ToolPhase.ready;
    if (_servers.isEmpty) {
      await _serve(serving);
      if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) {
        await _unserve();
        return;
      }
      if (_servers.isEmpty) {
        _set(ToolPhase.refused); // no port at all on this phone
        _scheduleRetry();
        return;
      }
      _set(ToolPhase.ready);
      _events.add(ToolLoad(_entryUrl()));
    } else {
      _set(ToolPhase.ready);
      if (!wasReady) _events.add(const ToolReload());
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final delay = retryDelays[min(_tries, retryDelays.length - 1)];
    _tries++;
    _retry = Timer(delay, () => unawaited(_check()));
  }

  /// A request of the main tool was refused or the tool left the list: the
  /// computer is asked again (once at a time).
  void _recheck() {
    if (_phase == ToolPhase.ready) unawaited(_check());
  }

  // ------------------------------------------------------------- serving --

  String _random() {
    final r = Random.secure();
    return base64UrlNoPad(
      Uint8List.fromList(List.generate(16, (_) => r.nextInt(256))),
    );
  }

  Uri _entryUrl() {
    final nonce = _nonce = _random();
    _nonceAt = DateTime.now();
    return Uri(
      scheme: 'http',
      host: 'localhost',
      port: servedPort,
      path: '${kToolReservedPrefix}enter',
      queryParameters: {'n': nonce, 'to': _path},
    );
  }

  String get _cookieName => toolGateCookieName(servedPort ?? _port);

  /// Binds the tool on its port (or another, E3) and each other tool of the
  /// workspace on its own port when it is free (E4).
  Future<void> _serve(List<ToolServing> serving) async {
    _secret = _random();
    final main = serving.first;
    final own = await _bind(main.port) ?? await _bind(0);
    if (own == null) return;
    _servers.add(_Served(this, main.id, own, main: true));
    for (final other in serving.skip(1)) {
      final servers = await _bind(other.port);
      if (servers != null) _servers.add(_Served(this, other.id, servers));
    }
  }

  /// 127.0.0.1:[port] and, when it can, [::1] on the same port; never any
  /// other address (E11). Null when the port cannot be had.
  Future<List<HttpServer>?> _bind(int port) async {
    final HttpServer v4;
    try {
      v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      return null;
    }
    final servers = [v4];
    try {
      servers.add(
        await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          v4.port,
          v6Only: true,
        ),
      );
    } on SocketException {
      // IPv4 only: `localhost` still reaches it.
    }
    for (final server in servers) {
      server
        ..defaultResponseHeaders
            .clear() // E11: nothing the tool did not send
        ..serverHeader = null
        ..autoCompress = false;
    }
    return servers;
  }

  Future<void> _unserve() async {
    for (final stream in [..._streams]) {
      stream.abort();
    }
    _streams.clear();
    final servers = [..._servers];
    _servers.clear();
    _nonce = null;
    for (final served in servers) {
      await served.close();
    }
  }

  bool _allowedOrigin(String origin) {
    for (final served in _servers) {
      if (toolLoopbackPrefix(origin, served.port) == origin) return true;
    }
    return false;
  }

  bool _hasGate(HttpRequest request) {
    final expected = utf8.encode(_secret);
    for (final cookie in request.headers['cookie'] ?? const <String>[]) {
      for (final pair in cookie.split(';')) {
        final at = pair.indexOf('=');
        if (at < 0 || pair.substring(0, at).trim() != _cookieName) continue;
        final value = utf8.encode(pair.substring(at + 1).trim());
        if (constantTimeEquals(value, expected)) return true;
      }
    }
    return false;
  }

  Future<void> _handle(_Served served, int port, HttpRequest request) async {
    final response = request.response;
    // E11: a page of another host (DNS rebinding) is refused.
    final host = request.headers.value(HttpHeaders.hostHeader) ?? '';
    if (!isToolLoopbackAuthority(host, port)) {
      return _answer(request, HttpStatus.forbidden);
    }
    // E11: the reserved prefix is the phone's own, never the tool's.
    if (request.uri.path.startsWith(kToolReservedPrefix)) {
      return _enter(request, served);
    }
    final origin = request.headers.value('origin');
    final preflight =
        request.method == 'OPTIONS' &&
        origin != null &&
        _allowedOrigin(origin) &&
        request.headers.value('access-control-request-method') != null;
    // E11: only the page's webview has the gate cookie (a CORS preflight of
    // one of the served origins carries none: it is let through, R6).
    if (!preflight && !_hasGate(request)) {
      return _answer(request, HttpStatus.forbidden);
    }
    final upgrade = WebSocketTransformer.isUpgradeRequest(request);
    final safe = const {'GET', 'HEAD', 'OPTIONS'}.contains(request.method);
    if (!safe || upgrade) {
      if (origin != null && !_allowedOrigin(origin)) {
        return _answer(request, HttpStatus.forbidden);
      }
      if (request.headers.value('sec-fetch-site') == 'cross-site') {
        return _answer(request, HttpStatus.forbidden);
      }
    }
    switch (_phase) {
      case ToolPhase.ready:
        break;
      case ToolPhase.disabled:
        return _answer(request, HttpStatus.badGateway, texts.disabled);
      case ToolPhase.gone:
        return _answer(request, HttpStatus.badGateway, texts.gone);
      case ToolPhase.unavailable:
        return _answer(
          request,
          HttpStatus.serviceUnavailable,
          texts.needsDesktop,
        );
      default:
        return _answer(request, HttpStatus.serviceUnavailable);
    }
    if (!link.connected) {
      return _answer(request, HttpStatus.serviceUnavailable);
    }
    final uri = request.uri;
    if (uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !uri.path.startsWith('/')) {
      return _answer(request, HttpStatus.badRequest);
    }
    final target = uri.toString();
    if (!isToolTarget(target)) {
      return _answer(request, HttpStatus.requestUriTooLong);
    }
    if (!isToolMethod(request.method)) {
      return _answer(request, HttpStatus.methodNotAllowed);
    }
    final head = _head(request);
    if (!isToolHead(head)) {
      return _answer(request, HttpStatus.requestHeaderFieldsTooLarge);
    }
    final length = request.headers.contentLength;
    if (length > maxRequestBody) {
      return _answer(request, HttpStatus.requestEntityTooLarge);
    }
    final ws = _streams.whereType<_WsStream>().length;
    final http = _streams.length - ws;
    if (upgrade ? ws >= kToolMaxWsStreams : http >= kToolMaxHttpStreams) {
      return _answer(request, HttpStatus.serviceUnavailable);
    }
    _requests++;
    final id = link.newStreamId();
    final stream = upgrade
        ? _WsStream(this, served, id, request)
        : _HttpStream(
            this,
            served,
            id,
            request,
            hasBody: length > 0 || request.headers.chunkedTransferEncoding,
          );
    _streams.add(stream);
    link.listen(id, stream);
    final sent = link.enqueue(
      ToolRequest(
        id: id,
        tool: served.tool,
        method: request.method,
        target: target,
        head: head,
        alias: served.main ? alias : null,
        ws: upgrade,
        end: stream is! _HttpStream || !stream.hasBody,
      ),
    );
    if (!sent) {
      stream.forget();
      return _answer(request, HttpStatus.serviceUnavailable);
    }
    response.bufferOutput = false; // a piece goes as it comes (SSE)
    stream.start();
  }

  /// The request's head as the computer gets it: no hop-by-hop header, no
  /// gate cookie (E11).
  List<String> _head(HttpRequest request) {
    final raw = <String>[];
    request.headers.forEach((name, values) {
      for (final value in values) {
        raw
          ..add(name)
          ..add(value);
      }
    });
    final dropped = toolDroppedNames(raw);
    final head = <String>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final name = raw[i];
      if (dropped.contains(name)) continue;
      final value = name == 'cookie'
          ? stripToolGateCookies(raw[i + 1])
          : raw[i + 1];
      if (value == null) continue;
      head
        ..add(name)
        ..add(value);
    }
    return head;
  }

  /// `/__shellx/enter?n=<nonce>&to=<path>`: once, within [nonceLife], sets
  /// the gate cookie and goes on to `to` (E11). Anything else there: 404.
  Future<void> _enter(HttpRequest request, _Served served) async {
    final uri = request.uri;
    if (uri.path != '${kToolReservedPrefix}enter' || !served.main) {
      return _answer(request, HttpStatus.notFound);
    }
    final nonce = _nonce;
    final at = _nonceAt;
    final given = uri.queryParameters['n'] ?? '';
    final fresh =
        nonce != null &&
        at != null &&
        DateTime.now().difference(at) <= nonceLife &&
        constantTimeEquals(utf8.encode(given), utf8.encode(nonce));
    if (!fresh) return _answer(request, HttpStatus.forbidden);
    _nonce = null; // one time only
    final to = uri.queryParameters['to'] ?? '/';
    final response = request.response
      ..statusCode = HttpStatus.seeOther
      ..headers.set(HttpHeaders.locationHeader, isToolTarget(to) ? to : '/')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('referrer-policy', 'no-referrer')
      ..headers.add(
        HttpHeaders.setCookieHeader,
        '$_cookieName=$_secret; Path=/; HttpOnly; SameSite=Strict',
      )
      ..contentLength = 0;
    await request.drain<void>().catchError((Object _) {});
    await response.close().catchError((Object _) => response);
  }

  /// Answers [request] here, with [text] as a plain body when given.
  Future<void> _answer(HttpRequest request, int status, [String? text]) async {
    final response = request.response;
    try {
      response.statusCode = status;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (text == null) {
        response.contentLength = 0;
      } else {
        final bytes = utf8.encode(text);
        response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/plain; charset=utf-8',
        );
        response.contentLength = bytes.length;
        response.add(bytes);
      }
      await request.drain<void>().catchError((Object _) {});
      await response.close();
    } on Object {
      // The webview went away meanwhile.
    }
  }

  /// What a stream that ended before its response answers the webview.
  Future<void> _answerEnd(HttpRequest request, _Served served, String? code) {
    final c = toolEndCode(code) ?? ToolCode.aborted;
    if (served.main &&
        (c == ToolCode.refused ||
            c == ToolCode.disabled ||
            c == ToolCode.gone ||
            c == ToolCode.unavailable)) {
      _recheck();
    }
    if (!served.main && (c == ToolCode.disabled || c == ToolCode.gone)) {
      _events.add(ToolSiblingOff(served.port));
    }
    return switch (c) {
      ToolCode.refused => _answer(
        request,
        HttpStatus.badGateway,
        texts.refused(served.main ? _port : served.port),
      ),
      ToolCode.disabled || ToolCode.gone =>
        served.main
            ? _answer(request, HttpStatus.badGateway, texts.disabled)
            : _answer(
                request,
                HttpStatus.badGateway,
                texts.siblingOff(served.port),
              ),
      ToolCode.busy => _answer(request, HttpStatus.serviceUnavailable),
      ToolCode.tooLarge => _answer(
        request,
        HttpStatus.badGateway,
        texts.tooLarge,
      ),
      ToolCode.timeout => _answer(request, HttpStatus.gatewayTimeout),
      ToolCode.unavailable || ToolCode.desktopClosed => _answer(
        request,
        HttpStatus.serviceUnavailable,
        texts.needsDesktop,
      ),
      ToolCode.badRequest => _answer(request, HttpStatus.badRequest),
      _ => _answer(request, HttpStatus.badGateway),
    };
  }

  @override
  String toString() => 'ToolSession(…)';
}

/// One tool served on this phone: its servers (IPv4 and maybe IPv6).
final class _Served {
  _Served(this.session, this.tool, this.servers, {this.main = false}) {
    for (final server in servers) {
      server.listen(
        (request) => unawaited(
          session._handle(this, server.port, request).catchError((Object _) {}),
        ),
        onError: (Object _) {},
      );
    }
  }

  final ToolSession session;
  final String tool;
  final List<HttpServer> servers;
  final bool main;

  int get port => servers.first.port;

  Future<void> close() async {
    for (final server in servers) {
      await server.close(force: true).catchError((Object _) => server);
    }
  }
}

/// One webview request through the tunnel.
sealed class _Stream implements ToolStreamListener {
  _Stream(this.session, this.served, this.id, this.request)
    : window = ToolSendWindow(session.link.credit);

  final ToolSession session;
  final _Served served;
  final int id;
  final HttpRequest request;
  final ToolSendWindow window;
  bool done = false;
  bool responded = false;

  MachineTools get link => session.link;

  void start();

  /// Ended here (page left, app paused): the computer is told.
  void abort() {
    if (done) return;
    link.enqueue(ToolEnd(id: id, code: ToolCode.aborted));
    forget();
    cut();
  }

  /// Drops what is held toward the webview.
  void cut();

  /// The stream is over: forget it.
  void forget() {
    done = true;
    window.close();
    link.release(id);
    session._streams.remove(this);
  }

  @override
  void onLost() {
    if (done) return;
    forget();
    if (responded) {
      cut();
    } else {
      unawaited(session._answer(request, HttpStatus.badGateway));
    }
  }
}

/// An HTTP request: its body to the computer, the answer to the webview.
final class _HttpStream extends _Stream {
  _HttpStream(
    super.session,
    super.served,
    super.id,
    super.request, {
    required this.hasBody,
  });

  final bool hasBody;
  ToolBytesOut? _body;
  ToolBytesIn? _answer;

  @override
  void start() {
    if (!hasBody) {
      unawaited(request.drain<void>().catchError((Object _) {}));
      return;
    }
    _body = ToolBytesOut(
      id: id,
      source: request,
      window: window,
      pacer: const ToolUnpaced(),
      send: link.enqueue,
      maxBytes: session.maxRequestBody,
      onTooLarge: () {
        if (done) return;
        link.enqueue(ToolEnd(id: id, code: ToolCode.aborted));
        forget();
        unawaited(session._answer(request, HttpStatus.requestEntityTooLarge));
      },
      onError: (_) => abort(),
    )..start();
  }

  @override
  void onResponse(ToolResponse message) {
    if (done || responded) return;
    responded = true;
    final response = request.response;
    final status = message.status;
    if (status < 100 || status > 599 || status == 101) {
      forget();
      unawaited(session._answer(request, HttpStatus.badGateway));
      return;
    }
    response.statusCode = status;
    int? length;
    for (var i = 0; i + 1 < message.head.length; i += 2) {
      final name = message.head[i];
      final value = message.head[i + 1];
      if (name == 'content-length') {
        length = int.tryParse(value);
        continue;
      }
      if (kToolHopByHop.contains(name) || !isWritableHeaderValue(value)) {
        continue;
      }
      if (name == 'content-disposition' &&
          value.toLowerCase().startsWith('attachment')) {
        session._events.add(const ToolDownloadBlocked());
      }
      try {
        response.headers.add(name, value);
      } on FormatException {
        // A name dart:io refuses: left out.
      }
    }
    final head = request.method == 'HEAD';
    final noBody = status == 204 || status == 304 || status < 200;
    if (length != null && length >= 0 && !noBody) {
      response.contentLength = length;
    }
    if (message.end || head || noBody) {
      forget();
      unawaited(response.close().catchError((Object _) => response));
      return;
    }
    final inlet = _answer = ToolBytesIn(
      onConsumed: (total) => link.acks.consumed(id, total),
    );
    unawaited(
      response
          .addStream(inlet.stream)
          .then((_) => response.close())
          .catchError((Object _) => response),
    );
  }

  @override
  void onData(ToolData message) {
    final inlet = _answer;
    if (done || inlet == null) return;
    if (!inlet.add(message.data, end: message.end)) {
      abort();
      return;
    }
    if (message.end) forget();
  }

  @override
  void onWsMessage(ToolWsMessage message) => abort();

  @override
  void onAck(int total) {
    if (_body?.onAck(total) == false) abort();
  }

  @override
  void onEnd(ToolEnd message) {
    if (done) return;
    forget();
    if (responded) {
      cut();
    } else {
      unawaited(session._answerEnd(request, served, message.code));
    }
  }

  @override
  void cut() {
    _body?.cancel();
    _answer?.fail(const SocketException('cut'));
    if (!responded) {
      unawaited(session._answer(request, HttpStatus.badGateway));
    }
  }
}

/// A WebSocket: upgraded once the tool's side is open (`tool.res 101`).
final class _WsStream extends _Stream {
  _WsStream(super.session, super.served, super.id, super.request);

  Socket? _socket;
  WebSocket? _ws;
  ToolWsOut? _out;
  ToolWsIn? _in;
  ToolBytesIn? _refusal;

  List<String> get _offered => [
    for (final value in request.headers['sec-websocket-protocol'] ?? const [])
      for (final p in value.split(','))
        if (p.trim().isNotEmpty) p.trim(),
  ];

  @override
  void start() {}

  @override
  void onResponse(ToolResponse message) {
    if (done || responded) return;
    responded = true;
    if (message.status != HttpStatus.switchingProtocols) {
      _refused(message);
      return;
    }
    final protocols = toolHeadValues(message.head, 'sec-websocket-protocol');
    final protocol = protocols.isEmpty ? null : protocols.first;
    final key = request.headers.value('sec-websocket-key');
    if (key == null || (protocol != null && !_offered.contains(protocol))) {
      abort();
      return;
    }
    unawaited(_upgrade(key, protocol));
  }

  Future<void> _upgrade(String key, String? protocol) async {
    final response = request.response
      ..statusCode = HttpStatus.switchingProtocols
      ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('sec-websocket-accept', webSocketAccept(key))
      ..contentLength = 0;
    if (protocol != null) {
      response.headers.set('sec-websocket-protocol', protocol);
    }
    final Socket socket;
    try {
      socket = await response.detachSocket();
    } on Object {
      abort();
      return;
    }
    if (done) {
      socket.destroy();
      return;
    }
    _socket = socket;
    final ws = _ws = WebSocket.fromUpgradedSocket(
      socket,
      protocol: protocol,
      serverSide: true,
    );
    _in = ToolWsIn(
      write: (message) => ws.addStream(Stream.value(message)),
      onConsumed: (total) => link.acks.consumed(id, total),
      maxMessage: session.maxWsMessage,
    );
    _out = ToolWsOut(
      id: id,
      source: ws,
      window: window,
      pacer: const ToolUnpaced(),
      send: link.enqueue,
      maxMessage: session.maxWsMessage,
      onTooBig: () => _closeBoth(WebSocketStatus.messageTooBig),
      onDone: () {
        if (done) return;
        link.enqueue(
          ToolEnd(id: id, wsCode: ws.closeCode, wsReason: ws.closeReason),
        );
        forget();
        _socket?.destroy();
      },
    )..start();
  }

  /// The tool would not upgrade: the webview gets its answer as HTTP.
  void _refused(ToolResponse message) {
    final response = request.response..statusCode = message.status;
    for (var i = 0; i + 1 < message.head.length; i += 2) {
      final name = message.head[i];
      final value = message.head[i + 1];
      if (kToolHopByHop.contains(name) ||
          name == 'content-length' ||
          !isWritableHeaderValue(value)) {
        continue;
      }
      try {
        response.headers.add(name, value);
      } on FormatException {
        // left out
      }
    }
    if (message.end) {
      forget();
      unawaited(response.close().catchError((Object _) => response));
      return;
    }
    final inlet = _refusal = ToolBytesIn(
      onConsumed: (total) => link.acks.consumed(id, total),
    );
    unawaited(
      response
          .addStream(inlet.stream)
          .then((_) => response.close())
          .catchError((Object _) => response),
    );
  }

  /// A message over the limit: both sides close with [code].
  void _closeBoth(int code) {
    if (done) return;
    link.enqueue(ToolEnd(id: id, wsCode: code));
    forget();
    _out?.discard();
    _closeWebview(code, null);
  }

  void _closeWebview(int? code, String? reason) {
    final ws = _ws;
    if (ws == null) return;
    final valid = code != null && _sendable(code);
    unawaited(
      (_in?.idle ?? Future<void>.value())
          .timeout(const Duration(seconds: 5))
          .then((_) => valid ? ws.close(code, reason) : ws.close())
          .catchError((Object _) => _socket?.destroy()),
    );
  }

  static bool _sendable(int code) =>
      (code >= 1000 && code <= 1003) ||
      (code >= 1007 && code <= 1011) ||
      (code >= 3000 && code <= 4999);

  @override
  void onData(ToolData message) {
    final inlet = _refusal;
    if (done || inlet == null) return;
    if (!inlet.add(message.data, end: message.end)) {
      abort();
      return;
    }
    if (message.end) forget();
  }

  @override
  void onWsMessage(ToolWsMessage message) {
    final input = _in;
    if (done || input == null) return;
    if (!input.add(message)) _closeBoth(WebSocketStatus.messageTooBig);
  }

  @override
  void onAck(int total) {
    if (_out?.onAck(total) == false) abort();
  }

  @override
  void onEnd(ToolEnd message) {
    if (done) return;
    forget();
    if (!responded) {
      unawaited(session._answerEnd(request, served, message.code));
      return;
    }
    if (_ws == null) {
      _refusal?.fail(const SocketException('cut'));
      return;
    }
    _out?.discard();
    // The tool closed (its code), or the stream failed (going away).
    _closeWebview(
      message.code == null ? message.wsCode : WebSocketStatus.goingAway,
      message.code == null ? message.wsReason : null,
    );
  }

  @override
  void cut() {
    _out?.cancel();
    _refusal?.fail(const SocketException('cut'));
    final ws = _ws;
    if (ws != null) {
      _closeWebview(WebSocketStatus.goingAway, null);
    } else if (!responded) {
      unawaited(session._answer(request, HttpStatus.badGateway));
    }
  }
}
````

In `packages/shellx_client/lib/shellx_client.dart`, after `export 'src/machine_tools.dart';` add:

````dart
export 'src/tool_session.dart';
````

- [ ] **Step 6: Run the tests to verify they pass**

````bash
cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart format lib/src/tool_session.dart lib/shellx_client.dart test/support/test_tool.dart test/support/tool_pipe.dart test/tool_session_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; all tests pass (166 → 183).

- [ ] **Step 7: Commit**

````bash
git add packages/shellx_client/lib/src/tool_session.dart packages/shellx_client/lib/shellx_client.dart packages/shellx_client/pubspec.yaml packages/shellx_client/test/support/test_tool.dart packages/shellx_client/test/support/tool_pipe.dart packages/shellx_client/test/tool_session_test.dart
git commit -m "feat(v2-tools): the phone's loopback server for an open tool — loopback only, a one-time entry and a gate cookie, HTTP and WebSockets through the tunnel, its life with the app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 10: End to end — both sides in one process, and over the real relay

The V2-2 pattern (R20): a real agent with a `ToolProxy` and a real phone, in one test process.
- **In-process (always runs):** over the in-memory relay and the real encrypted channel, in real time.
  - First test: list → open → the page through the tunnel → a WebSocket echo → the tool turned off on the computer: the page says so within a second, the WebSocket closes, nothing is served any more.
  - Second test: 8 MB whole while a terminal still answers; no frame over 64 KiB; the computer well under the relay's 500 frames a second (RF 1, RF 2, criterion 7).
- **Real relay (`shellx_e2e`, runs when `SHELLX_E2E_RELAY` is set, like every relay test there):** the same flow plus 50 MB checked byte by byte. There the relay's frame budget (500 a second per device) and its frame size are real; they do not depend on `RATE_LIMITS_ENABLED`, which only turns off the account limits.

**Files:**
- Create: `packages/shellx_client/test/tools_e2e_test.dart`
- Create: `packages/shellx_e2e/test/tools_e2e_test.dart`
- Modify: `packages/shellx_e2e/test/support/e2e_world.dart`

**Interfaces:**
- Consumes:
  - Task 4: `SessionRouter(tools:)`;
  - Task 5: `ToolProxy(connect:)`, `ToolProxy.serve`, `ToolCatalog`;
  - Task 8: `MachineClient.tools` (`supported`, `watch`, `listing`);
  - Task 9: `ToolSession`, `ToolPhase`, `ToolLoad`, and the test support `TestTool`, `catalogOf`, `Webview`, `ipv6Only`, `until`;
  - existing test support: `FakeRelay.onData`, `FakePtyFactory`, `TestKeys`, `TabRecorder` (`shellx_client`); `E2eWorld`, `TabText`, `waitUntil` (`shellx_e2e`).
- Produces: `E2eWorld.create(Uri baseUri, {ShellResolver? shell, Map<String, String>? shellEnvironment, ShellIntegration? shellIntegration, AgentNotifications Function(ShellxApi agentApi)? notifications, ToolEndpoint? tools})`.

- [ ] **Step 1: Write the in-process end to end**

`packages/shellx_client/test/tools_e2e_test.dart`:

````dart
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/fake_pty.dart';
import 'support/fake_relay.dart';
import 'support/harness.dart'
    show TestKeys, TabRecorder, agentId, phoneId, phonePairingId, userId;
import 'support/test_tool.dart';
import 'support/tool_pipe.dart' show Webview, ipv6Only, until;

const _id = 'k3f9za7q1m';

/// A real agent with a tool proxy and a real phone over the fake relay and
/// the real encrypted channel, in real time; the tool listens on [::1] so the
/// phone (same machine) can serve its port on 127.0.0.1.
final class _World {
  _World._();

  final relay = FakeRelay();
  late final ToolProxy proxy;
  late final FakePtyFactory ptys;
  late final AgentService agent;
  late final ClientService phone;
  late final MachineClient machine;

  /// When each frame the agent sent reached the relay, and its size.
  final agentFrames = <(Duration, int)>[];
  final _clock = Stopwatch()..start();

  static Future<_World> start(TestKeys keys) async {
    final w = _World._();
    final agentDevice = w.relay.addDevice(
      id: agentId,
      userId: userId,
      kind: DeviceKind.agent,
    );
    final phoneDevice = w.relay.addDevice(
      id: phoneId,
      userId: userId,
      kind: DeviceKind.mobile,
    );
    w.relay.onData = (from, to, frame) {
      if (from == agentId) {
        w.agentFrames.add((w._clock.elapsed, frame.encode().length));
      }
      return frame;
    };
    final trusted = TrustedStore(InMemoryKeyValueStore());
    await trusted.add(
      TrustedDevice(
        mobileId: phoneId,
        publicKey: keys.phone.publicKey,
        name: 'Test Phone',
        pairedAt: DateTime.utc(2026),
        pairingId: phonePairingId,
      ),
    );
    w.relay.pairings[(agentId, phoneId)] = phonePairingId;
    w.ptys = FakePtyFactory();
    final ids = sessionIdAllocator(Random(7));
    w.proxy = ToolProxy(connect: ipv6Only);
    final router = SessionRouter(
      shells: SessionManager(
        ptyFactory: w.ptys,
        shellResolver: const FixedShellResolver(),
        homeDirectory: '/Users/test',
        baseEnvironment: const {},
        nextId: ids,
      ),
      desktop: DesktopSessionManager(nextId: ids),
      desktopSharing: () => true,
      tools: w.proxy,
    );
    w.agent = AgentService(
      relay: RelayConnection(
        wsUri: w.relay.wsUri,
        token: () => agentDevice.token,
        connector: w.relay.connector,
      ),
      api: ShellxApi(baseUri: w.relay.baseUri, httpClient: w.relay.httpClient)
        ..token = agentDevice.token,
      deviceId: agentId,
      identity: keys.agent,
      trusted: trusted,
      sessions: router,
      pairing: PairingCodeManager(),
      appVersion: '1.0.0',
    );
    await w.agent.start();
    final pins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
    await pins.add(
      PinnedMachine(
        agentId: agentId,
        publicKey: keys.agent.publicKey,
        pairedAt: DateTime.utc(2026),
      ),
    );
    w.phone = ClientService(
      relay: RelayConnection(
        wsUri: w.relay.wsUri,
        token: () => phoneDevice.token,
        connector: w.relay.connector,
      ),
      api: ShellxApi(baseUri: w.relay.baseUri, httpClient: w.relay.httpClient)
        ..token = phoneDevice.token,
      deviceId: phoneId,
      userId: userId,
      identity: keys.phone,
      pinned: pins,
      appVersion: '1.0.0',
      deviceName: 'Test Phone',
      platform: DevicePlatform.ios,
    );
    await w.phone.start();
    await until(() => w.phone.isOnline(agentId));
    w.machine = w.phone.machine(agentId);
    await w.machine.connect();
    return w;
  }

  Future<void> stop() async {
    proxy.close();
    await phone.stop();
    await agent.stop();
  }
}

/// V2-4 §8, end to end (the V2-2 pattern: both sides in one test, over the
/// fake relay and the real encrypted channel).
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('list → open → page → WebSocket echo → turned off', () async {
    final tool = await TestTool.start(address: InternetAddress.loopbackIPv6);
    final w = await _World.start(keys);
    final webview = Webview();
    addTearDown(() async {
      webview.close();
      await w.stop();
      await tool.close();
    });
    w.proxy.serve(catalogOf([tool.entry(host: '[::1]')]));

    // The phone sees the flag, then the list.
    await w.machine.listSessions(includeDesktop: true);
    expect(w.machine.tools.supported, isTrue);
    await w.machine.tools.watch();
    await until(() => w.machine.tools.listing?.tools.isNotEmpty ?? false);
    final info = w.machine.tools.listing!.tools.single;
    expect(
      (info.name, info.ws, info.port),
      ('Bảng việc', 'shop-web', tool.port),
    );

    // Open: the page through the tunnel.
    final session = ToolSession(
      tool: info.id,
      port: info.port,
      path: info.path,
      link: w.machine.tools,
    );
    final events = <ToolPageEvent>[];
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    final page = await webview.enter(events.whereType<ToolLoad>().single.url);
    expect(page.status, 200);
    expect(page.text, '<h1>/</h1>');

    // A WebSocket echo.
    final ws = await webview.socket(
      Uri.parse('ws://localhost:${session.servedPort}/ws'),
      protocols: ['vite-hmr'],
      origin: 'http://localhost:${session.servedPort}',
    );
    final got = <Object?>[];
    ws.listen(got.add);
    ws.add('xin chào');
    await until(() => got.isNotEmpty);
    expect(got.single, 'xin chào');

    // Turned off on the computer: the page says so within a second and the
    // WebSocket is gone; nothing reaches the tool any more.
    final clock = Stopwatch()..start();
    w.proxy.serve(catalogOf([], off: [_id]));
    await until(() => session.phase == ToolPhase.disabled);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    await ws.done.timeout(const Duration(seconds: 5));
    final hits = tool.hits.length;
    // Nothing is served on the phone any more.
    await expectLater(
      webview.request(Uri.parse('http://localhost:${tool.port}/')),
      throwsA(isA<SocketException>()),
    );
    expect(tool.hits.length, hits);
    await session.close();
  });

  test('8 MB through the tunnel: whole, no frame over 64 KiB, the computer '
      'well under the relay\'s 500 frames a second, and a terminal still '
      'answers (RF 1, RF 2, criterion 7)', () async {
    const size = 8 * 1000 * 1000;
    final body = Uint8List.fromList(
      List.generate(size, (i) => (i * 131 + (i >> 9)) & 0xFF),
    );
    final tool = await TestTool.start(
      address: InternetAddress.loopbackIPv6,
      routes: {
        '/big': (request) async {
          request.response.contentLength = size;
          for (var at = 0; at < size; at += 65536) {
            request.response.add(
              Uint8List.sublistView(body, at, min(at + 65536, size)),
            );
            await request.response.flush();
          }
          await request.response.close();
        },
      },
    );
    final w = await _World.start(keys);
    final webview = Webview();
    addTearDown(() async {
      webview.close();
      await w.stop();
      await tool.close();
    });
    w.proxy.serve(catalogOf([tool.entry(host: '[::1]')]));
    final tab = await w.machine.openSession(cols: 80, rows: 24);
    final terminal = TabRecorder(tab);
    final session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: w.machine.tools,
    );
    final events = <ToolPageEvent>[];
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    await webview.enter(events.whereType<ToolLoad>().single.url);

    final start = w.agentFrames.length;
    final downloading = webview.request(
      Uri.parse('http://localhost:${session.servedPort}/big'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    w.ptys.ptys.last.emit('still here\r\n');
    final page = await downloading;
    expect(page.status, 200);
    expect(page.body, body);
    await until(() => terminal.text.contains('still here'));

    final frames = w.agentFrames.skip(start).toList();
    expect(frames.every((f) => f.$2 <= kMaxFrameBytes), isTrue);
    for (final (t, _) in frames) {
      final inSecond = frames
          .where((f) => f.$1 >= t && f.$1 < t + const Duration(seconds: 1))
          .length;
      expect(inSecond, lessThan(250), reason: 'the relay closes at 500');
    }
    await session.close();
  });
}
````

- [ ] **Step 2: Run it**

Run: `cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart test test/tools_e2e_test.dart`
Expected: 2 tests pass in a few seconds (Tasks 4–9 made both sides). A failure here is an integration bug between those tasks: find it with superpowers:systematic-debugging, fix it in the file that owns it with a unit test next to that file's tests, then run this again.

- [ ] **Step 3: Write the real-relay test**

`packages/shellx_e2e/test/tools_e2e_test.dart`:

````dart
@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

const _size = 50 * 1000 * 1000;
int _byte(int i) => (i * 131 + (i >> 9)) & 0xFF;

/// The tool on [::1] (the phone, on this same machine, serves its port on
/// 127.0.0.1): a page, 50 MB at `/big`, a WebSocket echo at `/ws`.
Future<HttpServer> _tool() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
  server.listen((request) async {
    final response = request.response;
    switch (request.uri.path) {
      case '/big':
        response.contentLength = _size;
        final chunk = Uint8List(65536);
        for (var at = 0; at < _size; at += chunk.length) {
          final n = _size - at < chunk.length ? _size - at : chunk.length;
          for (var i = 0; i < n; i++) {
            chunk[i] = _byte(at + i);
          }
          response.add(Uint8List.fromList(chunk.sublist(0, n)));
          await response.flush();
        }
        await response.close();
      case '/ws':
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen(ws.add);
      default:
        response.write('<h1>tool</h1>');
        await response.close();
    }
  });
  return server;
}

/// V2-4 §8 and success criterion 7 over a real relay (run with
/// `SHELLX_E2E_RELAY=http://127.0.0.1:8787` while `npm run dev` runs in
/// `relay/`): the relay's 500 frames a second and its frame size are real
/// here.
void main() {
  test('50 MB through the tunnel: whole, the channel and a terminal stay; '
      'a WebSocket echoes; turned off, the page says so', () async {
    final tool = await _tool();
    final proxy = ToolProxy(
      connect: (port) => Socket.connect(InternetAddress.loopbackIPv6, port),
    );
    final world = await E2eWorld.create(Uri.parse(relayUrl!), tools: proxy);
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, _, _) async => ConnectionTask.fromSocket(
        Socket.connect(InternetAddress.loopbackIPv4, uri.port),
        () {},
      );
    addTearDown(() async {
      client.close(force: true);
      proxy.close();
      await world.dispose();
      await tool.close(force: true);
    });
    proxy.serve(
      ToolCatalog.fromServeBody(
        ToolCatalog.serveBody([
          {
            'id': 'k3f9za7q1m',
            'name': 'Bảng việc',
            'ws': 'shop-web',
            'group': 'ws:a',
            'url': 'http://[::1]:${tool.port}/',
          },
        ]),
      ),
    );
    await world.pair(world.phone, registered: false);
    final machine = world.phone.service.machine(world.agentId);
    await machine.connect();
    await machine.listSessions(includeDesktop: true);
    expect(machine.tools.supported, isTrue);
    final tab = await machine.openSession(cols: 80, rows: 24);
    final output = TabText(tab);

    final session = ToolSession(
      tool: 'k3f9za7q1m',
      port: tool.port,
      path: '/',
      link: machine.tools,
    );
    final loads = <Uri>[];
    session.events.listen((e) {
      if (e is ToolLoad) loads.add(e.url);
    });
    session.start();
    await waitUntil(() => loads.isNotEmpty, reason: 'the tool did not open');

    // The entry URL: its cookie is the gate.
    final entering = await client.getUrl(loads.single);
    entering.followRedirects = false;
    final enter = await entering.close();
    expect(enter.statusCode, 303);
    final cookie = enter.headers['set-cookie']!.single.split(';').first;
    await enter.drain<void>();
    Future<HttpClientResponse> get(String path) async {
      final request = await client.getUrl(
        Uri.parse('http://localhost:${session.servedPort}$path'),
      );
      request.headers.set('cookie', cookie);
      return request.close();
    }

    // 50 MB, checked byte by byte as it streams, while a terminal echoes.
    final big = await get('/big');
    expect(big.statusCode, 200);
    var at = 0;
    var wrong = 0;
    var echoed = false;
    await for (final chunk in big) {
      for (final b in chunk) {
        if (b != _byte(at++)) wrong++;
      }
      if (!echoed && at > _size ~/ 2) {
        echoed = true;
        machine.input(tab.id, Uint8List.fromList(utf8.encode('echo half\n')));
      }
    }
    expect(at, _size);
    expect(wrong, 0);
    await waitUntil(() => output.text.contains('half'), reason: 'terminal');
    expect(machine.state, isA<MachineReady>());

    // A WebSocket echo.
    final ws = await WebSocket.connect(
      'ws://localhost:${session.servedPort}/ws',
      headers: {'cookie': cookie},
      customClient: client,
    );
    final got = <Object?>[];
    ws.listen(got.add);
    ws.add('xin chào');
    await waitUntil(() => got.isNotEmpty, reason: 'no echo');
    expect(got.single, 'xin chào');

    // Turned off on the computer: the page says so within a second.
    final clock = Stopwatch()..start();
    proxy.serve(ToolCatalog([], off: {'k3f9za7q1m'}));
    await waitUntil(
      () => session.phase == ToolPhase.disabled,
      reason: 'not disabled',
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    await session.close();
  }, skip: relayUrl == null ? 'SHELLX_E2E_RELAY is not set' : null);
}
````

- [ ] **Step 4: Run it to verify it fails**

Run: `cd packages/shellx_e2e && ~/fvm/versions/3.41.4/bin/dart test test/tools_e2e_test.dart`
Expected: FAIL to compile — `E2eWorld.create` has no parameter `tools`.

- [ ] **Step 5: Let the world's agent serve tools**

In `packages/shellx_e2e/test/support/e2e_world.dart`:

1. In `static Future<E2eWorld> create(...)`, after the parameter `AgentNotifications Function(ShellxApi agentApi)? notifications,` add `ToolEndpoint? tools,`, and in its call `await world._build(...)` after `notifications: notifications,` add `tools: tools,`.
2. In `Future<void> _build(...)`, after the parameter `AgentNotifications Function(ShellxApi agentApi)? notifications,` add `ToolEndpoint? tools,`.
3. In `_build`, in `router = SessionRouter(...)`, after `desktopSharing: () => sharing.enabled,` add `tools: tools,`.

- [ ] **Step 6: Run the package, then the real relay**

````bash
cd packages/shellx_e2e && ~/fvm/versions/3.41.4/bin/dart format test/tools_e2e_test.dart test/support/e2e_world.dart && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test
````

Expected: no issue; 16 passed, 10 skipped (the new test is skipped: `SHELLX_E2E_RELAY is not set`).

Then against a local relay, on a port of its own (other agents may use 8787) and a throw-away database in the git-ignored `relay/.data/`. Start it in the background (`run_in_background`), keeping its PID:

````bash
cd relay && npm ci && mkdir -p .data && (PORT=8799 DB_PATH=.data/v24-e2e.db npm run dev > .data/v24-relay.log 2>&1 & echo $! > .data/v24-relay.pid)
````

Wait until `curl -s http://127.0.0.1:8799/v1/version` answers, then:

````bash
cd packages/shellx_e2e && SHELLX_E2E_RELAY=http://127.0.0.1:8799 ~/fvm/versions/3.41.4/bin/dart test test/tools_e2e_test.dart
````

Expected: 1 test passes (50 MB in about 17 s); `grep -c ws_rate_limited relay/.data/v24-relay.log` prints `0`. Note the time and the result for the ledger (Task 16).

Stop the relay by its PIDs only (npm, its shell, node) — never `pkill`/`killall`:

````bash
cd relay && p=$(cat .data/v24-relay.pid) && kids=$(pgrep -P "$p") && grand=$(for k in $kids; do pgrep -P "$k"; done) && kill $grand $kids "$p"; rm -f .data/v24-e2e.db* .data/v24-relay.log .data/v24-relay.pid
````

- [ ] **Step 7: Commit**

````bash
git add packages/shellx_client/test/tools_e2e_test.dart packages/shellx_e2e/test/tools_e2e_test.dart packages/shellx_e2e/test/support/e2e_world.dart
git commit -m "test(v2-tools): end to end — list, open, a page and a WebSocket through the tunnel, turned off within a second; 8 MB in process and 50 MB over the real relay, whole and under its frame budget

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 11: The desktop's agent side: the slot in every runtime, the proxy in the background service

E5, like V2-2's `ai` slot.
- **`SessionCore.tools`:** a `ToolEndpointSlot` that lives for the process; every `CoreAgentRuntime`'s router sends `tool.*` to it, so a revoke, a stop or a new runtime never loses the target.
- **The background service** (`daemon_main.dart`) holds the relay, so it hosts the proxy:
  - `installDaemonTools` makes one `ToolProxy`, sets it as the slot's target and as `MuxServer.tools` (it takes the window's `tool.serve` lists, Task 7);
  - `hello.caps` says `tools`, so a window knows it may push lists (Task 15);
  - on shutdown the proxy closes (its streams end `desktop_closed`).
- **The in-process window:** its slot stays empty until Task 15 (R2), so it advertises no tools before then.

**Files:**
- Modify: `apps/desktop/lib/src/agent/session_core.dart`, `apps/desktop/lib/src/agent/agent_runtime.dart`, `apps/desktop/lib/daemon_main.dart`
- Create: `apps/desktop/lib/src/agent/daemon_tools.dart`
- Test: `apps/desktop/test/agent/tool_slot_test.dart`

**Interfaces:**
- Consumes: Task 4 `ToolEndpointSlot`, `SessionRouter(tools:)`; Task 5 `ToolProxy`, `ToolCatalog`; Task 7 `MuxServer.tools`, `MuxType.toolServe`.
- Produces:
  - `final ToolEndpointSlot SessionCore.tools`;
  - `ToolProxy installDaemonTools(MuxServer server, SessionCore core)`;
  - `const kDaemonCaps = ['agent', 'cli', 'tools']` (Task 15 checks `tools` in the service's `hello.caps`).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/agent/tool_slot_test.dart`:

````dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/daemon_main.dart' show kDaemonCaps;
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/daemon_tools.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';

import '../mux/mux_test_support.dart';
import '../support/fake_pty.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// V2-4 E5, E6: every runtime's router sends `tool.*` to the process's slot;
/// the background service hosts the proxy and takes the window's list.
void main() {
  SessionCore core() => SessionCore(
    ptyFactory: FakePtyFactory(),
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
    api: ShellxApi(baseUri: Uri.parse('https://relay.test')),
  );

  test('no target: not serving (no tools flag), the phone hears '
      'unavailable', () {
    final c = core();
    final out = <OutboundMessage>[];
    c.tools.outbound.listen(out.add);
    expect(c.tools.serving, isFalse);
    c.tools.handle(_phone, const ToolList());
    expect((out.single.message as ToolListResult).available, isFalse);
  });

  test('every runtime built on the core uses its slot: a revoked phone and '
      'a stopped runtime reach the slot\'s target', () async {
    final c = core();
    final target = _Endpoint();
    c.tools.target = target;
    for (var run = 1; run <= 2; run++) {
      final runtime = await _runtimeOn(c);
      await runtime.revoke(_phone);
      expect(target.gone, [_phone], reason: 'revoke, runtime $run');
      await runtime.stop();
      expect(target.allGone, 1, reason: 'stop, runtime $run');
      target
        ..gone.clear()
        ..allGone = 0;
    }
  });

  test('the background service: it says it has tools; its proxy serves the '
      'window\'s list and keeps it when the window goes', () async {
    expect(kDaemonCaps, contains('tools'));
    final c = core();
    final listener = TestListener();
    final server = MuxServer(
      sessions: c.sessions,
      secret: testSecret,
      self: const MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i'),
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    final proxy = installDaemonTools(server, c); // What daemon_main calls.
    addTearDown(proxy.close);
    expect(c.tools.serving, isTrue);
    final toPhone = <ToolMessage>[];
    c.tools.outbound.listen((o) => toPhone.add(o.message as ToolMessage));

    // No window has said anything yet: the list is unavailable.
    c.tools.handle(_phone, const ToolList());
    expect((toPhone.single as ToolListResult).available, isFalse);

    final (client, daemonSide) = MemoryMuxTransport.pair();
    listener.push(daemonSide);
    await clientHandshake(client, secret: testSecret, app: 't', role: 'ui');
    client.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': ToolCatalog.serveBody([
            {
              'id': 'k3f9za7q1m',
              'name': 'Bảng việc',
              'ws': 'shop-web',
              'group': 'ws:a',
              'url': 'http://localhost:5173/',
            },
          ]),
        },
      ),
    );
    await pumpEventQueue();
    final listed = toPhone.last as ToolListResult;
    expect(listed.available, isTrue);
    expect(utf8.decode(listed.body), contains('Bảng việc'));
    await client.close();
    await pumpEventQueue();
    expect(proxy.catalog?.tools.single.id, 'k3f9za7q1m');
  });
}

/// A runtime on [core] that never reaches a relay; nothing is started.
Future<CoreAgentRuntime> _runtimeOn(SessionCore core) async {
  final api = ShellxApi(baseUri: Uri.parse('https://relay.test'));
  return CoreAgentRuntime(
    RuntimeParams(
      credentials: const AgentCredentials(
        token: 'agent-token',
        deviceId: '22222222-2222-4222-8222-222222222222',
        userId: '11111111-1111-4111-8111-111111111111',
        email: 'phu@example.com',
      ),
      identity: await NoiseKeyPair.generate(),
      trusted: TrustedStore(InMemoryKeyValueStore()),
      api: api,
    ),
    core: core,
    relayBaseUri: Uri.parse('https://relay.test'),
    appVersion: '1.0.0',
    connector: (uri, headers) async =>
        throw const SocketException('offline in tests'),
  );
}

/// A [ToolEndpoint] that only records what the slot passes on.
final class _Endpoint implements ToolEndpoint {
  final gone = <String>[];
  var allGone = 0;

  @override
  Stream<OutboundMessage> get outbound => const Stream.empty();

  @override
  bool get serving => true;

  @override
  void handle(String mobileId, ToolMessage message) {}

  @override
  void phoneGone(String mobileId) => gone.add(mobileId);

  @override
  void allPhonesGone() => allGone++;
}
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/agent/tool_slot_test.dart`
Expected: FAIL to compile — `SessionCore.tools` and `daemon_tools.dart` do not exist.

- [ ] **Step 3: The slot in the core, used by every runtime**

In `apps/desktop/lib/src/agent/session_core.dart`, at the end of `SessionCore`, after `final ai = AiEndpointSlot();` add:

````dart

  /// V2-4 E5: where phones' `tool.*` messages go. Every runtime's router
  /// uses it; the process that holds the relay sets its target to its tool
  /// proxy (the window in-process, the background service otherwise). Until
  /// then it does not serve: phones see no Tool group.
  final tools = ToolEndpointSlot();
````

In `apps/desktop/lib/src/agent/agent_runtime.dart`, in the `SessionRouter(...)` that `CoreAgentRuntime` builds, after `ai: core.ai,` add `tools: core.tools,`.

- [ ] **Step 4: The proxy in the background service**

`apps/desktop/lib/src/agent/daemon_tools.dart`:

````dart
import 'package:shellx_agent/shellx_agent.dart';

import 'session_core.dart';

/// V2-4 E5, background service: the service holds the relay, so it hosts
/// the tool proxy. One proxy is the target of [core]'s slot (what every
/// runtime's router sends) and takes the window's lists (`tool.serve`); the
/// last list stays when the window quits, like the service's shells.
///
/// Called once, before the server listens and the agent starts.
ToolProxy installDaemonTools(MuxServer server, SessionCore core) {
  final proxy = ToolProxy();
  server.tools = proxy;
  core.tools.target = proxy;
  return proxy;
}
````

In `apps/desktop/lib/daemon_main.dart`:

1. After `import 'src/agent/daemon_ai.dart';` add `import 'src/agent/daemon_tools.dart';`.
2. Replace:

````dart
/// What the daemon tells a client about itself (`hello.caps`, additive).
const kDaemonCaps = ['agent', 'cli'];
````

with:

````dart
/// What the daemon tells a client about itself (`hello.caps`, additive).
/// `tools` (V2-4 E5): it hosts the tool proxy and takes `tool.serve`.
const kDaemonCaps = ['agent', 'cli', 'tools'];
````

3. In `_serve`, after `installDaemonAi(server, core);` add:

````dart
  // V2-4 E5: tools are served here, from the window's last list.
  final tools = installDaemonTools(server, core);
````

4. In `_serve`, replace `shutdown: () => _shutdown(container, cli, side),` with `shutdown: () => _shutdown(container, cli, side, tools),`.
5. Give `_shutdown` a fourth parameter `ToolProxy tools,` (after `AgentSide side,`) and, as its last statement (after the `if (remote != null) { … }` block), add:

````dart
  tools.close(); // its streams and its connections to the tools
````

- [ ] **Step 5: Run the tests to verify they pass**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/agent/session_core.dart lib/src/agent/agent_runtime.dart lib/src/agent/daemon_tools.dart lib/daemon_main.dart test/agent/tool_slot_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: no issue; all tests pass (3574 → 3577, 10 skipped).

- [ ] **Step 6: Commit**

````bash
git add apps/desktop/lib/src/agent/session_core.dart apps/desktop/lib/src/agent/agent_runtime.dart apps/desktop/lib/src/agent/daemon_tools.dart apps/desktop/lib/daemon_main.dart apps/desktop/test/agent/tool_slot_test.dart
git commit -m "feat(v2-tools): the tool slot in every desktop runtime; the background service hosts the proxy and says tools in hello.caps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 12: Mobile foundation: the web view packages, local cleartext only, the strings, the backend seam

What the tool page (Task 13) and the picker (Task 14) build on.
- **Packages (R15):** `webview_flutter` 4.14.1, `webview_flutter_android` 4.12.0, `webview_flutter_wkwebview` 3.25.1, pinned exactly (newer ones need Dart 3.12).
- **E14, iOS:** `NSAppTransportSecurity › NSAllowsLocalNetworking` (never `NSAllowsArbitraryLoads`), and `http` among the queried schemes so a page's link to another http site can open in the browser (E12).
- **E14, Android:**
  - `networkSecurityConfig`: cleartext is off everywhere except `localhost` and `127.0.0.1` (never `usesCleartextTraffic`); `[::1]` is not needed: the page always loads `localhost` (R16);
  - an `http` VIEW query for the browser.
- **Strings (§6, R14):** in English and Vietnamese.
- **The backend seam:**
  - `MachineSession.tools` (`ToolMachine`: flag, list, watch, a `ToolPageSession` per open page) over `MachineTools`/`ToolSession`;
  - its scriptable fakes for widget tests.

**Files:**
- Modify: `apps/mobile/pubspec.yaml`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/ios/Runner/Info.plist`, `apps/mobile/android/app/src/main/AndroidManifest.xml`
- Create: `apps/mobile/android/app/src/main/res/xml/network_security_config.xml`
- Modify: `apps/mobile/lib/l10n/intl_en.arb`, `apps/mobile/lib/l10n/intl_vi.arb`, generated `apps/mobile/lib/shared/src/l10n.dart`, `apps/mobile/lib/shared/src/intl/messages_en.dart`, `apps/mobile/lib/shared/src/intl/messages_vi.dart`
- Modify: `apps/mobile/lib/core/backend/backend.dart`, `apps/mobile/lib/core/backend/client_backend.dart`
- Test: `apps/mobile/test/platform_config_test.dart`, `apps/mobile/test/support/fakes.dart`

**Interfaces:**
- Consumes: Task 8 `MachineTools`, `ToolInfo`, `ToolListing`; Task 9 `ToolSession`, `ToolPhase`, `ToolPageEvent`, `ToolLoad`, `ToolHostTexts`.
- Produces:
  - `abstract interface class ToolPageSession`:
    - state: `ToolPhase get phase; Stream<void> get changes; Stream<ToolPageEvent> get events; int get port; int? get servedPort; int? get alias; Set<String> get origins;`
    - E20: `int get requests; void resetRequests();`
    - life: `void start(); void home(); Future<void> pause(); void resume(); Future<void> close();`
  - `abstract interface class ToolMachine { bool? get supported; ToolListing? get listing; Stream<ToolListing> get listings; Future<void> watch(); void unwatch(); ToolPageSession page(ToolInfo tool, ToolHostTexts texts); }`;
  - `ToolMachine get MachineSession.tools`;
  - fakes:
    - `FakeToolMachine`: `supportedValue`, `listingValue`, `emitListing`, `watchCalls`, `unwatchCalls`, `watching`, `pages`, `texts`;
    - `FakeToolPage`: `tool`, `phaseValue`, `servedPortValue`, `requestsValue`, `setPhase`, `ready({int? port})`, `emit`, and counters `starts`, `homes`, `pauses`, `resumes`, `closes`, `resets`;
    - `FakeMachineSession.tools`;
  - `S` getters (generated):
    - `pickerTools`, `toolRowSub(workspace, port)`, `toolsEmpty`, `toolViaComputer(port)`;
    - `toolLoadingTunnel`, `toolSlow(count)`, `toolRefusedPhone(port)`, `toolDisabled`, `toolGone`, `toolNeedsDesktop`;
    - `toolOtherPort(alias, port)`, `toolSiblingOff(port)`, `toolOpenExternal(host)`, `toolNoDownloads`;
    - `toolHome`, `toolClearDataPhone`, `toolReload`, `toolReconnecting`, `toolResponseTooLarge`, `toolDialogTitle(name)`, `toolClearDataPhoneConfirm`.

- [ ] **Step 1: Write the failing tests**

In `apps/mobile/test/platform_config_test.dart`:

1. Before the test `'microphone and speech recognition prompts: Info.plist and both languages'` add:

````dart
    test('V2-4 E14: ATS allows the local network (a tool page on localhost); http links can open', () {
      final plist = readFile('ios/Runner/Info.plist');
      expect(
        plist,
        contains('<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>'),
      );
      expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
      expect(plist, contains('<string>http</string>'));
    });
````

2. Before the test `'voice input: RECORD_AUDIO and the speech recognition service query'` add:

````dart
    test('V2-4 E14: cleartext only to localhost and 127.0.0.1, through the network security config', () {
      final manifest = readFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
      expect(manifest, isNot(contains('usesCleartextTraffic')));
      final config = readFile('android/app/src/main/res/xml/network_security_config.xml');
      expect(config, contains('<base-config cleartextTrafficPermitted="false" />'));
      expect(config, contains('<domain-config cleartextTrafficPermitted="true">'));
      final domains = RegExp(r'<domain[^>]*>([^<]+)</domain>').allMatches(config).map((m) => m.group(1)).toList();
      expect(domains, ['localhost', '127.0.0.1']);
      expect(manifest, contains('<data android:scheme="http"/>'));
    });
````

3. In the test `'the runtime packages the app works around are pinned exactly (pubspec.lock is not committed)'`, after `expect(pubspec, contains('\n  signals_flutter: 6.3.1\n'));` add:

````dart
    // V2-4 E12: the newest webview packages on Flutter 3.41.4.
    expect(pubspec, contains('\n  webview_flutter: 4.14.1\n'));
    expect(pubspec, contains('\n  webview_flutter_android: 4.12.0\n'));
    expect(pubspec, contains('\n  webview_flutter_wkwebview: 3.25.1\n'));
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform_config_test.dart`
Expected: 3 failures — no `NSAppTransportSecurity`, no `networkSecurityConfig`, no `webview_flutter` pin.

- [ ] **Step 3: Pin the web view packages**

In `apps/mobile/pubspec.yaml`, under `dependencies:`, after `url_launcher: ^6.3.2` add:

````yaml
  # V2-4 E12: the tool page. Pinned exactly: the newest that run on Flutter 3.41.4 / Dart 3.11
  # (webview_flutter_android 4.12.1+ and webview_flutter_wkwebview 3.26+ need Dart 3.12). Bump the
  # three together with Flutter. The platform packages are direct dependencies for their own
  # settings (file chooser, geolocation off).
  webview_flutter: 4.14.1
  webview_flutter_android: 4.12.0
  webview_flutter_wkwebview: 3.25.1
````

Run at the repo root: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get`. If V2-3 already added `webview_flutter` 4.14.1 and `webview_flutter_wkwebview` 3.25.1 to the desktop, the workspace resolves one version of each; a different pin there is a conflict to settle in the ledger, never by loosening these.

The iOS pod lock is committed: let `pod install` add the new plugin, and keep the repo's CocoaPods version line (about 10 s; nothing is built or launched):

````bash
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build ios --config-only --no-codesign && orig=$(git show HEAD:apps/mobile/ios/Podfile.lock | grep '^COCOAPODS:') && sed -i '' "s/^COCOAPODS: .*/$orig/" ios/Podfile.lock && git diff ios/Podfile.lock
````

Expected: the diff adds only `webview_flutter_wkwebview` (under `PODS`, `DEPENDENCIES`, `EXTERNAL SOURCES` and `SPEC CHECKSUMS`).

- [ ] **Step 4: iOS: local networking only, and http links**

In `apps/mobile/ios/Runner/Info.plist`:

1. In `LSApplicationQueriesSchemes`, after `<string>https</string>` add `<string>http</string>` (same indentation: two tabs).
2. After

````xml
	<key>LSRequiresIPhoneOS</key>
	<true/>
````

add:

````xml
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
````

- [ ] **Step 5: Android: cleartext only to the phone's loopback**

`apps/mobile/android/app/src/main/res/xml/network_security_config.xml`:

````xml
<?xml version="1.0" encoding="utf-8"?>
<!-- V2-4 E14: a tool page is served on this phone's loopback (http://localhost:<port>); only there
     is cleartext allowed. Everything else keeps Android's default: HTTPS only. -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
````

In `apps/mobile/android/app/src/main/AndroidManifest.xml`:

1. Replace the first line of the comment above `<application` — `<!-- allowBackup=false: secure storage must not be restored onto another install` — with:

````xml
    <!-- networkSecurityConfig (V2-4 E14): cleartext only to this phone's own loopback, where a
         tool page is served; the relay, FCM and every link stay HTTPS-only.
         allowBackup=false: secure storage must not be restored onto another install
````

2. Replace `android:dataExtractionRules="@xml/data_extraction_rules">` with:

````xml
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:networkSecurityConfig="@xml/network_security_config">
````

3. In `<queries>`, after the `https` VIEW `<intent>` add:

````xml
        <!-- V2-4 E12: a tool page's link to another http site opens in the browser. -->
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="http"/>
        </intent>
````

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/platform_config_test.dart`
Expected: all pass.

- [ ] **Step 7: The strings**

In `apps/mobile/lib/l10n/intl_en.arb`, add a comma after the last entry (`"@aiPlan": …`, or the last key another plan added) and append before the closing `}`:

````json
  "pickerTools": "Tools",
  "toolRowSub": "{workspace} · localhost:{port}",
  "@toolRowSub": {"placeholders": {"workspace": {"type": "String"}, "port": {"type": "int"}}},
  "toolsEmpty": "No tools are on for phone yet. On the computer: the tool's bar › 📱 Phone.",
  "toolViaComputer": "localhost:{port} · via computer",
  "@toolViaComputer": {"placeholders": {"port": {"type": "int"}}},
  "toolLoadingTunnel": "Loading through the tunnel…",
  "toolSlow": "Loading through your computer… ({count} requests)",
  "@toolSlow": {"placeholders": {"count": {"type": "int"}}},
  "toolRefusedPhone": "Nothing is running at localhost:{port} on the computer.",
  "@toolRefusedPhone": {"placeholders": {"port": {"type": "int"}}},
  "toolDisabled": "This tool can no longer be opened on the phone.",
  "toolGone": "This tool was deleted on the computer.",
  "toolNeedsDesktop": "Open ShellX on the computer to use tools.",
  "toolOtherPort": "Opened on port {alias} because port {port} is busy on this phone. Links that name port {port} may not work.",
  "@toolOtherPort": {"placeholders": {"alias": {"type": "int"}, "port": {"type": "int"}}},
  "toolSiblingOff": "The tool on port {port} isn't on for phone.",
  "@toolSiblingOff": {"placeholders": {"port": {"type": "int"}}},
  "toolOpenExternal": "Open {host} in your browser?",
  "@toolOpenExternal": {"placeholders": {"host": {"type": "String"}}},
  "toolNoDownloads": "Downloads don't work on the phone yet.",
  "toolHome": "Start page",
  "toolClearDataPhone": "Clear tool data",
  "toolReload": "Reload",
  "toolReconnecting": "Reconnecting…",
  "toolResponseTooLarge": "The tool's response is too large.",
  "toolDialogTitle": "{name} says",
  "@toolDialogTitle": {"placeholders": {"name": {"type": "String"}}},
  "toolClearDataPhoneConfirm": "Sign every tool out and clear its cookies and storage?"
````

In `apps/mobile/lib/l10n/intl_vi.arb`, the same way (after `"aiPlan": …`):

````json
  "pickerTools": "Tool",
  "toolRowSub": "{workspace} · localhost:{port}",
  "toolsEmpty": "Chưa có tool nào bật cho điện thoại. Trên máy tính: thanh của tool › 📱 Điện thoại.",
  "toolViaComputer": "localhost:{port} · qua máy tính",
  "toolLoadingTunnel": "Đang tải qua đường hầm…",
  "toolSlow": "Đang tải qua máy tính… ({count} request)",
  "toolRefusedPhone": "Không có gì chạy ở localhost:{port} trên máy tính.",
  "toolDisabled": "Tool này không còn mở được trên điện thoại.",
  "toolGone": "Tool này đã bị xóa trên máy tính.",
  "toolNeedsDesktop": "Mở ShellX trên máy tính để dùng tool.",
  "toolOtherPort": "Đang mở ở cổng {alias} vì cổng {port} bận trên điện thoại. Link ghi rõ cổng {port} có thể không chạy.",
  "toolSiblingOff": "Tool ở cổng {port} chưa bật cho điện thoại.",
  "toolOpenExternal": "Mở {host} bằng trình duyệt?",
  "toolNoDownloads": "Tải tệp chưa làm được trên điện thoại.",
  "toolHome": "Về trang đầu",
  "toolClearDataPhone": "Xóa dữ liệu của tool",
  "toolReload": "Tải lại",
  "toolReconnecting": "Đang kết nối lại…",
  "toolResponseTooLarge": "Phản hồi của tool quá lớn.",
  "toolDialogTitle": "{name} nhắn",
  "toolClearDataPhoneConfirm": "Đăng xuất mọi tool và xóa cookie, bộ nhớ của chúng?"
````

Generate and format (from `apps/mobile`):

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart
````

- [ ] **Step 8: The backend seam and its fakes**

In `apps/mobile/lib/core/backend/backend.dart`:

1. In `abstract interface class MachineSession`, after `AiMachine get ai;` add:

````dart

  /// V2-4: the machine's personal web tools.
  ToolMachine get tools;
````

2. Before the doc comment of `ShellxBackend` (it starts with `/// Everything the signed-in UI needs from`) add:

````dart
/// App-side view of one open tool page ([ToolSession] in `shellx_client`, V2-4): while it is
/// started, the phone serves the tool on its own loopback (only to the page's web view: E11) and
/// carries every request to the computer. Never logs what it carries.
abstract interface class ToolPageSession {
  ToolPhase get phase;

  /// After every change of [phase].
  Stream<void> get changes;

  /// What the web view must do: load the entry URL, reload; what to tell the user.
  Stream<ToolPageEvent> get events;

  /// The tool's port on the computer.
  int get port;

  /// The port this phone serves it on (null while nothing is served); [alias] when it is not
  /// [port] (E3: the tool's port is taken on this phone).
  int? get servedPort;
  int? get alias;

  /// The origins this phone serves (`http://localhost:<port>`): the web view stays on them (E12).
  Set<String> get origins;

  /// Requests served since [resetRequests] (E20).
  int get requests;
  void resetRequests();

  /// Asks the computer and serves the tool.
  void start();

  /// "Về trang đầu".
  void home();

  /// The app went to the background (E13): nothing is served until [resume].
  Future<void> pause();
  void resume();

  /// The page was left: nothing is served, the computer is told.
  Future<void> close();
}

/// App-side view of a machine's tools ([MachineTools] in `shellx_client`, V2-4).
abstract interface class ToolMachine {
  /// From the computer's answer to a list of its sessions: null before the first one, false for a
  /// computer without tools for phones.
  bool? get supported;
  ToolListing? get listing;
  Stream<ToolListing> get listings;

  /// Keeps [listing] current (one switch, like [AiMachine.watch]).
  Future<void> watch();
  void unwatch();

  /// A page for [tool] that serves nothing until [ToolPageSession.start]; [texts] are the plain
  /// answers the phone's server gives itself, in the phone's language.
  ToolPageSession page(ToolInfo tool, ToolHostTexts texts);
}
````

In `apps/mobile/lib/core/backend/client_backend.dart`:

1. In `_MachineSessionAdapter`, after `late final AiMachine ai = _AiMachineAdapter(_client.ai);` add:

````dart

  @override
  late final ToolMachine tools = _ToolMachineAdapter(_client.tools);
````

2. At the end of the file add:

````dart
final class _ToolMachineAdapter implements ToolMachine {
  _ToolMachineAdapter(this._tools);

  final MachineTools _tools;

  @override
  bool? get supported => _tools.supported;

  @override
  ToolListing? get listing => _tools.listing;

  @override
  Stream<ToolListing> get listings => _tools.listings;

  @override
  Future<void> watch() => _tools.watch();

  @override
  void unwatch() => _tools.unwatch();

  @override
  ToolPageSession page(ToolInfo tool, ToolHostTexts texts) =>
      _ToolPageAdapter(ToolSession(tool: tool.id, port: tool.port, path: tool.path, link: _tools, texts: texts));
}

final class _ToolPageAdapter implements ToolPageSession {
  _ToolPageAdapter(this._session);

  final ToolSession _session;

  @override
  ToolPhase get phase => _session.phase;

  @override
  Stream<void> get changes => _session.changes;

  @override
  Stream<ToolPageEvent> get events => _session.events;

  @override
  int get port => _session.port;

  @override
  int? get servedPort => _session.servedPort;

  @override
  int? get alias => _session.alias;

  @override
  Set<String> get origins => _session.origins;

  @override
  int get requests => _session.requests;

  @override
  void resetRequests() => _session.resetRequests();

  @override
  void start() => _session.start();

  @override
  void home() => _session.home();

  @override
  Future<void> pause() => _session.pause();

  @override
  void resume() => _session.resume();

  @override
  Future<void> close() => _session.close();
}
````

In `apps/mobile/test/support/fakes.dart`:

1. In `FakeMachineSession`, after `final FakeAiMachine ai = FakeAiMachine();` add:

````dart

  /// V2-4: the machine's tools.
  @override
  final FakeToolMachine tools = FakeToolMachine();
````

2. Before `/// Scriptable [ShellxBackend].` add:

````dart
/// Scriptable [ToolMachine] (V2-4): the list as a test sets it, and the pages it made.
class FakeToolMachine implements ToolMachine {
  bool? supportedValue;
  ToolListing? listingValue;
  final StreamController<ToolListing> _listings = StreamController<ToolListing>.broadcast(sync: true);
  int watchCalls = 0;
  int unwatchCalls = 0;
  bool watching = false;

  /// Every page made, in order, and the texts each was given.
  final List<FakeToolPage> pages = [];
  final List<ToolHostTexts> texts = [];

  /// A list from the computer: it has tools.
  void emitListing(ToolListing listing) {
    supportedValue = true;
    listingValue = listing;
    _listings.add(listing);
  }

  @override
  bool? get supported => supportedValue;

  @override
  ToolListing? get listing => listingValue;

  @override
  Stream<ToolListing> get listings => _listings.stream;

  @override
  Future<void> watch() async {
    watchCalls++;
    watching = true;
  }

  @override
  void unwatch() {
    unwatchCalls++;
    watching = false;
  }

  @override
  ToolPageSession page(ToolInfo tool, ToolHostTexts texts) {
    this.texts.add(texts);
    final page = FakeToolPage(tool);
    pages.add(page);
    return page;
  }
}

/// Scriptable [ToolPageSession]: a test sets the phase and says what the page must do.
class FakeToolPage implements ToolPageSession {
  FakeToolPage(this.tool);

  final ToolInfo tool;
  ToolPhase phaseValue = ToolPhase.opening;
  int? servedPortValue;
  int requestsValue = 0;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  final StreamController<ToolPageEvent> _events = StreamController<ToolPageEvent>.broadcast(sync: true);
  int starts = 0;
  int homes = 0;
  int pauses = 0;
  int resumes = 0;
  int closes = 0;
  int resets = 0;

  void setPhase(ToolPhase phase) {
    phaseValue = phase;
    _changes.add(null);
  }

  /// Served on [port] ([tool]'s own by default) and told to load its entry URL.
  void ready({int? port}) {
    servedPortValue = port ?? tool.port;
    setPhase(ToolPhase.ready);
    _events.add(ToolLoad(Uri.parse('http://localhost:$servedPortValue/__shellx/enter?n=x&to=%2F')));
  }

  void emit(ToolPageEvent event) => _events.add(event);

  @override
  ToolPhase get phase => phaseValue;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<ToolPageEvent> get events => _events.stream;

  @override
  int get port => tool.port;

  @override
  int? get servedPort => servedPortValue;

  @override
  int? get alias {
    final served = servedPortValue;
    return served != null && served != tool.port ? served : null;
  }

  @override
  Set<String> get origins => {if (servedPortValue != null) 'http://localhost:$servedPortValue'};

  @override
  int get requests => requestsValue;

  @override
  void resetRequests() {
    resets++;
    requestsValue = 0;
  }

  @override
  void start() => starts++;

  @override
  void home() => homes++;

  @override
  Future<void> pause() async {
    pauses++;
    setPhase(ToolPhase.paused);
  }

  @override
  void resume() => resumes++;

  @override
  Future<void> close() async {
    closes++;
    phaseValue = ToolPhase.closed;
  }
}
````

- [ ] **Step 9: Run everything**

````bash
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/core/backend/backend.dart lib/core/backend/client_backend.dart test/support/fakes.dart test/platform_config_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: analyze reports only the pre-existing `unnecessary_import` info in `test/features/terminal/ime_in_place_edit_test.dart`; all tests pass (1262 → 1264; `test/l10n_test.dart` checks both languages have the same keys).

- [ ] **Step 10: Commit**

````bash
git add apps/mobile/pubspec.yaml apps/mobile/ios/Podfile.lock apps/mobile/ios/Runner/Info.plist apps/mobile/android/app/src/main/AndroidManifest.xml apps/mobile/android/app/src/main/res/xml/network_security_config.xml apps/mobile/lib/l10n/intl_en.arb apps/mobile/lib/l10n/intl_vi.arb apps/mobile/lib/shared/src/l10n.dart apps/mobile/lib/shared/src/intl/messages_en.dart apps/mobile/lib/shared/src/intl/messages_vi.dart apps/mobile/lib/core/backend/backend.dart apps/mobile/lib/core/backend/client_backend.dart apps/mobile/test/platform_config_test.dart apps/mobile/test/support/fakes.dart
git commit -m "feat(v2-tools): mobile foundation — webview packages pinned, cleartext only to the phone's loopback, the tool strings, MachineSession.tools

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 13: The tool page (`ToolRoute`) and Settings › "Xóa dữ liệu của tool"

The page a tool opens in, pushed over the machine page (R23).
- **E15, the bar:** ‹, the tool's name, "localhost:5173 · qua máy tính", ↻, and ⋯ with "Về trang đầu" and "Tải lại". Under it, a 2 px progress line; past 3 s, "Đang tải qua máy tính… (n request)" (E20).
- **E16, what covers the web view:**
  - "Đang tải qua đường hầm…" until the first page is in;
  - "Không có gì chạy ở localhost:5173 trên máy tính." with a spinner while it retries;
  - "Tool này không còn mở được trên điện thoại.", "Tool này đã bị xóa trên máy tính.", "Mở ShellX trên máy tính để dùng tool.";
  - a lost channel keeps the page under a "Đang kết nối lại…" strip (R18);
  - E3: "Đang mở ở cổng P′ vì cổng P bận trên điện thoại. …".
- **E12, the web view (`ToolWebEngine`; `webview_flutter` in the app, a fake in tests):**
  - JavaScript on, no JavaScript channel into the app;
  - every permission request denied, Android geolocation off, Android's file chooser gives nothing and says "Tải tệp chưa làm được trên điện thoại." (R17);
  - navigation by `toolNavigation` (R16): the served origins go on, another loopback spelling goes to `localhost`, an unserved local port is stopped and named in a toast, another http(s) site asks "Mở {host} bằng trình duyệt?" and opens in the browser, anything else at the top is stopped;
  - the page's `alert`/`confirm`/`prompt` are the app's dialogs titled "{name} nhắn", so a page cannot pass for ShellX;
  - a stopped web content process (iOS) reloads.
- **E13:** the app in the background pauses the session (nothing served), back on screen resumes it (`AppLifecycleListener`).
- **Back:** Android back goes back in the page first, then leaves; leaving closes the session (its servers close, the computer is told).
- **Settings:** a row "Xóa dữ liệu của tool" asks first ("Đăng xuất mọi tool và xóa cookie, bộ nhớ của chúng?"), then clears the web view's cookies, cache and local storage (R22). The new row moves "Đăng xuất" below the fold of `app_test.dart`'s phone, so that test now scrolls until rows can be tapped (`.hitTestable()`).

**Files:**
- Create:
  - `apps/mobile/lib/features/tools/domain/tool_navigation.dart`, `apps/mobile/lib/features/tools/domain/tool_texts.dart`;
  - `apps/mobile/lib/features/tools/presentation/tool_web_engine.dart`, `apps/mobile/lib/features/tools/presentation/controllers/tool_page_controller.dart`, `apps/mobile/lib/features/tools/presentation/pages/tool_page.dart`.
- Modify: `apps/mobile/lib/core/router/app_router.dart` (+ generated `app_router.gr.dart`, `apps/mobile/lib/core/dependency/dependency.config.dart`), `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`
- Test:
  - Create: `apps/mobile/test/support/fake_tool_engine.dart`, `apps/mobile/test/features/tools/tool_navigation_test.dart`, `apps/mobile/test/features/tools/tool_page_test.dart`;
  - Modify: `apps/mobile/test/features/settings/settings_page_test.dart`, `apps/mobile/test/app_test.dart`.

**Interfaces:**
- Consumes:
  - Task 12: `ToolMachine.page`, `ToolPageSession`, `FakeToolMachine`/`FakeToolPage`, the `S` tool strings;
  - Task 9: `ToolPhase`, `ToolLoad`, `ToolReload`, `ToolSiblingOff`, `ToolDownloadBlocked`, `ToolHostTexts`;
  - Task 8: `ToolInfo`;
  - existing: `Controller` (`popupHandler`), `signal`/`Watch`, `SessionHolder`, `ExternalLinks.openOrToast`, `showConfirmDialog`, `NoticeBanner`, `ConnectionBanner`, `AppCircularProgress`, `S.linkSheetOpen`, and the test harness `routedApp`, `pinned`, `agentA`, `FakeSessionHolder`, `FakePopupHandler`, `FakeExternalLinks`.
- Produces:
  - `tool_navigation.dart`: `sealed class ToolNavigation` with `ToolGo()`, `ToolGoInstead(Uri url)`, `ToolAskExternal(Uri url)`, `ToolOtherLocal(int port)`, `ToolBlock()`; `ToolNavigation toolNavigation(String url, {required bool mainFrame, required Set<String> origins})`;
  - `tool_texts.dart`: `final class AppToolTexts extends ToolHostTexts { const AppToolTexts(S s); }`;
  - `tool_web_engine.dart`:
    - `final class ToolWebCallbacks` (`decide`, `onProgress`, `onPageStarted`, `onPageFinished`, `onCrashed`, `onFileChooser`, `alert`, `confirm`, `prompt`);
    - `abstract interface class ToolWebEngine { void attach(ToolWebCallbacks callbacks); Future<void> load(Uri url); Future<void> reload(); Future<bool> canGoBack(); Future<void> goBack(); set askExternal(Future<void> Function(Uri url) ask); Widget view(); void dispose(); }`, with `@Injectable(as: ToolWebEngine) WebViewToolEngine`;
    - `abstract interface class ToolWebData { Future<void> clear(); }`, with `@LazySingleton(as: ToolWebData) WebViewToolData`;
  - `tool_page_controller.dart`: `enum ToolNotice { noDownloads, siblingOff }`; `const Duration kToolSlowAfter = Duration(seconds: 3)`; `@injectable class ToolPageController extends Controller { ToolPageController(@factoryParam String agentId, @factoryParam ToolInfo tool, SessionHolder session); }`;
  - `tool_page.dart`: `@RoutePage() class ToolPage { const ToolPage({Key? key, required String agentId, required ToolInfo tool}); }`, so the generated `ToolRoute({Key? key, required String agentId, required ToolInfo tool})`;
  - keys:
    - the bar: `tool.back`, `tool.title`, `tool.subtitle`, `tool.reload`, `tool.menu`, `tool.home`, `tool.menuReload`;
    - strips and progress: `tool.reconnecting`, `tool.otherPort`, `tool.progress`, `tool.slow`;
    - covers: `tool.loading`, `tool.refused`, `tool.disabled`, `tool.gone`, `tool.unavailable`;
    - dialogs: `tool.dialog`, `tool.dialogField`;
    - Settings: `settings.clearToolData`;
  - test support: `FakeToolWebEngine`, `FakeToolWebData` (`test/support/fake_tool_engine.dart`).

- [ ] **Step 1: Write the test support**

`apps/mobile/test/support/fake_tool_engine.dart`:

````dart
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

/// Stands for the web view of a tool page (V2-4): records what the page asks of it; a test plays
/// the web view's side through [callbacks].
class FakeToolWebEngine implements ToolWebEngine {
  late ToolWebCallbacks callbacks;
  late Future<void> Function(Uri url) ask;
  final List<Uri> loads = [];
  int reloads = 0;
  int goBacks = 0;
  bool canGoBackValue = false;
  bool disposed = false;

  @override
  void attach(ToolWebCallbacks callbacks) => this.callbacks = callbacks;

  @override
  set askExternal(Future<void> Function(Uri url) ask) => this.ask = ask;

  @override
  Future<void> load(Uri url) async => loads.add(url);

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<void> goBack() async => goBacks++;

  @override
  Widget view() => const ColoredBox(key: Key('fake-webview'), color: Color(0xFFFFFFFF));

  @override
  void dispose() => disposed = true;
}

/// Records what Settings clears.
class FakeToolWebData implements ToolWebData {
  int clears = 0;

  @override
  Future<void> clear() async => clears++;
}
````

- [ ] **Step 2: Write the failing tests**

`apps/mobile/test/features/tools/tool_navigation_test.dart`:

````dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';

const _served = {'http://localhost:5173', 'http://localhost:8000'};

ToolNavigation _top(String url) => toolNavigation(url, mainFrame: true, origins: _served);

/// V2-4 E12: where the tool page's web view may go.
void main() {
  test('the pages this phone serves, and about:blank', () {
    expect(_top('http://localhost:5173/'), isA<ToolGo>());
    expect(_top('http://localhost:8000/api?x=1'), isA<ToolGo>());
    expect(_top('about:blank'), isA<ToolGo>());
  });

  test('another loopback spelling of a served port goes to localhost (E2)', () {
    final go = _top('http://127.0.0.1:5173/login?next=%2F') as ToolGoInstead;
    expect(go.url.toString(), 'http://localhost:5173/login?next=%2F');
    expect((_top('http://[::1]:8000/') as ToolGoInstead).url.toString(), 'http://localhost:8000/');
  });

  test('a local port not served: stopped and named (E4)', () {
    expect((_top('http://localhost:9000/') as ToolOtherLocal).port, 9000);
    expect((_top('http://127.0.0.1:80/') as ToolOtherLocal).port, 80);
  });

  test('another site asks first; https to localhost is another site', () {
    expect((_top('https://accounts.example.com/sso') as ToolAskExternal).url.host, 'accounts.example.com');
    expect(_top('http://192.168.1.9:5173/'), isA<ToolAskExternal>());
    expect(_top('https://localhost:5173/'), isA<ToolAskExternal>());
  });

  test('other schemes at the top are stopped; frames inside the page go on', () {
    for (final url in ['javascript:alert(1)', 'file:///etc/hosts', 'intent://x#Intent;end', 'data:text/html,hi', '']) {
      expect(_top(url), isA<ToolBlock>(), reason: url);
    }
    expect(toolNavigation('data:text/html,hi', mainFrame: false, origins: _served), isA<ToolGo>());
  });
}
````

`apps/mobile/test/features/tools/tool_page_test.dart`:

````dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/controllers/tool_page_controller.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_tool_engine.dart';
import '../../support/fakes.dart';

const _tool = ToolInfo(id: 'k3f9za7q1m', name: 'Bảng việc', ws: 'shop-web', port: 5173, path: '/', group: 'ws:a');

/// V2-4 E12, E13, E15, E16, E20: the tool page with a stand-in web view.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeToolWebEngine engine;
  late FakePopupHandler popups;
  late FakeExternalLinks links;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    engine = FakeToolWebEngine();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<ToolWebEngine>(() => engine)
      ..registerFactoryParam<ToolPageController, String, ToolInfo>(
        (agentId, tool) => ToolPageController(agentId, tool, session),
      );
  });

  tearDown(() => getIt.reset());

  FakeToolPage page() => machine.tools.pages.single;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => ToolRoute(agentId: agentA, tool: _tool),
        routes: [AutoRoute(page: ToolRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    // The first load shows a spinner: pump the push, never settle it.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The tool is served and its first page is in (no spinner left).
  Future<void> shown(WidgetTester tester, {int? port}) async {
    page().ready(port: port);
    engine.callbacks.onPageStarted();
    engine.callbacks.onPageFinished();
    await tester.pumpAndSettle();
  }

  testWidgets('the bar names the tool; first load through the tunnel, then the page', (tester) async {
    await open(tester);
    expect(page().starts, 1);
    // The phone server's own answers are in the phone's language.
    final texts = machine.tools.texts.single;
    expect(texts.refused(5173), 'Không có gì chạy ở localhost:5173 trên máy tính.');
    expect(texts.siblingOff(8000), 'Tool ở cổng 8000 chưa bật cho điện thoại.');
    expect(texts.tooLarge, 'Phản hồi của tool quá lớn.');
    expect(find.text('Bảng việc'), findsOneWidget);
    expect(find.text('localhost:5173 · qua máy tính'), findsOneWidget);
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget);
    page().ready();
    await tester.pump();
    expect(engine.loads.single.path, '/__shellx/enter');
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget, reason: 'until the first page is in');
    engine.callbacks.onPageStarted();
    engine.callbacks.onProgress(40);
    engine.callbacks.onPageFinished();
    await tester.pump();
    expect(find.text('Đang tải qua đường hầm…'), findsNothing);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);
  });

  testWidgets('the states of E16 cover the page', (tester) async {
    await open(tester);
    await shown(tester);
    for (final (phase, text) in [
      (ToolPhase.refused, 'Không có gì chạy ở localhost:5173 trên máy tính.'),
      (ToolPhase.disabled, 'Tool này không còn mở được trên điện thoại.'),
      (ToolPhase.gone, 'Tool này đã bị xóa trên máy tính.'),
      (ToolPhase.unavailable, 'Mở ShellX trên máy tính để dùng tool.'),
    ]) {
      page().setPhase(phase);
      await tester.pump();
      expect(find.text(text), findsOneWidget, reason: phase.name);
    }
  });

  testWidgets('a lost channel keeps the page under "Đang kết nối lại…"; another port says so (E3)', (tester) async {
    await open(tester);
    await shown(tester, port: 49152);
    expect(
      find.text('Đang mở ở cổng 49152 vì cổng 5173 bận trên điện thoại. Link ghi rõ cổng 5173 có thể không chạy.'),
      findsOneWidget,
    );
    page().setPhase(ToolPhase.reconnecting);
    await tester.pump();
    expect(find.text('Đang kết nối lại…'), findsOneWidget);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);
    page().emit(const ToolReload());
    expect(engine.reloads, 1);
  });

  testWidgets('↻ reloads; ⋯ goes to the start page or reloads', (tester) async {
    await open(tester);
    await shown(tester);
    await tester.tap(find.byKey(const Key('tool.reload')));
    await tester.pump();
    expect(engine.reloads, 1);
    await tester.tap(find.byKey(const Key('tool.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Về trang đầu'));
    await tester.pumpAndSettle();
    expect(page().homes, 1);
    await tester.tap(find.byKey(const Key('tool.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool.menuReload')));
    await tester.pumpAndSettle();
    expect(engine.reloads, 2);
  });

  testWidgets('past 3 s a page says how many requests it made (E20)', (tester) async {
    await open(tester);
    await shown(tester);
    engine.callbacks.onPageStarted();
    page().requestsValue = 7;
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('tool.slow')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Đang tải qua máy tính… (7 request)'), findsOneWidget);
    engine.callbacks.onPageFinished();
    await tester.pump();
    expect(find.byKey(const Key('tool.slow')), findsNothing);
  });

  testWidgets('another site asks first, then opens in the browser (E12)', (tester) async {
    await open(tester);
    await shown(tester);
    final decision = engine.callbacks.decide('https://accounts.example.com/sso', true);
    expect(decision, isA<ToolAskExternal>());
    unawaited(engine.ask((decision as ToolAskExternal).url));
    await tester.pumpAndSettle();
    expect(find.text('Mở accounts.example.com bằng trình duyệt?'), findsOneWidget);
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(links.opened.single.toString(), 'https://accounts.example.com/sso');
    expect(engine.callbacks.decide('http://localhost:5173/x', true), isA<ToolGo>());
    expect(engine.callbacks.decide('javascript:alert(1)', true), isA<ToolBlock>());
  });

  testWidgets('a local port that is not served is named in a toast (E4)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide('http://localhost:8000/', true), isA<ToolOtherLocal>());
    expect(popups.infos.single, 'Tool ở cổng 8000 chưa bật cho điện thoại.');
  });

  testWidgets('the page\'s dialogs are the app\'s and name the tool (E12)', (tester) async {
    await open(tester);
    await shown(tester);
    final confirmed = engine.callbacks.confirm('Xóa thẻ?');
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc nhắn'), findsOneWidget);
    expect(find.text('Xóa thẻ?'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await confirmed, isTrue);
    final typed = engine.callbacks.prompt('Tên?', 'An');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tool.dialogField')), 'Bình');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await typed, 'Bình');
  });

  testWidgets('downloads and file choosers are not on the phone yet: a toast (E12)', (tester) async {
    await open(tester);
    page().emit(const ToolDownloadBlocked());
    engine.callbacks.onFileChooser();
    page().emit(const ToolSiblingOff(8000));
    expect(popups.infos, [
      'Tải tệp chưa làm được trên điện thoại.',
      'Tải tệp chưa làm được trên điện thoại.',
      'Tool ở cổng 8000 chưa bật cho điện thoại.',
    ]);
  });

  testWidgets('the app in the background: nothing served; back: served again (E13); a stopped web '
      'process reloads', (tester) async {
    await open(tester);
    await shown(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(page().pauses, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(page().resumes, 1);
    engine.callbacks.onCrashed();
    expect(engine.reloads, 1);
  });

  testWidgets('back goes back in the page first, then leaves; leaving closes the tool', (tester) async {
    await open(tester);
    await shown(tester);
    engine.canGoBackValue = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(engine.goBacks, 1);
    expect(find.text('Bảng việc'), findsOneWidget);
    engine.canGoBackValue = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc'), findsNothing);
    expect(page().closes, 1);
    expect(engine.disposed, isTrue);
  });
}
````

In `apps/mobile/test/features/settings/settings_page_test.dart`:

1. Add the imports `import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';` (after the `terminal_workspace.dart` import) and `import '../../support/fake_tool_engine.dart';` (after `import '../../support/fake_push.dart';`).
2. Before `group('A11 D31: keep the terminal size', () {` add:

````dart
  testWidgets('V2-4 E12: "Xóa dữ liệu của tool" asks first, then signs every tool out', (tester) async {
    final data = FakeToolWebData();
    getIt.registerSingleton<ToolWebData>(data);
    await openSettings(tester);
    final row = find.byKey(const Key('settings.clearToolData'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Đăng xuất mọi tool và xóa cookie, bộ nhớ của chúng?'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(data.clears, 0);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa dữ liệu của tool').last);
    await tester.pumpAndSettle();
    expect(data.clears, 1);
  });
````

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/features/tools test/features/settings/settings_page_test.dart`
Expected: FAIL to compile — `tool_navigation.dart`, `tool_web_engine.dart`, `ToolPageController` and `ToolRoute` do not exist.

- [ ] **Step 4: Where the page may go, and the server's own texts**

`apps/mobile/lib/features/tools/domain/tool_navigation.dart`:

````dart
/// V2-4 E12: what the tool page's web view does with a navigation.
sealed class ToolNavigation {
  const ToolNavigation();
}

/// Go on: a page this phone serves, a frame inside the page, `about:blank`.
final class ToolGo extends ToolNavigation {
  const ToolGo();
}

/// Go to [url] instead: another loopback spelling of a served port, as `localhost` (where the gate
/// cookie is; E2).
final class ToolGoInstead extends ToolNavigation {
  const ToolGoInstead(this.url);
  final Uri url;
}

/// Another http(s) site: ask, then open it in the phone's browser.
final class ToolAskExternal extends ToolNavigation {
  const ToolAskExternal(this.url);
  final Uri url;
}

/// A port of this phone's loopback that is not served (a tool not on for phone, E4): stopped, and
/// the page says which.
final class ToolOtherLocal extends ToolNavigation {
  const ToolOtherLocal(this.port);
  final int port;
}

/// Anything else (`javascript:`, `file:`, `intent:`, `data:` at the top): stopped, silently.
final class ToolBlock extends ToolNavigation {
  const ToolBlock();
}

const _loopback = {'localhost', '127.0.0.1', '::1'};

/// V2-4 E12: the main frame stays on what this phone serves ([origins], `http://localhost:<port>`);
/// another http(s) page asks first and opens in the browser; any other scheme is stopped. Frames
/// inside the page go where the page says.
ToolNavigation toolNavigation(String url, {required bool mainFrame, required Set<String> origins}) {
  if (!mainFrame || url == 'about:blank') return const ToolGo();
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return const ToolBlock();
  }
  if (uri.scheme == 'http' && _loopback.contains(uri.host)) {
    if (!origins.contains('http://localhost:${uri.port}')) return ToolOtherLocal(uri.port);
    return uri.host == 'localhost' ? const ToolGo() : ToolGoInstead(uri.replace(host: 'localhost'));
  }
  return ToolAskExternal(uri);
}
````

`apps/mobile/lib/features/tools/domain/tool_texts.dart`:

````dart
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// What the phone's tool server answers by itself (V2-4 E16, §7), in the phone's language.
final class AppToolTexts extends ToolHostTexts {
  const AppToolTexts(this._s);

  final S _s;

  @override
  String refused(int port) => _s.toolRefusedPhone(port);

  @override
  String siblingOff(int port) => _s.toolSiblingOff(port);

  @override
  String get disabled => _s.toolDisabled;

  @override
  String get gone => _s.toolGone;

  @override
  String get needsDesktop => _s.toolNeedsDesktop;

  @override
  String get tooLarge => _s.toolResponseTooLarge;
}
````

- [ ] **Step 5: The web view**

`apps/mobile/lib/features/tools/presentation/tool_web_engine.dart`:

````dart
import 'dart:async';

import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// What the tool page hears from its web view (V2-4 E12).
final class ToolWebCallbacks {
  const ToolWebCallbacks({
    required this.decide,
    required this.onProgress,
    required this.onPageStarted,
    required this.onPageFinished,
    required this.onCrashed,
    required this.onFileChooser,
    required this.alert,
    required this.confirm,
    required this.prompt,
  });

  /// Where the web view may go ([toolNavigation]); the engine acts on the answer it gets.
  final ToolNavigation Function(String url, bool mainFrame) decide;
  final void Function(int percent) onProgress;
  final void Function() onPageStarted;
  final void Function() onPageFinished;

  /// The web content process stopped: the page reloads.
  final void Function() onCrashed;

  /// The page asked for a file (Android): none is given (E12).
  final void Function() onFileChooser;

  /// The page's `alert`, `confirm` and `prompt`, shown as the app's dialogs naming the tool.
  final Future<void> Function(String message) alert;
  final Future<bool> Function(String message) confirm;
  final Future<String?> Function(String message, String? value) prompt;
}

/// The tool page's web view: `webview_flutter` in the app, a fake in tests.
abstract interface class ToolWebEngine {
  void attach(ToolWebCallbacks callbacks);
  Future<void> load(Uri url);
  Future<void> reload();
  Future<bool> canGoBack();
  Future<void> goBack();

  /// Asks the user, then opens [url] in the phone's browser (set by the page).
  set askExternal(Future<void> Function(Uri url) ask);
  Widget view();
  void dispose();
}

/// V2-4 E12: `webview_flutter` with no JavaScript channel into the app, every permission request
/// (camera, microphone, location) denied, geolocation off, no file chooser, and the main frame kept
/// on the phone's own loopback ([ToolWebCallbacks.decide]).
@Injectable(as: ToolWebEngine)
final class WebViewToolEngine implements ToolWebEngine {
  WebViewToolEngine() : _controller = WebViewController(onPermissionRequest: (request) => request.deny());

  final WebViewController _controller;
  Future<void> Function(Uri url) _askExternal = (_) async {};

  @override
  set askExternal(Future<void> Function(Uri url) ask) => _askExternal = ask;

  @override
  void attach(ToolWebCallbacks callbacks) {
    unawaited(_controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            switch (callbacks.decide(request.url, request.isMainFrame)) {
              case ToolGo():
                return NavigationDecision.navigate;
              case ToolGoInstead(:final url):
                unawaited(_controller.loadRequest(url));
              case ToolAskExternal(:final url):
                unawaited(_askExternal(url));
              case ToolOtherLocal() || ToolBlock():
                break;
            }
            return NavigationDecision.prevent;
          },
          onProgress: callbacks.onProgress,
          onPageStarted: (_) => callbacks.onPageStarted(),
          onPageFinished: (_) => callbacks.onPageFinished(),
          onWebResourceError: (error) {
            if (error.errorType == WebResourceErrorType.webContentProcessTerminated) callbacks.onCrashed();
          },
        ),
      ),
    );
    unawaited(_controller.setOnJavaScriptAlertDialog((request) => callbacks.alert(request.message)));
    unawaited(_controller.setOnJavaScriptConfirmDialog((request) => callbacks.confirm(request.message)));
    unawaited(
      _controller.setOnJavaScriptTextInputDialog(
        (request) async => await callbacks.prompt(request.message, request.defaultText) ?? '',
      ),
    );
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setGeolocationEnabled(false));
      unawaited(
        platform.setOnShowFileSelector((_) async {
          callbacks.onFileChooser();
          return const <String>[];
        }),
      );
    }
  }

  @override
  Future<void> load(Uri url) => _controller.loadRequest(url);

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<bool> canGoBack() => _controller.canGoBack();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Widget view() => WebViewWidget(controller: _controller);

  @override
  void dispose() {}
}

/// Settings › "Xóa dữ liệu của tool" (V2-4 E12): the tool pages' cookies and storage.
abstract interface class ToolWebData {
  Future<void> clear();
}

@LazySingleton(as: ToolWebData)
final class WebViewToolData implements ToolWebData {
  @override
  Future<void> clear() async {
    await WebViewCookieManager().clearCookies();
    final controller = WebViewController();
    await controller.clearCache();
    await controller.clearLocalStorage();
  }
}
````

- [ ] **Step 6: The controller**

`apps/mobile/lib/features/tools/presentation/controllers/tool_page_controller.dart`:

````dart
import 'dart:async';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

/// What the tool page tells the user in a toast (it has the strings).
enum ToolNotice { noDownloads, siblingOff }

/// After this long a page still loading says how many requests it made (V2-4 E20).
const Duration kToolSlowAfter = Duration(seconds: 3);

/// V2-4 E13, E15, E16: one tool on the phone. It serves the tool while the page is open and the app
/// is in the foreground, drives the web view (the entry URL, reloads), and says where the page is.
/// Nothing it carries is ever logged.
@injectable
class ToolPageController extends Controller {
  ToolPageController(@factoryParam this.agentId, @factoryParam this.tool, SessionHolder session)
    : _backend = session.backend.peek();

  final String agentId;
  final ToolInfo tool;
  final ShellxBackend? _backend;
  ToolPageSession? _page;
  ToolWebEngine? _engine;
  StreamSubscription<void>? _changes;
  StreamSubscription<ToolPageEvent>? _events;
  final _notices = StreamController<(ToolNotice, int?)>.broadcast(sync: true);
  Timer? _slow;
  bool _foreground = true;
  bool _disposed = false;

  final Signal<ToolPhase> _phase = signal(ToolPhase.opening);
  final Signal<int?> _alias = signal(null);
  final Signal<int> _progress = signal(0);
  final Signal<bool> _loading = signal(false);
  final Signal<bool> _firstLoad = signal(true);
  final Signal<int?> _slowRequests = signal(null);

  ShellxBackend? get backend => _backend;
  ReadonlySignal<ToolPhase> get phase => _phase;

  /// The port this phone serves the tool on when it is not the tool's own (E3).
  ReadonlySignal<int?> get alias => _alias;
  ReadonlySignal<int> get progress => _progress;
  ReadonlySignal<bool> get loading => _loading;

  /// Until the first page is in: "Đang tải qua đường hầm…".
  ReadonlySignal<bool> get firstLoad => _firstLoad;

  /// The requests of a page loading for more than [kToolSlowAfter]; null otherwise.
  ReadonlySignal<int?> get slowRequests => _slowRequests;

  /// Toasts for the page: a download it cannot take, a tool of the workspace that is off.
  Stream<(ToolNotice, int?)> get notices => _notices.stream;

  /// Serves the tool and shows it in [engine]; [texts] are the server's own answers.
  void start(ToolWebEngine engine, ToolHostTexts texts) {
    _engine = engine;
    final backend = _backend;
    if (backend == null) return _set(_phase, ToolPhase.closed);
    final MachineSession machine;
    try {
      machine = backend.machine(agentId);
    } on StateError {
      return _set(_phase, ToolPhase.gone); // not paired any more
    }
    final page = _page = machine.tools.page(tool, texts);
    _changes = page.changes.listen((_) => _sync());
    _events = page.events.listen(_onEvent);
    page.start();
    _sync();
  }

  void _sync() {
    final page = _page;
    if (page == null) return;
    _set(_phase, page.phase);
    _set(_alias, page.alias);
  }

  void _onEvent(ToolPageEvent event) {
    switch (event) {
      case ToolLoad(:final url):
        unawaited(_engine?.load(url));
      case ToolReload():
        unawaited(_engine?.reload());
      case ToolSiblingOff(:final port):
        _notices.add((ToolNotice.siblingOff, port));
      case ToolDownloadBlocked():
        _notices.add((ToolNotice.noDownloads, null));
    }
  }

  /// [ToolWebCallbacks.decide]: E12 against what this phone serves now.
  ToolNavigation decide(String url, bool mainFrame) {
    final decision = toolNavigation(url, mainFrame: mainFrame, origins: _page?.origins ?? const {});
    if (decision is ToolOtherLocal) _notices.add((ToolNotice.siblingOff, decision.port));
    return decision;
  }

  void pageStarted() {
    _page?.resetRequests();
    _set(_loading, true);
    _set(_slowRequests, null);
    _slow?.cancel();
    var waited = Duration.zero;
    const tick = Duration(milliseconds: 500);
    _slow = Timer.periodic(tick, (_) {
      waited += tick;
      if (waited >= kToolSlowAfter) _set(_slowRequests, _page?.requests ?? 0);
    });
  }

  void pageFinished() {
    _slow?.cancel();
    _slow = null;
    _set(_loading, false);
    _set(_slowRequests, null);
    _set(_firstLoad, false);
  }

  void progressed(int percent) => _set(_progress, percent);

  /// E12: the web content process stopped: the page loads again.
  void crashed() => unawaited(_engine?.reload());

  void fileChooser() => _notices.add((ToolNotice.noDownloads, null));

  Future<void> reload() async => _engine?.reload();

  /// "Về trang đầu".
  void home() => _page?.home();

  /// Android back: a page back in the web view first; false when there is none (the page closes).
  Future<bool> back() async {
    final engine = _engine;
    if (engine == null || !await engine.canGoBack()) return false;
    await engine.goBack();
    return true;
  }

  /// E13: served only while the app is in the foreground (Apple TN2277); back in it, served again
  /// (the port may change) and loaded.
  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _foreground = foreground;
    final page = _page;
    if (page == null) return;
    if (foreground) {
      page.resume();
    } else {
      unawaited(page.pause());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _slow?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_events?.cancel());
    unawaited(_page?.close());
    unawaited(_notices.close());
  }

  void _set<T>(Signal<T> s, T value) {
    if (_disposed) return;
    s.value = value;
  }
}
````

- [ ] **Step 7: The page**

`apps/mobile/lib/features/tools/presentation/pages/tool_page.dart`:

````dart
import 'dart:async';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/tools/domain/tool_texts.dart';
import 'package:shellx_mobile/features/tools/presentation/controllers/tool_page_controller.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-4 E15: one tool of the computer, over the machine's page: a bar (‹, the name, "localhost:5173 ·
/// qua máy tính", ↻, ⋯), a thin progress line, and the page in a web view. The states of E16 cover
/// the web view; a lost channel keeps the page under a strip. Android back goes back in the page
/// first.
@RoutePage()
class ToolPage extends StatefulWidget {
  const ToolPage({super.key, required this.agentId, required this.tool});

  final String agentId;
  final ToolInfo tool;

  @override
  State<ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<ToolPage> {
  late final ToolPageController _controller = getIt<ToolPageController>(param1: widget.agentId, param2: widget.tool);
  late final ToolWebEngine _engine = getIt<ToolWebEngine>();
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<(ToolNotice, int?)>? _notices;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // E13: served while the app is on screen; `hidden` and `paused` close the servers.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _controller.setForeground(
        state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _notices = _controller.notices.listen(_notice);
    _engine
      ..askExternal = _askExternal
      ..attach(
        ToolWebCallbacks(
          decide: _controller.decide,
          onProgress: _controller.progressed,
          onPageStarted: _controller.pageStarted,
          onPageFinished: _controller.pageFinished,
          onCrashed: _controller.crashed,
          onFileChooser: _controller.fileChooser,
          alert: _alert,
          confirm: _confirm,
          prompt: _prompt,
        ),
      );
    _controller.start(_engine, AppToolTexts(S.of(context)));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_notices?.cancel());
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _notice((ToolNotice, int?) notice) {
    if (!mounted) return;
    final s = S.of(context);
    final (kind, port) = notice;
    _controller.popupHandler.showInfo(
      title: switch (kind) {
        ToolNotice.noDownloads => s.toolNoDownloads,
        ToolNotice.siblingOff => s.toolSiblingOff(port ?? 0),
      },
    );
  }

  /// E12: another site opens in the phone's browser, once the user says so.
  Future<void> _askExternal(Uri url) async {
    if (!mounted) return;
    final s = S.of(context);
    final open = await showConfirmDialog(context, message: s.toolOpenExternal(url.host), confirmLabel: s.linkSheetOpen);
    if (open) await getIt<ExternalLinks>().openOrToast(url);
  }

  /// E12: the page's dialogs are the app's, titled with the tool's name (a page cannot pass for
  /// ShellX).
  Future<void> _alert(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tool.dialog'),
        title: Text(S.of(context).toolDialogTitle(widget.tool.name)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tool.dialog'),
        title: Text(S.of(context).toolDialogTitle(widget.tool.name)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<String?> _prompt(String message, String? value) async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _PromptDialog(title: S.of(context).toolDialogTitle(widget.tool.name), message: message, value: value),
    );
  }

  /// Android back: a page back in the web view first, else the tool page closes.
  Future<void> _back() async {
    if (await _controller.back()) return;
    _leave();
  }

  /// Past the [PopScope] (it only stops `maybePop`): the page closes.
  void _leave() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Column(
            children: [
              _bar(context),
              if (_controller.backend case final backend?)
                ConnectionBanner(
                  backend: backend,
                  onReconnectReplaced: () => unawaited(getIt<SessionHolder>().reconnectReplaced()),
                ),
              Watch(_strips),
              Watch(_progress),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _engine.view()),
                    Positioned.fill(child: Watch(_cover)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          IconButton(
            key: const Key('tool.back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new, color: colors.primary),
            onPressed: _leave,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tool.name,
                  key: const Key('tool.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.subHeader.bold.copyWith(color: colors.primaryText),
                ),
                2.sizedHeight,
                Text(
                  s.toolViaComputer(widget.tool.port),
                  key: const Key('tool.subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('tool.reload'),
            tooltip: s.toolReload,
            icon: Icon(Icons.refresh, color: colors.primary),
            onPressed: () => unawaited(_controller.reload()),
          ),
          PopupMenuButton<String>(
            key: const Key('tool.menu'),
            icon: Icon(Icons.more_horiz, color: colors.primary),
            onSelected: (choice) {
              if (choice == 'home') _controller.home();
              if (choice == 'reload') unawaited(_controller.reload());
            },
            itemBuilder: (context) => [
              PopupMenuItem(key: const Key('tool.home'), value: 'home', child: Text(s.toolHome)),
              PopupMenuItem(key: const Key('tool.menuReload'), value: 'reload', child: Text(s.toolReload)),
            ],
          ),
        ],
      ),
    );
  }

  /// E16 "Đang kết nối lại…" over a page kept as it is; E3 the other port.
  Widget _strips(BuildContext context) {
    final s = S.of(context);
    final alias = _controller.alias.value;
    final reconnecting = _controller.phase.value == ToolPhase.reconnecting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reconnecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: NoticeBanner(key: const Key('tool.reconnecting'), text: s.toolReconnecting),
          ),
        if (alias != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: NoticeBanner(
              key: const Key('tool.otherPort'),
              text: s.toolOtherPort(alias, widget.tool.port),
              tone: NoticeTone.info,
            ),
          ),
      ],
    );
  }

  /// The thin progress line; past 3 s "Đang tải qua máy tính… (n request)" (E20).
  Widget _progress(BuildContext context) {
    final colors = context.colors;
    final loading = _controller.loading.value;
    final slow = _controller.slowRequests.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 2,
          child: loading
              ? LinearProgressIndicator(
                  key: const Key('tool.progress'),
                  value: _controller.progress.value / 100,
                  minHeight: 2,
                  color: colors.link,
                  backgroundColor: colors.divider,
                )
              : null,
        ),
        if (slow != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              S.of(context).toolSlow(slow),
              key: const Key('tool.slow'),
              style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
            ),
          ),
      ],
    );
  }

  /// E16: what covers the web view while the page cannot be shown.
  Widget _cover(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final phase = _controller.phase.value;
    final (key, text, waiting) = switch (phase) {
      ToolPhase.opening || ToolPhase.busy => ('tool.loading', s.toolLoadingTunnel, true),
      ToolPhase.ready when _controller.firstLoad.value => ('tool.loading', s.toolLoadingTunnel, true),
      ToolPhase.refused => ('tool.refused', s.toolRefusedPhone(widget.tool.port), true),
      ToolPhase.disabled => ('tool.disabled', s.toolDisabled, false),
      ToolPhase.gone => ('tool.gone', s.toolGone, false),
      ToolPhase.unavailable => ('tool.unavailable', s.toolNeedsDesktop, false),
      ToolPhase.ready || ToolPhase.reconnecting || ToolPhase.paused || ToolPhase.closed => (null, null, false),
    };
    if (key == null || text == null) return const SizedBox.shrink();
    return ColoredBox(
      key: Key(key),
      color: colors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (waiting) ...[const AppCircularProgress(size: 24), 16.sizedHeight],
              Text(
                text,
                textAlign: TextAlign.center,
                style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's `prompt`: the app's dialog, titled with the tool's name; its field lives as long as it.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.message, required this.value});

  final String title;
  final String message;
  final String? value;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _field = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('tool.dialog'),
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message),
        TextField(key: const Key('tool.dialogField'), controller: _field, autofocus: true),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _field.text),
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}
````

In `apps/mobile/lib/core/router/app_router.dart`, after `AutoRoute(page: AiSessionRoute.page, guards: [authGuard]),` add:

````dart
    AutoRoute(page: ToolRoute.page, guards: [authGuard]),
````

Generate the route and the injection config (from `apps/mobile`; the generated files are committed as generated):

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs
````

Expected: `lib/core/router/app_router.gr.dart` gains `ToolRoute`/`ToolRouteArgs`; `lib/core/dependency/dependency.config.dart` gains `ToolWebData`, `ToolWebEngine` and the `ToolPageController` factory with two parameters.

- [ ] **Step 8: Settings › "Xóa dữ liệu của tool"**

In `apps/mobile/lib/features/settings/presentation/pages/settings_page.dart`:

1. After `import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';` add `import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';`.
2. Before `void _showLicenses() {` add:

````dart
  /// V2-4 E12: the tool pages keep their logins; this signs every tool out (asks first).
  Future<void> _clearToolData() async {
    final strings = S.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: strings.toolClearDataPhoneConfirm,
      confirmLabel: strings.toolClearDataPhone,
    );
    if (confirmed) await getIt<ToolWebData>().clear();
  }
````

3. In the card whose last row opens the licenses (`onTap: _showLicenses,`), after that `_Row(...)` add:

````dart
              Divider(height: 1, color: colors.divider),
              _Row(key: const Key('settings.clearToolData'), title: strings.toolClearDataPhone, onTap: _clearToolData),
````

4. In `class _Row`, add `super.key,` as the first parameter of `const _Row({`.

In `apps/mobile/test/app_test.dart`, make the four `scrollUntilVisible` calls of the Settings rows wait until the row can be tapped: replace `find.text('Sign out'), 200` with `find.text('Sign out').hitTestable(), 200` (three places) and `find.text('Delete account'), 200` with `find.text('Delete account').hitTestable(), 200` (one place).

- [ ] **Step 9: Run everything**

````bash
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/features/tools lib/core/router/app_router.dart lib/features/settings/presentation/pages/settings_page.dart test/support/fake_tool_engine.dart test/features/tools test/features/settings/settings_page_test.dart test/app_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: analyze reports only the pre-existing info; all tests pass (1264 → 1281).

- [ ] **Step 10: Commit**

````bash
git add apps/mobile/lib/features/tools apps/mobile/lib/core/router/app_router.dart apps/mobile/lib/core/router/app_router.gr.dart apps/mobile/lib/core/dependency/dependency.config.dart apps/mobile/lib/features/settings/presentation/pages/settings_page.dart apps/mobile/test/support/fake_tool_engine.dart apps/mobile/test/features/tools/tool_navigation_test.dart apps/mobile/test/features/tools/tool_page_test.dart apps/mobile/test/features/settings/settings_page_test.dart apps/mobile/test/app_test.dart
git commit -m "feat(v2-tools): the tool page — the bar, the states of E16, navigation kept on the phone's loopback, the page's dialogs named, served only in the foreground; Settings clears tool data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 14: The Tool group in the session picker; opening a tool from it

E15, criterion 1. When the computer says `tools` (Task 8's `supported`), the machine's session picker shows a group "Tool" after the AI sessions.
- **Rows:** one per tool on for the phone — 🧩, the name, "shop-web · localhost:4000", "Mở" — and a tap pushes `ToolRoute` over the terminal page.
- **Hints:** no tool on: "Chưa có tool nào bật cho điện thoại. Trên máy tính: thanh của tool › 📱 Điện thoại."; no list from the computer yet: "Mở ShellX trên máy tính để dùng tool.".
- **Live list:** the group follows the computer's list while the picker is open, so a tool turned on shows at once. `TerminalWorkspace` watches the list like the AI list: held by the picker, unwatched when nothing holds it.
- **Old desktop:** without the flag there is no group, and `+` still opens a session at once when there is nothing else to pick.

**Files:**
- Modify: `apps/mobile/lib/features/terminal/presentation/controllers/terminal_workspace.dart`, `apps/mobile/lib/features/terminal/presentation/widgets/session_picker.dart`, `apps/mobile/lib/features/terminal/presentation/pages/terminal_page.dart`
- Test: `apps/mobile/test/features/tools/tool_entry_test.dart`

**Interfaces:**
- Consumes: Task 12 `ToolMachine` (`supported`, `listing`, `listings`, `watch`, `unwatch`), `FakeToolMachine`; Task 13 `ToolRoute`, `ToolRouteArgs`; Task 8 `ToolInfo`, `ToolListing`; existing `SessionListing`, `showSessionPicker`, `SessionChoice`, `aiListingWait`, `stubRoute`, `openPushed`.
- Produces:
  - `SessionListing(…, {bool? toolsSupported, ToolListing? tools, Stream<ToolListing>? toolUpdates})` (its `isEmpty` is false when `toolsSupported == true`);
  - `void Function() TerminalWorkspace.holdToolListing()`; `ToolListing? TerminalWorkspace.toolListing`;
  - `final class OpenTool extends SessionChoice { const OpenTool(this.tool); final ToolInfo tool; }`;
  - keys: `picker-tool-<id>` (a row), `picker-tools-hint`.

- [ ] **Step 1: Write the failing tests**

`apps/mobile/test/features/tools/tool_entry_test.dart`:

````dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

const _board = ToolInfo(id: 'k3f9za7q1m', name: 'Bảng việc', ws: 'shop-web', port: 4000, path: '/', group: 'ws:a');
const _api = ToolInfo(id: 'api0000001', name: 'API', ws: 'shop-web', port: 8000, path: '/docs', group: 'ws:a');

/// V2-4 E15, criterion 1: the Tool group of the machine's session picker.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late List<Object?> pushed;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    final settings = AppSettings(InMemoryKeyValueStore());
    pushed = [];
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(FakeSpeechInput(), settings));
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [
          AutoRoute(page: TerminalRoute.page),
          stubRoute(ToolRoute.name, pushed: pushed),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  testWidgets('the Tool group lists the tools on for phone; a tap opens one', (tester) async {
    machine.tools
      ..supportedValue = true
      ..listingValue = const ToolListing(tools: [_board, _api]);
    await open(tester);
    expect(find.text('TOOL'), findsOneWidget);
    expect(find.text('Bảng việc'), findsOneWidget);
    expect(find.text('shop-web · localhost:4000'), findsOneWidget);
    expect(find.text('shop-web · localhost:8000'), findsOneWidget);
    expect(machine.tools.watching, isTrue, reason: 'the list follows the computer while the picker is open');
    await tester.tap(find.byKey(const ValueKey('picker-tool-k3f9za7q1m')));
    await tester.pumpAndSettle();
    expect((pushed.single! as ToolRouteArgs).tool, _board);
    expect(machine.tools.watching, isFalse);
  });

  testWidgets('a tool turned on while the picker is open shows at once (criterion 1)', (tester) async {
    machine.tools
      ..supportedValue = true
      ..listingValue = const ToolListing();
    await open(tester);
    expect(
      find.text('Chưa có tool nào bật cho điện thoại. Trên máy tính: thanh của tool › 📱 Điện thoại.'),
      findsOneWidget,
    );
    machine.tools.emitListing(const ToolListing(tools: [_board]));
    await tester.pump();
    expect(find.text('Bảng việc'), findsOneWidget);
  });

  testWidgets('no list from the computer yet: open ShellX on it', (tester) async {
    machine.tools
      ..supportedValue = true
      ..listingValue = const ToolListing(available: false);
    await open(tester);
    expect(find.text('Mở ShellX trên máy tính để dùng tool.'), findsOneWidget);
  });

  testWidgets('an older computer: no Tool group, and + opens a session at once', (tester) async {
    machine.tools.supportedValue = false;
    await open(tester);
    expect(find.text('TOOL'), findsNothing);
    expect(machine.opened, hasLength(1));
  });
}
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/features/tools/tool_entry_test.dart`
Expected: 3 failures (no "TOOL" group, no tool rows, no hint); "an older computer: no Tool group, and + opens a session at once" already passes — it pins that an old desktop sees no change.

- [ ] **Step 3: The workspace holds the tool list**

In `apps/mobile/lib/features/terminal/presentation/controllers/terminal_workspace.dart`:

1. Replace the constructor of `SessionListing`:

````dart
  const SessionListing(this.sessions, {required this.desktopSharing, this.aiSupported, this.ai});
````

with:

````dart
  const SessionListing(
    this.sessions, {
    required this.desktopSharing,
    this.aiSupported,
    this.ai,
    this.toolsSupported,
    this.tools,
    this.toolUpdates,
  });
````

2. In `SessionListing`, after the field `final AiListing? ai;` add:

````dart

  /// V2-4: whether the computer has tools for phones; null when unknown (an older computer says
  /// nothing: no Tool group then).
  final bool? toolsSupported;

  /// V2-4: the tools this phone may open; null when not supported or not received yet.
  final ToolListing? tools;

  /// V2-4: the list as it changes while the picker is open (criterion 1: a tool turned on shows).
  final Stream<ToolListing>? toolUpdates;
````

3. Replace `isEmpty` and its comment:

````dart
  /// Nothing to pick: `+` opens a new session at once. A computer with AI for phones always
  /// offers the picker ("Phiên AI mới").
  bool get isEmpty => sessions.isEmpty && aiSupported != true;
````

with:

````dart
  /// Nothing to pick: `+` opens a new session at once. A computer with AI or tools for phones
  /// always offers the picker ("Phiên AI mới", the Tool group).
  bool get isEmpty => sessions.isEmpty && aiSupported != true && toolsSupported != true;
````

4. In `pickable()`, replace `final ai = await _pickableAiListing();` with:

````dart
    final (ai, tools) = await (_pickableAiListing(), _pickableToolListing()).wait;
````

   and in the `SessionListing(...)` it returns, after `ai: ai,` add:

````dart
      toolsSupported: machine.tools.supported,
      tools: tools,
      toolUpdates: machine.tools.supported == true ? machine.tools.listings : null,
````

5. Before the comment `// V2-2: the computer's AI sessions. The list is watched while a page shows it …` add:

````dart
  // V2-4: the computer's tools, watched like the AI list (while a page or the picker shows them).
  int _toolHolders = 0;
  bool _toolWatching = false;
  bool _toolStale = false;
  StreamSubscription<ToolListing>? _toolFeed;

  /// The computer's tool list as far as it can be trusted (see [aiListing]).
  ToolListing? get toolListing => _toolStale ? null : machine.tools.listing;

  /// Like [holdAiListing], for the tool list.
  void Function() holdToolListing() {
    _toolHolders++;
    _syncToolWatch();
    var held = true;
    return () {
      if (!held) return;
      held = false;
      _toolHolders--;
      _syncToolWatch();
    };
  }

  void _syncToolWatch() {
    final tools = machine.tools;
    final want = !_disposed && _toolHolders > 0 && tools.supported == true;
    if (want == _toolWatching) return;
    _toolWatching = want;
    if (want) {
      _toolFeed = tools.listings.listen((_) => _toolStale = false);
      unawaited(tools.watch().catchError((Object _) {}));
    } else {
      unawaited(_toolFeed?.cancel());
      _toolFeed = null;
      _toolStale = true;
      tools.unwatch();
    }
  }

  /// The tool list for the picker: null when the computer has no tools for phones, or did not answer
  /// within [aiListingWait].
  Future<ToolListing?> _pickableToolListing() async {
    if (_disposed || machine.tools.supported != true) return null;
    final release = holdToolListing();
    try {
      final held = toolListing;
      if (held != null) return held;
      final next = Completer<ToolListing?>();
      void finish(ToolListing? listing) {
        if (!next.isCompleted) next.complete(listing);
      }

      final timer = Timer(aiListingWait, () => finish(null));
      final heard = machine.tools.listings.listen(finish, onDone: () => finish(null));
      return await next.future.whenComplete(() {
        timer.cancel();
        unawaited(heard.cancel());
      });
    } finally {
      release();
    }
  }
````

6. In `dispose()`, after `_syncAiWatch();` add `_syncToolWatch();`.

- [ ] **Step 4: The Tool group in the picker**

In `apps/mobile/lib/features/terminal/presentation/widgets/session_picker.dart`:

1. After `import 'package:shellx_ai/remote.dart';` add `import 'package:shellx_client/shellx_client.dart';`.
2. After `final class NewAiSession extends SessionChoice { … }` add:

````dart

/// V2-4: open a tool of the computer.
final class OpenTool extends SessionChoice {
  const OpenTool(this.tool);
  final ToolInfo tool;
}
````

3. In `showSessionPicker`, after the AI block (the `if (listing.aiSupported == false) ...[ … ] else if (listing.aiSupported == true) ...[ … ],` that ends with `_Group(children: _aiRows(context, listing)),` and `],`), and before `14.sizedHeight, _GroupHeader(strings.pickerDesktopGroup),`, add:

````dart
              // V2-4 E15: the Tool group after the AI sessions (none from a computer without tools).
              if (listing.toolsSupported == true) ...[
                14.sizedHeight,
                _GroupHeader(strings.pickerTools),
                8.sizedHeight,
                StreamBuilder<ToolListing>(
                  stream: listing.toolUpdates,
                  initialData: listing.tools,
                  builder: (context, snapshot) => _Group(children: _toolRows(context, snapshot.data)),
                ),
              ],
````

4. Before `/// One AI session: "Nút đăng xuất" / …` (the doc comment of `_AiRow`) add:

````dart
/// V2-4 E15: a row per tool on for the phone; a hint when there is none, or no list yet.
List<Widget> _toolRows(BuildContext context, ToolListing? tools) {
  final s = S.of(context);
  if (tools == null || !tools.available) {
    return [_Hint(key: const ValueKey('picker-tools-hint'), text: s.toolNeedsDesktop)];
  }
  if (tools.tools.isEmpty) return [_Hint(key: const ValueKey('picker-tools-hint'), text: s.toolsEmpty)];
  return [for (final tool in tools.tools) _ToolRow(tool: tool)];
}

/// One tool: 🧩, "Bảng việc" / "shop-web · localhost:4000".
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool});

  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    return InkWell(
      key: ValueKey('picker-tool-${tool.id}'),
      onTap: () => Navigator.pop(context, OpenTool(tool)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(
            children: [
              ExcludeSemantics(child: Icon(Icons.extension_outlined, size: 20, color: colors.secondaryText)),
              10.sizedWidth,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.subHeader15.bold.copyWith(color: colors.primaryText),
                    ),
                    2.sizedHeight,
                    Text(
                      s.toolRowSub(tool.ws, tool.port),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
              10.sizedWidth,
              Text(s.pickerOpen, style: context.typo.subHeader15.bold.copyWith(color: colors.link)),
            ],
          ),
        ),
      ),
    );
  }
}
````

- [ ] **Step 5: Opening a tool from the terminal page**

In `apps/mobile/lib/features/terminal/presentation/pages/terminal_page.dart`:

1. In `_pick`, replace `final choice = await showSessionPicker(context, listing);` with:

````dart
    // V2-4 criterion 1: the Tool group follows the computer's list while the picker is open.
    final release = _controller.hasWorkspace ? _controller.workspace.holdToolListing() : () {};
    final SessionChoice? choice;
    try {
      choice = await showSessionPicker(context, listing);
    } finally {
      release();
    }
````

2. In the `switch (choice)` of `_pick`, after the case `case OpenAiSession(:final session): await _openAi(session.sid);` add:

````dart
      case OpenTool(:final tool):
        await _openTool(tool);
````

3. After the method that opens an AI session (`_openAi`), add:

````dart

  /// V2-4 E15: the tool over this page; the terminal tabs are not looked at meanwhile.
  Future<void> _openTool(ToolInfo tool) async {
    _controller.setViewing(false);
    await context.router.push(ToolRoute(agentId: widget.agentId, tool: tool));
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _controller.setViewing(true);
  }
````

- [ ] **Step 6: Run everything**

````bash
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/features/terminal/presentation/controllers/terminal_workspace.dart lib/features/terminal/presentation/widgets/session_picker.dart lib/features/terminal/presentation/pages/terminal_page.dart test/features/tools/tool_entry_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: analyze reports only the pre-existing info; all tests pass (1281 → 1285).

- [ ] **Step 7: Commit**

````bash
git add apps/mobile/lib/features/terminal/presentation/controllers/terminal_workspace.dart apps/mobile/lib/features/terminal/presentation/widgets/session_picker.dart apps/mobile/lib/features/terminal/presentation/pages/terminal_page.dart apps/mobile/test/features/tools/tool_entry_test.dart
git commit -m "feat(v2-tools): the Tool group in the session picker, live while it is open; a tap opens the tool page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 15: The desktop window serves its phone list (needs V2-3 Task 1)

**Prerequisite — V2-3 Task 1 in this branch.** Before this task starts, the controller cherry-picks V2-3 Task 1's commit into `v2-4`. That commit adds `apps/desktop/lib/src/tools/tool_entry.dart` (`ToolEntry`) and `apps/desktop/lib/src/tools/tool_registry.dart` (`toolRegistryProvider`), with the interface in "Shared interface with V2-3" above. Check first:

````bash
ls apps/desktop/lib/src/tools/tool_entry.dart apps/desktop/lib/src/tools/tool_registry.dart && grep -n "phoneOn\|toolRegistryProvider" apps/desktop/lib/src/tools/tool_entry.dart apps/desktop/lib/src/tools/tool_registry.dart
````

If either file is missing, stop and ask the controller; never write stand-ins in the branch. If V2-3 named things differently, adapt the calls here (not V2-3's files) and record it in the ledger.

E5, the window's side:
- **The phone list:** `phoneToolsBodyProvider` builds it from `toolRegistryProvider`:
  - every tool with `phoneOn` (the phone flag on and allowed: http on a loopback name, V2-3 D15), with its workspace's name (`sidebarWorkspacesProvider`, `Workspace.displayName`) and its workspace id as the group;
  - the ids of every other tool go in `off` (R3);
  - `ToolCatalog.serveBody` keeps it within one mux frame.
- **In-process** (the window holds the relay, `side != null`):
  - the window's `ToolProxy` becomes the target of the agent side's slot (Task 11), so `session.list.result` now says `tools`;
  - it serves the list, again on every change (`container.listen`);
  - on quit (`stopToolPhone`) every stream ends `desktop_closed`, phones that list hear `available: false`, and the slot stops serving.
- **With the background service:** the list goes over the mux (`tool.serve`, Task 7) at once, on every change and on every new link, but only to a service whose `hello.caps` says `tools` (an older one is never sent it); on quit the service keeps the last list.
- **Never throws:** errors log only their type, and the window starts whatever happens.

**Files:**
- Create: `apps/desktop/lib/src/tools/tool_phone.dart`
- Modify: `apps/desktop/lib/main.dart`
- Test: `apps/desktop/test/tools/tool_phone_test.dart`

**Interfaces:**
- Consumes:
  - V2-3 Task 1: `ToolEntry` (`id`, `ws`, `name`, `url`, `phoneOn`, `copyWith(phone:)`), `toolRegistryProvider`, `ToolRegistry` (a `Notifier<List<ToolEntry>>` with a no-argument constructor);
  - Task 5: `ToolProxy`, `ToolCatalog.serveBody`/`fromServeBody`; Task 7: `MuxType.toolServe`; Task 11: `SessionCore.tools`, `installDaemonTools`, `kDaemonCaps`;
  - existing: `sidebarWorkspacesProvider` (`workspace(id)?.displayName(l10n)`), `kDefaultWorkspaceId`, `appL10nProvider`, `daemonLinkProvider` (`DaemonLink.info.caps`, `.client.send`), and the tests' `cliContainer`, `attachClient`, `TestListener`, `MemoryMuxTransport`.
- Produces:
  - `final phoneToolsBodyProvider = Provider<Uint8List>(…)`; `final toolPhoneProxyProvider = Provider<ToolProxy>(…)`;
  - `void startToolPhone(ProviderContainer container, {ToolEndpointSlot? slot})`; `void stopToolPhone(ProviderContainer container)`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/tools/tool_phone_test.dart`:

````dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/daemon_tools.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_phone.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../cli/support/cli_container.dart';
import '../mux/mux_test_support.dart';
import '../support/fake_local_sessions.dart';
import '../support/fake_pty.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// V2-3's list as a test sets it.
final class _Tools extends ToolRegistry {
  _Tools(this._initial);
  final List<ToolEntry> _initial;

  @override
  List<ToolEntry> build() => _initial;

  void set(List<ToolEntry> tools) => state = tools;
}

const _board = ToolEntry(
  id: 'k3f9za7q1m',
  ws: kDefaultWorkspaceId,
  name: 'Bảng việc',
  url: 'http://localhost:4000/',
  phone: true,
);
const _grafana = ToolEntry(
  id: 'grafana001',
  ws: kDefaultWorkspaceId,
  name: 'Grafana',
  url: 'http://localhost:3000/',
);
const _remote = ToolEntry(
  id: 'remote0001',
  ws: kDefaultWorkspaceId,
  name: 'Staging',
  url: 'https://staging.example.com/',
  phone: true, // not allowed on a phone (V2-3 D15): never served
);

ProviderContainer _window(List<ToolEntry> tools) => cliContainer(
  FakeLocalSessions(),
  overrides: [toolRegistryProvider.overrideWith(() => _Tools(tools))],
);

SessionCore _core() => SessionCore(
  ptyFactory: FakePtyFactory(),
  shellResolver: const FixedShellResolver(),
  homeDirectory: '/Users/phu',
  baseEnvironment: const {'HOME': '/Users/phu'},
  api: ShellxApi(baseUri: Uri.parse('https://relay.test')),
);

List<String> _ids(Uint8List body) {
  final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
  return [for (final t in json['tools']! as List) (t as Map)['id'] as String];
}

/// V2-4 E5, E15: the window's tools for phones, in-process and through the
/// background service (needs V2-3's `toolRegistryProvider`).
void main() {
  test('only tools on for the phone are served, with their workspace\'s '
      'name; the others are named off', () {
    final c = _window([_board, _grafana, _remote]);
    final body = c.read(phoneToolsBodyProvider);
    final json = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    expect(json['tools'], [
      {
        'id': 'k3f9za7q1m',
        'name': 'Bảng việc',
        'ws': 'Default',
        'group': kDefaultWorkspaceId,
        'url': 'http://localhost:4000/',
      },
    ]);
    expect(json['off'], ['grafana001', 'remote0001']);
  });

  test('in-process: the slot serves the window\'s list; a change is heard; '
      'quitting tells the phone and stops serving', () async {
    final c = _window([_board]);
    final core = _core();
    final heard = <ToolMessage>[];
    core.tools.outbound.listen((o) => heard.add(o.message as ToolMessage));
    expect(core.tools.serving, isFalse);
    startToolPhone(c, slot: core.tools);
    expect(core.tools.serving, isTrue);
    core.tools.handle(_phone, const ToolList());
    expect(_ids((heard.last as ToolListResult).body), ['k3f9za7q1m']);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      _board.copyWith(phone: false),
    ]);
    await pumpEventQueue();
    expect(_ids((heard.last as ToolListResult).body), isEmpty);
    stopToolPhone(c);
    expect((heard.last as ToolListResult).available, isFalse);
    expect(core.tools.serving, isFalse);
  });

  test('with the background service: the list goes over the link to a '
      'service that has tools, again on every change; an older one gets '
      'nothing', () async {
    final core = _core();
    final listener = TestListener();
    final server = MuxServer(
      sessions: core.sessions,
      secret: testSecret,
      self: const MuxPeerInfo(
        protocol: kMuxProtocol,
        app: 't',
        instance: 'i',
        caps: ['agent', 'cli', 'tools'],
      ),
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    final proxy = installDaemonTools(server, core);
    addTearDown(proxy.close);
    final client = await attachClient(listener);
    final c = _window([_board]);
    c
        .read(daemonLinkProvider.notifier)
        .set(
          DaemonLink(
            sessions: RemoteLocalSessions(client),
            info: const MuxPeerInfo(
              protocol: kMuxProtocol,
              app: 't',
              caps: ['agent', 'cli', 'tools'],
            ),
          ),
        );
    startToolPhone(c); // no slot: the background service holds the relay
    await pumpEventQueue();
    expect(proxy.catalog?.tools.map((t) => t.id), ['k3f9za7q1m']);
    (c.read(toolRegistryProvider.notifier) as _Tools).set([
      _board,
      _grafana.copyWith(phone: true),
    ]);
    await pumpEventQueue();
    expect(proxy.catalog?.tools.map((t) => t.id), ['k3f9za7q1m', 'grafana001']);

    // An older service (no `tools` in its caps) is never sent the list.
    final older = _window([_board]);
    final sent = <String>[];
    final (raw, daemonSide) = MemoryMuxTransport.pair();
    daemonSide.messages.listen((m) => sent.add(m.type));
    older
        .read(daemonLinkProvider.notifier)
        .set(
          DaemonLink(
            sessions: RemoteLocalSessions(MuxClient(raw)),
            info: const MuxPeerInfo(
              protocol: kMuxProtocol,
              app: 't',
              caps: ['agent', 'cli'],
            ),
          ),
        );
    startToolPhone(older);
    await pumpEventQueue();
    expect(sent, isNot(contains(MuxType.toolServe)));
  });
}
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_phone_test.dart`
Expected: FAIL to compile — `tool_phone.dart` does not exist.

- [ ] **Step 3: Write the window's side**

`apps/desktop/lib/src/tools/tool_phone.dart`:

````dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../mux/daemon_state.dart';
import '../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../terminal/sidebar_workspaces.dart';
import 'tool_registry.dart';

/// V2-4 E5: what phones may open, as the window says it (`tool.serve`'s `b`, or the in-process
/// proxy's list): every tool with its phone flag on and allowed (V2-3 D15, `phoneOn`) with its
/// workspace's name, and the ids of the other tools (a stream of one of them ends `disabled`, not
/// `gone`).
final phoneToolsBodyProvider = Provider<Uint8List>((ref) {
  final tools = ref.watch(toolRegistryProvider);
  final sidebar = ref.watch(sidebarWorkspacesProvider);
  final l10n = ref.watch(appL10nProvider);
  return ToolCatalog.serveBody(
    [
      for (final tool in tools)
        if (tool.phoneOn)
          {
            'id': tool.id,
            'name': tool.name,
            'ws': sidebar.workspace(tool.ws)?.displayName(l10n) ?? '',
            'group': tool.ws,
            'url': tool.url,
          },
    ],
    off: [
      for (final tool in tools)
        if (!tool.phoneOn) tool.id,
    ],
  );
});

/// V2-4 E5, in-process: the window holds the relay, so it hosts the tool proxy (one per run).
final toolPhoneProxyProvider = Provider<ToolProxy>((ref) {
  final proxy = ToolProxy();
  ref.onDispose(proxy.close);
  return proxy;
});

/// The slot the in-process proxy serves phones through (for [stopToolPhone]).
final class _ToolSlotPlug {
  ToolEndpointSlot? slot;
}

final _toolSlotPlugProvider = Provider<_ToolSlotPlug>((ref) => _ToolSlotPlug());

/// Called once by `main.dart` before any phone can reach the window: in-process the proxy becomes the
/// target of the agent side's [slot] (every runtime's router sends it `tool.*`) and serves the
/// window's list from now on; with the background service the list goes there instead. Never throws:
/// the window starts whatever happens here (phones then see no Tool group); the error's type goes to
/// the log.
void startToolPhone(ProviderContainer container, {ToolEndpointSlot? slot}) {
  try {
    if (slot != null) {
      final proxy = container.read(toolPhoneProxyProvider);
      container.listen<Uint8List>(
        phoneToolsBodyProvider,
        (_, body) => proxy.serve(ToolCatalog.fromServeBody(body)),
        fireImmediately: true,
      );
      container.read(_toolSlotPlugProvider).slot = slot;
      slot.target = proxy;
    } else {
      // The background service holds the relay: the list goes there on each link whose service says
      // it has tools (`hello.caps`), at once and whenever it changes; an older one is never sent it.
      void push() {
        final link = container.read(daemonLinkProvider);
        if (link == null || !link.info.caps.contains('tools')) return;
        link.client.send(MuxType.toolServe, {
          'b': container.read(phoneToolsBodyProvider),
        });
      }

      container.listen(daemonLinkProvider, (_, _) => push());
      container.listen<Uint8List>(
        phoneToolsBodyProvider,
        (_, _) => push(),
        fireImmediately: true,
      );
    }
  } on Object catch (error) {
    debugPrint(
      'ShellX: tools for phones failed to start: ${error.runtimeType}',
    );
  }
}

/// The window quits (V2-4 E5): in-process every phone stream ends `desktop_closed`, phones that list
/// hear `available: false`, and the slot stops serving. With the background service nothing changes:
/// it keeps the last list. Never throws.
void stopToolPhone(ProviderContainer container) {
  try {
    if (!container.exists(toolPhoneProxyProvider)) return;
    final proxy = container.read(toolPhoneProxyProvider);
    proxy.close();
    final slot = container.read(_toolSlotPlugProvider).slot;
    if (slot != null && identical(slot.target, proxy)) slot.target = null;
  } on Object catch (error) {
    debugPrint('ShellX: closing tools for phones failed: ${error.runtimeType}');
  }
}
````

- [ ] **Step 4: Start it with the window, stop it on quit**

In `apps/desktop/lib/main.dart`:

1. After `import 'src/terminal/terminal_tabs.dart';` add `import 'src/tools/tool_phone.dart';` (keep the imports sorted as they are; if V2-3 added other `src/tools/` imports, put it among them in order).
2. In `quitApp()`, as its first statement (before the comment `// V2-2 D1: a phone that still mirrors an AI session hears the window …`), add:

````dart
    // V2-4 E5: a phone on a tool page hears the window quit (in-process); the
    // background service keeps serving its last list. Never throws.
    stopToolPhone(container);
````

3. After `startAiPhone(container, slot: side?.core.ai);` add:

````dart
  // V2-4 E5: phones reach the tools on for them — through this process's
  // proxy (the agent side's slot), or the background service's (the list goes
  // there). Never throws.
  startToolPhone(container, slot: side?.core.tools);
````

- [ ] **Step 5: Run everything**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/tools/tool_phone.dart lib/main.dart test/tools/tool_phone_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
````

Expected: no issue; all tests pass (3577 → 3580 plus V2-3 Task 1's own tests, 10 skipped).

- [ ] **Step 6: Commit**

````bash
git add apps/desktop/lib/src/tools/tool_phone.dart apps/desktop/lib/main.dart apps/desktop/test/tools/tool_phone_test.dart
git commit -m "feat(v2-tools): the desktop window serves its phone list — in-process through the slot, or pushed to a background service that has tools

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

---

### Task 16: Final verification: every package and both apps, the compatibility matrix, the privacy sweep, the real relay, the ledger

Nothing new is built here: the branch is checked as a whole, and what was found goes in the ledger. **This task ends with a local commit of the ledger. It never pushes:** a push to `main` starts a desktop release (`release-desktop.yml`); the controller merges `v2-4` and pushes.

**Files:**
- Modify: `docs/superpowers/ledgers/v2-4-tools-phone.md`

**Interfaces:**
- Consumes: everything of Tasks 1–15.
- Produces: the ledger's "Execution" section.

- [ ] **Step 1: Every package and both apps, analyze and test**

Run each line from the repo root of the worktree and note the counts:

````bash
(cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test)
(cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test)
(cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test)
(cd packages/shellx_e2e && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test)
(cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test)
(cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test)
(cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test)
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test)
````

Expected (V2-4 alone; V2-2b's or V2-3's tests add to these when they are merged):
- `shellx_core` 395; `shellx_agent` 955; `shellx_client` 185; `shellx_e2e` 16 passed, 10 skipped (the relay tests); `shellx_acp` 87 and `shellx_ai` 576 (unchanged);
- `apps/mobile` 1285, with only the pre-existing `unnecessary_import` info in `test/features/terminal/ime_in_place_edit_test.dart`;
- `apps/desktop` 3580 plus V2-3 Task 1's tests, 10 skipped;
- every analyze otherwise clean.

If `packages/shellx_core/test/util/terminal_links_test.dart` "path performance" fails, run that file alone: it is timing-sensitive on a busy machine.

- [ ] **Step 2: Both apps still build (the native side of the web view and the platform config)**

````bash
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build apk --debug && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build ios --debug --no-codesign
````

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (about 70 s; it checks the manifest merge, `network_security_config.xml` and `webview_flutter_android`) and `✓ Built build/ios/iphoneos/Runner.app` (about 60 s; `webview_flutter_wkwebview` and `Info.plist`). Nothing is launched; no app runs on real data. Afterwards `git status` must show no change; if the `COCOAPODS:` line of `apps/mobile/ios/Podfile.lock` changed, revert that line (`git checkout -- apps/mobile/ios/Podfile.lock`, Task 12 already committed the plugin's lines).

- [ ] **Step 3: The compatibility matrix (E19, criterion 9)**

````bash
(cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test test/protocol/tool_messages_test.dart --plain-name "compatibility with every released peer" && ~/fvm/versions/3.41.4/bin/dart test test/protocol/tool_messages_test.dart --plain-name "session.list.result carries the tools protocol")
(cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/tool/tool_router_test.dart test/mux/mux_tools_test.dart)
(cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart test test/tools_test.dart --plain-name "compatibility")
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/agent/tool_slot_test.dart test/tools/tool_phone_test.dart)
(cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/features/tools/tool_entry_test.dart --plain-name "an older computer")
````

Expected: all pass. They make this matrix (copy it into the ledger):

| Pair | What holds | Tests |
|---|---|---|
| old phone ↔ new desktop | the old decoder skips `tool.*` and reads `session.list.result` with `tools` as before; a phone that never sends `tool.*` gets none | core "a V2-2 phone or desktop (frozen at d8ad686) skips every tool.*", "a V2-2 phone reads session.list.result with tools as before", "a V1 peer (frozen at 5e04dc8) skips them too"; client "old phone, new desktop: a phone that never asks gets no tool.*" |
| new phone ↔ old desktop | no `tools` flag → no Tool group, `tool.open` fails instead of waiting, terminals fine | core "an older desktop sends none: null"; agent "without an endpoint tool.* is ignored, like an older agent"; client "new phone, old desktop: …"; mobile "an older computer: no Tool group, and + opens a session at once" |
| new window ↔ old background service | no `tools` in `hello.caps` → the list is never sent; an older service ignores `tool.serve` anyway | desktop "with the background service: … an older one gets nothing"; agent "an older service (no proxy) ignores tool.serve and keeps answering" |
| old window ↔ new background service | no list pushed → phones hear `available: false` ("Mở ShellX trên máy tính để dùng tool.") | desktop "the background service: it says it has tools; its proxy serves the window's list and keeps it when the window goes" |
| new ↔ new | the flag only while a proxy serves, only for `desktop: true` | agent "tools: 1 only while an endpoint serves, only to a desktop: true …"; desktop "no target: not serving (no tools flag), the phone hears unavailable" |

- [ ] **Step 4: The privacy and security sweep (E9, E11, E14, E18)**

Run from the repo root and compare with the expected output:

````bash
NEW="packages/shellx_core/lib/src/protocol/tool_messages.dart packages/shellx_core/lib/src/protocol/tool_rules.dart packages/shellx_core/lib/src/protocol/tool_flow.dart packages/shellx_agent/lib/src/tool packages/shellx_client/lib/src/machine_tools.dart packages/shellx_client/lib/src/tool_session.dart apps/mobile/lib/features/tools apps/desktop/lib/src/tools/tool_phone.dart apps/desktop/lib/src/agent/daemon_tools.dart"
grep -rnE "(^|[^A-Za-z_.])(print|debugPrint|log)\(|stderr|stdout|developer\.log" $NEW -A1
grep -rn "findProxy\|followRedirects\|autoUncompress\|userAgent\|InternetAddress\.\|Socket.connect" packages/shellx_agent/lib/src/tool
grep -rn "InternetAddress.any\|anyIPv" packages/shellx_client/lib packages/shellx_agent/lib/src/tool apps/mobile/lib
grep -n "HttpServer.bind" -A3 packages/shellx_client/lib/src/tool_session.dart
grep -rn "addJavaScriptChannel\|JavaScriptChannel\|NSAllowsArbitraryLoads\|usesCleartextTraffic" apps/mobile/lib apps/mobile/ios/Runner/Info.plist apps/mobile/android/app/src/main
grep -rn "String toString()" -A1 $NEW | grep "=>"
grep -rn "Claude Code\|hide-claude-auth\|SHELLX_" $NEW apps/mobile/lib/l10n
````

Expected:
1. **Logging:** only the two `debugPrint` lines of `tool_phone.dart`, each printing `error.runtimeType`.
2. **Destination:**
   - `Socket.connect` only to `InternetAddress.loopbackIPv4`/`loopbackIPv6`;
   - `findProxy = ((_) => 'DIRECT')`, `autoUncompress = false`, `userAgent = null`;
   - `followRedirects = false` twice (HTTP and WebSocket).
3. **Binding:** nothing on `any`; the phone binds `loopbackIPv4`, and `loopbackIPv6` with `v6Only: true`.
4. **Web view:** nothing (no JavaScript channel, no arbitrary loads, no app-wide cleartext).
5. **`toString`:** every line returns `'…(…)'`: the messages' `'$runtimeType(…)'`, `ServedTool`, `ToolCatalog`, `ToolForwardedHead`, `ToolInfo`, `ToolListing`, `ToolServing`, `ToolLoad`, `ToolSession`. Each is pinned by "toString never shows a URL, a header or a body (E18)" (core), "toString never shows a URL or a name (E18)" (agent) and "toString never shows a URL (E18)" (client).
6. **Naming and credentials:** nothing.

Any other line is a finding: fix it in the file that owns it (with a test), then run Step 1 again for that package.

- [ ] **Step 5: The real relay, on the final branch**

As in Task 10 Step 6: start `npm run dev` on port 8799 with `DB_PATH=.data/v24-e2e.db` (background, PID kept), run `SHELLX_E2E_RELAY=http://127.0.0.1:8799 ~/fvm/versions/3.41.4/bin/dart test test/tools_e2e_test.dart` in `packages/shellx_e2e`, check `grep -c ws_rate_limited relay/.data/v24-relay.log` is `0`, stop the relay by its PIDs (never `pkill`/`killall`), and remove the `.data/v24-*` files. Note the time of the 50 MB transfer.

- [ ] **Step 6: The ledger**

Append to `docs/superpowers/ledgers/v2-4-tools-phone.md`, with the numbers you measured:

````markdown
## Execution

- Tasks 1–15 on branch `v2-4` (worktree `.claude/worktrees/v2-4`); V2-3 Task 1 cherry-picked by the controller before Task 15. Not pushed: the controller merges and pushes.
- Tests: shellx_core 351 → 395, shellx_agent 916 → 955, shellx_client 159 → 185 (the in-process end to end included), shellx_e2e 16 passed / 10 skipped without a relay, shellx_acp 87 and shellx_ai 576 unchanged, apps/mobile 1262 → 1285, apps/desktop 3574 → 3580 (+ V2-3 Task 1's), 10 skipped. Analyze clean but the pre-existing mobile info (`ime_in_place_edit_test.dart`).
- Builds: Android debug APK and iOS (no codesign) build; nothing launched.
- Real relay (`npm run dev`, port 8799, frame budget 500/s per device as in production): 50 MB through the tunnel in 17 s, byte for byte; no `ws_rate_limited` in the relay log.
- Compatibility matrix (E19): the table of Task 16 Step 3, all passing.
- Privacy sweep (E9, E11, E14, E18): only error runtime types logged; the proxy reaches 127.0.0.1/::1 only, no proxy, no redirects, no unpacking; the phone binds loopback only; no JavaScript channel, no arbitrary loads, cleartext only to localhost/127.0.0.1; every `toString` redacted and pinned.
- Rulings beyond the spec: R1–R23 above (planning rulings).
- Manual checks of spec §10, all pending (need a person, a real phone and a Mac): (1) iPhone iOS 17/18: a Vite tool on `localhost:5173` opens, HMR works, Telex typing in the page; (2) a tool declared as `http://127.0.0.1:8000` (Django/Jupyter) opens on iPhone; (3) Android 10, 14, 16 as (1); (4) a low port (80) and a port taken on the phone: alias mode (E3) and its strip; (5) a frontend and its API on two ports, both on: the page reaches the API (E4); (6) background and back: the page reloads and works; (7) slow network (Network Link Conditioner 3G): a big image, a terminal at the same time, the channel stays after a minute; (8) turning 📱 off on the desktop while the phone shows the page: it says so within 1 s; (9) VoiceOver / TalkBack in a tool page: note how far they read.
- Next (spec §11, E21, E22): `https` tools, `*.localhost` and other machines of the network; downloads and file pickers; service workers on iOS (App-Bound Domains); push notifications for tools; tools on the machine list; the desktop showing which phone has a tool open; the relay's heartbeat fix (M4); decryption off the UI isolate or native AEAD on the phone.
````

- [ ] **Step 7: Commit (no push)**

````bash
git add docs/superpowers/ledgers/v2-4-tools-phone.md
git commit -m "docs(v2-tools): ledger — results, compatibility matrix, privacy sweep, the real relay, manual checks pending

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

Do not push.
