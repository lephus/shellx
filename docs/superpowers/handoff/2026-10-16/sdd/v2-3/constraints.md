# V2-3 constraints for every implementer and reviewer (read completely)

Worktree: /Users/richard/Documents/helper/shellx/.claude/worktrees/v2-3 (branch v2-3). Run every command from there (cd into it for every command). Never touch MAIN's files (except writing your report into the SDD workspace) or any other worktree (.claude/worktrees/v2-2b, v2-4).

## A. Session-wide global constraints (binding)


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


## B. The plan's own Rulings and Global Constraints (verbatim from the plan, lines 77–205)

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

## C. Controller rulings that refine A and B (binding; recorded in the SDD ledger)

- `SCRATCH` = `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad` (the session scratchpad; the only temp root outside the repo you may write).
- Launches / the macOS integration test: use the PLAN's Task 6 recipe (bundle id `pro.shellx.desktop.itest`, temporary `HOME` and `CFFIXED_USER_HOME`), not the smoke copy named in A — with these changes: the temporary folder is made under `SCRATCH` (`mktemp -d "$SCRATCH/shellx-itest.XXXXXX"`), never under `${TMPDIR}` or `/tmp`; `git worktree remove --force` is allowed ONLY on the throw-away worktree path that the same recipe run created (never any other path, never `git worktree prune`); after the run, confirm the PID you started has exited (`kill -0 <pid>` fails) and, only if it is still alive, `kill -9` that one PID. Never `flutter test -d macos`, never `flutter test integration_test/…`, never `flutter run`.
- Suite counts: this worktree has no macOS build until Task 3 Step 7. Before that build, expect the plan's desktop `flutter test` count minus one passed and plus one skipped (`test/terminal_sharing/end_to_end_macos_test.dart`). Baseline measured at eb0b6dc: desktop `+3574 ~10`, shellx_agent `+916`, both analyzers clean.
- Known timing-flaky files when the machine is busy (other tracks run tests concurrently): `test/terminal/global_search_test.dart`, `test/terminal/terminal_search_test.dart`, `test/ui/find_reconnect_test.dart`. Re-run such a file alone once before treating a failure as yours; mention it in your report.
- Commit trailer: your own model's (A), even where the plan's commit text shows Opus.
- Never `git add` anything outside the task's Files list (plus `docs/superpowers/ledgers/v2-tools.md` where the task's steps append to it). Use explicit paths with `git add`, never `git add -A` / `git add .`.

## D. Chunk 2 (Tasks 7–12) additions (binding; recorded in the SDD ledger)

- **Foreground only.** Run every test, analyze and build command in the foreground (Bash timeout up to 600000 ms; if a suite would take longer, split it by directory). Never use `run_in_background`, and never end your turn while a command you started is still running. End your run only by delivering your report.
- **Suite totals.** From Task 5 on, the desktop whole-suite totals in this worktree are the plan's numbers **+5** (five tests added by reviewed fixes in Tasks 1, 2 and 5 — a top-level controller ruling), with 9 skipped (the worktree has a macOS build). So a task's expected whole-suite total = the plan's total for that task + 5 + any tests the controller's rulings for that task add. `packages/shellx_agent` is unchanged so far (baseline `+916`).
- **Known timing-flaky files** (other tracks run Flutter tests on this machine at the same time): `test/terminal/global_search_test.dart`, `test/terminal/terminal_search_test.dart`, `test/ui/find_reconnect_test.dart`, `test/terminal/find_session_test.dart`. A timeout-only failure is re-run alone once before it counts; mention it in your report.
- **No launches in Tasks 7–12.** None of these tasks requires launching the app, a macOS build or the integration test: never `flutter run`, `flutter test -d macos`, `flutter test integration_test/…`, or `flutter build …` in this chunk.
- **Real-home preferences.** Never read, write or delete anything under `~/Library/Preferences/` (in particular `pro.shellx.desktop.plist`, the user's real domain, and any `pro.shellx.desktop.*` test plist).
- **Windows-only code** is checked here only by `flutter analyze` and unit tests with fakes; the Windows build runs on CI after the last chunk (the top-level controller pushes; you never push).
- **Other plans' ledgers.** V2-3's ledger doc is `docs/superpowers/ledgers/v2-tools.md`; Tasks 7–12 do not append to it (only Tasks 1, 5, 6, 16 do). Never write `docs/superpowers/ledgers/v2-ai.md` or `v2-4-tools-phone.md`.
- **Scratch hygiene (added after an incident in Task 12).** The scratchpad (`SCRATCH`) is shared with other tracks. Make your own scratch folder fresh and unique (`mktemp -d "$SCRATCH/v2-3-<task>-XXXX"`), keep backups and throw-away files only there, and delete only what you created. Never `rm -rf` a path you did not create in this run.

## E. Chunk 3 (Tasks 13–16 and the final review) — binding; supersedes D where they differ

- **Foreground only (verbatim, harness note).** Run every test, analyze and build command in the foreground (Bash timeout up to 600000 ms; if a suite would take longer, split it by directory). Never use `run_in_background`, and never end your turn while a command you started is still running. End your run only by delivering your report.
- **Scratch hygiene (verbatim).** Make your own temp folder with `mktemp -d "$SCRATCH/tmp.XXXXXX"` (SCRATCH as given), keep every temporary file (backups, mutation copies, logs) inside it, and remove only that folder. Never `rm -rf` or overwrite a path you did not create in this dispatch, and never write loose files at the SCRATCH root.
- **Suite totals.** From Task 12 on, the desktop whole-suite totals in this worktree are the plan's numbers **+46** (tests added by reviewed rulings and fixes in chunks 1–2), with 9 skipped. A task's expected total = the plan's total for that task + 46 + the tests the controller's rulings for chunk 3 add (the dispatch states the number). `packages/shellx_agent` has no offset (921).
- **Known timing-flaky files** (other tracks run Flutter tests on this machine at the same time): `test/terminal/global_search_test.dart`, `test/terminal/terminal_search_test.dart`, `test/ui/find_reconnect_test.dart`, `test/terminal/find_session_test.dart`. A timeout-only failure is re-run alone once before it counts; mention it in your report.
- **Builds and launches.** Task 13 Step 7 and Task 16 Step 4 build the macOS app in the worktree (`flutter build macos --debug`, no launch); afterwards put back the `COCOAPODS:` line of `apps/desktop/macos/Podfile.lock`. The only launches in this chunk are Task 16 Steps 5–6 (the isolated recipe, rulings F4–F6 in section C). Never `flutter run`, `flutter test -d macos`, `flutter test integration_test/…`.
- **Real-home preferences.** Never read the contents of, write, or delete anything under `~/Library/Preferences/`; never run `defaults` on any `pro.shellx.desktop*` domain. `pro.shellx.desktop` is the user's real domain: never touch it. Task 16 alone lists metadata (`ls -lT ~/Library/Preferences/pro.shellx.desktop.*.plist` — this glob never matches the real `pro.shellx.desktop.plist`; name, size, mtime only) before and after its isolated runs and reports any new or changed file.
- **Windows-only code** is checked here only by `flutter analyze` and unit tests with fakes; the Windows build runs on CI after the last chunk (the top-level controller pushes; you never push).
- **Ledger doc.** In chunk 3 only Task 16 appends to `docs/superpowers/ledgers/v2-tools.md`. Never write `docs/superpowers/ledgers/v2-ai.md` or `v2-4-tools-phone.md`.
- **No subagents.** Implementers and reviewers never dispatch subagents of any kind.
