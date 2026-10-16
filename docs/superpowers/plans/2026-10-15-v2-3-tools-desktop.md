# ShellX V2-3 — Personal tools by URL on the desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user adds a personal web tool (a name and an `http(s)` URL, with port suggestions from what the workspace's terminals and AI agent run), sees it in a tool dock beside the selected tab's panes (AI or terminal), keeps it loaded and signed in across tab switches and restarts, and can flag it for the phone (V2-4 does the phone part). macOS embeds WKWebView; Windows embeds WebView2 only with `tool-embed = on` and otherwise opens the system browser.

**Architecture:**
- **Model (pure Dart, `lib/src/tools/`).** `ToolEntry` and `parseToolUrl` (D1, D11, D15) and `ToolRegistry`, persisted as one JSON string per tool in the window-owned settings key `workspace_tools` (D2). This is the interface V2-4 consumes; Task 1 produces it exactly.
- **Engine (`lib/src/browser/`).**
  - A6's URL model and `BrowserEngine` interface, without the bridge: no JS channel, no script, no snapshot (D16).
  - macOS: `WkWebViewEngine` (`webview_flutter` 4.14.1 + `webview_flutter_wkwebview` 3.25.1, a platform view) and `BrowserNative.swift`. They are reviewed and hardened in Task 5: D9 navigation policy, D13 error kinds including ATS −1022, D10 key forwarding from the live keymap, focus hand-back on a click outside the page, native guards for new windows and downloads, clearing data, JS dialogs through ShellX.
  - Windows: `WinFloatingEngine` (`webview_win_floating` 3.0.3, a WebView2 window floating over Flutter's), behind the file key `tool-embed = auto | on | off`.
- **Dock.**
  - `ToolDockController` keeps one `ToolDockState` per workspace (open, zoom, width, active, chips). It is restored from a new top-level `toolDock` key in `layout.json`.
  - `ToolPages` keeps at most 8 live `ToolPage`s app-wide (LRU). Each owns an engine, the D13 retry loop with a 1 s port knock for local tools, the crash reload and the JS dialog guard.
  - `ToolArea` adds the dock as a third column in `TerminalWorkspacePage._body()`: panes │ handle │ dock.
- **Entry points.**
  - A "Tools" group under each workspace in the sidebar, and "Add tool" beside "New AI session".
  - 🧩 on the AI pane header; the palette ("Open tool: {name}", "Add tool…"); ⌘⇧B / Ctrl+Shift+B.
  - Settings › Projects: tools per project card, "Clear tool data…", "Show tools in ShellX".
- **Port suggestions.** `PaneSession.ports` of the workspace's terminal panes, plus one on-demand scan of the ports held by processes under the workspace's AI agent pids. The scan uses `ListeningScan.under` in `shellx_agent`, on top of A2's `PortProbe` and process table.

**Tech Stack:** Dart 3.11.1 / Flutter 3.41.4 (`~/fvm/versions/3.41.4/bin`, not on PATH), `flutter_riverpod` 3.3, `webview_flutter` 4.14.1, `webview_flutter_wkwebview` 3.25.1, `webview_win_floating` 3.0.3 (WebView2 SDK 1.0.1418.22 via NuGet at CMake time), Swift (macOS Runner), `flutter_test` with a fake engine, `integration_test` (an isolated macOS build only), `package:test` in `shellx_agent`.

**Spec:** `docs/superpowers/specs/2026-10-15-v2-3-tools-desktop-design.md` (binding, Vietnamese; D1–D24, §4 UI and strings, §5 model, §6 engine, §8 edges, §9 tests, §10 Review Focus, §11 manual checks). Background: the research note `.superpowers/sdd/2026-10-15-v2-3-tools-desktop/v2-3.md`, the A6 spec `docs/superpowers/specs/2026-10-07-desktop-browser-a6-design.md`, and A6's parked engine on `origin/feat/desktop-a6` (`9e84866`).

## Prerequisite and how this plan was made

**Where.** Execute in the worktree `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-3`, on branch `v2-3` made from `shellx-v2` at `130d8aa`.
- `130d8aa` is `38a786d` plus the release workflow (`5929cdc`), the V2-2b plan and the V2-4 plan. None of them touches `apps/` or `packages/`.
- Every command below runs from that worktree's root.
- Commit each task on `v2-3`. The controller reviews it and merges `v2-3` into `shellx-v2`.

**Never push.** Not `v2-3`, not `shellx-v2`, not a `windows-check/…` branch. A push to `main` releases the desktop app (`.github/workflows/release-desktop.yml`), so the controller does every push.

**Order.** Run the tasks in order: 1 → 16.

**Task 1 is shared with V2-4** (`docs/superpowers/plans/2026-10-15-v2-4-tools-phone.md`, Task 15).
- V2-4 consumes `ToolEntry`, `parseToolUrl`, `ToolUrlResult`/`ToolUrlOk`/`ToolUrlBad`/`ToolUrlError` and `ToolRegistry`/`toolRegistryProvider` exactly as Task 1 writes them. Never rename or narrow them.
- V2-4's controller cherry-picks Task 1's commit into `v2-4`, so that commit holds only Task 1's files (and the new ledger).

**Plans run in parallel (V2-2b on `v2-2b`, V2-4).** They branch from the same `shellx-v2`, so every replace block below applies as written on `v2-3`.
- If `v2-3` starts from a later `shellx-v2` (V2-2b merged first), the counts below are higher, and a replace block may need re-anchoring on the same lines. Keep the change the same and note it in the ledger.
- When the controller merges, it may meet small conflicts in shared files; keep both sides:
  - the ARB files and their generated localizations;
  - `settings_store.dart`, and the key count in `test/agent/settings_ownership_test.dart` (ruling R21: theirs + 1);
  - `terminal_workspace_page.dart`, `session_sidebar.dart`.

V2-3 keeps its own ledger, `docs/superpowers/ledgers/v2-tools.md`, so ledgers never conflict.

**How this plan was checked (2026-10-15).**
- Every task's code was written and run in a scratch worktree of `38a786d` (the same `apps/` and `packages/` as `130d8aa`). The code below is that code.
- Every replace block was generated from those files against `38a786d`.
- The plan was then replayed task by task into a second, fresh worktree of `38a786d`. The replay applied the files and replace blocks below and ran the commands that change files (`git checkout` from the A6 branch, `flutter pub get`, `flutter gen-l10n`, the frozen-parser copy). After every task it ran `flutter analyze` and the whole desktop suite; after Task 3 it also ran `flutter build macos --debug`. The result was byte-identical to the scratch worktree.
- Results:
  - `apps/desktop`: `flutter analyze` clean; `flutter test` **3789 passed, 9 skipped** (baseline, before any macOS build: 3574 passed, 10 skipped).
  - `packages/shellx_agent`: `dart analyze` clean; `dart test` **921 passed** (baseline 916 passed).
  - `flutter build macos --debug`: built.
  - The isolated macOS integration test (Task 6 recipe): 7 of 7 passed.
  - An isolated smoke launch of the full app (Task 16 recipe: bundle id `pro.shellx.desktop.itest`, temporary HOME) ran 20 s without an exception. Its only error lines were the existing "backup exclusion failed (TimeoutException)" ones: Time Machine exclusion under a temporary HOME.
- Not run here:
  - the Windows build: after Task 16 the controller pushes `windows-check/v2-3`, and the user reads the CI result;
  - the manual checks of spec §11.

Run first; Task 1 writes the output into the new ledger:

````bash
git branch --show-current && git log --oneline -1    # v2-3, at 130d8aa or later
git log --oneline -1 origin/feat/desktop-a6 || git fetch origin feat/desktop-a6    # 9e84866
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1)
(cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test 2>&1 | tail -1)
````

Expected at `130d8aa`: `No issues found!` twice; desktop `+3574 ~10: All tests passed!`; `shellx_agent` `+916: All tests passed!`.

## Rulings (each with "cost if wrong")

- **R1 — what the URL field accepts** (D1, Review Focus 5).
  - Leading and trailing spaces go. A missing scheme becomes `http://`; `localhost:5173` and `my_app:3000` count as "no scheme" although they parse as one.
  - Only `http`/`https`. No `user:pass@` (userinfo), no `\`, no control characters.
  - The host is letters, digits, `.`, `-`, `_`, or an IPv6 literal. Dart percent-encodes a space or a non-ASCII letter in a host, so `bücher.de` is refused as "no host": type its `xn--` form.
  - Port 1–65535. The fragment goes, and an empty path becomes `/`. At most 2 048 characters after normalising.
  - *Cost if wrong:* an IDN host must be typed in punycode.
- **R2 — strings the spec does not list.** These follow its wording and are pinned EN + VI in Task 2:
  - the URL error lines for `\`, no host, a bad port and length, and the 50-tool limit;
  - the D17 bar's button labels and the D21 menu labels;
  - the short D13 reasons (address not found, too long, certificate, network, other);
  - the "Tools: {name}" and "Tools width" accessibility labels (D18);
  - "OK", and the clear-data note.
  - *Cost if wrong:* some strings reworded later.
- **R3 — the bridge is gone from the interface, not just unused** (D16).
  - `BrowserEngine` has no `runScript`, `capturePng`, JS channel or bootstrap script.
  - `test/tools/tool_no_bridge_test.dart` fails if `lib/src/browser`, `lib/src/tools`, `lib/src/ui/tools` or `BrowserNative.swift` mentions `runJavaScript`, `runJavaScriptReturningResult`, `addJavaScriptChannel`, `addUserScript`, `WKUserScript`, `takeSnapshot`, `evaluateJavaScript` or `capturePng`.
  - *Cost if wrong:* A6's full browser adds its agent-facing methods back when it resumes.
- **R4 — macOS catches new windows and downloads natively.**
  - `webview_flutter_wkwebview` 3.25.1 has two gaps: its `WKUIDelegate` opens `window.open`/`target=_blank` in the same view, and its response policy always allows, so WebKit showed downloads inline (seen in the isolated run).
  - `BrowserNative.swift` therefore wraps the plugin's delegates. `NewWindowGuard` sends the URL to Dart as `OpenOutside(newWindow: true)`. `DownloadGuard` cancels an attachment or a MIME type WebKit cannot show, and sends `download`. Both forward everything else to the plugin, and `forget` puts the plugin's delegates back.
  - *Cost if wrong:* a plugin upgrade must re-check this file (the versions are pinned exactly).
- **R5 — `file:` in the top frame is refused by WebKit itself, before any policy call** (seen in the isolated run: the page stays, no URL change).
  - The D9 policy still blocks every other scheme WebKit does ask about: `javascript:`, `data:` and unknown schemes in the top frame, and anything but web/mail/phone as a new window.
  - *Cost if wrong:* none (two locks on one door).
- **R6 — Windows uses `webview_win_floating`'s own controller** (`WinWebViewController`), not `webview_flutter`'s.
  - Only it exposes `setVisibility`, `requestFocus`, `clearCache` (= `ClearBrowsingDataAll`), and the data folder and profile.
  - JS dialogs and downloads stay WebView2's own (the plugin has no hook). A new window arrives as a non-main-frame request and goes to the system browser.
  - *Cost if wrong:* with `tool-embed = on`, a Windows tool's `alert()` looks like Edge's and a download uses Edge's bar.
- **R7 — which chords stay with the page** (D10).
  - The spec's copy, paste, cut, select all, undo and redo stay with the page.
  - So do the terminal-only actions: `edit_line` (⌘←/⌘→/⌘⌫/⌥⌫/⌥⌦), `text:`/`csi:`/`esc:` sends and `ignore`. They would only take the page's own editing keys away.
  - Every other window binding is forwarded, the user's own and the first step of a sequence included.
  - *Cost if wrong:* a user's `text:` macro does nothing while a page has the keyboard.
- **R8 — a forwarded first step arms the sequence and gives the keyboard back** (D10). `KeySequence.arm(prefix)` starts the wait, and the dock's focus takes the keyboard, so the second step reaches ShellX. *Cost if wrong:* after a sequence, the user clicks into the page again.
- **R9 — a 1 s port knock for local tools** (criterion 5 against D13's schedule).
  - D13 retries at 1, 2, 4, 8, then every 10 s. Alone, that can leave a page up to 10 s behind its server.
  - While the "nothing is running" panel shows a tool on this computer, `ToolPage` also tries a TCP connect to its `host:port` once a second (500 ms timeout). It loads the page as soon as the connect succeeds.
  - *Cost if wrong:* one local connect per second while that panel shows.
- **R10 — a JS dialog flood answers itself** (D9).
  - At most 5 dialogs per 10 s per page are shown. Past that, `alert` is dismissed, `confirm` is `false` and `prompt` is `null`.
  - A dialog never answers "yes" by itself.
  - *Cost if wrong:* a page that legitimately asks more than 5 times in 10 s gets "no".
- **R11 — tool rows are not arrow-key stops, and group folding lasts for the run.** A2's arrow navigation walks tabs only; ⌘⇧P "Open tool: …" reaches every tool. *Cost if wrong:* keyboard users open tools from the palette.
- **R12 — agent pids come from the desktop's runtime factory, `shellx_ai` stays untouched** (spec scope).
  - When the factory knows the AI tab's pane, it builds the `AiRuntime` the way `AiHost.runtime` does, with a `launch` that records the agent's pid (`AiAgentPids`).
  - *Cost if wrong:* a 20-line copy of `AiHost.runtime` to keep in step (the provider's comment says so); a mismatch only loses the agent's ports from the suggestions.
- **R13 — no suggestions from SSH panes or exited panes; names only on demand** (D12).
  - An SSH pane's ports are the server's (spec §12: forwarded ports are typed by hand).
  - Process names come from one process-table read (`ps` on macOS, CIM on Windows) when the dialog opens.
  - *Cost if wrong:* a forwarded port is typed by hand.
- **R14 — a workspace shown without a tab ("loose", D4).**
  - Opening a tool of a workspace with no tab shows that workspace's dock beside an empty content area. The tab selected before stays selected underneath.
  - Pane commands (split, break, paste, focus) do nothing there. ⌘T and "New AI session" open the new tab in that workspace.
  - Any tab selection ends it. It is not restored.
  - *Cost if wrong:* after a restart, the dock of a workspace without tabs shows only when one of its tools is opened again.
- **R15 — an unloaded page loads again when it is shown again** (D5): its chip, its sidebar row or the palette, not only a click on the chip. *Cost if wrong:* none.
- **R16 — clearing tool data on Windows.**
  - With a live page: `clearCache()`, which is WebView2's `ClearBrowsingDataAll` on the shared `tools` profile.
  - Without one: the `%LOCALAPPDATA%\ShellX\tools` folder is deleted.
  - *Cost if wrong:* data WebView2 keeps outside the profile's browsing data stays until a clear with no page open.
- **R17 — the palette lists every tool of every workspace.** "Open tool: {name}", the shown workspace's first, with the workspace name as subtitle while the sidebar shows several workspaces. "Add tool…" is the keymap action. *Cost if wrong:* a long palette with many tools.
- **R18 — "Copy URL" copies the tool's URL.** ↗ on the bar opens the page's current URL (the tool's before the first load); the error panels and the download line open the URL they are about. *Cost if wrong:* copying the current page's URL takes ↗, then the browser.
- **R19 — `agent-skills/` is not updated** (outside spec §0's allowed paths). The ledger lists it as a follow-up (tell agents that tools exist). *Cost if wrong:* agents do not know tools exist yet.
- **R20 — adding from the window opens the tool; adding from Settings does not.** The window's entry points are the sidebar footer, ⌘⇧B with no tool, the palette and the AI header. *Cost if wrong:* one more click after adding in Settings.
- **R21 — `SettingKeys.all` grows from 34 to 35** (`workspace_tools`, window-owned, in `UiSettingKeys`). If V2-2b or V2-4 add keys first, the count is theirs + 1. *Cost if wrong:* a failing count test.
- **R22 — `toString()` of a tool is `ToolEntry(…)`.** That is the shared interface's class name; spec D24 says `Tool(…)`, with the same redaction. *Cost if wrong:* none.
- **R23 — no `watchPhoneTools()` stream** (spec §5). The registry is a Riverpod notifier; V2-4 watches `toolRegistryProvider` and filters `phoneOn` (shared interface). *Cost if wrong:* none (Riverpod is the stream).
- **R24 — the macOS integration test runs as a built app, not through `flutter test -d macos`.**
  - `flutter test -d macos` would run the Flutter tool itself under the temporary HOME (no pub cache, no settings).
  - So the recipe (Task 6) does three things in a throw-away worktree: it gives the app the bundle id `pro.shellx.desktop.itest`, builds with `flutter build macos --debug -t integration_test/tool_engine_test.dart`, and starts the binary with `HOME` and `CFFIXED_USER_HOME` set to a temporary folder. It reads the result from the log, then stops only that PID.
  - *Cost if wrong:* about a minute of build per run.
- **R25 — a retry loads the URL again; it never calls `reload()`.** After a failed first navigation, WKWebView's `reload()` reloads the last committed page (`about:blank`), not the one that failed (seen in the isolated run). *Cost if wrong:* none.
- **R26 — `workspace_tools` is a window key** (`UiSettingKeys`, A5b D13: one process writes each key). The background service never reads or writes it. *Cost if wrong:* none in V2-3.
- **R27 — `browser_url.dart` comes over unchanged (D6) but tools do not use it.**
  - It stays for A6's later browser. Tools follow V2-3 D11 through `isLocalToolHost` (Task 1): `*.localhost` and `0.0.0.0` count as this computer. A6's tightened S5 rule (`isLocalHost`) does not count them.
  - *Cost if wrong:* two local-host rules until A6 resumes.
- **R28 — Safari's Web Inspector reaches a tool page** (`setInspectable(true)`, macOS 13.3+, with Safari's Develop menu on). The tool is the user's own, and inspecting it is how they debug it beside ShellX. *Cost if wrong:* someone at the user's own session can inspect the user's own tool.

## Global Constraints

- **Branch and scope:**
  - Branch `v2-3` in `.claude/worktrees/v2-3` only (see Prerequisite). **Never push**: a push to `main` releases the desktop app, and the controller does every push. Never change `version:` in `apps/desktop/pubspec.yaml`: the release publishes that version.
  - Allowed: `apps/desktop` (including `macos/Runner` and the generated plugin files under `macos/Flutter` and `windows/flutter`), `packages/shellx_agent/lib/src/context/listening_ports.dart` and its test, and the ledger.
  - Never touch `packages/shellx_ai`, `packages/shellx_core`, `packages/shellx_acp`, `packages/shellx_client`, the phone protocol, `relay/`, `apps/mobile` or `agent-skills/`.
  - From `origin/feat/desktop-a6` take only the files Task 3 names. Never revert `fd7d178` and never bring `third_party/webview_windows`.
- **Dependencies (exact pins):**
  - `webview_flutter: 4.14.1` and `webview_flutter_wkwebview: 3.25.1` (3.26+ needs Flutter 3.44 / Dart 3.12); `webview_win_floating: 3.0.3`.
  - Resolve with `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the worktree root.
  - `pubspec.lock` files are git-ignored: never `git add` them.
  - After every `flutter build macos`, put the `COCOAPODS:` line of `apps/desktop/macos/Podfile.lock` back: `sed -i '' 's/^COCOAPODS: .*/COCOAPODS: 1.16.2/' apps/desktop/macos/Podfile.lock`. Never commit `1.17.0`.
- **Exact values (spec):**
  - Tools: at most `kMaxToolsPerWorkspace = 50` per workspace; name ≤ `kMaxToolNameLength = 60` characters (runes); URL ≤ `kMaxToolUrlLength = 2048`; `id` = 10 characters `[a-z0-9]`.
  - Storage: settings key `workspace_tools` = a list of JSON strings `{id, ws, name, url, phone}`.
  - Dock: default width 0.45 of the content area, at least 320 px, panes at least 360 px; handle 6 px; bar 32 px; chips only from 2 tools.
  - Pages: at most 8 live pages app-wide. Retries after 1, 2, 4, 8, then every 10 s, only while shown. A crashed page reloads once by itself.
  - Restore: `layout.json` gets a top-level `toolDock` = `{"<workspace id>": {"open", "zoom", "width", "active", "tools"}}`, written only when some dock differs from the default.
  - Keys: `toggle_tools` = ⌘⇧B / Ctrl+Shift+B; `add_tool` has no chord.
  - `tool-embed = auto | on | off`, default `auto` (embed on macOS, system browser on Windows).
  - Web data: macOS `WKWebsiteDataStore.default()`; Windows data folder `%LOCALAPPDATA%\ShellX\tools`, profile `tools`.
  - At most 8 port suggestions.
  - `Info.plist` gets `NSAppTransportSecurity › NSAllowsLocalNetworking = true` and nothing else (never `NSAllowsArbitraryLoadsInWebContent`).
- **No bridge (D16):** no JS channel, `runJavaScript`, user script or snapshot in `lib/src/browser` or `lib/src/tools` (pinned by `tool_no_bridge_test.dart`). `ui.browser.*` keeps answering `unknown_type`.
- **Privacy (D24):**
  - Never log a URL, path, page title, page text, cookie or header; log only an error's `runtimeType` or kind.
  - `toString()` of every new record shows its type and at most a count or a kind, never a URL, name, title, path or page text. Tests pin it.
    - `Name(…)`: `ToolEntry`, `ToolUrlOk`, `ToolRegistry`, `ToolPageState`, `ToolPage`, `ToolDraft`, `ToolPortSuggestion`, `UrlChanged`, `TitleChanged`, `OpenOutside`, `DownloadBlocked`.
    - A count or a kind: `ToolPages(3)`, `ToolDocks(2)`, `ToolDockState(open: true, zoom: false, tools: 2)`, `ToolUrlBad(userinfo)`, `LoadFailed(refused)`, `BrowserJsDialog(alert)`, `ListeningScan(4)`, `AiAgentPids(1)`.
- **Never auto-allow:** camera, microphone, location and notifications are denied without asking. A JS dialog never answers "yes" by itself. Nothing in V2-3 answers an agent permission.
- **Credentials and agents:**
  - ShellX never reads, stores or relays credentials; a tool's cookies stay in the engine's store.
  - Never pass `--hide-claude-auth`; never put `SHELLX_*` variables in an agent's environment.
  - Product naming: "Claude" or "Claude Agent", never "Claude Code", in feature names and UI strings.
- **Strings:**
  - `apps/desktop/lib/l10n/app_en.arb` + `app_vi.arb`, then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`. The generated `lib/l10n/app_localizations*.dart` are committed.
  - Vietnamese verbatim from spec §4, with straight quotes `"…"` as written there.
- **Old builds:** V1 (`164bba6`) and V2.0 (`d8ad686`) read a `layout.json` with `toolDock`, and settings with `workspace_tools`, without losing a tab and without a `.bak` (Task 9's frozen parsers).
- **The app is never launched on the user's real data.** The integration test and any launch use the Task 6 recipe only: a throw-away worktree, bundle id `pro.shellx.desktop.itest`, a temporary `HOME`/`CFFIXED_USER_HOME`. Never `pkill`/`killall`: stop only the PID you started.
- **Commands:**
  - desktop: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test <files>` and `… flutter analyze`;
  - `shellx_agent`: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test <files>` and `~/fvm/versions/3.41.4/bin/dart analyze`;
  - format only the files a task touches: `~/fvm/versions/3.41.4/bin/dart format <files>`. Never format the whole tree: some files on `main` are not in this formatter's style, e.g. `lib/src/platform/scroll_trace.dart`.
  - Window-shortcut widget tests use `variant: TargetPlatformVariant.only(TargetPlatform.macOS)`.
- **Every task ends green:** desktop `flutter analyze` reports `No issues found!` and `flutter test` passes. Task 11 adds `shellx_agent`'s `dart analyze` and `dart test`.
  - A few existing timing tests can fail when the machine is busy; seen while checking this plan: `test/terminal/global_search_test.dart`, `test/terminal/terminal_search_test.dart`, `test/ui/find_reconnect_test.dart`.
  - Rerun such a file alone before treating its failure as yours, and note it in the ledger.
  - The suite counts in this plan were taken in a worktree that already had a macOS build. `test/terminal_sharing/end_to_end_macos_test.dart` runs only with one. Before the worktree's first `flutter build macos` (Task 3 Step 7), expect one passed fewer and one skipped more (the baseline's `~10`).
- **Commits:** `feat(v2-tools): …` / `test(v2-tools): …` / `docs(v2-tools): …`, one per task at least, ending with the implementer's model trailer, e.g. `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

These are the five failure modes of spec §10, most likely first. Each is pinned by a test in the task that owns the code.

1. **A page reloads by surprise** when the user switches tabs or workspaces, opens a dialog or the palette, or resizes the window, losing what they typed. Expected: the same engine lives on, with no second `load`.
   - Task 13: "Review Focus 1: switching tabs, opening the palette and resizing keep the same page — one engine, one view, one load".
   - Task 10: "closing the dock keeps the pages (D5)" and "the page on screen is never the one unloaded".
   - Task 6 (real WebKit): "the page stays loaded when its view leaves and comes back".
2. **ShellX shortcuts while a page has the keyboard (macOS).** ⌘T, ⌘W, ⌘1…9, ⌘⇧E, ⌘⇧P and ⌘⇧B run; ⌘C/⌘V/⌘A/⌘X/⌘Z stay with the page; the user's own keys and a sequence's first step count.
   - Task 5: "the forwarded chords are the window keymap (Review Focus 2) …", "the user's own keys count, and a sequence's first step forwards (D10)", "every forwarded chord reads back as the chord it came from".
   - Task 10: "a reload of the keys reaches every live page (D10)".
   - Task 13: "a forwarded ⌘T runs New tab (D10)".
3. **The server is not running yet** (the most common case). Expected: the page appears by itself once the server is up, within 3 s.
   - Task 10: "refused: retries after 1, 2, 4, 8 then every 10 s, only while shown; the page shows once the server is up (D13, Review Focus 3)" and the R9 knock test.
   - Task 13: "the bar follows the page: … the refused panel …".
   - Task 6 (real WebKit): "a refused port, then the server comes up (D13)".
4. **An old build reads the new data.** A `layout.json` with `toolDock`, settings with `workspace_tools`.
   - Task 9: the frozen V1 and V2.0 parsers keep every tab, ignore `toolDock` and write no `.bak`.
   - Task 1: "Review Focus 4: tools live in their own key; the workspace list an older build reads and rewrites is never touched (D2)".
5. **Odd URLs in the field**: `javascript:alert(1)`, `http://user:pass@host`, `localhost:5173` without a scheme, `[::1]:8080`, leading spaces. Expected: normalised correctly or refused with a clear line, and a strange scheme never loads.
   - Task 1: the `parseToolUrl (D1, Review Focus 5)` table.
   - Task 5: "the top frame: any http/https page, about:blank; mail and phone outside; anything else blocked (D9, Review Focus 5)".
   - Task 12: "a bad URL says why after Add, and adds nothing (§4.2)".

---

## File Structure

All desktop paths are under `apps/desktop/`.

| File | Responsibility | Task |
|---|---|---|
| Create `lib/src/tools/tool_entry.dart`, `lib/src/tools/tool_registry.dart`; Modify `lib/src/platform/settings_store.dart`, `test/agent/settings_ownership_test.dart`; Create `test/tools/tool_entry_test.dart`, `test/tools/tool_registry_test.dart` | the tool model, URL rules, the registry in `workspace_tools` (shared with V2-4) | 1 |
| Modify `lib/l10n/app_en.arb`, `lib/l10n/app_vi.arb` (+ generated `lib/l10n/app_localizations*.dart`); Create `test/l10n/tool_strings_test.dart` | every V2-3 string, EN + VI | 2 |
| Modify `pubspec.yaml`, `macos/Runner/Info.plist`, `macos/Runner/MainFlutterWindow.swift`, `macos/Runner.xcodeproj/project.pbxproj` (+ generated `macos/Flutter/GeneratedPluginRegistrant.swift`, `macos/Podfile.lock`); Create `lib/src/browser/browser_url.dart`, `lib/src/browser/browser_engine.dart`, `lib/src/browser/engines/wk_webview_engine.dart`, `macos/Runner/BrowserNative.swift`, `test/support/fake_browser_engine.dart`, `test/browser/browser_url_test.dart`, `test/browser/wk_webview_engine_test.dart` | A6's engine, without the bridge | 3 |
| Modify `lib/src/ui/terminal/terminal_intents.dart`, `lib/src/config/keybind_actions.dart`, `lib/src/config/keybindings.dart`, `lib/src/ui/config/action_labels.dart`, `lib/src/ui/terminal/shortcut_labels.dart`, `test/config/keybindings_test.dart`, `test/ui/shortcut_golden_test.dart` | `toggle_tools` (⌘⇧B), `add_tool`, `OpenToolIntent` | 4 |
| Create `lib/src/tools/tool_navigation.dart`, `lib/src/tools/tool_keys.dart`; Modify `lib/src/browser/engines/wk_webview_engine.dart`, `macos/Runner/BrowserNative.swift`, `lib/src/ui/terminal/key_sequence.dart`, `test/browser/wk_webview_engine_test.dart`; Create `test/tools/tool_navigation_test.dart`, `test/tools/tool_keys_test.dart`, `test/tools/tool_no_bridge_test.dart` | review and hardening of the macOS engine (D9, D10, D13, D16) | 5 |
| Create `integration_test/tool_engine_test.dart` | the real engine in an isolated build (recipe) | 6 |
| Modify `pubspec.yaml` (+ generated `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`), `lib/src/config/shellx_config.dart`, `lib/src/config/config_show.dart`, `lib/src/config/config_template.dart`, `lib/src/config/settings_schema.dart`, `lib/src/ui/settings/settings_values.dart`, `test/config/settings_schema_test.dart`; Create `lib/src/browser/engines/win_floating_engine.dart`, `lib/src/tools/tool_embed.dart`, `test/browser/win_floating_engine_test.dart`, `test/tools/tool_embed_test.dart` | the Windows engine, `tool-embed` | 7 |
| Create `lib/src/tools/tool_dock_state.dart`, `lib/src/tools/tool_dock.dart`, `test/tools/tool_dock_state_test.dart`, `test/tools/tool_dock_test.dart` | per-workspace dock state and controller | 8 |
| Modify `lib/src/restore/restore_snapshot.dart`, `lib/src/restore/restore_capture.dart`, `lib/src/restore/restore_persistence.dart`; Create `test/restore/v2_0/restore_snapshot_v2_0.dart`, `test/restore/tool_dock_restore_test.dart` | `toolDock` in `layout.json`, compatibility | 9 |
| Create `lib/src/tools/tool_page.dart`, `lib/src/tools/tool_pages.dart`, `test/tools/tool_page_test.dart`, `test/tools/tool_pages_test.dart`; Modify `lib/src/terminal/terminal_tabs.dart`, `lib/src/ui/terminal/terminal_overlays.dart` | live pages: retry, knock, crash, dialogs, LRU of 8 | 10 |
| Modify `packages/shellx_agent/lib/src/context/listening_ports.dart`; Create `packages/shellx_agent/test/context/listening_under_test.dart`; Modify `lib/src/ai/ai_runtimes.dart`; Create `lib/src/tools/tool_ports.dart`, `test/tools/tool_ports_test.dart` | port suggestions (D12) | 11 |
| Create `lib/src/ui/tools/tool_dialogs.dart`, `lib/src/ui/tools/tool_actions.dart`, `test/support/tool_harness.dart`, `test/ui/tools/tool_dialog_test.dart`, `test/platform/url_opener_mail_test.dart`; Modify `lib/src/platform/url_opener.dart`, `test/support/fakes.dart` | the Add/Edit dialog, JS dialogs, tool commands | 12 |
| Create `lib/src/ui/tools/tool_bar.dart`, `lib/src/ui/tools/tool_dock_view.dart`, `lib/src/ui/tools/tool_area.dart`, `test/ui/tools/tool_dock_ui_test.dart`, `test/ui/tools/tool_ai_header_test.dart`; Modify `lib/src/ui/terminal/terminal_workspace_page.dart`, `lib/src/ui/ai/ai_header.dart`, `lib/src/ui/ai/ai_pane_view.dart`, `lib/src/ui/terminal/terminal_workspace_notices.dart` | the dock in the window, keys, palette, AI header | 13 |
| Create `lib/src/ui/tools/tool_sidebar_group.dart`, `test/ui/tools/tool_sidebar_test.dart`; Modify `lib/src/ui/terminal/session_sidebar.dart` | the sidebar group and "Add tool" | 14 |
| Create `lib/src/ui/tools/tool_project_list.dart`, `test/ui/tools/tool_settings_test.dart`; Modify `lib/src/ui/settings/pages/projects_page.dart` | Settings › Projects | 15 |
| Create `docs/superpowers/ledgers/v2-tools.md` (Task 1), then append | baseline, rulings, engine review, integration result, final results, manual checks | 1, 5, 6, 16 |

---


### Task 1: The tool model and the registry (shared with V2-4)

A tool is a name and an `http(s)` URL in a workspace, with a phone flag (D1). This task writes the pure model, the URL rules, and the registry that keeps every tool in its own settings key, `workspace_tools` (D2).
- **Not in the workspace JSON:** an older build rewrites that JSON without the keys it does not know.
- **Shared with V2-4:** the V2-4 plan consumes these files exactly as written here, so the names and types below are fixed.
- **Review Focus 4 and 5:** the URL table and the key isolation are pinned here.

**Files:**
- Create: `apps/desktop/lib/src/tools/tool_entry.dart`
- Create: `apps/desktop/lib/src/tools/tool_registry.dart`
- Modify: `apps/desktop/lib/src/platform/settings_store.dart` (`SettingKeys.workspaceTools`, in `all` and `UiSettingKeys`)
- Modify: `apps/desktop/test/agent/settings_ownership_test.dart` (35 keys)
- Test: `apps/desktop/test/tools/tool_entry_test.dart`, `apps/desktop/test/tools/tool_registry_test.dart`
- Create: `docs/superpowers/ledgers/v2-tools.md` (the baseline and the rulings)

**Interfaces:**
- Consumes (existing):
  - `settingsStoreProvider` (`lib/src/terminal/sidebar_workspaces.dart`);
  - `SettingsStore.getStrings(String key)` / `setStrings(String key, List<String> values)` (`lib/src/platform/settings_store.dart`).
- Produces, `lib/src/tools/tool_entry.dart` (pure Dart):
  - constants: `const int kMaxToolsPerWorkspace = 50;`, `const int kMaxToolNameLength = 60;`, `const int kMaxToolUrlLength = 2048;`, `final RegExp kToolIdPattern = RegExp(r'^[a-z0-9]{10}$');`
  - `enum ToolUrlError { notHttp, userinfo, backslash, noHost, badPort, tooLong }`
  - `sealed class ToolUrlResult`, `final class ToolUrlOk extends ToolUrlResult { final String url; }` (`toString()` → `ToolUrlOk(…)`), `final class ToolUrlBad extends ToolUrlResult { final ToolUrlError error; }`
  - `ToolUrlResult parseToolUrl(String input)`, `bool isLocalToolHost(String host)`, `String toolNameFor(String name, String url)` (a blank name → `host:port`).
  - `final class ToolEntry`:
    - `const ToolEntry({required String id, required String ws, required String name, required String url, bool phone = false})`;
    - getters: `Uri uri`, `String origin` (port always written), `int port`, `String hostPort`, `bool isLocal`, `bool unencrypted`, `bool phoneAllowed`, `bool phoneOn`;
    - `ToolEntry copyWith({String? name, String? url, bool? phone})`, `Map<String, Object?> toJson()`, `static ToolEntry? fromJson(Object? json)` (never throws);
    - `toString()` → `'ToolEntry(…)'`.
- Produces, `lib/src/tools/tool_registry.dart`:
  - `final toolIdSourceProvider = Provider<String Function()>(…)`;
  - `final toolRegistryProvider = NotifierProvider<ToolRegistry, List<ToolEntry>>(ToolRegistry.new);`
  - `class ToolRegistry extends Notifier<List<ToolEntry>>`:
    - `ToolEntry? add({required String ws, required String name, required String url, bool phone = false})`;
    - `void update(ToolEntry entry)`, `void remove(String id)`, `void removeWorkspace(String ws)`;
    - `ToolEntry? byId(String id)`, `List<ToolEntry> inWorkspace(String ws)`.
- Produces, `lib/src/platform/settings_store.dart`: `SettingKeys.workspaceTools = 'workspace_tools'`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/tools/tool_entry_test.dart`:

````dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';

String? ok(String input) => switch (parseToolUrl(input)) {
  ToolUrlOk(:final url) => url,
  ToolUrlBad() => null,
};

ToolUrlError? bad(String input) => switch (parseToolUrl(input)) {
  ToolUrlOk() => null,
  ToolUrlBad(:final error) => error,
};

ToolEntry tool(String url, {bool phone = false}) => ToolEntry(
  id: 'abcde12345',
  ws: 'default',
  name: 'Bảng việc',
  url: (parseToolUrl(url) as ToolUrlOk).url,
  phone: phone,
);

void main() {
  group('parseToolUrl (D1, Review Focus 5)', () {
    final good = <String, String>{
      'http://localhost:5173': 'http://localhost:5173/',
      'localhost:5173': 'http://localhost:5173/',
      '  localhost:5173/board?x=1#top  ': 'http://localhost:5173/board?x=1',
      'HTTPS://Example.COM/A': 'https://example.com/A',
      '[::1]:8080': 'http://[::1]:8080/',
      'http://[::1]:8080/x': 'http://[::1]:8080/x',
      '127.0.0.1:3000': 'http://127.0.0.1:3000/',
      'nas.lan:8080/admin': 'http://nas.lan:8080/admin',
      'grafana.example.com': 'http://grafana.example.com/',
      'http://localhost': 'http://localhost/',
      'http://localhost:5173/a b': 'http://localhost:5173/a%20b',
      'http://@localhost:5173/': 'http://localhost:5173/',
      'http://localhost:05173': 'http://localhost:5173/',
      'my_app:3000': 'http://my_app:3000/',
      'http://db_admin.lan/': 'http://db_admin.lan/',
    };
    good.forEach((input, expected) {
      test('"$input" → $expected', () => expect(ok(input), expected));
    });
    final refused = <String, ToolUrlError>{
      'javascript:alert(1)': ToolUrlError.notHttp,
      'file:///etc/passwd': ToolUrlError.notHttp,
      'data:text/html,hi': ToolUrlError.notHttp,
      'mailto:a@b.c': ToolUrlError.notHttp,
      'ftp://host/x': ToolUrlError.notHttp,
      'http://user:pass@localhost:5173/': ToolUrlError.userinfo,
      'https://google.com@evil.com/': ToolUrlError.userinfo,
      r'http://evil.com\@localhost': ToolUrlError.backslash,
      r'localhost:5173\x': ToolUrlError.backslash,
      '': ToolUrlError.noHost,
      '   ': ToolUrlError.noHost,
      'http://': ToolUrlError.noHost,
      'http:///x': ToolUrlError.noHost,
      'http://local host:5173': ToolUrlError.noHost,
      'http://exa\u0000mple.com/': ToolUrlError.noHost,
      'http://bücher.de/': ToolUrlError.noHost,
      'localhost:0': ToolUrlError.badPort,
      'http://localhost:0/': ToolUrlError.badPort,
      'localhost:65536': ToolUrlError.badPort,
      'http://localhost:99999': ToolUrlError.badPort,
      'http://localhost:abc': ToolUrlError.noHost,
    };
    refused.forEach((input, error) {
      test('"$input" → $error', () => expect(bad(input), error));
    });
    test('longer than 2048 characters is refused', () {
      expect(bad('http://a.com/${'x' * 2048}'), ToolUrlError.tooLong);
      expect(ok('http://a.com/${'x' * 2000}'), isNotNull);
    });
    test('never a scheme other than http or https', () {
      for (final input in [
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        ' vbscript:x',
        'about:blank',
        'chrome://settings',
        'shellx://x',
      ]) {
        final url = ok(input);
        expect(url == null || url.startsWith('http'), isTrue, reason: input);
      }
    });
    test('toString never shows the URL', () {
      expect(
        parseToolUrl('http://secret.example/x').toString(),
        'ToolUrlOk(…)',
      );
      expect(parseToolUrl('ftp://x').toString(), 'ToolUrlBad(notHttp)');
    });
  });

  group('ToolEntry', () {
    test('origin, port and host:port write the port (D11)', () {
      expect(tool('localhost:5173').origin, 'http://localhost:5173');
      expect(tool('http://localhost/').origin, 'http://localhost:80');
      expect(tool('https://example.com/x').origin, 'https://example.com:443');
      expect(tool('[::1]:8080').origin, 'http://[::1]:8080');
      expect(tool('[::1]:8080').hostPort, '[::1]:8080');
      expect(tool('https://example.com/x').port, 443);
      expect(tool('localhost:4000').hostPort, 'localhost:4000');
    });

    test('isLocal is A6 D11 local class (D11)', () {
      for (final local in [
        'localhost:1',
        'app.localhost:1',
        '127.0.0.1:1',
        '127.8.9.10:1',
        '[::1]:1',
        '0.0.0.0:1',
        'https://localhost/',
      ]) {
        expect(tool(local).isLocal, isTrue, reason: local);
      }
      for (final remote in [
        'example.com',
        '192.168.1.20:8080',
        '128.0.0.1',
        'localhost.example.com',
        'http://127.0.0.256/',
      ]) {
        expect(tool(remote).isLocal, isFalse, reason: remote);
      }
      expect(tool('example.com').unencrypted, isTrue);
      expect(tool('https://example.com').unencrypted, isFalse);
      expect(tool('localhost:5173').unencrypted, isFalse);
    });

    test('phoneAllowed: http on localhost, 127.0.0.1 or ::1 only (D15)', () {
      for (final allowed in [
        'localhost:5173',
        '127.0.0.1:3000',
        '[::1]:8080',
      ]) {
        expect(tool(allowed).phoneAllowed, isTrue, reason: allowed);
      }
      for (final refused in [
        'https://localhost:5173',
        'app.localhost:5173',
        '127.0.0.2:3000',
        '0.0.0.0:3000',
        '192.168.1.2:80',
        'example.com',
      ]) {
        expect(tool(refused).phoneAllowed, isFalse, reason: refused);
      }
      expect(tool('localhost:1', phone: true).phoneOn, isTrue);
      expect(tool('localhost:1').phoneOn, isFalse);
      expect(tool('https://localhost:1', phone: true).phoneOn, isFalse);
    });

    test('toJson and fromJson round-trip', () {
      final t = tool('localhost:5173/board', phone: true);
      expect(t.toJson(), {
        'id': 'abcde12345',
        'ws': 'default',
        'name': 'Bảng việc',
        'url': 'http://localhost:5173/board',
        'phone': true,
      });
      final back = ToolEntry.fromJson(t.toJson())!;
      expect(
        [back.id, back.ws, back.name, back.url, back.phone],
        [t.id, t.ws, t.name, t.url, t.phone],
      );
    });

    test('fromJson never throws; a bad entry is null (D2, §8)', () {
      final valid = tool('localhost:5173').toJson();
      final cases = <Object?>[
        null,
        42,
        'x',
        <Object?>[],
        {...valid, 'id': 'short'},
        {...valid, 'id': 'ABCDE12345'},
        {...valid, 'id': 7},
        {...valid, 'ws': ''},
        {...valid, 'ws': 'w' * 65},
        {...valid, 'ws': 3},
        {...valid, 'url': 'javascript:alert(1)'},
        {...valid, 'url': 'http://u:p@h/'},
        {...valid, 'url': null},
        <Object?, Object?>{1: 2},
      ];
      for (final c in cases) {
        expect(() => ToolEntry.fromJson(c), returnsNormally, reason: '$c');
        expect(ToolEntry.fromJson(c), isNull, reason: '$c');
      }
    });

    test('fromJson repairs a damaged name or flag', () {
      final valid = tool('localhost:5173').toJson();
      expect(
        ToolEntry.fromJson({...valid, 'name': ''})!.name,
        'localhost:5173',
      );
      expect(ToolEntry.fromJson({...valid, 'name': 5})!.name, 'localhost:5173');
      expect(
        ToolEntry.fromJson({...valid, 'name': 'n' * 80})!.name,
        'n' * kMaxToolNameLength,
      );
      expect(ToolEntry.fromJson({...valid, 'phone': 'yes'})!.phone, isFalse);
      expect(
        ToolEntry.fromJson({...valid, 'url': 'localhost:5173#x'})!.url,
        'http://localhost:5173/',
      );
    });

    test('toolNameFor: a blank name is host:port (D1)', () {
      expect(toolNameFor('  ', 'http://localhost:5173/'), 'localhost:5173');
      expect(toolNameFor(' Bảng việc ', 'http://localhost:5173/'), 'Bảng việc');
    });

    test('toString never shows the name or the URL (D24)', () {
      final t = tool('http://secret.example:4000/token=abc');
      expect(t.toString(), 'ToolEntry(…)');
    });
  });
}
````

`apps/desktop/test/tools/tool_registry_test.dart`:

````dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

void main() {
  late InMemorySettingsStore settings;
  late ProviderContainer c;
  var next = 0;

  ProviderContainer boot() => ProviderContainer.test(
    overrides: [
      settingsStoreProvider.overrideWithValue(settings),
      toolIdSourceProvider.overrideWithValue(
        () => 'tool${(next++).toString().padLeft(6, '0')}',
      ),
    ],
  );

  ToolRegistry registry() => c.read(toolRegistryProvider.notifier);
  List<ToolEntry> tools() => c.read(toolRegistryProvider);
  List<Map<String, Object?>> stored() => [
    for (final s in settings.getStrings(SettingKeys.workspaceTools))
      jsonDecode(s) as Map<String, Object?>,
  ];

  setUp(() {
    next = 0;
    settings = InMemorySettingsStore();
    c = boot();
  });

  test('add normalises the URL, names a blank tool host:port, saves', () async {
    final t = registry().add(
      ws: 'default',
      name: '  ',
      url: ' localhost:5173 ',
    )!;
    expect(t.id, 'tool000000');
    expect(t.url, 'http://localhost:5173/');
    expect(t.name, 'localhost:5173');
    expect(tools(), [t]);
    await Future<void>.delayed(Duration.zero);
    expect(stored(), [t.toJson()]);
  });

  test('add refuses a bad URL and a full workspace (D2)', () {
    expect(
      registry().add(ws: 'default', name: 'x', url: 'javascript:alert(1)'),
      isNull,
    );
    expect(
      registry().add(ws: 'default', name: 'x', url: 'http://u:p@h/'),
      isNull,
    );
    expect(registry().add(ws: '', name: 'x', url: 'localhost:1'), isNull);
    for (var i = 0; i < kMaxToolsPerWorkspace; i++) {
      expect(
        registry().add(ws: 'w1', name: '$i', url: 'localhost:${i + 1}'),
        isNotNull,
      );
    }
    expect(
      registry().add(ws: 'w1', name: 'one more', url: 'localhost:9'),
      isNull,
    );
    expect(
      registry().add(ws: 'w2', name: 'elsewhere', url: 'localhost:9'),
      isNotNull,
    );
    expect(registry().inWorkspace('w1'), hasLength(kMaxToolsPerWorkspace));
  });

  test('the phone flag holds only for a tool a phone may open (D15)', () {
    final local = registry().add(
      ws: 'default',
      name: 'a',
      url: 'localhost:1',
      phone: true,
    )!;
    final secure = registry().add(
      ws: 'default',
      name: 'b',
      url: 'https://localhost:1',
      phone: true,
    )!;
    final remote = registry().add(
      ws: 'default',
      name: 'c',
      url: 'nas.lan:80',
      phone: true,
    )!;
    expect([local.phone, secure.phone, remote.phone], [true, false, false]);
  });

  test('update keeps the id, workspace and place; re-validates (D23)', () {
    final a = registry().add(ws: 'w1', name: 'A', url: 'localhost:1')!;
    final b = registry().add(ws: 'w1', name: 'B', url: 'localhost:2')!;
    registry().update(
      ToolEntry(
        id: a.id,
        ws: 'other',
        name: ' Bảng ',
        url: 'localhost:3#x',
        phone: true,
      ),
    );
    final moved = registry().byId(a.id)!;
    expect(
      [moved.ws, moved.name, moved.url, moved.phone],
      ['w1', 'Bảng', 'http://localhost:3/', true],
    );
    expect(tools().map((t) => t.id), [a.id, b.id]);
    registry().update(a.copyWith(url: 'file:///etc/passwd'));
    expect(registry().byId(a.id)!.url, 'http://localhost:3/');
    registry().update(a.copyWith(url: 'https://example.com', phone: true));
    expect(registry().byId(a.id)!.phone, isFalse);
    registry().update(
      ToolEntry(id: 'zzzzzzzzzz', ws: 'w1', name: 'n', url: 'localhost:1'),
    );
    expect(tools(), hasLength(2));
  });

  test('remove and removeWorkspace (D2, D23)', () {
    final a = registry().add(ws: 'w1', name: 'A', url: 'localhost:1')!;
    registry().add(ws: 'w2', name: 'B', url: 'localhost:2');
    registry().add(ws: 'w2', name: 'C', url: 'localhost:3');
    registry().remove(a.id);
    expect(registry().byId(a.id), isNull);
    registry().removeWorkspace('w2');
    expect(tools(), isEmpty);
    registry().remove('nope');
    registry().removeWorkspace('nope');
  });

  test('a restart reads back what was saved', () async {
    final a = registry().add(
      ws: 'w1',
      name: 'A',
      url: 'localhost:1',
      phone: true,
    )!;
    final b = registry().add(ws: 'w2', name: 'B', url: 'https://x.dev/app')!;
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    c = boot();
    expect(tools().map((t) => t.toJson()), [a.toJson(), b.toJson()]);
  });

  test(
    'a damaged, duplicate or extra entry goes; the others stay (§8)',
    () async {
      final good = ToolEntry(
        id: 'aaaaaaaaaa',
        ws: 'w1',
        name: 'A',
        url: 'http://localhost:1/',
      );
      await settings.setStrings(SettingKeys.workspaceTools, [
        '{not json',
        jsonEncode({'id': 'bad'}),
        jsonEncode(good.toJson()),
        jsonEncode(good.toJson()),
        for (var i = 0; i < kMaxToolsPerWorkspace + 2; i++)
          jsonEncode(
            ToolEntry(
              id: 'b${i.toString().padLeft(9, '0')}',
              ws: 'w2',
              name: 'n',
              url: 'http://localhost:${i + 1}/',
            ).toJson(),
          ),
      ]);
      c.dispose();
      c = boot();
      expect(registry().inWorkspace('w1').map((t) => t.id), ['aaaaaaaaaa']);
      expect(registry().inWorkspace('w2'), hasLength(kMaxToolsPerWorkspace));
    },
  );

  test('a failed save is not an error', () async {
    settings.fail = true;
    expect(registry().add(ws: 'w1', name: 'A', url: 'localhost:1'), isNotNull);
    await Future<void>.delayed(Duration.zero);
  });

  test('toString never shows a tool', () {
    registry().add(ws: 'w1', name: 'Secret', url: 'localhost:1');
    expect(registry().toString(), 'ToolRegistry(…)');
  });

  test('Review Focus 4: tools live in their own key; the workspace list an '
      'older build reads and rewrites is never touched (D2)', () async {
    await settings.setStrings(SettingKeys.terminalWorkspaces, [
      '{"id":"default","collapsed":false}',
    ]);
    final a = registry().add(ws: 'default', name: 'A', url: 'localhost:1')!;
    registry().update(a.copyWith(name: 'B'));
    registry().remove(a.id);
    await Future<void>.delayed(Duration.zero);
    expect(settings.getStrings(SettingKeys.terminalWorkspaces), [
      '{"id":"default","collapsed":false}',
    ]);
    expect(SettingKeys.all, contains(SettingKeys.workspaceTools));
    expect(UiSettingKeys.all, contains(SettingKeys.workspaceTools));
    expect(DaemonSettingKeys.all, isNot(contains(SettingKeys.workspaceTools)));
  });
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_entry_test.dart test/tools/tool_registry_test.dart
````

Expected: compilation fails, `Error when reading 'lib/src/tools/tool_entry.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/tools/tool_entry.dart`:

````dart
/// V2-3 D1, D2, D11, D15: a personal tool — a name and an http(s) URL in a
/// workspace — and the rules its URL follows. Pure Dart: the registry, the
/// dock, the restore file and V2-4's phone list all read it.
library;

/// D2: at most this many tools per workspace.
const int kMaxToolsPerWorkspace = 50;

/// D2: a tool's name, in characters (runes).
const int kMaxToolNameLength = 60;

/// D2: a tool's URL, in characters, after [parseToolUrl] normalised it.
const int kMaxToolUrlLength = 2048;

/// D2: `id` is 10 characters `[a-z0-9]`.
final RegExp kToolIdPattern = RegExp(r'^[a-z0-9]{10}$');

/// Same bound as A2's stored workspace ids (`Workspace.decode`).
const int _maxWorkspaceId = 64;

final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');
final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');

/// `localhost:5173`, `app.local:8080/x`: a host and a port, which also reads
/// as a scheme (`localhost:`), so it is taken as "no scheme".
final RegExp _hostPort = RegExp(r'^[A-Za-z0-9._-]+:\d{1,5}(?:[/?#].*)?$');
final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// A registered host name: letters, digits, dots, dashes and underscores
/// (Docker service names); a percent sign means Dart encoded a space or a
/// non-ASCII letter into it.
final RegExp _hostName = RegExp(r'^[a-z0-9._-]+$');

/// Why [parseToolUrl] refused a URL (§4.2 shows a red line for each).
enum ToolUrlError { notHttp, userinfo, backslash, noHost, badPort, tooLong }

/// [parseToolUrl]'s answer: [ToolUrlOk] with the normalised URL, or
/// [ToolUrlBad] with the reason.
sealed class ToolUrlResult {
  const ToolUrlResult();
}

final class ToolUrlOk extends ToolUrlResult {
  const ToolUrlOk(this.url);

  /// http/https, a host, no user information, no fragment, the path and
  /// query kept (the page the tool starts on), "/" for an empty path.
  final String url;

  @override
  String toString() => 'ToolUrlOk(…)';
}

final class ToolUrlBad extends ToolUrlResult {
  const ToolUrlBad(this.error);
  final ToolUrlError error;

  @override
  String toString() => 'ToolUrlBad(${error.name})';
}

/// D1: what the URL field accepts. Leading and trailing spaces go; a
/// missing scheme becomes `http://`; only http and https load (never
/// `javascript:`, `file:`, `data:`); no `user:pass@`; no `\` (a browser
/// reads it as `/`, Dart does not); a host; a port 1–65535; the fragment
/// goes; at most [kMaxToolUrlLength] characters.
ToolUrlResult parseToolUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return const ToolUrlBad(ToolUrlError.noHost);
  if (text.length > kMaxToolUrlLength) {
    return const ToolUrlBad(ToolUrlError.tooLong);
  }
  if (text.contains(r'\')) return const ToolUrlBad(ToolUrlError.backslash);
  if (_control.hasMatch(text)) return const ToolUrlBad(ToolUrlError.noHost);
  final scheme = _scheme.firstMatch(text)?.group(1)?.toLowerCase();
  final String full;
  if (scheme == 'http' || scheme == 'https') {
    full = text;
  } else if (scheme == null || _hostPort.hasMatch(text)) {
    full = 'http://$text';
  } else {
    return const ToolUrlBad(ToolUrlError.notHttp);
  }
  final Uri uri;
  try {
    uri = Uri.parse(full);
  } on Object {
    // FormatException (a bad port), StateError ("http://" with no host).
    return const ToolUrlBad(ToolUrlError.noHost);
  }
  if (uri.userInfo.isNotEmpty) return const ToolUrlBad(ToolUrlError.userinfo);
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return const ToolUrlBad(ToolUrlError.noHost);
  if (!host.contains(':') && !_hostName.hasMatch(host)) {
    return const ToolUrlBad(ToolUrlError.noHost);
  }
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
    return const ToolUrlBad(ToolUrlError.badPort);
  }
  final clean = Uri(
    scheme: uri.scheme.toLowerCase(),
    host: host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.isEmpty ? '/' : uri.path,
    query: uri.hasQuery ? uri.query : null,
  ).toString();
  if (clean.length > kMaxToolUrlLength) {
    return const ToolUrlBad(ToolUrlError.tooLong);
  }
  return ToolUrlOk(clean);
}

/// D11: "On this computer" — `localhost`, `*.localhost`, 127.0.0.0/8, `::1`
/// and `0.0.0.0` (A6 D11's local class). [host] as `Uri.host` gives it
/// (IPv6 without brackets).
bool isLocalToolHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  if (h == '::1' || h == '0.0.0.0') return true;
  final v4 = _ipv4.firstMatch(h);
  if (v4 == null || v4.group(1) != '127') return false;
  return [2, 3, 4].every((i) => int.parse(v4.group(i)!) <= 255);
}

/// D15 / V2-4 E1: the hosts a phone may reach a tool on.
const Set<String> _phoneHosts = {'localhost', '127.0.0.1', '::1'};

/// A user-perceived name cut to [kMaxToolNameLength] runes, trimmed.
String _cleanName(String text) {
  final trimmed = text.replaceAll(_control, ' ').trim();
  final runes = trimmed.runes;
  return runes.length <= kMaxToolNameLength
      ? trimmed
      : String.fromCharCodes(runes.take(kMaxToolNameLength)).trim();
}

/// V2-3 D1/D2: a personal tool — a name and an http(s) URL in a workspace.
final class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.ws,
    required this.name,
    required this.url,
    this.phone = false,
  });

  /// 10 chars `[a-z0-9]`, stable for the tool's life.
  final String id;

  /// The workspace id (`Workspace.id`).
  final String ws;

  /// ≤ 60 chars, never empty.
  final String name;

  /// Normalised by [parseToolUrl]: http/https, a host, no userinfo, no
  /// fragment.
  final String url;

  /// D15: "Allow on phone" (only [phoneOn] counts).
  final bool phone;

  Uri get uri => Uri.parse(url);

  /// `scheme://host:port`, the port always written (`http://[::1]:8080`).
  String get origin {
    final u = uri;
    return '${u.scheme}://${_hostForUrl(u.host)}:${u.port}';
  }

  /// The effective port (80 / 443 when the URL has none).
  int get port => uri.port;

  /// D11 bar and sidebar: `localhost:5173`, `[::1]:8080`.
  String get hostPort => '${_hostForUrl(uri.host)}:$port';

  /// D11: "On this computer".
  bool get isLocal => isLocalToolHost(uri.host);

  /// D11: `http` not on this computer adds "not encrypted".
  bool get unencrypted => uri.scheme == 'http' && !isLocal;

  /// D15: http, and the host is `localhost`, `127.0.0.1` or `::1`.
  bool get phoneAllowed =>
      uri.scheme == 'http' && _phoneHosts.contains(uri.host.toLowerCase());

  bool get phoneOn => phone && phoneAllowed;

  ToolEntry copyWith({String? name, String? url, bool? phone}) => ToolEntry(
    id: id,
    ws: ws,
    name: name ?? this.name,
    url: url ?? this.url,
    phone: phone ?? this.phone,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'ws': ws,
    'name': name,
    'url': url,
    'phone': phone,
  };

  /// Never throws; null for an entry that is not a tool (bad id, workspace
  /// or URL). A damaged name or flag is repaired: an empty name becomes
  /// `host:port`, a long one is cut, a flag that is not `true` is off.
  static ToolEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final ws = json['ws'];
    final url = json['url'];
    if (id is! String || !kToolIdPattern.hasMatch(id)) return null;
    if (ws is! String || ws.isEmpty || ws.length > _maxWorkspaceId) {
      return null;
    }
    if (url is! String) return null;
    final parsed = parseToolUrl(url);
    if (parsed is! ToolUrlOk) return null;
    final rawName = json['name'];
    final draft = ToolEntry(id: id, ws: ws, name: '', url: parsed.url);
    final name = rawName is String ? _cleanName(rawName) : '';
    return ToolEntry(
      id: id,
      ws: ws,
      name: name.isEmpty ? draft.hostPort : name,
      url: parsed.url,
      phone: json['phone'] == true,
    );
  }

  /// D24: never the name or the URL.
  @override
  String toString() => 'ToolEntry(…)';
}

/// The name a tool gets: [name] cleaned, or `host:port` of [url] when it is
/// blank (D1). [url] is already normalised.
String toolNameFor(String name, String url) {
  final clean = _cleanName(name);
  if (clean.isNotEmpty) return clean;
  return ToolEntry(id: '', ws: '', name: '', url: url).hostPort;
}

String _hostForUrl(String host) => host.contains(':') ? '[$host]' : host;
````

`apps/desktop/lib/src/tools/tool_registry.dart`:

````dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'tool_entry.dart';

/// D2: a new tool's id — 10 random `[a-z0-9]`. Tests swap it for a
/// counter.
final toolIdSourceProvider = Provider<String Function()>((ref) {
  final random = Random.secure();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return () => List.generate(
    10,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
});

final toolRegistryProvider = NotifierProvider<ToolRegistry, List<ToolEntry>>(
  ToolRegistry.new,
);

/// V2-3 D2: every tool of every workspace, in the order they were added,
/// kept in [SettingKeys.workspaceTools] (one JSON object per element, a
/// window-owned key) — never inside the workspace JSON, which an older
/// build rewrites without the keys it does not know.
class ToolRegistry extends Notifier<List<ToolEntry>> {
  @override
  List<ToolEntry> build() {
    final stored = ref
        .watch(settingsStoreProvider)
        .getStrings(SettingKeys.workspaceTools);
    final result = <ToolEntry>[];
    final ids = <String>{};
    final perWorkspace = <String, int>{};
    for (final text in stored) {
      Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        continue; // a damaged entry goes, the others stay (§8)
      }
      final tool = ToolEntry.fromJson(json);
      if (tool == null || !ids.add(tool.id)) continue;
      final count = perWorkspace[tool.ws] ?? 0;
      if (count >= kMaxToolsPerWorkspace) continue;
      perWorkspace[tool.ws] = count + 1;
      result.add(tool);
    }
    return List.unmodifiable(result);
  }

  /// D1, D2, D15: a new tool at the end of [ws]'s list. Null when [url]
  /// is not a tool URL ([parseToolUrl]) or [ws] already has
  /// [kMaxToolsPerWorkspace] tools. A blank [name] becomes `host:port`;
  /// [phone] holds only for a tool that may open on a phone.
  ToolEntry? add({
    required String ws,
    required String name,
    required String url,
    bool phone = false,
  }) {
    if (ws.isEmpty || inWorkspace(ws).length >= kMaxToolsPerWorkspace) {
      return null;
    }
    final parsed = parseToolUrl(url);
    if (parsed is! ToolUrlOk) return null;
    final draft = ToolEntry(
      id: _newId(),
      ws: ws,
      name: toolNameFor(name, parsed.url),
      url: parsed.url,
    );
    final tool = draft.copyWith(phone: phone && draft.phoneAllowed);
    state = List.unmodifiable([...state, tool]);
    _save();
    return tool;
  }

  /// D23: the name, URL and phone flag of the tool with [entry]'s id; its
  /// workspace and place stay. Nothing for an unknown id or a URL that is
  /// not a tool URL.
  void update(ToolEntry entry) {
    final at = state.indexWhere((t) => t.id == entry.id);
    if (at < 0) return;
    final parsed = parseToolUrl(entry.url);
    if (parsed is! ToolUrlOk) return;
    final old = state[at];
    final next = ToolEntry(
      id: old.id,
      ws: old.ws,
      name: toolNameFor(entry.name, parsed.url),
      url: parsed.url,
    );
    final tool = next.copyWith(phone: entry.phone && next.phoneAllowed);
    if (tool.name == old.name &&
        tool.url == old.url &&
        tool.phone == old.phone) {
      return;
    }
    state = List.unmodifiable([...state]..[at] = tool);
    _save();
  }

  void remove(String id) {
    if (!state.any((t) => t.id == id)) return;
    state = List.unmodifiable([
      for (final t in state)
        if (t.id != id) t,
    ]);
    _save();
  }

  /// D2: a deleted workspace takes its tools with it.
  void removeWorkspace(String ws) {
    if (!state.any((t) => t.ws == ws)) return;
    state = List.unmodifiable([
      for (final t in state)
        if (t.ws != ws) t,
    ]);
    _save();
  }

  ToolEntry? byId(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<ToolEntry> inWorkspace(String ws) => [
    for (final t in state)
      if (t.ws == ws) t,
  ];

  String _newId() {
    final next = ref.read(toolIdSourceProvider);
    for (;;) {
      final id = next();
      if (kToolIdPattern.hasMatch(id) && byId(id) == null) return id;
    }
  }

  void _save() {
    if (!ref.mounted) return;
    final settings = ref.read(settingsStoreProvider);
    unawaited(
      settings
          .setStrings(SettingKeys.workspaceTools, [
            for (final t in state) jsonEncode(t.toJson()),
          ])
          .catchError(
            (Object e) => debugPrint('tools not saved: ${e.runtimeType}'),
          ),
    );
  }

  @override
  String toString() => 'ToolRegistry(…)';
}
````

In `apps/desktop/lib/src/platform/settings_store.dart`, replace:

````dart
  /// `agent<TAB>config<TAB>json value` per element. UI-owned.
  static const String aiAgentConfig = 'ai_agent_config';

  static const Set<String> all = {
    remoteAccess,
    keepAwake,
````

with:

````dart
  /// `agent<TAB>config<TAB>json value` per element. UI-owned.
  static const String aiAgentConfig = 'ai_agent_config';

  /// V2-3 D2: the personal tools of every workspace, one JSON object
  /// `{id, ws, name, url, phone}` per element. UI-owned.
  static const String workspaceTools = 'workspace_tools';

  static const Set<String> all = {
    remoteAccess,
    keepAwake,
````

In `apps/desktop/lib/src/platform/settings_store.dart`, replace:

````dart
    aiDefaultAgent,
    aiCustomAgents,
    aiAgentConfig,
  };
}

````

with:

````dart
    aiDefaultAgent,
    aiCustomAgents,
    aiAgentConfig,
    workspaceTools,
  };
}

````

In `apps/desktop/lib/src/platform/settings_store.dart`, replace:

````dart
    SettingKeys.aiDefaultAgent,
    SettingKeys.aiCustomAgents,
    SettingKeys.aiAgentConfig,
  };
}

````

with:

````dart
    SettingKeys.aiDefaultAgent,
    SettingKeys.aiCustomAgents,
    SettingKeys.aiAgentConfig,
    SettingKeys.workspaceTools,
  };
}

````

In `apps/desktop/test/agent/settings_ownership_test.dart`, replace:

````dart
  'ai_default_agent',
  'ai_custom_agents',
  'ai_agent_config',
};

final class _Listener implements MuxListener {
````

with:

````dart
  'ai_default_agent',
  'ai_custom_agents',
  'ai_agent_config',
  // V2-3 D2: the tools live in the window (V2-4 reads them there too).
  'workspace_tools',
};

final class _Listener implements MuxListener {
````

In `apps/desktop/test/agent/settings_ownership_test.dart`, replace:

````dart
  test('the decision for every current key is the recorded one', () {
    expect(DaemonSettingKeys.all, _expectedDaemon);
    expect(UiSettingKeys.all, _expectedUi);
    expect(SettingKeys.all, hasLength(34));
    expect(
      SettingKeys.quitKeepsSessionsExplained,
      'quit_keeps_sessions_explained',
````

with:

````dart
  test('the decision for every current key is the recorded one', () {
    expect(DaemonSettingKeys.all, _expectedDaemon);
    expect(UiSettingKeys.all, _expectedUi);
    expect(SettingKeys.all, hasLength(35));
    expect(
      SettingKeys.quitKeepsSessionsExplained,
      'quit_keeps_sessions_explained',
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/tools test/tools lib/src/platform/settings_store.dart test/agent/settings_ownership_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_entry_test.dart test/tools/tool_registry_test.dart test/agent/settings_ownership_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `dart format` changes nothing.
- `tool_entry_test.dart` +47, `tool_registry_test.dart` +10, `settings_ownership_test.dart` +6, all passed.
- `No issues found!`
- The whole suite: `3632 passed, 9 skipped`. Before the worktree's first macOS build: one passed fewer, one skipped more (see Global Constraints).

- [ ] **Step 5: The ledger**

Create `docs/superpowers/ledgers/v2-tools.md`. In the baseline line, put the base commit and the two counts the "Run first" block printed:

````markdown
# V2 tools — execution ledger (branch v2-3, merged into shellx-v2 by the controller)

## V2-3 (tools, desktop) — execution

- Baseline at 130d8aa (the branch's base): desktop analyze clean, `+3574 ~10`; shellx_agent analyze clean, `+916`.

## V2-3 (tools, desktop) — planning rulings

Plan: `docs/superpowers/plans/2026-10-15-v2-3-tools-desktop.md` (spec `docs/superpowers/specs/2026-10-15-v2-3-tools-desktop-design.md`). Task 1's `ToolEntry` / `parseToolUrl` / `ToolRegistry` are the interface V2-4 consumes.

Ruling R1: URL field — trim; no scheme → http:// (host:port counts as no scheme); http/https only; no userinfo, `\` or control characters; host [a-z0-9._-] or IPv6; port 1–65535; fragment dropped; empty path → /; ≤ 2048 — cost if wrong: IDN hosts typed in punycode.
Ruling R2: strings the spec does not list (URL errors, limit, bar and menu labels, D13 reasons, a11y labels, OK, clear-data note) follow its wording, EN + VI pinned — cost if wrong: some strings reworded.
Ruling R3: no runScript/capturePng/channel/bootstrap in BrowserEngine at all; a source scan pins it — cost if wrong: A6's full browser adds them back.
Ruling R4: macOS new windows and downloads caught by native delegate proxies (NewWindowGuard, DownloadGuard) around the plugin's — cost if wrong: a plugin upgrade re-checks BrowserNative.swift.
Ruling R5: top-level file: is refused by WebKit itself; the D9 policy blocks the other schemes — cost if wrong: none.
Ruling R6: Windows uses WinWebViewController (visibility, focus, clearCache, data folder); its JS dialogs and downloads stay WebView2's — cost if wrong: Edge-style alerts and downloads when tool-embed = on.
Ruling R7: copy/paste/cut/select all/undo/redo and terminal-only actions (edit_line, text/csi/esc, ignore) stay with the page; every other window chord forwards — cost if wrong: a text: macro is dead while a page has the keyboard.
Ruling R8: a forwarded first step arms the sequence and gives the keyboard to Flutter — cost if wrong: one click back into the page.
Ruling R9: while "nothing is running" shows a local tool, a 1 s TCP knock loads the page as soon as the port answers — cost if wrong: one local connect per second.
Ruling R10: more than 5 JS dialogs in 10 s answer themselves (dismiss/false/null), never "yes" — cost if wrong: a chatty page gets "no".
Ruling R11: tool rows are not arrow-key stops; group folding lasts for the run — cost if wrong: keyboard users open tools from the palette.
Ruling R12: agent pids recorded by the desktop runtime factory (a copy of AiHost.runtime with a recording launch); shellx_ai untouched — cost if wrong: 20 lines to keep in step.
Ruling R13: no suggestions from SSH or exited panes; process names read once when the dialog opens — cost if wrong: forwarded ports typed by hand.
Ruling R14: a workspace without tabs shows "loose" (its dock beside an empty area, pane commands off, ⌘T opens there), not restored — cost if wrong: its dock reappears only when a tool is opened.
Ruling R15: an unloaded page loads again whenever it is shown again — cost if wrong: none.
Ruling R16: Windows clear data = clearCache() on a live page, else delete %LOCALAPPDATA%\ShellX\tools — cost if wrong: data outside browsing data stays until a clear with no page open.
Ruling R17: the palette lists every tool of every workspace, shown workspace first — cost if wrong: a long palette.
Ruling R18: Copy URL copies the tool's URL; ↗ opens the page's current URL — cost if wrong: the current URL via ↗.
Ruling R19: agent-skills/ not updated (out of scope); follow-up — cost if wrong: agents do not know tools yet.
Ruling R20: adding from the window opens the tool; from Settings it does not — cost if wrong: one click.
Ruling R21: SettingKeys.all 34 → 35 (workspace_tools); theirs + 1 if V2-2b/V2-4 land keys first — cost if wrong: a count test.
Ruling R22: toString() is ToolEntry(…) (shared interface name) for spec D24's Tool(…) — cost if wrong: none.
Ruling R23: no watchPhoneTools(); V2-4 watches toolRegistryProvider — cost if wrong: none.
Ruling R24: the macOS integration test runs as a built app in a throw-away worktree (bundle id pro.shellx.desktop.itest, temporary HOME), not flutter test -d macos — cost if wrong: a minute of build per run.
Ruling R25: a retry loads the URL again, never reload() (WebKit reloads about:blank after a failed first load) — cost if wrong: none.
Ruling R26: workspace_tools is a window key (UiSettingKeys); the background service never touches it — cost if wrong: none.
Ruling R27: browser_url.dart comes over unchanged (D6) for A6's browser; tools use isLocalToolHost (V2-3 D11: *.localhost and 0.0.0.0 count as this computer) — cost if wrong: two local-host rules until A6 resumes.
Ruling R28: Safari's Web Inspector reaches a tool page (setInspectable, macOS 13.3+) — cost if wrong: someone at the user's own session can inspect the user's own tool.
````

- [ ] **Step 6: Commit**

````bash
git add apps/desktop/lib/src/tools/tool_entry.dart apps/desktop/lib/src/tools/tool_registry.dart \
  apps/desktop/lib/src/platform/settings_store.dart apps/desktop/test/agent/settings_ownership_test.dart \
  apps/desktop/test/tools/tool_entry_test.dart apps/desktop/test/tools/tool_registry_test.dart \
  docs/superpowers/ledgers/v2-tools.md
git commit -m "feat(v2-tools): tool model and registry — URL rules, the workspace_tools key, the interface V2-4 consumes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 2: Every V2-3 string, EN + VI

All 76 strings at once, so that later tasks only use them.
- **Spec strings:** §4.3, §4.2 and D17/D21/D22 word for word, with the Vietnamese straight quotes as the spec writes them (`"{name}"`).
- **Extras (ruling R2):** they follow its wording.
- **Pinned:** a test checks the Vietnamese and English text, and that no V2-3 string says "Claude Code".

**Files:**
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb`
- Regenerate (committed): `apps/desktop/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_vi.dart`
- Test: `apps/desktop/test/l10n/tool_strings_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces, `AppLocalizations` (`package:shellx_desktop/l10n/app_localizations.dart`):
  - getters: `toolsGroup`, `toolAdd`, `toolLocal`, `toolRemote`, `toolUnencrypted`, `toolBackToTool`, `toolPhoneOn`, `toolPhoneOff`, `toolPhoneOnlyLocal`, `toolAlsoPhone`, `toolExpand`, `toolCollapse`, `toolOpenInBrowser`, `toolAtsBlocked`, `toolCrashed`, `toolDownloadBlocked`, `toolClearData`, `toolClearDataConfirm`, `toolEmbedSetting`, `toolEmbedAuto`, `toolEmbedOn`, `toolEmbedOff`, `actionToggleTools`, `actionAddTool`, `toolDialogAddTitle`, `toolDialogEditTitle`, `toolDialogName`, `toolDialogNameHint`, `toolDialogUrl`, `toolDialogUrlHint`, `toolSuggestionsTitle`, `toolSuggestionsNone`, `toolDialogPhone`, `toolDialogPhoneNote`, `toolDialogAdd`, `toolDialogSave`, `toolUrlNotHttp`, `toolUrlUserinfo`, `toolUrlBackslash`, `toolUrlNoHost`, `toolUrlBadPort`, `toolUrlTooLong`, `toolBack`, `toolReload`, `toolStop`, `toolMore`, `toolEditMenu`, `toolCopyUrl`, `toolCloseDock`, `toolClose`, `toolMenuOpen`, `toolMenuEdit`, `toolMenuDelete`, `toolDeleteAction`, `toolClearDataAction`, `toolClearDataNote`, `toolDataLabel`, `toolNeedsWebView2`, `toolReasonDns`, `toolReasonTimeout`, `toolReasonCertificate`, `toolReasonUnreachable`, `toolReasonOther`, `toolHandleLabel`, `toolOk`.
  - methods: `String toolOpenCommand(String name)`, `String toolAway(String host)`, `String toolRefused(String hostPort)`, `String toolLoadFailed(String reason)`, `String toolDeleteConfirm(String name)`, `String toolCovered(String name)`, `String toolTooMany(String name)`, `String toolJsAlertTitle(String name)`, `String toolSuggestion(int port, String process)`, `String toolLimitReached(int count)`, `String toolDockLabel(String name)`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/l10n/tool_strings_test.dart`:

````dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('V2-3 §4.3: the Vietnamese strings, word for word', () {
    expect(vi.toolsGroup, 'Tool');
    expect(vi.toolAdd, 'Thêm tool');
    expect(vi.toolOpenCommand('Bảng việc'), 'Mở tool: Bảng việc');
    expect(vi.toolLocal, 'Trên máy này');
    expect(vi.toolRemote, 'Ngoài máy này');
    expect(vi.toolUnencrypted, 'không mã hoá');
    expect(vi.toolAway('sso.example.com'), 'Đang ở sso.example.com');
    expect(vi.toolBackToTool, 'Về tool');
    expect(
      [vi.toolPhoneOn, vi.toolPhoneOff],
      ['Điện thoại: bật', 'Điện thoại: tắt'],
    );
    expect(
      vi.toolPhoneOnlyLocal,
      'Chỉ tool http trên máy này mở được trên điện thoại.',
    );
    expect(vi.toolAlsoPhone, '· cả điện thoại');
    expect([vi.toolExpand, vi.toolCollapse], ['Mở rộng', 'Thu về']);
    expect(vi.toolOpenInBrowser, 'Mở bằng trình duyệt');
    expect(
      vi.toolRefused('localhost:5173'),
      'Chưa có gì chạy ở localhost:5173. Chạy server của tool rồi trang sẽ '
      'tự hiện.',
    );
    expect(vi.toolLoadFailed('x'), 'Không tải được trang: x');
    expect(
      vi.toolAtsBlocked,
      'macOS không cho mở trang http này trong ShellX.',
    );
    expect(vi.toolCrashed, 'Trang đã dừng.');
    expect(
      vi.toolDownloadBlocked,
      'Tool muốn tải một tệp. Mở bằng trình duyệt để tải.',
    );
    expect(
      vi.toolDeleteConfirm('Bảng việc'),
      'Xoá tool "Bảng việc"? Trang của nó đóng lại. Dữ liệu web của nó không '
      'bị xoá.',
    );
    expect(vi.toolClearData, 'Xoá dữ liệu của tool…');
    expect(
      vi.toolClearDataConfirm,
      'Đăng xuất mọi tool và xoá cookie, bộ nhớ của chúng?',
    );
    expect(vi.toolEmbedSetting, 'Hiện tool trong ShellX');
    expect(
      [vi.toolEmbedAuto, vi.toolEmbedOn, vi.toolEmbedOff],
      ['Tự động', 'Luôn', 'Không, mở bằng trình duyệt'],
    );
    expect(vi.toolCovered('Bảng việc'), 'Bảng việc — tạm ẩn khi đang mở menu');
    expect(
      vi.toolTooMany('Grafana'),
      'Đã dỡ "Grafana" cho ShellX nhẹ. Bấm để tải lại.',
    );
    expect(vi.toolJsAlertTitle('Bảng việc'), 'Bảng việc nhắn');
    expect(vi.actionToggleTools, 'Hiện hoặc ẩn vùng tool');
    expect(vi.actionAddTool, 'Thêm tool…');
  });

  test('V2-3 §4.2: the dialog, word for word', () {
    expect(
      [vi.toolDialogAddTitle, vi.toolDialogEditTitle],
      ['Thêm tool', 'Sửa tool'],
    );
    expect(
      [en.toolDialogAddTitle, en.toolDialogEditTitle],
      ['Add a tool', 'Edit tool'],
    );
    expect(vi.toolDialogNameHint, 'Bảng việc');
    expect(vi.toolDialogUrlHint, 'http://localhost:4000');
    expect(vi.toolSuggestionsTitle, 'Cổng đang chạy mà ShellX thấy:');
    expect(vi.toolSuggestion(5173, 'node'), 'localhost:5173 · node');
    expect(
      vi.toolSuggestionsNone,
      'Chưa thấy cổng nào. Chạy server của tool trong một terminal hoặc nhờ '
      'agent chạy.',
    );
    expect(vi.toolDialogPhone, 'Cho mở trên điện thoại');
    expect(
      vi.toolDialogPhoneNote,
      'Đi qua relay, mã hoá đầu cuối. Điện thoại chỉ tới được đúng URL này.',
    );
    expect([vi.toolDialogAdd, vi.toolDialogSave], ['Thêm', 'Lưu']);
    expect(vi.toolUrlNotHttp, 'URL phải bắt đầu bằng http:// hoặc https://');
    expect(
      vi.toolUrlUserinfo,
      'URL không được chứa tên đăng nhập hay mật khẩu',
    );
  });

  test('English reads as the spec says', () {
    expect(
      en.toolRefused('localhost:5173'),
      "Nothing is running at localhost:5173. Start your tool's server and "
      'the page will appear.',
    );
    expect(en.toolJsAlertTitle('Board'), 'Board says');
    expect(en.toolEmbedOff, 'No, open in browser');
    expect(en.actionToggleTools, 'Show or hide tools');
  });

  test('no V2-3 string says "Claude Code"', () {
    for (final name in ['app_en.arb', 'app_vi.arb']) {
      final arb =
          jsonDecode(File('lib/l10n/$name').readAsStringSync())
              as Map<String, Object?>;
      for (final MapEntry(:key, :value) in arb.entries) {
        if (!key.startsWith('tool') || value is! String) continue;
        expect(value, isNot(contains('Claude Code')), reason: '$name $key');
      }
    }
  });
}
````

- [ ] **Step 2: Run it to see it fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/l10n/tool_strings_test.dart
````

Expected: compilation fails, `The getter 'toolsGroup' isn't defined for the type 'AppLocalizations'`.

- [ ] **Step 3: Add the strings**

The English file keeps the repo's convention: an `@key` entry with `placeholders` only for strings that have placeholders.

In `apps/desktop/lib/l10n/app_en.arb`, replace:

````json
  "aiStopping": "Stopping…",
  "aiTurnDone": "Turn {n} · {time}",
  "@aiTurnDone": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}}},
  "aiFileMissing": "This file is not there any more."
}
````

with:

````json
  "aiStopping": "Stopping…",
  "aiTurnDone": "Turn {n} · {time}",
  "@aiTurnDone": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}}},
  "aiFileMissing": "This file is not there any more.",
  "toolsGroup": "Tools",
  "toolAdd": "Add tool",
  "toolOpenCommand": "Open tool: {name}",
  "@toolOpenCommand": {"placeholders": {"name": {"type": "String"}}},
  "toolLocal": "On this computer",
  "toolRemote": "Not on this computer",
  "toolUnencrypted": "not encrypted",
  "toolAway": "On {host}",
  "@toolAway": {"placeholders": {"host": {"type": "String"}}},
  "toolBackToTool": "Back to tool",
  "toolPhoneOn": "Phone: on",
  "toolPhoneOff": "Phone: off",
  "toolPhoneOnlyLocal": "Only http tools on this computer can open on a phone.",
  "toolAlsoPhone": "· on phone too",
  "toolExpand": "Expand",
  "toolCollapse": "Restore",
  "toolOpenInBrowser": "Open in browser",
  "toolRefused": "Nothing is running at {hostPort}. Start your tool's server and the page will appear.",
  "@toolRefused": {"placeholders": {"hostPort": {"type": "String"}}},
  "toolLoadFailed": "The page couldn't load: {reason}",
  "@toolLoadFailed": {"placeholders": {"reason": {"type": "String"}}},
  "toolAtsBlocked": "macOS doesn't allow this http page inside ShellX.",
  "toolCrashed": "The page stopped.",
  "toolDownloadBlocked": "This tool wants to download a file. Open it in your browser to download.",
  "toolDeleteConfirm": "Delete the tool \"{name}\"? Its page closes. Its web data stays.",
  "@toolDeleteConfirm": {"placeholders": {"name": {"type": "String"}}},
  "toolClearData": "Clear tool data…",
  "toolClearDataConfirm": "Sign every tool out and clear its cookies and storage?",
  "toolEmbedSetting": "Show tools in ShellX",
  "toolEmbedAuto": "Automatic",
  "toolEmbedOn": "Always",
  "toolEmbedOff": "No, open in browser",
  "toolCovered": "{name} — hidden while a menu is open",
  "@toolCovered": {"placeholders": {"name": {"type": "String"}}},
  "toolTooMany": "Closed \"{name}\" to keep ShellX light. Click to load it again.",
  "@toolTooMany": {"placeholders": {"name": {"type": "String"}}},
  "toolJsAlertTitle": "{name} says",
  "@toolJsAlertTitle": {"placeholders": {"name": {"type": "String"}}},
  "actionToggleTools": "Show or hide tools",
  "actionAddTool": "Add tool…",
  "toolDialogAddTitle": "Add a tool",
  "toolDialogEditTitle": "Edit tool",
  "toolDialogName": "Name",
  "toolDialogNameHint": "Task board",
  "toolDialogUrl": "URL",
  "toolDialogUrlHint": "http://localhost:4000",
  "toolSuggestionsTitle": "Running ports ShellX can see:",
  "toolSuggestion": "localhost:{port} · {process}",
  "@toolSuggestion": {"placeholders": {"port": {"type": "int"}, "process": {"type": "String"}}},
  "toolSuggestionsNone": "No running ports yet. Start your tool's server in a terminal or ask the agent to.",
  "toolDialogPhone": "Allow on phone",
  "toolDialogPhoneNote": "Through the relay, end-to-end encrypted. The phone can reach this URL only.",
  "toolDialogAdd": "Add",
  "toolDialogSave": "Save",
  "toolUrlNotHttp": "The URL must start with http:// or https://",
  "toolUrlUserinfo": "The URL can't contain a user name or password",
  "toolUrlBackslash": "The URL can't contain a backslash (\\)",
  "toolUrlNoHost": "The URL needs a host, like localhost:4000",
  "toolUrlBadPort": "The port must be a number from 1 to 65535",
  "toolUrlTooLong": "The URL is longer than 2048 characters",
  "toolLimitReached": "This project already has {count} tools.",
  "@toolLimitReached": {"placeholders": {"count": {"type": "int"}}},
  "toolBack": "Back",
  "toolReload": "Reload",
  "toolStop": "Stop",
  "toolMore": "More",
  "toolEditMenu": "Edit tool…",
  "toolCopyUrl": "Copy URL",
  "toolCloseDock": "Close tools",
  "toolClose": "Close tool",
  "toolMenuOpen": "Open",
  "toolMenuEdit": "Edit…",
  "toolMenuDelete": "Delete…",
  "toolDeleteAction": "Delete",
  "toolClearDataAction": "Clear",
  "toolClearDataNote": "Your tools stay; you sign in to them again.",
  "toolDataLabel": "Tool data",
  "toolNeedsWebView2": "Microsoft Edge WebView2 Runtime is needed.",
  "toolReasonDns": "the address was not found",
  "toolReasonTimeout": "it took too long",
  "toolReasonCertificate": "the certificate is not valid",
  "toolReasonUnreachable": "the network can't be reached",
  "toolReasonOther": "something went wrong",
  "toolDockLabel": "Tools: {name}",
  "@toolDockLabel": {"placeholders": {"name": {"type": "String"}}},
  "toolHandleLabel": "Tools width",
  "toolOk": "OK"
}
````

In `apps/desktop/lib/l10n/app_vi.arb`, replace:

````json
  "aiOutputCut": "Ẩn {count} dòng",
  "aiStopping": "Đang dừng…",
  "aiTurnDone": "Lượt {n} · {time}",
  "aiFileMissing": "Tệp này không còn nữa."
}
````

with:

````json
  "aiOutputCut": "Ẩn {count} dòng",
  "aiStopping": "Đang dừng…",
  "aiTurnDone": "Lượt {n} · {time}",
  "aiFileMissing": "Tệp này không còn nữa.",
  "toolsGroup": "Tool",
  "toolAdd": "Thêm tool",
  "toolOpenCommand": "Mở tool: {name}",
  "toolLocal": "Trên máy này",
  "toolRemote": "Ngoài máy này",
  "toolUnencrypted": "không mã hoá",
  "toolAway": "Đang ở {host}",
  "toolBackToTool": "Về tool",
  "toolPhoneOn": "Điện thoại: bật",
  "toolPhoneOff": "Điện thoại: tắt",
  "toolPhoneOnlyLocal": "Chỉ tool http trên máy này mở được trên điện thoại.",
  "toolAlsoPhone": "· cả điện thoại",
  "toolExpand": "Mở rộng",
  "toolCollapse": "Thu về",
  "toolOpenInBrowser": "Mở bằng trình duyệt",
  "toolRefused": "Chưa có gì chạy ở {hostPort}. Chạy server của tool rồi trang sẽ tự hiện.",
  "toolLoadFailed": "Không tải được trang: {reason}",
  "toolAtsBlocked": "macOS không cho mở trang http này trong ShellX.",
  "toolCrashed": "Trang đã dừng.",
  "toolDownloadBlocked": "Tool muốn tải một tệp. Mở bằng trình duyệt để tải.",
  "toolDeleteConfirm": "Xoá tool \"{name}\"? Trang của nó đóng lại. Dữ liệu web của nó không bị xoá.",
  "toolClearData": "Xoá dữ liệu của tool…",
  "toolClearDataConfirm": "Đăng xuất mọi tool và xoá cookie, bộ nhớ của chúng?",
  "toolEmbedSetting": "Hiện tool trong ShellX",
  "toolEmbedAuto": "Tự động",
  "toolEmbedOn": "Luôn",
  "toolEmbedOff": "Không, mở bằng trình duyệt",
  "toolCovered": "{name} — tạm ẩn khi đang mở menu",
  "toolTooMany": "Đã dỡ \"{name}\" cho ShellX nhẹ. Bấm để tải lại.",
  "toolJsAlertTitle": "{name} nhắn",
  "actionToggleTools": "Hiện hoặc ẩn vùng tool",
  "actionAddTool": "Thêm tool…",
  "toolDialogAddTitle": "Thêm tool",
  "toolDialogEditTitle": "Sửa tool",
  "toolDialogName": "Tên",
  "toolDialogNameHint": "Bảng việc",
  "toolDialogUrl": "URL",
  "toolDialogUrlHint": "http://localhost:4000",
  "toolSuggestionsTitle": "Cổng đang chạy mà ShellX thấy:",
  "toolSuggestion": "localhost:{port} · {process}",
  "toolSuggestionsNone": "Chưa thấy cổng nào. Chạy server của tool trong một terminal hoặc nhờ agent chạy.",
  "toolDialogPhone": "Cho mở trên điện thoại",
  "toolDialogPhoneNote": "Đi qua relay, mã hoá đầu cuối. Điện thoại chỉ tới được đúng URL này.",
  "toolDialogAdd": "Thêm",
  "toolDialogSave": "Lưu",
  "toolUrlNotHttp": "URL phải bắt đầu bằng http:// hoặc https://",
  "toolUrlUserinfo": "URL không được chứa tên đăng nhập hay mật khẩu",
  "toolUrlBackslash": "URL không được chứa dấu gạch ngược (\\)",
  "toolUrlNoHost": "URL cần có tên máy, ví dụ localhost:4000",
  "toolUrlBadPort": "Cổng phải là số từ 1 đến 65535",
  "toolUrlTooLong": "URL dài quá 2048 ký tự",
  "toolLimitReached": "Dự án này đã có {count} tool.",
  "toolBack": "Quay lại",
  "toolReload": "Tải lại",
  "toolStop": "Dừng",
  "toolMore": "Thêm",
  "toolEditMenu": "Sửa tool…",
  "toolCopyUrl": "Sao chép URL",
  "toolCloseDock": "Đóng vùng tool",
  "toolClose": "Đóng tool",
  "toolMenuOpen": "Mở",
  "toolMenuEdit": "Sửa…",
  "toolMenuDelete": "Xoá…",
  "toolDeleteAction": "Xoá",
  "toolClearDataAction": "Xoá",
  "toolClearDataNote": "Tool vẫn còn; bạn đăng nhập lại vào chúng.",
  "toolDataLabel": "Dữ liệu của tool",
  "toolNeedsWebView2": "Cần Microsoft Edge WebView2 Runtime.",
  "toolReasonDns": "không tìm thấy địa chỉ",
  "toolReasonTimeout": "quá lâu không phản hồi",
  "toolReasonCertificate": "chứng chỉ không hợp lệ",
  "toolReasonUnreachable": "không tới được mạng",
  "toolReasonOther": "có lỗi xảy ra",
  "toolDockLabel": "Tool: {name}",
  "toolHandleLabel": "Độ rộng vùng tool",
  "toolOk": "OK"
}
````

Regenerate the localizations:

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n
````

Expected: only Flutter's note that it uses the options in `l10n.yaml`; `git status` shows the three `lib/l10n/app_localizations*.dart` files changed.

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/l10n
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_strings_test.dart` +4, and the other `test/l10n` tests pass (they check that both ARB files have the same keys).
- `No issues found!`
- The whole suite: `3636 passed, 9 skipped`. Before the worktree's first macOS build: one passed fewer, one skipped more (see Global Constraints).

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/l10n/app_en.arb apps/desktop/lib/l10n/app_vi.arb \
  apps/desktop/lib/l10n/app_localizations.dart apps/desktop/lib/l10n/app_localizations_en.dart \
  apps/desktop/lib/l10n/app_localizations_vi.dart apps/desktop/test/l10n/tool_strings_test.dart
git commit -m "feat(v2-tools): every tool string, English and Vietnamese word for word from the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 3: A6's engine, taken for tools, without the bridge

Only the engine comes from the parked A6 branch (spec D6). Never revert `fd7d178`, and never bring `third_party/webview_windows`.
- **Unchanged:** the URL model `browser_url.dart` with its test, and the Runner registration of `BrowserNative.swift` (`MainFlutterWindow.swift`, `project.pbxproj`).
- **Adapted for tools:**
  - `browser_engine.dart`: the interface without `BridgeReceived`, `transport`, `runScript` and `capturePng` (D16, ruling R3). It gains what tools need: `coversFlutter`, `setVisible`, `OpenOutside`, a `DownloadBlocked` with its URL, the `ats` kind, the D9 `NavigationPolicy`, JS dialogs through a `BrowserDialogPresenter`, and `BrowserDataStore`.
  - The fake engine.
  - `WkWebViewEngine`, `BrowserNative.swift` and their test, without the bootstrap script and the snapshot.
- **Plist:** `NSAllowsLocalNetworking` (D19).
- **Dependencies:** the two `webview_flutter` packages, by hand, pinned exactly.

This task only extracts and adapts; Task 5 reviews and hardens the macOS engine (it was never reviewed).

About `browser_url.dart` (ruling R27):
- Until Task 5, the WIP engine uses its `isNavigable`. From Task 5 on, the D9 policy replaces that, and nothing in the tool path uses the file. It stays for A6's browser (D6).
- Tools follow V2-3 D11 through `isLocalToolHost` (Task 1). That rule counts `*.localhost` and `0.0.0.0` as this computer; A6's tightened S5 rule (`isLocalHost`) does not.

**Files:**
- Modify: `apps/desktop/pubspec.yaml`; regenerated by `flutter pub get` (committed): `apps/desktop/macos/Flutter/GeneratedPluginRegistrant.swift`; updated by the macOS build (committed, `COCOAPODS:` line restored): `apps/desktop/macos/Podfile.lock`
- From `origin/feat/desktop-a6`, unchanged: `apps/desktop/lib/src/browser/browser_url.dart`, `apps/desktop/test/browser/browser_url_test.dart`, `apps/desktop/macos/Runner/MainFlutterWindow.swift`, `apps/desktop/macos/Runner.xcodeproj/project.pbxproj`
- Create: `apps/desktop/lib/src/browser/browser_engine.dart`, `apps/desktop/lib/src/browser/engines/wk_webview_engine.dart`, `apps/desktop/macos/Runner/BrowserNative.swift`, `apps/desktop/test/support/fake_browser_engine.dart`
- Modify: `apps/desktop/macos/Runner/Info.plist`
- Test: `apps/desktop/test/browser/wk_webview_engine_test.dart`, `apps/desktop/test/browser/browser_url_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, `lib/src/browser/browser_engine.dart`:
  - `enum BrowserLoadErrorKind { refused, unreachable, dns, timeout, certificate, ats, crashed, unavailable, other }`
  - `sealed class BrowserEngineEvent`, with these events:
    - `UrlChanged(Uri url)`, `TitleChanged(String title)`;
    - `LoadStarted()`, `LoadProgress(int percent)`, `LoadFinished()`, `LoadFailed(BrowserLoadErrorKind kind)`;
    - `HistoryChanged({required bool canGoBack, required bool canGoForward})`;
    - `NavigationBlocked()`, `OpenOutside(Uri url, {required bool newWindow})`, `DownloadBlocked({Uri? url})`;
    - `ShortcutForwarded(String chord)`, `ContentClicked()`.
  - `enum NavigationVerdict { allow, outside, block }`; `typedef NavigationPolicy = NavigationVerdict Function(Uri? url, {required bool mainFrame, required bool newWindow});`
  - JS dialogs: `enum BrowserJsDialogKind { alert, confirm, prompt }`; `final class BrowserJsDialog({required BrowserJsDialogKind kind, required String message, String? defaultText})`; `typedef BrowserDialogPresenter = Future<Object?> Function(BrowserJsDialog dialog);` (alert → `null`, confirm → `bool`, prompt → `String?`).
  - `abstract interface class BrowserEngine`:
    - `Stream<BrowserEngineEvent> get events`, `bool get coversFlutter`;
    - navigation: `Future<void> load(Uri url)`, `goBack()`, `goForward()`, `reload()`, `stop()`;
    - keyboard: `Future<void> setForwardedChords(List<String> chords)`, `focusContent()`, `releaseFocus()`;
    - `Future<void> setVisible(bool visible)`, `Widget buildView()`, `Future<void> dispose()`.
  - `abstract interface class BrowserDataStore { Future<void> clearAll(); }`
- Produces, `lib/src/browser/engines/wk_webview_engine.dart` (Task 5 changes it):
  - `const String browserNativeChannelName = 'pro.shellx.desktop/browser'`;
  - `final class BrowserNativeMac implements BrowserDataStore`, `final browserNativeMacProvider = Provider<BrowserNativeMac>(…)`;
  - `final class WkWebViewEngine implements BrowserEngine` with `WkWebViewEngine({required BrowserNativeMac native, BrowserDialogPresenter? dialogs})`.
- Produces, `test/support/fake_browser_engine.dart`:
  - `final class FakeBrowserEngine implements BrowserEngine`, built with `FakeBrowserEngine({bool coversFlutter = false, String key = 'fake'})`;
  - what it records: `List<Uri> loads`, `List<String> calls`, `List<String> forwarded`, `bool? visible`, `bool disposed`, `int builds`;
  - `void emit(BrowserEngineEvent event)` sends an event as the page would.
- Produces, `lib/src/browser/browser_url.dart` (A6, unchanged): `parseAddressInput`, `isLocalHost`, `classifyOrigin`, `isNavigable`, `urlForRestore`, `displayAddress`.

- [ ] **Step 1: Add the dependencies**

In `apps/desktop/pubspec.yaml`, replace:

````yaml
  shellx_ai: any
  shellx_core: any
  tray_manager: ^0.5.3
  win32: ^5.15.0
  window_manager: ^0.5.2
  # xterm 4.0.0 (same version as apps/mobile, A1 D12), vendored for one
````

with:

````yaml
  shellx_ai: any
  shellx_core: any
  tray_manager: ^0.5.3
  # V2-3 D6: WKWebView as a platform view on macOS (tools). Pinned exactly:
  # wkwebview 3.26+ needs Flutter 3.44 / Dart 3.12.
  webview_flutter: 4.14.1
  webview_flutter_wkwebview: 3.25.1
  win32: ^5.15.0
  window_manager: ^0.5.2
  # xterm 4.0.0 (same version as apps/mobile, A1 D12), vendored for one
````

From the worktree root:

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
````

Expected: `Got dependencies!`. The output names `webview_flutter 4.14.1`, `webview_flutter_wkwebview 3.25.1` and `webview_flutter_platform_interface 2.15.1`. `apps/desktop/macos/Flutter/GeneratedPluginRegistrant.swift` gains `import webview_flutter_wkwebview` and its `WebViewFlutterPlugin.register(…)` line.

- [ ] **Step 2: Take the unchanged files from the A6 branch**

From the worktree root:

````bash
git log --oneline -1 origin/feat/desktop-a6 || git fetch origin feat/desktop-a6
git checkout origin/feat/desktop-a6 -- \
  apps/desktop/lib/src/browser/browser_url.dart \
  apps/desktop/test/browser/browser_url_test.dart \
  apps/desktop/macos/Runner/MainFlutterWindow.swift \
  apps/desktop/macos/Runner.xcodeproj/project.pbxproj
````

`git diff --cached apps/desktop/macos` must show exactly these lines and nothing else (`MainFlutterWindow.swift` and `project.pbxproj` have not changed on `main` since A6 branched at `148c2db`):

````diff
+		A6B0000100000000000000A1 /* BrowserNative.swift in Sources */ = {isa = PBXBuildFile; fileRef = A6B0000200000000000000A2 /* BrowserNative.swift */; };
+		A6B0000200000000000000A2 /* BrowserNative.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BrowserNative.swift; sourceTree = "<group>"; };
+				A6B0000200000000000000A2 /* BrowserNative.swift */,
+				A6B0000100000000000000A1 /* BrowserNative.swift in Sources */,
+  // A6 Task 7: UI path only; the daemon has no view controller (D35).
+  private var browserNative: BrowserNative?
+
+    browserNative = BrowserNative(controller: flutterViewController)
````

- [ ] **Step 3: Write the failing test**

`apps/desktop/test/browser/wk_webview_engine_test.dart`:

````dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NSURLError codes map to error kinds (A6 D14)', () {
    expect(macErrorKind(-1004), BrowserLoadErrorKind.refused);
    expect(macErrorKind(-1003), BrowserLoadErrorKind.dns);
    expect(macErrorKind(-1006), BrowserLoadErrorKind.dns);
    expect(macErrorKind(-1001), BrowserLoadErrorKind.timeout);
    expect(macErrorKind(-1009), BrowserLoadErrorKind.unreachable);
    expect(macErrorKind(-1005), BrowserLoadErrorKind.unreachable);
    for (final c in [-1200, -1201, -1202, -1203, -1204, -1205, -1206]) {
      expect(macErrorKind(c), BrowserLoadErrorKind.certificate);
    }
    expect(macErrorKind(-999), isNull); // cancelled by a newer navigation
    expect(
      macErrorKind(0, processTerminated: true),
      BrowserLoadErrorKind.crashed,
    );
    expect(macErrorKind(-1100), BrowserLoadErrorKind.other);
    expect(isMacInterruptedLoad(102), isTrue);
    expect(isMacInterruptedLoad(-1004), isFalse);
  });

  test('BrowserNativeMac: outbound calls and inbound events', () async {
    const channel = MethodChannel('test/browser');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final native = BrowserNativeMac(channel);
    final events = <BrowserEngineEvent>[];
    native.attach(7, events.add);
    await native.setForwardedChords(7, ['meta+t']);
    await native.stop(7);
    await native.focus(7);
    await native.blur(7);
    await native.clearAll();
    expect(calls.map((c) => c.method), [
      'setForwardedChords',
      'stop',
      'focus',
      'blur',
      'clearWebsiteData',
    ]);
    expect(calls.first.arguments, {
      'id': 7,
      'chords': ['meta+t'],
    });

    Future<void> inbound(String method, Map<String, Object?> args) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await inbound('shortcut', {'id': 7, 'chord': 'meta+t'});
    await inbound('pointerDown', {'id': 7});
    await inbound('shortcut', {'id': 99, 'chord': 'meta+t'}); // not ours
    expect(events, hasLength(2));
    expect((events[0] as ShortcutForwarded).chord, 'meta+t');
    expect(events[1], isA<ContentClicked>());
    native.detach(7);
    await inbound('pointerDown', {'id': 7});
    expect(events, hasLength(2));
  });
}
````

- [ ] **Step 4: Run the tests to see the engine test fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser
````

Expected:
- `browser_url_test.dart` passes (A6's file, unchanged).
- `wk_webview_engine_test.dart` fails to compile: `Error when reading 'lib/src/browser/engines/wk_webview_engine.dart': No such file or directory`.

- [ ] **Step 5: Implement**

`apps/desktop/lib/src/browser/browser_engine.dart`:

````dart
/// A6 §3.2, taken for V2-3 tools (D6, D16): what a page needs from
/// WKWebView (macOS) or WebView2 (Windows). No bridge, no script, no
/// screenshot: ShellX never runs code in a tool's page. One engine per
/// platform, and a fake for tests.
library;

import 'package:flutter/widgets.dart' show Widget;

/// D13 (A6 D14): why a load failed; it picks the panel's words.
enum BrowserLoadErrorKind {
  refused,
  unreachable,
  dns,
  timeout,
  certificate,

  /// macOS App Transport Security refused plain http (D19).
  ats,
  crashed,

  /// No engine (Windows without the WebView2 Runtime, §8).
  unavailable,
  other,
}

sealed class BrowserEngineEvent {
  const BrowserEngineEvent();
}

final class UrlChanged extends BrowserEngineEvent {
  const UrlChanged(this.url);
  final Uri url;

  @override
  String toString() => 'UrlChanged(…)';
}

final class TitleChanged extends BrowserEngineEvent {
  const TitleChanged(this.title);
  final String title;

  @override
  String toString() => 'TitleChanged(…)';
}

final class LoadStarted extends BrowserEngineEvent {
  const LoadStarted();
}

/// 0–100; engines without progress (WebView2) never send it.
final class LoadProgress extends BrowserEngineEvent {
  const LoadProgress(this.percent);
  final int percent;
}

final class LoadFinished extends BrowserEngineEvent {
  const LoadFinished();
}

final class LoadFailed extends BrowserEngineEvent {
  const LoadFailed(this.kind);
  final BrowserLoadErrorKind kind;

  @override
  String toString() => 'LoadFailed(${kind.name})';
}

final class HistoryChanged extends BrowserEngineEvent {
  const HistoryChanged({required this.canGoBack, required this.canGoForward});
  final bool canGoBack;
  final bool canGoForward;
}

/// D9: a navigation the page may not make (a `file:`, `javascript:` or
/// `data:` page, an unknown scheme). Refused without a word.
final class NavigationBlocked extends BrowserEngineEvent {
  const NavigationBlocked();
}

/// D9: the page asked for [url] outside itself — a new window
/// (`target=_blank`, `window.open`) or a `mailto:`/`tel:` link. The engine
/// already kept it out of the page; the tool page opens it outside.
final class OpenOutside extends BrowserEngineEvent {
  const OpenOutside(this.url, {required this.newWindow});
  final Uri url;
  final bool newWindow;

  @override
  String toString() => 'OpenOutside(…)';
}

/// D9: a download was stopped; [url] is what it would have fetched, when
/// the engine says.
final class DownloadBlocked extends BrowserEngineEvent {
  const DownloadBlocked({this.url});
  final Uri? url;

  @override
  String toString() => 'DownloadBlocked(…)';
}

/// D10: a ShellX chord (config spelling, `chordConfigText`) pressed while
/// the page had the keyboard; the page never saw it.
final class ShortcutForwarded extends BrowserEngineEvent {
  const ShortcutForwarded(this.chord);
  final String chord;
}

/// D10: a mouse press inside the page (macOS reports it natively).
final class ContentClicked extends BrowserEngineEvent {
  const ContentClicked();
}

/// What a navigation may do (D9, decided by `toolNavigation`).
enum NavigationVerdict { allow, outside, block }

/// D9: [url] (null: not a URL) in the top frame ([mainFrame]) or a frame of
/// the page, or as a new window ([newWindow]).
typedef NavigationPolicy =
    NavigationVerdict Function(
      Uri? url, {
      required bool mainFrame,
      required bool newWindow,
    });

enum BrowserJsDialogKind { alert, confirm, prompt }

/// D9: an `alert`, `confirm` or `prompt` of the page. Its text is the
/// page's: shown, never logged.
final class BrowserJsDialog {
  const BrowserJsDialog({
    required this.kind,
    required this.message,
    this.defaultText,
  });
  final BrowserJsDialogKind kind;
  final String message;
  final String? defaultText;

  @override
  String toString() => 'BrowserJsDialog(${kind.name})';
}

/// D9: shows the dialog; answers null (alert), a bool (confirm) or a
/// String? (prompt; null = cancelled).
typedef BrowserDialogPresenter =
    Future<Object?> Function(BrowserJsDialog dialog);

abstract interface class BrowserEngine {
  Stream<BrowserEngineEvent> get events;

  /// D7: a native window over Flutter's (WebView2 through
  /// `webview_win_floating`): nothing Flutter draws can cover it, so it is
  /// hidden ([setVisible]) while an overlay is open. False on macOS, where
  /// the page is a platform view inside Flutter's tree.
  bool get coversFlutter;

  Future<void> load(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stop();

  /// D10: the chords (config spelling) to hand back to Flutter while the
  /// page has the keyboard. Windows has no forwarding (D7): a no-op.
  Future<void> setForwardedChords(List<String> chords);

  /// D10: give the keyboard to the page.
  Future<void> focusContent();

  /// D10: give the keyboard back to Flutter.
  Future<void> releaseFocus();

  /// D7: show or hide the page (engines that [coversFlutter] only).
  Future<void> setVisible(bool visible);

  Widget buildView();

  Future<void> dispose();
}

/// D8, D22: the one data store every tool shares; "Clear tool data…".
abstract interface class BrowserDataStore {
  Future<void> clearAll();
}
````

`apps/desktop/lib/src/browser/engines/wk_webview_engine.dart`:

````dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../browser_engine.dart';
import '../browser_url.dart';

const String browserNativeChannelName = 'pro.shellx.desktop/browser';

/// A6 D14: NSURLErrorDomain codes → error kinds; `null` = not an error to
/// show (-999: cancelled because a newer navigation started).
BrowserLoadErrorKind? macErrorKind(int code, {bool processTerminated = false}) {
  if (processTerminated) return BrowserLoadErrorKind.crashed;
  return switch (code) {
    -999 => null,
    -1004 => BrowserLoadErrorKind.refused,
    -1003 || -1006 => BrowserLoadErrorKind.dns,
    -1001 => BrowserLoadErrorKind.timeout,
    -1009 || -1005 || -1018 || -1020 => BrowserLoadErrorKind.unreachable,
    >= -1206 && <= -1200 => BrowserLoadErrorKind.certificate,
    _ => BrowserLoadErrorKind.other,
  };
}

/// WebKitErrorDomain 102 "Frame load interrupted": WebKit stopped a
/// navigation it cannot display — a download (A6 D10).
bool isMacInterruptedLoad(int code) => code == 102;

/// The app's one `pro.shellx.desktop/browser` channel (BrowserNative.swift).
final class BrowserNativeMac implements BrowserDataStore {
  BrowserNativeMac([
    MethodChannel channel = const MethodChannel(browserNativeChannelName),
  ]) : _channel = channel;

  final MethodChannel _channel;
  final Map<int, void Function(BrowserEngineEvent)> _sinks = {};
  bool _listening = false;

  void attach(int webViewId, void Function(BrowserEngineEvent) sink) {
    // Lazily, so merely constructing it (a provider) needs no binding.
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_onCall);
    }
    _sinks[webViewId] = sink;
  }

  void detach(int webViewId) {
    _sinks.remove(webViewId);
    unawaited(
      _channel
          .invokeMethod<void>('forget', {'id': webViewId})
          .catchError((_) {}),
    );
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final sink = _sinks[args['id']];
    if (sink == null) return;
    switch (call.method) {
      case 'shortcut':
        final chord = args['chord'];
        if (chord is String) sink(ShortcutForwarded(chord));
      case 'pointerDown':
        sink(const ContentClicked());
    }
  }

  Future<void> stop(int id) => _channel.invokeMethod<void>('stop', {'id': id});
  Future<void> focus(int id) =>
      _channel.invokeMethod<void>('focus', {'id': id});
  Future<void> blur(int id) => _channel.invokeMethod<void>('blur', {'id': id});
  Future<void> setForwardedChords(int id, List<String> chords) => _channel
      .invokeMethod<void>('setForwardedChords', {'id': id, 'chords': chords});

  /// D8: the app's default WebKit store.
  @override
  Future<void> clearAll() => _channel.invokeMethod<void>('clearWebsiteData');
}

/// The app's one native channel (macOS); its handler registers lazily.
final browserNativeMacProvider = Provider<BrowserNativeMac>(
  (ref) => BrowserNativeMac(),
);

/// A6 D1, taken for V2-3 (D6): WKWebView through webview_flutter_wkwebview,
/// as a platform view. No JavaScript channel, no document-start script, no
/// snapshot (D16). Task 5 reviews and hardens it.
final class WkWebViewEngine implements BrowserEngine {
  WkWebViewEngine({
    required BrowserNativeMac native,
    BrowserDialogPresenter? dialogs,
  }) : _native = native,
       _dialogs = dialogs {
    _controller = WebViewController.fromPlatformCreationParams(
      WebKitWebViewControllerCreationParams(),
    );
    _platform = _controller.platform as WebKitWebViewController;
    _id = _platform.webViewIdentifier;
    _native.attach(_id, _emit);
    _ready = _setup();
  }

  final BrowserNativeMac _native;
  final BrowserDialogPresenter? _dialogs;
  late final WebViewController _controller;
  late final WebKitWebViewController _platform;
  late final int _id;
  late final Future<void> _ready;
  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast();

  void _emit(BrowserEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _setup() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _platform.setInspectable(true);
    // Makes the id known to BrowserNative (the key monitor's list).
    await _native.setForwardedChords(_id, const []);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (uri != null && isNavigable(uri)) {
            return NavigationDecision.navigate;
          }
          _emit(const NavigationBlocked());
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => _emit(const LoadStarted()),
        onProgress: (p) => _emit(LoadProgress(p)),
        onPageFinished: (_) async {
          _emit(const LoadFinished());
          await _history();
          final title = await _controller.getTitle();
          if (title != null) _emit(TitleChanged(title));
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (uri != null) _emit(UrlChanged(uri));
          unawaited(_history());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false) return;
          if (isMacInterruptedLoad(error.errorCode)) {
            _emit(const DownloadBlocked());
            return;
          }
          final kind = macErrorKind(
            error.errorCode,
            processTerminated:
                error.errorType ==
                WebResourceErrorType.webContentProcessTerminated,
          );
          if (kind != null) _emit(LoadFailed(kind));
        },
      ),
    );
    await _controller.setOnJavaScriptAlertDialog((r) async {
      await _dialogs?.call(
        BrowserJsDialog(kind: BrowserJsDialogKind.alert, message: r.message),
      );
    });
    await _controller.setOnJavaScriptConfirmDialog((r) async {
      final ok = await _dialogs?.call(
        BrowserJsDialog(kind: BrowserJsDialogKind.confirm, message: r.message),
      );
      return ok == true;
    });
    await _controller.setOnJavaScriptTextInputDialog((r) async {
      final text = await _dialogs?.call(
        BrowserJsDialog(
          kind: BrowserJsDialogKind.prompt,
          message: r.message,
          defaultText: r.defaultText,
        ),
      );
      return text is String ? text : '';
    });
  }

  Future<void> _history() async => _emit(
    HistoryChanged(
      canGoBack: await _controller.canGoBack(),
      canGoForward: await _controller.canGoForward(),
    ),
  );

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  bool get coversFlutter => false;

  @override
  Future<void> load(Uri url) async {
    await _ready;
    if (url == aboutBlank) {
      await _controller.loadHtmlString('');
    } else {
      await _controller.loadRequest(url);
    }
  }

  @override
  Future<void> goBack() async {
    await _ready;
    await _controller.goBack();
  }

  @override
  Future<void> goForward() async {
    await _ready;
    await _controller.goForward();
  }

  @override
  Future<void> reload() async {
    await _ready;
    await _controller.reload();
  }

  @override
  Future<void> stop() async {
    await _ready;
    await _native.stop(_id);
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async {
    await _ready;
    await _native.setForwardedChords(_id, chords);
  }

  @override
  Future<void> focusContent() async {
    await _ready;
    await _native.focus(_id);
  }

  @override
  Future<void> releaseFocus() async {
    await _ready;
    await _native.blur(_id);
  }

  @override
  Future<void> setVisible(bool visible) async {}

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    _native.detach(_id);
    await _events.close();
  }
}
````

`apps/desktop/macos/Runner/BrowserNative.swift` is A6's file without `addBootstrap` and `snapshot`, and with this task's header:

````swift
import Cocoa
import FlutterMacOS
import WebKit
import webview_flutter_wkwebview

/// A6 Task 7, taken for V2-3 tools: what webview_flutter's Dart API lacks —
/// stop, clearing the app's website data, and handing ShellX chords and
/// clicks back to Flutter while a page has the keyboard. No script, no
/// snapshot (V2-3 D16). Channel "pro.shellx.desktop/browser". Never logs
/// URLs, titles or page content. V2-3 Task 5 reviews and hardens it.
final class BrowserNative: NSObject {
  private let channel: FlutterMethodChannel
  private let controller: FlutterViewController
  /// Web view id → chords to forward. An id is known once Dart called
  /// setForwardedChords for it (every engine does at setup).
  private var forwarded: [Int64: Set<String>] = [:]
  private var keyMonitor: Any?
  private var mouseMonitor: Any?

  init(controller: FlutterViewController) {
    self.controller = controller
    channel = FlutterMethodChannel(
      name: "pro.shellx.desktop/browser",
      binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result) ?? result(nil)
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self, let id = self.paneWebViewId(firstResponderOf: event),
        let chord = BrowserNative.chord(event),
        self.forwarded[id]?.contains(chord) == true
      else { return event }
      self.channel.invokeMethod("shortcut", arguments: ["id": id, "chord": chord])
      return nil  // the page never sees a ShellX chord
    }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      if let self, let id = self.paneWebViewId(under: event) {
        self.channel.invokeMethod("pointerDown", arguments: ["id": id])
      }
      return event
    }
  }

  deinit {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
  }

  /// The WKWebView behind a Dart `WebKitWebViewController.webViewIdentifier`
  /// (the plugin's public native API, stable across its versions).
  private func webView(_ id: Int64) -> WKWebView? {
    FWFWebViewFlutterWKWebViewExternalAPI.webView(
      forIdentifier: id, withPluginRegistry: controller)
  }

  private func paneWebViewId(firstResponderOf event: NSEvent) -> Int64? {
    guard let view = event.window?.firstResponder as? NSView else { return nil }
    return paneWebViewId(containing: view)
  }

  private func paneWebViewId(under event: NSEvent) -> Int64? {
    guard let content = event.window?.contentView,
      let hit = content.hitTest(event.locationInWindow)
    else { return nil }
    return paneWebViewId(containing: hit)
  }

  private func paneWebViewId(containing view: NSView) -> Int64? {
    var current: NSView? = view
    while let v = current, !(v is WKWebView) { current = v.superview }
    guard let web = current as? WKWebView else { return nil }
    return forwarded.keys.first { webView($0) === web }
  }

  /// Same format as Dart's `chordString`: alt, ctrl, meta, shift, key.
  static func chord(_ event: NSEvent) -> String? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key: String
    switch event.keyCode {
    case 123: key = "left"
    case 124: key = "right"
    case 125: key = "down"
    case 126: key = "up"
    case 53: key = "escape"
    case 36: key = "enter"
    case 48: key = "tab"
    case 96: key = "f5"
    case 97: key = "f6"
    default:
      guard let c = event.charactersIgnoringModifiers?.lowercased(), c.count == 1
      else { return nil }
      key = c
    }
    var parts: [String] = []
    if flags.contains(.option) { parts.append("alt") }
    if flags.contains(.control) { parts.append("ctrl") }
    if flags.contains(.command) { parts.append("meta") }
    if flags.contains(.shift) { parts.append("shift") }
    parts.append(key)
    return parts.joined(separator: "+")
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = (args["id"] as? NSNumber)?.int64Value
    switch call.method {
    case "clearWebsiteData":
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast
      ) { result(nil) }
      return
    case "setForwardedChords":
      if let id { forwarded[id] = Set(args["chords"] as? [String] ?? []) }
      result(nil)
      return
    case "forget":
      if let id { forwarded.removeValue(forKey: id) }
      result(nil)
      return
    default:
      break
    }
    guard let id, let web = webView(id) else {
      result(FlutterError(code: "not_found", message: nil, details: nil))
      return
    }
    switch call.method {
    case "stop":
      web.stopLoading()
      result(nil)
    case "focus":
      web.window?.makeFirstResponder(web)
      result(nil)
    case "blur":
      // Back to the Flutter view, so the next keys reach Flutter (D16).
      if let responder = web.window?.firstResponder as? NSView,
        responder === web || responder.isDescendant(of: web)
      {
        web.window?.makeFirstResponder(controller.view)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
````

`apps/desktop/test/support/fake_browser_engine.dart`:

````dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:shellx_desktop/src/browser/browser_engine.dart';

/// Test double: records calls, lets tests push engine events.
final class FakeBrowserEngine implements BrowserEngine {
  FakeBrowserEngine({this.coversFlutter = false, this.key = 'fake'});

  /// Tells engines apart in widget keys (`browser.fakeView.<key>`).
  final String key;

  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast(sync: true);

  @override
  final bool coversFlutter;

  final List<Uri> loads = [];
  final List<String> calls = [];
  List<String> forwarded = const [];
  bool? visible;
  bool disposed = false;

  /// How many times [buildView] ran (a rebuilt platform view would be a
  /// second native view for one page).
  int builds = 0;

  void emit(BrowserEngineEvent event) => _events.add(event);

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  Future<void> load(Uri url) async => loads.add(url);
  @override
  Future<void> goBack() async => calls.add('back');
  @override
  Future<void> goForward() async => calls.add('forward');
  @override
  Future<void> reload() async => calls.add('reload');
  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> setForwardedChords(List<String> chords) async =>
      forwarded = chords;

  @override
  Future<void> focusContent() async => calls.add('focus');

  @override
  Future<void> releaseFocus() async => calls.add('release');

  @override
  Future<void> setVisible(bool visible) async => this.visible = visible;

  @override
  Widget buildView() {
    builds++;
    return SizedBox.expand(key: Key('browser.fakeView.$key'));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
````

D19: `http://localhost`, `http://127.0.0.1`, home-network IPs and `*.local` load in WKWebView. `NSAllowsArbitraryLoadsInWebContent` is never added.

In `apps/desktop/macos/Runner/Info.plist`, replace:

````xml
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>$(PRODUCT_COPYRIGHT)</string>
	<key>NSMainNibFile</key>
	<string>MainMenu</string>
	<key>NSPrincipalClass</key>
````

with:

````xml
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>$(PRODUCT_COPYRIGHT)</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
	<key>NSMainNibFile</key>
	<string>MainMenu</string>
	<key>NSPrincipalClass</key>
````

- [ ] **Step 6: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/browser test/browser test/support/fake_browser_engine.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `dart format` changes nothing.
- `browser_url_test.dart` +53 and `wk_webview_engine_test.dart` +2, all passed.
- `No issues found!`
- The whole suite: `3691 passed, 9 skipped`. Before the worktree's first macOS build: one passed fewer, one skipped more (see Global Constraints).

- [ ] **Step 7: Build the macOS app (no launch)**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug
sed -i '' 's/^COCOAPODS: .*/COCOAPODS: 1.16.2/' macos/Podfile.lock
git diff macos/Podfile.lock
````

Expected:
- `✓ Built build/macos/Build/Products/Debug/ShellX.app`.
- The `Podfile.lock` diff adds `webview_flutter_wkwebview (0.0.1)`, its dependency and external-source lines, and the checksum `webview_flutter_wkwebview: 8ebf4fded22593026f7dbff1fbff31ea98573c8d`. No `COCOAPODS:` change.

Do not open the app.

- [ ] **Step 8: Commit**

````bash
git add apps/desktop/pubspec.yaml apps/desktop/macos/Flutter/GeneratedPluginRegistrant.swift apps/desktop/macos/Podfile.lock \
  apps/desktop/macos/Runner/MainFlutterWindow.swift apps/desktop/macos/Runner.xcodeproj/project.pbxproj \
  apps/desktop/macos/Runner/BrowserNative.swift apps/desktop/macos/Runner/Info.plist \
  apps/desktop/lib/src/browser apps/desktop/test/browser apps/desktop/test/support/fake_browser_engine.dart
git commit -m "feat(v2-tools): A6's engine for tools — URL model, interface without the bridge, WKWebView engine, local networking

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 4: `toggle_tools` (⌘⇧B / Ctrl+Shift+B), `add_tool` and `OpenToolIntent`

Three window intents and two keymap actions (D4, D10, D21):
- `toggle_tools`: bound by default to ⌘⇧B / Ctrl+Shift+B, which is free on both platforms.
- `add_tool`: no default chord; the user may bind one.
- `OpenToolIntent(toolId)`: built by the window for the palette.

`describeIntent` never prints a tool id. The actions run nothing yet: Task 13 wires them in the window.

**Files:**
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_intents.dart`, `apps/desktop/lib/src/config/keybind_actions.dart`, `apps/desktop/lib/src/config/keybindings.dart`, `apps/desktop/lib/src/ui/config/action_labels.dart`, `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`
- Test: `apps/desktop/test/config/keybindings_test.dart`, `apps/desktop/test/ui/shortcut_golden_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations.actionToggleTools`, `actionAddTool` (Task 2).
- Produces:
  - `class ToggleToolsIntent extends Intent { const ToggleToolsIntent(); }`
  - `class AddToolIntent extends Intent { const AddToolIntent(); }`
  - `class OpenToolIntent extends Intent { const OpenToolIntent(this.toolId); final String toolId; }`
  - `ActionSpec('toggle_tools', ActionGroup.window)` and `ActionSpec('add_tool', ActionGroup.window)`. `intentForAction` maps them to `ToggleToolsIntent()` / `AddToolIntent()`, and `describeIntent(OpenToolIntent(…)) == 'OpenToolIntent'`.
  - default binding `shifted(LogicalKeyboardKey.keyB)` → `toggle_tools`;
  - `String? toggleToolsShortcutLabel()` (`lib/src/ui/terminal/shortcut_labels.dart`): `⌘⇧B` / `Ctrl+Shift+B`.

- [ ] **Step 1: Write the failing tests**

In `apps/desktop/test/config/keybindings_test.dart`, replace:

````dart
    expect(codes(problems), [
      (1, ConfigProblemCode.badActionParam, ConfigSeverity.error),
    ]);
  });

  test('V2-1 D5: new_ai_session is ⌘⇧E / Ctrl+Shift+E; new_terminal_tab '
````

with:

````dart
    expect(codes(problems), [
      (1, ConfigProblemCode.badActionParam, ConfigSeverity.error),
    ]);
  });

  test('V2-3 D10: toggle_tools is ⌘⇧B / Ctrl+Shift+B; add_tool has no '
      'chord', () {
    var (b, problems) = resolve('');
    expect(problems, isEmpty);
    expect(lookup(b, 'super+shift+b'), isA<ToggleToolsIntent>());
    expect(b.labelOf(const KeyAction('toggle_tools')), '⌘⇧B');
    expect(b.labelOf(const KeyAction('add_tool')), isNull);
    (b, problems) = resolve('', platform: win);
    expect(lookup(b, 'ctrl+shift+b'), isA<ToggleToolsIntent>());
    expect(b.labelOf(const KeyAction('toggle_tools')), 'Ctrl+Shift+B');
    (b, problems) = resolve('keybind = super+shift+j=add_tool');
    expect(problems, isEmpty);
    expect(lookup(b, 'super+shift+j'), isA<AddToolIntent>());
  });

  test('V2-1 D5: new_ai_session is ⌘⇧E / Ctrl+Shift+E; new_terminal_tab '
````

In `apps/desktop/test/ui/shortcut_golden_test.dart`, replace:

````dart
    ? const {'shift+meta+65 norepeat -> NewAiSessionIntent'}
    : const {'ctrl+shift+65 norepeat -> NewAiSessionIntent'};

void main() {
  // No browser map: A6 is not merged ("browser pending A6").
  final maps =
````

with:

````dart
    ? const {'shift+meta+65 norepeat -> NewAiSessionIntent'}
    : const {'ctrl+shift+65 norepeat -> NewAiSessionIntent'};

/// V2-3 D10: "Show or hide tools" (⌘⇧B / Ctrl+Shift+B).
Set<String> v23Additions(String platform) => platform == 'mac'
    ? const {'shift+meta+62 norepeat -> ToggleToolsIntent'}
    : const {'ctrl+shift+62 norepeat -> ToggleToolsIntent'};

void main() {
  // No browser map: A6 is not merged ("browser pending A6").
  final maps =
````

In `apps/desktop/test/ui/shortcut_golden_test.dart`, replace:

````dart
              .union(a10Additions(name))
              .union(a11Additions(name))
              .union(a11Changes(name))
              .union(v21Additions(name)),
        );
      });
    }
````

with:

````dart
              .union(a10Additions(name))
              .union(a11Additions(name))
              .union(a11Changes(name))
              .union(v21Additions(name))
              .union(v23Additions(name)),
        );
      });
    }
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/keybindings_test.dart test/ui/shortcut_golden_test.dart
````

Expected: compilation fails, `The name 'ToggleToolsIntent' isn't a type` / `Undefined name 'ToggleToolsIntent'`.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/ui/terminal/terminal_intents.dart`, replace:

````dart
/// menu).
class NewTerminalTabIntent extends Intent {
  const NewTerminalTabIntent();
}

class CloseTabIntent extends Intent {
````

with:

````dart
/// menu).
class NewTerminalTabIntent extends Intent {
  const NewTerminalTabIntent();
}

/// V2-3 D10: ⌘⇧B / Ctrl+Shift+B, the AI header's tool button — show or
/// hide the tool dock of the selected tab's workspace.
class ToggleToolsIntent extends Intent {
  const ToggleToolsIntent();
}

/// V2-3 D4, D21: "Add tool…" (palette, sidebar foot).
class AddToolIntent extends Intent {
  const AddToolIntent();
}

/// V2-3 D4: "Open tool: {name}" (palette; built by the window, one per
/// tool).
class OpenToolIntent extends Intent {
  const OpenToolIntent(this.toolId);
  final String toolId;
}

class CloseTabIntent extends Intent {
````

In `apps/desktop/lib/src/config/keybind_actions.dart`, replace:

````dart
    ),
    const ActionSpec('next_region', ActionGroup.window, repeats: true),
    const ActionSpec('previous_region', ActionGroup.window, repeats: true),
    const ActionSpec(
      'toggle_command_palette',
      ActionGroup.window,
````

with:

````dart
    ),
    const ActionSpec('next_region', ActionGroup.window, repeats: true),
    const ActionSpec('previous_region', ActionGroup.window, repeats: true),
    // V2-3 D10: the tool dock (⌘⇧B / Ctrl+Shift+B); "Add tool…" has no
    // default chord.
    const ActionSpec('toggle_tools', ActionGroup.window),
    const ActionSpec('add_tool', ActionGroup.window),
    const ActionSpec(
      'toggle_command_palette',
      ActionGroup.window,
````

In `apps/desktop/lib/src/config/keybind_actions.dart`, replace:

````dart
  'new_tab' => const NewTabIntent(),
  'new_ai_session' => const NewAiSessionIntent(),
  'new_terminal_tab' => const NewTerminalTabIntent(),
  'close_surface' => const CloseTabIntent(),
  'close_tab' => const CloseWholeTabIntent(),
  'reopen_closed' => const ReopenClosedIntent(),
````

with:

````dart
  'new_tab' => const NewTabIntent(),
  'new_ai_session' => const NewAiSessionIntent(),
  'new_terminal_tab' => const NewTerminalTabIntent(),
  'toggle_tools' => const ToggleToolsIntent(),
  'add_tool' => const AddToolIntent(),
  'close_surface' => const CloseTabIntent(),
  'close_tab' => const CloseWholeTabIntent(),
  'reopen_closed' => const ReopenClosedIntent(),
````

In `apps/desktop/lib/src/config/keybind_actions.dart`, replace:

````dart
  WorkspaceFontIntent(:final step, :final reset) =>
    reset ? 'WorkspaceFontIntent(reset)' : 'WorkspaceFontIntent($step)',
  RunUserCommandIntent(:final name) => 'RunUserCommandIntent($name)',
  _ => i.runtimeType.toString(),
};
````

with:

````dart
  WorkspaceFontIntent(:final step, :final reset) =>
    reset ? 'WorkspaceFontIntent(reset)' : 'WorkspaceFontIntent($step)',
  RunUserCommandIntent(:final name) => 'RunUserCommandIntent($name)',
  OpenToolIntent() => 'OpenToolIntent',
  _ => i.runtimeType.toString(),
};
````

In `apps/desktop/lib/src/config/keybindings.dart`, replace:

````dart
    b(shifted(LogicalKeyboardKey.keyN), 'new_workspace'),
    // V2-1 D5: ⌘⇧E / Ctrl+Shift+E (free on both).
    b(shifted(LogicalKeyboardKey.keyE), 'new_ai_session'),
    b(shifted(LogicalKeyboardKey.keyK), 'ssh_connect'),
    b(shifted(LogicalKeyboardKey.keyI), 'toggle_notifications'),
    b(shifted(LogicalKeyboardKey.keyU), 'jump_to_unread'),
````

with:

````dart
    b(shifted(LogicalKeyboardKey.keyN), 'new_workspace'),
    // V2-1 D5: ⌘⇧E / Ctrl+Shift+E (free on both).
    b(shifted(LogicalKeyboardKey.keyE), 'new_ai_session'),
    // V2-3 D10: ⌘⇧B / Ctrl+Shift+B (free on both).
    b(shifted(LogicalKeyboardKey.keyB), 'toggle_tools'),
    b(shifted(LogicalKeyboardKey.keyK), 'ssh_connect'),
    b(shifted(LogicalKeyboardKey.keyI), 'toggle_notifications'),
    b(shifted(LogicalKeyboardKey.keyU), 'jump_to_unread'),
````

In `apps/desktop/lib/src/ui/config/action_labels.dart`, replace:

````dart
  'new_tab' => l10n.actionNewTab,
  'new_ai_session' => l10n.actionNewAiSession,
  'new_terminal_tab' => l10n.actionNewTerminalTab,
  'close_surface' => l10n.actionCloseSurface,
  'close_tab' => l10n.actionCloseTab,
  'new_workspace' => l10n.actionNewWorkspace,
````

with:

````dart
  'new_tab' => l10n.actionNewTab,
  'new_ai_session' => l10n.actionNewAiSession,
  'new_terminal_tab' => l10n.actionNewTerminalTab,
  'toggle_tools' => l10n.actionToggleTools,
  'add_tool' => l10n.actionAddTool,
  'close_surface' => l10n.actionCloseSurface,
  'close_tab' => l10n.actionCloseTab,
  'new_workspace' => l10n.actionNewWorkspace,
````

In `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`, replace:

````dart
    actionShortcutLabel(const KeyAction('new_tab'));
String? newAiSessionShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_ai_session'));
String? closeTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('close_surface'));
String? copyShortcutLabel() =>
````

with:

````dart
    actionShortcutLabel(const KeyAction('new_tab'));
String? newAiSessionShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_ai_session'));
String? toggleToolsShortcutLabel() =>
    actionShortcutLabel(const KeyAction('toggle_tools'));
String? closeTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('close_surface'));
String? copyShortcutLabel() =>
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/ui/terminal/terminal_intents.dart lib/src/config/keybind_actions.dart lib/src/config/keybindings.dart lib/src/ui/config/action_labels.dart lib/src/ui/terminal/shortcut_labels.dart test/config/keybindings_test.dart test/ui/shortcut_golden_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config test/ui/shortcut_golden_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `keybindings_test.dart` +21 and `shortcut_golden_test.dart` +4, all passed.
- `No issues found!`
- The whole suite: `3692 passed, 9 skipped`.

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/src/ui/terminal/terminal_intents.dart apps/desktop/lib/src/config/keybind_actions.dart \
  apps/desktop/lib/src/config/keybindings.dart apps/desktop/lib/src/ui/config/action_labels.dart \
  apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/test/config/keybindings_test.dart \
  apps/desktop/test/ui/shortcut_golden_test.dart
git commit -m "feat(v2-tools): toggle_tools (⌘⇧B / Ctrl+Shift+B), add_tool and the open-tool intent

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 5: Review and harden the macOS engine (D9, D10, D13, D16)

A6's macOS engine was parked as work in progress and never reviewed (spec §13). This task is that review. Each finding below is fixed here and pinned by a test (unit tests here, real WebKit in Task 6).

| # | Area | What the WIP did (Task 3's copy) | What it does now |
|---|---|---|---|
| 1 | D9 top frame | allowed http/https/`about:blank`, blocked everything else silently, even `mailto:`/`tel:` | `toolNavigation` (`lib/src/tools/tool_navigation.dart`) is injected as the engine's `NavigationPolicy`. Top frame: any http/https page (an SSO round trip included) and `about:blank`. `mailto:`/`tel:` → `OpenOutside` (the system). `file:`, `javascript:`, `data:`, unknown → blocked, no message. |
| 2 | D9 frames | every sub-frame navigation allowed | frames load http/https/`about`/`data`/`blob`; anything else is blocked |
| 3 | D9 new windows | the plugin's `WKUIDelegate` loaded `target=_blank`/`window.open` in the same view, so the tool navigated away | `NewWindowGuard` (Swift) answers "no window" and sends `newWindow` → `OpenOutside(newWindow: true)` for web/mail/phone, nothing otherwise (ruling R4) |
| 4 | D9 downloads | the plugin's response policy always allows: a zip replaced the page (seen in the isolated run) | `DownloadGuard` cancels a top-frame attachment or a type WebKit cannot show, and sends `download` → `DownloadBlocked(url)`. The guard's own cancel (WebKitErrorDomain 102) shows nothing. |
| 5 | D13 errors | NSURL codes read without their domain; WebKit 102 taken for a download; ATS −1022 was "other" | `macErrorEvent(domain, code, …)`. NSURLErrorDomain: −999 → nothing, −1004 → `refused`, −1022 → `ats`, −1003/−1006 → `dns`, −1001 → `timeout`, −1009/−1005/−1018/−1020 → `unreachable`, −1206…−1200 → `certificate`, else `other`. WebKitErrorDomain: 102 → nothing, 100 → `DownloadBlocked`, else `other`. A dead content process → `crashed`. |
| 6 | D9 permissions | the plugin's default | camera and microphone are denied (`onPermissionRequest: deny`, pinned by Task 6's camera test). ShellX declares no location usage, so WebKit cannot grant location either, and WKWebView gives third-party apps no web notifications. |
| 7 | D10 chord spelling | `alt+ctrl+meta+shift+key` from `charactersIgnoringModifiers`, so ⌘⇧1 read as `!` and arrows as `left`: no binding ever matched | Swift writes Dart's `chordConfigText` spelling: ctrl, alt, shift, super, then the key. Named keys go by key code (layout-independent, `keybind_trigger.dart` `_names`), characters by `characters(byApplyingModifiers: [])`, punctuation by name. The test "every forwarded chord reads back as the chord it came from" pins the Dart side. |
| 8 | D10 which chords | none chosen yet (A6 sent its own list) | `toolForwardedChords(bindings)`: every window binding of the live keymap (the user's own included) and every sequence's first step, minus `kToolPageActions` and cut/undo/redo (rulings R7, R8) |
| 9 | D10 sequences | a first step was swallowed | `resolveToolChord` maps a forwarded first step to `ToolChordPrefix`. The window then arms `KeySequence` (`arm`) and takes the keyboard back, so the second step reaches ShellX. |
| 10 | D10 focus | only a click on the page was reported; a click elsewhere left WebKit holding the keyboard | a click anywhere outside the page while the page has the keyboard makes the Flutter view first responder |
| 11 | ids | `setForwardedChords` registered any id | only `attach`ed ids are tool web views. `attach` installs the guards; `forget` (dispose) puts the plugin's delegates back. |
| 12 | D16 | no bootstrap/snapshot since Task 3 | a source scan (`tool_no_bridge_test.dart`) fails on any script, channel or snapshot API in the tool path (ruling R3) |
| 13 | D8, D22 | `clearWebsiteData` on the app's default store | unchanged: right per D8 (one store for every tool, `~/Library/WebKit/<bundle id>`) |
| 14 | retry | `reload()` after a failed first load | the page retries with `load(url)` (ruling R25, Task 10); the engine keeps `reload()` for ↻ on a loaded page |
| 15 | inspector | off | `setInspectable(true)`: Safari's Web Inspector reaches the user's own tool on macOS 13.3+ (ruling R28) |

**Files:**
- Create: `apps/desktop/lib/src/tools/tool_navigation.dart`, `apps/desktop/lib/src/tools/tool_keys.dart`
- Modify (whole file): `apps/desktop/lib/src/browser/engines/wk_webview_engine.dart`, `apps/desktop/macos/Runner/BrowserNative.swift`
- Modify: `apps/desktop/lib/src/ui/terminal/key_sequence.dart` (`arm`)
- Test: `apps/desktop/test/tools/tool_navigation_test.dart`, `apps/desktop/test/tools/tool_keys_test.dart`, `apps/desktop/test/tools/tool_no_bridge_test.dart`, `apps/desktop/test/browser/wk_webview_engine_test.dart` (whole file)

**Interfaces:**
- Consumes:
  - `KeyBindings` (`all`, `sequences`, `platform`), `KeyBinding` (`scope`, `action`, `sequence`), `KeyChord`, `KeyScope`;
  - `parseKeyChord(String)` and `chordConfigText(KeyChord)` (`lib/src/config/keybind_trigger.dart`), `intentForAction(KeyAction)` (`lib/src/config/keybind_actions.dart`);
  - `keySequenceProvider` / `KeySequence` (`lib/src/ui/terminal/key_sequence.dart`), `shellxConfigProvider`;
  - Task 3's `browser_engine.dart`.
- Produces:
  - `NavigationVerdict toolNavigation(Uri? url, {required bool mainFrame, required bool newWindow})`, a `NavigationPolicy`.
  - In `lib/src/tools/tool_keys.dart`:
    - `const Set<String> kToolPageActions` (`copy_to_clipboard`, `paste_from_clipboard`, `select_all`, `edit_line`, `text`, `csi`, `esc`, `ignore`);
    - `List<String> toolForwardedChords(KeyBindings bindings)` (sorted, config spelling);
    - `sealed class ToolChord`, `final class ToolChordIntent(Intent intent)`, `final class ToolChordPrefix(KeyChord prefix)`;
    - `ToolChord? resolveToolChord(KeyBindings bindings, String text)`.
  - `bool KeySequence.arm(KeyChord prefix)`.
  - In `wk_webview_engine.dart`:
    - `BrowserEngineEvent? macErrorEvent(String? domain, int code, {bool processTerminated = false, Uri? url})`;
    - `Future<void> BrowserNativeMac.attach(int webViewId, {required void Function(BrowserEngineEvent event) sink, required void Function(Uri? url) newWindow})`;
    - `WkWebViewEngine({required BrowserNativeMac native, required NavigationPolicy policy, BrowserDialogPresenter? dialogs})`.
  - Channel `pro.shellx.desktop/browser`:
    - Dart → native: `attach {id}`, `forget {id}`, `stop {id}`, `focus {id}`, `blur {id}`, `setForwardedChords {id, chords}`, `clearWebsiteData`;
    - native → Dart: `shortcut {id, chord}`, `pointerDown {id}`, `newWindow {id, url?}`, `download {id, url?}`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/tools/tool_navigation_test.dart`:

````dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/tools/tool_navigation.dart';

NavigationVerdict top(String url) =>
    toolNavigation(Uri.tryParse(url), mainFrame: true, newWindow: false);
NavigationVerdict window(String url) =>
    toolNavigation(Uri.tryParse(url), mainFrame: true, newWindow: true);
NavigationVerdict frame(String url) =>
    toolNavigation(Uri.tryParse(url), mainFrame: false, newWindow: false);

void main() {
  const allow = NavigationVerdict.allow;
  const outside = NavigationVerdict.outside;
  const block = NavigationVerdict.block;

  test('the top frame: any http/https page, about:blank; mail and phone '
      'outside; anything else blocked (D9, Review Focus 5)', () {
    expect(top('http://localhost:5173/x'), allow);
    expect(top('https://sso.example.com/login'), allow, reason: 'SSO');
    expect(top('about:blank'), allow);
    expect(top('mailto:a@b.c'), outside);
    expect(top('tel:+84123'), outside);
    for (final url in [
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,hi',
      'blob:http://localhost/1',
      'shellx-test://x',
      'about:srcdoc',
      'http://',
    ]) {
      expect(top(url), block, reason: url);
    }
    expect(toolNavigation(null, mainFrame: true, newWindow: false), block);
  });

  test('a new window never opens in the tool: web, mail and phone go '
      'outside, the rest nowhere (D9)', () {
    expect(window('https://docs.example.com/'), outside);
    expect(window('http://localhost:5173/other'), outside);
    expect(window('mailto:a@b.c'), outside);
    expect(window('javascript:alert(1)'), block);
    expect(window('file:///x'), block);
  });

  test('frames of the page load web, about, data and blob content; the '
      'rest is blocked', () {
    expect(frame('https://embed.example.com/'), allow);
    expect(frame('about:srcdoc'), allow);
    expect(frame('data:text/html,hi'), allow);
    expect(frame('blob:http://localhost/1'), allow);
    expect(frame('mailto:a@b.c'), block);
    expect(frame('file:///x'), block);
  });
}
````

`apps/desktop/test/tools/tool_keys_test.dart`:

````dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/tools/tool_keys.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

KeyBindings bindingsFor(
  TargetPlatform platform, [
  List<String> lines = const [],
]) {
  final problems = <ConfigProblem>[];
  var n = 0;
  return resolveKeyBindings(
    platform: platform,
    entries: [
      for (final l in lines)
        KeybindEntry(
          l,
          ConfigEntry(file: '/c', line: ++n, key: 'keybind', value: l),
        ),
    ],
    commandNames: const {},
    optionAsAlt: OptionAsAlt.off,
    problems: problems,
  );
}

void main() {
  const mac = TargetPlatform.macOS;

  test('the forwarded chords are the window keymap (Review Focus 2): ⌘T, '
      '⌘W, ⌘1…9, ⌘⇧E, ⌘⇧P, ⌘⇧B forward; ⌘C/⌘V/⌘A/⌘X/⌘Z and the prompt '
      'keys stay with the page (D10)', () {
    final chords = toolForwardedChords(KeyBindings.defaults(mac));
    for (final c in [
      'super+t',
      'super+w',
      'super+1',
      'super+9',
      'shift+super+e',
      'shift+super+p',
      'shift+super+b',
      'alt+super+arrow_right',
      'ctrl+f6',
    ]) {
      expect(chords, contains(c), reason: c);
    }
    for (final c in [
      'super+c',
      'super+v',
      'super+a',
      'super+x',
      'super+z',
      'shift+super+z',
      'super+arrow_left',
      'super+backspace',
      'alt+backspace',
    ]) {
      expect(chords, isNot(contains(c)), reason: c);
    }
  });

  test("the user's own keys count, and a sequence's first step forwards "
      '(D10)', () {
    final b = bindingsFor(mac, [
      'super+shift+j=new_tab',
      'ctrl+a>c=new_tab',
      'super+t=unbind',
    ]);
    final chords = toolForwardedChords(b);
    expect(chords, contains('shift+super+j'));
    expect(chords, contains('ctrl+a'));
    expect(chords, isNot(contains('super+t')));
  });

  test('every forwarded chord reads back as the chord it came from', () {
    for (final platform in [mac, TargetPlatform.windows]) {
      for (final text in toolForwardedChords(KeyBindings.defaults(platform))) {
        expect(chordConfigText(parseKeyChord(text)!), text, reason: text);
      }
    }
  });

  test('resolveToolChord: a binding gives its intent, a first step its '
      'prefix, anything else nothing', () {
    final b = bindingsFor(mac, ['ctrl+a>c=new_tab']);
    expect(
      (resolveToolChord(b, 'super+t')! as ToolChordIntent).intent,
      isA<NewTabIntent>(),
    );
    expect(
      (resolveToolChord(b, 'shift+super+b')! as ToolChordIntent).intent,
      isA<ToggleToolsIntent>(),
    );
    expect(
      (resolveToolChord(b, 'ctrl+a')! as ToolChordPrefix).prefix,
      const KeyChord(LogicalKeyboardKey.keyA, control: true),
    );
    expect(resolveToolChord(b, 'super+c'), isNull, reason: 'the page’s');
    expect(resolveToolChord(b, 'shift+super+q'), isNull);
    expect(resolveToolChord(b, 'not a chord'), isNull);
  });

  test('KeySequence.arm starts the wait for a known first step only', () async {
    final fs = MemoryConfigFs()
      ..write(testConfigPaths().shellx, 'keybind = ctrl+a>c=new_tab\n');
    final c = ProviderContainer.test(overrides: configOverrides(fs));
    await loadConfig(c);
    final seq = c.read(keySequenceProvider.notifier);
    expect(
      seq.arm(const KeyChord(LogicalKeyboardKey.keyB, control: true)),
      isFalse,
    );
    expect(c.read(keySequenceProvider), isNull);
    expect(
      seq.arm(const KeyChord(LogicalKeyboardKey.keyA, control: true)),
      isTrue,
    );
    expect(
      c.read(keySequenceProvider),
      const KeyChord(LogicalKeyboardKey.keyA, control: true),
    );
  });
}
````

`apps/desktop/test/tools/tool_no_bridge_test.dart`:

````dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V2-3 D16: ShellX never runs code in a tool's page — no JavaScript
/// channel, no script, no snapshot — and the engine says so in its source.
void main() {
  test('no bridge, script or snapshot in the tool path (D16)', () {
    const banned = [
      'runJavaScript',
      'runJavaScriptReturningResult',
      'addJavaScriptChannel',
      'addUserScript',
      'WKUserScript',
      'takeSnapshot',
      'evaluateJavaScript',
      'capturePng',
    ];
    final files = [
      for (final dir in [
        'lib/src/browser',
        'lib/src/tools',
        'lib/src/ui/tools',
      ])
        // `lib/src/ui/tools` comes with the dock (plan Task 12).
        if (Directory(dir).existsSync())
          ...Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      File('macos/Runner/BrowserNative.swift'),
    ];
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final word in banned) {
        expect(text, isNot(contains(word)), reason: '${f.path}: $word');
      }
    }
  });
}
````

Replace the whole of `apps/desktop/test/browser/wk_webview_engine_test.dart` with:

````dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BrowserLoadErrorKind? kind(String domain, int code) =>
      switch (macErrorEvent(domain, code)) {
        LoadFailed(:final kind) => kind,
        _ => null,
      };

  test('NSURLError codes map to the D13 kinds, ATS included', () {
    const u = 'NSURLErrorDomain';
    expect(kind(u, -1004), BrowserLoadErrorKind.refused);
    expect(kind(u, -1022), BrowserLoadErrorKind.ats);
    expect(kind(u, -1003), BrowserLoadErrorKind.dns);
    expect(kind(u, -1006), BrowserLoadErrorKind.dns);
    expect(kind(u, -1001), BrowserLoadErrorKind.timeout);
    for (final c in [-1009, -1005, -1018, -1020]) {
      expect(kind(u, c), BrowserLoadErrorKind.unreachable, reason: '$c');
    }
    for (final c in [-1200, -1201, -1202, -1203, -1204, -1205, -1206]) {
      expect(kind(u, c), BrowserLoadErrorKind.certificate, reason: '$c');
    }
    expect(kind(u, -1100), BrowserLoadErrorKind.other);
    expect(macErrorEvent(u, -999), isNull, reason: 'a newer navigation');
  });

  test('WebKit 100 is a stopped download, 102 the guard\'s own cancel; a '
      'dead page is crashed', () {
    final url = Uri.parse('http://localhost:4000/export.csv');
    final download = macErrorEvent('WebKitErrorDomain', 100, url: url);
    expect(download, isA<DownloadBlocked>());
    expect((download! as DownloadBlocked).url, url);
    expect(macErrorEvent('WebKitErrorDomain', 102), isNull);
    expect(kind('WebKitErrorDomain', 101), BrowserLoadErrorKind.other);
    expect(switch (macErrorEvent('WKErrorDomain', 2, processTerminated: true)) {
      LoadFailed(:final kind) => kind,
      _ => null,
    }, BrowserLoadErrorKind.crashed);
    expect(kind('SomethingElse', 1), BrowserLoadErrorKind.other);
  });

  test('BrowserNativeMac: outbound calls and inbound events', () async {
    const channel = MethodChannel('test/browser');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final native = BrowserNativeMac(channel);
    final events = <BrowserEngineEvent>[];
    final windows = <Uri?>[];
    await native.attach(7, sink: events.add, newWindow: windows.add);
    await native.setForwardedChords(7, ['super+t']);
    await native.stop(7);
    await native.focus(7);
    await native.blur(7);
    await native.clearAll();
    expect(calls.map((c) => c.method), [
      'attach',
      'setForwardedChords',
      'stop',
      'focus',
      'blur',
      'clearWebsiteData',
    ]);
    expect(calls[1].arguments, {
      'id': 7,
      'chords': ['super+t'],
    });

    Future<void> inbound(String method, Map<String, Object?> args) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await inbound('shortcut', {'id': 7, 'chord': 'super+t'});
    await inbound('pointerDown', {'id': 7});
    await inbound('newWindow', {'id': 7, 'url': 'https://example.com/x'});
    await inbound('newWindow', {'id': 7});
    await inbound('download', {'id': 7, 'url': 'http://h/a.zip'});
    await inbound('shortcut', {'id': 99, 'chord': 'super+t'}); // not ours
    expect(events, hasLength(3));
    expect((events[0] as ShortcutForwarded).chord, 'super+t');
    expect(events[1], isA<ContentClicked>());
    expect((events[2] as DownloadBlocked).url, Uri.parse('http://h/a.zip'));
    expect(windows, [Uri.parse('https://example.com/x'), null]);
    native.detach(7);
    await inbound('pointerDown', {'id': 7});
    expect(events, hasLength(3));
    expect(calls.last.method, 'forget');
  });

  test('events and dialogs never print what the page holds (D24)', () {
    expect(
      UrlChanged(Uri.parse('http://x/secret')).toString(),
      'UrlChanged(…)',
    );
    expect(const TitleChanged('secret').toString(), 'TitleChanged(…)');
    expect(
      OpenOutside(Uri.parse('mailto:a@b.c'), newWindow: false).toString(),
      'OpenOutside(…)',
    );
    expect(
      const BrowserJsDialog(
        kind: BrowserJsDialogKind.prompt,
        message: 'secret',
      ).toString(),
      'BrowserJsDialog(prompt)',
    );
  });
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_navigation_test.dart test/tools/tool_keys_test.dart test/tools/tool_no_bridge_test.dart test/browser/wk_webview_engine_test.dart
````

Expected:
- the first two fail to compile (`Error when reading 'lib/src/tools/tool_navigation.dart'` / `'lib/src/tools/tool_keys.dart'`);
- `tool_no_bridge_test.dart` passes already (Task 3 left no bridge);
- `wk_webview_engine_test.dart` fails to compile: `Method not found: 'macErrorEvent'`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/tools/tool_navigation.dart`:

````dart
import '../browser/browser_engine.dart';

/// Pages a frame of a tool may show besides http/https (an iframe of
/// `about:srcdoc`, `data:` or `blob:` content stays inside the page).
const Set<String> _frameSchemes = {'http', 'https', 'about', 'data', 'blob'};

/// Links the operating system answers (mail, phone).
const Set<String> _systemSchemes = {'mailto', 'tel'};

/// V2-3 D9: where a navigation of a tool's page goes.
/// - The top frame: any http/https page (an SSO round trip included);
///   `about:blank`; `mailto:`/`tel:` go outside; anything else (`file:`,
///   `javascript:`, `data:`, an unknown scheme) is blocked, silently.
/// - A new window (`target=_blank`, `window.open`): outside for http,
///   https, mailto and tel; blocked otherwise. Never inside the tool.
/// - Another frame: http/https/about/data/blob load; the rest is blocked.
NavigationVerdict toolNavigation(
  Uri? url, {
  required bool mainFrame,
  required bool newWindow,
}) {
  if (url == null) return NavigationVerdict.block;
  final scheme = url.scheme.toLowerCase();
  final web = (scheme == 'http' || scheme == 'https') && url.host.isNotEmpty;
  if (newWindow) {
    return web || _systemSchemes.contains(scheme)
        ? NavigationVerdict.outside
        : NavigationVerdict.block;
  }
  if (!mainFrame) {
    return _frameSchemes.contains(scheme)
        ? NavigationVerdict.allow
        : NavigationVerdict.block;
  }
  if (web || url.toString() == 'about:blank') return NavigationVerdict.allow;
  if (_systemSchemes.contains(scheme)) return NavigationVerdict.outside;
  return NavigationVerdict.block;
}
````

`apps/desktop/lib/src/tools/tool_keys.dart`:

````dart
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show Intent;

import '../config/keybind_actions.dart';
import '../config/keybind_trigger.dart';
import '../config/keybindings.dart';

/// D10: actions whose chords stay with the page — copy, paste and select
/// all (the spec), and ruling R7: what only acts on a terminal that has the
/// keyboard (prompt editing ⌘←/⌘→/⌘⌫/⌥⌫/⌥⌦, typed text, `ignore`), which
/// would only take the page's own editing keys away.
const Set<String> kToolPageActions = {
  'copy_to_clipboard',
  'paste_from_clipboard',
  'select_all',
  'edit_line',
  'text',
  'csi',
  'esc',
  'ignore',
};

/// D10: cut, undo and redo stay with the page whatever they are bound to.
Set<KeyChord> _pageChords(TargetPlatform platform) =>
    platform == TargetPlatform.macOS
    ? {
        const KeyChord(LogicalKeyboardKey.keyX, meta: true),
        const KeyChord(LogicalKeyboardKey.keyZ, meta: true),
        const KeyChord(LogicalKeyboardKey.keyZ, meta: true, shift: true),
      }
    : {
        const KeyChord(LogicalKeyboardKey.keyX, control: true),
        const KeyChord(LogicalKeyboardKey.keyZ, control: true),
        const KeyChord(LogicalKeyboardKey.keyY, control: true),
        const KeyChord(LogicalKeyboardKey.keyZ, control: true, shift: true),
      };

/// D10: the chords a page hands back to ShellX while it has the keyboard,
/// in the config spelling BrowserNative.swift compares (`chordConfigText`):
/// every window binding of the live keymap — the user's own included — and
/// the first step of every two-step sequence, but none of [kToolPageActions]
/// and no cut/undo/redo chord.
List<String> toolForwardedChords(KeyBindings bindings) {
  final keep = _pageChords(bindings.platform);
  final out = <String>{};
  for (final b in bindings.all) {
    if (b.scope != KeyScope.window) continue;
    if (kToolPageActions.contains(b.action.name)) continue;
    final chord = b.sequence.first;
    if (keep.contains(chord)) continue;
    final text = chordConfigText(chord);
    if (text != null) out.add(text);
  }
  return out.toList()..sort();
}

/// What a chord the page handed back does: a binding's intent, or the
/// first step of a sequence ([prefix]); null when it is neither any more (a
/// reload changed the keys meanwhile).
sealed class ToolChord {
  const ToolChord();
}

final class ToolChordIntent extends ToolChord {
  const ToolChordIntent(this.intent);
  final Intent intent;
}

final class ToolChordPrefix extends ToolChord {
  const ToolChordPrefix(this.prefix);
  final KeyChord prefix;
}

ToolChord? resolveToolChord(KeyBindings bindings, String text) {
  final chord = parseKeyChord(text);
  if (chord == null) return null;
  for (final b in bindings.all) {
    if (b.scope == KeyScope.window &&
        b.sequence.length == 1 &&
        b.sequence.single == chord &&
        !kToolPageActions.contains(b.action.name)) {
      return ToolChordIntent(intentForAction(b.action));
    }
  }
  if (bindings.sequences.any((b) => b.sequence.first == chord)) {
    return ToolChordPrefix(chord);
  }
  return null;
}
````

In `apps/desktop/lib/src/ui/terminal/key_sequence.dart`, replace:

````dart

  void cancel() {
    if (state != null) state = null;
  }

  /// Handles one key. Handled: swallowed (a prefix, the step that ran, Esc,
````

with:

````dart

  void cancel() {
    if (state != null) state = null;
  }

  /// V2-3 D10: a tool page handed back [prefix] (the first step of a
  /// sequence): the wait starts as if the key had been pressed here. False
  /// when no sequence starts with it.
  bool arm(KeyChord prefix) {
    final sequences = ref.read(shellxConfigProvider).bindings.sequences;
    if (!sequences.any((b) => b.sequence.first == prefix)) return false;
    _seen = null;
    state = prefix;
    return true;
  }

  /// Handles one key. Handled: swallowed (a prefix, the step that ran, Esc,
````

Replace the whole of `apps/desktop/lib/src/browser/engines/wk_webview_engine.dart` with:

````dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../browser_engine.dart';

const String browserNativeChannelName = 'pro.shellx.desktop/browser';

typedef _NativeSink = ({
  void Function(BrowserEngineEvent event) sink,
  void Function(Uri? url) newWindow,
});

/// D9, D13: what a main-frame error of [domain] / [code] is — an error for
/// the panel, a stopped download, or nothing to show (null: a newer
/// navigation cancelled this one).
BrowserEngineEvent? macErrorEvent(
  String? domain,
  int code, {
  bool processTerminated = false,
  Uri? url,
}) {
  if (processTerminated) return const LoadFailed(BrowserLoadErrorKind.crashed);
  switch (domain) {
    case 'WebKitErrorDomain':
      // 102 "frame load interrupted": BrowserNative's download guard
      // cancelled the response and already said so. 100: a type WebKit
      // cannot show that slipped past the guard.
      if (code == 102) return null;
      if (code == 100) return DownloadBlocked(url: url);
      return const LoadFailed(BrowserLoadErrorKind.other);
    case 'NSURLErrorDomain':
      final kind = switch (code) {
        -999 => null,
        -1004 => BrowserLoadErrorKind.refused,
        -1022 => BrowserLoadErrorKind.ats,
        -1003 || -1006 => BrowserLoadErrorKind.dns,
        -1001 => BrowserLoadErrorKind.timeout,
        -1009 || -1005 || -1018 || -1020 => BrowserLoadErrorKind.unreachable,
        >= -1206 && <= -1200 => BrowserLoadErrorKind.certificate,
        _ => BrowserLoadErrorKind.other,
      };
      return kind == null ? null : LoadFailed(kind);
    default:
      return const LoadFailed(BrowserLoadErrorKind.other);
  }
}

/// The app's one `pro.shellx.desktop/browser` channel (BrowserNative.swift).
final class BrowserNativeMac implements BrowserDataStore {
  BrowserNativeMac([
    MethodChannel channel = const MethodChannel(browserNativeChannelName),
  ]) : _channel = channel;

  final MethodChannel _channel;
  final Map<int, _NativeSink> _sinks = {};
  bool _listening = false;

  /// Starts forwarding [webViewId]'s native events: chords and clicks to
  /// [sink], new windows (D9) to [newWindow] (BrowserNative `attach`).
  Future<void> attach(
    int webViewId, {
    required void Function(BrowserEngineEvent event) sink,
    required void Function(Uri? url) newWindow,
  }) {
    // Lazily, so merely constructing it (a provider) needs no binding.
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_onCall);
    }
    _sinks[webViewId] = (sink: sink, newWindow: newWindow);
    return _channel.invokeMethod<void>('attach', {'id': webViewId});
  }

  void detach(int webViewId) {
    _sinks.remove(webViewId);
    unawaited(
      _channel
          .invokeMethod<void>('forget', {'id': webViewId})
          .catchError((_) {}),
    );
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final target = _sinks[args['id']];
    if (target == null) return;
    switch (call.method) {
      case 'shortcut':
        final chord = args['chord'];
        if (chord is String) target.sink(ShortcutForwarded(chord));
      case 'pointerDown':
        target.sink(const ContentClicked());
      case 'newWindow':
        final url = args['url'];
        target.newWindow(url is String ? Uri.tryParse(url) : null);
      case 'download':
        final url = args['url'];
        target.sink(
          DownloadBlocked(url: url is String ? Uri.tryParse(url) : null),
        );
    }
  }

  Future<void> stop(int id) => _channel.invokeMethod<void>('stop', {'id': id});
  Future<void> focus(int id) =>
      _channel.invokeMethod<void>('focus', {'id': id});
  Future<void> blur(int id) => _channel.invokeMethod<void>('blur', {'id': id});
  Future<void> setForwardedChords(int id, List<String> chords) => _channel
      .invokeMethod<void>('setForwardedChords', {'id': id, 'chords': chords});

  /// D8, D22: the app's default WebKit store (`~/Library/WebKit/<bundle id>`).
  @override
  Future<void> clearAll() => _channel.invokeMethod<void>('clearWebsiteData');
}

/// The app's one native channel (macOS); its handler registers lazily.
final browserNativeMacProvider = Provider<BrowserNativeMac>(
  (ref) => BrowserNativeMac(),
);

/// A6 D1 for V2-3 (D6): WKWebView through webview_flutter_wkwebview, as a
/// platform view, in the app's default data store (D8). No JavaScript
/// channel, no user script, no snapshot (D16). [policy] decides every
/// navigation (D9); [dialogs] shows the page's alert/confirm/prompt.
final class WkWebViewEngine implements BrowserEngine {
  WkWebViewEngine({
    required BrowserNativeMac native,
    required NavigationPolicy policy,
    BrowserDialogPresenter? dialogs,
  }) : _native = native,
       _policy = policy,
       _dialogs = dialogs {
    // D9: camera and microphone are refused (the app has no usage
    // description, and a tool gets no device).
    _controller = WebViewController.fromPlatformCreationParams(
      WebKitWebViewControllerCreationParams(),
      onPermissionRequest: (request) => unawaited(request.deny()),
    );
    _platform = _controller.platform as WebKitWebViewController;
    _id = _platform.webViewIdentifier;
    _ready = _setup();
  }

  final BrowserNativeMac _native;
  final NavigationPolicy _policy;
  final BrowserDialogPresenter? _dialogs;
  late final WebViewController _controller;
  late final WebKitWebViewController _platform;
  late final int _id;
  late final Future<void> _ready;
  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast();

  void _emit(BrowserEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  /// D9: a new window never opens, here or in a second view: it goes
  /// outside (http, https, mailto, tel) or nowhere.
  void _newWindow(Uri? url) {
    final verdict = _policy(url, mainFrame: true, newWindow: true);
    if (verdict == NavigationVerdict.outside && url != null) {
      _emit(OpenOutside(url, newWindow: true));
    } else {
      _emit(const NavigationBlocked());
    }
  }

  Future<void> _setup() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Safari's Web Inspector reaches the user's own tool (macOS 13.3+).
    await _platform.setInspectable(true);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final url = Uri.tryParse(request.url);
          final verdict = _policy(
            url,
            mainFrame: request.isMainFrame,
            newWindow: false,
          );
          switch (verdict) {
            case NavigationVerdict.allow:
              return NavigationDecision.navigate;
            case NavigationVerdict.outside when url != null:
              _emit(OpenOutside(url, newWindow: false));
            case _:
              _emit(const NavigationBlocked());
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => _emit(const LoadStarted()),
        onProgress: (p) => _emit(LoadProgress(p)),
        onPageFinished: (_) async {
          _emit(const LoadFinished());
          await _history();
          final title = await _controller.getTitle();
          if (title != null) _emit(TitleChanged(title));
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (uri != null) _emit(UrlChanged(uri));
          unawaited(_history());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false) return;
          final event = macErrorEvent(
            error is WebKitWebResourceError ? error.domain : null,
            error.errorCode,
            processTerminated:
                error.errorType ==
                WebResourceErrorType.webContentProcessTerminated,
            url: Uri.tryParse(error.url ?? ''),
          );
          if (event != null) _emit(event);
        },
      ),
    );
    await _controller.setOnJavaScriptAlertDialog((r) async {
      await _dialogs?.call(
        BrowserJsDialog(kind: BrowserJsDialogKind.alert, message: r.message),
      );
    });
    await _controller.setOnJavaScriptConfirmDialog((r) async {
      final ok = await _dialogs?.call(
        BrowserJsDialog(kind: BrowserJsDialogKind.confirm, message: r.message),
      );
      return ok == true;
    });
    await _controller.setOnJavaScriptTextInputDialog((r) async {
      final text = await _dialogs?.call(
        BrowserJsDialog(
          kind: BrowserJsDialogKind.prompt,
          message: r.message,
          defaultText: r.defaultText,
        ),
      );
      return text is String ? text : '';
    });
    // Last: the plugin's own UI delegate is set by now, and BrowserNative
    // stands its new-window guard in front of it.
    await _native.attach(_id, sink: _emit, newWindow: _newWindow);
  }

  Future<void> _history() async => _emit(
    HistoryChanged(
      canGoBack: await _controller.canGoBack(),
      canGoForward: await _controller.canGoForward(),
    ),
  );

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  bool get coversFlutter => false;

  @override
  Future<void> load(Uri url) async {
    await _ready;
    await _controller.loadRequest(url);
  }

  @override
  Future<void> goBack() async {
    await _ready;
    await _controller.goBack();
  }

  @override
  Future<void> goForward() async {
    await _ready;
    await _controller.goForward();
  }

  @override
  Future<void> reload() async {
    await _ready;
    await _controller.reload();
  }

  @override
  Future<void> stop() async {
    await _ready;
    await _native.stop(_id);
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async {
    await _ready;
    await _native.setForwardedChords(_id, chords);
  }

  @override
  Future<void> focusContent() async {
    await _ready;
    await _native.focus(_id);
  }

  @override
  Future<void> releaseFocus() async {
    await _ready;
    await _native.blur(_id);
  }

  @override
  Future<void> setVisible(bool visible) async {}

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    _native.detach(_id);
    await _events.close();
  }
}
````

Replace the whole of `apps/desktop/macos/Runner/BrowserNative.swift` with:

````swift
import Cocoa
import FlutterMacOS
import WebKit
import webview_flutter_wkwebview

/// V2-3 (A6 Task 7, taken for tools): what webview_flutter's Dart API
/// lacks — stopping a load, clearing the app's website data, keeping a page's
/// new windows out of the tool, and handing ShellX chords and clicks back to
/// Flutter while a page has the keyboard (spec D8, D9, D10). Channel
/// "pro.shellx.desktop/browser". No script, no snapshot (D16). Never logs a
/// URL, a title or page content.
final class BrowserNative: NSObject {
  private let channel: FlutterMethodChannel
  private let controller: FlutterViewController
  /// Web view id → chords to forward (config spelling, Dart's
  /// `chordConfigText`). An id is known once Dart attached it.
  private var forwarded: [Int64: Set<String>] = [:]
  /// Web view id → the guards standing in front of the plugin's delegates.
  private var windowGuards: [Int64: NewWindowGuard] = [:]
  private var downloadGuards: [Int64: DownloadGuard] = [:]
  private var keyMonitor: Any?
  private var mouseMonitor: Any?

  init(controller: FlutterViewController) {
    self.controller = controller
    channel = FlutterMethodChannel(
      name: "pro.shellx.desktop/browser",
      binaryMessenger: controller.engine.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result) ?? result(nil)
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self, let id = self.toolWebViewId(firstResponderOf: event),
        let chord = BrowserNative.chord(event),
        self.forwarded[id]?.contains(chord) == true
      else { return event }
      self.channel.invokeMethod("shortcut", arguments: ["id": id, "chord": chord])
      return nil  // D10: the page never sees a ShellX chord
    }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      if let id = self.toolWebViewId(under: event) {
        self.channel.invokeMethod("pointerDown", arguments: ["id": id])
      } else if self.toolWebViewId(firstResponderOf: event) != nil {
        // D10: a click anywhere outside the page gives the keyboard back to
        // Flutter, whatever was clicked.
        event.window?.makeFirstResponder(self.controller.view)
      }
      return event
    }
  }

  deinit {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
  }

  /// The WKWebView behind a Dart `WebKitWebViewController.webViewIdentifier`
  /// (the plugin's public native API, stable across its versions).
  private func webView(_ id: Int64) -> WKWebView? {
    FWFWebViewFlutterWKWebViewExternalAPI.webView(
      forIdentifier: id, withPluginRegistry: controller)
  }

  private func toolWebViewId(firstResponderOf event: NSEvent) -> Int64? {
    guard let view = event.window?.firstResponder as? NSView else { return nil }
    return toolWebViewId(containing: view)
  }

  private func toolWebViewId(under event: NSEvent) -> Int64? {
    guard let content = event.window?.contentView,
      let hit = content.hitTest(event.locationInWindow)
    else { return nil }
    return toolWebViewId(containing: hit)
  }

  private func toolWebViewId(containing view: NSView) -> Int64? {
    var current: NSView? = view
    while let v = current, !(v is WKWebView) { current = v.superview }
    guard let web = current as? WKWebView else { return nil }
    return forwarded.keys.first { webView($0) === web }
  }

  /// Keys named by their code (layout-independent), in Dart's config
  /// spelling (`keybind_trigger.dart` `_names`, first name of each key).
  static let namedKeys: [UInt16: String] = [
    36: "enter", 76: "kp_enter", 48: "tab", 53: "escape", 49: "space",
    51: "backspace", 117: "delete", 114: "insert", 115: "home", 119: "end",
    116: "page_up", 121: "page_down", 123: "arrow_left", 124: "arrow_right",
    125: "arrow_down", 126: "arrow_up", 122: "f1", 120: "f2", 99: "f3",
    118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9",
    109: "f10", 103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15",
    106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20", 69: "kp_add",
    78: "kp_subtract", 82: "kp_0", 83: "kp_1", 84: "kp_2", 85: "kp_3",
    86: "kp_4", 87: "kp_5", 88: "kp_6", 89: "kp_7", 91: "kp_8", 92: "kp_9",
  ]

  /// Punctuation by the character the key types without modifiers.
  static let punctuation: [String: String] = [
    "=": "equal", "-": "minus", "+": "plus", ",": "comma", ".": "period",
    "/": "slash", "\\": "backslash", ";": "semicolon", "'": "quote",
    "`": "backquote", "[": "bracket_left", "]": "bracket_right",
  ]

  /// The key of [event] as Dart's `chordConfigText` writes it; nil for a
  /// key Dart has no name for.
  static func keyName(_ event: NSEvent) -> String? {
    if let named = namedKeys[event.keyCode] { return named }
    // The character without Shift, Option or Command: ⌘⇧1 is "1", ⌘⇧= is
    // "=", as Flutter's logical key is.
    guard let raw = event.characters(byApplyingModifiers: []), raw.count == 1
    else { return nil }
    let c = raw.lowercased()
    if let p = punctuation[c] { return p }
    guard let scalar = c.unicodeScalars.first else { return nil }
    if scalar.value < 0x80 {
      let letter = scalar.value >= 0x61 && scalar.value <= 0x7a
      let digit = scalar.value >= 0x30 && scalar.value <= 0x39
      return letter || digit ? c : nil
    }
    return c  // a layout's own letter (ö, é), as Dart writes it
  }

  /// [event] as Dart's `chordConfigText` writes a chord: ctrl, alt, shift,
  /// super, then the key.
  static func chord(_ event: NSEvent) -> String? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard let key = keyName(event) else { return nil }
    var parts: [String] = []
    if flags.contains(.control) { parts.append("ctrl") }
    if flags.contains(.option) { parts.append("alt") }
    if flags.contains(.shift) { parts.append("shift") }
    if flags.contains(.command) { parts.append("super") }
    parts.append(key)
    return parts.joined(separator: "+")
  }

  private func send(_ method: String, id: Int64, url: URL?) {
    var arguments: [String: Any] = ["id": id]
    if let url { arguments["url"] = url.absoluteString }
    channel.invokeMethod(method, arguments: arguments)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = (args["id"] as? NSNumber)?.int64Value
    switch call.method {
    case "clearWebsiteData":
      // D8, D22: the app's default store — every tool's cookies and storage.
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast
      ) { result(nil) }
      return
    case "setForwardedChords":
      if let id, forwarded[id] != nil {
        forwarded[id] = Set(args["chords"] as? [String] ?? [])
      }
      result(nil)
      return
    case "forget":
      if let id {
        forwarded.removeValue(forKey: id)
        let web = webView(id)
        if let guardian = windowGuards.removeValue(forKey: id),
          let web, web.uiDelegate === guardian
        {
          web.uiDelegate = guardian.inner
        }
        if let guardian = downloadGuards.removeValue(forKey: id),
          let web, web.navigationDelegate === guardian
        {
          web.navigationDelegate = guardian.inner
        }
      }
      result(nil)
      return
    default:
      break
    }
    guard let id, let web = webView(id) else {
      result(FlutterError(code: "not_found", message: nil, details: nil))
      return
    }
    switch call.method {
    case "attach":
      if forwarded[id] == nil { forwarded[id] = [] }
      if windowGuards[id] == nil, let inner = web.uiDelegate {
        let guardian = NewWindowGuard(inner: inner) { [weak self] url in
          self?.send("newWindow", id: id, url: url)
        }
        windowGuards[id] = guardian
        web.uiDelegate = guardian
      }
      if downloadGuards[id] == nil, let inner = web.navigationDelegate {
        let guardian = DownloadGuard(inner: inner) { [weak self] url in
          self?.send("download", id: id, url: url)
        }
        downloadGuards[id] = guardian
        web.navigationDelegate = guardian
      }
      result(nil)
    case "stop":
      web.stopLoading()
      result(nil)
    case "focus":
      web.window?.makeFirstResponder(web)
      result(nil)
    case "blur":
      // D10: back to the Flutter view, so the next keys reach Flutter.
      if let responder = web.window?.firstResponder as? NSView,
        responder === web || responder.isDescendant(of: web)
      {
        web.window?.makeFirstResponder(controller.view)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// V2-3 D9: a page's new window (`target=_blank`, `window.open`) never opens
/// in the tool. The plugin's own UI delegate would load it in the same view;
/// this guard answers "no window" and hands the URL to Dart, and passes every
/// other call (JavaScript dialogs, media permissions) on to the plugin's
/// delegate. WKWebView holds its delegate weakly: BrowserNative keeps the
/// guard, the guard keeps the plugin's delegate.
final class NewWindowGuard: NSObject, WKUIDelegate {
  let inner: WKUIDelegate
  private let onNewWindow: (URL?) -> Void

  init(inner: WKUIDelegate, onNewWindow: @escaping (URL?) -> Void) {
    self.inner = inner
    self.onNewWindow = onNewWindow
    super.init()
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    onNewWindow(navigationAction.request.url)
    return nil
  }

  override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || inner.responds(to: aSelector)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    inner.responds(to: aSelector) ? inner : super.forwardingTarget(for: aSelector)
  }
}

/// V2-3 D9: a tool never downloads. The plugin's navigation delegate lets
/// every response show (a zip would replace the page); this guard stops a
/// top-frame response that is a download — an attachment, or a type WebKit
/// cannot show — and hands its URL to Dart, and passes every other call on
/// to the plugin's delegate.
final class DownloadGuard: NSObject, WKNavigationDelegate {
  let inner: WKNavigationDelegate
  private let onDownload: (URL?) -> Void

  init(inner: WKNavigationDelegate, onDownload: @escaping (URL?) -> Void) {
    self.inner = inner
    self.onDownload = onDownload
    super.init()
  }

  static func isDownload(_ response: WKNavigationResponse) -> Bool {
    guard response.isForMainFrame else { return false }
    if !response.canShowMIMEType { return true }
    guard let http = response.response as? HTTPURLResponse,
      let disposition = http.value(forHTTPHeaderField: "Content-Disposition")
    else { return false }
    return disposition.trimmingCharacters(in: .whitespaces).lowercased()
      .hasPrefix("attachment")
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if DownloadGuard.isDownload(navigationResponse) {
      onDownload(navigationResponse.response.url)
      decisionHandler(.cancel)
      return
    }
    let answered: Void? = inner.webView?(
      webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler)
    if answered == nil { decisionHandler(.allow) }
  }

  override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || inner.responds(to: aSelector)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    inner.responds(to: aSelector) ? inner : super.forwardingTarget(for: aSelector)
  }
}
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/tools lib/src/browser lib/src/ui/terminal/key_sequence.dart test/tools test/browser
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools test/browser test/ui/terminal
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_navigation_test.dart` +3, `tool_keys_test.dart` +5, `tool_no_bridge_test.dart` +1, `wk_webview_engine_test.dart` +4, and `test/ui/terminal` (`KeySequence` included), all passed.
- `No issues found!`
- The whole suite: `3703 passed, 9 skipped`.

- [ ] **Step 5: Build the macOS app (no launch)**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug
sed -i '' 's/^COCOAPODS: .*/COCOAPODS: 1.16.2/' macos/Podfile.lock && git diff --stat macos/Podfile.lock
````

Expected: `✓ Built build/macos/Build/Products/Debug/ShellX.app`; no `Podfile.lock` change.

- [ ] **Step 6: Ledger**

Append to `docs/superpowers/ledgers/v2-tools.md` under `## V2-3 (tools, desktop) — execution` one line per finding of the table above, as "macOS engine review: #n area — fixed by … (test …)".

- [ ] **Step 7: Commit**

````bash
git add apps/desktop/lib/src/tools/tool_navigation.dart apps/desktop/lib/src/tools/tool_keys.dart \
  apps/desktop/lib/src/browser/engines/wk_webview_engine.dart apps/desktop/macos/Runner/BrowserNative.swift \
  apps/desktop/lib/src/ui/terminal/key_sequence.dart apps/desktop/test/tools/tool_navigation_test.dart \
  apps/desktop/test/tools/tool_keys_test.dart apps/desktop/test/tools/tool_no_bridge_test.dart \
  apps/desktop/test/browser/wk_webview_engine_test.dart docs/superpowers/ledgers/v2-tools.md
git commit -m "fix(v2-tools): macOS engine review — navigation policy, new windows and downloads guarded, errors by domain with ATS, chords in the keymap's spelling, focus back on a click outside

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 6: The real macOS engine in an isolated build

Spec §9 asks for the real engine, in the real Runner, against a small server inside the test. The test runs only in an isolated build: a throw-away worktree, bundle id `pro.shellx.desktop.itest`, and a temporary `HOME` (ruling R24). So it never touches the user's ShellX data, WebKit store or settings.

It pins, on real WebKit:
- load and title over `http://127.0.0.1` (D19);
- the D9 rules: `file:` refused (by WebKit itself, ruling R5); a custom scheme blocked; `mailto:` and a new window sent outside;
- a refused port, then the server up (D13, Review Focus 3, ruling R25);
- a download stopped while the page stays (ruling R4);
- the camera refused; an `alert()` through ShellX's presenter;
- a page that stays loaded when its view leaves the tree and comes back (Review Focus 1).

Never run it with `flutter test integration_test/…` in your checkout, and never `flutter test -d macos`. Both would build and start the app with the real bundle id and your HOME.

**Files:**
- Create: `apps/desktop/integration_test/tool_engine_test.dart`

**Interfaces:**
- Consumes: Task 5's `WkWebViewEngine({native, policy, dialogs})`, `BrowserNativeMac()`, `toolNavigation`, and Task 3's events.
- Produces: nothing for later tasks (a test).

- [ ] **Step 1: Write the test**

`apps/desktop/integration_test/tool_engine_test.dart`:

````dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';
import 'package:shellx_desktop/src/tools/tool_navigation.dart';

/// V2-3 §9: the real macOS engine in the real Runner, against a small
/// server: load and title, http to 127.0.0.1 (D19), the D9 navigation
/// rules, a refused port then the server up (D13), a stopped download, a
/// refused camera, a JavaScript alert through ShellX, and a page that
/// stays loaded when its view leaves the tree and comes back (Review
/// Focus 1). Run only in an isolated build (plan Task 6 recipe): never
/// with the app's real bundle id or HOME.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String base;
  final pages = <String, String>{
    '/': '<title>Tool title</title><p>tool</p>',
    '/blocked': "<script>location.href = 'file:///etc/hosts'</script>",
    '/custom': "<script>location.href = 'shellx-test://x'</script>",
    '/mail': "<script>location.href = 'mailto:x@example.com'</script>",
    '/popup': "<script>window.open('/other', '_blank')</script>",
    '/camera':
        '<script>(navigator.mediaDevices ? '
        'navigator.mediaDevices.getUserMedia({video: true}) : '
        "Promise.reject()).then(() => location.href = '/granted', "
        "() => location.href = '/denied')</script>",
    '/alert': "<script>alert('hello'); location.href = '/after-alert'</script>",
  };

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) {
      final res = req.response;
      if (req.uri.path == '/file.zip') {
        res.headers.contentType = ContentType('application', 'zip');
        res.headers.set('content-disposition', 'attachment; filename=a.zip');
        res.add([1, 2, 3]);
      } else {
        res.headers.contentType = ContentType.html;
        res.write(
          '<!doctype html><meta charset="utf-8">'
          '${pages[req.uri.path] ?? '<title>${req.uri.path}</title>'}',
        );
      }
      unawaited(res.close());
    });
  });

  tearDownAll(() => server.close(force: true));

  final dialogs = <BrowserJsDialog>[];
  late WkWebViewEngine engine;
  late List<BrowserEngineEvent> events;

  Future<void> show(WidgetTester tester, {bool view = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: view ? engine.buildView() : const SizedBox.shrink(),
            ),
          ),
        ),
      );

  Future<void> until(
    WidgetTester tester,
    bool Function() done,
    String what,
  ) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out: $what');
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  bool urlIs(String path) =>
      events.any((e) => e is UrlChanged && e.url.path == path);

  setUp(() {
    dialogs.clear();
    engine = WkWebViewEngine(
      native: BrowserNativeMac(),
      policy: toolNavigation,
      dialogs: (d) async {
        dialogs.add(d);
        return null;
      },
    );
    events = [];
    engine.events.listen(events.add);
  });

  tearDown(() => engine.dispose());

  testWidgets('loads http://127.0.0.1 (D19) and reads the title', (t) async {
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(
      t,
      () => events.any((e) => e is TitleChanged && e.title == 'Tool title'),
      'title',
    );
    expect(events.whereType<LoadFinished>(), isNotEmpty);
    expect(events.whereType<LoadFailed>(), isEmpty);
  });

  testWidgets('file: is blocked, mailto: and a new window go outside (D9)', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/blocked'));
    await until(t, () => events.any((e) => e is LoadFinished), 'blocked page');
    await t.pump(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      events.whereType<UrlChanged>().where((e) => e.url.scheme == 'file'),
      isEmpty,
    );
    events.clear();
    await engine.load(Uri.parse('$base/custom'));
    await until(
      t,
      () => events.any((e) => e is NavigationBlocked),
      'custom scheme',
    );
    events.clear();
    await engine.load(Uri.parse('$base/mail'));
    await until(
      t,
      () => events.any((e) => e is OpenOutside && e.url.scheme == 'mailto'),
      'mailto',
    );
    events.clear();
    await engine.load(Uri.parse('$base/popup'));
    await until(
      t,
      () => events.any(
        (e) => e is OpenOutside && e.newWindow && e.url.path == '/other',
      ),
      'new window',
    );
    // The new window never loaded in the tool.
    expect(urlIs('/other'), isFalse);
  });

  testWidgets('a refused port, then the server comes up (D13)', (t) async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await show(t);
    final url = Uri.parse('http://127.0.0.1:$port/');
    await engine.load(url);
    await until(
      t,
      () => events.any(
        (e) => e is LoadFailed && e.kind == BrowserLoadErrorKind.refused,
      ),
      'refused',
    );
    final up = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    addTearDown(() => up.close(force: true));
    up.listen((req) {
      req.response.headers.contentType = ContentType.html;
      req.response.write('<title>Up</title>');
      unawaited(req.response.close());
    });
    events.clear();
    await engine.load(url); // what the D13 retry does
    await until(
      t,
      () => events.any((e) => e is TitleChanged && e.title == 'Up'),
      'up',
    );
  });

  testWidgets('a download is stopped, the page stays (D9)', (t) async {
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(t, () => events.any((e) => e is LoadFinished), 'page');
    events.clear();
    await engine.load(Uri.parse('$base/file.zip'));
    await until(t, () => events.any((e) => e is DownloadBlocked), 'download');
    final blocked = events.whereType<DownloadBlocked>().single;
    expect(blocked.url?.path, '/file.zip');
    expect(events.whereType<LoadFinished>(), isEmpty, reason: 'not shown');
  });

  testWidgets('the camera is refused (D9)', (t) async {
    await show(t);
    await engine.load(Uri.parse('$base/camera'));
    await until(t, () => urlIs('/denied'), 'camera refused');
    expect(urlIs('/granted'), isFalse);
  });

  testWidgets('alert() goes through ShellX, then the page goes on (D9)', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/alert'));
    await until(t, () => urlIs('/after-alert'), 'after alert');
    expect(dialogs.single.kind, BrowserJsDialogKind.alert);
    expect(dialogs.single.message, 'hello');
  });

  testWidgets('the page stays loaded when its view leaves and comes back', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(t, () => events.any((e) => e is LoadFinished), 'first load');
    events.clear();
    await show(t, view: false);
    await t.pump(const Duration(milliseconds: 300));
    await show(t);
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 100));
    expect(events.whereType<LoadStarted>(), isEmpty, reason: 'no reload');
    expect(events.whereType<LoadFailed>(), isEmpty);
  });
}
````

- [ ] **Step 2: Analyze**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
````

Expected: `No issues found!`. `flutter test` does not run `integration_test/`.

- [ ] **Step 3: Run it with the isolated recipe**

From the worktree root. The recipe:
1. makes a throw-away worktree of `HEAD` and copies the new test into it;
2. gives that copy its own bundle id;
3. builds the test as the app;
4. starts the binary with a temporary `HOME` (the window stays hidden: `LSUIElement`);
5. waits for the result in the log, stops only that PID, and removes everything.

````bash
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/shellx-itest.XXXXXX")
git worktree add --detach "$SCRATCH/wt" HEAD
cp apps/desktop/integration_test/tool_engine_test.dart "$SCRATCH/wt/apps/desktop/integration_test/"
(
  cd "$SCRATCH/wt"
  PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get > /dev/null
  sed -i '' 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.itest/' \
    apps/desktop/macos/Runner/Configs/AppInfo.xcconfig
  grep -q '^PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.itest$' apps/desktop/macos/Runner/Configs/AppInfo.xcconfig \
    || { echo 'bundle id not changed: stop'; exit 1; }
  cd apps/desktop
  PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug -t integration_test/tool_engine_test.dart || exit 1
  mkdir -p "$SCRATCH/home"
  HOME="$SCRATCH/home" CFFIXED_USER_HOME="$SCRATCH/home" \
    build/macos/Build/Products/Debug/ShellX.app/Contents/MacOS/ShellX > "$SCRATCH/itest.log" 2>&1 &
  PID=$!
  python3 - "$SCRATCH/itest.log" "$PID" <<'EOF'
import os, signal, sys, time
log, pid = sys.argv[1], int(sys.argv[2])
for _ in range(360):  # 3 minutes at most
    text = open(log, errors='replace').read()
    if 'All tests passed!' in text or 'Some tests failed' in text:
        break
    time.sleep(0.5)
os.kill(pid, signal.SIGTERM)  # only the app this recipe started
EOF
  grep -E '^flutter: [0-9]+:[0-9]+ \+' "$SCRATCH/itest.log" | tail -9
)
ls "$SCRATCH/home/Library/WebKit"
git worktree remove --force "$SCRATCH/wt" && rm -rf "$SCRATCH"
````

Expected:
- no `bundle id not changed: stop` line (the recipe stops before building when the bundle id did not change);
- `✓ Built build/macos/Build/Products/Debug/ShellX.app` (about a minute);
- the log ends with `flutter: 00:0N +9: All tests passed!` (7 tests, plus `setUpAll` and `tearDownAll`);
- `ls` shows `pro.shellx.desktop.itest`, so WebKit's data went to the temporary HOME.

After the result, the log also carries Flutter's "integration_test plugin was not detected" warning. It is harmless: the binary ran without `flutter test` around it.

- [ ] **Step 4: Ledger**

Append the recipe's result line and the date under `## V2-3 (tools, desktop) — execution` in `docs/superpowers/ledgers/v2-tools.md`, with "integration test: isolated build, bundle id pro.shellx.desktop.itest, temporary HOME (plan Task 6 recipe)".

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/integration_test/tool_engine_test.dart docs/superpowers/ledgers/v2-tools.md
git commit -m "test(v2-tools): the real WKWebView engine in an isolated build — load, D9 rules, refused then up, download, camera, alert, page kept

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 7: The Windows engine and `tool-embed`

**Engine.** `webview_win_floating` 3.0.3 puts a real WebView2 window over the Flutter window (D7). `WinFloatingEngine` drives it through the plugin's own `WinWebViewController` (ruling R6).
- **Data (D8):** one data folder, `%LOCALAPPDATA%\ShellX\tools`, and one profile, `tools`. Without `LOCALAPPDATA` there is no folder, so no page starts.
- **Permissions (D9):** denied.
- **Navigation:** the same `toolNavigation` policy as macOS. The plugin reports new windows as non-main-frame requests, and they go outside.
- **Errors:** WebView2's `COREWEBVIEW2_WEB_ERROR_STATUS` values map to the D13 kinds. A failed creation (no WebView2 Runtime) makes every call answer `unavailable` (§8: "Cần Microsoft Edge WebView2 Runtime.").
- **Covering:** `coversFlutter` is true, so the dock hides the page behind a stand-in while an overlay is open (Task 13).

**Where tools open.** Nobody has run the Windows engine on a real machine yet, so the file key `tool-embed = auto | on | off` decides (default `auto`).
- `auto` embeds on macOS and opens the system browser on Windows, until spec §11.2 passes. Then one line changes here, with its test.
- The key shows on Settings › Projects (D22) and in `shellx config show`.

**Windows build.** The plugin builds C++ and fetches the WebView2 SDK (NuGet) when CMake runs; only the Windows CI can try that. This plan never pushes: the controller pushes the finished branch to `windows-check/v2-3` after Task 16, and the user reads that result.

**Files:**
- Modify: `apps/desktop/pubspec.yaml`; regenerated by `flutter pub get` (committed): `apps/desktop/windows/flutter/generated_plugin_registrant.cc`, `apps/desktop/windows/flutter/generated_plugins.cmake`
- Create: `apps/desktop/lib/src/browser/engines/win_floating_engine.dart`, `apps/desktop/lib/src/tools/tool_embed.dart`
- Modify: `apps/desktop/lib/src/config/shellx_config.dart`, `apps/desktop/lib/src/config/config_show.dart`, `apps/desktop/lib/src/config/config_template.dart`, `apps/desktop/lib/src/config/settings_schema.dart`, `apps/desktop/lib/src/ui/settings/settings_values.dart`
- Test: `apps/desktop/test/browser/win_floating_engine_test.dart`, `apps/desktop/test/tools/tool_embed_test.dart`, `apps/desktop/test/config/settings_schema_test.dart`

**Interfaces:**
- Consumes: Task 3's `BrowserEngine`, `BrowserDataStore` and events, and Task 5's `NavigationPolicy` (`toolNavigation`). Also `shellxConfigProvider` (`lib/src/config/config_controller.dart`), `SettingDef`/`SettingOwner`/`SettingPage`/`SettingControl`/`SettingChoice`/`SettingSample` (`lib/src/config/settings_schema.dart`), and `AppLocalizations.toolEmbedSetting`/`toolEmbedAuto`/`toolEmbedOn`/`toolEmbedOff` (Task 2).
- Produces:
  - `const String kToolProfileName = 'tools'`;
  - `String? toolDataFolder(Map<String, String> environment)`;
  - `BrowserLoadErrorKind? winErrorKind(int status)`;
  - `final class WinFloatingEngine implements BrowserEngine`, built with `WinFloatingEngine({required NavigationPolicy policy, required String dataFolder})`;
  - `final class WinFloatingDataStore implements BrowserDataStore`, built with `WinFloatingDataStore(String? dataFolder)` (ruling R16).
  - `enum ToolEmbed { auto, on, off }` and `ShellxConfig.toolEmbed`; a bad value is a config problem listing `auto, on, off`.
  - `bool toolsEmbedded(ToolEmbed mode, TargetPlatform platform)`, `final toolPlatformProvider = Provider<TargetPlatform>(…)` (tests make it Windows), `final toolsEmbeddedProvider = Provider<bool>(…)`.
  - `SettingDef` `tool-embed` on `SettingPage.projects`, segmented, file-owned.

- [ ] **Step 1: Add the dependency**

In `apps/desktop/pubspec.yaml`, replace:

````yaml
  # wkwebview 3.26+ needs Flutter 3.44 / Dart 3.12.
  webview_flutter: 4.14.1
  webview_flutter_wkwebview: 3.25.1
  win32: ^5.15.0
  window_manager: ^0.5.2
  # xterm 4.0.0 (same version as apps/mobile, A1 D12), vendored for one
````

with:

````yaml
  # wkwebview 3.26+ needs Flutter 3.44 / Dart 3.12.
  webview_flutter: 4.14.1
  webview_flutter_wkwebview: 3.25.1
  # V2-3 D7: WebView2 on Windows, a native window over the Flutter one.
  webview_win_floating: 3.0.3
  win32: ^5.15.0
  window_manager: ^0.5.2
  # xterm 4.0.0 (same version as apps/mobile, A1 D12), vendored for one
````

From the worktree root:

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
````

Expected:
- `Got dependencies!`, with `webview_win_floating 3.0.3` and its dependency `fullscreen_window 1.2.1`.
- `apps/desktop/windows/flutter/generated_plugin_registrant.cc` and `generated_plugins.cmake` gain `fullscreen_window` and `webview_win_floating`.
- Nothing changes under `apps/desktop/macos`: both plugins are Windows-only.

- [ ] **Step 2: Write the failing tests**

`apps/desktop/test/browser/win_floating_engine_test.dart`:

````dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/win_floating_engine.dart';

void main() {
  test('WebView2 error statuses map to the D13 kinds', () {
    expect(winErrorKind(12), BrowserLoadErrorKind.refused);
    for (final s in [6, 9, 10, 11]) {
      expect(winErrorKind(s), BrowserLoadErrorKind.unreachable, reason: '$s');
    }
    expect(winErrorKind(13), BrowserLoadErrorKind.dns);
    expect(winErrorKind(7), BrowserLoadErrorKind.timeout);
    for (final s in [1, 2, 3, 4, 5]) {
      expect(winErrorKind(s), BrowserLoadErrorKind.certificate, reason: '$s');
    }
    expect(winErrorKind(14), isNull, reason: 'cancelled');
    expect(winErrorKind(16), BrowserLoadErrorKind.other);
    expect(winErrorKind(0), BrowserLoadErrorKind.other);
  });

  test('the data folder is %LOCALAPPDATA%\\ShellX\\tools, never elsewhere '
      '(D8)', () {
    expect(
      toolDataFolder({'LOCALAPPDATA': r'C:\Users\me\AppData\Local'}),
      r'C:\Users\me\AppData\Local\ShellX\tools',
    );
    expect(toolDataFolder({}), isNull);
    expect(toolDataFolder({'LOCALAPPDATA': ''}), isNull);
    expect(kToolProfileName, 'tools');
  });

  test('with no page alive, clearing deletes the folder (D22)', () async {
    final root = await Directory.systemTemp.createTemp('tools');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final folder = Directory('${root.path}/tools');
    await File('${folder.path}/EBWebView/x').create(recursive: true);
    await WinFloatingDataStore(folder.path).clearAll();
    expect(await folder.exists(), isFalse);
    await WinFloatingDataStore(null).clearAll(); // nothing to clear
    await WinFloatingDataStore(folder.path).clearAll(); // already gone
  });
}
````

`apps/desktop/test/tools/tool_embed_test.dart`:

````dart
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/tools/tool_embed.dart';
import 'package:shellx_desktop/src/ui/settings/pages/page_parts.dart'
    show settingById;

({ShellxConfig config, List<ConfigProblem> problems}) build(String? value) {
  final problems = <ConfigProblem>[];
  final config = buildShellxConfig(
    ghostty: const [],
    shellx: [
      if (value != null)
        ConfigEntry(file: '/c', line: 1, key: 'tool-embed', value: value),
    ],
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  test('tool-embed: auto by default; auto, on, off; a bad value is a '
      'problem (D7)', () {
    expect(build(null).config.toolEmbed, ToolEmbed.auto);
    expect(build('on').config.toolEmbed, ToolEmbed.on);
    expect(build('off').config.toolEmbed, ToolEmbed.off);
    expect(build('auto').config.toolEmbed, ToolEmbed.auto);
    final bad = build('maybe');
    expect(bad.config.toolEmbed, ToolEmbed.auto);
    expect(bad.problems.single.code, ConfigProblemCode.badValue);
  });

  test('auto embeds on macOS only; on and off say so everywhere (D7, D20)', () {
    const mac = TargetPlatform.macOS;
    const win = TargetPlatform.windows;
    expect(toolsEmbedded(ToolEmbed.auto, mac), isTrue);
    expect(toolsEmbedded(ToolEmbed.auto, win), isFalse);
    expect(toolsEmbedded(ToolEmbed.on, win), isTrue);
    expect(toolsEmbedded(ToolEmbed.on, mac), isTrue);
    expect(toolsEmbedded(ToolEmbed.off, mac), isFalse);
    expect(toolsEmbedded(ToolEmbed.off, win), isFalse);
  });

  test('the row is on Settings › Projects (D22)', () {
    final row = settingById('tool-embed');
    expect(row.page, SettingPage.projects);
    expect(row.choices!.map((c) => c.wire), ['auto', 'on', 'off']);
  });
}
````

In `apps/desktop/test/config/settings_schema_test.dart`, replace:

````dart
      'new-tab-kind',
      'ai-agent-claude',
      'ai-checkpoint-days',
    };
    final have = {
      for (final d in kSettings)
````

with:

````dart
      'new-tab-kind',
      'ai-agent-claude',
      'ai-checkpoint-days',
      // V2-3.
      'tool-embed',
    };
    final have = {
      for (final d in kSettings)
````

- [ ] **Step 3: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/win_floating_engine_test.dart test/tools/tool_embed_test.dart test/config/settings_schema_test.dart
````

Expected:
- compilation fails: `Error when reading 'lib/src/browser/engines/win_floating_engine.dart'`, and `Undefined name 'ToolEmbed'`;
- `settings_schema_test.dart` fails on the missing `tool-embed` key.

- [ ] **Step 4: Implement**

`apps/desktop/lib/src/browser/engines/win_floating_engine.dart`:

````dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show JavaScriptMode, NavigationDecision;
import 'package:webview_win_floating/webview_win_floating.dart';

import '../browser_engine.dart';

/// D8: the WebView2 profile every tool shares.
const String kToolProfileName = 'tools';

/// D8: `%LOCALAPPDATA%\ShellX\tools`; null without `LOCALAPPDATA` (then no
/// page can start: never a folder next to the program).
String? toolDataFolder(Map<String, String> environment) {
  final base = environment['LOCALAPPDATA'];
  if (base == null || base.isEmpty) return null;
  return '$base\\ShellX\\tools';
}

/// D13: WebView2's `COREWEBVIEW2_WEB_ERROR_STATUS` → the panel's kind; null
/// for a navigation that was cancelled (14).
BrowserLoadErrorKind? winErrorKind(int status) => switch (status) {
  14 => null,
  12 => BrowserLoadErrorKind.refused,
  6 || 9 || 10 || 11 => BrowserLoadErrorKind.unreachable,
  13 => BrowserLoadErrorKind.dns,
  7 => BrowserLoadErrorKind.timeout,
  >= 1 && <= 5 => BrowserLoadErrorKind.certificate,
  _ => BrowserLoadErrorKind.other,
};

/// V2-3 D7: WebView2 through `webview_win_floating` 3.0.3 — a real WebView2
/// window placed over the Flutter window. Flutter cannot draw over it
/// ([coversFlutter]): the dock hides it while an overlay is open. The page
/// keeps every key while it has the keyboard (no forwarding). Downloads use
/// WebView2's own download bar (the plugin has no hook; ruling in the plan),
/// JavaScript dialogs are WebView2's own.
final class WinFloatingEngine implements BrowserEngine {
  WinFloatingEngine({
    required NavigationPolicy policy,
    required String dataFolder,
  }) : _policy = policy {
    _controller = WinWebViewController(
      params: WindowsWebViewControllerCreationParams(
        userDataFolder: dataFolder,
        profileName: kToolProfileName,
      ),
      // D9: no camera, microphone, location or notifications.
      onPermissionRequest: (request) => unawaited(request.deny()),
    );
    _live.add(this);
    _ready = _setup();
  }

  /// Engines alive now (the data store clears through one of them).
  static final Set<WinFloatingEngine> _live = {};

  final NavigationPolicy _policy;
  late final WinWebViewController _controller;
  late final Future<void> _ready;
  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast();

  void _emit(BrowserEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _setup() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setNavigationDelegate(
      WinNavigationDelegate(
        onNavigationRequest: (request) {
          final url = Uri.tryParse(request.url);
          // The plugin asks only for the top frame and for new windows
          // (WebView2 NewWindowRequested), which it reports as "not the
          // main frame".
          final newWindow = !request.isMainFrame;
          switch (_policy(url, mainFrame: true, newWindow: newWindow)) {
            case NavigationVerdict.allow when !newWindow:
              return NavigationDecision.navigate;
            case NavigationVerdict.outside when url != null:
              _emit(OpenOutside(url, newWindow: newWindow));
            case _:
              _emit(const NavigationBlocked());
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => _emit(const LoadStarted()),
        onPageFinished: (_) {
          _emit(const LoadFinished());
          unawaited(_history());
        },
        // Required with onPageFinished: the plugin calls it unchecked.
        onHttpError: (_) {},
        onSslAuthError: (error) {
          unawaited(error.cancel());
          _emit(const LoadFailed(BrowserLoadErrorKind.certificate));
        },
        onWebResourceError: (error) {
          final kind = winErrorKind(error.errorCode);
          if (kind != null) _emit(LoadFailed(kind));
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (uri != null) _emit(UrlChanged(uri));
        },
        onPageTitleChanged: (title) => _emit(TitleChanged(title)),
        onHistoryChanged: () => unawaited(_history()),
      ),
    );
  }

  Future<void> _history() async {
    try {
      _emit(
        HistoryChanged(
          canGoBack: await _controller.canGoBack(),
          canGoForward: await _controller.canGoForward(),
        ),
      );
    } on Object {
      // The view went away meanwhile.
    }
  }

  /// D8 §8: no WebView2 Runtime (or no data folder) fails the plugin's
  /// creation; every call then says "unavailable" instead of throwing.
  Future<void> _guard(Future<void> Function() call) async {
    try {
      await _ready;
      await call();
    } on Object catch (error) {
      debugPrint('tool page: engine unavailable (${error.runtimeType})');
      _emit(const LoadFailed(BrowserLoadErrorKind.unavailable));
    }
  }

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  bool get coversFlutter => true;

  @override
  Future<void> load(Uri url) => _guard(() => _controller.loadRequest(url));

  @override
  Future<void> goBack() => _guard(_controller.goBack);

  @override
  Future<void> goForward() => _guard(_controller.goForward);

  @override
  Future<void> reload() => _guard(_controller.reload);

  @override
  Future<void> stop() => _guard(_controller.cancelNavigate);

  @override
  Future<void> setForwardedChords(List<String> chords) async {}

  @override
  Future<void> focusContent() => _guard(_controller.requestFocus);

  /// WebView2 keeps the keyboard until a click lands outside it (D7).
  @override
  Future<void> releaseFocus() async {}

  @override
  Future<void> setVisible(bool visible) =>
      _guard(() => _controller.setVisibility(visible));

  @override
  Widget buildView() => WinWebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    _live.remove(this);
    await _events.close();
    try {
      await _controller.dispose();
    } on Object {
      // Never created (no runtime): nothing to free.
    }
  }
}

/// D8, D22 on Windows: through a live page when there is one (WebView2
/// clears the profile, `ClearBrowsingDataAll`); with none, no WebView2
/// process holds the folder, so it is deleted.
final class WinFloatingDataStore implements BrowserDataStore {
  WinFloatingDataStore(this.dataFolder);
  final String? dataFolder;

  @override
  Future<void> clearAll() async {
    final live = WinFloatingEngine._live.firstOrNull;
    if (live != null) {
      await live._ready;
      await live._controller.clearCache();
      return;
    }
    final folder = dataFolder;
    if (folder == null) return;
    final dir = Directory(folder);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
````

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

````dart
/// V2-1 D4 `new-tab-kind`: what ⌘T / Ctrl+Shift+T, `+`, the empty window's
/// button and the startup tab open. The names are the wire values.
enum NewTabKind { terminal, ai }

/// `link-editor`: where ⌘-click (Ctrl-click on Windows) opens a file path
/// found in a local pane. `auto` = the first installed of Cursor, VS Code,
````

with:

````dart
/// V2-1 D4 `new-tab-kind`: what ⌘T / Ctrl+Shift+T, `+`, the empty window's
/// button and the startup tab open. The names are the wire values.
enum NewTabKind { terminal, ai }

/// V2-3 D7 `tool-embed`: where a tool opens. `auto` shows it in ShellX on
/// macOS and in the system browser on Windows (until the §11.2 check); `on`
/// always in ShellX; `off` always in the browser. The names are the wire
/// values.
enum ToolEmbed { auto, on, off }

/// `link-editor`: where ⌘-click (Ctrl-click on Windows) opens a file path
/// found in a local pane. `auto` = the first installed of Cursor, VS Code,
````

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

````dart
    this.confirmClose = ConfirmClose.whenRunning,
    this.agentResume = AgentResume.ask,
    this.newTabKind = NewTabKind.terminal,
    this.aiAgentClaude = true,
    this.aiCheckpointDays = kAiCheckpointDaysDefault,
    this.linkEditor = LinkEditor.auto,
````

with:

````dart
    this.confirmClose = ConfirmClose.whenRunning,
    this.agentResume = AgentResume.ask,
    this.newTabKind = NewTabKind.terminal,
    this.toolEmbed = ToolEmbed.auto,
    this.aiAgentClaude = true,
    this.aiCheckpointDays = kAiCheckpointDaysDefault,
    this.linkEditor = LinkEditor.auto,
````

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

````dart

  /// `new-tab-kind` (ShellX file only, V2-1 D4): `terminal` by default.
  final NewTabKind newTabKind;

  /// `ai-agent-claude = on | off` (ShellX file only, V2-1 D21): off hides
  /// Claude from the AI interface everywhere.
````

with:

````dart

  /// `new-tab-kind` (ShellX file only, V2-1 D4): `terminal` by default.
  final NewTabKind newTabKind;

  /// `tool-embed` (ShellX file only, V2-3 D7): `auto` by default.
  final ToolEmbed toolEmbed;

  /// `ai-agent-claude = on | off` (ShellX file only, V2-1 D21): off hides
  /// Claude from the AI interface everywhere.
````

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

````dart
  var confirmClose = ConfirmClose.whenRunning;
  var agentResume = AgentResume.ask;
  var newTabKind = NewTabKind.terminal;
  var aiAgentClaude = true;
  var aiCheckpointDays = kAiCheckpointDaysDefault;
  var linkEditor = LinkEditor.auto;
````

with:

````dart
  var confirmClose = ConfirmClose.whenRunning;
  var agentResume = AgentResume.ask;
  var newTabKind = NewTabKind.terminal;
  var toolEmbed = ToolEmbed.auto;
  var aiAgentClaude = true;
  var aiCheckpointDays = kAiCheckpointDaysDefault;
  var linkEditor = LinkEditor.auto;
````

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

````dart
        };
        if (kind == null) return _badValue(e, g, 'terminal, ai');
        newTabKind = kind;
      case 'ai-agent-claude':
        final on = switch (v) {
          '' || 'on' || 'true' => true,
````

with:

````dart
        };
        if (kind == null) return _badValue(e, g, 'terminal, ai');
        newTabKind = kind;
      case 'tool-embed':
        final mode = switch (v) {
          '' || 'auto' => ToolEmbed.auto,
          'on' => ToolEmbed.on,
          'off' => ToolEmbed.off,
          _ => null,
        };
        if (mode == null) return _badValue(e, g, 'auto, on, off');
        toolEmbed = mode;
      case 'ai-agent-claude':
        final on = switch (v) {
          '' || 'on' || 'true' => true,
````

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

````dart
    confirmClose: confirmClose,
    agentResume: agentResume,
    newTabKind: newTabKind,
    aiAgentClaude: aiAgentClaude,
    aiCheckpointDays: aiCheckpointDays,
    linkEditor: linkEditor,
````

with:

````dart
    confirmClose: confirmClose,
    agentResume: agentResume,
    newTabKind: newTabKind,
    toolEmbed: toolEmbed,
    aiAgentClaude: aiAgentClaude,
    aiCheckpointDays: aiCheckpointDays,
    linkEditor: linkEditor,
````

In `apps/desktop/lib/src/config/config_show.dart`, replace:

````dart
    v('new-tab-kind', c.newTabKind.name),
    v('ai-agent-claude', c.aiAgentClaude ? 'on' : 'off'),
    v('ai-checkpoint-days', '${c.aiCheckpointDays}'),
    v('link-editor', c.linkEditor.name),
    v('pr-status', '${c.prStatus}'),
    v('agent-event-command', c.agentEventCommand),
````

with:

````dart
    v('new-tab-kind', c.newTabKind.name),
    v('ai-agent-claude', c.aiAgentClaude ? 'on' : 'off'),
    v('ai-checkpoint-days', '${c.aiCheckpointDays}'),
    v('tool-embed', c.toolEmbed.name),
    v('link-editor', c.linkEditor.name),
    v('pr-status', '${c.prStatus}'),
    v('agent-event-command', c.agentEventCommand),
````

In `apps/desktop/lib/src/config/config_template.dart`, replace:

````dart
    '# ai-agent-claude = on  (off: hide Claude from the AI interface)',
    '# ai-checkpoint-days = 14  (days the AI tab keeps restore points, 1 to 90)',
    '',
    '# --- Keys (Ghostty keybind syntax; later lines win) ---',
    '# keybind = $split=new_split:down',
    '# keybind = ctrl+a>c=new_tab',
````

with:

````dart
    '# ai-agent-claude = on  (off: hide Claude from the AI interface)',
    '# ai-checkpoint-days = 14  (days the AI tab keeps restore points, 1 to 90)',
    '',
    '# --- Tools ---',
    '# tool-embed = auto  (on: show tools in ShellX on Windows too; off: always open them in the browser)',
    '',
    '# --- Keys (Ghostty keybind syntax; later lines win) ---',
    '# keybind = $split=new_split:down',
    '# keybind = ctrl+a>c=new_tab',
````

In `apps/desktop/lib/src/config/settings_schema.dart`, replace:

````dart
      SettingSample('on', 'on'),
    ],
  ),
  // V2-1 D12: how long restore points are kept.
  SettingDef(
    id: 'ai-checkpoint-days',
````

with:

````dart
      SettingSample('on', 'on'),
    ],
  ),
  // V2-3 D7, D22: where tools open (Settings › Projects, last).
  SettingDef(
    id: 'tool-embed',
    owner: SettingOwner.file,
    page: SettingPage.projects,
    control: SettingControl.segmented,
    fileKey: 'tool-embed',
    label: (l) => l.toolEmbedSetting,
    keywords: const ['tool', 'web', 'browser', 'localhost', 'trình duyệt'],
    choices: [
      SettingChoice('auto', (l) => l.toolEmbedAuto),
      SettingChoice('on', (l) => l.toolEmbedOn),
      SettingChoice('off', (l) => l.toolEmbedOff),
    ],
    sampleValues: const [
      SettingSample('off', 'off'),
      SettingSample('on', 'on'),
      SettingSample('auto', 'auto'),
    ],
  ),
  // V2-1 D12: how long restore points are kept.
  SettingDef(
    id: 'ai-checkpoint-days',
````

In `apps/desktop/lib/src/ui/settings/settings_values.dart`, replace:

````dart
  'new-tab-kind' => c.newTabKind.name,
  'ai-agent-claude' => c.aiAgentClaude ? 'on' : 'off',
  'ai-checkpoint-days' => '${c.aiCheckpointDays}',
  'link-editor' => c.linkEditor.name,
  'pr-status' => '${c.prStatus}',
  'global-hotkey' =>
````

with:

````dart
  'new-tab-kind' => c.newTabKind.name,
  'ai-agent-claude' => c.aiAgentClaude ? 'on' : 'off',
  'ai-checkpoint-days' => '${c.aiCheckpointDays}',
  'tool-embed' => c.toolEmbed.name,
  'link-editor' => c.linkEditor.name,
  'pr-status' => '${c.prStatus}',
  'global-hotkey' =>
````

`apps/desktop/lib/src/tools/tool_embed.dart`:

````dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/config_controller.dart';
import '../config/shellx_config.dart';

/// V2-3 D7, D20: whether tools show inside ShellX on [platform]. `auto` is
/// macOS only until the §11.2 check passes on a real Windows machine (then
/// this one line changes, with its test).
bool toolsEmbedded(ToolEmbed mode, TargetPlatform platform) => switch (mode) {
  ToolEmbed.on => true,
  ToolEmbed.off => false,
  ToolEmbed.auto => platform == TargetPlatform.macOS,
};

/// The platform tools run on; tests make it Windows.
final toolPlatformProvider = Provider<TargetPlatform>(
  (ref) => defaultTargetPlatform,
);

/// D20: false → every way to open a tool opens the system browser.
final toolsEmbeddedProvider = Provider<bool>(
  (ref) => toolsEmbedded(
    ref.watch(shellxConfigProvider.select((s) => s.config.toolEmbed)),
    ref.watch(toolPlatformProvider),
  ),
);
````

- [ ] **Step 5: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/browser lib/src/tools/tool_embed.dart lib/src/config/shellx_config.dart lib/src/config/config_show.dart lib/src/config/config_template.dart lib/src/config/settings_schema.dart lib/src/ui/settings/settings_values.dart test/browser test/tools/tool_embed_test.dart test/config/settings_schema_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser test/tools/tool_embed_test.dart test/config test/ui/settings
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `win_floating_engine_test.dart` +3, `tool_embed_test.dart` +3, `settings_schema_test.dart` +13, and the rest of `test/config` and `test/ui/settings` (the config template and `config show` included), all passed.
- `No issues found!`
- The whole suite: `3712 passed, 9 skipped`.

- [ ] **Step 6: Commit**

````bash
git add apps/desktop/pubspec.yaml apps/desktop/windows/flutter/generated_plugin_registrant.cc \
  apps/desktop/windows/flutter/generated_plugins.cmake apps/desktop/lib/src/browser/engines/win_floating_engine.dart \
  apps/desktop/lib/src/tools/tool_embed.dart apps/desktop/lib/src/config/shellx_config.dart \
  apps/desktop/lib/src/config/config_show.dart apps/desktop/lib/src/config/config_template.dart \
  apps/desktop/lib/src/config/settings_schema.dart apps/desktop/lib/src/ui/settings/settings_values.dart \
  apps/desktop/test/browser/win_floating_engine_test.dart apps/desktop/test/tools/tool_embed_test.dart \
  apps/desktop/test/config/settings_schema_test.dart
git commit -m "feat(v2-tools): WebView2 engine for Windows behind tool-embed (auto: browser on Windows until checked)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 8: The dock state and its controller

**State.** Each workspace has its own dock (D3): open or not, zoomed or not, its width as a fraction of the content area, the tool on show, and the chips (D5).
- `ToolDockState` is pure Dart. It is also what `layout.json` stores (Task 9), so it repairs anything damaged instead of throwing.
- `toolDockLayout` places panes │ handle │ dock with D3's numbers: 45 % by default, a dock of at least 320 px, panes of at least 360 px. Too narrow (§8): no dock unless zoomed. A zoom covers the content area and leaves the panes their width, so no terminal is resized by it.

**Controller.** `ToolDockController` holds every workspace's dock and the "loose" workspace (D4, ruling R14). It follows three things:
- the registry: a deleted tool leaves every dock (D23);
- the sidebar: a deleted workspace takes its dock, and its tools leave the registry (D2, §8);
- the selected tab: a selection ends "loose", and each workspace's last selected tab is remembered (D4).

**Files:**
- Create: `apps/desktop/lib/src/tools/tool_dock_state.dart`, `apps/desktop/lib/src/tools/tool_dock.dart`
- Test: `apps/desktop/test/tools/tool_dock_state_test.dart`, `apps/desktop/test/tools/tool_dock_test.dart`

**Interfaces:**
- Consumes:
  - `toolRegistryProvider`, `ToolEntry`, `kMaxToolsPerWorkspace`, `kToolIdPattern` (Task 1);
  - `sidebarWorkspacesProvider`/`SidebarState` (`workspaces`, `workspaceOf(int tabId)`, `tabsOf(String ws)`, `currentId`) and `terminalTabsProvider`/`TerminalTabsState` (`selectedId`), both existing.
- Produces, `lib/src/tools/tool_dock_state.dart`:
  - `const double kToolDockDefaultWidth = 0.45`, `kToolDockMinWidth = 320`, `kToolPaneMinWidth = 360`, `kToolDockHandle = 6`;
  - `final class ToolDockState({bool open = false, bool zoom = false, double width = kToolDockDefaultWidth, String? active, List<String> tools = const []})`:
    - `bool get isDefault`;
    - `ToolDockState copyWith({bool? open, bool? zoom, double? width, String? active, List<String>? tools})`;
    - `activated(String toolId)`, `opened(String toolId)`, `without(String toolId)`;
    - `Map<String, Object?> toJson()`, `static ToolDockState? tryParse(Object? raw)`;
    - `==`, and `toString()` → `ToolDockState(…)`.
  - `final class ToolDockLayout({required double paneWidth, required double? dockLeft, required double dockWidth})` with `bool get showsDock`, `bool get showsHandle`;
  - `ToolDockLayout toolDockLayout({required double width, required ToolDockState? dock, required bool embedded})` and `double toolDockFraction({required double width, required double dockWidth})`.
- Produces, `lib/src/tools/tool_dock.dart`:
  - `final class ToolDocks({Map<String, ToolDockState> byWorkspace = const {}, String? loose})` with `ToolDockState of(String ws)`;
  - `final toolDockProvider = NotifierProvider<ToolDockController, ToolDocks>(ToolDockController.new);`
  - `class ToolDockController extends Notifier<ToolDocks>`:
    - opening and closing: `void open(String ws, String toolId)`, `void activate(String ws, String toolId)`, `void closeTool(String ws, String toolId)`, `void close(String ws)`, `bool reopen(String ws)`;
    - size: `void setZoom(String ws, bool zoom)`, `void setWidth(String ws, double fraction)`;
    - loose: `void showLoose(String ws)`, `void clearLoose()`;
    - memory: `int? lastTabOf(String ws)`, `String? lastViewedOf(String ws)`;
    - restore: `Map<String, ToolDockState> get saved` (non-default docks only), `void restore(Map<String, ToolDockState> saved)`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/tools/tool_dock_state_test.dart`:

````dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/tools/tool_dock_state.dart';

const a = 'aaaaaaaaaa', b = 'bbbbbbbbbb', c = 'cccccccccc';

void main() {
  group('ToolDockState', () {
    test('opened adds a chip once and shows it (D4, D5)', () {
      final s = const ToolDockState().opened(a).opened(b).opened(a);
      expect(s.open, isTrue);
      expect(s.tools, [a, b]);
      expect(s.active, a);
    });

    test('without: the chip after shows, else the one before; the last '
        'chip closes the dock (D5, D10)', () {
      final s = const ToolDockState().opened(a).opened(b).opened(c);
      expect(s.activated(b).without(b).active, c);
      expect(s.without(c).active, b);
      expect(s.without(a).active, c, reason: 'not the one on show');
      final last = const ToolDockState(width: 0.6, zoom: true).opened(a);
      final closed = last.without(a);
      expect(
        [closed.open, closed.zoom, closed.tools, closed.width],
        [false, false, <String>[], 0.6],
      );
      expect(s.without('zzzzzzzzzz'), s);
    });

    test('toJson / tryParse round-trip (D14)', () {
      final s = const ToolDockState(width: 0.5).opened(a).opened(b);
      expect(s.toJson(), {
        'open': true,
        'zoom': false,
        'width': 0.5,
        'active': b,
        'tools': [a, b],
      });
      expect(ToolDockState.tryParse(s.toJson()), s);
    });

    test('tryParse repairs, never throws (D14)', () {
      expect(ToolDockState.tryParse(null), isNull);
      expect(ToolDockState.tryParse('x'), isNull);
      final repaired = ToolDockState.tryParse({
        'open': 'yes',
        'zoom': true,
        'width': 3,
        'active': 'nope',
        'tools': [a, a, 'BAD', 7, b],
      })!;
      expect(repaired.open, isFalse);
      expect(repaired.zoom, isTrue);
      expect(repaired.width, kToolDockDefaultWidth);
      expect(repaired.tools, [a, b]);
      expect(repaired.active, a);
      final empty = ToolDockState.tryParse({'open': true, 'zoom': true})!;
      expect([empty.open, empty.zoom, empty.active], [false, false, null]);
    });

    test('toString shows no ids', () {
      expect(
        const ToolDockState().opened(a).toString(),
        'ToolDockState(open: true, zoom: false, tools: 1)',
      );
    });
  });

  group('toolDockLayout (D3, §8)', () {
    final dock = const ToolDockState().opened(a);

    test('closed, not embedded or empty: the panes take everything', () {
      for (final d in [
        null,
        const ToolDockState(),
        dock.copyWith(open: false),
      ]) {
        final l = toolDockLayout(width: 1000, dock: d, embedded: true);
        expect([l.paneWidth, l.showsDock], [1000, false]);
      }
      final off = toolDockLayout(width: 1000, dock: dock, embedded: false);
      expect(off.showsDock, isFalse);
    });

    test('45 % by default, beside the panes and the handle', () {
      final l = toolDockLayout(width: 1000, dock: dock, embedded: true);
      expect(l.dockWidth, 450);
      expect(l.paneWidth, 1000 - kToolDockHandle - 450);
      expect(l.dockLeft, l.paneWidth + kToolDockHandle);
      expect(l.showsHandle, isTrue);
    });

    test('at least 320 px for the dock and 360 px for the panes', () {
      final narrow = toolDockLayout(
        width: 700,
        dock: dock.copyWith(width: 0.1),
        embedded: true,
      );
      expect(narrow.dockWidth, kToolDockMinWidth);
      final wide = toolDockLayout(
        width: 700,
        dock: dock.copyWith(width: 0.9),
        embedded: true,
      );
      expect(wide.paneWidth, kToolPaneMinWidth);
    });

    test('too narrow: no dock unless zoomed; zoomed covers everything and '
        'leaves the panes their width', () {
      final small = toolDockLayout(width: 600, dock: dock, embedded: true);
      expect([small.showsDock, small.paneWidth], [false, 600]);
      final zoomedSmall = toolDockLayout(
        width: 600,
        dock: dock.copyWith(zoom: true),
        embedded: true,
      );
      expect([zoomedSmall.dockLeft, zoomedSmall.dockWidth], [0, 600]);
      final zoomed = toolDockLayout(
        width: 1000,
        dock: dock.copyWith(zoom: true),
        embedded: true,
      );
      expect(
        [zoomed.dockLeft, zoomed.dockWidth, zoomed.showsHandle],
        [0, 1000, false],
      );
      expect(
        zoomed.paneWidth,
        1000 - kToolDockHandle - 450,
        reason: 'no resize',
      );
    });

    test('a drag keeps a fraction within the pixel minimums', () {
      expect(toolDockFraction(width: 1000, dockWidth: 500), 0.5);
      expect(toolDockFraction(width: 1000, dockWidth: 100), 0.32);
      expect(
        toolDockFraction(width: 1000, dockWidth: 990),
        (1000 - kToolDockHandle - kToolPaneMinWidth) / 1000,
      );
      expect(
        toolDockFraction(width: 500, dockWidth: 300),
        kToolDockDefaultWidth,
      );
    });
  });
}
````

`apps/desktop/test/tools/tool_dock_test.dart`:

````dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_dock_state.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  var next = 0;

  setUp(() {
    next = 0;
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        toolIdSourceProvider.overrideWithValue(
          () => 'tool${(next++).toString().padLeft(6, '0')}',
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    c.read(toolDockProvider);
  });

  ToolDockController dock() => c.read(toolDockProvider.notifier);
  ToolDocks docks() => c.read(toolDockProvider);
  ToolEntry add(String ws, int port) => c
      .read(toolRegistryProvider.notifier)
      .add(ws: ws, name: '', url: 'localhost:$port')!;

  test('open, activate, close a chip, close and reopen the dock (D4, D5)', () {
    final a = add(kDefaultWorkspaceId, 1), b = add(kDefaultWorkspaceId, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(kDefaultWorkspaceId, b.id);
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id, b.id]);
    dock().activate(kDefaultWorkspaceId, a.id);
    expect(docks().of(kDefaultWorkspaceId).active, a.id);
    dock().close(kDefaultWorkspaceId);
    expect(docks().of(kDefaultWorkspaceId).open, isFalse);
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id, b.id], reason: 'D5');
    expect(dock().reopen(kDefaultWorkspaceId), isTrue);
    expect(docks().of(kDefaultWorkspaceId).active, a.id);
    dock().closeTool(kDefaultWorkspaceId, a.id);
    dock().closeTool(kDefaultWorkspaceId, b.id);
    expect(docks().of(kDefaultWorkspaceId).open, isFalse);
    expect(dock().reopen(kDefaultWorkspaceId), isFalse);
  });

  test('zoom and width are the workspace\'s own (D3)', () {
    final a = add(kDefaultWorkspaceId, 1);
    final ws2 = c.read(sidebarWorkspacesProvider.notifier).createFor(name: 'B');
    final b = add(ws2, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(ws2, b.id);
    dock().setZoom(ws2, true);
    dock().setWidth(kDefaultWorkspaceId, 0.6);
    expect(docks().of(ws2).zoom, isTrue);
    expect(docks().of(kDefaultWorkspaceId).zoom, isFalse);
    expect(docks().of(kDefaultWorkspaceId).width, 0.6);
    expect(docks().of(ws2).width, kToolDockDefaultWidth);
  });

  test('a deleted tool leaves every dock (D23)', () {
    final a = add(kDefaultWorkspaceId, 1), b = add(kDefaultWorkspaceId, 2);
    dock().open(kDefaultWorkspaceId, a.id);
    dock().open(kDefaultWorkspaceId, b.id);
    c.read(toolRegistryProvider.notifier).remove(b.id);
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id]);
    expect(docks().of(kDefaultWorkspaceId).active, a.id);
    c.read(toolRegistryProvider.notifier).remove(a.id);
    expect(docks().of(kDefaultWorkspaceId).open, isFalse);
  });

  test('a deleted workspace takes its dock and its tools (D2, §8)', () {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final ws2 = side.createFor(name: 'B');
    final b = add(ws2, 2);
    final a = add(kDefaultWorkspaceId, 1);
    dock().open(ws2, b.id);
    side.delete(ws2);
    expect(docks().byWorkspace.containsKey(ws2), isFalse);
    expect(c.read(toolRegistryProvider), [a]);
  });

  test('loose: shown until a tab is selected (D4)', () async {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    await c.read(terminalTabsProvider.notifier).openTab();
    final ws2 = side.createFor(name: 'B');
    dock().showLoose(ws2);
    expect(docks().loose, ws2);
    await side.openTabIn(ws2);
    expect(docks().loose, isNull);
  });

  test('the last tab of each workspace is remembered (D4)', () async {
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab();
    await tabs.openTab();
    final first = c.read(terminalTabsProvider).tabs.first.id;
    tabs.select(first);
    expect(dock().lastTabOf(kDefaultWorkspaceId), first);
  });

  test('restore keeps known workspaces and tools; saved skips defaults '
      '(D14)', () {
    final a = add(kDefaultWorkspaceId, 1);
    dock().restore({
      kDefaultWorkspaceId: ToolDockState(
        open: true,
        active: a.id,
        tools: [a.id, 'zzzzzzzzzz'],
      ),
      'gone': ToolDockState(open: true, tools: [a.id]),
    });
    expect(docks().of(kDefaultWorkspaceId).tools, [a.id]);
    expect(docks().byWorkspace.containsKey('gone'), isFalse);
    expect(dock().saved.keys, [kDefaultWorkspaceId]);
    dock().closeTool(kDefaultWorkspaceId, a.id);
    expect(dock().saved, isEmpty);
  });
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_dock_state_test.dart test/tools/tool_dock_test.dart
````

Expected: compilation fails, `Error when reading 'lib/src/tools/tool_dock_state.dart'`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/tools/tool_dock_state.dart`:

````dart
/// V2-3 D3, D5, D14: one workspace's tool dock — open or not, zoomed or
/// not, its width, the tool on show and the chips — and where it goes in
/// the window. Pure Dart: the restore file (`toolDock`) holds it as is.
library;

import 'dart:math' as math;

import 'tool_entry.dart' show kMaxToolsPerWorkspace, kToolIdPattern;

/// D3: 45 % of the content area by default.
const double kToolDockDefaultWidth = 0.45;

/// D3: the dock is at least 320 px; the panes keep at least 360 px.
const double kToolDockMinWidth = 320;
const double kToolPaneMinWidth = 360;

/// The strip between the panes and the dock that drags its width.
const double kToolDockHandle = 6;

/// A stored width outside this range is repaired.
const double _minFraction = 0.1, _maxFraction = 0.9;

final class ToolDockState {
  const ToolDockState({
    this.open = false,
    this.zoom = false,
    this.width = kToolDockDefaultWidth,
    this.active,
    this.tools = const [],
  });

  final bool open;

  /// D3 "Expand": the dock covers the whole content area.
  final bool zoom;

  /// A fraction of the content area.
  final double width;

  /// The tool on show (one of [tools]).
  final String? active;

  /// D5: the open tools, one chip each, in the order they were opened.
  final List<String> tools;

  /// Nothing worth keeping in `layout.json`.
  bool get isDefault =>
      !open && !zoom && width == kToolDockDefaultWidth && tools.isEmpty;

  ToolDockState copyWith({
    bool? open,
    bool? zoom,
    double? width,
    String? active,
    List<String>? tools,
  }) => ToolDockState(
    open: open ?? this.open,
    zoom: zoom ?? this.zoom,
    width: width ?? this.width,
    active: active ?? this.active,
    tools: tools ?? this.tools,
  );

  /// D5: [toolId] (already a chip) on show.
  ToolDockState activated(String toolId) =>
      tools.contains(toolId) ? copyWith(active: toolId) : this;

  /// D4: open, with [toolId] on show (a chip of its own at the end).
  ToolDockState opened(String toolId) => ToolDockState(
    open: true,
    zoom: zoom,
    width: width,
    active: toolId,
    tools: tools.contains(toolId) ? tools : [...tools, toolId],
  );

  /// D5, D10: [toolId]'s chip closes; the one after it (else before it)
  /// shows; with none left the dock closes and leaves its zoom.
  ToolDockState without(String toolId) {
    final at = tools.indexOf(toolId);
    if (at < 0) return this;
    final rest = [...tools]..removeAt(at);
    if (rest.isEmpty) {
      return ToolDockState(width: width);
    }
    final next = active == toolId
        ? rest[math.min(at, rest.length - 1)]
        : active;
    return ToolDockState(
      open: open,
      zoom: zoom,
      width: width,
      active: next,
      tools: rest,
    );
  }

  Map<String, Object?> toJson() => {
    'open': open,
    'zoom': zoom,
    'width': width,
    'active': active,
    'tools': tools,
  };

  /// D14, lenient: null only for something that is not an object; a
  /// damaged field is repaired (a bad width is the default, unknown ids go,
  /// an open dock without chips is closed).
  static ToolDockState? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rawTools = raw['tools'];
    final tools = <String>[];
    if (rawTools is List) {
      for (final t in rawTools) {
        if (t is String &&
            kToolIdPattern.hasMatch(t) &&
            !tools.contains(t) &&
            tools.length < kMaxToolsPerWorkspace) {
          tools.add(t);
        }
      }
    }
    final width = raw['width'];
    final active = raw['active'];
    return ToolDockState(
      open: raw['open'] == true && tools.isNotEmpty,
      zoom: raw['zoom'] == true && tools.isNotEmpty,
      width: width is num && width >= _minFraction && width <= _maxFraction
          ? width.toDouble()
          : kToolDockDefaultWidth,
      active: active is String && tools.contains(active)
          ? active
          : tools.firstOrNull,
      tools: List.unmodifiable(tools),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ToolDockState &&
      other.open == open &&
      other.zoom == zoom &&
      other.width == width &&
      other.active == active &&
      _sameList(other.tools, tools);

  @override
  int get hashCode =>
      Object.hash(open, zoom, width, active, Object.hashAll(tools));

  @override
  String toString() =>
      'ToolDockState(open: $open, zoom: $zoom, tools: ${tools.length})';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Where the panes and the dock go in a content area (D3, §8).
final class ToolDockLayout {
  const ToolDockLayout({
    required this.paneWidth,
    required this.dockLeft,
    required this.dockWidth,
  });

  /// The panes' width. Kept while the dock is zoomed over them, so no
  /// terminal is resized by a zoom.
  final double paneWidth;

  /// Null: no dock on screen.
  final double? dockLeft;
  final double dockWidth;

  bool get showsDock => dockLeft != null;

  /// The drag strip sits between the panes and a dock that is not zoomed.
  bool get showsHandle => dockLeft != null && dockLeft! > 0;
}

/// D3, §8: the dock of [dock] in a content area [width] wide. A dock that
/// does not fit beside 360 px of panes is shown only zoomed.
ToolDockLayout toolDockLayout({
  required double width,
  required ToolDockState? dock,
  required bool embedded,
}) {
  final show = embedded && dock != null && dock.open && dock.tools.isNotEmpty;
  if (!show) {
    return ToolDockLayout(paneWidth: width, dockLeft: null, dockWidth: 0);
  }
  final room = width - kToolDockHandle;
  final fits = room >= kToolPaneMinWidth + kToolDockMinWidth;
  final dockWidth = fits
      ? (width * dock.width)
            .clamp(kToolDockMinWidth, room - kToolPaneMinWidth)
            .roundToDouble()
      : 0.0;
  final paneWidth = fits ? room - dockWidth : width;
  if (dock.zoom) {
    return ToolDockLayout(paneWidth: paneWidth, dockLeft: 0, dockWidth: width);
  }
  if (!fits) {
    return ToolDockLayout(paneWidth: width, dockLeft: null, dockWidth: 0);
  }
  return ToolDockLayout(
    paneWidth: paneWidth,
    dockLeft: paneWidth + kToolDockHandle,
    dockWidth: dockWidth,
  );
}

/// The width fraction a drag to [dockWidth] pixels keeps (clamped to the
/// pixel minimums of [toolDockLayout]).
double toolDockFraction({required double width, required double dockWidth}) {
  final room = width - kToolDockHandle;
  if (room < kToolPaneMinWidth + kToolDockMinWidth) {
    return kToolDockDefaultWidth;
  }
  final px = dockWidth.clamp(kToolDockMinWidth, room - kToolPaneMinWidth);
  return (px / width).clamp(_minFraction, _maxFraction).toDouble();
}
````

`apps/desktop/lib/src/tools/tool_dock.dart`:

````dart
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'tool_dock_state.dart';
import 'tool_entry.dart';
import 'tool_registry.dart';

/// Every workspace's dock, and the workspace shown without a tab of its
/// own (D4 [loose]).
final class ToolDocks {
  const ToolDocks({this.byWorkspace = const {}, this.loose});

  final Map<String, ToolDockState> byWorkspace;

  /// D4: a tool of a workspace with no tab opened: that workspace's dock
  /// shows beside an empty content area until a tab is selected.
  final String? loose;

  ToolDockState of(String ws) => byWorkspace[ws] ?? const ToolDockState();

  ToolDocks copyWith({
    Map<String, ToolDockState>? byWorkspace,
    Object? loose = _keep,
  }) => ToolDocks(
    byWorkspace: byWorkspace ?? this.byWorkspace,
    loose: identical(loose, _keep) ? this.loose : loose as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ToolDocks &&
      other.loose == loose &&
      mapEquals(other.byWorkspace, byWorkspace);

  @override
  int get hashCode => Object.hash(
    loose,
    Object.hashAllUnordered([
      for (final e in byWorkspace.entries) Object.hash(e.key, e.value),
    ]),
  );

  @override
  String toString() => 'ToolDocks(${byWorkspace.length})';
}

const Object _keep = Object();

final toolDockProvider = NotifierProvider<ToolDockController, ToolDocks>(
  ToolDockController.new,
);

/// V2-3 D3–D5, D14: the docks. A deleted tool leaves every dock; a deleted
/// workspace takes its dock and its tools (D2, §8). Each workspace's last
/// selected tab is remembered for D4 ("the nearest tab").
class ToolDockController extends Notifier<ToolDocks> {
  final _lastTab = <String, int>{};

  /// D10: the tool each workspace showed last, kept after its chip closed.
  final _lastViewed = <String, String>{};

  @override
  ToolDocks build() {
    ref.listen<List<ToolEntry>>(toolRegistryProvider, (before, after) {
      final ids = {for (final t in after) t.id};
      final gone = {
        for (final t in before ?? const <ToolEntry>[])
          if (!ids.contains(t.id)) t.id,
      };
      for (final id in gone) {
        _dropTool(id);
      }
    });
    ref.listen<SidebarState>(sidebarWorkspacesProvider, (before, after) {
      final now = {for (final w in after.workspaces) w.id};
      for (final w in before?.workspaces ?? const <Workspace>[]) {
        if (now.contains(w.id)) continue;
        _dropWorkspace(w.id);
        ref.read(toolRegistryProvider.notifier).removeWorkspace(w.id);
      }
      if (state.loose != null && after.tabsOf(state.loose!).isNotEmpty) {
        state = state.copyWith(loose: null);
      }
    });
    ref.listen<int?>(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id == null) return;
      final ws = ref.read(sidebarWorkspacesProvider).workspaceOf(id);
      if (ws != null) _lastTab[ws] = id;
      if (state.loose != null) state = state.copyWith(loose: null);
    });
    return const ToolDocks();
  }

  /// D4: the tab of [ws] the user was last in, if it is still there.
  int? lastTabOf(String ws) {
    final id = _lastTab[ws];
    final sidebar = ref.read(sidebarWorkspacesProvider);
    return id != null && sidebar.tabsOf(ws).contains(id) ? id : null;
  }

  /// D4: [ws]'s dock opens with [toolId] on show.
  void open(String ws, String toolId) {
    _lastViewed[ws] = toolId;
    _set(ws, state.of(ws).opened(toolId));
  }

  /// D5: a chip of [ws] on show.
  void activate(String ws, String toolId) {
    _lastViewed[ws] = toolId;
    _set(ws, state.of(ws).activated(toolId));
  }

  /// D10: the tool [ws] showed last (it may have been deleted since).
  String? lastViewedOf(String ws) => _lastViewed[ws];

  /// D10, D17 ×: [toolId]'s chip closes (the last one closes the dock).
  void closeTool(String ws, String toolId) {
    final next = state.of(ws).without(toolId);
    _set(ws, next);
    if (!next.open && state.loose == ws) state = state.copyWith(loose: null);
  }

  /// D17 ⋯ "Close tools", ⌘⇧B: hidden; the chips and their pages stay
  /// (D5: closing the dock unloads nothing).
  void close(String ws) {
    final dock = state.of(ws);
    if (!dock.open) return;
    _set(ws, dock.copyWith(open: false, zoom: false));
    if (state.loose == ws) state = state.copyWith(loose: null);
  }

  /// ⌘⇧B with chips: the dock shows again with the tool last on show.
  bool reopen(String ws) {
    final dock = state.of(ws);
    if (dock.open || dock.tools.isEmpty) return false;
    _set(ws, dock.copyWith(open: true));
    return true;
  }

  /// D3 "Expand" / "Restore".
  void setZoom(String ws, bool zoom) {
    final dock = state.of(ws);
    if (dock.open && dock.zoom != zoom) _set(ws, dock.copyWith(zoom: zoom));
  }

  void setWidth(String ws, double fraction) {
    final dock = state.of(ws);
    if (dock.width != fraction) _set(ws, dock.copyWith(width: fraction));
  }

  /// D4: show [ws] (which has no tab) with its dock.
  void showLoose(String ws) => state = state.copyWith(loose: ws);

  void clearLoose() {
    if (state.loose != null) state = state.copyWith(loose: null);
  }

  /// D14: what `layout.json` keeps — every dock that is not the default.
  Map<String, ToolDockState> get saved => {
    for (final e in state.byWorkspace.entries)
      if (!e.value.isDefault) e.key: e.value,
  };

  /// D14 at startup: the saved docks of workspaces that still exist, with
  /// the chips of tools that still exist in them. Pages load later, when a
  /// dock first shows (lazy).
  void restore(Map<String, ToolDockState> saved) {
    final sidebar = ref.read(sidebarWorkspacesProvider);
    final registry = ref.read(toolRegistryProvider.notifier);
    final next = <String, ToolDockState>{...state.byWorkspace};
    for (final MapEntry(key: ws, value: dock) in saved.entries) {
      if (sidebar.workspace(ws) == null) continue;
      final known = {for (final t in registry.inWorkspace(ws)) t.id};
      var kept = dock;
      for (final id in dock.tools) {
        if (!known.contains(id)) kept = kept.without(id);
      }
      if (kept.isDefault) continue;
      next[ws] = kept;
    }
    state = state.copyWith(byWorkspace: Map.unmodifiable(next));
  }

  void _dropTool(String id) {
    for (final MapEntry(key: ws, value: dock) in state.byWorkspace.entries) {
      if (dock.tools.contains(id)) closeTool(ws, id);
    }
  }

  void _dropWorkspace(String ws) {
    if (!state.byWorkspace.containsKey(ws) && state.loose != ws) return;
    state = state.copyWith(
      byWorkspace: Map.unmodifiable({
        for (final e in state.byWorkspace.entries)
          if (e.key != ws) e.key: e.value,
      }),
      loose: state.loose == ws ? null : state.loose,
    );
    _lastTab.remove(ws);
    _lastViewed.remove(ws);
  }

  void _set(String ws, ToolDockState dock) {
    if (state.of(ws) == dock) return;
    state = state.copyWith(
      byWorkspace: Map.unmodifiable({...state.byWorkspace, ws: dock}),
    );
  }
}
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/tools test/tools
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_dock_state_test.dart` +10, `tool_dock_test.dart` +7, and the earlier `test/tools` files, all passed.
- `No issues found!`
- The whole suite: `3729 passed, 9 skipped`.

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/src/tools/tool_dock_state.dart apps/desktop/lib/src/tools/tool_dock.dart \
  apps/desktop/test/tools/tool_dock_state_test.dart apps/desktop/test/tools/tool_dock_test.dart
git commit -m "feat(v2-tools): a dock per workspace — chips, zoom, width, layout, the workspace shown without a tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 9: `toolDock` in `layout.json`, and what old builds do with it

**Format (D14).** The docks go to a new top-level key of `layout.json` v1:

`"toolDock": {"<workspace id>": {"open": true, "zoom": false, "width": 0.45, "active": "<tool id>", "tools": ["<tool id>", …]}}`

- The key is written only when some dock differs from the default, so a user without tools writes the same file as before.
- It is read leniently: a damaged dock is dropped, never the file.
- On start, the docks come back as they were, but no page loads until its dock shows (Task 10).

**Compatibility (Review Focus 4).** V1 (`164bba6`) and V2.0 (`d8ad686`) ignore unknown top-level keys.
- Two frozen parsers pin it: they read a file with `toolDock` and keep every terminal and AI tab, without a `.bak`.
- The V1 copy already exists (`test/restore/v1/restore_snapshot_v1.dart`, V2-1). This task freezes V2.0's from `d8ad686` the same way.
- Accepted (spec D14): an old build that rewrites the file drops `toolDock`. The tools stay in settings; only the docks reopen empty.

**Files:**
- Modify: `apps/desktop/lib/src/restore/restore_snapshot.dart`, `apps/desktop/lib/src/restore/restore_capture.dart`, `apps/desktop/lib/src/restore/restore_persistence.dart`
- Create: `apps/desktop/test/restore/v2_0/restore_snapshot_v2_0.dart` (generated in Step 1, never edited)
- Test: `apps/desktop/test/restore/tool_dock_restore_test.dart`

**Interfaces:**
- Consumes: `ToolDockState` (`toJson`, `tryParse`, `isDefault`) and `toolDockProvider`/`ToolDockController` (`saved`, `restore`) from Task 8.
- Produces:
  - `RestoreSnapshot({…, Map<String, ToolDockState> toolDock = const {}})` with `final Map<String, ToolDockState> toolDock`;
  - `captureSnapshot({…, Map<String, ToolDockState> toolDock = const {}})`;
  - `RestorePersistence` writes on every `toolDockProvider` change and calls `ToolDockController.restore(snapshot.toolDock)` in `restoreAtStartup`.

- [ ] **Step 1: Freeze the V2.0 parser**

From the worktree root:

````bash
mkdir -p apps/desktop/test/restore/v2_0
{ printf '%s\n' "// Frozen copy of lib/src/restore/restore_snapshot.dart at d8ad686 (the V2.0" \
    "// parser: V1 plus aiTabs), for V2-3 D14's compatibility test. Never edit it."
  git show d8ad686:apps/desktop/lib/src/restore/restore_snapshot.dart \
    | sed "s#'\.\./terminal/#'package:shellx_desktop/src/terminal/#"
} > apps/desktop/test/restore/v2_0/restore_snapshot_v2_0.dart
~/fvm/versions/3.41.4/bin/dart format apps/desktop/test/restore/v2_0/restore_snapshot_v2_0.dart
````

Expected: `Formatted 1 file (1 changed)`. Its imports are now the `package:shellx_desktop/src/terminal/…` ones, as in the V1 copy. It is 550 lines.

- [ ] **Step 2: Write the failing test**

`apps/desktop/test/restore/tool_dock_restore_test.dart`:

````dart
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';
import 'v1/restore_snapshot_v1.dart' as v1;
import 'v2_0/restore_snapshot_v2_0.dart' as v20;

void main() {
  late RecordingFiles files;
  late ProviderContainer c;
  var next = 0;

  setUp(() {
    next = 0;
    files = RecordingFiles();
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        restoreStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        toolIdSourceProvider.overrideWithValue(
          () => 'tool${(next++).toString().padLeft(6, '0')}',
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    c.read(toolDockProvider);
  });

  final termKey = 'b' * 32;
  final aiKey = 'a' * 32;

  ToolEntry add(int port) => c
      .read(toolRegistryProvider.notifier)
      .add(ws: kDefaultWorkspaceId, name: 'T$port', url: 'localhost:$port')!;

  RestoreSnapshot capture() => captureSnapshot(
    tabs: c.read(terminalTabsProvider),
    sidebar: c.read(sidebarWorkspacesProvider),
    keyOf: (_) => termKey,
    now: DateTime(2026, 10, 15, 9),
    cleanExit: true,
    aiKeyOf: (_) => aiKey,
    toolDock: c.read(toolDockProvider.notifier).saved,
  );

  Future<ToolEntry> withDock() async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final t = add(5173);
    c.read(toolDockProvider.notifier).open(kDefaultWorkspaceId, t.id);
    c.read(toolDockProvider.notifier).setWidth(kDefaultWorkspaceId, 0.5);
    return t;
  }

  test('the docks are saved under a top-level toolDock (D14)', () async {
    final t = await withDock();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    expect(json['v'], 1);
    expect(json['toolDock'], {
      kDefaultWorkspaceId: {
        'open': true,
        'zoom': false,
        'width': 0.5,
        'active': t.id,
        'tools': [t.id],
      },
    });
  });

  test('without a dock there is no toolDock key at all', () async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    expect(json.containsKey('toolDock'), isFalse);
  });

  test('round trip: what was written reads back', () async {
    final t = await withDock();
    final back = RestoreSnapshot.tryParse(capture().encode())!;
    expect(back.toolDock[kDefaultWorkspaceId]!.tools, [t.id]);
    expect(back.toolDock[kDefaultWorkspaceId]!.width, 0.5);
    expect(back.tabs, hasLength(1));
  });

  test('a damaged dock is dropped, never the file (D14)', () async {
    await withDock();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    json['toolDock'] = {
      kDefaultWorkspaceId: 'nope',
      '': {'open': true},
      'w2': {'tools': 'x'},
    };
    final back = RestoreSnapshot.tryParse(jsonEncode(json))!;
    expect(back.toolDock, isEmpty);
    expect(back.tabs, hasLength(1));
    json['toolDock'] = 42;
    expect(RestoreSnapshot.tryParse(jsonEncode(json))!.tabs, hasLength(1));
  });

  test('V1 compatibility: the V1 parser keeps the tabs and ignores '
      'toolDock (no .bak)', () async {
    await withDock();
    final old = v1.RestoreSnapshot.tryParse(capture().encode());
    expect(old, isNotNull);
    expect(old!.tabs.map((t) => t.key), [termKey]);
  });

  test('V2.0 compatibility: the V2.0 parser keeps the terminal and AI tabs '
      'and ignores toolDock (no .bak)', () async {
    await withDock();
    openTestAiTab(c, title: 'Fix login', cwd: '/w/shop');
    final text = capture().encode();
    expect(text, contains('"toolDock"'));
    final old = v20.RestoreSnapshot.tryParse(text);
    expect(old, isNotNull);
    expect(old!.tabs.map((t) => t.key), [termKey]);
    expect(old.aiTabs.single.key, aiKey);
  });

  test('persistence writes a dock change and the startup restore brings it '
      'back (D14)', () async {
    final persistence = c.read(restorePersistenceProvider.notifier)..start();
    final t = await withDock();
    await persistence.flushAll(clean: false);
    final written = files.layouts.last;
    expect(written.toolDock[kDefaultWorkspaceId]!.active, t.id);

    // A new run: same settings (the tool), the file just written.
    final settings = c.read(settingsStoreProvider);
    c.dispose();
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(settings),
        restoreStoreProvider.overrideWithValue(RecordingFiles()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 10)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(RestoreLoad(snapshot: written));
    final dock = c.read(toolDockProvider).of(kDefaultWorkspaceId);
    expect([dock.open, dock.active, dock.width], [true, t.id, 0.5]);
  });
}
````

- [ ] **Step 3: Run it to see it fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/tool_dock_restore_test.dart
````

Expected: compilation fails, `No named parameter with the name 'toolDock'`.

- [ ] **Step 4: Implement**

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart
import '../terminal/agent_status.dart' show AgentKind, isValidSessionId;
import '../terminal/pane_layout.dart';
import '../terminal/tab_meta.dart';

// Pure model of `restore/layout.json`: imports only the A3 pane tree, so
// the tab and sidebar notifiers can depend on it without a cycle. Capture
````

with:

````dart
import '../terminal/agent_status.dart' show AgentKind, isValidSessionId;
import '../terminal/pane_layout.dart';
import '../terminal/tab_meta.dart';
import '../tools/tool_dock_state.dart';

// Pure model of `restore/layout.json`: imports only the A3 pane tree, so
// the tab and sidebar notifiers can depend on it without a cycle. Capture
````

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart
    required this.workspaces,
    required this.tabs,
    this.aiTabs = const [],
  });

  final DateTime savedAt;
````

with:

````dart
    required this.workspaces,
    required this.tabs,
    this.aiTabs = const [],
    this.toolDock = const {},
  });

  final DateTime savedAt;
````

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart

  /// V2-1 D14: the AI tabs (top-level `aiTabs`, which V1 ignores).
  final List<SavedAiTab> aiTabs;

  /// Something to restore: a terminal tab or an AI tab (Review Focus 2).
  bool get hasTabs => tabs.isNotEmpty || aiTabs.isNotEmpty;
````

with:

````dart

  /// V2-1 D14: the AI tabs (top-level `aiTabs`, which V1 ignores).
  final List<SavedAiTab> aiTabs;

  /// V2-3 D14: each workspace's tool dock (top-level `toolDock`, which V1
  /// and V2.0 ignore), by workspace id; only docks that are not the default.
  final Map<String, ToolDockState> toolDock;

  /// Something to restore: a terminal tab or an AI tab (Review Focus 2).
  bool get hasTabs => tabs.isNotEmpty || aiTabs.isNotEmpty;
````

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
      );

  /// Equal apart from [savedAt] and [cleanExit]: no write needed.
````

with:

````dart
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
        toolDock: toolDock,
      );

  /// Equal apart from [savedAt] and [cleanExit]: no write needed.
````

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart
    // V2-1 D14: only when there is one, so a terminal-only layout is
    // byte-identical to before.
    if (aiTabs.isNotEmpty) 'aiTabs': [for (final t in aiTabs) t.toJson()],
  };

  String encode() => jsonEncode({
````

with:

````dart
    // V2-1 D14: only when there is one, so a terminal-only layout is
    // byte-identical to before.
    if (aiTabs.isNotEmpty) 'aiTabs': [for (final t in aiTabs) t.toJson()],
    // V2-3 D14: likewise only when there is one.
    if (toolDock.isNotEmpty)
      'toolDock': {for (final e in toolDock.entries) e.key: e.value.toJson()},
  };

  String encode() => jsonEncode({
````

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart
        }
        workspaces.add(SavedWorkspace(id: id, tabs: members));
      }
      final selected = root['selectedTab'] as String?;
      return RestoreSnapshot(
        savedAt: savedAt,
````

with:

````dart
        }
        workspaces.add(SavedWorkspace(id: id, tabs: members));
      }
      // V2-3 D14: the docks; a damaged one is dropped, never the file.
      final toolDock = <String, ToolDockState>{};
      if (root['toolDock'] case final Map<String, Object?> docks) {
        for (final MapEntry(:key, :value) in docks.entries) {
          if (key.isEmpty || key.length > _maxWorkspaceId) continue;
          final dock = ToolDockState.tryParse(value);
          if (dock != null && !dock.isDefault) toolDock[key] = dock;
        }
      }
      final selected = root['selectedTab'] as String?;
      return RestoreSnapshot(
        savedAt: savedAt,
````

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

````dart
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
      );
    } on Object {
      // FormatException, TypeError from a cast, ArgumentError from
````

with:

````dart
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
        toolDock: toolDock,
      );
    } on Object {
      // FormatException, TypeError from a cast, ArgumentError from
````

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

````dart
import '../terminal/pane_layout.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'restore_snapshot.dart';

/// What is restorable right now (D9: exited panes and tabs left with no
````

with:

````dart
import '../terminal/pane_layout.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import '../tools/tool_dock_state.dart';
import 'restore_snapshot.dart';

/// What is restorable right now (D9: exited panes and tabs left with no
````

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

````dart
/// V2-1 D14: AI tabs go to `aiTabs`, keyed by [aiKeyOf] of their AI pane
/// (never [keyOf]: AI pane ids are negative, as displaced tabs' are); none
/// without [aiKeyOf].
RestoreSnapshot captureSnapshot({
  required TerminalTabsState tabs,
  required SidebarState sidebar,
````

with:

````dart
/// V2-1 D14: AI tabs go to `aiTabs`, keyed by [aiKeyOf] of their AI pane
/// (never [keyOf]: AI pane ids are negative, as displaced tabs' are); none
/// without [aiKeyOf].
///
/// V2-3 D14: [toolDock] (each workspace's dock that is not the default) goes
/// to the top-level `toolDock`.
RestoreSnapshot captureSnapshot({
  required TerminalTabsState tabs,
  required SidebarState sidebar,
````

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

````dart
  String? daemon,
  SavedAgent? Function(int sessionId)? agentOf,
  String Function(int aiPaneId)? aiKeyOf,
}) {
  final saved = <int, SavedTab>{};
  final savedAi = <int, SavedAiTab>{};
````

with:

````dart
  String? daemon,
  SavedAgent? Function(int sessionId)? agentOf,
  String Function(int aiPaneId)? aiKeyOf,
  Map<String, ToolDockState> toolDock = const {},
}) {
  final saved = <int, SavedTab>{};
  final savedAi = <int, SavedAiTab>{};
````

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

````dart
      for (final t in tabs.tabs)
        if (!placed.contains(t.id)) ?savedAi[t.id],
    ],
  );
}

````

with:

````dart
      for (final t in tabs.tabs)
        if (!placed.contains(t.id)) ?savedAi[t.id],
    ],
    toolDock: toolDock,
  );
}

````

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

````dart
import '../terminal/resume_offers.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'restore_capture.dart';
import 'restore_snapshot.dart';
import 'restore_store.dart';
````

with:

````dart
import '../terminal/resume_offers.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import '../tools/tool_dock.dart';
import 'restore_capture.dart';
import 'restore_snapshot.dart';
import 'restore_store.dart';
````

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

````dart
    ref.onDispose(() => unawaited(replacements.cancel()));
    ref.listen(terminalTabsProvider, (_, _) => _schedule());
    ref.listen(sidebarWorkspacesProvider, (_, _) => _schedule());
    // A12 D13: a pane's agent session changing is a layout change; a state
    // change alone is not.
    ref.listen(agentStatusProvider, (prev, next) {
````

with:

````dart
    ref.onDispose(() => unawaited(replacements.cancel()));
    ref.listen(terminalTabsProvider, (_, _) => _schedule());
    ref.listen(sidebarWorkspacesProvider, (_, _) => _schedule());
    // V2-3 D14: a dock opened, closed, resized or zoomed.
    ref.listen(toolDockProvider, (_, _) => _schedule());
    // A12 D13: a pane's agent session changing is a layout change; a state
    // change alone is not.
    ref.listen(agentStatusProvider, (prev, next) {
````

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

````dart
        return;
      }
      final snapshot = plan.snapshot;
      // A12 D13–D14: the agents that were running, offered back (never run).
      restoreAgentSessions(
        ref,
````

with:

````dart
        return;
      }
      final snapshot = plan.snapshot;
      // V2-3 D14: the docks as they were; their pages load when shown.
      ref.read(toolDockProvider.notifier).restore(snapshot.toolDock);
      // A12 D13–D14: the agents that were running, offered back (never run).
      restoreAgentSessions(
        ref,
````

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

````dart
      daemon: currentDaemon,
      agentOf: _agentOf,
      aiKeyOf: aiKeyOf,
    );
    final previous = _written;
    if (!force && previous != null && previous.sameLayoutAs(next)) return;
````

with:

````dart
      daemon: currentDaemon,
      agentOf: _agentOf,
      aiKeyOf: aiKeyOf,
      toolDock: ref.read(toolDockProvider.notifier).saved,
    );
    final previous = _written;
    if (!force && previous != null && previous.sameLayoutAs(next)) return;
````

- [ ] **Step 5: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/restore test/restore/tool_dock_restore_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_dock_restore_test.dart` +7, and every other `test/restore` test (the V1 and V2-1 compatibility tests included), all passed.
- `No issues found!`
- The whole suite: `3736 passed, 9 skipped`.

- [ ] **Step 6: Commit**

````bash
git add apps/desktop/lib/src/restore/restore_snapshot.dart apps/desktop/lib/src/restore/restore_capture.dart \
  apps/desktop/lib/src/restore/restore_persistence.dart apps/desktop/test/restore/v2_0/restore_snapshot_v2_0.dart \
  apps/desktop/test/restore/tool_dock_restore_test.dart
git commit -m "feat(v2-tools): docks restored from a top-level toolDock; V1 and V2.0 parsers keep every tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 10: Live pages — retry, knock, crash, dialogs, at most 8

**`ToolPage` (one per opened tool).** It owns the engine, the page state the bar and panels show, and every rule about loading:
- **First load:** nothing loads until the dock first shows the page (D14).
- **Refused (D13):** reloads after 1, 2, 4, 8, then every 10 s, only while shown. A retry loads the URL again (ruling R25). For a tool on this computer, a 1 s TCP knock loads the page as soon as the port answers (ruling R9, criterion 5).
- **Crash:** a dead page reloads once by itself; the next crash shows "Trang đã dừng." (D13).
- **Other errors:** their panel, with no retry.
- **Away from the tool (D9):** tracked against the tool's origin ("Đang ở <host>", "Về tool").
- **To the window:** outside links (`mailto:`, `tel:`, new windows), downloads, forwarded chords and clicks inside the page go to the window.
- **JS dialogs:** shown through the dock's presenter while the page is on screen, with the default answers otherwise, and the flood guard (ruling R10).
- **A new URL (D23):** the page reloads there; a new name does not reload it.

**`ToolPages` (app-wide).** It keeps the live pages, at most `kMaxLiveToolPages = 8` (D5).
- **Eviction:** the ninth page unloads the one unseen longest, never the page on screen. Its chip stays, and the neutral toast `toolTooMany` says so (`ToolUnloadedNotice`).
- **Pages that go:** a closed chip or a deleted tool takes its page. Closing the dock keeps the pages (D5, Review Focus 1).
- **Keys:** a keymap reload sends the new forwarded chords to every page.
- **Engine:** the factory picks WKWebView on macOS and WebView2 on Windows; tests swap in the fake.

**Files:**
- Create: `apps/desktop/lib/src/tools/tool_page.dart`, `apps/desktop/lib/src/tools/tool_pages.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`ToolUnloadedNotice`), `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` (its toast)
- Test: `apps/desktop/test/tools/tool_page_test.dart`, `apps/desktop/test/tools/tool_pages_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `ToolEntry` (`uri`, `origin`, `isLocal`), `isLocalToolHost`, `toolRegistryProvider`;
  - Task 3: `BrowserEngine`, the events, `BrowserDialogPresenter`, `BrowserJsDialog`, `BrowserDataStore`, `browserNativeMacProvider`, `WkWebViewEngine`;
  - Task 5: `toolNavigation`, `toolForwardedChords`;
  - Task 7: `WinFloatingEngine`, `WinFloatingDataStore`, `toolDataFolder`;
  - Task 8: `toolDockProvider`/`ToolDocks`;
  - existing: `shellxConfigProvider` (`bindings`), `terminalTabsProvider.notifier.showNotice(TabNotice)`, `TabNotice`, `NoticeToast`.
- Produces, `lib/src/tools/tool_page.dart`:
  - `Duration toolRetryDelay(int attempt)`;
  - knocking: `const Duration kToolKnockEvery = Duration(seconds: 1)`, `typedef ToolKnock = Future<bool> Function(String host, int port)`, `Future<bool> knockToolPort(String host, int port)`;
  - the dialog guard: `const int kToolDialogBurst = 5`, `const Duration kToolDialogWindow = Duration(seconds: 10)`;
  - `final class ToolPageState({Uri? url, bool loading = false, bool canGoBack = false, BrowserLoadErrorKind? error, Uri? download, bool started = false})` with `bool awayFrom(ToolEntry tool)`, `copyWith`, and `toString()` → `ToolPageState(…)`;
  - `final class ToolPage extends ChangeNotifier`:
    - built with `ToolPage({required ToolEntry tool, required BrowserEngine Function(BrowserDialogPresenter dialogs) engine, ToolKnock knock = knockToolPort, DateTime Function() now = DateTime.now})`;
    - fields: `late final BrowserEngine engine`;
    - getters: `ToolEntry get tool`, `ToolPageState get state`, `bool get shown`;
    - callbacks the window sets: `void Function(String chord)? onShortcut`, `void Function()? onContentClicked`, `void Function(Uri url)? onOpenOutside`, `BrowserDialogPresenter? presenter`;
    - methods: `void setShown(bool shown)`, `Future<void> reload()`, `Future<void> stop()`, `Future<void> back()`, `Future<void> backToTool()`, `void retarget(ToolEntry next)`, `void dismissDownload()`.
- Produces, `lib/src/tools/tool_pages.dart`:
  - `const int kMaxLiveToolPages = 8`;
  - the engine: `typedef ToolEngineFactory = BrowserEngine Function(ToolEntry tool, BrowserDialogPresenter dialogs)`, `final toolEngineFactoryProvider = Provider<ToolEngineFactory>(…)`;
  - `final toolDataStoreProvider = Provider<BrowserDataStore>(…)` and `final toolKnockProvider = Provider<ToolKnock>(…)`;
  - `final toolPagesProvider = NotifierProvider<ToolPages, Set<String>>(ToolPages.new)`, with `ToolPage? existing(String toolId)`, `ToolPage open(ToolEntry tool)` and `void close(String toolId)`.
- Produces, `lib/src/terminal/terminal_tabs.dart`: `final class ToolUnloadedNotice extends TabNotice { const ToolUnloadedNotice(this.name); final String name; }`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/tools/tool_page_test.dart`:

````dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_page.dart';

import '../support/fake_browser_engine.dart';

ToolEntry tool(String url) => ToolEntry(
  id: 'abcde12345',
  ws: 'default',
  name: 'Board',
  url: (parseToolUrl(url) as ToolUrlOk).url,
);

void main() {
  late FakeBrowserEngine engine;
  late BrowserDialogPresenter dialogs;
  final knocks = <String>[];
  var portUp = false;

  ToolPage page(ToolEntry t, {DateTime Function()? now}) => ToolPage(
    tool: t,
    engine: (d) {
      dialogs = d;
      return engine = FakeBrowserEngine();
    },
    knock: (host, port) async {
      knocks.add('$host:$port');
      return portUp;
    },
    now: now ?? DateTime.now,
  );

  setUp(() {
    knocks.clear();
    portUp = false;
  });

  test('nothing loads before the first show; the first show loads the '
      'tool (D14)', () {
    final p = page(tool('localhost:5173/board'));
    expect(engine.loads, isEmpty);
    p.setShown(true);
    expect(engine.loads, [Uri.parse('http://localhost:5173/board')]);
    expect(p.state.started, isTrue);
    p.setShown(false);
    p.setShown(true);
    expect(engine.loads, hasLength(1), reason: 'never reloaded by a show');
  });

  test('refused: retries after 1, 2, 4, 8 then every 10 s, only while '
      'shown; the page shows once the server is up (D13, Review Focus 3)', () {
    fakeAsync((async) {
      final p = page(tool('https://example.com/'));
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      expect(p.state.error, BrowserLoadErrorKind.refused);
      var loads = engine.loads.length;
      for (final wait in [1, 2, 4, 8, 10, 10]) {
        async.elapse(Duration(seconds: wait) - const Duration(milliseconds: 1));
        expect(engine.loads, hasLength(loads), reason: 'not before $wait s');
        async.elapse(const Duration(milliseconds: 1));
        expect(engine.loads, hasLength(++loads), reason: 'at $wait s');
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      }
      p.setShown(false);
      async.elapse(const Duration(seconds: 60));
      expect(engine.loads, hasLength(loads), reason: 'hidden: no retry');
      p.setShown(true);
      async.elapse(const Duration(seconds: 10));
      expect(engine.loads, hasLength(loads + 1));
      engine.emit(const LoadStarted());
      engine.emit(const LoadFinished());
      expect(p.state.error, isNull);
      async.elapse(const Duration(seconds: 60));
      expect(engine.loads, hasLength(loads + 1), reason: 'up: no retry');
    });
  });

  test('between slow reloads a local tool is knocked on every second; once '
      'its port answers the page loads at once (ruling R9, criterion 5)', () {
    fakeAsync((async) {
      page(tool('localhost:5173')).setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      for (final wait in [1, 2, 4, 8]) {
        async.elapse(Duration(seconds: wait));
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      }
      // The next reload is 10 s away now.
      final before = engine.loads.length;
      knocks.clear();
      async.elapse(const Duration(seconds: 3));
      expect(knocks, ['localhost:5173', 'localhost:5173', 'localhost:5173']);
      expect(engine.loads, hasLength(before));
      portUp = true;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(engine.loads, hasLength(before + 1));
    });
  });

  test('no knock for a tool that is not on this computer', () {
    fakeAsync((async) {
      page(tool('nas.lan:8080')).setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      async.elapse(const Duration(seconds: 5));
      expect(knocks, isEmpty);
      expect(engine.loads, hasLength(2), reason: 'the 1 s reload only');
    });
  });

  test('a crash reloads once by itself; the next one shows "stopped" '
      '(D13)', () {
    final p = page(tool('localhost:5173'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('http://localhost:5173/deep')));
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(engine.loads.last, Uri.parse('http://localhost:5173/deep'));
    expect(p.state.error, isNull);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, BrowserLoadErrorKind.crashed);
    final loads = engine.loads.length;
    unawaited(p.reload());
    expect(engine.loads, hasLength(loads + 1), reason: 'user reload');
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, isNull, reason: 'a user reload starts over');
  });

  test('other errors show their panel and do not retry (D13)', () {
    fakeAsync((async) {
      final p = page(tool('localhost:5173'));
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.ats));
      async.elapse(const Duration(seconds: 30));
      expect(p.state.error, BrowserLoadErrorKind.ats);
      expect(engine.loads, hasLength(1));
    });
  });

  test('away from the tool, and back (D9)', () {
    final p = page(tool('localhost:4000'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('https://sso.example.com/login')));
    expect(p.state.awayFrom(p.tool), isTrue);
    unawaited(p.backToTool());
    expect(engine.loads.last, Uri.parse('http://localhost:4000/'));
    engine.emit(UrlChanged(Uri.parse('http://localhost:4000/x')));
    expect(p.state.awayFrom(p.tool), isFalse);
  });

  test('outside links, downloads, keys and clicks reach the window (D9, '
      'D10)', () {
    final p = page(tool('localhost:4000'));
    final outside = <Uri>[];
    final chords = <String>[];
    var clicks = 0;
    p.onOpenOutside = outside.add;
    p.onShortcut = chords.add;
    p.onContentClicked = () => clicks++;
    p.setShown(true);
    engine.emit(OpenOutside(Uri.parse('mailto:a@b.c'), newWindow: false));
    engine.emit(const ShortcutForwarded('super+t'));
    engine.emit(const ContentClicked());
    engine.emit(const NavigationBlocked());
    engine.emit(DownloadBlocked(url: Uri.parse('http://localhost:4000/a.zip')));
    expect(outside, [Uri.parse('mailto:a@b.c')]);
    expect(chords, ['super+t']);
    expect(clicks, 1);
    expect(p.state.download, Uri.parse('http://localhost:4000/a.zip'));
    p.dismissDownload();
    expect(p.state.download, isNull);
  });

  test('a new URL reloads the page there; a new name does not (D23)', () {
    final p = page(tool('localhost:4000'));
    p.setShown(true);
    p.retarget(p.tool.copyWith(name: 'Other'));
    expect(engine.loads, hasLength(1));
    p.retarget(p.tool.copyWith(url: 'http://localhost:4001/'));
    expect(engine.loads.last, Uri.parse('http://localhost:4001/'));
  });

  test('dialogs: shown while presented, default answers otherwise, and a '
      'flood is answered by itself (ruling R10)', () async {
    var now = DateTime(2026, 10, 15, 9);
    final p = page(tool('localhost:4000'), now: () => now);
    const confirm = BrowserJsDialog(
      kind: BrowserJsDialogKind.confirm,
      message: 'Delete?',
    );
    expect(await dialogs(confirm), isFalse, reason: 'no presenter');
    var shown = 0;
    p.presenter = (d) async {
      shown++;
      return true;
    };
    for (var i = 0; i < kToolDialogBurst - 1; i++) {
      expect(await dialogs(confirm), isTrue);
    }
    expect(await dialogs(confirm), isFalse, reason: 'flood');
    expect(shown, kToolDialogBurst - 1);
    now = now.add(kToolDialogWindow + const Duration(seconds: 1));
    expect(await dialogs(confirm), isTrue, reason: 'calm again');
  });

  test('dispose stops retries and disposes the engine', () {
    fakeAsync((async) {
      final p = page(tool('localhost:5173'));
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      p.dispose();
      async.elapse(const Duration(seconds: 30));
      expect(engine.loads, hasLength(1));
      expect(engine.disposed, isTrue);
      expect(knocks, isEmpty);
    });
  });

  test('retry delays are 1, 2, 4, 8, then 10 s', () {
    expect(
      [for (var i = 0; i < 7; i++) toolRetryDelay(i).inSeconds],
      [1, 2, 4, 8, 10, 10, 10],
    );
  });
}
````

`apps/desktop/test/tools/tool_pages_test.dart`:

````dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/config_harness.dart';
import '../support/fake_browser_engine.dart';
import '../support/fake_local_sessions.dart';
import '../support/memory_config_fs.dart';

void main() {
  late ProviderContainer c;
  late MemoryConfigFs fs;
  final engines = <String, FakeBrowserEngine>{};
  var next = 0;

  setUp(() async {
    next = 0;
    engines.clear();
    fs = MemoryConfigFs();
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        toolIdSourceProvider.overrideWithValue(
          () => 'tool${(next++).toString().padLeft(6, '0')}',
        ),
        toolEngineFactoryProvider.overrideWithValue(
          (tool, _) => engines[tool.id] = FakeBrowserEngine(key: tool.id),
        ),
        toolKnockProvider.overrideWithValue((_, _) async => false),
        ...configOverrides(fs),
      ],
    );
    await loadConfig(c);
    c.read(sidebarWorkspacesProvider);
    c.read(toolDockProvider);
    c.read(toolPagesProvider);
  });

  ToolEntry add(int port) => c
      .read(toolRegistryProvider.notifier)
      .add(ws: kDefaultWorkspaceId, name: 'T$port', url: 'localhost:$port')!;
  ToolPages pages() => c.read(toolPagesProvider.notifier);
  void openChip(ToolEntry t) =>
      c.read(toolDockProvider.notifier).open(kDefaultWorkspaceId, t.id);

  test('a page is made once and gets the forwarded chords (D10)', () {
    final t = add(1);
    openChip(t);
    final p = pages().open(t);
    expect(pages().open(t), same(p));
    expect(c.read(toolPagesProvider), {t.id});
    expect(engines[t.id]!.forwarded, contains('super+t'));
    expect(engines[t.id]!.loads, isEmpty, reason: 'loads when shown');
  });

  test('the ninth page unloads the one unseen longest; its chip stays and '
      'a toast says so (D5)', () {
    final tools = [for (var i = 1; i <= 9; i++) add(i)];
    for (final t in tools) {
      openChip(t);
      pages().open(t).setShown(true);
      pages().existing(t.id)!.setShown(false);
    }
    expect(c.read(toolPagesProvider), hasLength(kMaxLiveToolPages));
    expect(pages().existing(tools.first.id), isNull);
    expect(engines[tools.first.id]!.disposed, isTrue);
    expect(
      c.read(toolDockProvider).of(kDefaultWorkspaceId).tools,
      contains(tools.first.id),
    );
    final notice = c.read(terminalTabsProvider).notice;
    expect(notice, isA<ToolUnloadedNotice>());
    expect((notice! as ToolUnloadedNotice).name, 'T1');
  });

  test('the page on screen is never the one unloaded', () {
    final tools = [for (var i = 1; i <= 9; i++) add(i)];
    openChip(tools.first);
    pages().open(tools.first).setShown(true);
    for (final t in tools.skip(1)) {
      openChip(t);
      pages().open(t);
    }
    expect(pages().existing(tools.first.id), isNotNull);
    expect(pages().existing(tools[1].id), isNull);
  });

  test('a closed chip or a deleted tool takes its page (D5, D23)', () {
    final a = add(1), b = add(2);
    openChip(a);
    openChip(b);
    pages().open(a);
    pages().open(b);
    c.read(toolDockProvider.notifier).closeTool(kDefaultWorkspaceId, a.id);
    expect(pages().existing(a.id), isNull);
    expect(engines[a.id]!.disposed, isTrue);
    c.read(toolRegistryProvider.notifier).remove(b.id);
    expect(pages().existing(b.id), isNull);
    expect(c.read(toolPagesProvider), isEmpty);
  });

  test('closing the dock keeps the pages (D5)', () {
    final a = add(1);
    openChip(a);
    pages().open(a);
    c.read(toolDockProvider.notifier).close(kDefaultWorkspaceId);
    expect(pages().existing(a.id), isNotNull);
  });

  test('an edited URL reloads the open page there (D23)', () {
    final a = add(1);
    openChip(a);
    pages().open(a).setShown(true);
    c
        .read(toolRegistryProvider.notifier)
        .update(a.copyWith(url: 'localhost:2'));
    expect(engines[a.id]!.loads.last, Uri.parse('http://localhost:2/'));
  });

  test('a reload of the keys reaches every live page (D10)', () async {
    final a = add(1);
    openChip(a);
    pages().open(a);
    fs.write(testConfigPaths().shellx, 'keybind = super+shift+j=new_tab\n');
    await loadConfig(c);
    expect(engines[a.id]!.forwarded, contains('shift+super+j'));
  });
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_page_test.dart test/tools/tool_pages_test.dart
````

Expected: compilation fails, `Error when reading 'lib/src/tools/tool_page.dart'`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/tools/tool_page.dart`:

````dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../browser/browser_engine.dart';
import 'tool_entry.dart';

/// D13: reloads after a refused connection — 1, 2, 4, 8 s, then every 10 s.
Duration toolRetryDelay(int attempt) =>
    attempt < 4 ? Duration(seconds: 1 << attempt) : const Duration(seconds: 10);

/// Ruling R9: between D13's reloads, a local tool's port is knocked on once
/// a second, so the page shows within about a second of its server coming
/// up (criterion 5), whatever the reload schedule has reached.
const Duration kToolKnockEvery = Duration(seconds: 1);

/// Whether something accepts a TCP connection on [host]:[port] now. Sends
/// nothing; never logs the host.
typedef ToolKnock = Future<bool> Function(String host, int port);

Future<bool> knockToolPort(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 500),
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

/// Ruling R10: a page that opens more than this many JavaScript dialogs in
/// [kToolDialogWindow] gets the default answers without a dialog until it
/// calms down (a loop of `alert()` must not lock the window).
const int kToolDialogBurst = 5;
const Duration kToolDialogWindow = Duration(seconds: 10);

/// What one tool's page shows (D13, D17).
@immutable
final class ToolPageState {
  const ToolPageState({
    this.url,
    this.loading = false,
    this.canGoBack = false,
    this.error,
    this.download,
    this.started = false,
  });

  /// The page's address now (null before the first load).
  final Uri? url;
  final bool loading;
  final bool canGoBack;

  /// D13: the panel over the page; null when the page shows.
  final BrowserLoadErrorKind? error;

  /// D9: a download was stopped (its URL, or the page's).
  final Uri? download;

  /// The page was asked to load at least once (lazy, D14).
  final bool started;

  /// D9 "On {host}": the page left the tool's origin (an SSO round trip).
  bool awayFrom(ToolEntry tool) {
    final u = url;
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return false;
    final t = tool.uri;
    return u.scheme != t.scheme || u.host != t.host || u.port != t.port;
  }

  ToolPageState copyWith({
    Object? url = _keep,
    bool? loading,
    bool? canGoBack,
    Object? error = _keep,
    Object? download = _keep,
    bool? started,
  }) => ToolPageState(
    url: identical(url, _keep) ? this.url : url as Uri?,
    loading: loading ?? this.loading,
    canGoBack: canGoBack ?? this.canGoBack,
    error: identical(error, _keep)
        ? this.error
        : error as BrowserLoadErrorKind?,
    download: identical(download, _keep) ? this.download : download as Uri?,
    started: started ?? this.started,
  );

  @override
  String toString() => 'ToolPageState(…)';
}

const Object _keep = Object();

/// One tool's live page: its engine, its state, D13's retries and the
/// crash reload, D9's outside links, downloads and dialogs. Created when
/// its dock first shows it (D14), disposed when its chip closes, the tool
/// goes or the app needs the room (D5).
final class ToolPage extends ChangeNotifier {
  ToolPage({
    required ToolEntry tool,
    required BrowserEngine Function(BrowserDialogPresenter dialogs) engine,
    ToolKnock knock = knockToolPort,
    DateTime Function() now = DateTime.now,
  }) : _tool = tool,
       _knock = knock,
       _now = now {
    this.engine = engine(_presentDialog);
    _events = this.engine.events.listen(_on);
  }

  late final BrowserEngine engine;
  late final StreamSubscription<BrowserEngineEvent> _events;
  final ToolKnock _knock;
  final DateTime Function() _now;
  ToolEntry _tool;
  ToolPageState _state = const ToolPageState();
  bool _shown = false;
  bool _disposed = false;

  /// What the last load asked for (a retry loads it again).
  Uri? _target;
  int _attempt = 0;
  int _crashes = 0;
  Timer? _retry;
  Timer? _knocker;
  bool _knocking = false;
  final List<DateTime> _dialogs = [];

  /// Set by the window: a ShellX chord the page handed back (D10).
  void Function(String chord)? onShortcut;

  /// Set by the window: a click inside the page (D10).
  void Function()? onContentClicked;

  /// Set by the window: a new window, `mailto:` or `tel:` (D9).
  void Function(Uri url)? onOpenOutside;

  /// Set by the dock while the page is on screen: shows a JavaScript
  /// dialog with the tool's name (D9). Without it: the default answers.
  BrowserDialogPresenter? presenter;

  ToolEntry get tool => _tool;
  ToolPageState get state => _state;
  bool get shown => _shown;

  /// The dock shows this page, or stopped showing it. The first show loads
  /// the tool's URL (D14: nothing loads before); retries run only while
  /// shown (D13).
  void setShown(bool shown) {
    if (_disposed || _shown == shown) return;
    _shown = shown;
    if (shown && !_state.started) {
      unawaited(_load(_tool.uri));
      return;
    }
    if (shown && _state.error == BrowserLoadErrorKind.refused) {
      _scheduleRetry();
    } else if (!shown) {
      _stopRetrying();
    }
  }

  /// ↻ and the panels' "Reload": a user's reload starts over (crash count,
  /// retry schedule).
  Future<void> reload() async {
    _crashes = 0;
    _attempt = 0;
    _stopRetrying();
    if (_state.error != null || !_state.started) {
      await _load(_state.url ?? _target ?? _tool.uri);
    } else {
      _set(_state.copyWith(download: null));
      await engine.reload();
    }
  }

  Future<void> stop() => engine.stop();
  Future<void> back() => engine.goBack();

  /// D9 "Back to tool".
  Future<void> backToTool() => _load(_tool.uri);

  /// D23: the tool was edited. A new URL loads at once (if the page had
  /// started); a new name or flag only changes what the bar says.
  void retarget(ToolEntry next) {
    final moved = next.url != _tool.url;
    _tool = next;
    if (moved && _state.started) {
      unawaited(_load(next.uri));
    } else {
      notifyListeners();
    }
  }

  void dismissDownload() => _set(_state.copyWith(download: null));

  Future<void> _load(Uri url) async {
    _target = url;
    _stopRetrying();
    _set(
      _state.copyWith(
        started: true,
        loading: true,
        error: null,
        download: null,
      ),
    );
    await engine.load(url);
  }

  void _on(BrowserEngineEvent e) {
    switch (e) {
      case LoadStarted():
        _set(_state.copyWith(loading: true, error: null, download: null));
      case LoadFinished():
        _attempt = 0;
        _stopRetrying();
        _set(_state.copyWith(loading: false, error: null));
      case UrlChanged(:final url):
        _set(_state.copyWith(url: url));
      case HistoryChanged(:final canGoBack):
        _set(_state.copyWith(canGoBack: canGoBack));
      case LoadFailed(:final kind):
        _failed(kind);
      case DownloadBlocked(:final url):
        _set(_state.copyWith(loading: false, download: url ?? _state.url));
      case OpenOutside(:final url):
        onOpenOutside?.call(url);
      case ShortcutForwarded(:final chord):
        onShortcut?.call(chord);
      case ContentClicked():
        onContentClicked?.call();
      case TitleChanged() || LoadProgress() || NavigationBlocked():
        break; // D9: a blocked navigation says nothing
    }
  }

  void _failed(BrowserLoadErrorKind kind) {
    if (kind == BrowserLoadErrorKind.crashed && _crashes == 0) {
      // D13: the page's process died: one reload by itself.
      _crashes++;
      unawaited(_load(_state.url ?? _target ?? _tool.uri));
      return;
    }
    _set(_state.copyWith(loading: false, error: kind));
    if (kind == BrowserLoadErrorKind.refused && _shown) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(toolRetryDelay(_attempt), () {
      _attempt++;
      unawaited(_load(_state.url ?? _target ?? _tool.uri));
    });
    final target = _state.url ?? _target ?? _tool.uri;
    if (isLocalToolHost(target.host)) {
      _knocker?.cancel();
      _knocker = Timer.periodic(kToolKnockEvery, (_) => _knockOnce(target));
    }
  }

  Future<void> _knockOnce(Uri target) async {
    if (_knocking) return;
    _knocking = true;
    try {
      final up = await _knock(target.host, target.port);
      if (up &&
          !_disposed &&
          _shown &&
          _state.error == BrowserLoadErrorKind.refused) {
        unawaited(_load(target));
      }
    } finally {
      _knocking = false;
    }
  }

  void _stopRetrying() {
    _retry?.cancel();
    _retry = null;
    _knocker?.cancel();
    _knocker = null;
  }

  Future<Object?> _presentDialog(BrowserJsDialog dialog) async {
    final now = _now();
    _dialogs.removeWhere((t) => now.difference(t) > kToolDialogWindow);
    _dialogs.add(now);
    final show = presenter;
    if (show == null || _dialogs.length > kToolDialogBurst || _disposed) {
      return switch (dialog.kind) {
        BrowserJsDialogKind.alert => null,
        BrowserJsDialogKind.confirm => false,
        BrowserJsDialogKind.prompt => null,
      };
    }
    return show(dialog);
  }

  void _set(ToolPageState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRetrying();
    unawaited(_events.cancel());
    unawaited(engine.dispose());
    super.dispose();
  }

  @override
  String toString() => 'ToolPage(…)';
}
````

`apps/desktop/lib/src/tools/tool_pages.dart`:

````dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browser/browser_engine.dart';
import '../browser/engines/win_floating_engine.dart';
import '../browser/engines/wk_webview_engine.dart';
import '../config/config_controller.dart';
import '../config/keybindings.dart';
import '../terminal/terminal_tabs.dart';
import 'tool_dock.dart';
import 'tool_entry.dart';
import 'tool_keys.dart';
import 'tool_navigation.dart';
import 'tool_page.dart';
import 'tool_registry.dart';

/// D5 (A6 D28): at most this many live pages in the whole app.
const int kMaxLiveToolPages = 8;

/// Makes the engine of [tool]'s page; [dialogs] shows its JavaScript
/// dialogs. Tests swap it for `FakeBrowserEngine`.
typedef ToolEngineFactory =
    BrowserEngine Function(ToolEntry tool, BrowserDialogPresenter dialogs);

final toolEngineFactoryProvider = Provider<ToolEngineFactory>(
  (ref) =>
      (tool, dialogs) => Platform.isWindows
      ? WinFloatingEngine(
          policy: toolNavigation,
          dataFolder: toolDataFolder(Platform.environment) ?? '',
        )
      : WkWebViewEngine(
          native: ref.read(browserNativeMacProvider),
          policy: toolNavigation,
          dialogs: dialogs,
        ),
);

/// D8, D22: the data store every tool shares ("Clear tool data…").
final toolDataStoreProvider = Provider<BrowserDataStore>(
  (ref) => Platform.isWindows
      ? WinFloatingDataStore(toolDataFolder(Platform.environment))
      : ref.read(browserNativeMacProvider),
);

/// Ruling R9's knock; tests make it a fake.
final toolKnockProvider = Provider<ToolKnock>((ref) => knockToolPort);

final toolPagesProvider = NotifierProvider<ToolPages, Set<String>>(
  ToolPages.new,
);

/// V2-3 D5: the live pages, by tool id (the state is the set of ids, so a
/// dock rebuilds when a page comes or goes). A page is made when its dock
/// first shows it; past [kMaxLiveToolPages] the page unseen longest is
/// unloaded (its chip stays, a toast says so). A closed chip, a deleted
/// tool or a new URL (D23) reaches its page here.
class ToolPages extends Notifier<Set<String>> {
  final _pages = <String, ToolPage>{};

  /// Least recently shown first.
  final _order = <String>[];

  @override
  Set<String> build() {
    ref.listen<List<ToolEntry>>(toolRegistryProvider, (_, tools) {
      final byId = {for (final t in tools) t.id: t};
      for (final id in [..._pages.keys]) {
        final tool = byId[id];
        if (tool == null) {
          close(id);
        } else if (!identical(tool, _pages[id]!.tool)) {
          _pages[id]!.retarget(tool);
        }
      }
    });
    ref.listen<ToolDocks>(toolDockProvider, (_, docks) {
      final open = {for (final d in docks.byWorkspace.values) ...d.tools};
      for (final id in [..._pages.keys]) {
        if (!open.contains(id)) close(id);
      }
    });
    ref.listen<KeyBindings>(shellxConfigProvider.select((s) => s.bindings), (
      _,
      bindings,
    ) {
      final chords = toolForwardedChords(bindings);
      for (final page in _pages.values) {
        unawaited(page.engine.setForwardedChords(chords));
      }
    });
    ref.onDispose(() {
      for (final page in _pages.values) {
        page.dispose();
      }
      _pages.clear();
      _order.clear();
    });
    return const {};
  }

  ToolPage? existing(String toolId) => _pages[toolId];

  /// [tool]'s page, made (not loaded: [ToolPage.setShown] loads it) on the
  /// first call. Never call it while building.
  ToolPage open(ToolEntry tool) {
    final made = _pages[tool.id];
    if (made != null) {
      _touch(tool.id);
      return made;
    }
    final factory = ref.read(toolEngineFactoryProvider);
    final page = ToolPage(
      tool: tool,
      engine: (dialogs) => factory(tool, dialogs),
      knock: ref.read(toolKnockProvider),
    );
    unawaited(
      page.engine.setForwardedChords(
        toolForwardedChords(ref.read(shellxConfigProvider).bindings),
      ),
    );
    _pages[tool.id] = page;
    _touch(tool.id);
    _evict();
    state = {..._pages.keys};
    return page;
  }

  /// The page leaves (its chip closed, its tool deleted).
  void close(String toolId) {
    final page = _pages.remove(toolId);
    if (page == null) return;
    _order.remove(toolId);
    page.dispose();
    state = {..._pages.keys};
  }

  void _touch(String id) {
    _order
      ..remove(id)
      ..add(id);
  }

  void _evict() {
    while (_pages.length > kMaxLiveToolPages) {
      final victim = _order.firstWhere(
        (id) => !(_pages[id]?.shown ?? false),
        orElse: () => _order.first,
      );
      final name = _pages[victim]?.tool.name ?? '';
      close(victim);
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(ToolUnloadedNotice(name));
    }
  }

  @override
  String toString() => 'ToolPages(${_pages.length})';
}
````

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

````dart
/// Error toast.
final class LinkOpenFailedNotice extends TabNotice {
  const LinkOpenFailedNotice();
}

/// A10 D15–D17: why a drop or an image paste did nothing.
````

with:

````dart
/// Error toast.
final class LinkOpenFailedNotice extends TabNotice {
  const LinkOpenFailedNotice();
}

/// V2-3 D5: a ninth live tool page unloaded the one unseen longest; its chip
/// stays (a click loads it again). [name] is the tool's name, shown only
/// in the toast. Neutral toast.
final class ToolUnloadedNotice extends TabNotice {
  const ToolUnloadedNotice(this.name);
  final String name;
}

/// A10 D15–D17: why a drop or an image paste did nothing.
````

The toast is neutral, like the other informational notices:

In `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`, replace:

````dart
      widget.notice is RestorePanesFailedNotice ||
      widget.notice is CliSkillsCopiedNotice ||
      widget.notice is CliPathInstalledNotice ||
      widget.notice is SshRecentClearedNotice;

  /// A fresh 6 s (4 s when neutral), unless the pointer or the keyboard is
  /// on the toast.
````

with:

````dart
      widget.notice is RestorePanesFailedNotice ||
      widget.notice is CliSkillsCopiedNotice ||
      widget.notice is CliPathInstalledNotice ||
      widget.notice is SshRecentClearedNotice ||
      widget.notice is ToolUnloadedNotice;

  /// A fresh 6 s (4 s when neutral), unless the pointer or the keyboard is
  /// on the toast.
````

In `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`, replace:

````dart
    RemotePortForwardFailedNotice(:final port) => l10n.remotePortForwardFailed(
      port,
    ),
  };

  @override
````

with:

````dart
    RemotePortForwardFailedNotice(:final port) => l10n.remotePortForwardFailed(
      port,
    ),
    ToolUnloadedNotice(:final name) => l10n.toolTooMany(name),
  };

  @override
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/tools test/tools lib/src/terminal/terminal_tabs.dart lib/src/ui/terminal/terminal_overlays.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_page_test.dart` +12, `tool_pages_test.dart` +7, and the earlier `test/tools` files, all passed.
- `No issues found!`
- The whole suite: `3755 passed, 9 skipped`.

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/src/tools/tool_page.dart apps/desktop/lib/src/tools/tool_pages.dart \
  apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart \
  apps/desktop/test/tools/tool_page_test.dart apps/desktop/test/tools/tool_pages_test.dart
git commit -m "feat(v2-tools): live tool pages — retries with a port knock, one crash reload, dialogs with a flood guard, at most 8

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 11: Port suggestions — the workspace's terminals and its AI agents' servers

The Add-tool dialog suggests "Running ports ShellX can see" for its workspace (D12, criterion 2), from two sources:
1. **Terminal panes.** `PaneSession.ports` of every terminal pane in the workspace, the terminal panes of AI tabs included. These are what A2's watcher already sees. SSH and exited panes are skipped (ruling R13).
2. **AI agents.** One on-demand scan, when the dialog opens, of the ports held by processes under the workspace's AI agent pids. For example, Claude ran `npm run dev`, which runs node, which listens. The agent runs in the window in both modes, so the window scans.
   - `shellx_agent` gains `ListeningScan`: one read of the listening sockets plus one read of the process table (`ps -axo pid=,ppid=,comm=` on macOS, CIM `Win32_Process` on Windows), and `under(roots)`. It reuses A2's `PortProbe` and `ownerOf`, with the agent pids standing in for the session shells.
   - The desktop records each AI pane's agent pid from its runtime factory (ruling R12). `shellx_ai` stays untouched.

**Each suggestion.** It reads `localhost:<port> · <process>`. At most 8, sorted by port, without ports a tool of the workspace already uses.

**Files:**
- Modify: `packages/shellx_agent/lib/src/context/listening_ports.dart`
- Test: `packages/shellx_agent/test/context/listening_under_test.dart`
- Modify: `apps/desktop/lib/src/ai/ai_runtimes.dart`
- Create: `apps/desktop/lib/src/tools/tool_ports.dart`
- Test: `apps/desktop/test/tools/tool_ports_test.dart`

**Interfaces:**
- Consumes:
  - existing: `PortProbe` (`listening()`, `parents()`), `MacPortProbe`, `WindowsPortProbe`, `parseParentTable`, `TimedCommandRunner`/`runWithTimeout`, `ProbeOutput` (`shellx_agent`);
  - existing: `AiRuntimeRequest`, `aiRuntimeFactoryProvider`, `aiHostProvider`/`AiHost` (`resolver`, `env`, `launch`, `checkpoints`, `clientVersion`), `AiRuntime`, `AiSessionState`, `AgentLauncher`, `AgentChannel`, `AgentProcess`;
  - existing: `TerminalTabsState` (`tabs`, each tab's `panes` and `aiPanes`), `SidebarState.tabsOf`, `PaneSession` (`ports`, `remote`, `exited`);
  - Task 1's `toolRegistryProvider`.
- Produces, `shellx_agent` (exported by `package:shellx_agent/shellx_agent.dart`):
  - `typedef ProgramRow = ({int parent, String name})`. It is not `ProcessRow`, which `shellx_ai` already exports.
  - `Map<int, ProgramRow> parseProcessTable(String output)`;
  - `abstract interface class ProcessTableProbe { Future<Map<int, ProgramRow>> processTable(); }`, implemented by `MacPortProbe` and `WindowsPortProbe`;
  - `typedef RootedPort = ({int port, int root, String name})`;
  - `final class ListeningScan(Map<int, Set<int>> listening, Map<int, ProgramRow> table)`:
    - `static const empty`, `static Future<ListeningScan> read(PortProbe ports, ProcessTableProbe table)`;
    - `String nameOf(int port)`, `List<RootedPort> under(Set<int> roots)`;
    - `toString()` → `ListeningScan(…)`.
- Produces, `apps/desktop/lib/src/ai/ai_runtimes.dart`:
  - `AiRuntimeRequest({…, int? paneId})`;
  - `final class AiAgentPids` with `int? of(int paneId)`, `void set(int paneId, int pid)`, `void clear(int paneId, int pid)`;
  - `final aiAgentPidsProvider = Provider<AiAgentPids>(…)`;
  - `AgentLauncher recordingAgentPids(AgentLauncher inner, AiAgentPids pids, int paneId, {int? Function(AgentChannel channel) pidOf})`.
- Produces, `apps/desktop/lib/src/tools/tool_ports.dart`:
  - `const int kMaxToolSuggestions = 8`;
  - `final class ToolPortSuggestion({required int port, String process = ''})` with `String get url` (`http://localhost:<port>/`) and `toString()` → `ToolPortSuggestion(…)`;
  - `List<ToolPortSuggestion> toolPortSuggestions({required Set<int> panePorts, List<RootedPort> agentPorts = const [], String Function(int port)? nameOf, required Set<int> usedPorts})`;
  - `Set<int> workspacePanePorts(TerminalTabsState tabs, SidebarState sidebar, String ws)`, `Set<int> workspaceAgentPids(TerminalTabsState tabs, SidebarState sidebar, String ws, AiAgentPids pids)`;
  - `final toolPortProbeProvider = Provider<({PortProbe ports, ProcessTableProbe table})>(…)`;
  - `final toolPortSuggestionsProvider = FutureProvider.autoDispose.family<List<ToolPortSuggestion>, String>(…)` (by workspace id, one scan per dialog).

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/context/listening_under_test.dart`:

````dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class _Probe implements PortProbe, ProcessTableProbe {
  _Probe(this.ports, this.rows);
  final Map<int, Set<int>> ports;
  final Map<int, ProgramRow> rows;
  int calls = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    calls++;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => {
    for (final e in rows.entries) e.key: e.value.parent,
  };

  @override
  Future<Map<int, ProgramRow>> processTable() async {
    calls++;
    return rows;
  }
}

void main() {
  test('ps / CIM "pid ppid command": the base name, without .exe; spaces, '
      'controls and bad lines (V2-3 D12)', () {
    final table = parseProcessTable(
      '  612   500 /usr/local/bin/node\n'
      ' 700 612 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n'
      '4321 100 node.exe\n'
      '4400 100 C:\\Program Files\\Py\\python.EXE\n'
      '9 1 a\u0007b\n'
      'bad line\n'
      '12 x y\n',
    );
    expect(table, {
      612: (parent: 500, name: 'node'),
      700: (parent: 612, name: 'Electron'),
      4321: (parent: 100, name: 'node'),
      4400: (parent: 100, name: 'python'),
      9: (parent: 1, name: 'ab'),
    });
    expect(parseProcessTable('1 0 ${'x' * 100}')[1]!.name, hasLength(64));
  });

  test('MacPortProbe.processTable runs ps with the command column', () async {
    final calls = <String>[];
    final probe = MacPortProbe(
      run: (exe, args, {required timeout}) async {
        calls.add('$exe ${args.join(' ')} ${timeout.inSeconds}');
        return const ProbeOutput(0, '100 1 /bin/zsh\n');
      },
    );
    expect(await probe.processTable(), {100: (parent: 1, name: 'zsh')});
    expect(calls, ['/bin/ps -axo pid=,ppid=,comm= 2']);
  });

  test('WindowsPortProbe.processTable asks CIM for the name too', () async {
    final calls = <List<Object>>[];
    final probe = WindowsPortProbe(
      environment: const {'SystemRoot': r'D:\Win'},
      run: (exe, args, {required timeout}) async {
        calls.add([exe, args, timeout.inSeconds]);
        return const ProbeOutput(0, '4321 100 node.exe\n');
      },
    );
    expect(await probe.processTable(), {4321: (parent: 100, name: 'node')});
    expect(
      calls.single[0],
      r'D:\Win\System32\WindowsPowerShell\v1.0\powershell.exe',
    );
    expect((calls.single[1] as List).last, contains('ParentProcessId,Name'));
    expect(calls.single[2], 5);
  });

  test('ListeningScan.under: ports of processes under the roots, the '
      'roots included; others never (V2-3 D12)', () async {
    // claude (900) → node adapter (901) → npm (902) → vite (903) :5173
    // claude (900) itself :7777; an unrelated server (50) :8080.
    final probe = _Probe(
      {
        903: {5173},
        900: {7777},
        50: {8080},
      },
      {
        900: (parent: 1, name: 'claude'),
        901: (parent: 900, name: 'node'),
        902: (parent: 901, name: 'npm'),
        903: (parent: 902, name: 'node'),
        50: (parent: 1, name: 'nginx'),
      },
    );
    final scan = await ListeningScan.read(probe, probe);
    expect(scan.under({900}), [
      (port: 5173, root: 900, name: 'node'),
      (port: 7777, root: 900, name: 'claude'),
    ]);
    expect(scan.under({}), isEmpty);
    expect(scan.nameOf(8080), 'nginx');
    expect(scan.nameOf(9), '');
    expect(scan.toString(), 'ListeningScan(3)');
  });

  test('ListeningScan.read reads no table when nothing listens', () async {
    final none = _Probe({}, {});
    final scan = await ListeningScan.read(none, none);
    expect(scan.under({1}), isEmpty);
    expect(none.calls, 1);
  });
}
````

`apps/desktop/test/tools/tool_ports_test.dart`:

````dart
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_ports.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

final class _Probe implements PortProbe, ProcessTableProbe {
  _Probe(this.ports, this.rows);
  final Map<int, Set<int>> ports;
  final Map<int, ProgramRow> rows;
  int scans = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    scans++;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => const {};

  @override
  Future<Map<int, ProgramRow>> processTable() async => rows;
}

final class _Channel implements AgentChannel {
  final _exit = Completer<int>();
  void end() => _exit.complete(0);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  StreamSink<List<int>> get stdin => StreamController<List<int>>().sink;
  @override
  String get stderrTail => '';
  @override
  Future<void> stop() async {}
  @override
  Future<void> kill() async {}
}

void main() {
  test('suggestions: panes and agents, named, without used ports, by port, '
      'at most 8 (D12)', () {
    final list = toolPortSuggestions(
      panePorts: {5173, 3000, 9000},
      agentPorts: const [
        (port: 4000, root: 1, name: 'node'),
        (port: 3000, root: 1, name: 'node'),
      ],
      nameOf: (p) => p == 5173 ? 'vite' : '',
      usedPorts: {9000},
    );
    expect(list, const [
      ToolPortSuggestion(port: 3000, process: 'node'),
      ToolPortSuggestion(port: 4000, process: 'node'),
      ToolPortSuggestion(port: 5173, process: 'vite'),
    ]);
    expect(list.first.url, 'http://localhost:3000/');
    final many = toolPortSuggestions(
      panePorts: {for (var p = 1; p <= 12; p++) p},
      usedPorts: const {},
    );
    expect(many.map((s) => s.port), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(many.first.toString(), 'ToolPortSuggestion(…)');
  });

  group('in a window', () {
    late FakeLocalSessions local;
    late ProviderContainer c;
    late _Probe probe;

    setUp(() {
      local = FakeLocalSessions();
      probe = _Probe(
        {
          100: {5173},
          903: {4000},
          50: {8080},
        },
        {
          100: (parent: 1, name: 'node'),
          900: (parent: 1, name: 'claude'),
          903: (parent: 900, name: 'node'),
          50: (parent: 1, name: 'nginx'),
        },
      );
      c = ProviderContainer.test(
        overrides: [
          localSessionsProvider.overrideWithValue(local),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
          appL10nProvider.overrideWithValue(
            lookupAppLocalizations(const Locale('en')),
          ),
          toolPortProbeProvider.overrideWithValue((ports: probe, table: probe)),
        ],
      );
      c.read(sidebarWorkspacesProvider);
    });

    test('a terminal pane\'s ports, and an AI agent\'s server, appear in '
        'one scan (D12, criterion 2)', () async {
      await c.read(terminalTabsProvider.notifier).openTab();
      final session = local.summaries.single.id;
      local.replace(local.summary(session, ports: [5173]));
      final ai = openTestAiTab(c, title: 'x', cwd: '/w');
      c.read(aiAgentPidsProvider).set(ai.ai!.id, 900);
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, const [
        ToolPortSuggestion(port: 4000, process: 'node'),
        ToolPortSuggestion(port: 5173, process: 'node'),
      ]);
      expect(probe.scans, 1);
    });

    test('ports a tool of the workspace uses are left out (D12)', () async {
      await c.read(terminalTabsProvider.notifier).openTab();
      local.replace(local.summary(local.summaries.single.id, ports: [5173]));
      c
          .read(toolRegistryProvider.notifier)
          .add(ws: kDefaultWorkspaceId, name: 'x', url: 'localhost:5173');
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, isEmpty);
    });

    test('an SSH pane\'s ports are the server\'s: never suggested', () async {
      await c
          .read(terminalTabsProvider.notifier)
          .openTab(launch: SshLaunch(SshTarget.parseKey('me@host')!));
      local.replace(
        local.summary(
          local.summaries.single.id,
          ports: [5173],
          remote: SessionRemote(
            launch: SshLaunch(SshTarget.parseKey('me@host')!),
          ),
        ),
      );
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, isEmpty);
      expect(probe.scans, 0, reason: 'nothing to look up');
    });
  });

  test('recordingAgentPids keeps the pid while the agent runs', () async {
    final pids = AiAgentPids();
    final channel = _Channel();
    final launch = recordingAgentPids(
      (command, {required cwd}) async => channel,
      pids,
      -1,
      pidOf: (_) => 4242,
    );
    await launch(const AgentCommand(executable: 'x'), cwd: '/');
    expect(pids.of(-1), 4242);
    channel.end();
    await Future<void>.delayed(Duration.zero);
    expect(pids.of(-1), isNull);
    expect(pids.toString(), 'AiAgentPids(0)');
  });

  test('a real agent process has its pid read', () async {
    final pids = AiAgentPids();
    final launch = recordingAgentPids(
      (command, {required cwd}) => AgentProcess.start(command, cwd: cwd),
      pids,
      -3,
    );
    final channel = await launch(
      const AgentCommand(executable: '/bin/cat'),
      cwd: Directory.systemTemp.path,
    );
    expect(pids.of(-3), isNotNull);
    await channel.kill();
    await channel.exitCode;
    await Future<void>.delayed(Duration.zero);
    expect(pids.of(-3), isNull);
  }, testOn: '!windows');
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
(cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/context/listening_under_test.dart)
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_ports_test.dart)
````

Expected: both fail to compile: `parseProcessTable`, `ListeningScan` and `ProcessTableProbe` are not defined yet in `shellx_agent`, and the desktop test reports `Error when reading 'lib/src/tools/tool_ports.dart'`.

- [ ] **Step 3: Implement the scan in `shellx_agent`**

In `packages/shellx_agent/lib/src/context/listening_ports.dart`, replace:

````dart
  return null;
}

/// Where listening ports and the process tree come from.
abstract interface class PortProbe {
  /// Listening TCP ports by pid. Throws [PortProbeException].
````

with:

````dart
  return null;
}

/// V2-3 D12: one process of the table — its parent and its program's name.
typedef ProgramRow = ({int parent, String name});

final _controls = RegExp(r'[\x00-\x1f\x7f]');

/// `pid ppid command` per line (`ps -axo pid=,ppid=,comm=`, and the CIM
/// query of [WindowsPortProbe.processTable]). The command may hold spaces
/// (a path): its base name is kept, without a Windows `.exe`, controls
/// dropped, at most 64 characters. Never logged.
Map<int, ProgramRow> parseProcessTable(String output) {
  final result = <int, ProgramRow>{};
  for (final line in const LineSplitter().convert(output)) {
    final m = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.+?)\s*$').firstMatch(line);
    if (m == null) continue;
    final base = m.group(3)!.split(RegExp(r'[\\/]')).last;
    var name = base.replaceAll(_controls, '');
    if (name.toLowerCase().endsWith('.exe')) {
      name = name.substring(0, name.length - 4);
    }
    if (name.length > 64) name = name.substring(0, 64);
    result[int.parse(m.group(1)!)] = (
      parent: int.parse(m.group(2)!),
      name: name,
    );
  }
  return result;
}

/// V2-3 D12: the process table with program names, read on demand.
abstract interface class ProcessTableProbe {
  /// pid → parent and name. Throws [PortProbeException].
  Future<Map<int, ProgramRow>> processTable();
}

/// V2-3 D12: a port a process under one of the roots listens on.
typedef RootedPort = ({int port, int root, String name});

/// V2-3 D12: the listening ports and the process table, read once, on
/// demand (when "Add tool" opens) — never polled.
final class ListeningScan {
  const ListeningScan(this.listening, this.table);

  /// Listening TCP ports by pid.
  final Map<int, Set<int>> listening;

  /// pid → parent and program name; empty when nothing listens.
  final Map<int, ProgramRow> table;

  static const empty = ListeningScan({}, {});

  /// Reads the ports, then the table only when something listens. Throws
  /// [PortProbeException].
  static Future<ListeningScan> read(
    PortProbe ports,
    ProcessTableProbe table,
  ) async {
    final listening = await ports.listening();
    if (listening.isEmpty) return empty;
    return ListeningScan(listening, await table.processTable());
  }

  /// The program listening on [port] ('' when unknown).
  String nameOf(int port) {
    for (final MapEntry(key: pid, value: open) in listening.entries) {
      if (open.contains(port)) return table[pid]?.name ?? '';
    }
    return '';
  }

  /// The ports that processes under [roots], or the roots themselves,
  /// listen on — the dev server an AI agent started, which no session shell
  /// owns. A2's attribution ([ownerOf]) with the roots standing in for
  /// shells. One entry per port, sorted.
  List<RootedPort> under(Set<int> roots) {
    if (roots.isEmpty) return const [];
    final parents = {for (final e in table.entries) e.key: e.value.parent};
    final rootOf = {for (final r in roots) r: r};
    final byPort = <int, RootedPort>{};
    for (final MapEntry(key: pid, value: open) in listening.entries) {
      final root = ownerOf(pid, parents, rootOf);
      if (root == null) continue;
      final name = table[pid]?.name ?? '';
      for (final port in open) {
        byPort.putIfAbsent(port, () => (port: port, root: root, name: name));
      }
    }
    return [for (final port in byPort.keys.toList()..sort()) byPort[port]!];
  }

  @override
  String toString() => 'ListeningScan(${listening.length})';
}

/// Where listening ports and the process tree come from.
abstract interface class PortProbe {
  /// Listening TCP ports by pid. Throws [PortProbeException].
````

In `packages/shellx_agent/lib/src/context/listening_ports.dart`, replace:

````dart
}

/// macOS: `lsof` and `ps` (C3).
final class MacPortProbe implements PortProbe {
  MacPortProbe({TimedCommandRunner run = runWithTimeout}) : _run = run;
  final TimedCommandRunner _run;
  static const timeout = Duration(seconds: 2);
````

with:

````dart
}

/// macOS: `lsof` and `ps` (C3).
final class MacPortProbe implements PortProbe, ProcessTableProbe {
  MacPortProbe({TimedCommandRunner run = runWithTimeout}) : _run = run;
  final TimedCommandRunner _run;
  static const timeout = Duration(seconds: 2);
````

In `packages/shellx_agent/lib/src/context/listening_ports.dart`, replace:

````dart
    }
    return parseParentTable(out.stdout);
  }
}

/// Windows: `netstat -ano` for ports (fast), CIM through PowerShell for
````

with:

````dart
    }
    return parseParentTable(out.stdout);
  }

  @override
  Future<Map<int, ProgramRow>> processTable() async {
    final out = await _run('/bin/ps', const [
      '-axo',
      'pid=,ppid=,comm=',
    ], timeout: timeout);
    if (out.exitCode != 0) {
      throw PortProbeException('ps exited with code ${out.exitCode}');
    }
    return parseProcessTable(out.stdout);
  }
}

/// Windows: `netstat -ano` for ports (fast), CIM through PowerShell for
````

In `packages/shellx_agent/lib/src/context/listening_ports.dart`, replace:

````dart
/// `wmic`: Windows 11 24H2 removed it (D7). Both run by absolute path
/// under `%SystemRoot%\System32`, so a `netstat.exe` or `powershell.exe`
/// earlier on `PATH` (or in the working directory) is never picked up.
final class WindowsPortProbe implements PortProbe {
  WindowsPortProbe({
    TimedCommandRunner run = runWithTimeout,
    Map<String, String>? environment,
````

with:

````dart
/// `wmic`: Windows 11 24H2 removed it (D7). Both run by absolute path
/// under `%SystemRoot%\System32`, so a `netstat.exe` or `powershell.exe`
/// earlier on `PATH` (or in the working directory) is never picked up.
final class WindowsPortProbe implements PortProbe, ProcessTableProbe {
  WindowsPortProbe({
    TimedCommandRunner run = runWithTimeout,
    Map<String, String>? environment,
````

In `packages/shellx_agent/lib/src/context/listening_ports.dart`, replace:

````dart
      throw PortProbeException('powershell exited with code ${out.exitCode}');
    }
    return parseParentTable(out.stdout);
  }
}

````

with:

````dart
      throw PortProbeException('powershell exited with code ${out.exitCode}');
    }
    return parseParentTable(out.stdout);
  }

  @override
  Future<Map<int, ProgramRow>> processTable() async {
    final out = await _run(_powerShell, const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name"
          r" | ForEach-Object { '{0} {1} {2}' -f $_.ProcessId, "
          r"$_.ParentProcessId, $_.Name }",
    ], timeout: cimTimeout);
    if (out.exitCode != 0) {
      throw PortProbeException('powershell exited with code ${out.exitCode}');
    }
    return parseProcessTable(out.stdout);
  }
}

````

- [ ] **Step 4: Record the agents' pids in the desktop**

In `apps/desktop/lib/src/ai/ai_runtimes.dart`, replace:

````dart
    required this.cwd,
    this.resumeSessionId,
    this.preferredConfig = const {},
  });

  final AgentSpec agent;
````

with:

````dart
    required this.cwd,
    this.resumeSessionId,
    this.preferredConfig = const {},
    this.paneId,
  });

  final AgentSpec agent;
````

In `apps/desktop/lib/src/ai/ai_runtimes.dart`, replace:

````dart

  /// D11: the remembered choices (never "Bypass permissions", R6).
  final Map<String, Object> preferredConfig;

  @override
  String toString() => '…';
````

with:

````dart

  /// D11: the remembered choices (never "Bypass permissions", R6).
  final Map<String, Object> preferredConfig;

  /// V2-3 D12: the AI pane the runtime is for (its agent's pid is kept in
  /// [aiAgentPidsProvider]); null: not kept.
  final int? paneId;

  @override
  String toString() => '…';
````

In `apps/desktop/lib/src/ai/ai_runtimes.dart`, replace:

````dart
      (state) => state.label,
);

/// Makes one AI pane's runtime. Tests swap it for runtimes over
/// `FakeLauncher` (`test/support/ai_fakes.dart`): no process, no login
/// shell, no git.
final aiRuntimeFactoryProvider =
    Provider<AiRuntime Function(AiRuntimeRequest request)>(
      (ref) =>
          (r) => ref
              .read(aiHostProvider)
              .runtime(
                agent: r.agent,
                cwd: r.cwd,
                resumeSessionId: r.resumeSessionId,
                preferredConfig: r.preferredConfig,
              ),
    );

/// The runtime of every AI pane: made on first use, stopped when its pane
/// goes, all stopped on quit. It also carries each runtime's news into the
````

with:

````dart
      (state) => state.label,
);

/// V2-3 D12: the pid of each AI pane's running agent — the root of the
/// "servers this agent started" scan. Kept by the default runtime factory;
/// runtimes over fakes leave it empty. Never logged.
final class AiAgentPids {
  final _byPane = <int, int>{};

  int? of(int paneId) => _byPane[paneId];

  void set(int paneId, int pid) => _byPane[paneId] = pid;

  /// Only the agent it recorded: a newer agent of the pane stays.
  void clear(int paneId, int pid) {
    if (_byPane[paneId] == pid) _byPane.remove(paneId);
  }

  @override
  String toString() => 'AiAgentPids(${_byPane.length})';
}

final aiAgentPidsProvider = Provider<AiAgentPids>((ref) => AiAgentPids());

/// V2-3 D12: [inner], and the pid of each agent it starts kept for [paneId]
/// until that agent exits. [pidOf] reads a channel's pid (an [AgentProcess]
/// has one).
AgentLauncher recordingAgentPids(
  AgentLauncher inner,
  AiAgentPids pids,
  int paneId, {
  int? Function(AgentChannel channel) pidOf = _pidOf,
}) => (command, {required cwd}) async {
  final channel = await inner(command, cwd: cwd);
  final pid = pidOf(channel);
  if (pid != null) {
    pids.set(paneId, pid);
    unawaited(
      channel.exitCode.then(
        (_) => pids.clear(paneId, pid),
        onError: (Object _) => pids.clear(paneId, pid),
      ),
    );
  }
  return channel;
};

int? _pidOf(AgentChannel channel) =>
    channel is AgentProcess ? channel.pid : null;

/// Makes one AI pane's runtime. Tests swap it for runtimes over
/// `FakeLauncher` (`test/support/ai_fakes.dart`): no process, no login
/// shell, no git.
///
/// With a pane, it is `AiHost.runtime` (V2-1a) with one change: the agent's
/// pid is kept for V2-3 D12 ([recordingAgentPids]). Keep the two in step.
final aiRuntimeFactoryProvider =
    Provider<AiRuntime Function(AiRuntimeRequest request)>((ref) {
      return (r) {
        final host = ref.read(aiHostProvider);
        final paneId = r.paneId;
        if (paneId == null) {
          return host.runtime(
            agent: r.agent,
            cwd: r.cwd,
            resumeSessionId: r.resumeSessionId,
            preferredConfig: r.preferredConfig,
          );
        }
        return AiRuntime(
          state: AiSessionState(
            agentId: r.agent.id,
            agentName: r.agent.name,
            cwd: r.cwd,
          ),
          resolve: () async =>
              host.resolver.resolve(r.agent, await host.env.resolve()),
          launch: recordingAgentPids(
            host.launch,
            ref.read(aiAgentPidsProvider),
            paneId,
          ),
          clientVersion: host.clientVersion,
          checkpoints: () async =>
              host.checkpoints.forProject(r.cwd, await host.env.resolve()),
          resumeSessionId: r.resumeSessionId,
          preferredConfig: r.preferredConfig,
        );
      };
    });

/// The runtime of every AI pane: made on first use, stopped when its pane
/// goes, all stopped on quit. It also carries each runtime's news into the
````

In `apps/desktop/lib/src/ai/ai_runtimes.dart`, replace:

````dart
          ref.read(settingsStoreProvider),
          agent.id,
        ),
      ),
    );
    _runtimes[paneId] = runtime;
````

with:

````dart
          ref.read(settingsStoreProvider),
          agent.id,
        ),
        paneId: paneId,
      ),
    );
    _runtimes[paneId] = runtime;
````

- [ ] **Step 5: Implement the suggestions**

`apps/desktop/lib/src/tools/tool_ports.dart`:

````dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart'
    show
        ListeningScan,
        MacPortProbe,
        PortProbe,
        ProcessTableProbe,
        RootedPort,
        WindowsPortProbe;

import '../ai/ai_runtimes.dart' show AiAgentPids, aiAgentPidsProvider;
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'tool_registry.dart';

/// D12: at most this many suggestions.
const int kMaxToolSuggestions = 8;

/// D12: `localhost:<port> · <process>`.
@immutable
final class ToolPortSuggestion {
  const ToolPortSuggestion({required this.port, this.process = ''});
  final int port;

  /// The listening program's name; '' while unknown.
  final String process;

  String get url => 'http://localhost:$port/';

  @override
  bool operator ==(Object other) =>
      other is ToolPortSuggestion &&
      other.port == port &&
      other.process == process;

  @override
  int get hashCode => Object.hash(port, process);

  @override
  String toString() => 'ToolPortSuggestion(…)';
}

/// D12: the ports [panePorts] of the workspace's terminal panes and the
/// [agentPorts] its AI agents' processes listen on, named by [nameOf], less
/// the ports its tools already use, by port, at most [kMaxToolSuggestions].
List<ToolPortSuggestion> toolPortSuggestions({
  required Set<int> panePorts,
  List<RootedPort> agentPorts = const [],
  String Function(int port)? nameOf,
  required Set<int> usedPorts,
}) {
  final named = <int, String>{
    for (final p in panePorts) p: nameOf?.call(p) ?? '',
    for (final p in agentPorts) p.port: p.name,
  };
  final ports = named.keys.where((p) => !usedPorts.contains(p)).toList()
    ..sort();
  return [
    for (final p in ports.take(kMaxToolSuggestions))
      ToolPortSuggestion(port: p, process: named[p]!),
  ];
}

/// D12 (1): the ports the terminal panes of workspace [ws] listen on — an
/// AI tab's terminal pane too, never an SSH pane's (those are the
/// server's, §12).
Set<int> workspacePanePorts(
  TerminalTabsState tabs,
  SidebarState sidebar,
  String ws,
) {
  final ids = sidebar.tabsOf(ws).toSet();
  return {
    for (final tab in tabs.tabs)
      if (ids.contains(tab.id))
        for (final pane in tab.panes.values)
          if (pane.remote == null && !pane.exited) ...pane.ports,
  };
}

/// D12 (2): the pids of the running agents of [ws]'s AI tabs.
Set<int> workspaceAgentPids(
  TerminalTabsState tabs,
  SidebarState sidebar,
  String ws,
  AiAgentPids pids,
) {
  final ids = sidebar.tabsOf(ws).toSet();
  return {
    for (final tab in tabs.tabs)
      if (ids.contains(tab.id))
        for (final pane in tab.aiPanes.keys) ?pids.of(pane),
  };
}

/// The probes of the on-demand scan; tests make them fakes.
final toolPortProbeProvider =
    Provider<({PortProbe ports, ProcessTableProbe table})>((ref) {
      if (Platform.isWindows) {
        final probe = WindowsPortProbe();
        return (ports: probe, table: probe);
      }
      final probe = MacPortProbe();
      return (ports: probe, table: probe);
    });

/// D12: what "Add tool" suggests for workspace [ws] — read once, when the
/// dialog opens (`autoDispose`: a new dialog scans again), in the window,
/// where the agents run, with or without the background service.
final toolPortSuggestionsProvider = FutureProvider.autoDispose
    .family<List<ToolPortSuggestion>, String>((ref, ws) async {
      final tabs = ref.read(terminalTabsProvider);
      final sidebar = ref.read(sidebarWorkspacesProvider);
      final panePorts = workspacePanePorts(tabs, sidebar, ws);
      final roots = workspaceAgentPids(
        tabs,
        sidebar,
        ws,
        ref.read(aiAgentPidsProvider),
      );
      final used = {
        for (final t in ref.read(toolRegistryProvider.notifier).inWorkspace(ws))
          if (t.isLocal) t.port,
      };
      var scan = ListeningScan.empty;
      if (panePorts.isNotEmpty || roots.isNotEmpty) {
        final probe = ref.read(toolPortProbeProvider);
        try {
          scan = await ListeningScan.read(probe.ports, probe.table);
        } on Object catch (error) {
          // The panes' own ports still show, without names.
          debugPrint('tool suggestions: scan failed (${error.runtimeType})');
        }
      }
      return toolPortSuggestions(
        panePorts: panePorts,
        agentPorts: scan.under(roots),
        nameOf: scan.nameOf,
        usedPorts: used,
      );
    });
````

- [ ] **Step 6: Run the tests**

````bash
cd packages/shellx_agent
~/fvm/versions/3.41.4/bin/dart format lib/src/context/listening_ports.dart test/context/listening_under_test.dart
~/fvm/versions/3.41.4/bin/dart analyze
~/fvm/versions/3.41.4/bin/dart test 2>&1 | tail -1
cd ../../apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/ai/ai_runtimes.dart lib/src/tools/tool_ports.dart test/tools/tool_ports_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_ports_test.dart test/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `shellx_agent`: `No issues found!`; `listening_under_test.dart` +5; the package `921 passed` (916 before).
- Desktop: `tool_ports_test.dart` +6 and every `test/ai` test (the runtime factory with and without a pane) pass; `No issues found!`; the whole suite `3761 passed, 9 skipped`.

- [ ] **Step 7: Commit**

````bash
git add packages/shellx_agent/lib/src/context/listening_ports.dart packages/shellx_agent/test/context/listening_under_test.dart \
  apps/desktop/lib/src/ai/ai_runtimes.dart apps/desktop/lib/src/tools/tool_ports.dart apps/desktop/test/tools/tool_ports_test.dart
git commit -m "feat(v2-tools): port suggestions from the workspace's terminals and from servers its AI agents started

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 12: The Add/Edit dialog, JS dialogs and the tool commands

**The Add/Edit dialog (§4.2).** `ToolDialog` is shared by add and edit (D23). Its parts:
- **Fields:** Name ("Bảng việc" as hint) and URL (`http://localhost:4000` as hint).
- **Suggestions:** "Cổng đang chạy mà ShellX thấy:" with buttons `localhost:<port> · <process>`, from Task 11's provider, or the hint when there is none (D12).
  - A pick fills the URL.
  - When the name is still empty, it also fills the name: the project folder's name, else the process name.
- **Phone flag:** "Cho mở trên điện thoại" with its note. It is off for a URL a phone may not open, with D15's reason.
- **Checking:** a bad URL says why in a red line under the field after Add (Review Focus 5, ruling R1).
- **Limit:** a full project (50 tools) says so ("Dự án này đã có 50 tool.") and Add is off.
- **Result:** the dialog only returns a `ToolDraft`. What Add does with it is the caller's.

**JS dialogs.** `showToolJsDialog` shows a page's `alert`/`confirm`/`prompt` titled "{name} nhắn", so a page cannot pass for ShellX (spec §7).

**`ToolActions`.** The window's tool commands, for the sidebar, the palette, the AI header, the dock bar and Settings:
- **open (D4, D20):** show the tool's workspace (its last tab, else its first, else "loose", ruling R14) and open its dock on the tool. With embedding off, open the system browser instead.
- **toggle (⌘⇧B, D10, D20):**
  - an open dock closes;
  - a closed dock reopens on the tool viewed last;
  - a workspace with no tool asks for one;
  - not embedded: it asks only when the workspace has no tool.
- **add, edit, delete:** delete asks first, with D23's question.
- **outside:** "Open in browser"; `mailto:`/`tel:` go to the system through `UrlOpener.openMailOrPhone`, which accepts only those two schemes.
- **also:** the phone flag, and Copy URL (ruling R18).

**Test support.** `test/support/tool_harness.dart` (`ToolRig`) pumps the real workspace page with fake engines (one per tool, kept by id), a fake port probe and process table, a fake data store, no knock, and counter ids. Tasks 13–15 use it.

**Files:**
- Create: `apps/desktop/lib/src/ui/tools/tool_dialogs.dart`, `apps/desktop/lib/src/ui/tools/tool_actions.dart`
- Modify: `apps/desktop/lib/src/platform/url_opener.dart` (`openMailOrPhone`), `apps/desktop/test/support/fakes.dart` (`RecordingUrlOpener.mailOrPhone`)
- Create: `apps/desktop/test/support/tool_harness.dart`
- Test: `apps/desktop/test/ui/tools/tool_dialog_test.dart`, `apps/desktop/test/platform/url_opener_mail_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `ToolEntry`, `parseToolUrl`, `ToolUrlError`, `toolRegistryProvider`, `kMaxToolsPerWorkspace`;
  - Task 3: `BrowserJsDialog`, `BrowserJsDialogKind`;
  - Task 7: `toolsEmbeddedProvider`, `toolPlatformProvider`;
  - Task 8: `toolDockProvider`, `ToolDocks`, `ToolDockController`;
  - Task 10: `toolEngineFactoryProvider`, `toolKnockProvider`, `toolDataStoreProvider`;
  - Task 11: `toolPortSuggestionsProvider`, `toolPortProbeProvider`, `ToolPortSuggestion`, `ProgramRow`, `PortProbe`, `ProcessTableProbe`;
  - existing: `desktopServicesProvider` (`urlOpener`), `windowRouterProvider` (`confirm(ConfirmRequest)`), `appL10nProvider`, `terminalTabsProvider`, `sidebarWorkspacesProvider` (`workspace(id)?.root`, `reveal`), `LinkOpenFailedNotice`, `pumpConfiguredWorkspace` and `TestHarness` (`test/support/…`).
- Produces, `lib/src/ui/tools/tool_dialogs.dart`:
  - `final class ToolDraft({required String name, required String url, required bool phone})` (`toString()` → `ToolDraft(…)`);
  - `Future<ToolDraft?> showToolDialog(BuildContext context, {required String ws, ToolEntry? existing})`;
  - `String toolUrlErrorText(AppLocalizations l10n, ToolUrlError error)`;
  - `class ToolDialog extends ConsumerStatefulWidget`, built with `ToolDialog({Key? key, required String ws, ToolEntry? existing})`;
  - `String toolDeleteQuestion(AppLocalizations l10n, ToolEntry tool)`;
  - `Future<Object?> showToolJsDialog(BuildContext context, String toolName, BrowserJsDialog dialog)`.
  - Keys:
    - the dialog: `tool.dialog`, `tool.dialog.name`, `tool.dialog.url`, `tool.dialog.phone`, `tool.dialog.save`, `tool.dialog.cancel`, `tool.dialog.full`;
    - suggestions: `tool.suggestion.<port>`, `tool.suggestions.none`;
    - JS dialogs: `tool.js`, `tool.js.text`, `tool.js.ok`, `tool.js.cancel`.
- Produces, `lib/src/ui/tools/tool_actions.dart`:
  - `String dockWorkspaceOf(ToolDocks docks, TerminalTabsState tabs, SidebarState sidebar)`;
  - `enum ToolToggle { opened, closed, asked, nothing }`;
  - `final class ToolActions`, built with `const ToolActions(WidgetRef ref)`:
    - `String currentWorkspace()`;
    - `Future<bool> open(String toolId)`, `Future<ToolToggle> toggle(BuildContext context)`;
    - `Future<ToolEntry?> add(BuildContext context, String ws)`, `Future<void> edit(BuildContext context, ToolEntry tool)`, `Future<void> delete(ToolEntry tool)`;
    - `Future<void> openInBrowser(ToolEntry tool, {Uri? url})`, `Future<void> openOutside(Uri url)`;
    - `void togglePhone(ToolEntry tool)`, `Future<void> copyUrl(ToolEntry tool)`.
- Produces, `lib/src/platform/url_opener.dart`: `Future<void> UrlOpener.openMailOrPhone(Uri uri)`. It throws `ArgumentError` for any other scheme, a control character or more than 2 048 characters, without running a command. macOS runs `/usr/bin/open <uri>`; Windows runs `rundll32 url.dll,FileProtocolHandler <uri>`.
- Produces, `test/support/tool_harness.dart`:
  - `FakeToolProbe` (mutable `ports`, `table`, `scans`) and `FakeToolData` (`clears`);
  - `ToolRig({bool coversFlutter = false, TargetPlatform platform = TargetPlatform.macOS})`:
    - fields: `engines` (by tool id), `dialogs`, `made`, `probe`, `data`, `harness`, `container`, `overrides`;
    - methods: `Future<void> pump(WidgetTester tester, {String config = ''})`, `ToolEntry add(String ws, String url, {String name = ''})`.

- [ ] **Step 1: Write the failing tests and the harness**

`apps/desktop/test/support/tool_harness.dart`:

````dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/tools/tool_embed.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/tools/tool_ports.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import 'config_workspace.dart';
import 'fake_browser_engine.dart';
import 'fakes.dart';

/// V2-3: scans that find [ports] (pid → ports) and [table].
final class FakeToolProbe implements PortProbe, ProcessTableProbe {
  /// What the scans find; tests fill them.
  final Map<int, Set<int>> ports = {};
  final Map<int, ProgramRow> table = {};
  int scans = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    scans++;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => const {};

  @override
  Future<Map<int, ProgramRow>> processTable() async => table;
}

final class FakeToolData implements BrowserDataStore {
  int clears = 0;
  @override
  Future<void> clearAll() async => clears++;
}

/// The workspace page with tools: every page's engine is a
/// [FakeBrowserEngine] in [engines] (by tool id; [made] counts them).
final class ToolRig {
  ToolRig({this.coversFlutter = false, this.platform = TargetPlatform.macOS});

  final bool coversFlutter;
  final TargetPlatform platform;
  final engines = <String, FakeBrowserEngine>{};
  final dialogs = <String, BrowserDialogPresenter>{};
  int made = 0;
  final probe = FakeToolProbe();
  final data = FakeToolData();
  final harness = TestHarness(settings: {'onboarding_done': true});
  var _next = 0;

  late ProviderContainer container;

  List<Override> get overrides => [
    toolEngineFactoryProvider.overrideWithValue((tool, presenter) {
      made++;
      dialogs[tool.id] = presenter;
      return engines[tool.id] = FakeBrowserEngine(
        key: tool.id,
        coversFlutter: coversFlutter,
      );
    }),
    toolKnockProvider.overrideWithValue((_, _) async => false),
    toolPortProbeProvider.overrideWithValue((ports: probe, table: probe)),
    toolDataStoreProvider.overrideWithValue(data),
    toolPlatformProvider.overrideWithValue(platform),
    toolIdSourceProvider.overrideWithValue(
      () => 'tool${(_next++).toString().padLeft(6, '0')}',
    ),
  ];

  Future<void> pump(WidgetTester tester, {String config = ''}) async {
    final r = await pumpConfiguredWorkspace(
      tester,
      config: config,
      harness: harness,
      extra: overrides,
    );
    container = r.container;
  }

  ToolEntry add(String ws, String url, {String name = ''}) => container
      .read(toolRegistryProvider.notifier)
      .add(ws: ws, name: name, url: url)!;
}
````

`apps/desktop/test/ui/tools/tool_dialog_test.dart`:

````dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/tools/tool_dialogs.dart';

import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  /// The dialog alone; what Add does with it is the window's (Task 13).
  Future<ToolDraft?> Function() openDialog(WidgetTester t) {
    ToolDraft? result;
    var done = false;
    unawaited(
      showToolDialog(
        t.element(find.byType(TerminalWorkspacePage)),
        ws: kDefaultWorkspaceId,
      ).then((r) {
        result = r;
        done = true;
      }),
    );
    return () async {
      await t.pumpAndSettle();
      expect(done, isTrue);
      return result;
    };
  }

  Future<void> shown(WidgetTester t) async {
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
  }

  testWidgets('suggestions: a terminal\'s port named by its program; a pick '
      'fills the URL and the name (D12)', (t) async {
    await rig.pump(t);
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    final session = rig.container.read(terminalTabsProvider).tabs.single.id;
    local.replace(local.summary(session, ports: [5173]));
    rig.probe.ports[100] = {5173};
    rig.probe.table[100] = (parent: 1, name: 'node');
    await t.pumpAndSettle();
    final closed = openDialog(t);
    await shown(t);
    expect(find.text('localhost:5173 · node'), findsOneWidget);
    await t.tap(find.byKey(const Key('tool.suggestion.5173')));
    await t.pump();
    expect(find.text('http://localhost:5173/'), findsOneWidget);
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    final draft = (await closed())!;
    expect(
      [draft.name, draft.url, draft.phone],
      ['node', 'http://localhost:5173/', false],
    );
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('no port yet: the hint (D12)', (t) async {
    await rig.pump(t);
    openDialog(t);
    await shown(t);
    expect(find.byKey(const Key('tool.suggestions.none')), findsOneWidget);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('a bad URL says why after Add, and adds nothing (§4.2)', (
    t,
  ) async {
    await rig.pump(t);
    final closed = openDialog(t);
    await shown(t);
    await t.enterText(
      find.byKey(const Key('tool.dialog.url')),
      'javascript:alert(1)',
    );
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pump();
    expect(
      find.text('The URL must start with http:// or https://'),
      findsOneWidget,
    );
    await t.enterText(
      find.byKey(const Key('tool.dialog.url')),
      'http://me:pw@localhost:1',
    );
    await t.pump();
    expect(
      find.text("The URL can't contain a user name or password"),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('tool.dialog.cancel')));
    expect(await closed(), isNull);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('"Allow on phone" is off for a tool that is not local http '
      '(D15)', (t) async {
    await rig.pump(t);
    final closed = openDialog(t);
    await shown(t);
    await t.enterText(find.byKey(const Key('tool.dialog.url')), 'nas.lan:80');
    await t.pump();
    final box = t.widget<CheckboxListTile>(
      find.byKey(const Key('tool.dialog.phone')),
    );
    expect(box.onChanged, isNull);
    expect(
      find.text('Only http tools on this computer can open on a phone.'),
      findsOneWidget,
    );
    await t.enterText(
      find.byKey(const Key('tool.dialog.url')),
      'localhost:3000',
    );
    await t.pump();
    await t.tap(find.byKey(const Key('tool.dialog.phone')));
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    expect((await closed())!.phone, isTrue);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('a full project says so; Add is off (D2)', (t) async {
    await rig.pump(t);
    for (var i = 1; i <= kMaxToolsPerWorkspace; i++) {
      rig.add(kDefaultWorkspaceId, 'localhost:$i');
    }
    await t.pumpAndSettle();
    openDialog(t);
    await shown(t);
    expect(find.byKey(const Key('tool.dialog.full')), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('tool.dialog.save')))
          .onPressed,
      isNull,
    );
    await disposeWorkspace(t, rig.container);
  });
}
````

`apps/desktop/test/platform/url_opener_mail_test.dart`:

````dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

void main() {
  late List<String> ran;
  Future<ProcessResult> run(String exe, List<String> args) async {
    ran.add(jsonEncode([exe, ...args]));
    return ProcessResult(0, 0, '', '');
  }

  setUp(() => ran = []);

  test('mailto: and tel: go to the system (V2-3 D9)', () async {
    await SystemUrlOpener(
      isWindows: false,
      run: run,
    ).openMailOrPhone(Uri.parse('mailto:a@b.c?subject=hi'));
    await SystemUrlOpener(
      isWindows: true,
      run: run,
    ).openMailOrPhone(Uri.parse('tel:+84123'));
    expect(ran, [
      '["/usr/bin/open","mailto:a@b.c?subject=hi"]',
      '["rundll32","url.dll,FileProtocolHandler","tel:+84123"]',
    ]);
  });

  test('nothing else ever reaches a command', () async {
    final opener = SystemUrlOpener(isWindows: false, run: run);
    for (final bad in [
      'https://example.com',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'sms:123',
      'facetime:x',
    ]) {
      await expectLater(
        opener.openMailOrPhone(Uri.parse(bad)),
        throwsArgumentError,
        reason: bad,
      );
    }
    expect(ran, isEmpty);
  });
}
````

In `apps/desktop/test/support/fakes.dart`, replace:

````dart
    webLinks.add(uri);
  }

  /// A10: paths shown in Finder / Explorer (path, isDirectory).
  final List<(String, bool)> revealed = [];

````

with:

````dart
    webLinks.add(uri);
  }

  /// V2-3 D9: mailto: and tel: links handed to the system.
  final List<Uri> mailOrPhone = [];

  @override
  Future<void> openMailOrPhone(Uri uri) async {
    if (fail) throw const ProcessException('/usr/bin/open', [], 'failed');
    mailOrPhone.add(uri);
  }

  /// A10: paths shown in Finder / Explorer (path, isDirectory).
  final List<(String, bool)> revealed = [];

````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools/tool_dialog_test.dart test/platform/url_opener_mail_test.dart
````

Expected: compilation fails, `Error when reading 'lib/src/ui/tools/tool_dialogs.dart'` and `The method 'openMailOrPhone' isn't defined`.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/platform/url_opener.dart`, replace:

````dart
  /// command. [open] stays https-only: it is for links the app itself
  /// builds.
  Future<void> openWebLink(Uri uri);

  /// A10 D7: shows [path] (absolute) selected in Finder / Explorer — a
  /// folder too, so a `.app` bundle is never launched. Never runs the file. Throws [ArgumentError] for a path that is
````

with:

````dart
  /// command. [open] stays https-only: it is for links the app itself
  /// builds.
  Future<void> openWebLink(Uri uri);

  /// V2-3 D9: a tool page's `mailto:` or `tel:` link, handed to the
  /// system's mail or phone app. Throws [ArgumentError] for any other
  /// scheme, or a link with a control character, without running a
  /// command.
  Future<void> openMailOrPhone(Uri uri);

  /// A10 D7: shows [path] (absolute) selected in Finder / Explorer — a
  /// folder too, so a `.app` bundle is never launched. Never runs the file. Throws [ArgumentError] for a path that is
````

In `apps/desktop/lib/src/platform/url_opener.dart`, replace:

````dart
  }

  @override
  Future<void> reveal(String path, {required bool isDirectory}) async {
    final absolute = _isWindows
        ? RegExp(r'^[A-Za-z]:\\').hasMatch(path)
````

with:

````dart
  }

  @override
  Future<void> openMailOrPhone(Uri uri) async {
    final text = uri.toString();
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'mailto' && scheme != 'tel') ||
        text.length > 2048 ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(text)) {
      throw ArgumentError.value(scheme, 'uri', 'Only mailto: and tel: open');
    }
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', text]);
    } else {
      await _run('/usr/bin/open', [text]);
    }
  }

  @override
  Future<void> reveal(String path, {required bool isDirectory}) async {
    final absolute = _isWindows
        ? RegExp(r'^[A-Za-z]:\\').hasMatch(path)
````

`apps/desktop/lib/src/ui/tools/tool_dialogs.dart`:

````dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../browser/browser_engine.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_ports.dart';
import '../../tools/tool_registry.dart';
import '../theme/shellx_desktop_theme.dart';

/// What the tool dialog gives back (§4.2).
final class ToolDraft {
  const ToolDraft({required this.name, required this.url, required this.phone});
  final String name;
  final String url;
  final bool phone;

  @override
  String toString() => 'ToolDraft(…)';
}

/// §4.2: "Add tool" for workspace [ws], or "Edit tool" for [existing].
/// Null when cancelled.
Future<ToolDraft?> showToolDialog(
  BuildContext context, {
  required String ws,
  ToolEntry? existing,
}) => showDialog<ToolDraft>(
  context: context,
  builder: (_) => ToolDialog(ws: ws, existing: existing),
);

/// D1 errors, in the dialog's words.
String toolUrlErrorText(AppLocalizations l10n, ToolUrlError error) =>
    switch (error) {
      ToolUrlError.notHttp => l10n.toolUrlNotHttp,
      ToolUrlError.userinfo => l10n.toolUrlUserinfo,
      ToolUrlError.backslash => l10n.toolUrlBackslash,
      ToolUrlError.noHost => l10n.toolUrlNoHost,
      ToolUrlError.badPort => l10n.toolUrlBadPort,
      ToolUrlError.tooLong => l10n.toolUrlTooLong,
    };

class ToolDialog extends ConsumerStatefulWidget {
  const ToolDialog({super.key, required this.ws, this.existing});
  final String ws;
  final ToolEntry? existing;

  @override
  ConsumerState<ToolDialog> createState() => _ToolDialogState();
}

class _ToolDialogState extends ConsumerState<ToolDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late bool _phone = widget.existing?.phone ?? false;

  /// The URL error shows once Add was pressed, then follows the typing.
  bool _checked = false;

  bool get _adding => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _url.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  ToolUrlResult get _parsed => parseToolUrl(_url.text);

  /// D15: only an http tool on this computer may open on a phone.
  bool get _phoneAllowed => switch (_parsed) {
    ToolUrlOk(:final url) => ToolEntry(
      id: '',
      ws: '',
      name: '',
      url: url,
    ).phoneAllowed,
    ToolUrlBad() => false,
  };

  bool get _full =>
      _adding &&
      ref.read(toolRegistryProvider.notifier).inWorkspace(widget.ws).length >=
          kMaxToolsPerWorkspace;

  void _pick(ToolPortSuggestion s) {
    _url.text = s.url;
    if (_name.text.trim().isEmpty) {
      final root = ref
          .read(sidebarWorkspacesProvider)
          .workspace(widget.ws)
          ?.root;
      final folder = root == null ? '' : p.basename(root);
      _name.text = folder.isNotEmpty ? folder : s.process;
    }
  }

  void _save() {
    setState(() => _checked = true);
    if (_full || _parsed is! ToolUrlOk) return;
    Navigator.of(context).pop(
      ToolDraft(
        name: _name.text,
        url: _url.text,
        phone: _phone && _phoneAllowed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parsed = _parsed;
    final error = _checked && parsed is ToolUrlBad
        ? toolUrlErrorText(l10n, parsed.error)
        : null;
    return AlertDialog(
      key: const Key('tool.dialog'),
      title: Text(_adding ? l10n.toolDialogAddTitle : l10n.toolDialogEditTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('tool.dialog.name'),
              controller: _name,
              autofocus: true,
              maxLength: kMaxToolNameLength,
              decoration: InputDecoration(
                labelText: l10n.toolDialogName,
                hintText: l10n.toolDialogNameHint,
                counterText: '',
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: ShellxSpace.s12),
            TextField(
              key: const Key('tool.dialog.url'),
              controller: _url,
              decoration: InputDecoration(
                labelText: l10n.toolDialogUrl,
                hintText: l10n.toolDialogUrlHint,
                errorText: error,
                errorMaxLines: 2,
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_adding) ...[
              const SizedBox(height: ShellxSpace.s12),
              _Suggestions(ws: widget.ws, onPick: _pick),
            ],
            const SizedBox(height: ShellxSpace.s8),
            Tooltip(
              message: _phoneAllowed ? '' : l10n.toolPhoneOnlyLocal,
              child: CheckboxListTile(
                key: const Key('tool.dialog.phone'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _phone && _phoneAllowed,
                onChanged: _phoneAllowed
                    ? (on) => setState(() => _phone = on ?? false)
                    : null,
                title: Text(l10n.toolDialogPhone),
                subtitle: Text(
                  _phoneAllowed
                      ? l10n.toolDialogPhoneNote
                      : l10n.toolPhoneOnlyLocal,
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_full)
              Text(
                l10n.toolLimitReached(kMaxToolsPerWorkspace),
                key: const Key('tool.dialog.full'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('tool.dialog.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const Key('tool.dialog.save'),
          onPressed: _full ? null : _save,
          child: Text(_adding ? l10n.toolDialogAdd : l10n.toolDialogSave),
        ),
      ],
    );
  }
}

/// D12: "Running ports ShellX can see:" — the panes' ports at once, the
/// agents' servers and the names when the scan is back (≤ 2 s).
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.ws, required this.onPick});
  final String ws;
  final void Function(ToolPortSuggestion suggestion) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scanned = ref.watch(toolPortSuggestionsProvider(ws));
    final list =
        scanned.value ??
        toolPortSuggestions(
          panePorts: workspacePanePorts(
            ref.read(terminalTabsProvider),
            ref.read(sidebarWorkspacesProvider),
            ws,
          ),
          usedPorts: const {},
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.toolSuggestionsTitle,
          style: ShellxText.small.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
        const SizedBox(height: ShellxSpace.s6),
        if (list.isEmpty && !scanned.isLoading)
          Text(
            l10n.toolSuggestionsNone,
            key: const Key('tool.suggestions.none'),
            style: ShellxText.caption.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          )
        else
          Wrap(
            spacing: ShellxSpace.s6,
            runSpacing: ShellxSpace.s6,
            children: [
              for (final s in list)
                ActionChip(
                  key: Key('tool.suggestion.${s.port}'),
                  label: Text(
                    s.process.isEmpty
                        ? 'localhost:${s.port}'
                        : l10n.toolSuggestion(s.port, s.process),
                  ),
                  onPressed: () => onPick(s),
                ),
            ],
          ),
      ],
    );
  }
}

/// D23: "Delete the tool …?" through the window's confirm.
String toolDeleteQuestion(AppLocalizations l10n, ToolEntry tool) =>
    l10n.toolDeleteConfirm(tool.name);

/// D9: a page's alert / confirm / prompt, titled with the tool's name so a
/// page cannot pass for ShellX. The page's text is clipped, never logged.
Future<Object?> showToolJsDialog(
  BuildContext context,
  String toolName,
  BrowserJsDialog dialog,
) => showDialog<Object?>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ToolJsDialog(name: toolName, dialog: dialog),
);

class _ToolJsDialog extends StatefulWidget {
  const _ToolJsDialog({required this.name, required this.dialog});
  final String name;
  final BrowserJsDialog dialog;

  @override
  State<_ToolJsDialog> createState() => _ToolJsDialogState();
}

class _ToolJsDialogState extends State<_ToolJsDialog> {
  late final _text = TextEditingController(
    text: widget.dialog.defaultText ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = widget.dialog.kind;
    final message = widget.dialog.message;
    final shown = message.length > 2000
        ? '${message.substring(0, 2000)}…'
        : message;
    Object? cancel() => switch (kind) {
      BrowserJsDialogKind.alert => null,
      BrowserJsDialogKind.confirm => false,
      BrowserJsDialogKind.prompt => null,
    };
    Object? ok() => switch (kind) {
      BrowserJsDialogKind.alert => null,
      BrowserJsDialogKind.confirm => true,
      BrowserJsDialogKind.prompt => _text.text,
    };
    return AlertDialog(
      key: const Key('tool.js'),
      title: Text(l10n.toolJsAlertTitle(widget.name)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(child: SelectableText(shown)),
            ),
            if (kind == BrowserJsDialogKind.prompt) ...[
              const SizedBox(height: ShellxSpace.s12),
              TextField(
                key: const Key('tool.js.text'),
                controller: _text,
                autofocus: true,
                onSubmitted: (_) => Navigator.of(context).pop(ok()),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (kind != BrowserJsDialogKind.alert)
          TextButton(
            key: const Key('tool.js.cancel'),
            onPressed: () => Navigator.of(context).pop(cancel()),
            child: Text(l10n.actionCancel),
          ),
        FilledButton(
          key: const Key('tool.js.ok'),
          autofocus: kind != BrowserJsDialogKind.prompt,
          onPressed: () => Navigator.of(context).pop(ok()),
          child: Text(l10n.toolOk),
        ),
      ],
    );
  }
}
````

`apps/desktop/lib/src/ui/tools/tool_actions.dart`:

````dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/desktop_services.dart' show desktopServicesProvider;
import '../../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_embed.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_registry.dart';
import '../window_router.dart';
import 'tool_dialogs.dart';

/// D3, D4: the workspace whose dock the window shows — the one shown
/// without a tab ([ToolDocks.loose]), else the selected tab's, else the
/// current one.
String dockWorkspaceOf(
  ToolDocks docks,
  TerminalTabsState tabs,
  SidebarState sidebar,
) {
  final selected = tabs.selectedId;
  return docks.loose ??
      (selected == null ? null : sidebar.workspaceOf(selected)) ??
      sidebar.currentId;
}

/// What ⌘⇧B did (D10, D20).
enum ToolToggle { opened, closed, asked, nothing }

/// The window's tool commands (D4, D10, D15, D20–D23) for the sidebar, the
/// palette, the AI header and Settings. Opening, toggling and adding run
/// through the window's intents, which also move the keyboard.
final class ToolActions {
  const ToolActions(this.ref);
  final WidgetRef ref;

  ToolRegistry get _registry => ref.read(toolRegistryProvider.notifier);
  ToolDockController get _dock => ref.read(toolDockProvider.notifier);
  bool get _embedded => ref.read(toolsEmbeddedProvider);

  String currentWorkspace() => dockWorkspaceOf(
    ref.read(toolDockProvider),
    ref.read(terminalTabsProvider),
    ref.read(sidebarWorkspacesProvider),
  );

  /// D4, D20: [toolId]'s workspace shows (its last tab, else its first,
  /// else none — D4's empty content area) and its dock opens on the tool.
  /// Not embedded: the system browser. True when the dock shows it.
  Future<bool> open(String toolId) async {
    final tool = _registry.byId(toolId);
    if (tool == null) return false;
    if (!_embedded) {
      await openInBrowser(tool);
      return false;
    }
    _showWorkspace(tool.ws);
    _dock.open(tool.ws, tool.id);
    return true;
  }

  void _showWorkspace(String ws) {
    final tabs = ref.read(terminalTabsProvider);
    final sidebar = ref.read(sidebarWorkspacesProvider);
    final selected = tabs.selectedId;
    if (selected != null && sidebar.workspaceOf(selected) == ws) {
      if (ref.read(toolDockProvider).loose != null) _dock.clearLoose();
      return;
    }
    final tab = _dock.lastTabOf(ws) ?? sidebar.tabsOf(ws).firstOrNull;
    if (tab != null) {
      ref.read(sidebarWorkspacesProvider.notifier).reveal(tab);
      ref.read(terminalTabsProvider.notifier).select(tab);
      return;
    }
    _dock.showLoose(ws);
  }

  /// D10, D20: ⌘⇧B on the shown workspace.
  Future<ToolToggle> toggle(BuildContext context) async {
    final ws = currentWorkspace();
    final tools = _registry.inWorkspace(ws);
    if (!_embedded) {
      if (tools.isNotEmpty) return ToolToggle.nothing;
      final added = await add(context, ws);
      return added == null ? ToolToggle.nothing : ToolToggle.asked;
    }
    final dock = ref.read(toolDockProvider).of(ws);
    if (dock.open) {
      _dock.close(ws);
      return ToolToggle.closed;
    }
    if (_dock.reopen(ws)) return ToolToggle.opened;
    if (tools.isEmpty) {
      final added = await add(context, ws);
      if (added == null) return ToolToggle.nothing;
      return await open(added.id) ? ToolToggle.opened : ToolToggle.asked;
    }
    final last = _dock.lastViewedOf(ws);
    final tool = tools.where((t) => t.id == last).firstOrNull ?? tools.first;
    return await open(tool.id) ? ToolToggle.opened : ToolToggle.nothing;
  }

  /// §4.2: the dialog for a new tool of [ws]; the tool, or null.
  Future<ToolEntry?> add(BuildContext context, String ws) async {
    final draft = await showToolDialog(context, ws: ws);
    if (draft == null) return null;
    return _registry.add(
      ws: ws,
      name: draft.name,
      url: draft.url,
      phone: draft.phone,
    );
  }

  /// D23: name, URL and phone flag in the same dialog.
  Future<void> edit(BuildContext context, ToolEntry tool) async {
    final draft = await showToolDialog(context, ws: tool.ws, existing: tool);
    if (draft == null) return;
    _registry.update(
      tool.copyWith(name: draft.name, url: draft.url, phone: draft.phone),
    );
  }

  /// D23: asks first; the chip and the page go with the tool.
  Future<void> delete(ToolEntry tool) async {
    final l10n = ref.read(appL10nProvider);
    final yes = await ref
        .read(windowRouterProvider.notifier)
        .confirm(
          ConfirmRequest(
            title: toolDeleteQuestion(l10n, tool),
            body: '',
            confirmLabel: l10n.toolDeleteAction,
          ),
        );
    if (yes) _registry.remove(tool.id);
  }

  /// D17 ↗, D20, D21: the tool's URL (or [url], a page or a download it
  /// reached) in the system browser.
  Future<void> openInBrowser(ToolEntry tool, {Uri? url}) =>
      _outside(url ?? tool.uri);

  /// D9: a page's new window goes to the browser, `mailto:`/`tel:` to the
  /// system.
  Future<void> openOutside(Uri url) => _outside(url);

  Future<void> _outside(Uri url) async {
    final opener = ref.read(desktopServicesProvider).urlOpener;
    final scheme = url.scheme.toLowerCase();
    try {
      if (scheme == 'mailto' || scheme == 'tel') {
        await opener.openMailOrPhone(url);
      } else {
        await opener.openWebLink(url);
      }
    } on Object catch (error) {
      debugPrint('tool: not opened outside (${error.runtimeType})');
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(const LinkOpenFailedNotice());
    }
  }

  /// D15: on or off; only a tool a phone may open turns on.
  void togglePhone(ToolEntry tool) {
    if (!tool.phoneAllowed) return;
    _registry.update(tool.copyWith(phone: !tool.phone));
  }

  /// D17 ⋯ "Copy URL": the tool's own URL.
  Future<void> copyUrl(ToolEntry tool) =>
      Clipboard.setData(ClipboardData(text: tool.url));
}
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/ui/tools lib/src/platform/url_opener.dart test/support/tool_harness.dart test/support/fakes.dart test/ui/tools test/platform/url_opener_mail_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools test/platform
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_dialog_test.dart` +5, `url_opener_mail_test.dart` +2, and the other `test/platform` tests, all passed.
- `No issues found!`
- The whole suite: `3768 passed, 9 skipped`.

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/src/ui/tools/tool_dialogs.dart apps/desktop/lib/src/ui/tools/tool_actions.dart \
  apps/desktop/lib/src/platform/url_opener.dart apps/desktop/test/support/fakes.dart \
  apps/desktop/test/support/tool_harness.dart apps/desktop/test/ui/tools/tool_dialog_test.dart \
  apps/desktop/test/platform/url_opener_mail_test.dart
git commit -m "feat(v2-tools): the Add/Edit tool dialog with port suggestions, ShellX-framed JS dialogs, the tool commands

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 13: The dock in the window — bar, chips, page, keys, palette, AI header

The dock becomes the third column of `TerminalWorkspacePage._body()` (D3). Widget tree and keys:

- **`ToolArea`** (`lib/src/ui/tools/tool_area.dart`) replaces the bare `TerminalPane` in `_body(covered)`.
  - It is a `LayoutBuilder` → `Stack` of keyed slots placed by `toolDockLayout`:
    - `tool.panesSlot`: the panes, under `ExcludeFocus`/`ExcludeSemantics` while a zoomed dock or the loose panel covers them;
    - `tool.looseSlot`: the loose workspace's empty state (`Key('tool.loose')`, ruling R14);
    - `tool.handleSlot`: `ToolDockHandle` (`Key('tool.handle')`), whose drag sets the width;
    - `tool.dockSlot`: `ToolDockView` with `Key('tool.dock.<workspace id>')`.
  - The panes keep their width while zoomed, so no terminal is resized by a zoom.
- **`ToolDockView`** (`lib/src/ui/tools/tool_dock_view.dart`):
  - `Focus(focusNode: dockFocus)`. Esc on the bar leaves zoom (D3). The page has the keyboard exactly while this node is the primary focus (`focusContent`/`releaseFocus`, D10).
  - → `Semantics(label: toolDockLabel(name))` → `Column`, with three children:
    1. `_ToolChips`, only from 2 tools. Each chip is a selected-state button `tool.chip.<id>` with its × `tool.chip.<id>.close`.
    2. `ToolBar`.
    3. `Expanded(_ToolPageHost)`, keyed `tool.host.<id>`.
- **`_ToolPageHost`** (the same file):
  - It opens the page after the first frame (`ToolPages.open`), wires the page's callbacks to the window, and builds the engine's view once (`tool.view.<id>`).
  - Over the page it shows, when needed:
    - the D13 panel `tool.error.<kind>`, with `tool.error.reload` and/or `tool.error.browser`. Refused and crashed offer Reload only; ATS and "unavailable" offer the browser only; the others offer both.
    - the D9 download line `tool.download`, with `tool.download.browser` and `tool.download.close`;
    - for an engine that covers Flutter (Windows), the stand-in `tool.covered` ("{name} — tạm ẩn khi đang mở menu", D7) while anything is over the window. The engine is hidden meanwhile.
  - Its `dispose` uses no `ref`: the page itself is enough.
- **`ToolBar`** (`lib/src/ui/tools/tool_bar.dart`, 32 px, D17). From left to right:
  - 🧩 and `tool.bar.name`;
  - `tool.bar.mark`: `host:port` · "Trên máy này" / "Ngoài máy này" (+ " · không mã hoá" for http not on this computer);
  - when away: `tool.bar.away` ("Đang ở <host>") and `tool.bar.backToTool`;
  - `tool.bar.back` (off without history); `tool.bar.reload`, which is `tool.bar.stop` while loading;
  - `tool.bar.phone` (off with D15's reason as tooltip for a tool a phone may not open); `tool.bar.expand` (Mở rộng / Thu về); `tool.bar.browser`;
  - `tool.bar.more`, a menu with `tool.menu.edit`, `tool.menu.copy` and `tool.menu.closeDock`;
  - `tool.bar.close`.
- **The window** (`terminal_workspace_page.dart`):
  - **State:** `toolDockFocus` and `ToolActions`. `covered` is: the notification panel, an A9 overlay, a dialog, or a route above the page.
  - **D10 chords:** a chord the page hands back resolves through `resolveToolChord`. An intent runs; a sequence's first step arms `KeySequence` and releases the page's focus (ruling R8).
  - **D10 ⌘W:** with the dock focused, it closes the chip on show; the last chip closes the dock.
  - **D10 focus:** "focus right" from the rightmost pane enters the dock; "focus left" from the dock goes back.
  - **Actions:**
    - `ToggleToolsIntent`: opened → keyboard into the dock; closed → back to the panes;
    - `AddToolIntent`: adds, then opens (ruling R20, criterion 1);
    - `OpenToolIntent`: opens.
  - **Loose (D4, ruling R14):**
    - pane commands are off while loose;
    - ⌘T, "New AI session" and "New terminal tab" open in the loose workspace;
    - the empty-state button opens a tab there.
- **AI header** (`ai_header.dart`): `Key('ai.tools')` (🧩, label "Hiện hoặc ẩn vùng tool", on while the workspace's dock is open) invokes `ToggleToolsIntent`. `AiPaneView` closes its Changes/Files panel when the dock opens (D4); the user can open it again.
- **Palette** (`terminal_workspace_notices.dart`): "Mở tool: {name}" for every tool, the shown workspace's first, with the workspace name as subtitle while the sidebar shows several workspaces. Each runs `OpenToolIntent` (ruling R17). "Thêm tool…" comes from the keymap action (Task 4).

**Files:**
- Create: `apps/desktop/lib/src/ui/tools/tool_bar.dart`, `apps/desktop/lib/src/ui/tools/tool_dock_view.dart`, `apps/desktop/lib/src/ui/tools/tool_area.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/src/ui/ai/ai_header.dart`, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, `apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart`
- Test: `apps/desktop/test/ui/tools/tool_dock_ui_test.dart`, `apps/desktop/test/ui/tools/tool_ai_header_test.dart`

**Interfaces:**
- Consumes:
  - Task 4: the intents;
  - Task 5: `resolveToolChord`, `ToolChordIntent`, `ToolChordPrefix`, `KeySequence.arm`;
  - Task 7: `toolsEmbeddedProvider`;
  - Task 8: `toolDockProvider`, `toolDockLayout`, `toolDockFraction`, `kToolDockHandle`;
  - Task 10: `toolPagesProvider`, `ToolPage`, `ToolPageState`;
  - Task 12: `ToolActions`, `showToolJsDialog`, `ToolRig`;
  - existing: `TerminalPane`, `EmptyTerminalState`, `windowRouterProvider` (`dialogOpen`), `aiOpenerProvider` (`newTabIn`, `newSession(workspaceId:)`), `PaletteEntry`, `PaletteKind`.
- Produces:
  - `class ToolArea extends ConsumerWidget`, built with `ToolArea({Key? key, required Widget panes, required FocusNode dockFocus, required bool covered, required void Function(String chord) onChord, required VoidCallback onLeave, required Widget Function(String ws) loosePanel})`;
  - `class ToolDockView extends ConsumerStatefulWidget`, built with `ToolDockView({Key? key, required String workspaceId, required FocusNode focusNode, required bool covered, required void Function(String chord) onChord, required VoidCallback onLeave})`;
  - `class ToolDockHandle extends StatefulWidget`, built with `ToolDockHandle({Key? key, required double contentWidth, required double dockWidth, required double fraction, required ValueChanged<double> onFraction})`;
  - `const double kToolBarHeight = 32`, `const double kToolChipsHeight = 30`;
  - `class ToolBar extends StatelessWidget` (the D17 bar);
  - `TerminalWorkspacePageState.toolDockFocus`;
  - `AiHeader({…, VoidCallback? onTools, bool toolsOn = false})`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ui/tools/tool_dock_ui_test.dart`:

````dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';
import 'package:shellx_desktop/src/ui/tools/tool_area.dart';

import '../../support/config_workspace.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;

  setUp(() => rig = ToolRig());
  tearDown(() async {});

  /// What a sidebar row, the palette and Settings do (D4).
  Future<void> openTool(WidgetTester t, String id) async {
    Actions.invoke(t.element(find.byType(ToolArea)), OpenToolIntent(id));
    await t.pumpAndSettle();
  }

  testWidgets('opening a tool shows the dock beside the panes; the page '
      'loads its URL and gets the keyboard (D3, D4)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173', name: 'Board');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(find.byKey(const Key('tool.bar.name')), findsOneWidget);
    expect(find.text('localhost:5173 · On this computer'), findsOneWidget);
    final engine = rig.engines[tool.id]!;
    expect(engine.loads, [Uri.parse('http://localhost:5173/')]);
    expect(engine.calls, contains('focus'));
    final dock = t.getRect(find.byKey(const ValueKey('tool.dockSlot')));
    expect(dock.width, 396, reason: '45 % of the 879 px content area');
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Review Focus 1: switching tabs, opening the palette and '
      'resizing keep the same page — one engine, one view, one load', (
    t,
  ) async {
    await rig.pump(t);
    await rig.container.read(terminalTabsProvider.notifier).openTab();
    await t.pumpAndSettle();
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    final tabs = rig.container.read(terminalTabsProvider).tabs;
    rig.container.read(terminalTabsProvider.notifier).select(tabs.first.id);
    await t.pumpAndSettle();
    rig.container.read(terminalTabsProvider.notifier).select(tabs.last.id);
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    t.view.physicalSize = const Size(1300, 800);
    await t.pumpAndSettle();
    expect(rig.made, 1);
    expect(engine.builds, 1);
    expect(engine.loads, hasLength(1));
    expect(engine.calls, isNot(contains('reload')));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('chips from two tools; × on the last chip closes the dock '
      '(D5, D10)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'A');
    final b = rig.add(kDefaultWorkspaceId, 'localhost:2', name: 'B');
    await t.pumpAndSettle();
    await openTool(t, a.id);
    expect(find.byKey(Key('tool.chip.${a.id}')), findsNothing);
    await openTool(t, b.id);
    expect(find.byKey(Key('tool.chip.${a.id}')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byKey(Key('tool.chip.${a.id}')),
        matching: find.text('A'),
      ),
    );
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).active,
      a.id,
    );
    expect(rig.engines[b.id]!.disposed, isFalse, reason: 'D5: kept');
    await t.tap(find.byKey(Key('tool.chip.${a.id}.close')));
    await t.pumpAndSettle();
    expect(rig.engines[a.id]!.disposed, isTrue);
    await t.tap(find.byKey(const Key('tool.bar.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Expand covers the content area; Restore and Esc bring it '
      'back (D3)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('tool.dockSlot'))).width, 879);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('tool.dockSlot'))).width, 396);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).zoom,
      isFalse,
    );
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('⌘⇧B closes and reopens the dock; ⌘W in the dock closes the '
      'tool on show (D10)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(key);
      if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
    }

    await chord(LogicalKeyboardKey.keyB, shift: true);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(rig.engines[tool.id]!.disposed, isFalse, reason: 'D5');
    await chord(LogicalKeyboardKey.keyB, shift: true);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    await chord(LogicalKeyboardKey.keyW);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(rig.engines[tool.id]!.disposed, isTrue);
    expect(rig.container.read(terminalTabsProvider).tabs, hasLength(1));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    '⌘⇧B with no tool asks for one (D10)',
    (t) async {
      await rig.pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('tool.dialog.url')),
        'localhost:4000',
      );
      await t.tap(find.byKey(const Key('tool.dialog.save')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('the bar follows the page: stop while loading, the refused '
      'panel, ATS, away and back (D13, D17, Review Focus 3)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    expect(find.byKey(const Key('tool.bar.stop')), findsOneWidget);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
    await t.pump();
    expect(find.byKey(const Key('tool.error.refused')), findsOneWidget);
    expect(
      find.textContaining('Nothing is running at localhost:5173'),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 1));
    expect(engine.loads, hasLength(2), reason: 'the 1 s retry');
    engine.emit(const LoadStarted());
    engine.emit(const LoadFinished());
    await t.pump();
    expect(find.byKey(const Key('tool.error.refused')), findsNothing);
    expect(find.byKey(const Key('tool.bar.reload')), findsOneWidget);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.ats));
    await t.pump();
    expect(find.byKey(const Key('tool.error.ats')), findsOneWidget);
    expect(find.byKey(const Key('tool.error.reload')), findsNothing);
    engine.emit(const LoadStarted());
    engine.emit(UrlChanged(Uri.parse('https://sso.example.com/login')));
    engine.emit(const LoadFinished());
    await t.pump();
    expect(find.text('On sso.example.com'), findsOneWidget);
    await t.tap(find.byKey(const Key('tool.bar.backToTool')));
    await t.pump();
    expect(engine.loads.last, Uri.parse('http://localhost:5173/'));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'a forwarded ⌘T runs New tab (D10)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      expect(rig.engines[tool.id]!.forwarded, contains('super+t'));
      rig.engines[tool.id]!.emit(const ShortcutForwarded('super+t'));
      await t.pumpAndSettle();
      expect(rig.container.read(terminalTabsProvider).tabs, hasLength(2));
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a download shows its line with the browser button (D9)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      rig.engines[tool.id]!.emit(
        DownloadBlocked(url: Uri.parse('http://localhost:1/a.zip')),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('tool.download.browser')));
      await t.pump();
      expect(rig.harness.urlOpener.webLinks, [
        Uri.parse('http://localhost:1/a.zip'),
      ]);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tool-embed = off: opening a tool opens the browser (D20)',
    (t) async {
      await rig.pump(t, config: 'tool-embed = off\n');
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
      expect(rig.harness.urlOpener.webLinks, [
        Uri.parse('http://localhost:1/'),
      ]);
      expect(rig.made, 0);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Windows-like engine: a menu over the window hides the page '
      'behind a stand-in (D7)', (t) async {
    rig = ToolRig(coversFlutter: true);
    await rig.pump(t, config: 'tool-embed = on\n');
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'Board');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    expect(engine.visible, isNot(false));
    await t.tap(find.byKey(const Key('tool.bar.more')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool.covered')), findsOneWidget);
    expect(find.text('Board — hidden while a menu is open'), findsOneWidget);
    expect(engine.visible, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool.covered')), findsNothing);
    expect(engine.visible, isTrue);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a tool of a workspace without a tab: its dock beside an '
      'empty area; ⌘T opens a tab there (D4)', (t) async {
    await rig.pump(t);
    final side = rig.container.read(sidebarWorkspacesProvider.notifier);
    final ws = side.createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(find.byKey(const Key('tool.loose')), findsOneWidget);
    expect(rig.container.read(toolDockProvider).loose, ws);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyT);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    expect(rig.container.read(toolDockProvider).loose, isNull);
    final selected = rig.container.read(terminalTabsProvider).selectedId!;
    expect(
      rig.container.read(sidebarWorkspacesProvider).workspaceOf(selected),
      ws,
    );
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'the palette lists "Open tool: {name}" and opens it (D4)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'Board');
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyP);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Open tool');
      await t.pumpAndSettle();
      await t.tap(find.text('Open tool: Board'));
      await t.pumpAndSettle();
      expect(
        rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).active,
        tool.id,
      );
      expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
````

`apps/desktop/test/ui/tools/tool_ai_header_test.dart`:

````dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';
import '../../support/tool_harness.dart';

void main() {
  testWidgets('🧩 on the AI pane opens the workspace\'s tools and closes the '
      'Changes panel (D4)', (t) async {
    final rig = ToolRig();
    final files = FakeProject(testAiCwd, {'a.txt': 'x\n'})..onSnapshot = null;
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text('Done.')],
        ],
      ),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      harness: rig.harness,
      extra: [
        ...rig.overrides,
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    rig.container = w.container;
    final c = w.container;
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.tools')));
    await t.pumpAndSettle();
    expect(c.read(toolDockProvider).of(kDefaultWorkspaceId).active, tool.id);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(find.byKey(const Key('ai.sidePanel')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
````

- [ ] **Step 2: Run them to see them fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools/tool_dock_ui_test.dart test/ui/tools/tool_ai_header_test.dart
````

Expected: compilation fails, `Error when reading 'lib/src/ui/tools/tool_area.dart'`.

- [ ] **Step 3: The bar, the dock and the area**

`apps/desktop/lib/src/ui/tools/tool_bar.dart`:

````dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_page.dart';
import '../terminal/shellx_menu.dart';
import '../theme/shellx_desktop_theme.dart';

/// D17: the tool bar's height (the AI pane's bar style).
const double kToolBarHeight = 32;

enum _More { edit, copy, closeDock }

/// D17: 🧩, the name, `host:port` with the D11 mark, "On {host}" when the
/// page left the tool's origin; then back, reload/stop, phone, expand,
/// open in browser, ⋯ and ×. Every button has a spoken label (D18).
class ToolBar extends StatelessWidget {
  const ToolBar({
    super.key,
    required this.tool,
    required this.state,
    required this.zoomed,
    required this.onBack,
    required this.onReload,
    required this.onStop,
    required this.onBackToTool,
    required this.onPhone,
    required this.onZoom,
    required this.onBrowser,
    required this.onEdit,
    required this.onCopyUrl,
    required this.onCloseDock,
    required this.onClose,
  });

  final ToolEntry tool;

  /// Null before the page exists.
  final ToolPageState? state;
  final bool zoomed;
  final VoidCallback onBack;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onBackToTool;
  final VoidCallback onPhone;
  final VoidCallback onZoom;
  final VoidCallback onBrowser;
  final VoidCallback onEdit;
  final VoidCallback onCopyUrl;
  final VoidCallback onCloseDock;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = state;
    final loading = s?.loading ?? false;
    final away = s != null && s.awayFrom(tool) ? s.url : null;
    Widget button(
      Key key,
      IconData glyph,
      String label,
      VoidCallback? onPressed, {
      bool on = false,
      String? tip,
    }) => IconButton(
      key: key,
      tooltip: tip ?? label,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      color: on
          ? ShellxDesktopColors.accent
          : ShellxDesktopColors.textSecondary,
      onPressed: onPressed,
      icon: Semantics(label: label, child: Icon(glyph)),
    );
    final mark = tool.isLocal ? l10n.toolLocal : l10n.toolRemote;
    final where = tool.unencrypted
        ? '${tool.hostPort} · $mark · ${l10n.toolUnencrypted}'
        : '${tool.hostPort} · $mark';
    return SizedBox(
      height: kToolBarHeight,
      child: Padding(
        padding: const EdgeInsets.only(
          left: ShellxSpace.s8,
          right: ShellxSpace.s4,
        ),
        child: Row(
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.extension_outlined,
                size: 14,
                color: ShellxDesktopColors.accent,
              ),
            ),
            const SizedBox(width: ShellxSpace.s6),
            Flexible(
              child: Text(
                tool.name,
                key: const Key('tool.bar.name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.bodyStrong.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: ShellxSpace.s8),
            Flexible(
              child: Text(
                where,
                key: const Key('tool.bar.mark'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.caption.copyWith(
                  color: tool.unencrypted
                      ? ShellxDesktopColors.warn
                      : ShellxDesktopColors.textSecondary,
                ),
              ),
            ),
            if (away != null) ...[
              const SizedBox(width: ShellxSpace.s8),
              Flexible(
                child: Text(
                  l10n.toolAway(away.host),
                  key: const Key('tool.bar.away'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                ),
              ),
              Flexible(
                child: TextButton(
                  key: const Key('tool.bar.backToTool'),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShellxSpace.s6,
                    ),
                  ),
                  onPressed: onBackToTool,
                  child: Text(
                    l10n.toolBackToTool,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const Spacer(),
            button(
              const Key('tool.bar.back'),
              Icons.arrow_back,
              l10n.toolBack,
              s != null && s.canGoBack ? onBack : null,
            ),
            if (loading)
              button(
                const Key('tool.bar.stop'),
                Icons.close,
                l10n.toolStop,
                onStop,
              )
            else
              button(
                const Key('tool.bar.reload'),
                Icons.refresh,
                l10n.toolReload,
                onReload,
              ),
            button(
              const Key('tool.bar.phone'),
              Icons.smartphone,
              tool.phoneOn ? l10n.toolPhoneOn : l10n.toolPhoneOff,
              tool.phoneAllowed ? onPhone : null,
              on: tool.phoneOn,
              tip: tool.phoneAllowed ? null : l10n.toolPhoneOnlyLocal,
            ),
            button(
              const Key('tool.bar.expand'),
              zoomed ? Icons.close_fullscreen : Icons.open_in_full,
              zoomed ? l10n.toolCollapse : l10n.toolExpand,
              onZoom,
              on: zoomed,
            ),
            button(
              const Key('tool.bar.browser'),
              Icons.open_in_new,
              l10n.toolOpenInBrowser,
              onBrowser,
            ),
            Builder(
              builder: (context) => button(
                const Key('tool.bar.more'),
                Icons.more_horiz,
                l10n.toolMore,
                () async {
                  final box = context.findRenderObject()! as RenderBox;
                  final choice = await showShellxMenu<_More>(
                    context: context,
                    at: box.localToGlobal(Offset(0, box.size.height)),
                    entries: [
                      ShellxMenuEntry(
                        key: const Key('tool.menu.edit'),
                        value: _More.edit,
                        label: l10n.toolEditMenu,
                      ),
                      ShellxMenuEntry(
                        key: const Key('tool.menu.copy'),
                        value: _More.copy,
                        label: l10n.toolCopyUrl,
                      ),
                      ShellxMenuEntry(
                        key: const Key('tool.menu.closeDock'),
                        value: _More.closeDock,
                        label: l10n.toolCloseDock,
                      ),
                    ],
                  );
                  switch (choice) {
                    case _More.edit:
                      onEdit();
                    case _More.copy:
                      onCopyUrl();
                    case _More.closeDock:
                      onCloseDock();
                    case null:
                      break;
                  }
                },
              ),
            ),
            button(
              const Key('tool.bar.close'),
              Icons.close,
              l10n.toolClose,
              onClose,
            ),
          ],
        ),
      ),
    );
  }
}
````

`apps/desktop/lib/src/ui/tools/tool_dock_view.dart`:

````dart
import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../browser/browser_engine.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_dock_state.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_page.dart';
import '../../tools/tool_pages.dart';
import '../../tools/tool_registry.dart';
import '../terminal/device_pixel_lines.dart';
import '../theme/shellx_desktop_theme.dart';
import 'tool_actions.dart';
import 'tool_bar.dart';
import 'tool_dialogs.dart';

/// D5: a chip's height.
const double kToolChipsHeight = 30;

/// V2-3 D3: the dock of workspace [workspaceId] — the chips (from two
/// tools), the bar (D17) and the page. [focusNode] is the window's: while
/// it is the primary focus the page has the keyboard (D10). [covered]: a
/// menu, dialog or panel is open over the window (D7).
class ToolDockView extends ConsumerStatefulWidget {
  const ToolDockView({
    super.key,
    required this.workspaceId,
    required this.focusNode,
    required this.covered,
    required this.onChord,
    required this.onLeave,
  });

  final String workspaceId;
  final FocusNode focusNode;
  final bool covered;

  /// D10: a ShellX chord the page handed back.
  final void Function(String chord) onChord;

  /// The dock closed (or its last chip): the window moves the keyboard.
  final VoidCallback onLeave;

  @override
  ConsumerState<ToolDockView> createState() => _ToolDockViewState();
}

class _ToolDockViewState extends ConsumerState<ToolDockView> {
  ToolActions get _actions => ToolActions(ref);
  ToolDockController get _dock => ref.read(toolDockProvider.notifier);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(ToolDockView old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  ToolPage? get _page {
    final active = ref.read(toolDockProvider).of(widget.workspaceId).active;
    return active == null
        ? null
        : ref.read(toolPagesProvider.notifier).existing(active);
  }

  /// D10: the page has the keyboard exactly while the dock's own node is
  /// the primary focus; anywhere else (a bar button, a pane) it is
  /// Flutter's.
  void _onFocus() {
    final engine = _page?.engine;
    if (engine == null) return;
    unawaited(
      widget.focusNode.hasPrimaryFocus
          ? engine.focusContent()
          : engine.releaseFocus(),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // D3: Esc on the bar leaves "Expand".
    final dock = ref.read(toolDockProvider).of(widget.workspaceId);
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        dock.zoom) {
      _dock.setZoom(widget.workspaceId, false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _closeTool(String id) {
    _dock.closeTool(widget.workspaceId, id);
    if (!ref.read(toolDockProvider).of(widget.workspaceId).open) {
      widget.onLeave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ws = widget.workspaceId;
    final dock = ref.watch(toolDockProvider.select((d) => d.of(ws)));
    final tools = ref.watch(toolRegistryProvider);
    ref.watch(toolPagesProvider);
    final byId = {for (final t in tools) t.id: t};
    final chips = [for (final id in dock.tools) ?byId[id]];
    if (chips.isEmpty) return const SizedBox.shrink();
    final active =
        chips.where((t) => t.id == dock.active).firstOrNull ?? chips.first;
    final page = ref.read(toolPagesProvider.notifier).existing(active.id);
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        label: l10n.toolDockLabel(active.name),
        child: ColoredBox(
          color: ShellxDesktopColors.bgTerminal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chips.length >= 2)
                _ToolChips(
                  tools: chips,
                  active: active.id,
                  onSelect: (id) => _dock.activate(ws, id),
                  onClose: _closeTool,
                ),
              ListenableBuilder(
                listenable: page ?? const _Never(),
                builder: (context, _) => ToolBar(
                  tool: active,
                  state: page?.state,
                  zoomed: dock.zoom,
                  onBack: () => unawaited(page?.back()),
                  onReload: () => unawaited(page?.reload()),
                  onStop: () => unawaited(page?.stop()),
                  onBackToTool: () => unawaited(page?.backToTool()),
                  onPhone: () => _actions.togglePhone(active),
                  onZoom: () => _dock.setZoom(ws, !dock.zoom),
                  onBrowser: () => unawaited(
                    _actions.openInBrowser(
                      active,
                      url: page?.state.url ?? active.uri,
                    ),
                  ),
                  onEdit: () => unawaited(_actions.edit(context, active)),
                  onCopyUrl: () => unawaited(_actions.copyUrl(active)),
                  onCloseDock: () {
                    _dock.close(ws);
                    widget.onLeave();
                  },
                  onClose: () => _closeTool(active.id),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: _ToolPageHost(
                  key: ValueKey('tool.host.${active.id}'),
                  tool: active,
                  covered: widget.covered,
                  focusNode: widget.focusNode,
                  onChord: widget.onChord,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A listenable that never fires (the bar before its page exists).
final class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// D5: one chip per open tool; the one on show is selected (D18).
class _ToolChips extends StatelessWidget {
  const _ToolChips({
    required this.tools,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final List<ToolEntry> tools;
  final String active;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: kToolChipsHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s4),
        children: [
          for (final t in tools)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ShellxSpace.s2,
                vertical: ShellxSpace.s4,
              ),
              child: Semantics(
                button: true,
                selected: t.id == active,
                label: t.name,
                child: InkWell(
                  key: Key('tool.chip.${t.id}'),
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  onTap: () => onSelect(t.id),
                  child: Container(
                    padding: const EdgeInsets.only(left: ShellxSpace.s8),
                    decoration: BoxDecoration(
                      color: t.id == active
                          ? ShellxDesktopColors.rowSelected
                          : null,
                      borderRadius: BorderRadius.circular(ShellxRadius.r6),
                      border: Border.all(color: ShellxDesktopColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            t.name,
                            style: ShellxText.small.copyWith(
                              color: ShellxDesktopColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          key: Key('tool.chip.${t.id}.close'),
                          tooltip: l10n.toolClose,
                          iconSize: 12,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onClose(t.id),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The page of [tool]: made when first shown (D14), shown while this
/// lives (retries run only then, D13), the D13 panels, the D9 download
/// line, and on Windows the stand-in while something covers it (D7).
class _ToolPageHost extends ConsumerStatefulWidget {
  const _ToolPageHost({
    super.key,
    required this.tool,
    required this.covered,
    required this.focusNode,
    required this.onChord,
  });

  final ToolEntry tool;
  final bool covered;
  final FocusNode focusNode;
  final void Function(String chord) onChord;

  @override
  ConsumerState<_ToolPageHost> createState() => _ToolPageHostState();
}

class _ToolPageHostState extends ConsumerState<_ToolPageHost> {
  ToolPage? _page;

  /// One view per page, built once: a new widget would be a second
  /// platform view for the same web view.
  Widget? _view;

  @override
  void initState() {
    super.initState();
    // Never while building: making a page changes the pages provider.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;
    final page = ref.read(toolPagesProvider.notifier).open(widget.tool);
    page.onShortcut = widget.onChord;
    page.onContentClicked = widget.focusNode.requestFocus;
    page.onOpenOutside = (url) => unawaited(ToolActions(ref).openOutside(url));
    page.presenter = (dialog) =>
        showToolJsDialog(context, page.tool.name, dialog);
    page.setShown(true);
    setState(() {
      _page = page;
      _view = page.engine.buildView();
    });
    _syncVisible();
    if (widget.focusNode.hasPrimaryFocus) {
      unawaited(page.engine.focusContent());
    }
  }

  @override
  void didUpdateWidget(_ToolPageHost old) {
    super.didUpdateWidget(old);
    if (old.covered != widget.covered) _syncVisible();
  }

  /// D7: an engine that covers Flutter is hidden while anything is over
  /// it, or while a panel shows instead of the page.
  void _syncVisible() {
    final page = _page;
    if (page == null || !page.engine.coversFlutter) return;
    final s = page.state;
    final hide = widget.covered || s.error != null || s.download != null;
    unawaited(page.engine.setVisible(!hide));
  }

  @override
  void dispose() {
    // No ref here (the element is going): the page itself is enough. A page
    // that was unloaded meanwhile ignores all of this.
    final page = _page;
    if (page != null) {
      page.presenter = null;
      page.onShortcut = null;
      page.onContentClicked = null;
      page.onOpenOutside = null;
      page.setShown(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final view = _view;
    // The page went (unloaded for another, D5): this host makes it again.
    if (page != null &&
        ref.watch(
          toolPagesProvider.select((ids) => !ids.contains(page.tool.id)),
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _page = null;
          _view = null;
        });
        _attach();
      });
    }
    if (page == null || view == null) return const SizedBox.expand();
    return ListenableBuilder(
      listenable: page,
      builder: (context, _) {
        _syncVisible();
        final s = page.state;
        final l10n = AppLocalizations.of(context);
        final hideNative =
            page.engine.coversFlutter &&
            (widget.covered || s.error != null || s.download != null);
        return Stack(
          fit: StackFit.expand,
          children: [
            KeyedSubtree(
              key: ValueKey('tool.view.${page.tool.id}'),
              child: view,
            ),
            if (s.error case final kind?)
              _ErrorPanel(
                kind: kind,
                tool: page.tool,
                onReload: () => unawaited(page.reload()),
                onBrowser: () => unawaited(
                  ToolActions(ref).openInBrowser(page.tool, url: s.url),
                ),
              ),
            if (s.download case final url?)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _DownloadLine(
                  onBrowser: () => unawaited(
                    ToolActions(ref).openInBrowser(page.tool, url: url),
                  ),
                  onDismiss: page.dismissDownload,
                ),
              ),
            if (hideNative && widget.covered)
              Positioned.fill(
                child: ColoredBox(
                  key: const Key('tool.covered'),
                  color: ShellxDesktopColors.bgTerminal,
                  child: Center(
                    child: Text(
                      l10n.toolCovered(page.tool.name),
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// D13: what a failed load shows instead of the page.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.kind,
    required this.tool,
    required this.onReload,
    required this.onBrowser,
  });

  final BrowserLoadErrorKind kind;
  final ToolEntry tool;
  final VoidCallback onReload;
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = switch (kind) {
      BrowserLoadErrorKind.refused => l10n.toolRefused(tool.hostPort),
      BrowserLoadErrorKind.ats => l10n.toolAtsBlocked,
      BrowserLoadErrorKind.crashed => l10n.toolCrashed,
      BrowserLoadErrorKind.unavailable => l10n.toolNeedsWebView2,
      BrowserLoadErrorKind.dns => l10n.toolLoadFailed(l10n.toolReasonDns),
      BrowserLoadErrorKind.timeout => l10n.toolLoadFailed(
        l10n.toolReasonTimeout,
      ),
      BrowserLoadErrorKind.certificate => l10n.toolLoadFailed(
        l10n.toolReasonCertificate,
      ),
      BrowserLoadErrorKind.unreachable => l10n.toolLoadFailed(
        l10n.toolReasonUnreachable,
      ),
      BrowserLoadErrorKind.other => l10n.toolLoadFailed(l10n.toolReasonOther),
    };
    // D13: refused and crashed reload; ATS and a missing runtime can only
    // go to the browser; the others offer both.
    final reload =
        kind != BrowserLoadErrorKind.ats &&
        kind != BrowserLoadErrorKind.unavailable;
    final browser =
        kind != BrowserLoadErrorKind.refused &&
        kind != BrowserLoadErrorKind.crashed;
    return ColoredBox(
      key: Key('tool.error.${kind.name}'),
      color: ShellxDesktopColors.bgTerminal,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(ShellxSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: ShellxSpace.s12),
                Wrap(
                  spacing: ShellxSpace.s8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (reload)
                      FilledButton(
                        key: const Key('tool.error.reload'),
                        onPressed: onReload,
                        child: Text(l10n.toolReload),
                      ),
                    if (browser)
                      OutlinedButton(
                        key: const Key('tool.error.browser'),
                        onPressed: onBrowser,
                        child: Text(l10n.toolOpenInBrowser),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// D9: "This tool wants to download a file…" with the browser button.
class _DownloadLine extends StatelessWidget {
  const _DownloadLine({required this.onBrowser, required this.onDismiss});
  final VoidCallback onBrowser;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('tool.download'),
      color: ShellxDesktopColors.warnBg,
      padding: const EdgeInsets.symmetric(
        horizontal: ShellxSpace.s12,
        vertical: ShellxSpace.s6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.toolDownloadBlocked,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
            ),
          ),
          TextButton(
            key: const Key('tool.download.browser'),
            onPressed: onBrowser,
            child: Text(l10n.toolOpenInBrowser),
          ),
          IconButton(
            key: const Key('tool.download.close'),
            tooltip: l10n.actionClose,
            iconSize: 14,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// D3: the strip that drags the dock's width; a slider for screen readers
/// and the keyboard (5 % a step).
class ToolDockHandle extends StatefulWidget {
  const ToolDockHandle({
    super.key,
    required this.contentWidth,
    required this.dockWidth,
    required this.fraction,
    required this.onFraction,
  });

  final double contentWidth;
  final double dockWidth;
  final double fraction;
  final ValueChanged<double> onFraction;

  @override
  State<ToolDockHandle> createState() => _ToolDockHandleState();
}

class _ToolDockHandleState extends State<ToolDockHandle> {
  bool _hovered = false;
  double? _from;
  double _moved = 0;

  void _width(double px) => widget.onFraction(
    toolDockFraction(width: widget.contentWidth, dockWidth: px),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dpr = View.of(context).devicePixelRatio;
    final active = _hovered || _from != null;
    String percent(double f) => '${(f * 100).round()} %';
    return Semantics(
      slider: true,
      label: l10n.toolHandleLabel,
      value: percent(widget.fraction),
      increasedValue: percent(widget.fraction + 0.05),
      decreasedValue: percent(widget.fraction - 0.05),
      onIncrease: () => _width(widget.dockWidth + widget.contentWidth * 0.05),
      onDecrease: () => _width(widget.dockWidth - widget.contentWidth * 0.05),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const Key('tool.handle'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) => setState(() {
            _from = widget.dockWidth;
            _moved = 0;
          }),
          onPanUpdate: (d) {
            final from = _from;
            if (from == null) return;
            _moved += d.delta.dx;
            _width(from - _moved);
          },
          onPanEnd: (_) => setState(() => _from = null),
          onPanCancel: () => setState(() => _from = null),
          child: DevicePixelLine(
            vertical: true,
            color: active
                ? ShellxDesktopColors.accent
                : ShellxDesktopColors.line,
            devicePixels: hairlineDevicePixels(dpr) * (active ? 3 : 1),
            devicePixelRatio: dpr,
          ),
        ),
      ),
    );
  }
}
````

`apps/desktop/lib/src/ui/tools/tool_area.dart`:

````dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_dock_state.dart';
import '../../tools/tool_embed.dart';
import 'tool_dock_view.dart';

/// D3: the content area — the panes, and the shown workspace's dock beside
/// them (or over them, zoomed). The panes keep their place in the tree and
/// their width while the dock is zoomed, so no terminal is resized by it.
/// D4: a workspace shown without a tab gets [loosePanel] over the panes.
class ToolArea extends ConsumerWidget {
  const ToolArea({
    super.key,
    required this.panes,
    required this.dockFocus,
    required this.covered,
    required this.onChord,
    required this.onLeave,
    required this.loosePanel,
  });

  final Widget panes;
  final FocusNode dockFocus;
  final bool covered;
  final void Function(String chord) onChord;
  final VoidCallback onLeave;
  final Widget Function(String ws) loosePanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docks = ref.watch(toolDockProvider);
    final tabs = ref.watch(
      terminalTabsProvider.select((s) => (s.selectedId, s.tabs.length)),
    );
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final embedded = ref.watch(toolsEmbeddedProvider);
    final ws =
        docks.loose ??
        (tabs.$1 == null ? null : sidebar.workspaceOf(tabs.$1!)) ??
        sidebar.currentId;
    final dock = docks.of(ws);
    final loose = docks.loose;
    return LayoutBuilder(
      builder: (context, c) {
        final layout = toolDockLayout(
          width: c.maxWidth,
          dock: dock,
          embedded: embedded,
        );
        final hidden = layout.dockLeft == 0 || loose != null;
        return Stack(
          children: [
            Positioned(
              key: const ValueKey('tool.panesSlot'),
              left: 0,
              top: 0,
              bottom: 0,
              width: layout.paneWidth,
              child: ExcludeSemantics(
                excluding: hidden,
                child: ExcludeFocus(excluding: hidden, child: panes),
              ),
            ),
            if (loose != null)
              Positioned(
                key: const ValueKey('tool.looseSlot'),
                left: 0,
                top: 0,
                bottom: 0,
                width: layout.paneWidth,
                child: loosePanel(loose),
              ),
            if (layout.showsHandle)
              Positioned(
                key: const ValueKey('tool.handleSlot'),
                left: layout.paneWidth,
                top: 0,
                bottom: 0,
                width: kToolDockHandle,
                child: ToolDockHandle(
                  contentWidth: c.maxWidth,
                  dockWidth: layout.dockWidth,
                  fraction: dock.width,
                  onFraction: (f) =>
                      ref.read(toolDockProvider.notifier).setWidth(ws, f),
                ),
              ),
            if (layout.showsDock)
              Positioned(
                key: const ValueKey('tool.dockSlot'),
                left: layout.dockLeft,
                top: 0,
                bottom: 0,
                width: layout.dockWidth,
                child: ToolDockView(
                  key: ValueKey('tool.dock.$ws'),
                  workspaceId: ws,
                  focusNode: dockFocus,
                  covered: covered,
                  onChord: onChord,
                  onLeave: onLeave,
                ),
              ),
          ],
        );
      },
    );
  }
}
````

- [ ] **Step 4: Wire the window**

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
import '../../terminal/terminal_font_size.dart';
import '../../remote/ssh_actions.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../config/agent_command_approval.dart';
import '../window_focus.dart';
import '../window_router.dart';
import 'click_select.dart' show selectionText;
import 'close_tab.dart';
import 'copy_mode_controller.dart';
import 'key_sequence_host.dart';
import 'notifications_panel.dart';
import 'remote_marks.dart' show remoteAnnouncementBetween;
import 'session_sidebar.dart';
import 'shortcut_labels.dart';
import 'terminal_pane.dart';
import 'terminal_shortcuts.dart';
import 'terminal_workspace_config.dart';
````

with:

````dart
import '../../terminal/terminal_font_size.dart';
import '../../remote/ssh_actions.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_embed.dart';
import '../../tools/tool_keys.dart';
import '../../tools/tool_pages.dart';
import '../theme/shellx_desktop_theme.dart';
import '../tools/tool_actions.dart';
import '../tools/tool_area.dart';
import '../config/agent_command_approval.dart';
import '../window_focus.dart';
import '../window_router.dart';
import 'click_select.dart' show selectionText;
import 'close_tab.dart';
import 'copy_mode_controller.dart';
import 'key_sequence.dart' show keySequenceProvider;
import 'key_sequence_host.dart';
import 'notifications_panel.dart';
import 'remote_marks.dart' show remoteAnnouncementBetween;
import 'session_sidebar.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart' show EmptyTerminalState;
import 'terminal_pane.dart';
import 'terminal_shortcuts.dart';
import 'terminal_workspace_config.dart';
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
  /// The abnormal-end strip's "Close" (UI-A5 §4).
  final restoreStripFocus = FocusNode(debugLabel: 'restore strip');
  final daemonStripFocus = FocusNode(debugLabel: 'service strip');
  final sidebarScroll = ScrollController();

  /// The notifications panel is open (UI-A4 §5).
  bool panelOpen = false;
````

with:

````dart
  /// The abnormal-end strip's "Close" (UI-A5 §4).
  final restoreStripFocus = FocusNode(debugLabel: 'restore strip');
  final daemonStripFocus = FocusNode(debugLabel: 'service strip');

  /// V2-3 D10: the tool dock. Its own node being the primary focus means
  /// the page has the keyboard.
  final toolDockFocus = FocusNode(debugLabel: 'tool dock');
  final sidebarScroll = ScrollController();

  late final _tools = ToolActions(ref);

  /// The notifications panel is open (UI-A4 §5).
  bool panelOpen = false;
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        final empty = ref.read(terminalTabsProvider).tabs.isEmpty;
        (empty ? emptyFocus : terminalFocus).requestFocus();
      })
      ..ensureVisualUpdate();
  }

  /// ⌘⇧I, the bell.
````

with:

````dart
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        // V2-3 D4: a workspace shown without a tab offers "Open new tab".
        final empty =
            ref.read(terminalTabsProvider).tabs.isEmpty ||
            ref.read(toolDockProvider).loose != null;
        (empty ? emptyFocus : terminalFocus).requestFocus();
      })
      ..ensureVisualUpdate();
  }

  /// V2-3 D4, D10: the keyboard into the dock (its page), after the frame
  /// that builds it.
  void _focusDock() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && toolDockFocus.context != null) {
          toolDockFocus.requestFocus();
        }
      })
      ..ensureVisualUpdate();
  }

  /// V2-3 D4: a workspace shown without a tab: no pane command applies.
  bool get _loose => ref.read(toolDockProvider).loose != null;

  /// V2-3 D10: the shown workspace's dock is on screen.
  bool get _dockShown {
    final ws = _tools.currentWorkspace();
    final dock = ref.read(toolDockProvider).of(ws);
    return ref.read(toolsEmbeddedProvider) &&
        dock.open &&
        toolDockFocus.context != null;
  }

  /// V2-3 D10: a chord the page handed back runs as if pressed here; the
  /// first step of a sequence waits for its second step here (the page
  /// gives the keyboard back to Flutter for it).
  void _onToolChord(String chord) {
    final bindings = ref.read(shellxConfigProvider).bindings;
    switch (resolveToolChord(bindings, chord)) {
      case ToolChordIntent(:final intent):
        invokeIntent(intent);
      case ToolChordPrefix(:final prefix):
        if (ref.read(keySequenceProvider.notifier).arm(prefix)) {
          final ws = _tools.currentWorkspace();
          final active = ref.read(toolDockProvider).of(ws).active;
          final page = active == null
              ? null
              : ref.read(toolPagesProvider.notifier).existing(active);
          unawaited(page?.engine.releaseFocus());
        }
      case null:
        break;
    }
  }

  /// V2-3 D10: ⌘W in the dock closes the chip on show (the last one closes
  /// the dock).
  void _closeToolChip() {
    final ws = _tools.currentWorkspace();
    final dock = ref.read(toolDockProvider.notifier);
    final active = ref.read(toolDockProvider).of(ws).active;
    if (active != null) dock.closeTool(ws, active);
    if (!ref.read(toolDockProvider).of(ws).open) focusTerminal();
  }

  /// ⌘⇧I, the bell.
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart

  // AltGr (Windows: Ctrl + right Alt) is handled once, for every window
  // shortcut, by [WindowAction] (A9 D26).
  bool _split(Intent intent) => ref.read(terminalTabsProvider).selected != null;

  /// The pane chords apply only to a split tab; otherwise the key reaches
  /// the shell, like ⌘C without a selection.
  bool _isSplit(Intent intent) =>
      ref.read(terminalTabsProvider).selected?.isSplit ?? false;

  /// A11 D20 `break_pane`: a split tab's pane; V2-1 B10: not an AI tab's.
  bool _canBreakPane(Intent intent) {
    final selected = ref.read(terminalTabsProvider).selected;
    return selected != null && selected.isSplit && !selected.isAi;
  }
````

with:

````dart

  // AltGr (Windows: Ctrl + right Alt) is handled once, for every window
  // shortcut, by [WindowAction] (A9 D26).
  bool _split(Intent intent) =>
      !_loose && ref.read(terminalTabsProvider).selected != null;

  /// The pane chords apply only to a split tab; otherwise the key reaches
  /// the shell, like ⌘C without a selection.
  bool _isSplit(Intent intent) =>
      !_loose && (ref.read(terminalTabsProvider).selected?.isSplit ?? false);

  /// A11 D20 `break_pane`: a split tab's pane; V2-1 B10: not an AI tab's.
  bool _canBreakPane(Intent intent) {
    if (_loose) return false;
    final selected = ref.read(terminalTabsProvider).selected;
    return selected != null && selected.isSplit && !selected.isAi;
  }
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
      // open; they close it first.
      NewTabIntent: run<NewTabIntent>((_) {
        closePanel();
        unawaited(ref.read(sshActionsProvider).newTab());
        focusTerminal();
      }),
      // V2-1 D5: ⌘⇧E, the sidebar's button, the `+` menu, the palette.
      NewAiSessionIntent: run<NewAiSessionIntent>((_) {
        closePanel();
        ref.read(aiOpenerProvider).newSession();
        focusTerminal();
      }),
      // V2-1 D5: a terminal tab, whatever `new-tab-kind` says.
      NewTerminalTabIntent: run<NewTerminalTabIntent>((_) {
        closePanel();
        unawaited(
          workspaces.openTabIn(ref.read(sidebarWorkspacesProvider).currentId),
        );
        focusTerminal();
      }),
      CloseTabIntent: run<CloseTabIntent>((_) {
        closePanel();
        // UI-A2 §4: an open name field (maybe another tab's) is saved
        // first; losing the focus commits it.
        if (ref.read(sidebarWorkspacesProvider).renaming != null) {
````

with:

````dart
      // open; they close it first.
      NewTabIntent: run<NewTabIntent>((_) {
        closePanel();
        // V2-3 D4: in a workspace shown without a tab, the tab goes there.
        final loose = ref.read(toolDockProvider).loose;
        unawaited(
          loose != null
              ? ref.read(aiOpenerProvider).newTabIn(loose)
              : ref.read(sshActionsProvider).newTab(),
        );
        focusTerminal();
      }),
      // V2-1 D5: ⌘⇧E, the sidebar's button, the `+` menu, the palette.
      NewAiSessionIntent: run<NewAiSessionIntent>((_) {
        closePanel();
        ref
            .read(aiOpenerProvider)
            .newSession(workspaceId: ref.read(toolDockProvider).loose);
        focusTerminal();
      }),
      // V2-1 D5: a terminal tab, whatever `new-tab-kind` says.
      NewTerminalTabIntent: run<NewTerminalTabIntent>((_) {
        closePanel();
        unawaited(
          workspaces.openTabIn(
            ref.read(toolDockProvider).loose ??
                ref.read(sidebarWorkspacesProvider).currentId,
          ),
        );
        focusTerminal();
      }),
      CloseTabIntent: run<CloseTabIntent>((_) {
        closePanel();
        // V2-3 D10: in the dock, ⌘W closes the tool on show.
        if (toolDockFocus.hasFocus) {
          _closeToolChip();
          return;
        }
        // D4: nothing of the covered tab closes from a tab-less workspace.
        if (_loose) return;
        // UI-A2 §4: an open name field (maybe another tab's) is saved
        // first; losing the focus commits it.
        if (ref.read(sidebarWorkspacesProvider).renaming != null) {
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
        closePanel();
        unawaited(_splitPane(intent.axis));
      }, enabled: _split),
      FocusPaneIntent: run<FocusPaneIntent>((intent) {
        closePanel();
        if (tabs.focusDirection(intent.direction)) {
          focusTerminal();
          _announceFocusedPane();
        }
      }, enabled: _isSplit),
      TogglePaneZoomIntent: run<TogglePaneZoomIntent>((_) {
        closePanel();
        final l10n = AppLocalizations.of(context);
````

with:

````dart
        closePanel();
        unawaited(_splitPane(intent.axis));
      }, enabled: _split),
      // V2-3 D10: right from the rightmost pane into the dock, left from the
      // dock back to the panes.
      FocusPaneIntent: run<FocusPaneIntent>(
        (intent) {
          closePanel();
          if (toolDockFocus.hasFocus) {
            if (intent.direction == PaneDirection.left) focusTerminal();
            return;
          }
          if (_isSplit(intent) && tabs.focusDirection(intent.direction)) {
            focusTerminal();
            _announceFocusedPane();
          } else if (intent.direction == PaneDirection.right && _dockShown) {
            _focusDock();
          }
        },
        enabled: (intent) =>
            _isSplit(intent) ||
            toolDockFocus.hasFocus ||
            (intent.direction == PaneDirection.right && _dockShown),
      ),
      TogglePaneZoomIntent: run<TogglePaneZoomIntent>((_) {
        closePanel();
        final l10n = AppLocalizations.of(context);
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
      NewWorkspaceIntent: run<NewWorkspaceIntent>((_) {
        closePanel();
        unawaited(workspaces.create());
      }),
      ToggleNotificationsPanelIntent: run<ToggleNotificationsPanelIntent>(
        (_) => togglePanel(),
````

with:

````dart
      NewWorkspaceIntent: run<NewWorkspaceIntent>((_) {
        closePanel();
        unawaited(workspaces.create());
      }),
      // V2-3 D10, D20: ⌘⇧B, the AI header's tool button.
      ToggleToolsIntent: run<ToggleToolsIntent>((_) {
        closePanel();
        unawaited(() async {
          final result = await _tools.toggle(context);
          if (!mounted) return;
          switch (result) {
            case ToolToggle.opened:
              _focusDock();
            case ToolToggle.closed:
              focusTerminal();
            case ToolToggle.asked || ToolToggle.nothing:
              break;
          }
        }());
      }),
      // V2-3 D4, D21: a new tool of the shown workspace, opened at once
      // (criterion 1).
      AddToolIntent: run<AddToolIntent>((_) {
        closePanel();
        unawaited(() async {
          final tool = await _tools.add(context, _tools.currentWorkspace());
          if (tool == null || !mounted) return;
          if (await _tools.open(tool.id) && mounted) _focusDock();
        }());
      }),
      // V2-3 D4: the sidebar's rows, the palette, Settings › Projects.
      OpenToolIntent: run<OpenToolIntent>((intent) {
        closePanel();
        unawaited(() async {
          if (await _tools.open(intent.toolId) && mounted) _focusDock();
        }());
      }),
      ToggleNotificationsPanelIntent: run<ToggleNotificationsPanelIntent>(
        (_) => togglePanel(),
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
  /// V2-1 D2: the selected tab's focused pane is a terminal pane (not the
  /// AI pane): find, copy mode and select-all apply.
  bool _terminalFocused() =>
      ref.read(terminalTabsProvider).selected?.focused != null;

  /// A10 D4: the find bar of the selected tab's focused pane, if open.
  FindSession? _focusedFind() {
````

with:

````dart
  /// V2-1 D2: the selected tab's focused pane is a terminal pane (not the
  /// AI pane): find, copy mode and select-all apply.
  bool _terminalFocused() =>
      !_loose && ref.read(terminalTabsProvider).selected?.focused != null;

  /// A10 D4: the find bar of the selected tab's focused pane, if open.
  FindSession? _focusedFind() {
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
  /// panes behave alike.
  Future<void> _paste() async {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null) return;
    final paneId = tab.focusedPaneId;
    // A11 D13: a paste (the menu's too) is for the program, not for copy
    // mode: the mode ends first.
````

with:

````dart
  /// panes behave alike.
  Future<void> _paste() async {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null || _loose) return;
    final paneId = tab.focusedPaneId;
    // A11 D13: a paste (the menu's too) is for the program, not for copy
    // mode: the mode ends first.
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
    stripFocus.dispose();
    restoreStripFocus.dispose();
    daemonStripFocus.dispose();
    sidebarScroll.dispose();
    super.dispose();
  }
````

with:

````dart
    stripFocus.dispose();
    restoreStripFocus.dispose();
    daemonStripFocus.dispose();
    toolDockFocus.dispose();
    sidebarScroll.dispose();
    super.dispose();
  }
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
      defaultTargetPlatform,
      ref.watch(shellxConfigProvider.select((s) => s.bindings)),
    );
    return Shortcuts(
      shortcuts: overlayBlocksShortcuts ? const {} : _workspaceShortcuts!,
      child: Actions(
````

with:

````dart
      defaultTargetPlatform,
      ref.watch(shellxConfigProvider.select((s) => s.bindings)),
    );
    // V2-3 D7: anything over the window (the panel, an A9 overlay, a
    // dialog, a menu) covers the tool page; a page Flutter cannot draw over
    // (Windows) hides meanwhile.
    final covered =
        panelOpen ||
        overlay != null ||
        ref.watch(windowRouterProvider.select((w) => w.dialogOpen)) ||
        !(ModalRoute.isCurrentOf(context) ?? true);
    return Shortcuts(
      shortcuts: overlayBlocksShortcuts ? const {} : _workspaceShortcuts!,
      child: Actions(
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
                Positioned.fill(
                  child: ExcludeSemantics(
                    excluding: panelOpen || overlay != null,
                    child: _body(),
                  ),
                ),
                // UI-A4 §5.3: a click outside closes the panel (and only that).
````

with:

````dart
                Positioned.fill(
                  child: ExcludeSemantics(
                    excluding: panelOpen || overlay != null,
                    child: _body(covered),
                  ),
                ),
                // UI-A4 §5.3: a click outside closes the panel (and only that).
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
    );
  }

  Widget _body() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
````

with:

````dart
    );
  }

  Widget _body(bool covered) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

````dart
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: TerminalPane(
          terminalFocus: terminalFocus,
          emptyFocus: emptyFocus,
          stripFocus: stripFocus,
          restoreStripFocus: restoreStripFocus,
          daemonStripFocus: daemonStripFocus,
          shortcuts: overlayBlocksShortcuts ? const {} : terminalShortcuts,
          onKeyEvent: _terminalKey,
          onShowConfigProblems: () => openOverlay(A9Overlay.problems),
          onReviewAgentCommand: (command) => unawaited(
            reviewAgentCommand(ref, AppLocalizations.of(context), command),
          ),
          onClosePane: (id) {
            final tab = ref.read(terminalTabsProvider).tabOfSession(id);
            if (tab != null) unawaited(closePane(tab, id));
          },
        ),
      ),
    ],
````

with:

````dart
      ),
      const VerticalDivider(width: 1),
      Expanded(
        // V2-3 D3: the tool dock is a third column, beside the panes.
        child: ToolArea(
          dockFocus: toolDockFocus,
          covered: covered,
          onChord: _onToolChord,
          onLeave: focusTerminal,
          loosePanel: (ws) => ColoredBox(
            key: const Key('tool.loose'),
            color: ShellxDesktopColors.bgTerminal,
            child: EmptyTerminalState(
              buttonFocus: emptyFocus,
              onOpen: () => unawaited(
                ref.read(sidebarWorkspacesProvider.notifier).openTabIn(ws),
              ),
            ),
          ),
          panes: TerminalPane(
            terminalFocus: terminalFocus,
            emptyFocus: emptyFocus,
            stripFocus: stripFocus,
            restoreStripFocus: restoreStripFocus,
            daemonStripFocus: daemonStripFocus,
            shortcuts: overlayBlocksShortcuts ? const {} : terminalShortcuts,
            onKeyEvent: _terminalKey,
            onShowConfigProblems: () => openOverlay(A9Overlay.problems),
            onReviewAgentCommand: (command) => unawaited(
              reviewAgentCommand(ref, AppLocalizations.of(context), command),
            ),
            onClosePane: (id) {
              final tab = ref.read(terminalTabsProvider).tabOfSession(id);
              if (tab != null) unawaited(closePane(tab, id));
            },
          ),
        ),
      ),
    ],
````

- [ ] **Step 5: The AI header and the palette**

In `apps/desktop/lib/src/ui/ai/ai_header.dart`, replace:

````dart
    required this.onTerminal,
    this.onZoom,
    required this.onMore,
  });

  final int paneId;
````

with:

````dart
    required this.onTerminal,
    this.onZoom,
    required this.onMore,
    this.onTools,
    this.toolsOn = false,
  });

  final int paneId;
````

In `apps/desktop/lib/src/ui/ai/ai_header.dart`, replace:

````dart

  /// ⋯, with the point under the button (global) for the menu.
  final void Function(Offset at) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
````

with:

````dart

  /// ⋯, with the point under the button (global) for the menu.
  final void Function(Offset at) onMore;

  /// V2-3 D4: 🧩 shows or hides the workspace's tools; [toolsOn] while
  /// they show.
  final VoidCallback? onTools;
  final bool toolsOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
````

In `apps/desktop/lib/src/ui/ai/ai_header.dart`, replace:

````dart
              ),
            ),
            const Spacer(),
            if (onHistory case final open?)
              button(
                Icons.history,
````

with:

````dart
              ),
            ),
            const Spacer(),
            if (onTools case final tools?)
              button(
                Icons.extension_outlined,
                l10n.actionToggleTools,
                tools,
                const Key('ai.tools'),
                on: toolsOn,
              ),
            if (onHistory case final open?)
              button(
                Icons.history,
````

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

````dart
import '../../ai/ai_runtimes.dart';
import '../../config/settings_schema.dart' show SettingPage;
import '../../terminal/clipboard_media.dart' show clipboardMediaProvider;
import '../../terminal/terminal_tabs.dart';
import '../config/config_ui_request.dart';
import '../settings/settings_start_page.dart';
import '../terminal/shellx_menu.dart';
import '../terminal/terminal_intents.dart' show TogglePaneZoomIntent;
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart';
import 'ai_dock.dart';
````

with:

````dart
import '../../ai/ai_runtimes.dart';
import '../../config/settings_schema.dart' show SettingPage;
import '../../terminal/clipboard_media.dart' show clipboardMediaProvider;
import '../../terminal/sidebar_workspaces.dart' show sidebarWorkspacesProvider;
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_dock.dart';
import '../config/config_ui_request.dart';
import '../settings/settings_start_page.dart';
import '../terminal/shellx_menu.dart';
import '../terminal/terminal_intents.dart'
    show TogglePaneZoomIntent, ToggleToolsIntent;
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart';
import 'ai_dock.dart';
````

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

````dart
      );
    }
    final tabs = ref.read(terminalTabsProvider.notifier);
    Widget header(AiHeaderView view) => ListenableBuilder(
      listenable: _ui,
      builder: (context, _) => AiHeader(
````

with:

````dart
      );
    }
    final tabs = ref.read(terminalTabsProvider.notifier);
    // V2-3 D4: the tools of this tab's workspace; their dock opening closes
    // the Changes/Files panel (the user can open it again).
    final ws = ref.watch(
      sidebarWorkspacesProvider.select((s) => s.workspaceOf(widget.tab.id)),
    );
    final toolsOn = ref.watch(
      toolDockProvider.select((d) => ws != null && d.of(ws).open),
    );
    ref.listen<bool>(
      toolDockProvider.select((d) => ws != null && d.of(ws).open),
      (was, open) {
        if (open && was == false && _ui.panelOpen) _ui.togglePanel();
      },
    );
    Widget header(AiHeaderView view) => ListenableBuilder(
      listenable: _ui,
      builder: (context, _) => AiHeader(
````

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

````dart
        onTerminal: () => unawaited(tabs.openAiTerminal(widget.tab.id)),
        onZoom: widget.tab.isSplit ? _zoom : null,
        onMore: (at) => unawaited(_more(at)),
      ),
    );
    final content = Semantics(
````

with:

````dart
        onTerminal: () => unawaited(tabs.openAiTerminal(widget.tab.id)),
        onZoom: widget.tab.isSplit ? _zoom : null,
        onMore: (at) => unawaited(_more(at)),
        onTools: () => Actions.maybeInvoke(context, const ToggleToolsIntent()),
        toolsOn: toolsOn,
      ),
    );
    final content = Semantics(
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart`, replace:

````dart
import '../../terminal/sidebar_workspaces.dart'
    show settingsStoreProvider, sidebarWorkspacesProvider;
import '../../terminal/terminal_tabs.dart';
import '../config/command_palette.dart';
import '../config/config_problems_panel.dart';
import '../config/config_ui_request.dart';
````

with:

````dart
import '../../terminal/sidebar_workspaces.dart'
    show settingsStoreProvider, sidebarWorkspacesProvider;
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_registry.dart';
import '../config/command_palette.dart';
import '../config/config_problems_panel.dart';
import '../config/config_ui_request.dart';
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart`, replace:

````dart
import '../settings/settings_overlay.dart';
import '../window_router.dart';
import '../theme/shellx_desktop_theme.dart';
import 'key_sequence.dart';
import 'terminal_intents.dart';
import 'shortcut_labels.dart';
````

with:

````dart
import '../settings/settings_overlay.dart';
import '../window_router.dart';
import '../theme/shellx_desktop_theme.dart';
import '../tools/tool_actions.dart';
import 'key_sequence.dart';
import 'terminal_intents.dart';
import 'shortcut_labels.dart';
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart`, replace:

````dart
          },
        ),
        ..._moveEntries(l10n),
      ];
    });
  }

  /// A11 D20: "Move tab to {workspace}" for each other workspace and "Move
````

with:

````dart
          },
        ),
        ..._moveEntries(l10n),
        ..._toolEntries(l10n),
      ];
    });
  }

  /// V2-3 D4: "Open tool: {name}" for every tool, the shown workspace's
  /// first; the workspace's name under it while there are several.
  List<PaletteEntry> _toolEntries(AppLocalizations l10n) {
    final tools = ref.read(toolRegistryProvider);
    if (tools.isEmpty) return const [];
    final side = ref.read(sidebarWorkspacesProvider);
    final here = ToolActions(ref).currentWorkspace();
    return [
      for (final t in [
        ...tools.where((t) => t.ws == here),
        ...tools.where((t) => t.ws != here),
      ])
        PaletteEntry(
          id: 'tool:${t.id}',
          title: l10n.toolOpenCommand(t.name),
          subtitle: side.showHeaders
              ? side.workspace(t.ws)?.displayName(l10n)
              : null,
          kind: PaletteKind.action,
          shortcut: null,
          intent: OpenToolIntent(t.id),
        ),
    ];
  }

  /// A11 D20: "Move tab to {workspace}" for each other workspace and "Move
````

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart`, replace:

````dart
      },
    );
    _openIntents = {for (final e in entries) describeIntent(e.intent)};
    return [...entries, ..._moveEntries(AppLocalizations.of(context))];
  }

  /// Enter or a click: close first (the keyboard goes back where it was),
````

with:

````dart
      },
    );
    _openIntents = {for (final e in entries) describeIntent(e.intent)};
    final l10n = AppLocalizations.of(context);
    return [...entries, ..._moveEntries(l10n), ..._toolEntries(l10n)];
  }

  /// Enter or a click: close first (the keyboard goes back where it was),
````

- [ ] **Step 6: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/ui/tools lib/src/ui/terminal/terminal_workspace_page.dart lib/src/ui/ai/ai_header.dart lib/src/ui/ai/ai_pane_view.dart lib/src/ui/terminal/terminal_workspace_notices.dart test/ui/tools
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools test/ui/terminal test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_dock_ui_test.dart` +13 and `tool_ai_header_test.dart` +1, all passed.
- Every `test/ui/terminal` and `test/ui/ai` test still passes. The window's focus, split, close and palette tests run through `ToolArea` now.
- `No issues found!`
- The whole suite: `3782 passed, 9 skipped`.

- [ ] **Step 7: Build the macOS app (no launch)**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug
sed -i '' 's/^COCOAPODS: .*/COCOAPODS: 1.16.2/' macos/Podfile.lock && git diff --stat macos/Podfile.lock
````

Expected: `✓ Built build/macos/Build/Products/Debug/ShellX.app`; no `Podfile.lock` change.

- [ ] **Step 8: Commit**

````bash
git add apps/desktop/lib/src/ui/tools/tool_bar.dart apps/desktop/lib/src/ui/tools/tool_dock_view.dart \
  apps/desktop/lib/src/ui/tools/tool_area.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart \
  apps/desktop/lib/src/ui/ai/ai_header.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart \
  apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart \
  apps/desktop/test/ui/tools/tool_dock_ui_test.dart apps/desktop/test/ui/tools/tool_ai_header_test.dart
git commit -m "feat(v2-tools): the tool dock beside the panes — bar, chips, kept pages, ⌘⇧B/⌘W/focus keys, palette, AI header button

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 14: The sidebar — a "Tools" group per workspace, and "Add tool"

D21 in the sidebar.

**The group.** Under each workspace that has tools, after its rows, a foldable "Tool" group (`Key('sidebar.tools.<workspace id>')`).
- **Rows:** one per tool (`sidebar.tool.<id>`): 🧩, the name, and a second line `host:port`, plus " · cả điện thoại" while the phone flag is on.
- **Lit row:** the tool on show in an open dock.
- **Click:** runs `OpenToolIntent`.
- **Right-click menu:** `tool.row.menu.open`, `tool.row.menu.browser`, `tool.row.menu.edit`, `tool.row.menu.phone`, `tool.row.menu.delete`. Delete asks first, then the chip and the page go (D23).
- **Not embedded (D20):** a row shows ↗ (`sidebar.tool.browserMark`), and opening it opens the browser.
- **Keyboard:** rows are buttons (D18) but not arrow-key stops, and folding lasts for the run (ruling R11).

**The footer.** "Add tool" (`sidebar.addTool`) sits beside "New AI session" (`sidebar.newAi`). Both share the footer row, ellipsized on a narrow sidebar. It runs `AddToolIntent` on the shown workspace, which also opens the new tool (criterion 1: three clicks, pinned by a test).

**Files:**
- Create: `apps/desktop/lib/src/ui/tools/tool_sidebar_group.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`
- Test: `apps/desktop/test/ui/tools/tool_sidebar_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `toolRegistryProvider`, `ToolEntry`;
  - Task 4: `OpenToolIntent`, `AddToolIntent`;
  - Task 7: `toolsEmbeddedProvider`;
  - Task 8: `toolDockProvider`;
  - Task 12: `ToolActions` and `ToolRig`;
  - existing: `SessionSidebar` internals (`_Item`, row heights, `TextScaler`).
- Produces:
  - `final toolGroupsFoldedProvider = NotifierProvider<ToolGroupsFolded, Set<String>>(ToolGroupsFolded.new)`, with `void ToolGroupsFolded.toggle(String ws)`;
  - `class ToolSidebarGroup extends ConsumerWidget`, built with `ToolSidebarGroup({Key? key, required String workspaceId, required List<ToolEntry> tools})`;
  - `static double ToolSidebarGroup.heightFor(TextScaler scaler, {required int count, required bool folded})` (the sidebar's virtualized list needs each item's height).

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/tools/tool_sidebar_test.dart`:

````dart
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  testWidgets('each workspace\'s tools sit under it in a foldable group; '
      '"· on phone too"; the row on show is lit (D21)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    rig.container
        .read(toolRegistryProvider.notifier)
        .update(a.copyWith(phone: true));
    final ws2 = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'Shop');
    final b = rig.add(ws2, 'https://grafana.example.com', name: 'Grafana');
    await t.pumpAndSettle();
    expect(find.byKey(Key('sidebar.tool.${a.id}')), findsOneWidget);
    expect(find.byKey(Key('sidebar.tool.${b.id}')), findsOneWidget);
    expect(find.text('localhost:4000 · on phone too'), findsOneWidget);
    expect(find.text('grafana.example.com:443'), findsOneWidget);
    await t.tap(find.byKey(const Key('sidebar.tools.$kDefaultWorkspaceId')));
    await t.pumpAndSettle();
    expect(find.byKey(Key('sidebar.tool.${a.id}')), findsNothing);
    await t.tap(find.byKey(const Key('sidebar.tools.$kDefaultWorkspaceId')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('sidebar.tool.${a.id}')));
    await t.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byKey(Key('sidebar.tool.${a.id}')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('right-click: Delete asks, then the tool, its chip and its '
      'page go (D21, D23)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('sidebar.tool.${a.id}')));
    await t.pumpAndSettle();
    await t.tap(
      find.byKey(Key('sidebar.tool.${a.id}')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tool.row.menu.delete')));
    await t.pumpAndSettle();
    final confirm = rig.container.read(windowRouterProvider).confirm!;
    expect(
      confirm.title,
      'Delete the tool "Board"? Its page closes. Its web data stays.',
    );
    confirm.complete(true);
    await t.pumpAndSettle();
    expect(rig.container.read(toolRegistryProvider), isEmpty);
    expect(rig.engines[a.id]!.disposed, isTrue);
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).open,
      isFalse,
    );
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('"Add tool" sits beside "New AI session" at the foot (D21)', (
    t,
  ) async {
    await rig.pump(t);
    final ai = t.getRect(find.byKey(const Key('sidebar.newAi')));
    final add = t.getRect(find.byKey(const Key('sidebar.addTool')));
    expect(add.top, ai.top);
    expect(add.left, greaterThan(ai.left));
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('criterion 1: "Add tool", a suggestion, Add — the dock is '
      'open on the page in three clicks (D12, D21)', (t) async {
    await rig.pump(t);
    rig.probe.ports[7] = {5173};
    rig.probe.table[7] = (parent: 1, name: 'vite');
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    final session = rig.container.read(terminalTabsProvider).tabs.single.id;
    local.replace(local.summary(session, ports: [5173]));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sidebar.addTool')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tool.suggestion.5173')));
    await t.pump();
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    final tool = rig.container.read(toolRegistryProvider).single;
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(rig.engines[tool.id]!.loads, [Uri.parse('http://localhost:5173/')]);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('tools that open in the browser show ↗ on their row (D20)', (
    t,
  ) async {
    await rig.pump(t, config: 'tool-embed = off\n');
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sidebar.tool.browserMark')), findsOneWidget);
    await t.tap(find.byKey(Key('sidebar.tool.${tool.id}')));
    await t.pumpAndSettle();
    expect(rig.harness.urlOpener.webLinks, [Uri.parse('http://localhost:1/')]);
    await disposeWorkspace(t, rig.container);
  });
}
````

- [ ] **Step 2: Run it to see it fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools/tool_sidebar_test.dart
````

Expected: the tests compile and fail on their finders: no `sidebar.tools.…` group and no `sidebar.addTool` button yet (`Found 0 widgets with key …`).

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/tools/tool_sidebar_group.dart`:

````dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_embed.dart';
import '../../tools/tool_entry.dart';
import '../terminal/shellx_menu.dart';
import '../terminal/terminal_intents.dart';
import '../theme/shellx_desktop_theme.dart';
import 'tool_actions.dart';

/// D21: the workspaces whose "Tools" group is folded (this run only).
final toolGroupsFoldedProvider =
    NotifierProvider<ToolGroupsFolded, Set<String>>(ToolGroupsFolded.new);

class ToolGroupsFolded extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String ws) =>
      state = state.contains(ws) ? ({...state}..remove(ws)) : {...state, ws};
}

enum _ToolMenu { open, browser, edit, phone, delete }

/// D21: under a workspace with tools, the foldable "Tools" group: one row
/// per tool — 🧩, the name, `host:port` (with "· on phone too"), ↗ when
/// tools open in the browser (D20). The row of the tool on show in an open
/// dock is lit. Rows are buttons (D18); the keyboard reaches tools through
/// the palette and ⌘⇧B (ruling R11).
class ToolSidebarGroup extends ConsumerWidget {
  const ToolSidebarGroup({
    super.key,
    required this.workspaceId,
    required this.tools,
  });

  final String workspaceId;
  final List<ToolEntry> tools;

  static const double _header = 24;
  static const double _row = 36;

  /// The group's height, which the sidebar's lazy list adds up.
  static double heightFor(
    TextScaler scaler, {
    required int count,
    required bool folded,
  }) {
    final header = math.max(_header, scaler.scale(13) + 8);
    final row = math.max(_row, scaler.scale(13) + scaler.scale(11) + 12);
    return header + (folded ? 0 : row * count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final folded = ref.watch(
      toolGroupsFoldedProvider.select((s) => s.contains(workspaceId)),
    );
    final dock = ref.watch(toolDockProvider.select((d) => d.of(workspaceId)));
    final embedded = ref.watch(toolsEmbeddedProvider);
    final header = math.max(_header, scaler.scale(13) + 8);
    final row = math.max(_row, scaler.scale(13) + scaler.scale(11) + 12);
    return SizedBox(
      height: heightFor(scaler, count: tools.length, folded: folded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: header,
            child: Semantics(
              button: true,
              expanded: !folded,
              label: l10n.toolsGroup,
              child: InkWell(
                key: Key('sidebar.tools.$workspaceId'),
                onTap: () => ref
                    .read(toolGroupsFoldedProvider.notifier)
                    .toggle(workspaceId),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        folded ? Icons.chevron_right : Icons.expand_more,
                        size: 14,
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: ShellxSpace.s4),
                    ExcludeSemantics(
                      child: Text(
                        l10n.toolsGroup,
                        style: ShellxText.caption.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!folded)
            for (final t in tools)
              SizedBox(
                height: row,
                child: _ToolRow(
                  tool: t,
                  lit: dock.open && dock.active == t.id,
                  embedded: embedded,
                ),
              ),
        ],
      ),
    );
  }
}

class _ToolRow extends ConsumerWidget {
  const _ToolRow({
    required this.tool,
    required this.lit,
    required this.embedded,
  });

  final ToolEntry tool;
  final bool lit;
  final bool embedded;

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final actions = ToolActions(ref);
    final choice = await showShellxMenu<_ToolMenu>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('tool.row.menu.open'),
          value: _ToolMenu.open,
          label: l10n.toolMenuOpen,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.browser'),
          value: _ToolMenu.browser,
          label: l10n.toolOpenInBrowser,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.edit'),
          value: _ToolMenu.edit,
          label: l10n.toolMenuEdit,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.phone'),
          value: _ToolMenu.phone,
          label: l10n.toolDialogPhone,
          checked: tool.phoneOn,
          enabled: tool.phoneAllowed,
          tooltip: tool.phoneAllowed ? null : l10n.toolPhoneOnlyLocal,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.delete'),
          value: _ToolMenu.delete,
          label: l10n.toolMenuDelete,
          dividerBefore: true,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case _ToolMenu.open:
        Actions.maybeInvoke(context, OpenToolIntent(tool.id));
      case _ToolMenu.browser:
        unawaited(actions.openInBrowser(tool));
      case _ToolMenu.edit:
        unawaited(actions.edit(context, tool));
      case _ToolMenu.phone:
        actions.togglePhone(tool);
      case _ToolMenu.delete:
        unawaited(actions.delete(tool));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sub = tool.phoneOn
        ? '${tool.hostPort} ${l10n.toolAlsoPhone}'
        : tool.hostPort;
    return Semantics(
      button: true,
      selected: lit,
      label: '${tool.name}, $sub',
      child: GestureDetector(
        onSecondaryTapUp: (d) =>
            unawaited(_menu(context, ref, d.globalPosition)),
        child: InkWell(
          key: Key('sidebar.tool.${tool.id}'),
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
          onTap: () => Actions.maybeInvoke(context, OpenToolIntent(tool.id)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
            decoration: BoxDecoration(
              color: lit ? ShellxDesktopColors.rowSelected : null,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const Icon(
                    Icons.extension_outlined,
                    size: 14,
                    color: ShellxDesktopColors.accent,
                  ),
                  const SizedBox(width: ShellxSpace.s6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!embedded)
                    const Icon(
                      Icons.open_in_new,
                      key: Key('sidebar.tool.browserMark'),
                      size: 12,
                      color: ShellxDesktopColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
import '../../config/config_controller.dart';
import '../../remote/remote_port_forwards.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'session_tab_row.dart';
import 'shellx_menu.dart';
import 'sidebar_new_button.dart';
````

with:

````dart
import '../../config/config_controller.dart';
import '../../remote/remote_port_forwards.dart';
import '../../terminal/terminal_tabs.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_registry.dart';
import '../theme/shellx_desktop_theme.dart';
import '../tools/tool_sidebar_group.dart';
import 'session_tab_row.dart';
import 'shellx_menu.dart';
import 'sidebar_new_button.dart';
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
    final tabsState = ref.read(terminalTabsProvider);
    final attention = ref.read(tabAttentionProvider);
    final byId = {for (final t in tabsState.tabs) t.id: t};
    final items = <_Item>[];
    for (final w in s.workspaces) {
      final tabs = [for (final id in s.tabsOf(w.id)) ?byId[id]];
      if (s.showHeaders) {
````

with:

````dart
    final tabsState = ref.read(terminalTabsProvider);
    final attention = ref.read(tabAttentionProvider);
    final byId = {for (final t in tabsState.tabs) t.id: t};
    // V2-3 D21: each workspace's tools, after its rows.
    final toolsByWs = <String, List<ToolEntry>>{};
    for (final t in ref.read(toolRegistryProvider)) {
      toolsByWs.putIfAbsent(t.ws, () => []).add(t);
    }
    final folded = ref.read(toolGroupsFoldedProvider);
    final items = <_Item>[];
    void addTools(String ws) {
      final tools = toolsByWs[ws];
      if (tools == null) return;
      items.add(_ToolsItem(ws, tools, folded: folded.contains(ws)));
    }

    for (final w in s.workspaces) {
      final tabs = [for (final id in s.tabsOf(w.id)) ?byId[id]];
      if (s.showHeaders) {
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
        if (w.collapsed) continue;
        if (tabs.isEmpty) {
          items.add(_EmptyItem(w.id));
          continue;
        }
      }
````

with:

````dart
        if (w.collapsed) continue;
        if (tabs.isEmpty) {
          items.add(_EmptyItem(w.id));
          addTools(w.id);
          continue;
        }
      }
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
          ),
        );
      }
    }
    return items;
  }
````

with:

````dart
          ),
        );
      }
      addTools(w.id);
    }
    return items;
  }
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
    _HeaderItem(:final workspace) => ValueKey(('header', workspace.id)),
    _RowItem(:final tab) => ValueKey(('row', tab.id)),
    _EmptyItem(:final workspaceId) => ValueKey(('empty', workspaceId)),
  };

  /// Space above item [i]: 8 above a header (the first item has the
````

with:

````dart
    _HeaderItem(:final workspace) => ValueKey(('header', workspace.id)),
    _RowItem(:final tab) => ValueKey(('row', tab.id)),
    _EmptyItem(:final workspaceId) => ValueKey(('empty', workspaceId)),
    _ToolsItem(:final workspaceId) => ValueKey(('tools', workspaceId)),
  };

  /// Space above item [i]: 8 above a header (the first item has the
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
      ShellxSizes.emptyWorkspaceRow,
      scaler.scale(ShellxSizes.contextLine) + 16,
    ),
  };

  /// What the keyboard walks (D14): headers (workspace ids) and visible
````

with:

````dart
      ShellxSizes.emptyWorkspaceRow,
      scaler.scale(ShellxSizes.contextLine) + 16,
    ),
    _ToolsItem(:final tools, :final folded) => ToolSidebarGroup.heightFor(
      scaler,
      count: tools.length,
      folded: folded,
    ),
  };

  /// What the keyboard walks (D14): headers (workspace ids) and visible
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
      switch (item) {
        _HeaderItem(:final workspace) => workspace.id,
        _RowItem(:final tab) => tab.id,
        _EmptyItem() => null,
      },
  ].nonNulls.toList();

````

with:

````dart
      switch (item) {
        _HeaderItem(:final workspace) => workspace.id,
        _RowItem(:final tab) => tab.id,
        _EmptyItem() || _ToolsItem() => null,
      },
  ].nonNulls.toList();

````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
      final matches = switch (item) {
        _HeaderItem(:final workspace) => workspace.id == target,
        _RowItem(:final tab) => tab.id == target,
        _EmptyItem() => false,
      };
      if (matches) {
        found = top;
````

with:

````dart
      final matches = switch (item) {
        _HeaderItem(:final workspace) => workspace.id == target,
        _RowItem(:final tab) => tab.id == target,
        _EmptyItem() || _ToolsItem() => false,
      };
      if (matches) {
        found = top;
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
    final state = ref.watch(terminalTabsProvider);
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final home = ref.watch(homeDirectoryProvider);
    // A8: rows' port tooltips say whether a server's port is forwarded.
    ref.watch(remotePortForwardsProvider);
    registerRowActionOrder(l10n);
````

with:

````dart
    final state = ref.watch(terminalTabsProvider);
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final home = ref.watch(homeDirectoryProvider);
    // V2-3 D21: the tool rows follow the tools and their folding.
    ref.watch(toolRegistryProvider);
    ref.watch(toolGroupsFoldedProvider);
    // A8: rows' port tooltips say whether a server's port is forwarded.
    ref.watch(remotePortForwardsProvider);
    registerRowActionOrder(l10n);
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
              padding: EdgeInsets.only(top: gap, left: indent),
              child: empty(item),
            ),
          },
        );
      },
````

with:

````dart
              padding: EdgeInsets.only(top: gap, left: indent),
              child: empty(item),
            ),
            _ToolsItem(:final workspaceId, :final tools) => Padding(
              padding: EdgeInsets.only(top: gap, left: indent),
              child: ToolSidebarGroup(workspaceId: workspaceId, tools: tools),
            ),
          },
        );
      },
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
            descendantsAreTraversable: false,
            child: const AiIntroCard(),
          ),
          // V2-1 D5: "New AI session" at the foot of the sidebar. Not a Tab
          // stop (⌘⇧E is the keyboard's way): Tab keeps going sidebar →
          // strip → terminal.
          FocusTraversalGroup(
            descendantsAreTraversable: false,
            child: Padding(
````

with:

````dart
            descendantsAreTraversable: false,
            child: const AiIntroCard(),
          ),
          // V2-1 D5: "New AI session" at the foot of the sidebar, and V2-3
          // D21 "Add tool" beside it. Not Tab stops (⌘⇧E and the palette are
          // the keyboard's ways): Tab keeps going sidebar → strip → terminal.
          FocusTraversalGroup(
            descendantsAreTraversable: false,
            child: Padding(
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
                ShellxSpace.s8,
                ShellxSpace.s8,
              ),
              child: Tooltip(
                message: switch (newAiSessionShortcutLabel()) {
                  final shortcut? => l10n.aiNewSessionTooltip(shortcut),
                  null => l10n.aiNewSession,
                },
                child: TextButton.icon(
                  key: const Key('sidebar.newAi'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: ShellxDesktopColors.textSecondary,
                  ),
                  onPressed: () =>
                      Actions.maybeInvoke(context, const NewAiSessionIntent()),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: Text(l10n.aiNewSession),
                ),
              ),
            ),
          ),
````

with:

````dart
                ShellxSpace.s8,
                ShellxSpace.s8,
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Tooltip(
                      message: switch (newAiSessionShortcutLabel()) {
                        final shortcut? => l10n.aiNewSessionTooltip(shortcut),
                        null => l10n.aiNewSession,
                      },
                      child: TextButton.icon(
                        key: const Key('sidebar.newAi'),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: ShellxDesktopColors.textSecondary,
                        ),
                        onPressed: () => Actions.maybeInvoke(
                          context,
                          const NewAiSessionIntent(),
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 14),
                        label: Text(
                          l10n.aiNewSession,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: TextButton.icon(
                      key: const Key('sidebar.addTool'),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: ShellxDesktopColors.textSecondary,
                      ),
                      onPressed: () =>
                          Actions.maybeInvoke(context, const AddToolIntent()),
                      icon: const Icon(Icons.extension_outlined, size: 14),
                      label: Text(
                        l10n.toolAdd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
````

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

````dart
  const _EmptyItem(this.workspaceId);
  final String workspaceId;
}
````

with:

````dart
  const _EmptyItem(this.workspaceId);
  final String workspaceId;
}

/// V2-3 D21: a workspace's "Tools" group, after its rows.
final class _ToolsItem extends _Item {
  const _ToolsItem(this.workspaceId, this.tools, {required this.folded});
  final String workspaceId;
  final List<ToolEntry> tools;
  final bool folded;
}
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/ui/tools/tool_sidebar_group.dart lib/src/ui/terminal/session_sidebar.dart test/ui/tools/tool_sidebar_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools test/ui/terminal
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_sidebar_test.dart` +5, all passed.
- Every `test/ui/terminal` test still passes, the sidebar's own included: a workspace without tools has no group, and the footer's "New AI session" keeps its key.
- `No issues found!`
- The whole suite: `3787 passed, 9 skipped`.

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/src/ui/tools/tool_sidebar_group.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart \
  apps/desktop/test/ui/tools/tool_sidebar_test.dart
git commit -m "feat(v2-tools): a Tools group under each workspace in the sidebar, and Add tool beside New AI session

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 15: Settings › Projects — each project's tools, clearing tool data, where tools open

D22 on the Projects page.

**Each project card** ends with its tools (`ToolProjectList`, with the "Tool" caption).
- **Rows:** one per tool (`settings.tool.<id>`): the name and the URL, and the phone switch `settings.tool.<id>.phone`. The switch is off with D15's reason for a tool a phone may not open.
- **Buttons:** Open `…open`, Edit `…edit`, Delete `…delete`.
- **Add:** "Add tool" (`settings.project.<id>.addTool`) adds without opening (ruling R20).

**The end of the page:**
- `ActionRow` `settings.tools.clear`: "Dữ liệu của tool" with the button "Xoá dữ liệu của tool…". It asks first ("Đăng xuất mọi tool và xoá cookie, bộ nhớ của chúng?", with the note "Tool vẫn còn; bạn đăng nhập lại vào chúng." and the button "Xoá"), then clears the one store every tool shares (D8). A failure logs only its type.
- `settingWidget(settingById('tool-embed'))`: "Hiện tool trong ShellX", with Tự động / Luôn / Không, mở bằng trình duyệt (Task 7's `SettingDef`).

**Files:**
- Create: `apps/desktop/lib/src/ui/tools/tool_project_list.dart`
- Modify: `apps/desktop/lib/src/ui/settings/pages/projects_page.dart`. Its third hunk below is `dart format` joining a `Key(…)` that `main` left over three lines.
- Test: `apps/desktop/test/ui/tools/tool_settings_test.dart`

**Interfaces:**
- Consumes:
  - Task 1: `toolRegistryProvider`;
  - Task 10: `toolDataStoreProvider`;
  - Task 12: `ToolActions` (`open`, `add`, `edit`, `delete`, `togglePhone`) and `ToolRig`;
  - Task 7: `settingById('tool-embed')`;
  - existing: `windowRouterProvider` (`confirm(ConfirmRequest)`), `ActionRow`, `settingWidget`, `ShellxText`, `ShellxDesktopColors`.
- Produces:
  - `class ToolProjectList extends ConsumerWidget`, built with `ToolProjectList({Key? key, required String workspaceId})`;
  - `Future<void> confirmClearToolData(WidgetRef ref, AppLocalizations l10n)`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/tools/tool_settings_test.dart`:

````dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../../support/config_workspace.dart';
import '../../support/tool_harness.dart';

Future<void> openProjects(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.projects')));
  await t.pumpAndSettle();
}

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  testWidgets('a project card lists its tools: the phone switch, edit, '
      'open, and "Add tool" (D22)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    final b = rig.add(kDefaultWorkspaceId, 'https://x.dev', name: 'Docs');
    await t.pumpAndSettle();
    await openProjects(t);
    expect(find.byKey(Key('settings.tool.${a.id}')), findsOneWidget);
    expect(
      t
          .widget<Switch>(find.byKey(Key('settings.tool.${b.id}.phone')))
          .onChanged,
      isNull,
      reason: 'D15: https is not for phones',
    );
    await t.tap(find.byKey(Key('settings.tool.${a.id}.phone')));
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolRegistryProvider.notifier).byId(a.id)!.phone,
      isTrue,
    );
    await t.tap(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.addTool')),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tool.dialog.url')), 'localhost:9');
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    expect(rig.container.read(toolRegistryProvider), hasLength(3));
    expect(find.byType(SettingsOverlay), findsOneWidget, reason: 'stays');
    await t.tap(find.byKey(Key('settings.tool.${a.id}.open')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsNothing);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('"Clear tool data…" asks, then clears the one store (D8, '
      'D22); the tool-embed row is there', (t) async {
    await rig.pump(t);
    await openProjects(t);
    await t.ensureVisible(find.byKey(const Key('settings.tools.clear')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('row.tool-embed')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('settings.tools.clear')),
        matching: find.byType(OutlinedButton),
      ),
    );
    await t.pumpAndSettle();
    final confirm = rig.container.read(windowRouterProvider).confirm!;
    expect(
      confirm.title,
      'Sign every tool out and clear its cookies and storage?',
    );
    confirm.complete(true);
    await t.pumpAndSettle();
    expect(rig.data.clears, 1);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
````

- [ ] **Step 2: Run it to see it fail**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools/tool_settings_test.dart
````

Expected: the tests compile and fail on their finders: no `settings.tool.…` row and no `settings.tools.clear` (`Found 0 widgets with key …`).

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/tools/tool_project_list.dart`:

````dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../tools/tool_pages.dart';
import '../../tools/tool_registry.dart';
import '../terminal/terminal_intents.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'tool_actions.dart';

/// D22: a project card's tools — name, URL, the phone flag, open, edit,
/// delete — and "Add tool".
class ToolProjectList extends ConsumerWidget {
  const ToolProjectList({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actions = ToolActions(ref);
    final tools = [
      for (final t in ref.watch(toolRegistryProvider))
        if (t.ws == workspaceId) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.toolsGroup,
          style: ShellxText.caption.copyWith(
            color: ShellxDesktopColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final t in tools)
          Row(
            key: Key('settings.tool.${t.id}'),
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      t.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: t.phoneAllowed
                    ? l10n.toolDialogPhone
                    : l10n.toolPhoneOnlyLocal,
                child: Switch(
                  key: Key('settings.tool.${t.id}.phone'),
                  value: t.phoneOn,
                  onChanged: t.phoneAllowed
                      ? (_) => actions.togglePhone(t)
                      : null,
                ),
              ),
              IconButton(
                key: Key('settings.tool.${t.id}.open'),
                tooltip: l10n.toolMenuOpen,
                icon: const Icon(Icons.extension_outlined, size: 18),
                onPressed: () =>
                    Actions.maybeInvoke(context, OpenToolIntent(t.id)),
              ),
              IconButton(
                key: Key('settings.tool.${t.id}.edit'),
                tooltip: l10n.toolMenuEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => unawaited(actions.edit(context, t)),
              ),
              IconButton(
                key: Key('settings.tool.${t.id}.delete'),
                tooltip: l10n.toolMenuDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => unawaited(actions.delete(t)),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: Key('settings.project.$workspaceId.addTool'),
            onPressed: () => unawaited(actions.add(context, workspaceId)),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.toolAdd),
          ),
        ),
      ],
    );
  }
}

/// D22: "Clear tool data…": asks, then signs every tool out (one store,
/// D8).
Future<void> confirmClearToolData(WidgetRef ref, AppLocalizations l10n) async {
  final yes = await ref
      .read(windowRouterProvider.notifier)
      .confirm(
        ConfirmRequest(
          title: l10n.toolClearDataConfirm,
          body: l10n.toolClearDataNote,
          confirmLabel: l10n.toolClearDataAction,
        ),
      );
  if (!yes) return;
  try {
    await ref.read(toolDataStoreProvider).clearAll();
  } on Object catch (error) {
    debugPrint('tool data not cleared (${error.runtimeType})');
  }
}
````

In `apps/desktop/lib/src/ui/settings/pages/projects_page.dart`, replace:

````dart
import '../../../../l10n/app_localizations.dart';
import '../../../terminal/sidebar_workspaces.dart';
import '../../theme/shellx_desktop_theme.dart';
import 'page_parts.dart';

/// Projects (cmux gap 36): a prominent place to create, name and fold the
````

with:

````dart
import '../../../../l10n/app_localizations.dart';
import '../../../terminal/sidebar_workspaces.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../../tools/tool_project_list.dart';
import 'page_parts.dart';

/// Projects (cmux gap 36): a prominent place to create, name and fold the
````

In `apps/desktop/lib/src/ui/settings/pages/projects_page.dart`, replace:

````dart
            name: w.displayName(l10n),
            tabCount: state.tabsOf(w.id).length,
          ),
      ],
    );
  }
````

with:

````dart
            name: w.displayName(l10n),
            tabCount: state.tabsOf(w.id).length,
          ),
        // V2-3 D22: the tools' data, and where tools open.
        ActionRow(
          key: const Key('settings.tools.clear'),
          label: l10n.toolDataLabel,
          button: l10n.toolClearData,
          onPressed: () => confirmClearToolData(ref, l10n),
        ),
        settingWidget(settingById('tool-embed')),
      ],
    );
  }
````

In `apps/desktop/lib/src/ui/settings/pages/projects_page.dart`, replace:

````dart
                Tooltip(
                  message: l10n.settingsProjectDelete,
                  child: IconButton(
                    key: Key(
                      'settings.project.${widget.workspace.id}.delete',
                    ),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _notifier.delete(widget.workspace.id),
                  ),
````

with:

````dart
                Tooltip(
                  message: l10n.settingsProjectDelete,
                  child: IconButton(
                    key: Key('settings.project.${widget.workspace.id}.delete'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _notifier.delete(widget.workspace.id),
                  ),
````

In `apps/desktop/lib/src/ui/settings/pages/projects_page.dart`, replace:

````dart
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
````

with:

````dart
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
          // V2-3 D22: the project's tools.
          const SizedBox(height: 8),
          ToolProjectList(workspaceId: widget.workspace.id),
        ],
      ),
    );
````

- [ ] **Step 4: Run the tests**

````bash
cd apps/desktop
~/fvm/versions/3.41.4/bin/dart format lib/src/ui/tools/tool_project_list.dart lib/src/ui/settings/pages/projects_page.dart test/ui/tools/tool_settings_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools test/ui/settings
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
````

Expected:
- `tool_settings_test.dart` +2, and every `test/ui/tools` and `test/ui/settings` test (the Projects page's own included), all passed.
- `No issues found!`
- The whole suite: `3789 passed, 9 skipped`.

- [ ] **Step 5: Commit**

````bash
git add apps/desktop/lib/src/ui/tools/tool_project_list.dart apps/desktop/lib/src/ui/settings/pages/projects_page.dart \
  apps/desktop/test/ui/tools/tool_settings_test.dart
git commit -m "feat(v2-tools): Settings › Projects lists each project's tools; clear tool data; where tools open

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````


### Task 16: Finish — full verification, compatibility, privacy sweep, builds, ledger

Everything is checked here locally, and the result goes into the ledger. **Nothing is pushed.** A push to `main` releases the desktop app, so the controller does every push. After this task, the controller pushes the branch to `windows-check/v2-3`, and the user reads the Windows CI result (the build only CI can try, D7 and spec §13).

**Files:**
- Modify: `docs/superpowers/ledgers/v2-tools.md`
- No product code unless a check fails. A fix goes in its own commit, `fix(v2-tools): …`, with a test.

**Interfaces:**
- Consumes: everything.
- Produces: a green `v2-3` branch, ready for the controller to merge into `shellx-v2`.

- [ ] **Step 1: Full analyze and test run**

From the worktree root:

````bash
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
(cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test 2>&1 | tail -1) || echo "FAIL agent"
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1) || echo "FAIL desktop"
git diff --stat $(git merge-base HEAD shellx-v2) -- packages/shellx_core packages/shellx_ai packages/shellx_acp packages/shellx_client apps/mobile relay agent-skills
````

Expected:
- No `FAIL` line, and `No issues found!` twice.
- `shellx_agent` `921 passed`; desktop `3789 passed, 9 skipped`.
- The last `git diff --stat` prints nothing: no package outside the scope changed.

- [ ] **Step 2: Compatibility and the Review Focus tests (mandatory)**

````bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/tool_dock_restore_test.dart test/restore/ai_tabs_restore_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_registry_test.dart --plain-name "Review Focus 4"
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/tools/tool_dock_ui_test.dart --plain-name "Review Focus 1"
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/tools/tool_keys_test.dart test/tools/tool_page_test.dart test/tools/tool_entry_test.dart test/tools/tool_navigation_test.dart
````

Expected: every test passes. Together they pin the five Review Focus lines:
- old builds keep every tab (V1, V2.0);
- tools never touch the workspace list;
- one engine through tab, palette and size changes;
- the forwarded chords;
- the server coming up;
- odd URLs and schemes.

- [ ] **Step 3: Privacy and safety sweep (spec §7, D9, D16, D24)**

````bash
cd apps/desktop
grep -rn "print(\|debugPrint(" lib/src/tools lib/src/browser lib/src/ui/tools | grep -v "runtimeType" || echo "no content logged"
grep -rn "runJavaScript\|addJavaScriptChannel\|addUserScript\|evaluateJavaScript\|takeSnapshot\|callAsyncJavaScript" lib/src/tools lib/src/browser macos/Runner || echo "no bridge"
grep -n "NSAllowsArbitraryLoads" macos/Runner/Info.plist || echo "no arbitrary loads"
grep -rn "Claude Code" lib/l10n/app_en.arb lib/l10n/app_vi.arb | grep -i "tool" || echo "no Claude Code in tool strings"
grep -rn "allow()\|\.grant(" lib/src/browser lib/src/tools || echo "no permission granted"
git diff "$(git merge-base HEAD shellx-v2)" -- pubspec.yaml | grep "^[-+]version" || echo "version unchanged"
````

Expected:
- `no content logged`: the only log lines print an error's `runtimeType`;
- `no bridge`, `no arbitrary loads`, `no Claude Code in tool strings`, `no permission granted`, `version unchanged`.

Investigate any other output.

- [ ] **Step 4: macOS build (no launch)**

````bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug
sed -i '' 's/^COCOAPODS: .*/COCOAPODS: 1.16.2/' macos/Podfile.lock && git status --short macos
````

Expected: `✓ Built build/macos/Build/Products/Debug/ShellX.app`; `git status` shows no change under `macos/`.

- [ ] **Step 5: The real engine again (Task 6's isolated recipe)**

Run Task 6 Step 3's recipe unchanged on the finished branch.

Expected: `+9: All tests passed!`; `ls` shows `pro.shellx.desktop.itest`.

- [ ] **Step 6: An isolated smoke launch of the whole app**

The same isolation as Task 6: a throw-away worktree, the bundle id `pro.shellx.desktop.itest` and a temporary HOME. This time it builds the real app (no `-t`) and keeps it up for 20 s. Then it stops the app, and any child the app started, by PID only.

````bash
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/shellx-smoke.XXXXXX")
git worktree add --detach "$SCRATCH/wt" HEAD
(
  cd "$SCRATCH/wt"
  PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get > /dev/null
  sed -i '' 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.itest/' \
    apps/desktop/macos/Runner/Configs/AppInfo.xcconfig
  grep -q '^PRODUCT_BUNDLE_IDENTIFIER = pro.shellx.desktop.itest$' apps/desktop/macos/Runner/Configs/AppInfo.xcconfig \
    || { echo 'bundle id not changed: stop'; exit 1; }
  cd apps/desktop
  PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug || exit 1
  mkdir -p "$SCRATCH/home"
  HOME="$SCRATCH/home" CFFIXED_USER_HOME="$SCRATCH/home" \
    build/macos/Build/Products/Debug/ShellX.app/Contents/MacOS/ShellX > "$SCRATCH/smoke.log" 2>&1 &
  PID=$!
  python3 - "$PID" <<'EOF'
import os, signal, subprocess, sys, time
pid = int(sys.argv[1])
time.sleep(20)
children = subprocess.run(['pgrep', '-P', str(pid)], capture_output=True, text=True).stdout.split()
for p in [*map(int, children), pid]:  # only what this recipe started
    try:
        os.kill(p, signal.SIGTERM)
    except ProcessLookupError:
        pass
EOF
  grep -iE "exception|error|failed" "$SCRATCH/smoke.log" | head -20
)
git worktree remove --force "$SCRATCH/wt" && rm -rf "$SCRATCH"
````

Expected: the `grep` prints at most the existing `restore: backup exclusion failed (TimeoutException)` / `ShellX: AI backup exclusion failed (TimeoutException)` lines (Time Machine exclusion under a temporary HOME). Anything else is a finding: fix it with a test.

- [ ] **Step 7: Ledger**

Append to `docs/superpowers/ledgers/v2-tools.md` under `## V2-3 (tools, desktop) — execution`:
- per-task commits and test counts, with the final counts of Step 1;
- Steps 2–6 results: compatibility, sweep, macOS build, the isolated integration test and the smoke launch;
- any ruling the implementers made beyond R1–R28, one line each with its cost if wrong;
- "Windows: the controller pushes `windows-check/v2-3`; result pending (the user reads it)";
- the manual checks of spec §11.1 (macOS, 9 items) and §11.2 (Windows with `tool-embed = on`, 5 items), each marked "pending manual". Passing §11.2 is what flips `auto` to embed on Windows: one line in `toolsEmbedded`, with its test;
- follow-ups:
  - `agent-skills/`: tell agents that tools exist (ruling R19);
  - V2-4 (tools on the phone) consumes Task 1's interface;
  - A6's full browser can resume on this engine (D6).

- [ ] **Step 8: Commit**

````bash
git add docs/superpowers/ledgers/v2-tools.md
git commit -m "docs(v2-tools): V2-3 ledger — results, compatibility, sweep, isolated runs, manual checks pending

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
````

Do not push. Tell the controller the branch is ready, and that the Windows build waits on its `windows-check/v2-3` push.

---

## Self-review (done while writing)

- **Spec coverage:**
  - D1 URL rules: Task 1 (Review Focus 5), Task 12 (the dialog's red line).
  - D2 storage: Task 1 (`workspace_tools`, limits, workspace deletion via Task 8).
  - D3 the dock: Tasks 8 (state, layout), 13 (column, handle, zoom, Esc).
  - D4 opening: Tasks 12 (`ToolActions.open`, loose), 13 (AI header, palette, closing the Changes panel), 14 (sidebar), 15 (Settings).
  - D5 chips and 8 pages: Tasks 8, 10, 13.
  - D6 the engine from A6: Task 3; its review: Task 5; real WebKit: Task 6.
  - D7 Windows and `tool-embed`: Task 7; the stand-in: Task 13; the CI build: the controller after Task 16.
  - D8 data: Tasks 3 (macOS store), 7 (Windows folder and profile), 15 (clear).
  - D9 navigation, new windows, downloads, permissions, JS dialogs: Tasks 5, 6, 10, 12, 13.
  - D10 keys and focus: Tasks 4, 5, 10, 13.
  - D11 the mark: Tasks 1, 13.
  - D12 suggestions: Tasks 11, 12, 14 (criterion 1).
  - D13 errors and retries: Tasks 5 (kinds), 7 (Windows kinds), 10 (schedule, knock, crash), 13 (panels).
  - D14 restore: Tasks 8, 9, 10 (no load before shown).
  - D15 the phone flag: Tasks 1, 12, 13, 14, 15.
  - D16 no bridge: Tasks 3, 5 (scan).
  - D17 the bar: Task 13. D18 accessibility: Tasks 13, 14.
  - D19 ATS: Tasks 3 (plist), 5 (−1022), 6 (127.0.0.1).
  - D20 not embedded: Tasks 7, 12, 13, 14.
  - D21 sidebar: Task 14. D22 Settings: Tasks 7, 15. D23 edit and delete: Tasks 10, 12, 14.
  - D24 privacy: every task (`Name(…)` `toString`, Task 16 sweep).
  - §8 edges: Tasks 1, 8, 9, 10, 13.
  - §9 tests: Tasks 1–15.
  - §10 Review Focus: pinned above.
  - §11 manual checks: the Task 16 ledger.
- **Left out by design (spec §12):** tools on the phone (V2-4); agents seeing or driving tools (`ui.browser.*`); A6's full browser; downloads; a cookie store per tool; SSH workspaces through forwarding; two tools side by side.
- **Placeholders:** none. Every code block is the code that ran in the scratch worktree, and every replace block was generated from it and replayed.
- **Names across tasks:**
  - `ToolEntry`/`parseToolUrl`/`ToolRegistry` (Task 1), used by every later task and by V2-4;
  - `BrowserEngine` and the events (Task 3), used by Tasks 5, 6, 7, 10, 13;
  - `toolNavigation`/`toolForwardedChords`/`resolveToolChord`/`KeySequence.arm` (Task 5), used by Tasks 6, 10, 13;
  - `toolsEmbeddedProvider` (Task 7), used by Tasks 12, 13, 14;
  - `ToolDockState`/`toolDockProvider` (Task 8), used by Tasks 9, 10, 12, 13, 14;
  - `ToolPage`/`toolPagesProvider`/`toolEngineFactoryProvider`/`toolDataStoreProvider` (Task 10), used by Tasks 12, 13, 15;
  - `toolPortSuggestionsProvider`/`ListeningScan` (Task 11), used by Task 12;
  - `ToolActions`/`showToolDialog`/`ToolRig` (Task 12), used by Tasks 13, 14, 15.
- **Ordering:** 1 → 2 → … → 16, each task green on its own. Task 6 needs Task 5. Task 12 needs Tasks 8, 10 and 11. Task 13 needs Tasks 4, 5, 8, 10 and 12.

