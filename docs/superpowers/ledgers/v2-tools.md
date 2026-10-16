# V2 tools — execution ledger (branch v2-3, merged into shellx-v2 by the controller)

## V2-3 (tools, desktop) — execution

- Baseline at eb0b6dc (130d8aa plus the V2-3 plan commit; no apps/ or packages/ change): desktop analyze clean, `+3574 ~10`; shellx_agent analyze clean, `+916`.
<<<<<<< 7815f8faae7d46d4fcb006a58604eff0792a157b
- macOS engine review: #1 D9 top frame — fixed by `toolNavigation` (`lib/src/tools/tool_navigation.dart`) injected as the engine's `NavigationPolicy`: any http/https page and `about:blank` load, `mailto:`/`tel:` → `OpenOutside`, `file:`/`javascript:`/`data:`/unknown blocked without a word (test `tool_navigation_test` "the top frame…"; real WebKit in Task 6).
- macOS engine review: #2 D9 frames — fixed by `toolNavigation`'s frame rule: http/https/about/data/blob load, anything else is blocked (test `tool_navigation_test` "frames of the page…").
- macOS engine review: #3 D9 new windows — fixed by `NewWindowGuard` (BrowserNative.swift) in front of the plugin's UI delegate: no window, `newWindow` → `OpenOutside(newWindow: true)` for web/mail/phone, `NavigationBlocked` otherwise (R4) (tests `tool_navigation_test` "a new window never opens…", `wk_webview_engine_test` "BrowserNativeMac…"; real WebKit in Task 6).
- macOS engine review: #4 D9 downloads — fixed by `DownloadGuard` (BrowserNative.swift) in front of the plugin's navigation delegate: a top-frame attachment or a type WebKit cannot show is cancelled and sent as `download` → `DownloadBlocked(url)`; its own cancel (WebKitErrorDomain 102) shows nothing (tests `wk_webview_engine_test` "WebKit 100…", "BrowserNativeMac…"; real WebKit in Task 6).
- macOS engine review: #5 D13 errors — fixed by `macErrorEvent(domain, code, …)`: NSURLErrorDomain codes read with their domain, −1022 → `ats`, WebKitErrorDomain 102 → nothing and 100 → `DownloadBlocked`, a dead content process → `crashed` (tests `wk_webview_engine_test` "NSURLError codes…", "WebKit 100…").
- macOS engine review: #6 D9 permissions — fixed by `onPermissionRequest` → `deny` on the engine's `WebViewController` (camera, microphone); no location usage is declared and WKWebView gives apps no web notifications (test: Task 6's camera test, real WebKit).
- macOS engine review: #7 D10 chord spelling — fixed by `BrowserNative.chord`/`keyName` writing `chordConfigText`'s spelling (ctrl, alt, shift, super, key; named keys by key code, characters by `characters(byApplyingModifiers: [])`, punctuation by name) (test `tool_keys_test` "every forwarded chord reads back…" pins the Dart side; the Swift side has no automated test).
- macOS engine review: #8 D10 which chords — fixed by `toolForwardedChords(bindings)`: every window binding of the live keymap and every sequence's first step, minus `kToolPageActions` and cut/undo/redo (R7, R8) (tests `tool_keys_test` "the forwarded chords are the window keymap…", "the user's own keys count…").
- macOS engine review: #9 D10 sequences — fixed by `resolveToolChord` → `ToolChordPrefix` and `KeySequence.arm` (tests `tool_keys_test` "resolveToolChord…", "KeySequence.arm…").
- macOS engine review: #10 D10 focus — fixed by BrowserNative's mouse monitor: a click outside the page while the page has the keyboard makes the Flutter view first responder (no automated test: a native event monitor).
- macOS engine review: #11 ids — fixed by `attach`/`forget`: only attached ids are tool web views (`setForwardedChords` ignores any other id), `attach` installs the guards, `forget` puts the plugin's delegates back (test `wk_webview_engine_test` "BrowserNativeMac…": `attach` first, `forget` on `detach`).
- macOS engine review: #12 D16 — fixed by `tool_no_bridge_test.dart`, a source scan of `lib/src/browser`, `lib/src/tools`, `lib/src/ui/tools` and BrowserNative.swift for any script, channel or snapshot API (R3) (test `tool_no_bridge_test`).
- macOS engine review: #13 D8, D22 — unchanged, right per D8: `clearWebsiteData` clears `WKWebsiteDataStore.default()`, one store for every tool (test `wk_webview_engine_test` "BrowserNativeMac…": `clearAll` → `clearWebsiteData`).
- macOS engine review: #14 retry — unchanged here: the engine keeps `reload()` for ↻ on a loaded page; a failed first load retries with `load(url)` (R25, Task 10).
- macOS engine review: #15 inspector — fixed by `setInspectable(true)` at setup: Safari's Web Inspector reaches the user's own tool on macOS 13.3+ (R28) (test `wk_webview_engine_test` "the Web Inspector is best effort…").
- macOS engine review: #15 inspector best effort below macOS 13.3 (controller ruling, Task 3 Important 1) — fixed by `enableWebInspector`: a `PlatformException` from `setInspectable` is logged by its `runtimeType` only and never stops `_setup()`, so pages load on macOS 12.0–13.2 (test `wk_webview_engine_test` "the Web Inspector is best effort…"; the engine itself has no unit seam: its constructor makes a native WKWebView through the plugin).
- macOS engine review: no empty page URL (controller ruling, Task 3 Important 2) — fixed by `pageUriOf` (null for null, empty or scheme-less input): `UrlChanged` only for a URL with a scheme, and `macErrorEvent`'s `url`, the navigation request and the channel's `newWindow`/`download` URLs go through it too (test `wk_webview_engine_test` "a page URL from WebKit is a URL with a scheme or nothing…").
- macOS engine review: #18 new-window links (task review) — fixed by `DownloadGuard` taking a navigation action with no target frame (`target=_blank`, mail and phone links included) as a new window: cancelled, `newWindow` → `newWindowEvent` → `OpenOutside(newWindow: true)` or `NavigationBlocked`; frames still block mail and phone (test `wk_webview_engine_test` "a new window (window.open, or a target=_blank link)…"; real WebKit in Task 6).
- macOS engine review: #19 download-attribute downloads (task review) — fixed by `DownloadGuard` cancelling a navigation action that `shouldPerformDownload` (checked first) and sending `download` (no URL for `blob:`/`data:`) → `DownloadBlocked`; the response check stays (test `wk_webview_engine_test` "a page URL from WebKit…": a download without a URL; real WebKit in Task 6).
- macOS engine review: #20 chords on other layouts (task review, ruling amended) — fixed by porting Flutter's macOS layout map into BrowserNative.swift (`layoutMap`, `clue`: the pinned engine's FlutterKeyboardManager.mm `buildLayout` and FlutterKeyboardLayout.mm `lookUpLayoutForKeyCode`, built for the current input source and dropped when it changes): a typewriter key is named as Flutter names its logical key, including dead keys, the US punctuation goals and the last step that gives each letter or digit no key types to its US key; named keys go by key code; a key outside the map goes by its unshifted character, as before. US output is identical for all 128 key codes, and the map equals a literal transliteration of the engine's code on 16 system layouts (Hebrew ⌘T = t, Arabic ⌘⇧P = p and ⌘1…0 digits, Turkish F no shared letter) (no automated test: Swift).
- macOS engine review: #21 a disposed engine loads nothing (task review) — fixed by `_live()`: every public method that waits for setup makes no native call once the engine is disposed (no unit seam: the engine makes a native WKWebView).
- macOS engine review: #22 dispose stops the page (task review) — fixed by `forget` (dispose only) stopping the load and loading `about:blank`; the disposed engine reads nothing back from it and emits nothing (no automated test: native).
- Task 6 (2026-10-15): `flutter: 00:15 +12: All tests passed!` — integration test: isolated build, bundle id pro.shellx.desktop.itest, temporary HOME (plan Task 6 recipe) (`apps/desktop/integration_test/tool_engine_test.dart`; +3 cases from the Task 5 review: target=_blank mailto, blob download, same-origin download attribute).
- Task 16 (2026-10-16): `flutter: 00:22 +13: All tests passed!` — the same integration test at bfff4c0, isolated build, bundle id pro.shellx.desktop.itest, temporary HOME (plan Task 6 recipe with F4–F6) (+1 case: a refused load after a loaded page sends `LoadFailed(refused)` and no `LoadFinished` within 2 s, the premise of Task 10's recovery URL).

### Commits and test counts per task

- Task 1: eb0b6dc..54489b9 (f7bacfe, 54489b9) — tool_entry 48, tool_registry 10, settings_ownership 6; suite 3631/10 at f7bacfe, +1 test in 54489b9.
- Task 2: 54489b9..b509e58 (bdf117a, b509e58) — tool_strings 5, test/l10n 23; suite 3637/10 (before the first macOS build).
- Task 3: b509e58..b22a15d (b22a15d) — browser_url 53, wk_webview_engine 2; suite 3692/10, 3693/9 after the first macOS build.
- Task 4: b22a15d..d183362 (d183362) — keybindings +21, shortcut_golden +4; suite 3694/9.
- Task 5: d183362..84147e8 (9fef65d, 328dd40, e2e0be3, 84147e8) — test/browser + test/tools 127; macOS debug build, not launched; suite 3708/9.
- Task 6: 84147e8..bc1ec86 (42c767e, bc1ec86) — isolated run `+12: All tests passed!` at 42c767e and at bc1ec86.
- Task 7: bc1ec86..cd8f192 (cd8f192) — win_floating_engine 10, tool_embed +3, settings_schema +13; suite 3724/9.
- Task 8: cd8f192..7eed4f2 (4abdc1c, 7eed4f2) — tool_dock_state +10, tool_dock +9; suite 3742/9 at 4abdc1c, 3743 with 7eed4f2's test.
- Task 9: 7eed4f2..27818da (c37686a, 27818da) — tool_dock_restore +8; suite 3750/9 at c37686a, 3751 with 27818da's test.
- Task 10: 27818da..941c8f7 (a657251, 2fb86bd, 941c8f7) — tool_page 20, tool_pages 8; suite 3777/9 at 2fb86bd, 3779 with 941c8f7's tests.
- Task 11: 941c8f7..982c883 (f592f6d, 7ff50a9, 982c883) — shellx_agent listening_under +5 (package 921); tool_ports 15; suite 3785/9 at f592f6d, 3794 with the follow-up tests.
- Task 12: 982c883..004cb6d (efee9b5, 36ca72c, 004cb6d) — tool_dialog 17, url_opener_mail 3; suite 3802/9 at efee9b5, 3814 with the follow-up tests.
- Task 13: 004cb6d..b7cab3f (8116f9f, cd31077, 22865d2, 6ab6247, b7cab3f) — tool_dock_ui 21, tool_ai_header 1, win_floating_engine 11, test/ui 1238; macOS debug build, not launched; suite 3837/9.
- Task 14: b7cab3f..a7df506 (8fc7e86, f128aea, a7df506) — tool_sidebar 8, test/ui 1246; suite 3845/9.
- Task 15: a7df506..bc70258 (0d77cad, bc70258) — tool_settings 5, test/ui 1251; suite 3850/9.
- Task 16: bc70258..this ledger commit (bfff4c0, then the ledger) — tool_engine_test 11 cases (+1), isolated `+13`; no product code changed.
- Final counts (Task 16 Step 1, HEAD bfff4c0): desktop `flutter analyze` No issues found!; `flutter test` `01:52 +3850 ~9: All tests passed!` (the plan's 3789 + 61 tests added by reviewed rulings), after a first whole run of `+3849 ~9 -1` whose one failure was a timing flake (below); shellx_agent `dart analyze` No issues found!, `dart test` `+921: All tests passed!`; `git diff --stat eb0b6dc -- packages/shellx_core packages/shellx_ai packages/shellx_acp packages/shellx_client apps/mobile relay agent-skills` prints nothing (outside apps/desktop the branch changes only this ledger and shellx_agent's `listening_ports.dart` and its test).

### Results (Task 16, 2026-10-16)

- Compatibility and Review Focus (Step 2): `test/restore/tool_dock_restore_test.dart` + `test/restore/ai_tabs_restore_test.dart` `+16`; `test/tools/tool_registry_test.dart` "Review Focus 4" `+1`; `test/ui/tools/tool_dock_ui_test.dart` "Review Focus 1" `+2`; `tool_keys_test`, `tool_page_test`, `tool_entry_test`, `tool_navigation_test` `+76`. All passed: old builds keep every tab (V1, V2.0); tools never touch the workspace list; one engine through tab, palette and size changes; the forwarded chords; the server coming up; odd URLs and schemes.
- Privacy and safety sweep (Step 3): `no content logged`, `no bridge`, `no arbitrary loads`, `no Claude Code in tool strings`, `no permission granted`, `version unchanged` (against eb0b6dc). Beyond the six greps: the seven log lines the branch adds anywhere print only an error's `runtimeType`, and every `toString()` it adds prints a type and at most a kind, a count or flags. No finding, no fix.
- macOS build (Step 4): `flutter build macos --debug` → `✓ Built build/macos/Build/Products/Debug/ShellX.app`, not launched; the `COCOAPODS:` line put back; nothing under `macos/` in `git status`.
- Isolated real-engine run (Step 5): the Task 16 line above. Bundle id `pro.shellx.desktop.itest` in the throw-away worktree's xcconfig and in the built app (PlistBuddy) before the launch; the app's PID had exited after the SIGTERM, no kill needed; WebKit's data went to the temporary HOME (`Library/WebKit/pro.shellx.desktop.itest`); the throw-away worktree and its folder removed.
- Isolated smoke launch of the whole app (Step 6): the real app (no `-t`) built in a throw-away worktree of bfff4c0, bundle id `pro.shellx.desktop.itest` checked in the xcconfig and in the built app, temporary HOME, up for 20 s, then SIGTERM to its one direct child (`/bin/zsh`) and to the app: both had exited, no kill needed, and no process ran from the throw-away worktree afterwards. The log's `grep -iE "exception|error|failed"` shows only `restore: backup exclusion failed (TimeoutException)` and `ShellX: AI backup exclusion failed (TimeoutException)` (twice): Time Machine exclusion under a temporary HOME, as expected.
- Real-home metadata (`ls -lT ~/Library/Preferences/pro.shellx.desktop.*.plist` before Step 5 and after Step 6; names, sizes and mtimes only): `pro.shellx.desktop.itest.plist` 244 B, Oct 15 12:09:41 2026, and `pro.shellx.desktop.smoketest.plist` 178 B, Oct 14 21:56:51 2026, both unchanged; no new file. `~/Library/{WebKit,Caches,HTTPStorages}/pro.shellx.desktop.itest` exist neither before nor after.
- Timing flake (not among the plan's known timing-flaky files): `test/ui/find_bar_test.dart` "opens focused; typing counts matches "3 of 3"" failed once in the first whole run (count empty) and passed alone (`+7`) and in the second whole run. `FindSession` reads the buffer in 4 ms wall-clock slices; when the first slice does not finish under load, the rest waits for the 150 ms query debounce, which the test's single `pump()` never reaches. The branch touches neither the find bar, its session nor its test.

### Controller rulings beyond R1–R28

The controller's product-behaviour rulings made during execution, grouped by task, in the order they were made within a task (process and test-only rulings left out).

- Before Task 1 (F9): the plan's R7, R22, R23 and R24 stand where they differ from the spec's text (the page keeps its editing keys; a redacted `ToolEntry(…)`; V2-4 watches the provider; an isolated build with its own bundle id and HOME) — cost if wrong: as the plan states for each.
- Task 1: `parseToolUrl` refuses a port too large for an int (`ToolUrlBad(badPort)`), so `ToolEntry.fromJson` never throws and one damaged `workspace_tools` entry never empties the registry (spec §5, §8) — cost if wrong: none.
- Task 3: with the pinned webview_flutter_wkwebview 3.25.1, a cancelled or flood-answered `prompt()` reaches the page as `""`, not `null` (macOS; Windows keeps WebView2's own dialogs) — accepted as the plugin's limit — cost if wrong: a page that tells cancel from empty input reads a cancel as empty; the later fix is a native prompt panel (~50 lines and an isolated-run test).
- Task 3 (applied in Task 5): `setInspectable` is best effort — below macOS 13.3 its error is logged by `runtimeType` and setup goes on, so pages load on macOS 12.0–13.2 (spec §8) — cost if wrong: none.
- Task 3 (applied in Tasks 5 and 7): `UrlChanged` only for a URL with a scheme; a nil or empty URL from WebKit or WebView2 is never the page's address (D9, D17) — cost if wrong: none.
- Task 5: setup sends nothing native once the engine is disposed (no leaked, re-registered web view) — cost if wrong: none.
- Task 5: a navigation with no target frame (`target=_blank`, mail and phone links included) is a new window — cancelled, sent as `OpenOutside(newWindow: true)`; frames still block mail and phone (D9) — cost if wrong: none beyond a few native lines.
- Task 5: `download`-attribute downloads (`blob:`, `data:`, same-origin links) are cancelled and show D9's download line (`shouldPerformDownload`) — cost if wrong: none.
- Task 5: forwarded chords are named as Flutter names the logical key, so non-Latin and AZERTY-style layouts forward ShellX's chords; US output unchanged (D10, criterion 4) — cost if wrong: on an unusual layout a chord forwards differently from the terminal.
- Task 5: every public engine method makes no native call once disposed, so no hidden page runs without the D9 policy — cost if wrong: none.
- Task 5: dispose stops the page and loads `about:blank`, so an unloaded tool frees its scripts, sockets and audio (D5) — cost if wrong: none.
- Task 7 (F1): an empty data folder means no folder — no WebView2 starts and every call answers `unavailable` (D8) — cost if wrong: a few lines and one test for an environment (no LOCALAPPDATA) a real Windows session never has.
- Task 7: once disposed, `WinFloatingEngine` makes no plugin call, as on macOS — cost if wrong: a few lines and one test.
- Task 7: the plugin's `onPageFinished` after a failure is dropped (only `LoadFailed`); a 4xx/5xx page still ends with `LoadFinished`, as on macOS (D13) — cost if wrong: one flag; a failure never followed by a finish is cleared by the next start.
- Task 7: `_ready` never fails — a failed creation is logged once by `runtimeType`, every call then answers `LoadFailed(unavailable)`, and clearing data never throws because of a failed engine (§8) — cost if wrong: none.
- Task 7: the plugin's widget mounts only after a successful creation, and dispose frees the plugin's controller only after the view left the tree (no uncaught plugin errors) — cost if wrong: ~30 lines of Windows-only lifecycle code checked only by unit tests with the mock channel.
- Task 7: accepted known limitation — Windows D9 coverage is narrower than macOS: the plugin asks Dart only about user-initiated GET top-frame navigations and new windows, so redirects, POSTs and back/forward skip the policy (Chromium still blocks top-frame `file:`/`data:`; an external scheme reached by a redirect gets WebView2's own prompt) — cost if wrong: with `tool-embed = on`, a redirect to an external scheme shows WebView2's prompt instead of a silent block (manual check below).
- Task 8 (raised at Task 1): tools whose workspace no longer exists (deleted by an older build, or a damaged workspace list) are removed once at start: the dock controller drops every registry tool whose `ws` is not a loaded sidebar workspace (D2, §8) — cost if wrong: such a tool is deleted at the next start instead of staying invisible.
- Task 10 (raised at Task 5): R10's burst numbers also limit page-initiated outside opens — at most 5 per 10 s per page, extras dropped silently — cost if wrong: a 6th outside open within 10 s is dropped and the user clicks again.
- Task 10: dropped outside opens count toward that window, as dropped dialogs do (one shared helper) — cost if wrong: a looping page's next legitimate outside open waits for 10 s of calm.
- Task 10: the recovery URL is the one that failed — until a `LoadFinished`, every retry, R9 knock, crash reload and panel Reload loads the URL the app asked for (the new one after a D23 edit, the tool after "Về tool"); after it, the page's own address; a knock loads only if its target is still the recovery URL (D23, D9) — cost if wrong: a few lines; ↻ unchanged.
- Task 10: a crash before the asked-for load finished reloads what was asked; a crash after a committed page reloads the page's address — cost if wrong: a crash in the middle of a redirected first load restarts from the tool's URL.
- Task 10: ✕ ends the loading state, and ↻ after ✕ runs the pending load again with `load`, never `engine.reload()` (D17, R25) — cost if wrong: after ✕ of an edit, a later link failure retries the stopped URL (rare).
- Task 11: R12's runtime copy (F8) builds every desktop AI pane's runtime (the `AiHost.runtime` branch is unused in production); a tripwire test pins `AiHost.runtime`'s text and fails, naming the copy, when it changes — cost if wrong: one test that fails whenever `AiHost.runtime` changes (intended).
- Task 12: with embedding off, ⌘⇧B on a workspace with no tool adds one and then opens it in the browser (R20, D20) — cost if wrong: one browser open after adding through ⌘⇧B with embedding off.
- Task 13: R14 split by file — the window's tab selections end loose (⌘1…9 and the palette's tab entries, Next/Previous tab, the sidebar row's click, Enter and Space); the notification jump and the CLI `ui focus` were parked — cost if wrong: after a notification click on the tab selected underneath, loose stays until the user clicks the row (the jump was then fixed by the R14-gap ruling below).
- Task 13: `WinFloatingEngine` re-applies the last asked visibility after the plugin's widget mounts or re-activates, so a covered page stays hidden (D7) — cost if wrong: ~10 lines and one test in Task 7's file.
- Task 13: the loose panel has its own focus node, so closing a loose dock with no tab keeps the keyboard in ShellX (D10, D18) — cost if wrong: one more focus node and test.
- Task 13: a key that selects no tab (⌘9 with fewer tabs; Next/Previous with none visible) keeps loose (R14) — cost if wrong: ⌘9 with no ninth tab leaves loose on screen.
- Task 13: R14 gap — the notification jump (`TabAttention.jumpTo`), a search hit and a focus-history move also end loose; the CLI `ui focus` stays a deferred minor for the final review — cost if wrong: an agent's `ui focus` of the covered tab leaves loose on screen until the user clicks the row.
- Task 13: while loose, Swap/Join pane and the commands that act on the covered tab (Move to workspace, Pin, Close whole tab) are disabled and the move list is empty (R14) — cost if wrong: a palette command acts on a tab the user cannot see.
- Task 13: narrow windows — when an unzoomed dock would not show at the current width (content below 686 px, a window below ~907 px), a window entry point that opens a dock opens it expanded; Restore and Esc keep their meaning (spec §8) — cost if wrong: in a narrow window a tool opens full-width instead of not at all.
- Task 13: parked for the final review — `TabAttention` treats the selected tab's focused pane as in view while a zoomed dock or a loose panel covers it, so its bells are dropped and its notices marked read — cost if wrong: while a tool is expanded or a loose dock shows, a bell from the covered focused pane is not announced.
- Task 13: while loose, a file dropped on the area types nothing (`PaneDropTarget` off) (R14) — cost if wrong: one line and one test.
- Task 13: ⌘⇧B or 🧩 on an open dock that the width hides shows it expanded instead of closing it (D10) — cost if wrong: a few lines in the window's toggle handler.
- Task 13: while loose, a keyed user command runs nothing and shows D35's "no terminal" toast; Copy, Find next/end and workspace font zoom stay — cost if wrong: a keyed user command while loose gives the "no terminal" toast.
- Task 14: the sidebar's own keyboard selection (arrows, Home, End) ends loose where it selects a tab, not on a header move (R14) — cost if wrong: one line and one test.
- Task 14: a tool row's height holds both lines at any text size and stays 36 at 1× (D18) — cost if wrong: one test.
- Task 14: the list's own focus is a Tab stop only when it has tab rows or headers to walk, not for a Tools group alone (UI §3.6) — cost if wrong: one test.
- Task 14: amendment — no loose-ending in the one-workspace branch (a single workspace cannot be loose while it has a tab, so there it could only end loose with no tab chosen) — cost if wrong: none.
- Task 14: the footer stays one row — "New AI session" keeps its whole label; "Add tool" is a compact 🧩 icon button whose tooltip and Semantics label read "Add tool" (D21, D18) — cost if wrong: "Add tool" shows its name only on hover or VoiceOver; a stacked two-row footer is the alternative.
- Task 15: a confirmed "Clear tool data…" clears even when Settings closes under its question (D8) — cost if wrong: one test.
- Task 15: Add, Edit and Delete (Settings and the sidebar menu) take every provider before their first await, so they finish when Settings closes under their question (D22, D23) — cost if wrong: one test.
- Task 16 (prepared): the R9 knock for `*.localhost` and `0.0.0.0` tools is not probed here (a `.localhost` lookup may leave the machine); it goes to the final review as a fix-wave candidate (the knock dials loopback for D11-local names other than `localhost`) — cost if wrong: such tools wait for the 10 s schedule instead of the 1 s knock.

### Windows

- Windows: the controller pushes `windows-check/v2-3`; result pending (the user reads it).

### Manual checks (spec §11)

§11.1 macOS (a real Mac, macOS 14 or later and, if possible, macOS 12):
1. Add a Vite app's `http://localhost:<port>` as a tool: the page shows in the tool area; a window resize leaves no stale frame — pending manual.
2. The palette (⌘⇧P), context menus, toasts and the notifications panel draw over the page — pending manual.
3. Telex `tieesng vieejt` typed into a field in the page gives "tiếng việt", underlined while composing; ⌘C/⌘V inside the page — pending manual.
4. A click into the AI pane's input types there; a click back into the page gives the page the keys — pending manual.
5. While the page has the keyboard: ⌘T opens a tab, ⌘⇧B closes the tool area, ⌘1 goes to tab 1 — pending manual.
6. Trackpad scrolling; the pointer changes over links — pending manual.
7. `http://127.0.0.1:<port>` loads (ATS, D19) — pending manual.
8. Sign in to a tool, quit, reopen: still signed in; Safari does not see that cookie — pending manual.
9. VoiceOver reads the tool's bar; note how far it reads the page — pending manual.

§11.2 Windows (Windows 10 1809+ or 11, at 100 % and 150 %), with `tool-embed = on` in the config file:
1. Items 1, 3 (UniKey/EVKey Telex and the built-in Telex), 4, 6 and 8 as on macOS — pending manual.
2. Opening the palette, a menu or a dialog hides the page and shows the stand-in; closing the overlay puts the page back in place — pending manual.
3. At 150 %: sharp text, clicks land where aimed — pending manual.
4. Dragging the tool area's width, minimizing and maximizing the window: the page follows its frame and never sticks out — pending manual.
5. A machine without the WebView2 Runtime shows the D8 notice (§8) — pending manual.

Passing all five §11.2 items is what flips `auto` to embed on Windows: one line in `toolsEmbedded`, with its test.

Manual checks added during execution:
- macOS: ShellX shortcuts from a tool page on non-US layouts (Russian, Hebrew, Arabic, AZERTY, Turkish F) — pending manual.
- macOS: a click outside the page returns the keyboard to Flutter — pending manual.
- macOS: an export through a `download`-attribute link shows the download line — pending manual.
- The sidebar footer at its fixed 220 px: "New AI session" shows its whole label (EN and VI) and "Add tool" is a 🧩 icon button whose tooltip reads "Add tool" (macOS and Windows fonts) — pending manual.
- A window narrower than about 907 px: opening a tool shows its dock expanded; Restore hides it; ⌘⇧B shows it again — pending manual.
- A tool of a workspace without a tab ("loose"): a notification click, a search hit or focus history onto the tab selected underneath ends it; a file dropped on the empty area types nothing anywhere — pending manual.
- Windows with `tool-embed = on`: a page redirect to `mailto:` or a custom scheme (WebView2's own prompt shows instead of a silent block), a form POST to another origin, back/forward (D9 coverage is narrower than on macOS) — pending manual.
- Windows: the Add dialog's port suggestions appear within 2 s from a cold PowerShell/CIM start (criterion 2) — pending manual.
- Windows with `tool-embed = on`: opening the palette while a tool's WebView2 is still starting keeps the page hidden behind the stand-in — pending manual.
- The 1 s knock for tools at `*.localhost` and `0.0.0.0` (criterion 5) — pending manual.
- ⌘⇧B with `tool-embed = off` on a workspace without tools: adding opens the browser — pending manual.

### Follow-ups

- `agent-skills/`: tell agents that tools exist (R19).
- V2-4 (tools on the phone) consumes Task 1's interface (`ToolEntry`, `parseToolUrl`, `ToolUrlResult`, `ToolRegistry`, `toolRegistryProvider`; commits eb0b6dc..54489b9).
- A6's full browser can resume on this engine (D6): `BrowserEngine` without the bridge (R3), the macOS and Windows engines, and `browser_url.dart` kept for it (R27).

### Final review (2026-10-16)

Verdict: With fixes; no Critical. One fix wave on a2fe9c1, one commit per item, each with its tests:

1. D10 — ⌘⇧B on a closed dock without chips reopens the tool viewed last: the chip last on show however it got there (opened or chosen, the one a closed chip handed over to, the restored one); the first tool only when that one no longer exists — 9667cf3 (`tool_dock_ui_test` "⌘⇧B on a closed dock without chips reopens the tool viewed last: …", both probes).
2. D13 — a D23 edit that moves the URL and D9 "Back to tool" restart the retry back-off (1, 2, 4, 8, then every 10 s, only while shown; an edit made while hidden gets its 1 s once shown) and get their own crash reload — 4f3235e (`tool_page_test` "a URL the app newly asks for …", "an edited URL and "Back to tool" get their own crash reload").
3. A pane under a zoomed dock or a loose panel is not in view: one predicate, `toolPanesCovered` (`toolPanesCoveredProvider`), the rule ToolArea draws by; A4's "seen" and A12's "watched" exclude a covered pane, so its bells, notices and Claude's permission requests badge the tab and arrive; the 1 s dwell re-arms when the panes show again — b40fca6 (`attention_covered_test` 5 tests; `tool_dock_test` "the panes are covered by …"; `tool_dock_state_test` "toolDockCoversPanes …"; `tool_dock_ui_test` "the panes count as covered exactly …").
4. §8 — closing the last tab of the shown workspace with its dock open and embedded keeps that workspace on screen loose, after A2's successor selection: the same page, no reload; a closed dock or tools in the browser keep A2's behaviour — f8d3438 (`tool_dock_ui_test` "closing the last tab of the shown workspace …"; `tool_dock_test` group "§8: the last tab of the shown workspace closes", 3 tests).
5. R18 — after a failed edit or "Back to tool" the error panels' browser button opens the URL that failed (`ToolPage.recoveryUrl`), and the bar shows no "On {host}" until the asked-for URL loads — 0c33ad1 (`tool_page_test` "after an edit or "Back to tool", the page is not "away" …", "recoveryUrl is the URL a failure is about …"; `tool_dock_ui_test` "after a failed edit the bar says no "On {host}" …").
6. Drops — the terminal's drop target and the AI composer's refuse drops while item 3's predicate holds (desktop_drop routes a drop by bounds, not by what is on top) — 327b635 (`tool_dock_ui_test` "a file dropped on a zoomed dock …", "an image dropped over a zoomed dock or over the panel of a workspace shown without a tab …").
7. `tool-embed = off` closes every live page (engines disposed); switched back on, a tool shown loads again — 6ce3170 (`tool_dock_ui_test` "switching tool-embed to off closes every live page …").
8. R9 — the knock dials `localhost` for a `*.localhost` tool and `127.0.0.1` for `0.0.0.0`; any other host as it is — e02a59e (`tool_page_test` "toolKnockHost: …", "the knock dials loopback …").

Parked findings (ruling, cost if wrong):
- Toasts and the key-sequence pill under a zoomed dock or a loose panel: the notice layer lives in TerminalPane, which those cover — parked, next fix candidate — cost if wrong: a toast or the pill is not seen while a tool is expanded or a workspace shows loose.
- The refused panel blinks on each retry (it goes while the retry loads and comes back when refused): keeping it until a page commits needs a "committed" signal from the engines — parked — cost if wrong: a short blink at each retry while the server is down.
- Retries and the R9 knock go on while the window is minimized (the page still counts as shown, D13) — parked — cost if wrong: one local connect per second, and a reload every 10 s, while minimized.
- Deleting a workspace silently deletes its tools (D2, §8): telling the user needs new strings — the user's decision — cost if wrong: the tools go without a word.
- Polish: `toggleToolsShortcutLabel()` is unused — parked — cost if wrong: none. (ToolArea's inline copy of `dockWorkspaceOf`, parked with it, went with item 3: `dockWorkspaceOf` moved next to the shared predicate in `tool_dock.dart`, and ToolArea calls it.)

Manual checks this review added:
- Open a tool with ⌘⇧B and type at once: the keys reach the page (the first `focusContent` may run before the platform view is in a window) — pending manual.
- With a tool expanded, or a workspace shown loose, a Claude permission request in the covered pane badges its tab — pending manual.
=======
>>>>>>> v2-4

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
