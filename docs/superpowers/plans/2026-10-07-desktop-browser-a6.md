# ShellX Desktop A6 — Embedded Browser Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A browser pane is a new kind of leaf in A3's pane tree — split next to a terminal with ⌘⇧B / Ctrl+Shift+Alt+B, the terminal menu, the row menu or ⌥-click on an A2 port — with a URL bar, back/forward/reload/stop, a security mark and loading progress, backed by WKWebView (macOS) and WebView2 (Windows), and an internal `BrowserController` API (navigate, eval → JSON, screenshot, console, network, wait for load) whose `ui.browser.*` command shapes A7 will expose.

**Architecture:** Browser panes get negative pane ids so A3's `PaneLeaf(int)` and every `pane_layout.dart` function work unchanged; `TerminalTab` gains a `browsers` map of immutable `BrowserPaneState`s next to its `PaneSession`s, and a tab always keeps at least one terminal pane. Engines sit behind a small `BrowserEngine` interface (macOS: `webview_flutter_wkwebview` + a Swift helper for snapshot/stop/user script/data/key forwarding; Windows: a vendored, patched `webview_windows`), so the controller, the command handler and the UI are tested against `FakeBrowserEngine`. A document-start bootstrap script reports console, network and title through one bridge channel whose messages are treated as untrusted data.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), flutter_riverpod 3, `webview_flutter` ^4.14.1 + `webview_flutter_wkwebview` ^3.27.0 (macOS), `webview_windows` 0.4.0 vendored in `third_party/webview_windows` (Windows, WebView2), Swift (macOS Runner), C++ (vendored plugin), `flutter_test` + `fake_async`, ARB l10n via `flutter gen-l10n`.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-browser-a6-design.md` (binding; W1–W7 and D1–D38 are final). **UI design:** `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a6.md` (binding for every measurement, colour, string and wireframe; cited as "UI-A6 §N"), on top of UI-A3, UI-A4, UI-A2 and UI-A1. Executors read the spec and UI-A6 before Task 1.

## Prerequisite: A3 must be merged first

A6 executes **after A3 (`feat/desktop-a3`) is merged into `main`** — a browser pane is a leaf of A3's pane tree, and Tasks 5 and 9 edit A3's `TerminalTab`, `TerminalTabs`, `PaneTreeView`, menus and shortcuts. Per the roadmap A5a and A5b merge before A6; Task 10's restore step needs A5a (`restore_snapshot.dart`, `TerminalTabs.restore`) and its daemon note needs A5b. If A5a is not on `main` when Task 10 starts, skip Steps 5–8 of Task 10, record "A6 restore pending A5a" in the ledger, and do them right after A5a merges.

Start a fresh branch `feat/desktop-a6` from that `main`.

| Task | Needs A3 merged? | Why |
|---|---|---|
| 1 ⚠ Engine spike, dependencies, vendored plugin | No (new deps, `third_party/`, Runner files) — run on post-A3 `main` anyway | Spike results gate Tasks 7–8 |
| 2 URL model | No (new file) | — |
| 3 Bridge + bootstrap | No (new files) | — |
| 4 Engine interface + controller | No (new files) | — |
| 5 Tab model + registry | **Yes (hard)** | `TerminalTab`, `TerminalTabs`, `PaneNoRoomNotice`, `_removePane` are A3's |
| 6 Settings, profile, tray, strings, chords | **Yes** | `terminal_shortcuts.dart`, ARB files, `ShellxSizes` carry A3 code; tray carries A5a's "Terminal" submenu if merged |
| 7 ⚠ macOS engine | No for the engine, **yes** for the manual check | — |
| 8 ⚠ Windows engine | Same | — |
| 9 UI | **Yes (hard)** | `PaneTreeView`, menus, sidebar row |
| 10 Commands, restore, HANDOFF | **Yes**; restore needs **A5a** | see above |

Before Task 1 run the full suites on the fresh branch and record the counts (they must stay green throughout):

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test
cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```

## Global Constraints

- The spec wins over everything else; UI-A6 (then UI-A3, UI-A4, UI-A2, UI-A1) wins for visuals and copy. Never invent a colour, size, duration or string: take it from the UI section the task names. **No new colour tokens** (UI-A6 §1.1).
- Toolchain: Flutter `~/fvm/versions/3.41.4/bin/flutter`, Dart `~/fvm/versions/3.41.4/bin/dart`. Desktop tests: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Format: `~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed <paths>`. Analyze: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`.
- Engines, exact: `webview_flutter: ^4.14.1`, `webview_flutter_wkwebview: ^3.27.0`, `webview_windows` **0.4.0 vendored** at `third_party/webview_windows` with `SHELLX_PATCHES.md` (D2). Never `desktop_webview_window` (separate window, D3).
- **No protocol change, no phone change (D30):** no edits to `packages/shellx_core`, `packages/shellx_agent`, `apps/mobile`, relay, `term/`. A browser pane is never a session.
- **Browser pane ids are negative (D4)** (`isBrowserPaneId(id) ⇔ id < 0`); session ids stay positive. Never call `LocalSessions.view/close/resize` with a negative id.
- **A tab always holds ≥ 1 terminal pane (D5).** A browser pane is only ever created by splitting an existing tab.
- **Allowed top-level pages:** `http`, `https`, `about:blank` only (D10). The address field never searches (D9).
- **Agent gate (D20):** `evalJs`, `screenshot`, `console`, `network` refuse a non-local origin with `forbidden_origin` unless `browser_agent_all_origins` is on; checked in Dart **and** inside the page.
- **Bridge messages are untrusted data (D21):** parsed with size limits, never executed, never logged.
- Limits, exact: ≤ 8 browser panes (D28); eval body ≤ 32 KiB, result ≤ 48 KiB, timeout 10 s default / 30 s max (D19); wait 15 s / 60 s (D24); console and network rings of 500, pages ≤ 200, text/URL ≤ 2 KiB (D22, D23); ≤ 200 bridge messages/s per pane; minimum pane 240 × 160 logical px (D31); agent mark 10 s, announcement ≥ 60 s apart (D25).
- Settings keys (UI process, A5b D13): `browser_keep_data` (default `false`), `browser_agent_all_origins` (default `false`).
- Privacy (D33): never log URLs, titles, console text, scripts or eval results — only event types, error codes, `runtimeType`.
- Windows chords containing Alt fire only with the **left** Alt (A3 D20).
- l10n: every new string goes into both `apps/desktop/lib/l10n/app_en.arb` (with `@key` metadata; `port`, `count`, `index` are `int`) and `app_vi.arb` with identical keys, then `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; commit the generated `lib/l10n/app_localizations*.dart`.
- Code style: match the surrounding code (doc comments that say *why*, `final class`, no `print`). Every task ends with its tests green, `dart format --set-exit-if-changed` clean on touched files, analyzer clean, the full desktop suite green (from Task 5 on), and a commit with a conventional message. Commit only the files the task lists — **never `git add -A`**.
- ⚠ MANUAL steps need a real Mac (macOS 12+) or a real Windows 10 1809+/11 machine. An executor without one marks the step "⚠ PENDING MANUAL" in the ledger `docs/superpowers/ledgers/a1-desktop-terminal.md` (section "A6") and continues; the controller runs it before merge.

## Review Focus

1. **`waitForLoad()` called right after `navigate()`, before the engine's first event** — it must wait for the new page, not return the previous one at once. Pinned by the "loading at once" test in Task 4 and the `navigate` command test in Task 10.
2. **The last terminal pane of a tab that also holds a browser pane exits with code 0, or is closed** — the shell exiting must not silently take the browser pane with it (the terminal pane stays with its exit line), while an explicit close closes the whole tab; a tab must never be left with only browser panes. Pinned by the D5 tests in Task 5.
3. **The page navigates to another origin while an agent eval or screenshot is in flight** (a redirect from `localhost` to a login site) — the in-page origin check and the before/after screenshot check must refuse with `forbidden_origin`. Pinned by the screenshot test in Task 4 and the generated-script check in Task 3.
4. **Keys pressed while the web content has the keyboard** — ShellX chords (⌘L, ⌘W, ⌘⌥arrows, Ctrl+F6, ⌘1–9) reach Flutter even from a text field inside the page; ⌘C/⌘V/⌘A and plain typing (including Vietnamese IME composition) reach the page; Esc reaches the page unless a load is in progress; AltGr chords on Windows reach the page. Pinned by the chord tests in Task 6, the forwarded-chord test in Task 9 and the ⚠ MANUAL checks in Tasks 7–8.
5. **Typing something that is not an address** (`hello world`, `javascript:…`, `file:///…`, `3000`, `[::1]:8080`) — never a search, never a non-web scheme, the port shorthand works. Pinned by the table test in Task 2 and the address-field widget test in Task 9.

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `apps/desktop/pubspec.yaml` | `webview_flutter`, `webview_flutter_wkwebview`, `webview_windows` (path), asset `assets/browser/` |
| Create `third_party/webview_windows/**` + `SHELLX_PATCHES.md` | Vendored 0.4.0 + patches (a) capture, (b) accelerators, (c) downloads, (d) navigation policy, (e) focus |
| Create `apps/desktop/assets/browser/browser_bootstrap.js` | Document-start script: console, network, title, popups (D10, D21–D23) |
| Create `apps/desktop/lib/src/browser/browser_url.dart` | Address parsing, origin classes, restore URL, display address (D9–D11, D29) |
| Create `apps/desktop/lib/src/browser/browser_bridge.dart` | Bridge message parsing, eval script builder (D19, D21) |
| Create `apps/desktop/lib/src/browser/browser_engine.dart` | `BrowserEngine` interface, engine events, error kinds |
| Create `apps/desktop/lib/src/browser/browser_controller.dart` | `BrowserController`, `BrowserPaneState`, buffers, gate, wait, agent mark (D18–D25) |
| Create `apps/desktop/lib/src/browser/browser_registry.dart` | Engine factory provider, controllers per pane, lazy creation, notices, shortcut stream |
| Create `apps/desktop/lib/src/browser/browser_profile.dart` | Private profile per platform (D26) |
| Create `apps/desktop/lib/src/browser/shots_dir.dart` | Screenshot files for A7 (D24) |
| Create `apps/desktop/lib/src/browser/browser_chords.dart` | Chord strings shared with native code (D15) |
| Create `apps/desktop/lib/src/browser/browser_commands.dart` | `ui.browser.*` handler (D38) |
| Create `apps/desktop/lib/src/browser/engines/wk_webview_engine.dart` | macOS engine (D1) |
| Create `apps/desktop/lib/src/browser/engines/webview2_engine.dart` | Windows engine (D2) |
| Create `apps/desktop/macos/Runner/BrowserNative.swift` (+ register in `MainFlutterWindow.swift`, add to the Xcode project) | Snapshot, stop, bootstrap user script, data clearing, key/mouse monitor |
| Modify `apps/desktop/lib/src/terminal/terminal_tabs.dart` | `browsers`, `activeTerminalPane`, `openBrowser`, `updateBrowser`, `tabOfPane`, D5 |
| Modify `apps/desktop/lib/src/platform/settings_store.dart` | Two keys (D27) |
| Modify `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_presenter.dart`, `tray_actions.dart` | "Trình duyệt" submenu |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | UI-A6 §7 |
| Modify `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` | UI-A6 §1.2 sizes |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`, `shortcut_labels.dart` | Browser intents, ⌘⇧B, `browserForwardedChords`, `intentForForwardedChord` |
| Create `apps/desktop/lib/src/ui/terminal/browser_pane_view.dart` | Toolbar, address field, origin mark, progress, error page, agent mark, JS dialogs |
| Modify `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart` (A3) | Negative leaf → `BrowserPaneView`; browser pane header; min size |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` | Actions, region 1b, notices → toasts/announcements |
| Modify `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart` | Browser toasts |
| Modify `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `session_sidebar.dart` | ⌥-click port, row menu items |
| Modify `apps/desktop/lib/main.dart` | Engine factory override, profile prepare/quit, shots sweep |
| Modify `apps/desktop/lib/src/restore/restore_snapshot.dart`, `restore_persistence.dart`, `terminal_tabs.dart` (A5a) | `SavedBrowser` leaf (D29) |
| Modify `release/windows/shellx.iss` | Uninstall `%LOCALAPPDATA%\ShellX\webview`, `\browser` |
| Modify `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `HANDOFF.md` | D33, §16 |
| Create `apps/desktop/test/support/fake_browser_engine.dart` | Test double |
| Tests: `apps/desktop/test/browser/{browser_url,browser_bridge,browser_controller,browser_profile,shots_dir,browser_chords,browser_commands,browser_registry}_test.dart`, `test/terminal/terminal_tabs_browser_test.dart`, `test/ui/browser_pane_view_test.dart`, `test/ui/browser_entry_points_test.dart`, `test/tray/tray_browser_menu_test.dart`, `test/restore/restore_browser_test.dart` | |

---

### Task 1: ⚠ Engine spike, dependencies and the vendored Windows plugin (D1–D3)

This task decides whether the embedded engines are good enough (D3). It adds the dependencies and a throwaway debug-only demo pane, runs the manual checks on both platforms, records the results, and **stops the plan** if the gate fails.

**Files:**
- Modify: `apps/desktop/pubspec.yaml`
- Create: `third_party/webview_windows/` (copy of `webview_windows` 0.4.0), `third_party/webview_windows/SHELLX_PATCHES.md`
- Create (temporary, deleted at the end of the task): `apps/desktop/lib/spike_browser.dart`
- Modify: `docs/superpowers/ledgers/a1-desktop-terminal.md` (section "## A6 (browser pane) — spike")

**Interfaces:**
- Consumes: nothing.
- Produces: the three packages resolvable from `apps/desktop`; the ledger lines `Spike macOS: PASS|FAIL …` and `Spike Windows: PASS|FAIL …` that Tasks 7–8 read.

- [ ] **Step 1: Vendor `webview_windows` 0.4.0**

```bash
cd /tmp && ~/fvm/versions/3.41.4/bin/dart pub unpack webview_windows:0.4.0
mkdir -p "$OLDPWD/third_party" && cp -R /tmp/webview_windows-0.4.0 "$OLDPWD/third_party/webview_windows"
```

(Run from the repo root so `$OLDPWD` is the repo.) Create `third_party/webview_windows/SHELLX_PATCHES.md`:

```markdown
# ShellX patches to webview_windows 0.4.0

Vendored from pub.dev `webview_windows` 0.4.0 (BSD-3-Clause, jns.io) because
the last release is from 2024 and ShellX A6 needs five native additions
(spec 2026-10-07-desktop-browser-a6-design.md D2). Keep every change listed
here; re-apply them on any upgrade.

| # | Patch | Files | Added in |
|---|---|---|---|
| a | `capturePreview` → PNG bytes (`ICoreWebView2::CapturePreview`) | windows/webview.cc, webview.h, webview_bridge.cc, lib/src/webview.dart | A6 Task 8 |
| b | `setForwardedAccelerators` + `acceleratorKey` event (`AcceleratorKeyPressed`) | same | A6 Task 8 |
| c | Downloads cancelled + `downloadBlocked` event (`DownloadStarting`) | same | A6 Task 8 |
| d | Top-level navigation to non-http(s)/about schemes cancelled + `navigationBlocked` event (`NavigationStarting`) | same | A6 Task 8 |
| e | `moveFocus` (`ICoreWebView2Controller::MoveFocus`, programmatic) | same | A6 Task 8 |
```

- [ ] **Step 2: Add the dependencies**

In `apps/desktop/pubspec.yaml` under `dependencies:` (alphabetical with the rest):

```yaml
  # A6 D1: WKWebView as a platform view on macOS.
  webview_flutter: ^4.14.1
  webview_flutter_wkwebview: ^3.27.0
  # A6 D2: WebView2, vendored and patched, see
  # third_party/webview_windows/SHELLX_PATCHES.md.
  webview_windows:
    path: ../../third_party/webview_windows
```

and under `flutter: assets:` add `    - assets/browser/`. Create an empty placeholder `apps/desktop/assets/browser/.gitkeep` (Task 3 adds the real file). Run:

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
```

Expected: resolves; `pubspec.lock` changes. If `webview_windows` 0.4.0 conflicts with the workspace (`resolution: workspace`), add `third_party/webview_windows` to the root `pubspec.yaml` `workspace:` list exactly like `third_party/flutter_pty` is handled there (check the root file first; if `flutter_pty` is not listed, do not list `webview_windows` either).

- [ ] **Step 3: Write the spike pane (debug only)**

Create `apps/desktop/lib/spike_browser.dart`:

```dart
// A6 Task 1 spike — DELETE at the end of the task.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

void main() => runApp(const MaterialApp(home: _Spike()));

class _Spike extends StatefulWidget {
  const _Spike();
  @override
  State<_Spike> createState() => _SpikeState();
}

class _SpikeState extends State<_Spike> {
  WebViewController? _mac;
  final win.WebviewController _win = win.WebviewController();
  final TextEditingController _field = TextEditingController(text: 'https://example.com/');
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _mac = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(_field.text));
      _ready = true;
    } else {
      _win.initialize().then((_) async {
        await _win.loadUrl(_field.text);
        setState(() => _ready = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        const SizedBox(width: 220, child: ColoredBox(color: Color(0xFF111B1E))),
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: _field,
                onSubmitted: (v) => Platform.isMacOS
                    ? _mac!.loadRequest(Uri.parse(v))
                    : _win.loadUrl(v),
              ),
              Expanded(
                child: !_ready
                    ? const SizedBox()
                    : Platform.isMacOS
                    ? WebViewWidget(controller: _mac!)
                    : win.Webview(_win),
              ),
            ],
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Overlay above the web view')),
      ),
      child: const Icon(Icons.layers),
    ),
  );
}
```

Run it with `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter run -d macos -t lib/spike_browser.dart` (Windows: `-d windows`).

- [ ] **Step 4: ⚠ MANUAL — macOS checks (real Mac, macOS 12+)**

Record PASS/FAIL with one line of notes for each:
1. The page renders inside the right-hand area, clipped to it; resizing the window resizes the page with no stale frame.
2. The SnackBar (Flutter overlay) draws **above** the web view; a Flutter `PopupMenu` (right-click the text field) also draws above it.
3. Click into a text input on the page (e.g. `https://www.google.com/` search box) → typing reaches the page; switch input source to Vietnamese Telex (macOS built-in) and type `tieesng vieejt` → "tiếng việt" with the composition underline; ⌘C/⌘V work in the page.
4. Click the Flutter text field → typing goes to the Flutter field, not the page; click back into the page → the page has the keyboard.
5. VoiceOver (⌘F5): VO-arrow reads the page content (headings, links).
6. Scrolling with the trackpad scrolls the page; the mouse cursor changes over links.
7. External API reachable: add a temporary Swift file `macos/Runner/SpikeProbe.swift` containing only `import webview_flutter_wkwebview; let _probe: (Int64, FlutterPluginRegistry) -> WKWebView? = { WebViewFlutterWKWebViewExternalAPI.webView(forIdentifier: $0, withPluginRegistry: $1) }` (plus `import FlutterMacOS`, `import WebKit`), build with `flutter build macos --debug`, then delete the file. Builds = PASS. FAIL means Task 7 locates the `WKWebView` by walking the platform view's `NSView` subtree instead (spec D1 fallback) — note it in the ledger.

- [ ] **Step 5: ⚠ MANUAL — Windows checks (real Windows 10 1809+ or 11, 100 % and 150 % scaling)**

Same items 1–4 (Vietnamese: UniKey or EVKey Telex, and Windows' built-in Vietnamese Telex keyboard), plus:
5. Narrator (Ctrl+Win+Enter): record what it reads inside the page (expected: nothing — spec D2 limitation; PASS means "documented limitation confirmed", not "readable").
6. At 150 % scaling the page is sharp (not blurred) and pointer positions match (click a link exactly).
7. `WebviewController.getWebViewVersion()` returns a version string.

- [ ] **Step 6: Gate decision**

Add to `docs/superpowers/ledgers/a1-desktop-terminal.md`:

```markdown
## A6 (browser pane) — spike
Spike macOS: <PASS|FAIL> — <item: note, …>
Spike Windows: <PASS|FAIL> — <item: note, …>
```

**PASS** = items 1–4 and 6 pass on that platform (Windows item 5 is informational). If either platform FAILS items 1–4, **stop**: report to the controller with the notes; spec D3's fallback (native child window over the pane) needs its own plan task before Tasks 7–9. Otherwise continue.

- [ ] **Step 7: Delete the spike, verify, commit**

```bash
rm apps/desktop/lib/spike_browser.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
cd ../.. && git add apps/desktop/pubspec.yaml pubspec.lock apps/desktop/assets/browser/.gitkeep third_party/webview_windows docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "chore(desktop): add WKWebView and vendored WebView2 engines for A6 browser panes (spike results in ledger)"
```

(If the lock file lives at `apps/desktop/pubspec.lock` instead of the root, add that path.)

---

### Task 2: URL model — address field, origins, restore URL (D9–D11, D29)

**Files:**
- Create: `apps/desktop/lib/src/browser/browser_url.dart`
- Test: `apps/desktop/test/browser/browser_url_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum BrowserOrigin { local, secure, insecure, none }`; `final Uri aboutBlank`; `const int kMaxAddressLength = 2048`; `Uri? parseAddressInput(String raw)`; `bool isLocalHost(String host)`; `BrowserOrigin classifyOrigin(Uri? uri)`; `bool isNavigable(Uri uri)`; `String? urlForRestore(Uri? uri)`; `String displayAddress(Uri uri)`.

- [ ] **Step 1: Write the failing test**

Create `apps/desktop/test/browser/browser_url_test.dart`:

```dart
import 'package:shellx_desktop/src/browser/browser_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAddressInput (D9)', () {
    final cases = <String, String?>{
      '3000': 'http://localhost:3000/',
      ' 8000 ': 'http://localhost:8000/',
      '0': null,
      '65536': null,
      'localhost:3000': 'http://localhost:3000/',
      'localhost:3000/docs?x=1': 'http://localhost:3000/docs?x=1',
      'localhost': 'http://localhost/',
      'app.localhost:5173': 'http://app.localhost:5173/',
      '127.0.0.1:8080': 'http://127.0.0.1:8080/',
      '[::1]:3000': 'http://[::1]:3000/',
      '192.168.1.20:8080': 'http://192.168.1.20:8080/',
      'example.com': 'https://example.com/',
      'example.com/a b': null,
      'http://example.com': 'http://example.com/',
      'HTTPS://Example.com/x': 'https://example.com/x',
      'about:blank': 'about:blank',
      'hello world': null,
      'hello': null,
      'javascript:alert(1)': null,
      'file:///etc/passwd': null,
      'data:text/html,hi': null,
      'mailto:a@b.c': null,
      'http://': null,
      'localhost:99999': null,
      '': null,
    };
    cases.forEach((input, expected) {
      test('"$input"', () {
        expect(parseAddressInput(input)?.toString(), expected);
      });
    });
    test('longer than 2048 characters is refused', () {
      expect(parseAddressInput('https://a.com/${'x' * 2048}'), isNull);
    });
  });

  group('classifyOrigin (D11)', () {
    final cases = <String, BrowserOrigin>{
      'http://localhost:3000/': BrowserOrigin.local,
      'https://localhost/': BrowserOrigin.local,
      'http://app.localhost/': BrowserOrigin.local,
      'http://127.0.0.1/': BrowserOrigin.local,
      'http://127.8.9.10/': BrowserOrigin.local,
      'http://[::1]:8000/': BrowserOrigin.local,
      'http://0.0.0.0:8000/': BrowserOrigin.local,
      'https://example.com/': BrowserOrigin.secure,
      'http://example.com/': BrowserOrigin.insecure,
      'http://localhost.example.com/': BrowserOrigin.insecure,
      'http://128.0.0.1/': BrowserOrigin.insecure,
      'about:blank': BrowserOrigin.none,
      'file:///tmp/x': BrowserOrigin.none,
    };
    cases.forEach((url, expected) {
      test(url, () => expect(classifyOrigin(Uri.parse(url)), expected));
    });
    test('null', () => expect(classifyOrigin(null), BrowserOrigin.none));
  });

  test('isNavigable (D10)', () {
    expect(isNavigable(Uri.parse('http://localhost/')), isTrue);
    expect(isNavigable(Uri.parse('https://a.com/')), isTrue);
    expect(isNavigable(aboutBlank), isTrue);
    expect(isNavigable(Uri.parse('about:srcdoc')), isFalse);
    expect(isNavigable(Uri.parse('file:///x')), isFalse);
    expect(isNavigable(Uri.parse('mailto:a@b.c')), isFalse);
    expect(isNavigable(Uri.parse('javascript:void(0)')), isFalse);
  });

  test('urlForRestore strips credentials and fragment (D29)', () {
    expect(
      urlForRestore(Uri.parse('http://u:p@localhost:8888/lab?token=abc#cell')),
      'http://localhost:8888/lab?token=abc',
    );
    expect(urlForRestore(aboutBlank), isNull);
    expect(urlForRestore(Uri.parse('file:///x')), isNull);
    expect(urlForRestore(null), isNull);
    expect(urlForRestore(Uri.parse('https://a.com/${'x' * 2048}')), isNull);
  });

  test('displayAddress (UI-A6 §2.1)', () {
    expect(
      displayAddress(Uri.parse('http://localhost:5173/about')),
      'localhost:5173/about',
    );
    expect(
      displayAddress(Uri.parse('https://example.com/a%20b')),
      'example.com/a b',
    );
    expect(
      displayAddress(Uri.parse('http://example.com/')),
      'http://example.com/',
    );
    expect(displayAddress(aboutBlank), '');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_url_test.dart`
Expected: FAIL — `browser_url.dart` does not exist.

- [ ] **Step 3: Implement**

Create `apps/desktop/lib/src/browser/browser_url.dart`:

```dart
/// A6 D9–D11, D29: what the address field accepts, how an origin is
/// classified, and what of a URL survives into the restore file.
library;

/// D11. `none` is `about:blank` (and anything that is not http/https).
enum BrowserOrigin { local, secure, insecure, none }

/// The only page that is not http/https a browser pane may show.
final Uri aboutBlank = Uri.parse('about:blank');

const int kMaxAddressLength = 2048;

final RegExp _digits = RegExp(r'^\d{1,5}$');
final RegExp _whitespace = RegExp(r'\s');
final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');
final RegExp _hostPort = RegExp(r'^[A-Za-z0-9.-]+:\d{1,5}(?:[/?#].*)?$');
final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// D9: the address field's text → the URL to load, or `null` for "Không
/// phải địa chỉ web". Never a search: text that is not an address is
/// refused, so nothing typed ever reaches a search engine.
Uri? parseAddressInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.length > kMaxAddressLength) return null;
  if (text.toLowerCase() == 'about:blank') return aboutBlank;
  if (_digits.hasMatch(text)) {
    final port = int.parse(text);
    if (port < 1 || port > 65535) return null;
    return Uri.parse('http://localhost:$port/');
  }
  if (_whitespace.hasMatch(text)) return null;
  final scheme = _scheme.firstMatch(text)?.group(1)?.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return _web(text);
  // "localhost:3000" also looks like a scheme; anything else with a
  // scheme (javascript:, file:, data:, mailto:) is refused.
  if (scheme != null && !_hostPort.hasMatch(text)) return null;
  final guess = _web('http://$text');
  if (guess == null) return null;
  final host = guess.host;
  if (isLocalHost(host) || _isIpLiteral(host)) return guess;
  if (!host.contains('.')) return null;
  return guess.replace(scheme: 'https');
}

Uri? _web(String text) {
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return null;
  }
  if (uri.host.isEmpty) return null;
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
  return uri.path.isEmpty ? uri.replace(path: '/') : uri;
}

bool _isIpLiteral(String host) => _ipv4.hasMatch(host) || host.contains(':');

/// D11: loopback and `*.localhost` (RFC 6761: never resolved outside).
bool isLocalHost(String rawHost) {
  final host = rawHost.toLowerCase();
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host == '::1' || host == '[::1]' || host == '0.0.0.0') return true;
  final v4 = _ipv4.firstMatch(host);
  return v4 != null && v4.group(1) == '127';
}

BrowserOrigin classifyOrigin(Uri? uri) {
  if (uri == null) return BrowserOrigin.none;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return BrowserOrigin.none;
  if (isLocalHost(uri.host)) return BrowserOrigin.local;
  return scheme == 'https' ? BrowserOrigin.secure : BrowserOrigin.insecure;
}

/// D10: the only top-level pages a browser pane may show.
bool isNavigable(Uri uri) {
  if (uri == aboutBlank) return true;
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
}

/// D29: what the restore file keeps — http/https only, no credentials, no
/// fragment, ≤ 2048 characters; anything else restores as `about:blank`.
String? urlForRestore(Uri? uri) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  final clean = uri.replace(userInfo: '').removeFragment();
  final text = clean.toString();
  return text.length > kMaxAddressLength ? null : text;
}

/// UI-A6 §2.1: the unfocused address — no scheme for local and secure
/// pages (the origin mark says it), `http://` kept for insecure ones;
/// percent-escapes decoded for reading.
String displayAddress(Uri uri) {
  if (uri == aboutBlank) return '';
  final text = Uri.decodeFull(uri.toString());
  return switch (classifyOrigin(uri)) {
    BrowserOrigin.local || BrowserOrigin.secure => text.replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    ),
    _ => text,
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_url_test.dart`
Expected: PASS (43 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/browser/browser_url.dart apps/desktop/test/browser/browser_url_test.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/browser/browser_url.dart apps/desktop/test/browser/browser_url_test.dart
git commit -m "feat(desktop): browser address parsing, origin classes and restore URL (A6 D9-D11, D29)"
```

---

### Task 3: Bridge — message parsing, eval script, bootstrap script (D10, D19, D21–D23)

**Files:**
- Create: `apps/desktop/lib/src/browser/browser_bridge.dart`
- Create: `apps/desktop/assets/browser/browser_bootstrap.js` (delete `assets/browser/.gitkeep`)
- Test: `apps/desktop/test/browser/browser_bridge_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: constants `kBridgeMessageMax` (64 KiB), `kConsoleTextMax` (2048), `kNetworkUrlMax` (2048), `kEvalResultMax` (48 KiB), `kEvalScriptMax` (32 KiB); `enum BridgeTransport { webkit, webview2 }` with `postStatement`; `sealed class BridgeMessage` with `ConsoleMessage {level, text, url}`, `NetworkMessage {url, type, method?, status?, durationMs?, size?}`, `TitleMessage(title)`, `EvalResultMessage {nonce, json?, code?, message?, ok}`; `BridgeMessage? parseBridgeMessage(String raw)`; `String buildEvalScript({required String nonce, required String body, required bool allowAnyOrigin, required BridgeTransport transport})`; asset path `assets/browser/browser_bootstrap.js`.

- [ ] **Step 1: Write the failing test**

Create `apps/desktop/test/browser/browser_bridge_test.dart`:

```dart
import 'dart:convert';

import 'package:shellx_desktop/src/browser/browser_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBridgeMessage (D21)', () {
    test('console', () {
      final m =
          parseBridgeMessage(
                jsonEncode({
                  't': 'console',
                  'level': 'warn',
                  'text': 'xin chào',
                  'url': 'http://localhost/',
                }),
              )!
              as ConsoleMessage;
      expect(m.level, 'warn');
      expect(m.text, 'xin chào');
      expect(m.url, 'http://localhost/');
    });

    test('console text is cut to 2 KiB; unknown level dropped', () {
      final long =
          parseBridgeMessage(
                jsonEncode({
                  't': 'console',
                  'level': 'log',
                  'text': 'x' * 5000,
                }),
              )!
              as ConsoleMessage;
      expect(long.text.length, kConsoleTextMax);
      expect(long.url, '');
      expect(
        parseBridgeMessage(
          jsonEncode({'t': 'console', 'level': 'trace', 'text': 'a'}),
        ),
        isNull,
      );
    });

    test('net keeps only known fields, numbers non-negative', () {
      final m =
          parseBridgeMessage(
                jsonEncode({
                  't': 'net',
                  'url': 'http://localhost/api',
                  'type': 'fetch',
                  'method': 'post',
                  'status': 201,
                  'dur': 12.6,
                  'size': -1,
                  'headers': {'a': 'b'},
                }),
              )!
              as NetworkMessage;
      expect(m.method, 'POST');
      expect(m.status, 201);
      expect(m.durationMs, 13);
      expect(m.size, isNull);
      expect(
        parseBridgeMessage(jsonEncode({'t': 'net', 'url': '', 'type': 'x'})),
        isNull,
      );
    });

    test('eval ok / failed / too large / bad code', () {
      final ok =
          parseBridgeMessage(
                jsonEncode({
                  't': 'eval',
                  'n': 'abc',
                  'ok': true,
                  'json': '"hi"',
                }),
              )!
              as EvalResultMessage;
      expect(ok.ok, isTrue);
      expect(ok.json, '"hi"');
      final failed =
          parseBridgeMessage(
                jsonEncode({
                  't': 'eval',
                  'n': 'abc',
                  'ok': false,
                  'code': 'eval_error',
                  'message': 'boom',
                }),
              )!
              as EvalResultMessage;
      expect(failed.code, 'eval_error');
      expect(failed.message, 'boom');
      final big =
          parseBridgeMessage(
                jsonEncode({
                  't': 'eval',
                  'n': 'abc',
                  'ok': true,
                  'json': jsonEncode('é' * 30000),
                }),
              )!
              as EvalResultMessage;
      expect(big.code, 'result_too_large');
      expect(
        parseBridgeMessage(
          jsonEncode({'t': 'eval', 'n': 'abc', 'ok': false, 'code': 'rm -rf'}),
        ),
        isNull,
      );
    });

    test('malformed, oversized, unknown → null', () {
      expect(parseBridgeMessage('not json'), isNull);
      expect(parseBridgeMessage('[1,2]'), isNull);
      expect(
        parseBridgeMessage(jsonEncode({'t': 'exec', 'cmd': 'ls'})),
        isNull,
      );
      expect(parseBridgeMessage('"${'a' * (kBridgeMessageMax + 1)}"'), isNull);
    });
  });

  group('buildEvalScript (D19, D20)', () {
    String script({
      bool any = false,
      BridgeTransport t = BridgeTransport.webkit,
    }) => buildEvalScript(
      nonce: 'n0nce',
      body: 'return document.title;',
      allowAnyOrigin: any,
      transport: t,
    );

    test('carries the nonce, the body, the origin check and the transport', () {
      final s = script();
      expect(s, contains('"n0nce"'));
      expect(s, contains('return document.title;'));
      expect(s, contains("code: 'forbidden_origin'"));
      expect(s, contains('var allowed = false ||'));
      expect(
        s,
        contains('window.webkit.messageHandlers.ShellxBrowser.postMessage(s)'),
      );
      expect(script(any: true), contains('var allowed = true ||'));
      expect(
        script(t: BridgeTransport.webview2),
        contains('window.chrome.webview.postMessage(s)'),
      );
    });

    test('never uses eval or new Function (CSP)', () {
      final s = script();
      expect(s, isNot(contains('eval(')));
      expect(s, isNot(contains('new Function')));
    });

    test('a nonce with quotes stays a string literal', () {
      final s = buildEvalScript(
        nonce: 'a"b',
        body: '',
        allowAnyOrigin: false,
        transport: BridgeTransport.webkit,
      );
      expect(s, contains(r'var n = "a\"b";'));
    });
  });
}
```

Append this group at the end of `main()` (it pins Review Focus 3 — the in-page origin check covers every local host form and nothing else):

```dart
  test('the in-page origin check matches D11 (Review Focus 3)', () {
    final s = buildEvalScript(
      nonce: 'n',
      body: 'return 1;',
      allowAnyOrigin: false,
      transport: BridgeTransport.webkit,
    );
    for (final part in [
      "h === 'localhost'",
      r"/\.localhost$/.test(h)",
      "h === '[::1]'",
      "h === '0.0.0.0'",
      r"/^127\.\d+\.\d+\.\d+$/.test(h)",
      "location.href === 'about:blank'",
      "(p === 'http:' || p === 'https:')",
    ]) {
      expect(s, contains(part));
    }
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_bridge_test.dart`
Expected: FAIL — `browser_bridge.dart` does not exist.

- [ ] **Step 3: Implement the bridge**

Create `apps/desktop/lib/src/browser/browser_bridge.dart`:

```dart
/// A6 D19, D21–D23: the page → ShellX bridge. Everything that arrives here
/// was written by the page (or anything running in it): it is data, never
/// a command — it only fills the console/network buffers, updates the
/// title, or settles an eval that is waiting for its own nonce.
library;

import 'dart:convert';

/// D21: one bridge message, JSON. Bigger ones are dropped unread. Sized so
/// an eval result of [kEvalResultMax] bytes plus its envelope fits.
const int kBridgeMessageMax = 64 * 1024;

/// D22: console text kept per entry; D19: eval error message.
const int kConsoleTextMax = 2048;

/// D23: URL kept per network entry.
const int kNetworkUrlMax = 2048;

/// D19: an eval result must fit one A5b frame (64 KiB) with room to spare.
const int kEvalResultMax = 48 * 1024;

/// D19: an eval body (A7 `ui.browser.eval.script`).
const int kEvalScriptMax = 32 * 1024;

/// How a page reaches ShellX: macOS WKScriptMessageHandler, Windows
/// WebView2 `chrome.webview.postMessage`.
enum BridgeTransport {
  webkit('window.webkit.messageHandlers.ShellxBrowser.postMessage(s)'),
  webview2('window.chrome.webview.postMessage(s)');

  const BridgeTransport(this.postStatement);

  /// A statement that sends the string `s`.
  final String postStatement;
}

sealed class BridgeMessage {
  const BridgeMessage();
}

final class ConsoleMessage extends BridgeMessage {
  const ConsoleMessage({
    required this.level,
    required this.text,
    required this.url,
  });
  final String level;
  final String text;
  final String url;
}

final class NetworkMessage extends BridgeMessage {
  const NetworkMessage({
    required this.url,
    required this.type,
    this.method,
    this.status,
    this.durationMs,
    this.size,
  });
  final String url;
  final String type;
  final String? method;
  final int? status;
  final int? durationMs;
  final int? size;
}

final class TitleMessage extends BridgeMessage {
  const TitleMessage(this.title);
  final String title;
}

final class EvalResultMessage extends BridgeMessage {
  const EvalResultMessage.ok(this.nonce, String this.json)
    : code = null,
      message = null;
  const EvalResultMessage.failed(this.nonce, String this.code, this.message)
    : json = null;
  final String nonce;
  final String? json;
  final String? code;
  final String? message;
  bool get ok => code == null;
}

const Set<String> _levels = {'log', 'info', 'warn', 'error', 'debug'};
const Set<String> _evalCodes = {
  'forbidden_origin',
  'eval_error',
  'not_serializable',
  'result_too_large',
};

String _cut(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

int? _int(Object? v) => v is num && v.isFinite && v >= 0 ? v.round() : null;

/// Parses one message; `null` for anything malformed, oversized or unknown
/// (dropped silently — a page can send anything).
BridgeMessage? parseBridgeMessage(String raw) {
  if (raw.length > kBridgeMessageMax) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  switch (decoded['t']) {
    case 'console':
      final level = decoded['level'];
      final text = decoded['text'];
      if (level is! String || !_levels.contains(level) || text is! String) {
        return null;
      }
      final url = decoded['url'];
      return ConsoleMessage(
        level: level,
        text: _cut(text, kConsoleTextMax),
        url: url is String ? _cut(url, kNetworkUrlMax) : '',
      );
    case 'net':
      final url = decoded['url'];
      final type = decoded['type'];
      if (url is! String || url.isEmpty || type is! String) return null;
      final method = decoded['method'];
      return NetworkMessage(
        url: _cut(url, kNetworkUrlMax),
        type: _cut(type, 32),
        method: method is String ? _cut(method.toUpperCase(), 16) : null,
        status: _int(decoded['status']),
        durationMs: _int(decoded['dur']),
        size: _int(decoded['size']),
      );
    case 'title':
      final title = decoded['title'];
      return title is String ? TitleMessage(_cut(title, 1024)) : null;
    case 'eval':
      final nonce = decoded['n'];
      if (nonce is! String || nonce.isEmpty) return null;
      if (decoded['ok'] == true) {
        final json = decoded['json'];
        if (json is! String) return null;
        if (utf8.encode(json).length > kEvalResultMax) {
          return EvalResultMessage.failed(nonce, 'result_too_large', null);
        }
        return EvalResultMessage.ok(nonce, json);
      }
      final code = decoded['code'];
      if (code is! String || !_evalCodes.contains(code)) return null;
      final message = decoded['message'];
      return EvalResultMessage.failed(
        nonce,
        code,
        message is String ? _cut(message, kConsoleTextMax) : null,
      );
  }
  return null;
}

/// D19, D20: the script text the engine runs for one `evalJs`. The body
/// runs as an async function body; the page's origin is checked again
/// inside the page (it may have navigated since Dart checked); the result
/// goes back through the bridge tagged with [nonce]. No `eval()` or
/// `new Function`, so the page's CSP does not apply.
String buildEvalScript({
  required String nonce,
  required String body,
  required bool allowAnyOrigin,
  required BridgeTransport transport,
}) {
  final n = jsonEncode(nonce);
  return '''
(function () {
  var post = function (m) {
    try { var s = JSON.stringify(m); ${transport.postStatement}; } catch (e) {}
  };
  var n = $n;
  var h = location.hostname, p = location.protocol;
  var allowed = $allowAnyOrigin || location.href === 'about:blank' ||
    ((p === 'http:' || p === 'https:') &&
     (h === 'localhost' || /\\.localhost\$/.test(h) || h === '[::1]' ||
      h === '::1' || h === '0.0.0.0' || /^127\\.\\d+\\.\\d+\\.\\d+\$/.test(h)));
  if (!allowed) { post({t: 'eval', n: n, ok: false, code: 'forbidden_origin'}); return; }
  var fail = function (code, e) {
    post({t: 'eval', n: n, ok: false, code: code,
          message: String(e && e.message || e).slice(0, $kConsoleTextMax)});
  };
  (async function () {
$body
  })().then(function (v) {
    var s;
    try { s = JSON.stringify(v === undefined ? null : v); }
    catch (e) { fail('not_serializable', e); return; }
    if (s === undefined) s = 'null';
    if (s.length > $kEvalResultMax) { post({t: 'eval', n: n, ok: false, code: 'result_too_large'}); return; }
    post({t: 'eval', n: n, ok: true, json: s});
  }, function (e) { fail('eval_error', e); });
})();
''';
}
```

- [ ] **Step 4: Add the bootstrap script**

Create `apps/desktop/assets/browser/browser_bootstrap.js` and `git rm apps/desktop/assets/browser/.gitkeep`:

```js
// ShellX browser pane bootstrap (A6 D10, D21–D23). Injected at document
// start in the top frame, page world. Everything it sends is data for the
// pane's console/network buffers and title; ShellX never takes commands
// from the page. Kept small and defensive: a page may break any global.
(function () {
  'use strict';
  if (window.__shellxBootstrap) return;
  Object.defineProperty(window, '__shellxBootstrap', { value: true });

  var send = (function () {
    try {
      if (window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.ShellxBrowser) {
        var h = window.webkit.messageHandlers.ShellxBrowser;
        return function (s) { h.postMessage(s); };
      }
      if (window.chrome && window.chrome.webview) {
        var w = window.chrome.webview;
        return function (s) { w.postMessage(s); };
      }
    } catch (e) {}
    return function () {};
  })();
  var stringify = JSON.stringify;
  var post = function (m) { try { send(stringify(m)); } catch (e) {} };
  var MAX = 2048;

  var text = function (v) {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return String(v.stack || v.message || v);
    try {
      var s = stringify(v);
      return s === undefined ? String(v) : s;
    } catch (e) {
      return String(v);
    }
  };
  var join = function (args) {
    var out = '';
    for (var i = 0; i < args.length && out.length < MAX; i++) {
      out += (i ? ' ' : '') + text(args[i]);
    }
    return out.slice(0, MAX);
  };

  // Console (D22).
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var original = console[level];
    console[level] = function () {
      post({ t: 'console', level: level, text: join(arguments), url: location.href });
      if (original) return original.apply(console, arguments);
    };
  });
  window.addEventListener('error', function (e) {
    post({ t: 'console', level: 'error', url: location.href,
           text: join([e.message || 'Error', (e.filename || '') + ':' + (e.lineno || 0)]) });
  });
  window.addEventListener('unhandledrejection', function (e) {
    post({ t: 'console', level: 'error', url: location.href,
           text: join(['Unhandled rejection:', e.reason]) });
  });

  // Network (D23): resource timing, plus method/status from fetch and XHR.
  var net = function (m) { m.t = 'net'; m.url = String(m.url).slice(0, MAX); post(m); };
  try {
    new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (e) {
        if (e.initiatorType === 'fetch' || e.initiatorType === 'xmlhttprequest') return;
        net({ url: e.name, type: e.entryType === 'navigation' ? 'navigation' : e.initiatorType,
              status: e.responseStatus || undefined, dur: e.duration,
              size: e.transferSize || undefined });
      });
    }).observe({ entryTypes: ['resource', 'navigation'] });
  } catch (e) {}
  if (window.fetch) {
    var originalFetch = window.fetch;
    window.fetch = function (input, init) {
      var started = Date.now();
      var method = (init && init.method) || (input && input.method) || 'GET';
      var url = (input && input.url) || String(input);
      return originalFetch.apply(this, arguments).then(function (r) {
        net({ url: r.url || url, type: 'fetch', method: method, status: r.status,
              dur: Date.now() - started });
        return r;
      }, function (err) {
        net({ url: url, type: 'fetch', method: method, dur: Date.now() - started });
        throw err;
      });
    };
  }
  if (window.XMLHttpRequest) {
    var open = XMLHttpRequest.prototype.open;
    var sendXhr = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function (method, url) {
      this.__shellx = { method: method, url: url };
      return open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
      var x = this, info = x.__shellx || {}, started = Date.now();
      x.addEventListener('loadend', function () {
        net({ url: x.responseURL || info.url, type: 'xmlhttprequest',
              method: info.method, status: x.status || undefined, dur: Date.now() - started });
      });
      return sendXhr.apply(this, arguments);
    };
  }

  // Title (D21): WKWebView has no title callback through the plugin.
  var lastTitle = null;
  var reportTitle = function () {
    if (document.title !== lastTitle) {
      lastTitle = document.title;
      post({ t: 'title', title: lastTitle });
    }
  };
  document.addEventListener('DOMContentLoaded', function () {
    reportTitle();
    try {
      new MutationObserver(reportTitle).observe(document.head || document.documentElement,
        { subtree: true, childList: true, characterData: true });
    } catch (e) {}
  });

  // Popups open in the same pane (D10) — macOS only; WebView2 uses its
  // popup policy. Harmless on Windows.
  if (window.webkit) {
    window.open = function (url) {
      if (url) location.assign(url);
      return null;
    };
    document.addEventListener('click', function (e) {
      var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
      if (a && a.target !== '_self' && a.href) {
        e.preventDefault();
        location.assign(a.href);
      }
    }, true);
  }
})();
```

Syntax-check it (Node is used only as a parser here): `node --check apps/desktop/assets/browser/browser_bootstrap.js`. Expected: no output, exit 0.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_bridge_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 6: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/browser/browser_bridge.dart apps/desktop/test/browser/browser_bridge_test.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/browser/browser_bridge.dart apps/desktop/assets/browser/browser_bootstrap.js apps/desktop/test/browser/browser_bridge_test.dart
git commit -m "feat(desktop): browser bridge messages, eval script and bootstrap script (A6 D19, D21-D23)"
```

---

### Task 4: Engine interface, fake engine and `BrowserController` (D18–D25)

**Files:**
- Create: `apps/desktop/lib/src/browser/browser_engine.dart`
- Create: `apps/desktop/lib/src/browser/browser_controller.dart`
- Create: `apps/desktop/test/support/fake_browser_engine.dart`
- Test: `apps/desktop/test/browser/browser_controller_test.dart`

**Interfaces:**
- Consumes: Task 2 (`classifyOrigin`, `isNavigable`, `BrowserOrigin`), Task 3 (`parseBridgeMessage`, `buildEvalScript`, `BridgeTransport`, `kEvalScriptMax`, message classes).
- Produces:
  - `browser_engine.dart`: `enum BrowserLoadErrorKind { refused, unreachable, dns, timeout, certificate, crashed, unavailable, other }`; `sealed class BrowserEngineEvent` with `UrlChanged(Uri url)`, `TitleChanged(String title)`, `LoadStarted()`, `LoadProgress(int percent)`, `LoadFinished()`, `LoadFailed(BrowserLoadErrorKind kind)`, `HistoryChanged({canGoBack, canGoForward})`, `BridgeReceived(String raw)`, `NavigationBlocked()`, `DownloadBlocked()`, `ShortcutForwarded(String chord)`, `ContentClicked()`; `abstract interface class BrowserEngine { Stream<BrowserEngineEvent> get events; BridgeTransport get transport; Future<void> load(Uri); goBack(); goForward(); reload(); stop(); Future<void> runScript(String); Future<Uint8List> capturePng(); Future<void> setForwardedChords(List<String>); Future<void> focusContent(); Future<void> releaseFocus(); Widget buildView(); Future<void> dispose(); }`.
  - `browser_controller.dart`: `BrowserError(code, [message])`; `BrowserPaneState {url, title, loading, progress?, canGoBack, canGoForward, error?, agentActive, userNavigation; origin; copyWith}`; `ConsoleEntry`, `NetworkEntry`, `BrowserPageInfo {url, title}`; `enum BrowserNotice { schemeBlocked, downloadBlocked, agentStarted }`; constants `kBufferSize`, `kListLimit`, `kBridgeMessagesPerSecond`, `kAgentMarkFor`, `kAgentAnnounceGap`, `kEvalTimeout`, `kEvalTimeoutMax`, `kWaitTimeout`, `kWaitTimeoutMax`; `BrowserController({required int paneId, required BrowserEngine engine, required Uri initialUrl, required bool Function() allowAnyOrigin, required void Function(BrowserPaneState) onState, void Function(BrowserNotice)? onNotice, void Function(String chord)? onShortcut, void Function()? onContentClicked, DateTime Function()? clock, String Function()? nonce})` with `state`, `navigate(Uri, {bool byUser})`, `back/forward/reload({bool byUser})`, `stop()`, `waitForLoad({Duration timeout})`, `evalJs(String body, {Duration timeout})`, `screenshot()`, `console({since, limit, level})`, `network({since, limit})`, `agentCommand()`, `dispose()`, and pass-throughs to the engine for the pane view: `buildView()`, `focusContent()`, `releaseFocus()`, `setForwardedChords(List<String>)`.
  - `test/support/fake_browser_engine.dart`: `FakeBrowserEngine` with `emit(event)`, `loads`, `calls`, `scripts`, `forwarded`, `scriptError`, `png`, `onCapture`, `disposed`.

- [ ] **Step 1: Write the fake and the failing test**

Create `apps/desktop/test/support/fake_browser_engine.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:shellx_desktop/src/browser/browser_bridge.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';

/// Test double: records calls, lets tests push engine events.
final class FakeBrowserEngine implements BrowserEngine {
  FakeBrowserEngine({this.transport = BridgeTransport.webkit});

  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast(sync: true);
  @override
  final BridgeTransport transport;

  final List<Uri> loads = [];
  final List<String> calls = [];
  final List<String> scripts = [];
  List<String> forwarded = const [];
  Object? scriptError;
  Uint8List png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
  void Function()? onCapture;
  bool disposed = false;

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
  Future<void> runScript(String script) async {
    if (scriptError != null) throw scriptError!;
    scripts.add(script);
  }

  @override
  Future<Uint8List> capturePng() async {
    onCapture?.call();
    return png;
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async =>
      forwarded = chords;

  @override
  Future<void> focusContent() async => calls.add('focus');

  @override
  Future<void> releaseFocus() async => calls.add('release');

  @override
  Widget buildView() => const SizedBox.expand(key: Key('browser.fakeView'));

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
```

Create `apps/desktop/test/browser/browser_controller_test.dart`:

```dart
import 'dart:convert';

import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import '../support/fake_browser_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

late FakeBrowserEngine engine;
late BrowserController controller;
late List<BrowserPaneState> states;
late List<BrowserNotice> notices;
late List<String> chords;
late int clicks;
bool anyOrigin = false;
DateTime now = DateTime(2026, 10, 7, 9);
int nonces = 0;

void boot({String url = 'http://localhost:8000/'}) {
  engine = FakeBrowserEngine();
  states = [];
  notices = [];
  chords = [];
  clicks = 0;
  anyOrigin = false;
  nonces = 0;
  controller = BrowserController(
    paneId: -1,
    engine: engine,
    initialUrl: Uri.parse(url),
    allowAnyOrigin: () => anyOrigin,
    onState: states.add,
    onNotice: notices.add,
    onShortcut: chords.add,
    onContentClicked: () => clicks++,
    clock: () => now,
    nonce: () => 'nonce${++nonces}',
  );
}

void bridge(Map<String, Object?> m) =>
    engine.emit(BridgeReceived(jsonEncode(m)));

void answer(String nonce, Object? value) =>
    bridge({'t': 'eval', 'n': nonce, 'ok': true, 'json': jsonEncode(value)});

Matcher browserError(String code) =>
    isA<BrowserError>().having((e) => e.code, 'code', code);

void main() {
  setUp(boot);

  test('engine events drive the pane state', () {
    engine.emit(const LoadStarted());
    expect(controller.state.loading, isTrue);
    expect(controller.state.progress, isNull);
    engine.emit(const LoadProgress(40));
    engine.emit(UrlChanged(Uri.parse('http://localhost:8000/docs')));
    engine.emit(const TitleChanged('Docs'));
    engine.emit(const HistoryChanged(canGoBack: true, canGoForward: false));
    engine.emit(const LoadFinished());
    final s = controller.state;
    expect(s.loading, isFalse);
    expect(s.progress, 100);
    expect(s.url.toString(), 'http://localhost:8000/docs');
    expect(s.title, 'Docs');
    expect(s.canGoBack, isTrue);
    expect(states, isNotEmpty);
  });

  test(
    'navigate refuses non-web schemes; user navigation is flagged (D10, D17)',
    () async {
      expect(
        () => controller.navigate(Uri.parse('file:///etc/passwd')),
        throwsA(browserError('navigation_blocked')),
      );
      await controller.navigate(
        Uri.parse('http://localhost:3000/'),
        byUser: true,
      );
      expect(engine.loads.single.toString(), 'http://localhost:3000/');
      expect(controller.state.userNavigation, isTrue);
    },
  );

  group('evalJs (D19)', () {
    test('returns the decoded JSON value for its own nonce', () async {
      final result = controller.evalJs('return document.title;');
      await Future<void>.delayed(Duration.zero);
      expect(engine.scripts.single, contains('"nonce1"'));
      answer('nonce1', {'a': 1});
      expect(await result, {'a': 1});
    });

    test('a forged result for another nonce is ignored', () async {
      final result = controller.evalJs('return 1;');
      await Future<void>.delayed(Duration.zero);
      answer('someone-else', 'forged');
      answer('nonce1', 1);
      expect(await result, 1);
    });

    test('page errors map to codes', () async {
      final result = controller.evalJs('throw 1;');
      await Future<void>.delayed(Duration.zero);
      bridge({
        't': 'eval',
        'n': 'nonce1',
        'ok': false,
        'code': 'not_serializable',
        'message': 'cyclic',
      });
      await expectLater(result, throwsA(browserError('not_serializable')));
    });

    test('engine rejecting the script → eval_error', () async {
      engine.scriptError = StateError('syntax');
      await expectLater(
        controller.evalJs('return ('),
        throwsA(browserError('eval_error')),
      );
    });

    test('times out (default 10 s, capped at 30 s)', () {
      fakeAsync((async) {
        Object? error;
        controller
            .evalJs('return 1;', timeout: const Duration(minutes: 5))
            .catchError((Object e) {
              error = e;
              return null;
            });
        async.elapse(const Duration(seconds: 29));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, browserError('timeout'));
      });
    });

    test('oversized body → bad_request', () {
      expect(
        () => controller.evalJs('x' * (32 * 1024 + 1)),
        throwsA(browserError('bad_request')),
      );
    });
  });

  group('origin gate (D20)', () {
    setUp(() => boot(url: 'https://example.com/'));

    test('content reads refused on a non-local page by default', () async {
      await expectLater(
        controller.evalJs('return 1;'),
        throwsA(browserError('forbidden_origin')),
      );
      await expectLater(
        controller.screenshot(),
        throwsA(browserError('forbidden_origin')),
      );
      expect(
        () => controller.console(),
        throwsA(browserError('forbidden_origin')),
      );
      expect(
        () => controller.network(),
        throwsA(browserError('forbidden_origin')),
      );
      expect(engine.scripts, isEmpty);
    });

    test('allowed when the setting is on; the script carries it', () async {
      anyOrigin = true;
      final result = controller.evalJs('return 1;');
      await Future<void>.delayed(Duration.zero);
      expect(engine.scripts.single, contains('var allowed = true ||'));
      answer('nonce1', 1);
      expect(await result, 1);
    });

    test('navigation and waiting are always allowed', () async {
      await controller.navigate(Uri.parse('https://example.org/'));
      final wait = controller.waitForLoad();
      engine.emit(const LoadFinished());
      expect(await wait, isA<BrowserPageInfo>());
    });
  });

  test(
    'screenshot discarded when the page left for a non-local origin',
    () async {
      engine.onCapture = () =>
          engine.emit(UrlChanged(Uri.parse('https://bank.example/')));
      await expectLater(
        controller.screenshot(),
        throwsA(browserError('forbidden_origin')),
      );
      engine.onCapture = null;
      boot();
      expect(await controller.screenshot(), engine.png);
    },
  );

  group('console and network (D22, D23)', () {
    test('ring of 500, since/limit paging, level filter', () {
      for (var i = 0; i < 520; i++) {
        now = now.add(const Duration(seconds: 1)); // stay under the rate limit
        bridge({
          't': 'console',
          'level': i.isEven ? 'log' : 'error',
          'text': 'm$i',
        });
      }
      final first = controller.console();
      expect(first.length, 200);
      expect(first.first.text, 'm20'); // the 20 oldest fell out
      final next = controller.console(since: first.last.seq);
      expect(next.first.text, 'm220');
      expect(controller.console(level: 'error', limit: 5).map((e) => e.text), [
        'm21',
        'm23',
        'm25',
        'm27',
        'm29',
      ]);
    });

    test('network entries', () {
      bridge({
        't': 'net',
        'url': 'http://localhost:8000/',
        'type': 'navigation',
        'method': 'GET',
        'status': 200,
      });
      final e = controller.network().single;
      expect(e.method, 'GET');
      expect(e.status, 200);
    });

    test(
      'more than 200 messages a second: the excess is dropped and counted',
      () {
        for (var i = 0; i < 250; i++) {
          bridge({'t': 'console', 'level': 'log', 'text': 'flood $i'});
        }
        expect(controller.console(limit: 200).length, 200);
        now = now.add(const Duration(seconds: 2));
        bridge({'t': 'console', 'level': 'log', 'text': 'after'});
        final tail = controller.console(since: 200).map((e) => e.text).toList();
        expect(tail, ['[shellx] dropped 50', 'after']);
      },
    );
  });

  group('waitForLoad (D24)', () {
    test(
      'resolves on finish, fails on load error, at once when idle',
      () async {
        expect(
          (await controller.waitForLoad()).url.toString(),
          'http://localhost:8000/',
        );
        engine.emit(const LoadStarted());
        final ok = controller.waitForLoad();
        engine.emit(const TitleChanged('Hi'));
        engine.emit(const LoadFinished());
        expect((await ok).title, 'Hi');
        engine.emit(const LoadStarted());
        final failed = controller.waitForLoad();
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
        await expectLater(failed, throwsA(browserError('load_failed')));
      },
    );

    test('times out', () {
      fakeAsync((async) {
        engine.emit(const LoadStarted());
        Object? error;
        controller.waitForLoad(timeout: const Duration(seconds: 2)).catchError((
          Object e,
        ) {
          error = e;
          return BrowserPageInfo(url: Uri(), title: '');
        });
        async.elapse(const Duration(seconds: 3));
        expect(error, browserError('timeout'));
      });
    });
  });

  test(
    'agent mark lasts 10 s after the last command; announced once a burst (D25)',
    () {
      fakeAsync((async) {
        controller.agentCommand();
        expect(controller.state.agentActive, isTrue);
        expect(notices, [BrowserNotice.agentStarted]);
        async.elapse(const Duration(seconds: 6));
        controller.agentCommand();
        async.elapse(const Duration(seconds: 6));
        expect(controller.state.agentActive, isTrue);
        async.elapse(const Duration(seconds: 5));
        expect(controller.state.agentActive, isFalse);
        now = now.add(const Duration(seconds: 30));
        controller.agentCommand();
        expect(notices, [
          BrowserNotice.agentStarted,
        ]); // < 60 s since the last one
        now = now.add(const Duration(seconds: 61));
        async.elapse(const Duration(seconds: 11));
        controller.agentCommand();
        expect(notices, [
          BrowserNotice.agentStarted,
          BrowserNotice.agentStarted,
        ]);
      });
    },
  );

  test('notices and forwarded shortcuts', () {
    engine.emit(const NavigationBlocked());
    engine.emit(const DownloadBlocked());
    engine.emit(const ShortcutForwarded('meta+l'));
    engine.emit(const ContentClicked());
    expect(clicks, 1);
    expect(notices, [
      BrowserNotice.schemeBlocked,
      BrowserNotice.downloadBlocked,
    ]);
    expect(chords, ['meta+l']);
  });

  test(
    'dispose fails pending calls with not_found and disposes the engine',
    () async {
      final pending = controller.evalJs('return 1;');
      await Future<void>.delayed(Duration.zero);
      final check = expectLater(pending, throwsA(browserError('not_found')));
      await controller.dispose();
      await check;
      expect(engine.disposed, isTrue);
      expect(() => controller.reload(), throwsA(browserError('not_found')));
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_controller_test.dart`
Expected: FAIL — `browser_engine.dart` / `browser_controller.dart` do not exist.

- [ ] **Step 3: Implement the engine interface**

Create `apps/desktop/lib/src/browser/browser_engine.dart`:

```dart
/// A6 §3.2: what a browser pane needs from WKWebView / WebView2. One
/// implementation per platform (Tasks 7, 8) and a fake for tests.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Widget;

import 'browser_bridge.dart';


/// D14: why a load failed (drives the error page copy).
enum BrowserLoadErrorKind {
  refused,
  unreachable,
  dns,
  timeout,
  certificate,
  crashed,
  unavailable,
  other,
}

sealed class BrowserEngineEvent {
  const BrowserEngineEvent();
}

final class UrlChanged extends BrowserEngineEvent {
  const UrlChanged(this.url);
  final Uri url;
}

final class TitleChanged extends BrowserEngineEvent {
  const TitleChanged(this.title);
  final String title;
}

final class LoadStarted extends BrowserEngineEvent {
  const LoadStarted();
}

/// 0–100; engines without progress (WebView2) never send it (D13).
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
}

final class HistoryChanged extends BrowserEngineEvent {
  const HistoryChanged({required this.canGoBack, required this.canGoForward});
  final bool canGoBack;
  final bool canGoForward;
}

/// One raw bridge message from the page (D21) — parsed by the controller.
final class BridgeReceived extends BrowserEngineEvent {
  const BridgeReceived(this.raw);
  final String raw;
}

/// D10: a top-level navigation to a scheme a pane may not show.
final class NavigationBlocked extends BrowserEngineEvent {
  const NavigationBlocked();
}

/// D10: a download was cancelled.
final class DownloadBlocked extends BrowserEngineEvent {
  const DownloadBlocked();
}

/// D15: a ShellX chord pressed while the web content had the keyboard.
final class ShortcutForwarded extends BrowserEngineEvent {
  const ShortcutForwarded(this.chord);
  final String chord;
}

/// D16: a mouse press inside the web content (macOS reports it natively;
/// on Windows the Flutter `Listener` around the texture sees it).
final class ContentClicked extends BrowserEngineEvent {
  const ContentClicked();
}

abstract interface class BrowserEngine {
  Stream<BrowserEngineEvent> get events;

  /// The page → ShellX channel this engine uses (D21).
  BridgeTransport get transport;

  Future<void> load(Uri url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stop();

  /// Runs [script] in the top frame; the result, if any, comes back as a
  /// [BridgeReceived] (D19). Throws when the engine rejects the script.
  Future<void> runScript(String script);

  /// D24: the viewport as PNG at the screen's pixel ratio.
  Future<Uint8List> capturePng();

  /// D15: the chords to hand back to Flutter while the page has focus.
  Future<void> setForwardedChords(List<String> chords);

  /// D16: give the keyboard to the web content (first responder /
  /// WebView2 `MoveFocus`).
  Future<void> focusContent();

  /// D16: give the keyboard back to Flutter (the page must not keep the
  /// first responder once another pane or region has the focus).
  Future<void> releaseFocus();

  Widget buildView();

  Future<void> dispose();
}
```

- [ ] **Step 4: Implement the controller**

Create `apps/desktop/lib/src/browser/browser_controller.dart`:

```dart
/// A6 D18–D25: one browser pane's programmable side (W4) — the API A7
/// exposes, the origin gate, the console/network buffers.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'browser_bridge.dart';
import 'browser_engine.dart';
import 'browser_url.dart';

/// D18: every failure the API reports; [code] is the wire code (§3.6).
final class BrowserError implements Exception {
  const BrowserError(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'BrowserError($code)';
}

/// What the toolbar, the pane header and A7 `list` show (§3.1).
final class BrowserPaneState {
  const BrowserPaneState({
    required this.url,
    this.title = '',
    this.loading = false,
    this.progress,
    this.canGoBack = false,
    this.canGoForward = false,
    this.error,
    this.agentActive = false,
    this.userNavigation = false,
  });

  final Uri url;
  final String title;
  final bool loading;

  /// 0–100, `null` when the engine does not report progress (D13).
  final int? progress;
  final bool canGoBack;
  final bool canGoForward;
  final BrowserLoadErrorKind? error;

  /// D25: an agent command arrived in the last 10 s.
  final bool agentActive;

  /// D17: the current navigation was started by the user (announce it).
  final bool userNavigation;

  BrowserOrigin get origin => classifyOrigin(url);

  BrowserPaneState copyWith({
    Uri? url,
    String? title,
    bool? loading,
    Object? progress = _keep,
    bool? canGoBack,
    bool? canGoForward,
    Object? error = _keep,
    bool? agentActive,
    bool? userNavigation,
  }) => BrowserPaneState(
    url: url ?? this.url,
    title: title ?? this.title,
    loading: loading ?? this.loading,
    progress: identical(progress, _keep) ? this.progress : progress as int?,
    canGoBack: canGoBack ?? this.canGoBack,
    canGoForward: canGoForward ?? this.canGoForward,
    error: identical(error, _keep)
        ? this.error
        : error as BrowserLoadErrorKind?,
    agentActive: agentActive ?? this.agentActive,
    userNavigation: userNavigation ?? this.userNavigation,
  );
}

const Object _keep = Object();

/// D22.
final class ConsoleEntry {
  const ConsoleEntry({
    required this.seq,
    required this.ts,
    required this.level,
    required this.text,
    required this.url,
  });
  final int seq;
  final DateTime ts;
  final String level;
  final String text;
  final String url;
}

/// D23.
final class NetworkEntry {
  const NetworkEntry({
    required this.seq,
    required this.ts,
    required this.url,
    required this.type,
    this.method,
    this.status,
    this.durationMs,
    this.size,
  });
  final int seq;
  final DateTime ts;
  final String url;
  final String type;
  final String? method;
  final int? status;
  final int? durationMs;
  final int? size;
}

final class BrowserPageInfo {
  const BrowserPageInfo({required this.url, required this.title});
  final Uri url;
  final String title;
}

/// Things the UI turns into a toast or an announcement.
enum BrowserNotice { schemeBlocked, downloadBlocked, agentStarted }

const int kBufferSize = 500;
const int kListLimit = 200;
const int kBridgeMessagesPerSecond = 200;
const Duration kAgentMarkFor = Duration(seconds: 10);
const Duration kAgentAnnounceGap = Duration(seconds: 60);
const Duration kEvalTimeout = Duration(seconds: 10);
const Duration kEvalTimeoutMax = Duration(seconds: 30);
const Duration kWaitTimeout = Duration(seconds: 15);
const Duration kWaitTimeoutMax = Duration(seconds: 60);

final class BrowserController {
  BrowserController({
    required this.paneId,
    required BrowserEngine engine,
    required Uri initialUrl,
    required bool Function() allowAnyOrigin,
    required void Function(BrowserPaneState state) onState,
    void Function(BrowserNotice notice)? onNotice,
    void Function(String chord)? onShortcut,
    void Function()? onContentClicked,
    DateTime Function()? clock,
    String Function()? nonce,
  }) : _engine = engine,
       _allowAnyOrigin = allowAnyOrigin,
       _onState = onState,
       _onNotice = onNotice ?? ((_) {}),
       _onShortcut = onShortcut ?? ((_) {}),
       _onContentClicked = onContentClicked ?? (() {}),
       _clock = clock ?? DateTime.now,
       _nonce = nonce ?? _randomNonce,
       _state = BrowserPaneState(url: initialUrl) {
    _sub = engine.events.listen(_onEvent);
  }

  final int paneId;
  final BrowserEngine _engine;
  final bool Function() _allowAnyOrigin;
  final void Function(BrowserPaneState) _onState;
  final void Function(BrowserNotice) _onNotice;
  final void Function(String) _onShortcut;
  final void Function() _onContentClicked;
  final DateTime Function() _clock;
  final String Function() _nonce;
  late final StreamSubscription<BrowserEngineEvent> _sub;

  BrowserPaneState _state;
  BrowserPaneState get state => _state;

  final Queue<ConsoleEntry> _console = Queue();
  final Queue<NetworkEntry> _network = Queue();
  int _seq = 0;
  final Map<String, Completer<Object?>> _evals = {};
  final List<Completer<BrowserPageInfo>> _waiters = [];
  Timer? _agentTimer;
  DateTime? _lastAnnounce;
  DateTime? _windowStart;
  int _windowCount = 0;
  int _dropped = 0;
  bool _disposed = false;

  static String _randomNonce() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _set(BrowserPaneState next) {
    _state = next;
    if (!_disposed) _onState(next);
  }

  // ---- user and agent commands ----

  Future<void> navigate(Uri url, {bool byUser = false}) {
    _alive();
    if (!isNavigable(url)) throw const BrowserError('navigation_blocked');
    // Loading from now on, not from the engine's first event: a
    // waitForLoad() right after navigate() must wait for this page (§6).
    _set(
      _state.copyWith(
        url: url,
        loading: true,
        progress: null,
        error: null,
        userNavigation: byUser,
      ),
    );
    return _engine.load(url);
  }

  Future<void> back({bool byUser = false}) {
    _alive();
    _set(_state.copyWith(userNavigation: byUser));
    return _engine.goBack();
  }

  Future<void> forward({bool byUser = false}) {
    _alive();
    _set(_state.copyWith(userNavigation: byUser));
    return _engine.goForward();
  }

  Future<void> reload({bool byUser = false}) {
    _alive();
    _set(
      _state.copyWith(
        loading: true,
        progress: null,
        error: null,
        userNavigation: byUser,
      ),
    );
    return _engine.reload();
  }

  Future<void> stop() {
    _alive();
    return _engine.stop();
  }

  /// D24: settles when the current navigation finishes; at once when
  /// nothing is loading.
  Future<BrowserPageInfo> waitForLoad({Duration timeout = kWaitTimeout}) {
    _alive();
    if (!_state.loading) {
      final error = _state.error;
      if (error != null) {
        return Future.error(BrowserError('load_failed', error.name));
      }
      return Future.value(_info());
    }
    final c = Completer<BrowserPageInfo>();
    _waiters.add(c);
    return c.future.timeout(
      _clamp(timeout, kWaitTimeoutMax),
      onTimeout: () {
        _waiters.remove(c);
        throw const BrowserError('timeout');
      },
    );
  }

  /// D19: [body] is an async function body; the result is the decoded
  /// JSON value (`null` for undefined).
  Future<Object?> evalJs(String body, {Duration timeout = kEvalTimeout}) async {
    _alive();
    if (body.length > kEvalScriptMax) throw const BrowserError('bad_request');
    _gate();
    final nonce = _nonce();
    final c = Completer<Object?>();
    _evals[nonce] = c;
    try {
      await _engine.runScript(
        buildEvalScript(
          nonce: nonce,
          body: body,
          allowAnyOrigin: _allowAnyOrigin(),
          transport: _engine.transport,
        ),
      );
    } on Object catch (e) {
      _evals.remove(nonce);
      throw BrowserError('eval_error', e.runtimeType.toString());
    }
    return c.future.timeout(
      _clamp(timeout, kEvalTimeoutMax),
      onTimeout: () {
        _evals.remove(nonce);
        throw const BrowserError('timeout');
      },
    );
  }

  /// D20, D24: refused when the page left an allowed origin meanwhile.
  Future<Uint8List> screenshot() async {
    _alive();
    _gate();
    final before = _state.url;
    final png = await _engine.capturePng();
    if (_state.url != before) _gate();
    return png;
  }

  List<ConsoleEntry> console({
    int since = 0,
    int limit = kListLimit,
    String? level,
  }) {
    _alive();
    _gate();
    return _page(
      _console,
      since,
      limit,
      (e) => e.seq,
      (e) => level == null || e.level == level,
    );
  }

  List<NetworkEntry> network({int since = 0, int limit = kListLimit}) {
    _alive();
    _gate();
    return _page(_network, since, limit, (e) => e.seq, (_) => true);
  }

  /// The engine's view and focus, for BrowserPaneView (Task 9).
  Widget buildView() => _engine.buildView();
  Future<void> focusContent() => _engine.focusContent();
  Future<void> releaseFocus() => _engine.releaseFocus();
  Future<void> setForwardedChords(List<String> chords) =>
      _engine.setForwardedChords(chords);

  /// D25: called by the A7 command handler for every command on this pane.
  void agentCommand() {
    _alive();
    _agentTimer?.cancel();
    _agentTimer = Timer(
      kAgentMarkFor,
      () => _set(_state.copyWith(agentActive: false)),
    );
    final now = _clock();
    if (!_state.agentActive &&
        (_lastAnnounce == null ||
            now.difference(_lastAnnounce!) >= kAgentAnnounceGap)) {
      _lastAnnounce = now;
      _onNotice(BrowserNotice.agentStarted);
    }
    if (!_state.agentActive) _set(_state.copyWith(agentActive: true));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _agentTimer?.cancel();
    await _sub.cancel();
    for (final c in _evals.values) {
      c.completeError(const BrowserError('not_found'));
    }
    _evals.clear();
    for (final c in _waiters) {
      c.completeError(const BrowserError('not_found'));
    }
    _waiters.clear();
    await _engine.dispose();
  }

  // ---- internals ----

  void _alive() {
    if (_disposed) throw const BrowserError('not_found');
  }

  void _gate() {
    final origin = _state.origin;
    if (origin == BrowserOrigin.local || origin == BrowserOrigin.none) return;
    if (_allowAnyOrigin()) return;
    throw const BrowserError('forbidden_origin');
  }

  static Duration _clamp(Duration d, Duration max) =>
      d > max ? max : (d <= Duration.zero ? max : d);

  BrowserPageInfo _info() =>
      BrowserPageInfo(url: _state.url, title: _state.title);

  List<T> _page<T>(
    Iterable<T> all,
    int since,
    int limit,
    int Function(T) seq,
    bool Function(T) keep,
  ) => all
      .where((e) => seq(e) > since && keep(e))
      .take(limit.clamp(1, kListLimit))
      .toList(growable: false);

  void _push<T>(Queue<T> q, T entry) {
    q.addLast(entry);
    while (q.length > kBufferSize) {
      q.removeFirst();
    }
  }

  /// D21 / §5: at most 200 bridge messages a second; the excess is counted
  /// into one `warn` entry when the next second starts.
  bool _admit() {
    final now = _clock();
    final start = _windowStart;
    if (start == null || now.difference(start) >= const Duration(seconds: 1)) {
      final dropped = _dropped;
      _windowStart = now;
      _windowCount = 0;
      _dropped = 0;
      if (dropped > 0) {
        _push(
          _console,
          ConsoleEntry(
            seq: ++_seq,
            ts: now,
            level: 'warn',
            text: '[shellx] dropped $dropped',
            url: _state.url.toString(),
          ),
        );
      }
    }
    if (_windowCount >= kBridgeMessagesPerSecond) {
      _dropped++;
      return false;
    }
    _windowCount++;
    return true;
  }

  void _onEvent(BrowserEngineEvent event) {
    switch (event) {
      case UrlChanged(:final url):
        _set(_state.copyWith(url: url));
      case TitleChanged(:final title):
        _set(_state.copyWith(title: title));
      case LoadStarted():
        _set(_state.copyWith(loading: true, progress: null, error: null));
      case LoadProgress(:final percent):
        _set(_state.copyWith(progress: percent.clamp(0, 100)));
      case LoadFinished():
        _set(_state.copyWith(loading: false, progress: 100));
        for (final c in _waiters) {
          c.complete(_info());
        }
        _waiters.clear();
      case LoadFailed(:final kind):
        _set(_state.copyWith(loading: false, progress: null, error: kind));
        for (final c in _waiters) {
          c.completeError(BrowserError('load_failed', kind.name));
        }
        _waiters.clear();
      case HistoryChanged(:final canGoBack, :final canGoForward):
        _set(_state.copyWith(canGoBack: canGoBack, canGoForward: canGoForward));
      case NavigationBlocked():
        _onNotice(BrowserNotice.schemeBlocked);
      case DownloadBlocked():
        _onNotice(BrowserNotice.downloadBlocked);
      case ShortcutForwarded(:final chord):
        _onShortcut(chord);
      case ContentClicked():
        _onContentClicked();
      case BridgeReceived(:final raw):
        _onBridge(raw);
    }
  }

  void _onBridge(String raw) {
    final message = parseBridgeMessage(raw);
    if (message == null) return;
    if (message is! EvalResultMessage && !_admit()) return;
    final now = _clock();
    switch (message) {
      case ConsoleMessage(:final level, :final text, :final url):
        _push(
          _console,
          ConsoleEntry(
            seq: ++_seq,
            ts: now,
            level: level,
            text: text,
            url: url,
          ),
        );
      case NetworkMessage m:
        _push(
          _network,
          NetworkEntry(
            seq: ++_seq,
            ts: now,
            url: m.url,
            type: m.type,
            method: m.method,
            status: m.status,
            durationMs: m.durationMs,
            size: m.size,
          ),
        );
      case TitleMessage(:final title):
        _set(_state.copyWith(title: title));
      case EvalResultMessage m:
        final c = _evals.remove(m.nonce);
        if (c == null)
          return; // not ours, or already settled: a page can forge these
        if (m.ok) {
          c.complete(jsonDecode(m.json!));
        } else {
          c.completeError(BrowserError(m.code!, m.message));
        }
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/`
Expected: PASS (all browser tests so far).

- [ ] **Step 6: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/browser apps/desktop/test/browser apps/desktop/test/support/fake_browser_engine.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/browser/browser_engine.dart apps/desktop/lib/src/browser/browser_controller.dart apps/desktop/test/support/fake_browser_engine.dart apps/desktop/test/browser/browser_controller_test.dart
git commit -m "feat(desktop): BrowserEngine interface and BrowserController with origin gate, buffers and waits (A6 D18-D25)"
```

---
### Task 5: Tab model — browser panes in the tree, D5 invariant, registry (D4–D7, D28, D31, D34)

A browser pane becomes a leaf of A3's tree with a negative id. `TerminalTab` keeps its `PaneSession`s in `panes` and its browser states in a new `browsers` map; the A3 getters follow the **active terminal pane** (D6). `BrowserRegistry` owns the `BrowserController`s, creates them lazily (the selected tab's panes, or on demand) and disposes them when their pane leaves the tree.

**Files:**
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart`
- Create: `apps/desktop/lib/src/browser/browser_registry.dart`
- Test: `apps/desktop/test/terminal/terminal_tabs_browser_test.dart`, `apps/desktop/test/browser/browser_registry_test.dart`

**Interfaces:**
- Consumes: A3 `TerminalTab` (`layout`, `panes`, `focusedPaneId`, `zoomedPaneId`, `paneHistory`, `paneOrder`, `isSplit`, `copyWith`, `withPane`), `TerminalTabs` (`_replaceTab`, `_removePane`, `_removeTab`, `_visibleChanged`, `_metrics`, `_roomToSplit`, `split`, `focusPane`, `closePane`, `_exited`, `_set`), `PaneMetrics {area, minPane, divider}`, `PaneNoRoomNotice`, `splitPane`, `paneRects`, `paneIds`; Task 2 `aboutBlank`; Task 4 `BrowserPaneState`, `BrowserController`, `BrowserError`, `BrowserNotice`, `BrowserEngine`.
- Produces:
  - In `terminal_tabs.dart`: `bool isBrowserPaneId(int id)`; `const int kMaxBrowserPanes = 8`; `const Size kBrowserMinSize = Size(240, 160)`; `TerminalTab.browsers` (`Map<int, BrowserPaneState>`, default `const {}`, in `copyWith`); `TerminalTab.activeTerminalPane` (`PaneSession`); `TerminalTabsState.tabOfPane(int id)`, `TerminalTabsState.browserCount`; `final class BrowserLimitNotice extends TabNotice { const BrowserLimitNotice(this.max); final int max; }`, `final class BrowserSchemeBlockedNotice extends TabNotice`, `final class BrowserDownloadBlockedNotice extends TabNotice` (all `const`); `int TerminalTabs.openBrowser({int? tabId, int? target, Uri? url, SplitAxis axis = SplitAxis.row, bool focus = true, bool notify = true})` (throws `BrowserError` `not_found` / `browser_limit` / `no_room`); `void TerminalTabs.updateBrowser(int id, BrowserPaneState state)`; `closePane`/`focusPane` accept negative ids.
  - In `browser_registry.dart`: `typedef BrowserEngineFactory = BrowserEngine Function(int paneId)`; `final browserEngineFactoryProvider = Provider<BrowserEngineFactory>`; `final browserAllowAnyOriginProvider = Provider<bool Function()>` (Task 6 makes it read the setting); `final class BrowserShortcut { const BrowserShortcut(this.paneId, this.chord); final int paneId; final String chord; }`; `final browserRegistryProvider = NotifierProvider<BrowserRegistry, Set<int>>(BrowserRegistry.new)`; `BrowserRegistry.controller(int paneId) → BrowserController?` (creates on demand), `BrowserRegistry.existing(int paneId) → BrowserController?` (never creates — for widgets of hidden tabs), `Stream<BrowserNotice> notices`, `Stream<BrowserShortcut> shortcuts`, `Stream<int> contentClicks`.

- [ ] **Step 1: Write the failing tab tests**

Create `apps/desktop/test/terminal/terminal_tabs_browser_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_url.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:xterm/xterm.dart' show TerminalKey;

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

void boot() {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
    ],
  );
  state();
}

Matcher browserError(String code) =>
    isA<BrowserError>().having((e) => e.code, 'code', code);

void main() {
  setUp(() => local = FakeLocalSessions());

  test('openBrowser splits right of the focused pane with a negative id, '
      'at the smallest port of the active terminal (D4, D7)', () {
    local.add(local.summary(1, ports: [5173, 3000]));
    boot();
    final id = tabs().openBrowser();
    expect(id, -1);
    expect(isBrowserPaneId(id), isTrue);
    final tab = state().tabs.single;
    expect(tab.layout, const PaneSplit(
      axis: SplitAxis.row, ratio: 0.5,
      first: PaneLeaf(1), second: PaneLeaf(-1),
    ));
    expect(tab.focusedPaneId, -1);
    expect(tab.browsers[-1]!.url.toString(), 'http://localhost:3000/');
    expect(tab.panes.keys, [1]); // never a session
    expect(state().tabOfPane(-1), same(tab));
    expect(state().tabOfSession(-1), isNull);
    expect(tabs().openBrowser(), -2); // ids never reused
  });

  test('no port → about:blank; explicit URL and target honoured', () {
    local.add(local.summary(1));
    boot();
    final a = tabs().openBrowser();
    expect(state().tabs.single.browsers[a]!.url, aboutBlank);
    final b = tabs().openBrowser(
      target: 1,
      url: Uri.parse('http://localhost:8000/docs'),
      axis: SplitAxis.column,
      focus: false,
    );
    final tab = state().tabs.single;
    expect(tab.focusedPaneId, a); // focus: false keeps the keyboard where it was
    expect(tab.browsers[b]!.url.toString(), 'http://localhost:8000/docs');
    expect(paneIds(tab.layout), [1, b, a]);
  });

  test('getters follow the active terminal pane while a browser is focused (D6)', () {
    local.add(local.summary(1, title: 'vim', cwd: '/w'));
    boot();
    tabs().openBrowser();
    final tab = state().tabs.single;
    expect(tab.focusedPaneId, -1);
    expect(tab.activeTerminalPane.id, 1);
    expect(tab.label, 'vim');
    expect(tab.cwd, '/w');
    expect(tab.paneCount, 2);
  });

  test('limit of 8 browser panes (D28) and no room (D31) → notice + error', () {
    local.add(local.summary(1));
    boot();
    for (var i = 0; i < kMaxBrowserPanes; i++) {
      tabs().openBrowser(target: 1);
    }
    expect(() => tabs().openBrowser(), throwsA(browserError('browser_limit')));
    expect(state().notice, isA<BrowserLimitNotice>());
    expect(state().browserCount, 8);

    local = FakeLocalSessions();
    local.add(local.summary(1));
    boot();
    tabs().reportPaneMetrics(
      const PaneMetrics(area: Size(400, 600), minPane: Size(170, 112), divider: 1),
    );
    expect(() => tabs().openBrowser(), throwsA(browserError('no_room')));
    expect(state().notice, isA<PaneNoRoomNotice>());
    expect(state().tabs.single.browsers, isEmpty);
  });

  test('agent opens (notify: false) raise no notice', () {
    local.add(local.summary(1));
    boot();
    for (var i = 0; i < kMaxBrowserPanes; i++) {
      tabs().openBrowser(target: 1, notify: false);
    }
    expect(() => tabs().openBrowser(notify: false), throwsA(browserError('browser_limit')));
    expect(state().notice, isNull);
  });

  test('closing a browser pane: MRU focus, no session closed', () {
    local.add(local.summary(1));
    boot();
    final id = tabs().openBrowser();
    tabs().closePane(id);
    final tab = state().tabs.single;
    expect(tab.browsers, isEmpty);
    expect(tab.layout, const PaneLeaf(1));
    expect(tab.focusedPaneId, 1);
    expect(local.closed, isEmpty);
  });

  test('D5: the last terminal pane exiting 0 stays (exit line) while a '
      'browser pane is there; Enter then closes the whole tab', () async {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    local.views[1]!.end(0);
    await pumpEventQueue();
    final tab = state().tabs.single;
    expect(tab.panes[1]!.exitCode, 0);
    expect(tab.panes[1]!.exited, isTrue);
    expect(tab.browsers.keys, [-1]);
    tab.panes[1]!.terminal.keyInput(TerminalKey.enter);
    expect(state().tabs, isEmpty);
  });

  test('D5: closing the last terminal pane closes the tab with its browsers', () {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    tabs().closePane(1);
    expect(local.closed, [1]);
    expect(state().tabs, isEmpty);
  });

  test('a second terminal pane exiting 0 still goes away (A3 D7)', () async {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    await tabs().split(SplitAxis.column); // from the browser pane: new terminal 100
    local.views[100]!.end(0);
    await pumpEventQueue();
    expect(state().tabs.single.panes.keys, [1]);
  });

  test('splitting a terminal from a focused browser pane uses the active '
      'terminal cwd (D6)', () async {
    local.add(local.summary(1, cwd: '/w/app'));
    boot();
    tabs().openBrowser();
    await tabs().split(SplitAxis.row);
    expect(local.openCwds.last, '/w/app');
  });

  test('focusPane selects the tab of a browser pane; updateBrowser stores state', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    final id = tabs().openBrowser(tabId: 1, focus: false);
    tabs().select(2);
    tabs().focusPane(id);
    expect(state().selectedId, 1);
    expect(state().tabs.first.focusedPaneId, id);
    tabs().updateBrowser(id, BrowserPaneState(url: Uri.parse('http://localhost/'), title: 'Hi'));
    expect(state().tabs.first.browsers[id]!.title, 'Hi');
  });

  test('a browser pane never gets a resize or a view (D31, D4)', () {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    tabs().toggleZoom();
    tabs().toggleZoom();
    expect(local.views.keys, [1]);
    expect(local.viewRequests.where((id) => id < 0), isEmpty);
  });
}
```

(If `FakeLocalSessions` has no `viewRequests` list, add one in this step: `final List<int> viewRequests = [];` appended to in `view(int id)` — it is the fake's record of every `view` call.)

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_browser_test.dart`
Expected: FAIL — `openBrowser`, `browsers`, `tabOfPane`… undefined.

- [ ] **Step 3: Extend `TerminalTab` and `TerminalTabsState`**

In `apps/desktop/lib/src/terminal/terminal_tabs.dart` add the imports `../browser/browser_controller.dart` and `../browser/browser_url.dart`, then:

```dart
/// A6 D4: browser panes have negative ids from a desktop counter; agent
/// session ids are positive, so the two never collide and A3's
/// `PaneLeaf(int)` holds both.
bool isBrowserPaneId(int id) => id < 0;

/// A6 D28.
const int kMaxBrowserPanes = 8;

/// A6 D31 (UI-A6 §1.2 `browserMinWidth`/`browserMinHeight`): pane header,
/// toolbar and a usable page.
const Size kBrowserMinSize = Size(240, 160);

final class BrowserLimitNotice extends TabNotice {
  const BrowserLimitNotice(this.max);
  final int max;
}

final class BrowserSchemeBlockedNotice extends TabNotice {
  const BrowserSchemeBlockedNotice();
}

final class BrowserDownloadBlockedNotice extends TabNotice {
  const BrowserDownloadBlockedNotice();
}
```

`TerminalTab`: add the field `final Map<int, BrowserPaneState> browsers;` (constructor `this.browsers = const {}`, `copyWith({…, Map<int, BrowserPaneState>? browsers})` → `browsers: browsers ?? this.browsers`, and `TerminalTab.single` leaves it empty). Add:

```dart
  /// A6 D6: the pane the tab's A1/A2 getters describe — the focused pane
  /// when it is a terminal, else the most recently used terminal pane.
  /// A6 D5 guarantees there is always one.
  PaneSession get activeTerminalPane {
    final focusedPane = panes[focusedPaneId];
    if (focusedPane != null) return focusedPane;
    for (final id in paneHistory) {
      final pane = panes[id];
      if (pane != null) return pane;
    }
    return panes[paneOrder.firstWhere(panes.containsKey)]!;
  }
```

and change A3's `focused` getter to `PaneSession get focused => activeTerminalPane;` (every A3 getter that delegated to `focused` now follows D6). `paneCount`/`paneOrder`/`isSplit` already come from `layout`, so they count browser panes.

`TerminalTabsState`:

```dart
  /// The tab holding pane [id] — a session or a browser pane (A6).
  TerminalTab? tabOfPane(int id) {
    for (final tab in tabs) {
      if (tab.panes.containsKey(id) || tab.browsers.containsKey(id)) {
        return tab;
      }
    }
    return null;
  }

  int get browserCount =>
      tabs.fold(0, (n, tab) => n + tab.browsers.length);
```

- [ ] **Step 4: Add the browser operations to `TerminalTabs`**

```dart
  int _nextBrowserId = -1;

  /// A6 D7: splits [target] (default: the focused pane) of [tabId]
  /// (default: the selected tab) with a browser pane at [url] (default:
  /// the active terminal's smallest port, else about:blank). [notify]
  /// false (agent, A7) raises errors without a toast.
  int openBrowser({
    int? tabId,
    int? target,
    Uri? url,
    SplitAxis axis = SplitAxis.row,
    bool focus = true,
    bool notify = true,
  }) {
    final tab = tabId == null ? state.selected : _tab(tabId);
    if (tab == null) throw const BrowserError('not_found');
    final at = target ?? tab.focusedPaneId;
    if (!paneIds(tab.layout).contains(at)) {
      throw const BrowserError('not_found');
    }
    if (state.browserCount >= kMaxBrowserPanes) {
      if (notify) _set(notice: const BrowserLimitNotice(kMaxBrowserPanes));
      throw const BrowserError('browser_limit');
    }
    if (!_roomForBrowser(tab, at, axis)) {
      if (notify) _set(notice: const PaneNoRoomNotice());
      throw const BrowserError('no_room');
    }
    final id = _nextBrowserId--;
    final ports = tab.activeTerminalPane.ports;
    final start =
        url ??
        (ports.isEmpty ? aboutBlank : Uri.parse('http://localhost:${ports.first}/'));
    final wasZoomed = tab.zoomedPaneId != null;
    _replaceTab(
      tab.copyWith(
        layout: splitPane(tab.layout, at, id, axis),
        browsers: {...tab.browsers, id: BrowserPaneState(url: start)},
        focusedPaneId: focus ? id : tab.focusedPaneId,
        paneHistory: focus
            ? [id, ...tab.paneHistory]
            : [...tab.paneHistory, id],
        zoomedPaneId: null, // A3 D3: a split ends the zoom
      ),
    );
    if (focus && state.selectedId != tab.id) _set(selectedId: tab.id);
    if (wasZoomed && state.selectedId == tab.id) _visibleChanged();
    return id;
  }

  /// The registry copies each controller state here (UI and A7 `list`).
  void updateBrowser(int id, BrowserPaneState browser) {
    final tab = state.tabOfPane(id);
    if (tab == null || identical(tab.browsers[id], browser)) return;
    _replaceTab(tab.copyWith(browsers: {...tab.browsers, id: browser}));
  }

  /// A3 D4 for a browser half (A6 D31).
  bool _roomForBrowser(TerminalTab tab, int target, SplitAxis axis) {
    final m = _metrics;
    final unit = paneRects(tab.layout)[target];
    if (m == null || unit == null) return true;
    final width = unit.width * m.area.width;
    final height = unit.height * m.area.height;
    final targetMin = isBrowserPaneId(target) ? kBrowserMinSize : m.minPane;
    return axis == SplitAxis.row
        ? width >= targetMin.width + kBrowserMinSize.width + m.divider
        : height >= targetMin.height + kBrowserMinSize.height + m.divider;
  }
```

Edit the A3 members:
- `_roomToSplit(tab, target, axis)`: the target's own minimum becomes `isBrowserPaneId(target) ? kBrowserMinSize : m.minPane` (the new half stays a terminal minimum).
- `split(SplitAxis axis)`: replace `final pane = tab.panes[target]!;` with `final pane = tab.activeTerminalPane;` (cwd and grid estimate from the active terminal; the real grid arrives at the next layout, A3 D13).
- `focusPane(int sessionId)`: rename the parameter to `id` and use `state.tabOfPane(id)` instead of `state.tabOfSession(...)`.
- `closePane(int sessionId)`: first line `if (isBrowserPaneId(sessionId)) { _removePane(sessionId); return; }`.
- `_removePane(int sessionId)`: use `state.tabOfPane(sessionId)`; replace `if (!tab.isSplit) { _removeTab(tab.id); return; }` with

```dart
    // A6 D5: the last terminal pane takes the tab (and its browser panes)
    // with it — a tab never holds browser panes alone.
    final isBrowser = isBrowserPaneId(sessionId);
    if (!tab.isSplit || (!isBrowser && tab.panes.length == 1)) {
      _removeTab(tab.id);
      return;
    }
    if (!isBrowser) _links.remove(sessionId)?.dispose();
```

  (drop the old unconditional `_links.remove(sessionId)?.dispose();` that followed) and in the final `copyWith` use `panes: isBrowser ? tab.panes : (Map.of(tab.panes)..remove(sessionId))` and `browsers: isBrowser ? (Map.of(tab.browsers)..remove(sessionId)) : tab.browsers`.
- `_exited(...)`: in the branch that removes the pane on exit code 0 (not on `closedOnRequest`), insert before `_removePane(id)`:

```dart
      final tab = state.tabOfSession(id);
      if (tab != null && tab.panes.length == 1 && tab.browsers.isNotEmpty) {
        // A6 D5: keep the shell's pane (exit line, Enter closes) so the
        // browser pane does not vanish because a shell exited.
        _updatePane(id, (p) => p.copyWith(exitCode: 0));
        return;
      }
```

  and write the A1 D14 exit line for this case exactly as the non-zero branch does (same helper, code 0). `PaneSession.exited` is `exitCode != null` (A1) — exit code 0 counts as exited; Enter then reaches `_removePane`, which closes the tab (D5).
- `_visibleChanged()` already skips ids without a `PaneSession` (`tab.panes[id] == null → continue`) — leave it; the "never a resize" test pins it.

- [ ] **Step 5: Run the tab tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/terminal_tabs_browser_test.dart`
Expected: PASS (12 tests). Then the full suite: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` — PASS (A3's pane tests still pass: no browser pane means `browsers` is empty and `activeTerminalPane == focused pane`).

- [ ] **Step 6: Write the failing registry test**

Create `apps/desktop/test/browser/browser_registry_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/browser_registry.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_browser_engine.dart';
import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;
late Map<int, FakeBrowserEngine> engines;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);
BrowserRegistry registry() => container.read(browserRegistryProvider.notifier);

void boot() {
  engines = {};
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      browserEngineFactoryProvider.overrideWithValue(
        (id) => engines[id] = FakeBrowserEngine(),
      ),
    ],
  );
  state();
  container.read(browserRegistryProvider);
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('a browser pane of the selected tab gets an engine and loads its URL', () async {
    local.add(local.summary(1, ports: [3000]));
    boot();
    final id = tabs().openBrowser();
    await pumpEventQueue();
    expect(engines[id]!.loads.single.toString(), 'http://localhost:3000/');
    engines[id]!.emit(const TitleChanged('Vite'));
    expect(state().tabs.single.browsers[id]!.title, 'Vite');
    expect(container.read(browserRegistryProvider), {id});
  });

  test('about:blank loads nothing; panes of hidden tabs load lazily (D29)', () async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    final blank = tabs().openBrowser(tabId: 1);
    final hidden = tabs().openBrowser(
      tabId: 2, url: Uri.parse('http://localhost:8000/'), focus: false,
    );
    await pumpEventQueue();
    expect(engines[blank]!.loads, isEmpty);
    expect(engines.containsKey(hidden), isFalse);
    expect(registry().controller(hidden), isA<BrowserController>()); // on demand (A7)
    await pumpEventQueue();
    expect(engines[hidden]!.loads.single.toString(), 'http://localhost:8000/');
  });

  test('closing the pane disposes its controller and engine (D34)', () async {
    local.add(local.summary(1));
    boot();
    final id = tabs().openBrowser();
    await pumpEventQueue();
    tabs().closePane(id);
    await pumpEventQueue();
    expect(engines[id]!.disposed, isTrue);
    expect(registry().controller(id), isNull);
  });

  test('notices, shortcuts and clicks are re-published with the pane id', () async {
    local.add(local.summary(1));
    boot();
    final id = tabs().openBrowser();
    await pumpEventQueue();
    final notices = <BrowserNotice>[];
    final shortcuts = <BrowserShortcut>[];
    final clicks = <int>[];
    registry().notices.listen(notices.add);
    registry().shortcuts.listen(shortcuts.add);
    registry().contentClicks.listen(clicks.add);
    engines[id]!
      ..emit(const DownloadBlocked())
      ..emit(const ShortcutForwarded('meta+l'))
      ..emit(const ContentClicked());
    await pumpEventQueue();
    expect(notices, [BrowserNotice.downloadBlocked]);
    expect(shortcuts.single.paneId, id);
    expect(shortcuts.single.chord, 'meta+l');
    expect(clicks, [id]);
  });
}
```

- [ ] **Step 7: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_registry_test.dart`
Expected: FAIL — `browser_registry.dart` does not exist.

- [ ] **Step 8: Implement the registry**

Create `apps/desktop/lib/src/browser/browser_registry.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/terminal_tabs.dart';
import 'browser_controller.dart';
import 'browser_engine.dart';
import 'browser_url.dart';

/// Builds the platform engine for one pane (Tasks 7, 8); overridden in
/// `main.dart` and in tests.
typedef BrowserEngineFactory = BrowserEngine Function(int paneId);

final browserEngineFactoryProvider = Provider<BrowserEngineFactory>(
  (ref) => throw StateError('browserEngineFactoryProvider must be overridden'),
);

/// D20: read at every agent call. Task 6 makes it read the setting.
final browserAllowAnyOriginProvider = Provider<bool Function()>(
  (ref) => () => false,
);

final class BrowserShortcut {
  const BrowserShortcut(this.paneId, this.chord);
  final int paneId;
  final String chord;
}

/// The live [BrowserController]s by pane id (state = their ids). A pane
/// gets its engine when its tab is first selected or when something asks
/// for it ([controller], A7) — so a restored workspace does not start
/// eight pages at once (D29). Removed panes are disposed (D34).
final class BrowserRegistry extends Notifier<Set<int>> {
  final Map<int, BrowserController> _controllers = {};
  final StreamController<BrowserNotice> _notices =
      StreamController.broadcast();
  final StreamController<BrowserShortcut> _shortcuts =
      StreamController.broadcast();
  final StreamController<int> _clicks = StreamController.broadcast();

  Stream<BrowserNotice> get notices => _notices.stream;
  Stream<BrowserShortcut> get shortcuts => _shortcuts.stream;
  Stream<int> get contentClicks => _clicks.stream;

  @override
  Set<int> build() {
    ref.listen(terminalTabsProvider, (_, next) => _sync(next));
    ref.onDispose(() {
      for (final c in _controllers.values) {
        unawaited(c.dispose());
      }
      _controllers.clear();
      _notices.close();
      _shortcuts.close();
      _clicks.close();
    });
    // Not during build: creating a controller writes to terminalTabs.
    scheduleMicrotask(() {
      if (ref.mounted) _sync(ref.read(terminalTabsProvider));
    });
    return const {};
  }

  /// The controller if it exists; never creates one (pane views of hidden
  /// tabs are built inside A3's IndexedStack and must not start engines).
  BrowserController? existing(int paneId) => _controllers[paneId];

  /// The pane's controller, creating it (and loading its page) when the
  /// pane exists but was never shown; `null` for an unknown pane.
  BrowserController? controller(int paneId) {
    final existing = _controllers[paneId];
    if (existing != null) return existing;
    final initial = ref.read(terminalTabsProvider).tabOfPane(paneId)?.browsers[paneId];
    if (initial == null) return null;
    final controller = BrowserController(
      paneId: paneId,
      engine: ref.read(browserEngineFactoryProvider)(paneId),
      initialUrl: initial.url,
      allowAnyOrigin: ref.read(browserAllowAnyOriginProvider),
      onState: (s) =>
          ref.read(terminalTabsProvider.notifier).updateBrowser(paneId, s),
      onNotice: _notices.add,
      onShortcut: (chord) => _shortcuts.add(BrowserShortcut(paneId, chord)),
      onContentClicked: () => _clicks.add(paneId),
    );
    _controllers[paneId] = controller;
    if (initial.url != aboutBlank) {
      scheduleMicrotask(() {
        if (_controllers[paneId] == controller) {
          unawaited(controller.navigate(initial.url));
        }
      });
    }
    scheduleMicrotask(() {
      if (ref.mounted) state = _controllers.keys.toSet();
    });
    return controller;
  }

  void _sync(TerminalTabsState tabs) {
    final live = {for (final t in tabs.tabs) ...t.browsers.keys};
    var changed = false;
    for (final id in _controllers.keys.toList()) {
      if (!live.contains(id)) {
        unawaited(_controllers.remove(id)!.dispose());
        changed = true;
      }
    }
    for (final id in tabs.selected?.browsers.keys ?? const <int>[]) {
      if (!_controllers.containsKey(id)) {
        controller(id);
        changed = true;
      }
    }
    if (changed) state = _controllers.keys.toSet();
  }
}
```

- [ ] **Step 9: Run the tests, format, analyze, commit**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/ test/terminal/terminal_tabs_browser_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS.

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/browser/browser_registry.dart apps/desktop/test/terminal/terminal_tabs_browser_test.dart apps/desktop/test/browser/browser_registry_test.dart apps/desktop/test/support/fake_local_sessions.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/browser/browser_registry.dart apps/desktop/test/terminal/terminal_tabs_browser_test.dart apps/desktop/test/browser/browser_registry_test.dart apps/desktop/test/support/fake_local_sessions.dart
git commit -m "feat(desktop): browser panes as negative-id leaves of the pane tree, D5 invariant, browser registry (A6 D4-D7, D28, D31, D34)"
```

---

### Task 6: Settings, private profile, screenshot folder, tray submenu, strings, sizes and chords (D15, D24, D26, D27)

**Files:**
- Modify: `apps/desktop/lib/src/platform/settings_store.dart`
- Create: `apps/desktop/lib/src/browser/browser_profile.dart`, `apps/desktop/lib/src/browser/shots_dir.dart`, `apps/desktop/lib/src/browser/browser_chords.dart`
- Modify: `apps/desktop/lib/src/browser/browser_registry.dart` (`browserAllowAnyOriginProvider` reads the setting)
- Modify: `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_presenter.dart`, `tray_actions.dart`
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated)
- Modify: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart`, `shortcut_labels.dart`
- Test: `apps/desktop/test/browser/browser_profile_test.dart`, `shots_dir_test.dart`, `browser_chords_test.dart`, `apps/desktop/test/tray/tray_browser_menu_test.dart`

**Interfaces:**
- Consumes: Task 5 `browserAllowAnyOriginProvider`; A5a `TrayLocalState`, `buildTrayMenu(..., {TrayLocalState local})`, `TrayKeys.terminal`, `trayLocalStateProvider` (if A5a is not merged: add `TrayLocalState` here with only the two browser fields and place the submenu right before `TrayKeys.notifications`); A1 `settingsStoreProvider`, `SettingsStore`, `desktopShortcuts`, `terminalViewShortcuts`.
- Produces:
  - `SettingKeys.browserKeepData = 'browser_keep_data'`, `SettingKeys.browserAgentAllOrigins = 'browser_agent_all_origins'` (both in `SettingKeys.all`; UI-owned in A5b's `UiSettingKeys` if that set exists).
  - `WebsiteDataClearer`, `BrowserProfile({required bool isWindows, required bool Function() keepData, String? localAppData, WebsiteDataClearer? clearer, Random? random})` with `prepare()`, `onQuit()`, `clearNow() → Future<bool>`, `userDataPath`.
  - `ShotsDir(String path, {required bool isWindows, …})` with `write(Uint8List) → Future<String>`, `sweep({bool all})`; `const kShotLifetime = Duration(minutes: 10)`.
  - `browser_chords.dart`: `chordString(...)`, `chordKeyName(LogicalKeyboardKey)`, `chordOf(ShortcutActivator)`, `chordsOf(maps, keep:)`, `intentForChord(chord, maps)`.
  - `terminal_shortcuts.dart`: intents `OpenBrowserPaneIntent`, `BrowserFocusAddressIntent`, `BrowserReloadIntent`, `BrowserBackIntent`, `BrowserForwardIntent`, `BrowserStopIntent`; `Map<ShortcutActivator, Intent> browserPaneShortcuts(TargetPlatform)`; ⌘⇧B / Ctrl+Shift+Alt+B in the window map; `List<String> browserForwardedChords(TargetPlatform platform, {required bool loading})`; `Intent? intentForForwardedChord(String chord, TargetPlatform platform)`.
  - Tray: `TrayKeys.browser = 'browser'`, `TrayKeys.browserKeepData = 'browser_keep_data'`, `TrayKeys.browserAgentAllOrigins = 'browser_agent_all_origins'`, `TrayKeys.browserClearData = 'browser_clear_data'`; `TrayLocalState` gains `browserKeepData` and `browserAgentAllOrigins` (default `false`); actions `ToggleBrowserKeepData`, `RequestBrowserAgentAllOrigins` (opens the UI-A6 §5 confirm when turning on; turning off is immediate), `ClearBrowserData`.
  - ARB keys: every key in UI-A6 §7.
  - `ShellxSizes`: every size in UI-A6 §1.2 (`browserMinWidth = 240`, `browserMinHeight = 160` must equal `kBrowserMinSize`).

- [ ] **Step 1: Write the failing profile, shots and chord tests**

Create `apps/desktop/test/browser/browser_profile_test.dart`:

```dart
import 'dart:io';
import 'dart:math';

import 'package:shellx_desktop/src/browser/browser_profile.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeClearer implements WebsiteDataClearer {
  int clears = 0;
  @override
  Future<void> clearWebsiteData() async => clears++;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('a6profile'));
  tearDown(() => tmp.delete(recursive: true));

  String root() => '${tmp.path}/ShellX/webview';

  group('Windows', () {
    test(
      'a fresh per-run folder; earlier runs removed; kept profile untouched',
      () async {
        await Directory('${root()}/s-old1').create(recursive: true);
        await Directory('${root()}/profile').create(recursive: true);
        final p = BrowserProfile(
          isWindows: true,
          keepData: () => false,
          localAppData: tmp.path,
          random: Random(1),
        );
        await p.prepare();
        expect(p.userDataPath, startsWith('${root()}/s-'));
        expect(p.userDataPath!.split('/').last, hasLength(18)); // s- + 16 hex
        expect(Directory('${root()}/s-old1').existsSync(), isFalse);
        expect(Directory('${root()}/profile').existsSync(), isTrue);
        expect(Directory(p.userDataPath!).existsSync(), isTrue);
      },
    );

    test('keep data → the profile folder', () async {
      final p = BrowserProfile(
        isWindows: true,
        keepData: () => true,
        localAppData: tmp.path,
      );
      await p.prepare();
      expect(p.userDataPath, '${root()}/profile');
    });

    test('clearing the kept profile in use waits for the next start', () async {
      final p = BrowserProfile(
        isWindows: true,
        keepData: () => true,
        localAppData: tmp.path,
      );
      await p.prepare();
      await File('${root()}/profile/Cookies').writeAsString('x');
      expect(await p.clearNow(), isFalse);
      final next = BrowserProfile(
        isWindows: true,
        keepData: () => true,
        localAppData: tmp.path,
      );
      await next.prepare();
      expect(File('${root()}/profile/Cookies').existsSync(), isFalse);
      expect(File('${root()}/clear-profile').existsSync(), isFalse);
    });
  });

  group('macOS', () {
    test('clears at start and quit unless kept', () async {
      final c = FakeClearer();
      var keep = false;
      final p = BrowserProfile(
        isWindows: false,
        keepData: () => keep,
        clearer: c,
      );
      await p.prepare();
      await p.onQuit();
      expect(c.clears, 2);
      keep = true;
      await p.prepare();
      await p.onQuit();
      expect(c.clears, 2);
      expect(await p.clearNow(), isTrue);
      expect(c.clears, 3);
    });
  });
}
```

Create `apps/desktop/test/browser/shots_dir_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_desktop/src/browser/shots_dir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('a6shots'));
  tearDown(() => tmp.delete(recursive: true));

  test('writes a 0600 file in a 0700 folder; sweeps expired shots', () async {
    var now = DateTime.now();
    final shots = ShotsDir(
      '${tmp.path}/browser/shots',
      isWindows: false,
      clock: () => now,
    );
    final path = await shots.write(Uint8List.fromList([1, 2, 3]));
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    expect(RegExp(r'/[0-9a-f]{32}\.png$').hasMatch(path), isTrue);
    if (!Platform.isWindows) {
      expect(File(path).statSync().modeString(), 'rw-------');
      expect(
        Directory('${tmp.path}/browser/shots').statSync().modeString(),
        'rwx------',
      );
    }
    now = now.add(const Duration(minutes: 11));
    final second = await shots.write(Uint8List.fromList([4]));
    expect(File(path).existsSync(), isFalse);
    expect(File(second).existsSync(), isTrue);
    await shots.sweep(all: true);
    expect(File(second).existsSync(), isFalse);
  });
}
```

Create `apps/desktop/test/browser/browser_chords_test.dart`:

```dart
import 'package:shellx_desktop/src/browser/browser_chords.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class A extends Intent { const A(); }
class B extends Intent { const B(); }
class Copy extends Intent { const Copy(); }

void main() {
  test('chord strings use a fixed modifier order', () {
    expect(chordString(shift: true, meta: true, key: 'b'), 'meta+shift+b');
    expect(chordString(alt: true, ctrl: true, shift: true, key: 'b'), 'alt+ctrl+shift+b');
    expect(chordOf(const SingleActivator(LogicalKeyboardKey.keyL, meta: true)), 'meta+l');
    expect(chordOf(const SingleActivator(LogicalKeyboardKey.f6, control: true)), 'ctrl+f6');
    expect(chordOf(const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true, alt: true)), 'alt+meta+left');
    expect(chordOf(const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)), 'meta+[');
    expect(chordOf(const SingleActivator(LogicalKeyboardKey.digit3, control: true, alt: true)), 'alt+ctrl+3');
    expect(chordOf(const SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true)), isNull);
    expect(chordOf(const CharacterActivator('a')), isNull);
  });

  test('chordsOf filters intents; intentForChord maps back', () {
    final maps = [
      {
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true): const A(),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): const Copy(),
      },
      {const SingleActivator(LogicalKeyboardKey.escape): const B()},
    ];
    expect(chordsOf(maps, keep: (i) => i is! Copy), ['escape', 'meta+shift+b']);
    expect(intentForChord('meta+shift+b', maps), isA<A>());
    expect(intentForChord('meta+c', maps), isA<Copy>());
    expect(intentForChord('meta+z', maps), isNull);
  });
}
```

Create `apps/desktop/test/ui/browser_shortcuts_test.dart` (pins Review Focus 4 against the real maps):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

void main() {
  const mac = TargetPlatform.macOS;
  const win = TargetPlatform.windows;

  test('⌘⇧B / Ctrl+Shift+Alt+B open a browser pane', () {
    expect(
      desktopShortcuts(mac)[const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true)],
      isA<OpenBrowserPaneIntent>(),
    );
    expect(
      desktopShortcuts(win)[const SingleActivator(LogicalKeyboardKey.keyB, control: true, shift: true, alt: true)],
      isA<OpenBrowserPaneIntent>(),
    );
  });

  test('browser pane keys (UI-A6 §4.1)', () {
    final m = browserPaneShortcuts(mac);
    expect(m[const SingleActivator(LogicalKeyboardKey.keyL, meta: true)], isA<BrowserFocusAddressIntent>());
    expect(m[const SingleActivator(LogicalKeyboardKey.keyR, meta: true)], isA<BrowserReloadIntent>());
    expect(m[const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)], isA<BrowserBackIntent>());
    expect(m[const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true)], isA<BrowserForwardIntent>());
    expect(m[const SingleActivator(LogicalKeyboardKey.escape)], isA<BrowserStopIntent>());
    final w = browserPaneShortcuts(win);
    expect(w[const SingleActivator(LogicalKeyboardKey.keyL, control: true)], isA<BrowserFocusAddressIntent>());
    expect(w[const SingleActivator(LogicalKeyboardKey.f5)], isA<BrowserReloadIntent>());
    expect(w[const SingleActivator(LogicalKeyboardKey.keyR, control: true)], isA<BrowserReloadIntent>());
    expect(w[const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)], isA<BrowserBackIntent>());
    expect(w[const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true)], isA<BrowserForwardIntent>());
  });

  test('forwarded chords: ShellX keys yes, page editing keys no, Esc only while loading (D15)', () {
    final idle = browserForwardedChords(mac, loading: false);
    expect(idle, containsAll(['meta+l', 'meta+r', 'meta+[', 'meta+]', 'meta+shift+b', 'meta+w', 'meta+t', 'meta+1', 'ctrl+f6', 'ctrl+shift+f6', 'alt+meta+left']));
    expect(idle, isNot(contains('meta+c')));
    expect(idle, isNot(contains('meta+v')));
    expect(idle, isNot(contains('meta+a')));
    expect(idle, isNot(contains('meta+=')));
    expect(idle, isNot(contains('escape')));
    expect(browserForwardedChords(mac, loading: true), contains('escape'));
    expect(browserForwardedChords(win, loading: false), containsAll(['ctrl+l', 'f5', 'alt+left', 'alt+ctrl+shift+b', 'ctrl+f6']));
  });

  test('a forwarded chord maps back to its intent', () {
    expect(intentForForwardedChord('meta+l', mac), isA<BrowserFocusAddressIntent>());
    expect(intentForForwardedChord('meta+shift+b', mac), isA<OpenBrowserPaneIntent>());
    expect(intentForForwardedChord('ctrl+f6', mac), isNotNull);
    expect(intentForForwardedChord('meta+c', mac), isNull); // stays in the page
    expect(intentForForwardedChord('meta+z', mac), isNull);
  });
}
```

Create `apps/desktop/test/tray/tray_browser_menu_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

final vi = lookupAppLocalizations(const Locale('vi'));

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final sub = i.submenu?.items;
    if (sub != null) {
      final hit = find(sub, key);
      if (hit != null) return hit;
    }
  }
  return null;
}

void main() {
  for (final signedIn in [false, true]) {
    test('Trình duyệt submenu right after Terminal (signedIn: $signedIn)', () {
      final state = signedIn
          ? const AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c')
          : const AgentViewState(phase: AuthPhase.signedOut);
      final items = buildTrayMenu(
        state,
        vi,
        TrayMenuIds(),
        local: const TrayLocalState(browserKeepData: true),
      ).items!;
      final terminal = items.indexWhere((i) => i.key == TrayKeys.terminal);
      final browser = items.indexWhere((i) => i.key == TrayKeys.browser);
      expect(browser, terminal + 1);
      expect(items[browser].label, 'Trình duyệt');
      final keep = find(items, TrayKeys.browserKeepData)!;
      expect(keep.label, 'Giữ dữ liệu trình duyệt (cookie, đăng nhập)');
      expect(keep.checked, isTrue);
      final all = find(items, TrayKeys.browserAgentAllOrigins)!;
      expect(all.label, 'Cho phép agent điều khiển mọi trang');
      expect(all.checked, isFalse);
      expect(find(items, TrayKeys.browserClearData)!.label, 'Xóa dữ liệu trình duyệt');
    });
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_profile_test.dart test/browser/shots_dir_test.dart test/browser/browser_chords_test.dart test/ui/browser_shortcuts_test.dart test/tray/tray_browser_menu_test.dart`
Expected: FAIL — missing files and symbols.

- [ ] **Step 3: Settings keys, profile, screenshot folder**

In `apps/desktop/lib/src/platform/settings_store.dart` add to `SettingKeys` (and to `SettingKeys.all`; if A5b's `UiSettingKeys` exists, add them there — the UI process owns them):

```dart
  /// A6 D26/D27: keep the browser panes' cookies and site data between
  /// runs (default off: a fresh private profile every run).
  static const String browserKeepData = 'browser_keep_data';

  /// A6 D20/D27: agents may read any page, not only local ones.
  static const String browserAgentAllOrigins = 'browser_agent_all_origins';
```

Create `apps/desktop/lib/src/browser/browser_profile.dart`:

```dart
/// A6 D26: the browser panes' private profile — never the user's system
/// browser profile, cleared every run unless "Giữ dữ liệu" is on.
library;

import 'dart:io';
import 'dart:math';

/// macOS side of D26 (Task 7 implements it over the BrowserNative channel).
abstract interface class WebsiteDataClearer {
  Future<void> clearWebsiteData();
}

final class BrowserProfile {
  BrowserProfile({
    required this.isWindows,
    required bool Function() keepData,
    String? localAppData,
    WebsiteDataClearer? clearer,
    Random? random,
  }) : _keepData = keepData,
       _localAppData = localAppData,
       _clearer = clearer,
       _random = random ?? Random.secure();

  final bool isWindows;
  final bool Function() _keepData;
  final String? _localAppData;
  final WebsiteDataClearer? _clearer;
  final Random _random;

  String? _userDataPath;

  /// Windows: the WebView2 user data folder chosen by [prepare].
  String? get userDataPath => _userDataPath;

  Directory get _root => Directory(
    '${_localAppData ?? r'C:\Users\Default\AppData\Local'}'
    '${Platform.pathSeparator}ShellX${Platform.pathSeparator}webview',
  );

  /// Before the first web view of this run. Windows: removes every
  /// per-run folder of earlier runs (WebView2 locked them while running)
  /// and picks this run's folder. macOS: clears the app's website data
  /// unless kept — also covers a crash last time.
  Future<void> prepare() async {
    if (!isWindows) {
      if (!_keepData()) await _clearer?.clearWebsiteData();
      return;
    }
    final root = _root;
    await root.create(recursive: true);
    await for (final entry in root.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory && name.startsWith('s-')) {
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          // Still locked by a WebView2 process that outlived its app: next run.
        }
      }
    }
    final marker = File('${root.path}${Platform.pathSeparator}clear-profile');
    if (await marker.exists()) {
      final kept = Directory('${root.path}${Platform.pathSeparator}profile');
      try {
        if (await kept.exists()) await kept.delete(recursive: true);
        await marker.delete();
      } on FileSystemException {
        // Still locked: try again next run.
      }
    }
    final name = _keepData() ? 'profile' : 's-${_hex(8)}';
    final dir = Directory('${root.path}${Platform.pathSeparator}$name');
    await dir.create(recursive: true);
    _userDataPath = dir.path;
  }

  /// On quit. macOS clears now; Windows cannot (folder locked) — the next
  /// [prepare] removes it.
  Future<void> onQuit() async {
    if (!isWindows && !_keepData()) await _clearer?.clearWebsiteData();
  }

  /// Tray "Xóa dữ liệu trình duyệt". macOS: everything now. Windows: the
  /// kept profile folder is removed at the next start (it is in use now);
  /// returns false when the change waits for a restart.
  Future<bool> clearNow() async {
    if (!isWindows) {
      await _clearer?.clearWebsiteData();
      return true;
    }
    final kept = Directory('${_root.path}${Platform.pathSeparator}profile');
    if (_userDataPath == kept.path) {
      await File(
        '${_root.path}${Platform.pathSeparator}clear-profile',
      ).create(recursive: true);
      return false;
    }
    if (await kept.exists()) await kept.delete(recursive: true);
    return true;
  }

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
```

and append to it the providers `main.dart` overrides (Task 9):

```dart
/// Overridden in `main.dart` (Task 9).
final browserProfileProvider = Provider<BrowserProfile>(
  (ref) => throw StateError('browserProfileProvider must be overridden'),
);
```

(add `import 'package:flutter_riverpod/flutter_riverpod.dart';` at the top).

Create `apps/desktop/lib/src/browser/shots_dir.dart`:

```dart
/// A6 D24: screenshots handed to A7 as files (the IPC frame is 64 KiB),
/// private to the user and short-lived.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const Duration kShotLifetime = Duration(minutes: 10);

final class ShotsDir {
  ShotsDir(
    this.path, {
    required this.isWindows,
    DateTime Function()? clock,
    Random? random,
    Future<ProcessResult> Function(String, List<String>)? run,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       _run = run ?? Process.run;

  /// `<app support>/browser/shots` (macOS), `%LOCALAPPDATA%\ShellX\browser\shots`.
  final String path;
  final bool isWindows;
  final DateTime Function() _clock;
  final Random _random;
  final Future<ProcessResult> Function(String, List<String>) _run;

  /// Writes [png] as `<32 hex>.png` (0600 in a 0700 folder on macOS; the
  /// per-user `%LOCALAPPDATA%` ACL on Windows) after removing expired shots.
  Future<String> write(Uint8List png) async {
    final dir = Directory(path);
    await dir.create(recursive: true);
    if (!isWindows) await _run('/bin/chmod', ['700', dir.path]);
    await sweep();
    final name = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File('${dir.path}${Platform.pathSeparator}$name.png');
    // Permissions before content, like EndpointFile.
    await file.create(exclusive: true);
    if (!isWindows) await _run('/bin/chmod', ['600', file.path]);
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }

  /// Deletes shots older than [kShotLifetime]; [all] on start and quit.
  Future<void> sweep({bool all = false}) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;
    final now = _clock();
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.png')) continue;
      try {
        final age = now.difference(await entry.lastModified());
        if (all || age >= kShotLifetime) await entry.delete();
      } on FileSystemException {
        // Gone already or in use: the next sweep.
      }
    }
  }
}
```

and append:

```dart
/// Overridden in `main.dart` (Task 9): `<app support>/browser/shots` on
/// macOS, `%LOCALAPPDATA%\ShellX\browser\shots` on Windows.
final shotsDirProvider = Provider<ShotsDir>(
  (ref) => throw StateError('shotsDirProvider must be overridden'),
);
```

(with the same Riverpod import).

In `browser_registry.dart` replace the body of `browserAllowAnyOriginProvider`:

```dart
final browserAllowAnyOriginProvider = Provider<bool Function()>((ref) {
  final settings = ref.watch(settingsStoreProvider);
  return () => settings.getBool(
    SettingKeys.browserAgentAllOrigins,
    defaultValue: false,
  );
});
```

(imports: `../platform/settings_store.dart`, `../terminal/sidebar_workspaces.dart` for `settingsStoreProvider`).

- [ ] **Step 4: Chords and shortcuts**

Create `apps/desktop/lib/src/browser/browser_chords.dart`:

```dart
/// A6 D15: ShellX chords handed back from the web content to Flutter. The
/// same string format is produced by BrowserNative.swift (macOS) and the
/// vendored webview_windows accelerator patch: modifiers in the fixed
/// order alt, ctrl, meta, shift, then the key name, joined by '+'.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

String chordString({
  bool alt = false,
  bool ctrl = false,
  bool meta = false,
  bool shift = false,
  required String key,
}) => [
  if (alt) 'alt',
  if (ctrl) 'ctrl',
  if (meta) 'meta',
  if (shift) 'shift',
  key,
].join('+');

final Map<LogicalKeyboardKey, String> _named = {
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.f5: 'f5',
  LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.minus: '-',
};

/// The key name of [key]: a–z, 0–9, or a [_named] entry; `null` otherwise.
String? chordKeyName(LogicalKeyboardKey key) {
  final named = _named[key];
  if (named != null) return named;
  final label = key.keyLabel;
  if (label.length == 1 && RegExp(r'^[A-Za-z0-9]$').hasMatch(label)) {
    return label.toLowerCase();
  }
  return null;
}

String? chordOf(ShortcutActivator activator) {
  if (activator is! SingleActivator) return null;
  final key = chordKeyName(activator.trigger);
  if (key == null) return null;
  return chordString(
    alt: activator.alt,
    ctrl: activator.control,
    meta: activator.meta,
    shift: activator.shift,
    key: key,
  );
}

/// Chord strings of every activator in [maps] whose intent passes [keep].
List<String> chordsOf(
  Iterable<Map<ShortcutActivator, Intent>> maps, {
  required bool Function(Intent intent) keep,
}) {
  final out = <String>{};
  for (final map in maps) {
    map.forEach((activator, intent) {
      final chord = chordOf(activator);
      if (chord != null && keep(intent)) out.add(chord);
    });
  }
  return out.toList()..sort();
}

/// The intent [chord] stands for in [maps] (first match), or `null`.
Intent? intentForChord(
  String chord,
  Iterable<Map<ShortcutActivator, Intent>> maps,
) {
  for (final map in maps) {
    for (final entry in map.entries) {
      if (chordOf(entry.key) == chord) return entry.value;
    }
  }
  return null;
}
```

In `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart` add the intents next to the A3 pane intents:

```dart
/// A6 W1: ⌘⇧B / Ctrl+Shift+Alt+B — split a browser pane to the right.
class OpenBrowserPaneIntent extends Intent {
  const OpenBrowserPaneIntent();
}

/// A6 D15 (only while a browser pane is focused).
class BrowserFocusAddressIntent extends Intent {
  const BrowserFocusAddressIntent();
}

class BrowserReloadIntent extends Intent {
  const BrowserReloadIntent();
}

class BrowserBackIntent extends Intent {
  const BrowserBackIntent();
}

class BrowserForwardIntent extends Intent {
  const BrowserForwardIntent();
}

/// Esc: enabled only while the page is loading, so a disabled action lets
/// Esc reach the page (D15).
class BrowserStopIntent extends Intent {
  const BrowserStopIntent();
}
```

In `_windowShortcuts(platform)` add (not repeating, like A3's split):

```dart
    mac
            ? const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true)
            : const SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
                shift: true,
                alt: true,
              ):
        const OpenBrowserPaneIntent(),
```

(The Windows left-Alt guard of A3 D20 applies: register it in the same AltGr-filtered group A3 uses for Ctrl+Shift+Alt chords.) Then add at the end of the file:

```dart
/// A6 UI-A6 §4.1: keys of a focused browser pane (toolbar or page).
Map<ShortcutActivator, Intent> browserPaneShortcuts(TargetPlatform platform) =>
    platform == TargetPlatform.macOS
    ? const {
        SingleActivator(LogicalKeyboardKey.keyL, meta: true):
            BrowserFocusAddressIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: true):
            BrowserReloadIntent(),
        SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            BrowserBackIntent(),
        SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            BrowserForwardIntent(),
        SingleActivator(LogicalKeyboardKey.escape): BrowserStopIntent(),
      }
    : const {
        SingleActivator(LogicalKeyboardKey.keyL, control: true):
            BrowserFocusAddressIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, control: true):
            BrowserReloadIntent(),
        SingleActivator(LogicalKeyboardKey.f5): BrowserReloadIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            BrowserBackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            BrowserForwardIntent(),
        SingleActivator(LogicalKeyboardKey.escape): BrowserStopIntent(),
      };

/// D15: these stay with the page (copy, paste, select all, page zoom).
bool _pageKeeps(Intent intent) =>
    intent is CopySelectionIntent ||
    intent is PasteClipboardIntent ||
    intent is SelectAllIntent ||
    intent is FontBiggerIntent ||
    intent is FontSmallerIntent ||
    intent is FontResetIntent;

List<Map<ShortcutActivator, Intent>> _forwardMaps(TargetPlatform platform) => [
  browserPaneShortcuts(platform),
  desktopShortcuts(platform),
  terminalViewShortcuts(platform),
];

/// D15: the chords native code hands back to Flutter while the web content
/// has the keyboard. Unmodified keys stay with the page except F5 and —
/// while loading — Esc.
List<String> browserForwardedChords(
  TargetPlatform platform, {
  required bool loading,
}) => chordsOf(
  _forwardMaps(platform),
  keep: (intent) =>
      !_pageKeeps(intent) && (loading || intent is! BrowserStopIntent),
).where((c) => c.contains('+') || c == 'f5' || c == 'escape').toList();

/// The intent a forwarded [chord] stands for (`null`: not ShellX's).
Intent? intentForForwardedChord(String chord, TargetPlatform platform) {
  final intent = intentForChord(chord, _forwardMaps(platform));
  return intent == null || _pageKeeps(intent) ? null : intent;
}
```

(import `../../browser/browser_chords.dart`). In `shortcut_labels.dart` add labels for `OpenBrowserPaneIntent` (⌘⇧B / Ctrl+Shift+Alt+B), `BrowserFocusAddressIntent`, `BrowserReloadIntent`, `BrowserBackIntent`, `BrowserForwardIntent` following the existing pattern (platform glyphs, not translated).

- [ ] **Step 5: Strings and sizes**

Add to `apps/desktop/lib/l10n/app_en.arb` (UI-A6 §7, en column):

```json
  "browserOpenPane": "Open browser pane",
  "@browserOpenPane": {"description": "UI-A6 §7 browserOpenPane"},
  "browserOpenPortInPane": "Open :{port} in a browser pane",
  "@browserOpenPortInPane": {"description": "UI-A6 §7 browserOpenPortInPane", "placeholders": {"port": {"type": "int"}}},
  "browserOpenPortInPaneMenu": "Open port in a browser pane…",
  "@browserOpenPortInPaneMenu": {"description": "UI-A6 §7 browserOpenPortInPaneMenu"},
  "browserPortAltClickHint": "{modifier}-click: open in a browser pane",
  "@browserPortAltClickHint": {"description": "UI-A6 §7 browserPortAltClickHint", "placeholders": {"modifier": {"type": "String"}}},
  "browserBack": "Back  {shortcut}",
  "@browserBack": {"description": "UI-A6 §7 browserBack", "placeholders": {"shortcut": {"type": "String"}}},
  "browserForward": "Forward  {shortcut}",
  "@browserForward": {"description": "UI-A6 §7 browserForward", "placeholders": {"shortcut": {"type": "String"}}},
  "browserReload": "Reload  {shortcut}",
  "@browserReload": {"description": "UI-A6 §7 browserReload", "placeholders": {"shortcut": {"type": "String"}}},
  "browserStop": "Stop  Esc",
  "@browserStop": {"description": "UI-A6 §7 browserStop"},
  "browserOpenExternal": "Open in system browser",
  "@browserOpenExternal": {"description": "UI-A6 §7 browserOpenExternal"},
  "browserCopyAddress": "Copy page address",
  "@browserCopyAddress": {"description": "UI-A6 §7 browserCopyAddress"},
  "browserAddressLabel": "Page address",
  "@browserAddressLabel": {"description": "UI-A6 §7 browserAddressLabel"},
  "browserAddressHint": "Enter an address or port",
  "@browserAddressHint": {"description": "UI-A6 §7 browserAddressHint"},
  "browserAddressInvalid": "Not a web address",
  "@browserAddressInvalid": {"description": "UI-A6 §7 browserAddressInvalid"},
  "browserOriginLocal": "Page on this computer",
  "@browserOriginLocal": {"description": "UI-A6 §7 browserOriginLocal"},
  "browserOriginSecure": "Secure connection",
  "@browserOriginSecure": {"description": "UI-A6 §7 browserOriginSecure"},
  "browserOriginInsecure": "Not secure",
  "@browserOriginInsecure": {"description": "UI-A6 §7 browserOriginInsecure"},
  "browserUntitled": "Browser",
  "@browserUntitled": {"description": "UI-A6 §7 browserUntitled"},
  "browserLoadingLabel": "Loading",
  "@browserLoadingLabel": {"description": "UI-A6 §7 browserLoadingLabel"},
  "browserAgentMark": "Agent",
  "@browserAgentMark": {"description": "UI-A6 §7 browserAgentMark"},
  "browserAgentMarkTooltip": "An agent on this computer is controlling this page",
  "@browserAgentMarkTooltip": {"description": "UI-A6 §7 browserAgentMarkTooltip"},
  "browserAnnounceAgent": "An agent is controlling the browser pane",
  "@browserAnnounceAgent": {"description": "UI-A6 §7 browserAnnounceAgent"},
  "browserAnnounceLoaded": "Loaded {title}",
  "@browserAnnounceLoaded": {"description": "UI-A6 §7 browserAnnounceLoaded", "placeholders": {"title": {"type": "String"}}},
  "browserPaneRegionLabel": "Pane {index} of {count} — Browser: {title}",
  "@browserPaneRegionLabel": {"description": "UI-A6 §7 browserPaneRegionLabel", "placeholders": {"index": {"type": "int"}, "count": {"type": "int"}, "title": {"type": "String"}}},
  "browserToolbarRegionLabel": "Browser toolbar",
  "@browserToolbarRegionLabel": {"description": "UI-A6 §7 browserToolbarRegionLabel"},
  "browserSchemeBlocked": "The browser pane only opens http and https pages",
  "@browserSchemeBlocked": {"description": "UI-A6 §7 browserSchemeBlocked"},
  "browserDownloadBlocked": "The browser pane doesn’t download files — use “Open in system browser”",
  "@browserDownloadBlocked": {"description": "UI-A6 §7 browserDownloadBlocked"},
  "browserLimitReached": "You’ve reached the maximum of {count} browser panes",
  "@browserLimitReached": {"description": "UI-A6 §7 browserLimitReached", "placeholders": {"count": {"type": "int"}}},
  "browserErrorLocalRefusedTitle": "Nothing is running at {host}",
  "@browserErrorLocalRefusedTitle": {"description": "UI-A6 §7 browserErrorLocalRefusedTitle", "placeholders": {"host": {"type": "String"}}},
  "browserErrorLocalRefusedBody": "Start the server in a terminal (for example npm run dev), then try again.",
  "@browserErrorLocalRefusedBody": {"description": "UI-A6 §7 browserErrorLocalRefusedBody"},
  "browserErrorUnreachableTitle": "Can’t reach {host}",
  "@browserErrorUnreachableTitle": {"description": "UI-A6 §7 browserErrorUnreachableTitle", "placeholders": {"host": {"type": "String"}}},
  "browserErrorUnreachableBody": "Check the address and your network, then try again.",
  "@browserErrorUnreachableBody": {"description": "UI-A6 §7 browserErrorUnreachableBody"},
  "browserErrorDnsTitle": "Can’t find {host}",
  "@browserErrorDnsTitle": {"description": "UI-A6 §7 browserErrorDnsTitle", "placeholders": {"host": {"type": "String"}}},
  "browserErrorDnsBody": "The domain doesn’t exist or the network isn’t ready.",
  "@browserErrorDnsBody": {"description": "UI-A6 §7 browserErrorDnsBody"},
  "browserErrorTimeoutTitle": "{host} took too long to respond",
  "@browserErrorTimeoutTitle": {"description": "UI-A6 §7 browserErrorTimeoutTitle", "placeholders": {"host": {"type": "String"}}},
  "browserErrorCertTitle": "The connection to {host} isn’t secure",
  "@browserErrorCertTitle": {"description": "UI-A6 §7 browserErrorCertTitle", "placeholders": {"host": {"type": "String"}}},
  "browserErrorCertBody": "The site’s certificate isn’t valid. ShellX won’t open this page; you can open it in your system browser.",
  "@browserErrorCertBody": {"description": "UI-A6 §7 browserErrorCertBody"},
  "browserErrorCrashedTitle": "The page stopped unexpectedly",
  "@browserErrorCrashedTitle": {"description": "UI-A6 §7 browserErrorCrashedTitle"},
  "browserErrorCrashedBody": "Reload to open the page again.",
  "@browserErrorCrashedBody": {"description": "UI-A6 §7 browserErrorCrashedBody"},
  "browserErrorRuntimeTitle": "Microsoft Edge WebView2 Runtime is required",
  "@browserErrorRuntimeTitle": {"description": "UI-A6 §7 browserErrorRuntimeTitle"},
  "browserErrorRuntimeBody": "The browser pane uses Windows WebView2. Install the WebView2 Runtime, then open the pane again.",
  "@browserErrorRuntimeBody": {"description": "UI-A6 §7 browserErrorRuntimeBody"},
  "browserErrorRuntimeAction": "Get WebView2",
  "@browserErrorRuntimeAction": {"description": "UI-A6 §7 browserErrorRuntimeAction"},
  "browserErrorGenericTitle": "Can’t open the page",
  "@browserErrorGenericTitle": {"description": "UI-A6 §7 browserErrorGenericTitle"},
  "browserErrorRetry": "Try again",
  "@browserErrorRetry": {"description": "UI-A6 §7 browserErrorRetry"},
  "browserTrayMenu": "Browser",
  "@browserTrayMenu": {"description": "UI-A6 §7 browserTrayMenu"},
  "browserTrayKeepData": "Keep browser data (cookies, sign-ins)",
  "@browserTrayKeepData": {"description": "UI-A6 §7 browserTrayKeepData"},
  "browserTrayAgentAllOrigins": "Let agents control any page",
  "@browserTrayAgentAllOrigins": {"description": "UI-A6 §7 browserTrayAgentAllOrigins"},
  "browserTrayClearData": "Clear browser data",
  "@browserTrayClearData": {"description": "UI-A6 §7 browserTrayClearData"},
  "browserKeepDataRestartNote": "The change takes effect when you reopen ShellX.",
  "@browserKeepDataRestartNote": {"description": "UI-A6 §7 browserKeepDataRestartNote"},
  "browserDataCleared": "Browser data cleared",
  "@browserDataCleared": {"description": "UI-A6 §7 browserDataCleared"},
  "browserConfirmAllOriginsTitle": "Let agents control any page?",
  "@browserConfirmAllOriginsTitle": {"description": "UI-A6 §7 browserConfirmAllOriginsTitle"},
  "browserConfirmAllOriginsBody": "Agents on this computer (through the ShellX command line) will be able to run JavaScript, take screenshots and read the console of any page in a browser pane — including pages you’re signed in to. Only turn this on if you trust the agents you run.",
  "@browserConfirmAllOriginsBody": {"description": "UI-A6 §7 browserConfirmAllOriginsBody"},
  "browserConfirmAllOriginsAction": "Turn on",
  "@browserConfirmAllOriginsAction": {"description": "UI-A6 §7 browserConfirmAllOriginsAction"},
  "browserDialogTitle": "{host} says",
  "@browserDialogTitle": {"description": "UI-A6 §7 browserDialogTitle", "placeholders": {"host": {"type": "String"}}},
```

Add to `apps/desktop/lib/l10n/app_vi.arb` (vi column):

```json
  "browserOpenPane": "Mở pane trình duyệt",
  "browserOpenPortInPane": "Mở :{port} trong pane trình duyệt",
  "browserOpenPortInPaneMenu": "Mở cổng trong pane trình duyệt…",
  "browserPortAltClickHint": "{modifier}-click: mở trong pane trình duyệt",
  "browserBack": "Lùi  {shortcut}",
  "browserForward": "Tiến  {shortcut}",
  "browserReload": "Tải lại  {shortcut}",
  "browserStop": "Dừng  Esc",
  "browserOpenExternal": "Mở trong trình duyệt hệ thống",
  "browserCopyAddress": "Sao chép địa chỉ trang",
  "browserAddressLabel": "Địa chỉ trang",
  "browserAddressHint": "Nhập địa chỉ hoặc cổng",
  "browserAddressInvalid": "Không phải địa chỉ web",
  "browserOriginLocal": "Trang trên máy này",
  "browserOriginSecure": "Kết nối bảo mật",
  "browserOriginInsecure": "Không bảo mật",
  "browserUntitled": "Trình duyệt",
  "browserLoadingLabel": "Đang tải",
  "browserAgentMark": "Agent",
  "browserAgentMarkTooltip": "Một agent trên máy này đang điều khiển trang",
  "browserAnnounceAgent": "Agent đang điều khiển pane trình duyệt",
  "browserAnnounceLoaded": "Đã tải {title}",
  "browserPaneRegionLabel": "Pane {index} trên {count} — Trình duyệt: {title}",
  "browserToolbarRegionLabel": "Thanh công cụ trình duyệt",
  "browserSchemeBlocked": "Pane trình duyệt chỉ mở trang http và https",
  "browserDownloadBlocked": "Pane trình duyệt không tải file xuống — dùng “Mở trong trình duyệt hệ thống”",
  "browserLimitReached": "Đã đạt tối đa {count} pane trình duyệt",
  "browserErrorLocalRefusedTitle": "Chưa có gì chạy ở {host}",
  "browserErrorLocalRefusedBody": "Khởi động server trong terminal (vd. npm run dev) rồi thử lại.",
  "browserErrorUnreachableTitle": "Không kết nối được tới {host}",
  "browserErrorUnreachableBody": "Kiểm tra địa chỉ và kết nối mạng rồi thử lại.",
  "browserErrorDnsTitle": "Không tìm thấy {host}",
  "browserErrorDnsBody": "Tên miền không tồn tại hoặc mạng chưa sẵn sàng.",
  "browserErrorTimeoutTitle": "{host} phản hồi quá lâu",
  "browserErrorCertTitle": "Kết nối tới {host} không an toàn",
  "browserErrorCertBody": "Chứng chỉ của trang không hợp lệ. ShellX không mở trang này; bạn có thể mở trong trình duyệt hệ thống.",
  "browserErrorCrashedTitle": "Trang đã dừng bất ngờ",
  "browserErrorCrashedBody": "Tải lại để mở lại trang.",
  "browserErrorRuntimeTitle": "Cần Microsoft Edge WebView2 Runtime",
  "browserErrorRuntimeBody": "Pane trình duyệt dùng WebView2 của Windows. Cài WebView2 Runtime rồi mở lại pane.",
  "browserErrorRuntimeAction": "Tải WebView2",
  "browserErrorGenericTitle": "Không mở được trang",
  "browserErrorRetry": "Thử lại",
  "browserTrayMenu": "Trình duyệt",
  "browserTrayKeepData": "Giữ dữ liệu trình duyệt (cookie, đăng nhập)",
  "browserTrayAgentAllOrigins": "Cho phép agent điều khiển mọi trang",
  "browserTrayClearData": "Xóa dữ liệu trình duyệt",
  "browserKeepDataRestartNote": "Thay đổi có hiệu lực khi mở lại ShellX.",
  "browserDataCleared": "Đã xóa dữ liệu trình duyệt",
  "browserConfirmAllOriginsTitle": "Cho phép agent điều khiển mọi trang?",
  "browserConfirmAllOriginsBody": "Agent trên máy này (qua dòng lệnh ShellX) sẽ chạy được JavaScript, chụp ảnh và đọc console của mọi trang trong pane trình duyệt — kể cả trang bạn đã đăng nhập. Chỉ bật khi bạn tin các agent đang chạy.",
  "browserConfirmAllOriginsAction": "Bật",
  "browserDialogTitle": "{host} cho biết",
```

Run `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`.

In `ShellxSizes` (`shellx_desktop_theme.dart`) add, with the doc comment "UI-A6 §1.2":

```dart
  static const double browserToolbar = 32;
  static const double browserToolbarPadH = 6;
  static const double browserButton = 28;
  static const double browserButtonGap = 2;
  static const double browserAddressHeight = 24;
  static const double browserAddressPadH = 8;
  static const double browserOriginIcon = 14;
  static const double browserProgress = 2;
  static const double browserMinWidth = 240; // == kBrowserMinSize.width
  static const double browserMinHeight = 160; // == kBrowserMinSize.height
  static const double browserAgentMark = 20;
  static const double browserErrorMaxWidth = 420;
```

- [ ] **Step 6: Tray submenu "Trình duyệt"**

`tray_action.dart`: add to `TrayKeys`:

```dart
  static const String browser = 'browser';
  static const String browserKeepData = 'browser_keep_data';
  static const String browserAgentAllOrigins = 'browser_agent_all_origins';
  static const String browserClearData = 'browser_clear_data';
```

and the actions `final class ToggleBrowserKeepData extends TrayAction { const ToggleBrowserKeepData(); }`, `final class RequestBrowserAgentAllOrigins extends TrayAction { const RequestBrowserAgentAllOrigins(); }`, `final class ClearBrowserData extends TrayAction { const ClearBrowserData(); }`, mapped from the three keys wherever the existing key → action switch lives.

`tray_menu.dart`: `TrayLocalState` gains `this.browserKeepData = false, this.browserAgentAllOrigins = false` (fields `final bool …`). Next to A5a's `terminal()` builder:

```dart
  // UI-A6 §5: right after "Terminal", in both menus.
  MenuItem browser() => sub(TrayKeys.browser, l10n.browserTrayMenu, [
    check(
      TrayKeys.browserKeepData,
      l10n.browserTrayKeepData,
      local.browserKeepData,
    ),
    check(
      TrayKeys.browserAgentAllOrigins,
      l10n.browserTrayAgentAllOrigins,
      local.browserAgentAllOrigins,
    ),
    sep(),
    item(TrayKeys.browserClearData, l10n.browserTrayClearData),
  ]);
```

and insert `browser(),` right after `terminal(),` in both the signed-out and the signed-in `items` lists.

`tray_actions.dart`: `trayLocalStateProvider` also reads the two settings into `TrayLocalState`. Handle the actions:
- `ToggleBrowserKeepData` → `settings.setBool(SettingKeys.browserKeepData, !current)`; on Windows then show the neutral toast `browserKeepDataRestartNote` (A1 toast if the window is visible, else `LocalSystemNotifier`). macOS turning it **off** also calls `ref.read(browserProfileProvider).clearNow()` (D26: off → clear now).
- `RequestBrowserAgentAllOrigins` → when on: set `false` at once. When off: show the window and open the A1 short confirm (same route the tray uses for `confirmQuit*`) with `browserConfirmAllOriginsTitle`, `browserConfirmAllOriginsBody`, action `browserConfirmAllOriginsAction`, initial focus on Hủy; on confirm set `true`.
- `ClearBrowserData` → `final now = await ref.read(browserProfileProvider).clearNow();` → toast `browserDataCleared` when `now`, else `browserKeepDataRestartNote`.
Invalidate `trayLocalStateProvider` after each.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/ test/ui/browser_shortcuts_test.dart test/tray/ && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS (A5a's tray test still passes: its index check is `notifications == terminal + 1` → update that one expectation to `browser == terminal + 1` and `notifications == browser + 1`, since UI-A6 §5 places "Trình duyệt" between them).

- [ ] **Step 8: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/browser apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/src/tray apps/desktop/lib/src/ui apps/desktop/test/browser apps/desktop/test/ui/browser_shortcuts_test.dart apps/desktop/test/tray
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/browser/browser_profile.dart apps/desktop/lib/src/browser/shots_dir.dart apps/desktop/lib/src/browser/browser_chords.dart apps/desktop/lib/src/browser/browser_registry.dart apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/src/tray apps/desktop/lib/l10n apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/test/browser/browser_profile_test.dart apps/desktop/test/browser/shots_dir_test.dart apps/desktop/test/browser/browser_chords_test.dart apps/desktop/test/ui/browser_shortcuts_test.dart apps/desktop/test/tray/tray_browser_menu_test.dart
git commit -m "feat(desktop): browser settings, private profile, screenshot folder, tray submenu, strings and chords (A6 D15, D24, D26, D27)"
```

(Add the A5a tray test file to `git add` if Step 7 changed it.)

---

### Task 7: ⚠ macOS engine — `WkWebViewEngine` + `BrowserNative.swift` (D1, D10, D15, D16, D24, D26, D32)

Read the ledger line "Spike macOS" first. If spike item 7 failed (the plugin's external API is not reachable from Swift), **stop and report to the controller**: the spec D1 fallback (finding the `WKWebView` by walking the platform view's `NSView` subtree) needs a way to map a Dart controller to its native view and gets its own short design.

**Files:**
- Create: `apps/desktop/lib/src/browser/engines/wk_webview_engine.dart`
- Create: `apps/desktop/macos/Runner/BrowserNative.swift`; Modify: `apps/desktop/macos/Runner/MainFlutterWindow.swift`, `apps/desktop/macos/Runner.xcodeproj/project.pbxproj`
- Test: `apps/desktop/test/browser/wk_webview_engine_test.dart`

**Interfaces:**
- Consumes: Task 4 `BrowserEngine` + events, Task 2 `isNavigable`, Task 3 `BridgeTransport.webkit`, Task 6 `WebsiteDataClearer`.
- Produces:
  - `const browserNativeChannelName = 'pro.shellx.desktop/browser'`.
  - `final class BrowserNativeMac implements WebsiteDataClearer { BrowserNativeMac([MethodChannel channel]); void attach(int webViewId, void Function(BrowserEngineEvent) sink); void detach(int webViewId); Future<Uint8List> snapshot(int id); Future<void> stop(int id); Future<void> focus(int id); Future<void> blur(int id); Future<void> addBootstrap(int id, String source); Future<void> setForwardedChords(int id, List<String> chords); Future<void> clearWebsiteData(); }` — inbound calls `shortcut {id, chord}` → `ShortcutForwarded`, `pointerDown {id}` → `ContentClicked`.
  - `typedef BrowserDialogPresenter = Future<Object?> Function(BrowserJsDialog dialog)`; `final class BrowserJsDialog { const BrowserJsDialog({required this.kind, required this.host, required this.message, this.defaultText}); final BrowserJsDialogKind kind; … }`; `enum BrowserJsDialogKind { alert, confirm, prompt }` (presenter returns `null` for alert, `bool` for confirm, `String?` for prompt).
  - `BrowserLoadErrorKind? macErrorKind(int code, {bool processTerminated = false})` (`null` = ignore); `bool isMacInterruptedLoad(int code)` (WebKit 102 → download/policy).
  - `final class WkWebViewEngine implements BrowserEngine { WkWebViewEngine({required BrowserNativeMac native, required String bootstrap, BrowserDialogPresenter? dialogs}); }`.

- [ ] **Step 1: Write the failing test (Dart side: error mapping and the channel)**

Create `apps/desktop/test/browser/wk_webview_engine_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NSURLError codes map to error kinds (D14)', () {
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
    expect(macErrorKind(0, processTerminated: true), BrowserLoadErrorKind.crashed);
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
      return call.method == 'snapshot' ? Uint8List.fromList([1, 2]) : null;
    });
    final native = BrowserNativeMac(channel);
    final events = <BrowserEngineEvent>[];
    native.attach(7, events.add);
    await native.setForwardedChords(7, ['meta+l']);
    expect(await native.snapshot(7), [1, 2]);
    await native.stop(7);
    await native.clearWebsiteData();
    expect(calls.map((c) => c.method), ['setForwardedChords', 'snapshot', 'stop', 'clearWebsiteData']);
    expect(calls.first.arguments, {'id': 7, 'chords': ['meta+l']});

    Future<void> inbound(String method, Map<String, Object?> args) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await inbound('shortcut', {'id': 7, 'chord': 'meta+l'});
    await inbound('pointerDown', {'id': 7});
    await inbound('shortcut', {'id': 99, 'chord': 'meta+l'}); // unknown pane: dropped
    expect(events.length, 2);
    expect((events[0] as ShortcutForwarded).chord, 'meta+l');
    expect(events[1], isA<ContentClicked>());
    native.detach(7);
    await inbound('pointerDown', {'id': 7});
    expect(events.length, 2);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/wk_webview_engine_test.dart`
Expected: FAIL — `wk_webview_engine.dart` does not exist.

- [ ] **Step 3: Write `BrowserNative.swift`**

Create `apps/desktop/macos/Runner/BrowserNative.swift`:

```swift
import Cocoa
import FlutterMacOS
import WebKit
import webview_flutter_wkwebview

/// A6 Task 7: what webview_flutter's Dart API lacks — snapshot, stop, a
/// document-start script, clearing the app's website data, and handing
/// ShellX chords and clicks back to Flutter while a page has the keyboard
/// (spec D1, D15, D16, D24, D26). Channel "pro.shellx.desktop/browser".
final class BrowserNative: NSObject {
  private let channel: FlutterMethodChannel
  private let registry: FlutterPluginRegistry
  /// Web view id → chords to forward. An id is known once Dart called
  /// setForwardedChords for it (every engine does at setup).
  private var forwarded: [Int64: Set<String>] = [:]
  private var keyMonitor: Any?
  private var mouseMonitor: Any?

  init(messenger: FlutterBinaryMessenger, registry: FlutterPluginRegistry) {
    channel = FlutterMethodChannel(
      name: "pro.shellx.desktop/browser", binaryMessenger: messenger)
    self.registry = registry
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
    WebViewFlutterWKWebViewExternalAPI.webView(
      forIdentifier: id, withPluginRegistry: registry)
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
    case "addBootstrap":
      web.configuration.userContentController.addUserScript(
        WKUserScript(
          source: args["source"] as? String ?? "",
          injectionTime: .atDocumentStart, forMainFrameOnly: true))
      result(nil)
    case "stop":
      web.stopLoading()
      result(nil)
    case "focus":
      web.window?.makeFirstResponder(web)
      result(nil)
    case "blur":
      // Back to the Flutter view, so the next keys reach Flutter (D16).
      if let flutter = registry as? FlutterViewController,
        web.window?.firstResponder is NSView,
        let responder = web.window?.firstResponder as? NSView,
        responder === web || responder.isDescendant(of: web)
      {
        web.window?.makeFirstResponder(flutter.view)
      }
      result(nil)
    case "snapshot":
      web.takeSnapshot(with: nil) { image, _ in
        guard let image, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
        else {
          result(FlutterError(code: "snapshot_failed", message: nil, details: nil))
          return
        }
        result(FlutterStandardTypedData(bytes: png))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

In `MainFlutterWindow.swift`, where the `FlutterViewController` is created (the UI path only — A5b's `--daemon` path creates none, so the daemon never has browser panes, D35), keep a strong reference:

```swift
  private var browserNative: BrowserNative?
  // … after RegisterGeneratedPlugins(registry: flutterViewController):
  browserNative = BrowserNative(
    messenger: flutterViewController.engine.binaryMessenger,
    registry: flutterViewController)
```

Add `BrowserNative.swift` to the Runner target (Xcode: File → Add Files to "Runner"…, target Runner checked). Verify: `grep -c BrowserNative.swift apps/desktop/macos/Runner.xcodeproj/project.pbxproj` prints `4` (build file, file reference, group, sources phase).

- [ ] **Step 4: Write the Dart engine**

Create `apps/desktop/lib/src/browser/engines/wk_webview_engine.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../browser_bridge.dart';
import '../browser_engine.dart';
import '../browser_profile.dart';
import '../browser_url.dart';

const String browserNativeChannelName = 'pro.shellx.desktop/browser';

/// D14: NSURLErrorDomain codes → error page kinds; `null` = not an error
/// to show (-999: cancelled because a newer navigation started).
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
/// navigation it cannot display — a download (D10).
bool isMacInterruptedLoad(int code) => code == 102;

enum BrowserJsDialogKind { alert, confirm, prompt }

final class BrowserJsDialog {
  const BrowserJsDialog({
    required this.kind,
    required this.host,
    required this.message,
    this.defaultText,
  });
  final BrowserJsDialogKind kind;
  final String host;
  final String message;
  final String? defaultText;
}

/// D32: shows the A1 dialog; returns null (alert), bool (confirm) or
/// String? (prompt). Wired in main.dart (Task 9).
typedef BrowserDialogPresenter = Future<Object?> Function(BrowserJsDialog dialog);

/// The app's one `pro.shellx.desktop/browser` channel (BrowserNative.swift).
final class BrowserNativeMac implements WebsiteDataClearer {
  BrowserNativeMac([
    MethodChannel channel = const MethodChannel(browserNativeChannelName),
  ]) : _channel = channel {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final Map<int, void Function(BrowserEngineEvent)> _sinks = {};

  void attach(int webViewId, void Function(BrowserEngineEvent) sink) =>
      _sinks[webViewId] = sink;

  void detach(int webViewId) {
    _sinks.remove(webViewId);
    unawaited(_channel.invokeMethod<void>('forget', {'id': webViewId}));
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

  Future<Uint8List> snapshot(int id) async =>
      (await _channel.invokeMethod<Uint8List>('snapshot', {'id': id}))!;
  Future<void> stop(int id) => _channel.invokeMethod<void>('stop', {'id': id});
  Future<void> focus(int id) =>
      _channel.invokeMethod<void>('focus', {'id': id});
  Future<void> blur(int id) => _channel.invokeMethod<void>('blur', {'id': id});
  Future<void> addBootstrap(int id, String source) => _channel
      .invokeMethod<void>('addBootstrap', {'id': id, 'source': source});
  Future<void> setForwardedChords(int id, List<String> chords) => _channel
      .invokeMethod<void>('setForwardedChords', {'id': id, 'chords': chords});
  @override
  Future<void> clearWebsiteData() =>
      _channel.invokeMethod<void>('clearWebsiteData');
}

/// A6 D1: WKWebView through webview_flutter_wkwebview, as a platform view.
final class WkWebViewEngine implements BrowserEngine {
  WkWebViewEngine({
    required BrowserNativeMac native,
    required String bootstrap,
    BrowserDialogPresenter? dialogs,
  }) : _native = native,
       _dialogs = dialogs {
    _controller = WebViewController.fromPlatformCreationParams(
      WebKitWebViewControllerCreationParams(),
    );
    _platform = _controller.platform as WebKitWebViewController;
    _id = _platform.webViewIdentifier;
    _native.attach(_id, _emit);
    _ready = _setup(bootstrap);
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

  Future<void> _setup(String bootstrap) async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _platform.setInspectable(true);
    await _controller.addJavaScriptChannel(
      'ShellxBrowser',
      onMessageReceived: (m) => _emit(BridgeReceived(m.message)),
    );
    await _native.addBootstrap(_id, bootstrap);
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
                error.errorType == WebResourceErrorType.webContentProcessTerminated,
          );
          if (kind != null) _emit(LoadFailed(kind));
        },
      ),
    );
    await _controller.setOnJavaScriptAlertDialog((r) async {
      _logDialog('alert', r.message);
      await _dialogs?.call(_dialog(BrowserJsDialogKind.alert, r.url, r.message));
    });
    await _controller.setOnJavaScriptConfirmDialog((r) async {
      _logDialog('confirm', r.message);
      final ok = await _dialogs?.call(
        _dialog(BrowserJsDialogKind.confirm, r.url, r.message),
      );
      return ok == true;
    });
    await _controller.setOnJavaScriptTextInputDialog((r) async {
      _logDialog('prompt', r.message);
      final text = await _dialogs?.call(
        BrowserJsDialog(
          kind: BrowserJsDialogKind.prompt,
          host: Uri.tryParse(r.url)?.host ?? '',
          message: r.message,
          defaultText: r.defaultText,
        ),
      );
      return text is String ? text : '';
    });
  }

  BrowserJsDialog _dialog(BrowserJsDialogKind kind, String url, String message) =>
      BrowserJsDialog(kind: kind, host: Uri.tryParse(url)?.host ?? '', message: message);

  /// D32: the dialog also lands in the console buffer, as page data.
  void _logDialog(String kind, String message) => _emit(
    BridgeReceived(
      jsonEncode({'t': 'console', 'level': 'info', 'text': '[dialog] $kind: $message'}),
    ),
  );

  Future<void> _history() async => _emit(
    HistoryChanged(
      canGoBack: await _controller.canGoBack(),
      canGoForward: await _controller.canGoForward(),
    ),
  );

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  BridgeTransport get transport => BridgeTransport.webkit;

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
  Future<void> goBack() async => (await _ready, await _controller.goBack());
  @override
  Future<void> goForward() async =>
      (await _ready, await _controller.goForward());
  @override
  Future<void> reload() async => (await _ready, await _controller.reload());
  @override
  Future<void> stop() async => (await _ready, await _native.stop(_id));

  @override
  Future<void> runScript(String script) async {
    await _ready;
    await _controller.runJavaScript(script);
  }

  @override
  Future<Uint8List> capturePng() async {
    await _ready;
    return _native.snapshot(_id);
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
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    _native.detach(_id);
    await _events.close();
  }
}
```

(If the analyzer rejects the record-expression bodies of `goBack`/`goForward`/`reload`/`stop`, write them as `{ await _ready; await _controller.goBack(); }`.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/wk_webview_engine_test.dart`
Expected: PASS (2 tests). Build: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug` — succeeds.

- [ ] **Step 6: ⚠ MANUAL — macOS engine checks**

With a scratch override in a debug run (Task 9 wires the real UI; here call the registry from a temporary debug button, then remove it), on a real Mac:
1. `python3 -m http.server 8000` in a terminal; open a pane on `http://localhost:8000/` — loads; `TitleChanged("Directory listing for /")` arrives (title via bridge and `getTitle`).
2. `evalJs('return document.title')` → the title; on a page with a strict CSP (`https://github.com/`, after enabling all origins) still works.
3. `screenshot()` → PNG at 2× on Retina (width = 2 × view width).
4. Press ⌘L inside a page text field → `ShortcutForwarded('meta+l')`, the field does **not** receive "l"; ⌘C/⌘V still work in the field; Telex IME composes. After `releaseFocus()` the next keys reach Flutter, not the page.
5. Click into the page → `ContentClicked`.
6. Navigate to `mailto:x@y.z` link → `NavigationBlocked`, no Mail.app; download link (a `.zip`) → `DownloadBlocked`.
7. `alert('hi')` from eval → presenter called; console has "[dialog] alert: hi".
8. `clearWebsiteData` → a cookie set on `localhost:8000` (`document.cookie='a=1'`) is gone after reload.
Record results under "## A6 (browser pane) — spike" as `Task 7 macOS: …`.

- [ ] **Step 7: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/browser/engines/wk_webview_engine.dart apps/desktop/test/browser/wk_webview_engine_test.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/browser/engines/wk_webview_engine.dart apps/desktop/test/browser/wk_webview_engine_test.dart apps/desktop/macos/Runner/BrowserNative.swift apps/desktop/macos/Runner/MainFlutterWindow.swift apps/desktop/macos/Runner.xcodeproj/project.pbxproj docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "feat(desktop): macOS browser engine on WKWebView with native snapshot, stop, bootstrap and key forwarding (A6 D1, D15, D24, D26)"
```

---

### Task 8: ⚠ Windows engine — vendored patches + `WebView2Engine` (D2, D10, D15, D16, D24, D26)

Read the ledger line "Spike Windows" first. The C++ edits are made on any machine but only build and run on Windows; a macOS executor writes them, runs the Dart tests, and marks Step 6 "⚠ PENDING MANUAL".

**Files:**
- Modify: `third_party/webview_windows/windows/webview.h`, `webview.cc`, `webview_bridge.cc` (exact file names: the 0.4.0 package's `windows/` folder — the class wrapping `ICoreWebView2Controller` and the per-webview method/event channel bridge), `third_party/webview_windows/lib/src/webview.dart`, `third_party/webview_windows/SHELLX_PATCHES.md`
- Create: `apps/desktop/lib/src/browser/engines/webview2_engine.dart`
- Test: `apps/desktop/test/browser/webview2_engine_test.dart`

**Interfaces:**
- Consumes: Task 4, Task 2 `isNavigable`, Task 6 `BrowserProfile.userDataPath`.
- Produces:
  - Plugin Dart API (patches): `WebviewController.capturePreview() → Future<Uint8List>`, `setForwardedAccelerators(List<String>)`, `moveFocus()`, streams `acceleratorKey` (`Stream<String>`), `downloadBlocked` (`Stream<void>`), `navigationBlocked` (`Stream<void>`).
  - `BrowserLoadErrorKind? webErrorKind(String statusName)` (`null` = ignore).
  - `final class WebView2Engine implements BrowserEngine { WebView2Engine({required Future<void> environmentReady, required String bootstrap}); }`.
  - `Future<void> initWebView2Environment(BrowserProfile profile)` — memoized `WebviewController.initializeEnvironment(userDataPath: profile.userDataPath)` after `profile.prepare()`.

- [ ] **Step 1: Write the failing test**

Create `apps/desktop/test/browser/webview2_engine_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/webview2_engine.dart';

void main() {
  test('WebView2 web error statuses map to error kinds (D14)', () {
    expect(webErrorKind('operationCanceled'), isNull);
    expect(webErrorKind('WebErrorStatusOperationCanceled'), isNull);
    expect(webErrorKind('cannotConnect'), BrowserLoadErrorKind.refused);
    expect(webErrorKind('hostNameNotResolved'), BrowserLoadErrorKind.dns);
    expect(webErrorKind('timeout'), BrowserLoadErrorKind.timeout);
    for (final s in ['certificateCommonNameIsIncorrect', 'certificateExpired',
        'clientCertificateContainsErrors', 'certificateRevoked', 'certificateIsInvalid']) {
      expect(webErrorKind(s), BrowserLoadErrorKind.certificate);
    }
    for (final s in ['serverUnreachable', 'disconnected', 'connectionReset', 'connectionAborted']) {
      expect(webErrorKind(s), BrowserLoadErrorKind.unreachable);
    }
    expect(webErrorKind('unknown'), BrowserLoadErrorKind.other);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/webview2_engine_test.dart`
Expected: FAIL — `webview2_engine.dart` does not exist.

- [ ] **Step 3: Patch the plugin (C++)**

In the class that owns `ICoreWebView2Controller`/`ICoreWebView2` (`webview.h`/`.cc`), add members `std::set<std::string> forwarded_accelerators_;` and event tokens, and these pieces. Each event goes out through the plugin's existing event sink as a map `{"type": "<name>", "value": …}` — use the same helper the plugin uses for `"urlChanged"`.

(a) Capture:

```cpp
void Webview::CapturePreview(
    std::function<void(bool ok, std::vector<uint8_t> png)> done) {
  wil::com_ptr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    done(false, {});
    return;
  }
  webview_->CapturePreview(
      COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.get(),
      Microsoft::WRL::Callback<ICoreWebView2CapturePreviewCompletedHandler>(
          [stream, done](HRESULT hr) -> HRESULT {
            if (FAILED(hr)) {
              done(false, {});
              return S_OK;
            }
            STATSTG stat{};
            stream->Stat(&stat, STATFLAG_NONAME);
            std::vector<uint8_t> bytes(
                static_cast<size_t>(stat.cbSize.QuadPart));
            LARGE_INTEGER zero{};
            stream->Seek(zero, STREAM_SEEK_SET, nullptr);
            ULONG read = 0;
            stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read);
            bytes.resize(read);
            done(true, std::move(bytes));
            return S_OK;
          })
          .Get());
}
```

Bridge method `"capturePreview"` → `result->Success(flutter::EncodableValue(png))` (a `std::vector<uint8_t>` encodes as `Uint8List`), or `result->Error("capture_failed")`.

(b) Accelerators — `"setForwardedAccelerators"` takes a list of strings into `forwarded_accelerators_`; register once after the controller is created:

```cpp
// Same chord format as Dart's chordString: alt, ctrl, meta, shift, key.
// Right Alt (AltGr) never matches: those keys belong to the page (A3 D20).
static std::string ChordFor(UINT vk) {
  if (GetKeyState(VK_RMENU) & 0x8000) return "";
  const bool alt = GetKeyState(VK_LMENU) & 0x8000;
  const bool ctrl = GetKeyState(VK_CONTROL) & 0x8000;
  const bool shift = GetKeyState(VK_SHIFT) & 0x8000;
  std::string key;
  if (vk >= 'A' && vk <= 'Z') {
    key = std::string(1, static_cast<char>(vk - 'A' + 'a'));
  } else if (vk >= '0' && vk <= '9') {
    key = std::string(1, static_cast<char>(vk));
  } else {
    switch (vk) {
      case VK_LEFT: key = "left"; break;
      case VK_RIGHT: key = "right"; break;
      case VK_UP: key = "up"; break;
      case VK_DOWN: key = "down"; break;
      case VK_ESCAPE: key = "escape"; break;
      case VK_RETURN: key = "enter"; break;
      case VK_TAB: key = "tab"; break;
      case VK_F5: key = "f5"; break;
      case VK_F6: key = "f6"; break;
      case VK_OEM_4: key = "["; break;
      case VK_OEM_6: key = "]"; break;
      case VK_OEM_PLUS: key = "="; break;
      case VK_OEM_MINUS: key = "-"; break;
      default: return "";
    }
  }
  std::string chord;
  if (alt) chord += "alt+";
  if (ctrl) chord += "ctrl+";
  if (shift) chord += "shift+";
  return chord + key;
}

// in the controller setup:
webview_controller_->add_AcceleratorKeyPressed(
    Microsoft::WRL::Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
        [this](ICoreWebView2Controller*,
               ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT {
          COREWEBVIEW2_KEY_EVENT_KIND kind;
          args->get_KeyEventKind(&kind);
          if (kind != COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN &&
              kind != COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN) {
            return S_OK;
          }
          UINT vk = 0;
          args->get_VirtualKey(&vk);
          const std::string chord = ChordFor(vk);
          if (!chord.empty() && forwarded_accelerators_.count(chord)) {
            args->put_Handled(TRUE);
            EmitEvent("acceleratorKey", flutter::EncodableValue(chord));
          }
          return S_OK;
        })
        .Get(),
    &accelerator_token_);
```

(c) Downloads (needs `ICoreWebView2_4`):

```cpp
if (auto webview4 = webview_.try_query<ICoreWebView2_4>()) {
  webview4->add_DownloadStarting(
      Microsoft::WRL::Callback<ICoreWebView2DownloadStartingEventHandler>(
          [this](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args)
              -> HRESULT {
            args->put_Cancel(TRUE);
            EmitEvent("downloadBlocked", flutter::EncodableValue());
            return S_OK;
          })
          .Get(),
      &download_token_);
}
```

(d) Navigation policy — inside the plugin's existing `add_NavigationStarting` handler (it already reports the loading state), before anything else:

```cpp
wil::unique_cotaskmem_string uri;
args->get_Uri(&uri);
const std::wstring u = uri.get() ? uri.get() : L"";
const bool allowed = u.rfind(L"http://", 0) == 0 ||
                     u.rfind(L"https://", 0) == 0 || u == L"about:blank";
if (!allowed) {
  args->put_Cancel(TRUE);
  EmitEvent("navigationBlocked", flutter::EncodableValue());
  return S_OK;
}
```

(the comparison is case-sensitive; WebView2 reports the scheme lower-case).

(e) Focus — bridge method `"moveFocus"` → `webview_controller_->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)`.

Remove each handler with its token in the destructor (`remove_AcceleratorKeyPressed(accelerator_token_)`, `remove_DownloadStarting(download_token_)`).

- [ ] **Step 4: Patch the plugin (Dart) and the patch list**

In `third_party/webview_windows/lib/src/webview.dart` (`WebviewController`): add stream controllers and the methods, following the file's existing `_methodChannel.invokeMethod` / event `switch (map['type'])` pattern:

```dart
  final StreamController<String> _acceleratorKeyController = StreamController.broadcast();
  final StreamController<void> _downloadBlockedController = StreamController.broadcast();
  final StreamController<void> _navigationBlockedController = StreamController.broadcast();

  /// ShellX patch (b).
  Stream<String> get acceleratorKey => _acceleratorKeyController.stream;
  /// ShellX patch (c).
  Stream<void> get downloadBlocked => _downloadBlockedController.stream;
  /// ShellX patch (d).
  Stream<void> get navigationBlocked => _navigationBlockedController.stream;

  /// ShellX patch (a).
  Future<Uint8List> capturePreview() async {
    if (_isDisposed) throw StateError('disposed');
    assert(value.isInitialized);
    return (await _methodChannel.invokeMethod<Uint8List>('capturePreview'))!;
  }

  /// ShellX patch (b).
  Future<void> setForwardedAccelerators(List<String> chords) async {
    if (_isDisposed) return;
    await _methodChannel.invokeMethod('setForwardedAccelerators', chords);
  }

  /// ShellX patch (e).
  Future<void> moveFocus() async {
    if (_isDisposed) return;
    await _methodChannel.invokeMethod('moveFocus');
  }
```

In the event `switch`: `case 'acceleratorKey': _acceleratorKeyController.add(map['value'] as String);`, `case 'downloadBlocked': _downloadBlockedController.add(null);`, `case 'navigationBlocked': _navigationBlockedController.add(null);`; close the three controllers in `dispose()`.

- [ ] **Step 5: Write the engine**

Create `apps/desktop/lib/src/browser/engines/webview2_engine.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

import '../browser_bridge.dart';
import '../browser_controller.dart';
import '../browser_engine.dart';
import '../browser_profile.dart';
import '../browser_url.dart';

/// D14: `WebErrorStatus` names (they mirror COREWEBVIEW2_WEB_ERROR_STATUS,
/// with or without a `WebErrorStatus` prefix) → error page kinds; `null`
/// = a cancelled navigation, not an error.
BrowserLoadErrorKind? webErrorKind(String statusName) {
  final n = statusName.toLowerCase();
  if (n.contains('canceled') || n.contains('cancelled')) return null;
  if (n.contains('certificate')) return BrowserLoadErrorKind.certificate;
  if (n.contains('cannotconnect')) return BrowserLoadErrorKind.refused;
  if (n.contains('hostnamenotresolved')) return BrowserLoadErrorKind.dns;
  if (n.contains('timeout')) return BrowserLoadErrorKind.timeout;
  if (n.contains('unreachable') ||
      n.contains('disconnected') ||
      n.contains('reset') ||
      n.contains('aborted')) {
    return BrowserLoadErrorKind.unreachable;
  }
  return BrowserLoadErrorKind.other;
}

Future<void>? _environment;

/// D26: one WebView2 environment per run, in the profile's folder.
Future<void> initWebView2Environment(BrowserProfile profile) =>
    _environment ??= () async {
      await profile.prepare();
      await WebviewController.initializeEnvironment(
        userDataPath: profile.userDataPath,
      );
    }();

/// A6 D2: WebView2 through the vendored webview_windows (texture).
final class WebView2Engine implements BrowserEngine {
  WebView2Engine({
    required Future<void> environmentReady,
    required String bootstrap,
  }) {
    _ready = _setup(environmentReady, bootstrap);
  }

  final WebviewController _c = WebviewController();
  late final Future<void> _ready;
  final List<StreamSubscription<Object?>> _subs = [];
  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast();

  void _emit(BrowserEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _setup(Future<void> environmentReady, String bootstrap) async {
    await environmentReady;
    if (await WebviewController.getWebViewVersion() == null) {
      _emit(const LoadFailed(BrowserLoadErrorKind.unavailable));
      throw const BrowserError('unavailable');
    }
    await _c.initialize();
    await _c.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
    await _c.addScriptToExecuteOnDocumentCreated(bootstrap);
    _subs.addAll([
      _c.url.listen((u) {
        final uri = Uri.tryParse(u);
        if (uri != null) _emit(UrlChanged(uri));
      }),
      _c.title.listen((t) => _emit(TitleChanged(t))),
      _c.loadingState.listen((s) {
        if (s == LoadingState.loading) _emit(const LoadStarted());
        if (s == LoadingState.navigationCompleted) _emit(const LoadFinished());
      }),
      _c.historyChanged.listen(
        (h) => _emit(
          HistoryChanged(canGoBack: h.canGoBack, canGoForward: h.canGoForward),
        ),
      ),
      _c.onLoadError.listen((status) {
        final kind = webErrorKind(status.name);
        if (kind != null) _emit(LoadFailed(kind));
      }),
      _c.webMessage.listen(
        (m) => _emit(BridgeReceived(m is String ? m : jsonEncode(m))),
      ),
      _c.acceleratorKey.listen((chord) => _emit(ShortcutForwarded(chord))),
      _c.downloadBlocked.listen((_) => _emit(const DownloadBlocked())),
      _c.navigationBlocked.listen((_) => _emit(const NavigationBlocked())),
    ]);
  }

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  BridgeTransport get transport => BridgeTransport.webview2;

  @override
  Future<void> load(Uri url) async {
    await _ready;
    if (url == aboutBlank) {
      await _c.loadStringContent('');
    } else {
      await _c.loadUrl(url.toString());
    }
  }

  @override
  Future<void> goBack() async {
    await _ready;
    await _c.goBack();
  }

  @override
  Future<void> goForward() async {
    await _ready;
    await _c.goForward();
  }

  @override
  Future<void> reload() async {
    await _ready;
    await _c.reload();
  }

  @override
  Future<void> stop() async {
    await _ready;
    await _c.stop();
  }

  @override
  Future<void> runScript(String script) async {
    await _ready;
    await _c.executeScript(script);
  }

  @override
  Future<Uint8List> capturePng() async {
    await _ready;
    return _c.capturePreview();
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async {
    await _ready;
    await _c.setForwardedAccelerators(chords);
  }

  @override
  Future<void> focusContent() async {
    await _ready;
    await _c.moveFocus();
  }

  /// The texture has no native focus of its own: Flutter focusing another
  /// node is enough (⚠ checked in Step 6).
  @override
  Future<void> releaseFocus() async {}

  @override
  Widget buildView() => Listener(
    onPointerDown: (_) => _emit(const ContentClicked()),
    child: ValueListenableBuilder<WebviewValue>(
      valueListenable: _c,
      builder: (context, value, _) => value.isInitialized
          ? Webview(
              _c,
              // D36: no camera, microphone, location or notifications.
              permissionRequested: (url, kind, isUserInitiated) async =>
                  WebviewPermissionDecision.deny,
            )
          : const SizedBox.expand(),
    ),
  );

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _events.close();
    await _c.dispose();
  }
}
```

(The `WebErrorStatus`/`LoadingState`/`HistoryChanged`/`WebviewPermissionDecision` names come from `webview_windows` 0.4.0; if one differs, follow the vendored source — the mapping logic stays.)

- [ ] **Step 6: ⚠ MANUAL — Windows engine checks (real Windows)**

`flutter build windows --debug` must succeed. Then the eight checks of Task 7 Step 6 with Windows keys (Ctrl+L inside a page field → forwarded, field gets no "l"; AltGr+L on a Polish layout → reaches the page), plus:
9. After focusing a terminal pane with Ctrl+Alt+← from the page, typing reaches the shell (texture engine needs no `releaseFocus`); if keys still reach the page, record it — add a patch (f) that calls `MoveFocus` away / `SetFocus` on the Flutter HWND.
10. Esc while loading a slow page (`python3 -c` server that sleeps 10 s) → forwarded and stops; if `AcceleratorKeyPressed` does not fire for plain Esc, record it — the toolbar ✕ remains the way to stop (spec D15 note), no further work.
11. A fresh run with `browser_keep_data` off has a new `%LOCALAPPDATA%\ShellX\webview\s-*` folder and the previous run's folder is gone.
12. Uninstall WebView2 Runtime is not practical — instead rename `%ProgramFiles(x86)%\Microsoft\EdgeWebView` in a VM snapshot and confirm the "Cần Microsoft Edge WebView2 Runtime" page (after Task 9).
Record as `Task 8 Windows: …` in the ledger.

- [ ] **Step 7: Run the tests, format, analyze, commit**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/webview2_engine_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze`
Expected: PASS (1 test), no issues.

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib/src/browser/engines/webview2_engine.dart apps/desktop/test/browser/webview2_engine_test.dart third_party/webview_windows/lib
git add third_party/webview_windows apps/desktop/lib/src/browser/engines/webview2_engine.dart apps/desktop/test/browser/webview2_engine_test.dart docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "feat(desktop): Windows browser engine on patched webview_windows: capture, accelerators, downloads, scheme policy, focus (A6 D2, D10, D15, D24)"
```

---
### Task 9: UI — browser pane view, toolbar, error page, focus regions, entry points, wiring (D7, D8, D12–D17, D25, D32)

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/browser_pane_view.dart`, `apps/desktop/lib/src/browser/browser_dialogs.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart` (A3), `terminal_workspace_page.dart`, `terminal_overlays.dart`, `session_tab_row.dart`, `session_sidebar.dart`
- Modify: `apps/desktop/lib/src/platform/url_opener.dart` (+ `test/support/fakes.dart` fake opener), `apps/desktop/lib/main.dart`
- Test: `apps/desktop/test/ui/browser_pane_view_test.dart`, `apps/desktop/test/ui/browser_entry_points_test.dart`, `apps/desktop/test/platform/url_opener_test.dart` (extend)

**Interfaces:**
- Consumes: Tasks 2–8 (all names above); A3 `PaneTreeView`, its header widget and divider clamp, `terminalFocus` handling; A1 `ShellxIconButton`, `ShellxPrimaryButton`, `NoticeToast` neutral list, `SemanticsService.sendAnnouncement` pattern, `desktopServicesProvider.urlOpener`; A2 port link (`onOpenPort`) and row menu port items.
- Produces:
  - `UrlOpener.openWebPage(Uri uri)` — opens absolute `http`/`https` URLs with a host in the default browser (W2 "Open in system browser"); anything else throws `ArgumentError` without running a command.
  - `final class BrowserDialogQueue extends ChangeNotifier { BrowserJsDialog? get current; Future<Object?> present(BrowserJsDialog dialog); void complete(Object? result); }` + `final browserDialogsProvider = Provider<BrowserDialogQueue>` (overridden in `main.dart`).
  - `class BrowserPaneView extends ConsumerStatefulWidget { const BrowserPaneView({super.key, required int paneId, required bool focused, required FocusNode contentFocus, FocusNode? addressFocus}); }` (keys: `Key('browser.toolbar')`, `Key('browser.address')`, `Key('browser.back')`, `Key('browser.forward')`, `Key('browser.reload')`, `Key('browser.external')`, `Key('browser.progress')`, `Key('browser.origin')`, `Key('browser.agent')`, `Key('browser.error')`).
  - `class BrowserPaneHeaderContent extends StatelessWidget` (globe + title for A3's pane header).
  - `SessionTabRow.onOpenPortInPane` (`void Function(int port)?`).

- [ ] **Step 1: Write the failing widget tests**

Create `apps/desktop/test/ui/browser_pane_view_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/browser_registry.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/browser_pane_view.dart';

import '../support/fake_browser_engine.dart';
import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;
late Map<int, FakeBrowserEngine> engines;
final contentFocus = FocusNode(debugLabel: 'content');

Future<int> pump(WidgetTester tester, {List<int> ports = const [8000]}) async {
  local = FakeLocalSessions();
  local.add(local.summary(1, ports: ports));
  engines = {};
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('vi'))),
      browserEngineFactoryProvider.overrideWithValue((id) => engines[id] = FakeBrowserEngine()),
    ],
  );
  container.read(browserRegistryProvider);
  final id = container.read(terminalTabsProvider.notifier).openBrowser();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BrowserPaneView(paneId: id, focused: true, contentFocus: contentFocus),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return id;
}

void main() {
  testWidgets('toolbar: address, origin mark, disabled history buttons (UI-A6 §2.1)', (tester) async {
    final id = await pump(tester);
    expect(find.byKey(const Key('browser.toolbar')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('browser.toolbar'))).height, 32);
    final field = tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('browser.address')), matching: find.byType(EditableText)));
    expect(field.controller.text, 'localhost:8000/'); // local → no scheme
    expect(find.bySemanticsLabel('Trang trên máy này'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('browser.back'))).hasFlag(SemanticsFlag.isEnabled), isFalse);
    engines[id]!.emit(const HistoryChanged(canGoBack: true, canGoForward: false));
    await tester.pump();
    expect(tester.getSemantics(find.byKey(const Key('browser.back'))).hasFlag(SemanticsFlag.isEnabled), isTrue);
  });

  testWidgets('address field: Enter navigates, invalid text is refused (D9)', (tester) async {
    final id = await pump(tester);
    await tester.tap(find.byKey(const Key('browser.address')));
    await tester.enterText(find.byKey(const Key('browser.address')), 'hello world');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(engines[id]!.loads.length, 1); // only the initial load
    expect(find.byTooltip('Không phải địa chỉ web'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('browser.address')), '3000');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(engines[id]!.loads.last.toString(), 'http://localhost:3000/');
    expect(contentFocus.hasFocus, isTrue);
  });

  testWidgets('Esc in the address field reverts and returns to the page', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('browser.address')));
    await tester.enterText(find.byKey(const Key('browser.address')), 'abc');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final field = tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('browser.address')), matching: find.byType(EditableText)));
    expect(field.controller.text, 'localhost:8000/');
    expect(contentFocus.hasFocus, isTrue);
  });

  testWidgets('reload becomes stop while loading; progress bar; Esc stops only while loading (D13, D15)', (tester) async {
    final id = await pump(tester);
    engines[id]!.emit(const LoadStarted());
    engines[id]!.emit(const LoadProgress(45));
    await tester.pump();
    expect(find.byTooltip('Dừng  Esc'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('browser.progress'))).width, closeTo(800 * 0.45, 1));
    contentFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(engines[id]!.calls, contains('stop'));
    engines[id]!.emit(const LoadFinished());
    await tester.pump();
    engines[id]!.calls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(engines[id]!.calls, isNot(contains('stop')));
  });

  testWidgets('forwarded chords: Esc listed only while loading; ⌘L from the page focuses the address (D15)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final id = await pump(tester);
    expect(engines[id]!.forwarded, contains('meta+l'));
    expect(engines[id]!.forwarded, isNot(contains('escape')));
    engines[id]!.emit(const LoadStarted());
    await tester.pump();
    expect(engines[id]!.forwarded, contains('escape'));
    engines[id]!.emit(const ShortcutForwarded('meta+l'));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'browser.address');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('error page with retry; insecure mark; agent mark (D14, D25, UI-A6 §2.2)', (tester) async {
    final id = await pump(tester);
    engines[id]!.emit(const LoadFailed(BrowserLoadErrorKind.refused));
    await tester.pump();
    expect(find.text('Chưa có gì chạy ở localhost:8000'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    expect(engines[id]!.calls, contains('reload'));
    engines[id]!.emit(UrlChanged(Uri.parse('http://example.com/')));
    await tester.pump();
    expect(find.text('Không bảo mật'), findsOneWidget);
    container.read(browserRegistryProvider.notifier).existing(id)!.agentCommand();
    await tester.pump();
    expect(find.byKey(const Key('browser.agent')), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(find.byKey(const Key('browser.agent')), findsNothing);
  });

  testWidgets('focusing the content gives the engine the keyboard; leaving releases it (D16)', (tester) async {
    final id = await pump(tester);
    contentFocus.requestFocus();
    await tester.pump();
    expect(engines[id]!.calls, contains('focus'));
    contentFocus.unfocus();
    await tester.pump();
    expect(engines[id]!.calls, contains('release'));
  });
}
```

Create `apps/desktop/test/ui/browser_entry_points_test.dart` — pump the real `TerminalWorkspacePage` the way A3's `pane_shortcuts_test.dart` does (same harness, same overrides) plus `browserEngineFactoryProvider` with `FakeBrowserEngine`s, then:

```dart
  testWidgets('⌘⇧B opens a browser pane right of the focused terminal (D7)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpWorkspace(tester, sessions: [summary(1, ports: [3000])]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(BrowserPaneView), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Pane 2 of 2 — Browser: ')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('terminal menu and row menu offer "Open browser pane"', (tester) async {
    await pumpWorkspace(tester, sessions: [summary(1)]);
    await openTerminalMenu(tester);
    expect(find.text('Open browser pane'), findsOneWidget);
    await openRowMenu(tester, tabId: 1);
    expect(find.text('Open browser pane'), findsOneWidget);
  });

  testWidgets('⌥-click on a port opens it in a pane; again focuses that pane (D8)', (tester) async {
    await pumpWorkspace(tester, sessions: [summary(1, ports: [8000])]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tap(find.text(':8000'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowserPaneView), findsOneWidget);
    expect(urlOpener.opened, isEmpty); // not the system browser
    await tester.tap(find.text(':8000'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(BrowserPaneView), findsOneWidget); // reused
    await tester.tap(find.text(':8000')); // plain click: A2 unchanged
    expect(urlOpener.openedPorts, [8000]);
  });

  testWidgets('row menu "Open :8000 in a browser pane" (keyboard alternative, D8)', (tester) async {
    await pumpWorkspace(tester, sessions: [summary(1, ports: [8000])]);
    await openRowMenu(tester, tabId: 1);
    await tester.tap(find.text('Open :8000 in a browser pane'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowserPaneView), findsOneWidget);
  });

  testWidgets('Ctrl+F6 from the page → browser toolbar → sidebar (D16)', (tester) async {
    await pumpWorkspace(tester, sessions: [summary(1)]);
    container.read(terminalTabsProvider.notifier).openBrowser(url: Uri.parse('http://localhost:1/'));
    await tester.pumpAndSettle();
    await sendCtrlF6(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'browser.address');
    await sendCtrlF6(tester);
    expect(isSidebarFocused(), isTrue);
  });

  testWidgets('scheme/download notices become neutral toasts (D10)', (tester) async {
    await pumpWorkspace(tester, sessions: [summary(1)]);
    final id = container.read(terminalTabsProvider.notifier).openBrowser(url: Uri.parse('http://localhost:1/'));
    await tester.pumpAndSettle();
    engines[id]!.emit(const NavigationBlocked());
    await tester.pump();
    expect(find.text('The browser pane only opens http and https pages'), findsOneWidget);
  });
```

(`pumpWorkspace`, `summary`, `openTerminalMenu`, `openRowMenu`, `sendCtrlF6`, `isSidebarFocused`, `urlOpener` come from A3's pane UI test harness; if they are private to `pane_shortcuts_test.dart`, move them into `test/support/workspace_harness.dart` in this step and import them from both files. `FakeUrlOpener` gains `openedPages`/`openedPorts` lists.)

Add to `apps/desktop/test/platform/url_opener_test.dart`:

```dart
  test('openWebPage: http/https with a host only (W2)', () async {
    final runs = <List<String>>[];
    final opener = SystemUrlOpener(
      isWindows: false,
      run: (exe, args) async {
        runs.add([exe, ...args]);
        return ProcessResult(0, 0, '', '');
      },
    );
    await opener.openWebPage(Uri.parse('http://localhost:3000/docs?a=1'));
    await opener.openWebPage(Uri.parse('https://example.com/'));
    expect(runs, [
      ['/usr/bin/open', 'http://localhost:3000/docs?a=1'],
      ['/usr/bin/open', 'https://example.com/'],
    ]);
    for (final bad in ['file:///etc/passwd', 'javascript:alert(1)', 'http:///x', r'\\server\share']) {
      expect(() => opener.openWebPage(Uri.parse(bad)), throwsArgumentError);
    }
    expect(runs.length, 2);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/browser_pane_view_test.dart test/ui/browser_entry_points_test.dart test/platform/url_opener_test.dart`
Expected: FAIL — `BrowserPaneView`, `openWebPage`… undefined.

- [ ] **Step 3: `openWebPage` and the dialog queue**

In `url_opener.dart` add to the interface `Future<void> openWebPage(Uri uri);` and to `SystemUrlOpener`:

```dart
  /// A6 W2 "Mở trong trình duyệt hệ thống": the browser pane's page. Only
  /// absolute http/https URLs with a host — never file:, UNC or anything
  /// `open`/`FileProtocolHandler` would run.
  @override
  Future<void> openWebPage(Uri uri) async {
    final scheme = uri.scheme.toLowerCase();
    if (!uri.isAbsolute ||
        (scheme != 'http' && scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(uri.scheme, 'uri', 'Only web pages open');
    }
    final url = uri.toString();
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await _run('/usr/bin/open', [url]);
    }
  }
```

Implement it in every fake opener (`test/support/fakes.dart`: record into `openedPages`).

Create `apps/desktop/lib/src/browser/browser_dialogs.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engines/wk_webview_engine.dart' show BrowserJsDialog;

/// D32: page alert/confirm/prompt, one at a time, shown by the workspace
/// page as an A1 dialog. The engine waits on [present].
final class BrowserDialogQueue extends ChangeNotifier {
  final List<(BrowserJsDialog, Completer<Object?>)> _queue = [];

  BrowserJsDialog? get current => _queue.firstOrNull?.$1;

  Future<Object?> present(BrowserJsDialog dialog) {
    final done = Completer<Object?>();
    _queue.add((dialog, done));
    if (_queue.length == 1) notifyListeners();
    return done.future;
  }

  /// null (alert / cancelled prompt), bool (confirm), String (prompt).
  void complete(Object? result) {
    if (_queue.isEmpty) return;
    _queue.removeAt(0).$2.complete(result);
    notifyListeners();
  }
}

final browserDialogsProvider = Provider<BrowserDialogQueue>(
  (ref) => throw StateError('browserDialogsProvider must be overridden'),
);
```

- [ ] **Step 4: `BrowserPaneView`**

Create `apps/desktop/lib/src/ui/terminal/browser_pane_view.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../../browser/browser_controller.dart';
import '../../browser/browser_engine.dart';
import '../../browser/browser_registry.dart';
import '../../browser/browser_url.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';
import 'terminal_shortcuts.dart';

/// A6 D12–D17: one browser pane under its A3 pane header — toolbar (UI-A6
/// §2.1), page, error page (§3). The page view comes from the pane's
/// engine once the registry created it (lazily, D29).
class BrowserPaneView extends ConsumerStatefulWidget {
  const BrowserPaneView({
    super.key,
    required this.paneId,
    required this.focused,
    required this.contentFocus,
    this.addressFocus,
  });

  final int paneId;

  /// The tab is selected and this is its focused pane.
  final bool focused;

  /// A3's pane focus node (region 1 when this pane is focused).
  final FocusNode contentFocus;

  /// Region 1b (D16): the workspace's node for the focused browser pane's
  /// address field; null → the view's own node.
  final FocusNode? addressFocus;

  @override
  ConsumerState<BrowserPaneView> createState() => _BrowserPaneViewState();
}

class _BrowserPaneViewState extends ConsumerState<BrowserPaneView> {
  final TextEditingController _address = TextEditingController();
  late final FocusNode _ownAddressFocus = FocusNode(
    debugLabel: 'browser.address',
    onKeyEvent: _onAddressKey,
  );
  final GlobalKey _contentKey = GlobalKey();
  final List<StreamSubscription<Object?>> _subs = [];
  bool _invalid = false;
  bool? _forwardedLoading;
  bool _contentHadFocus = false;

  FocusNode get _addressFocus => widget.addressFocus ?? _ownAddressFocus;

  BrowserController? get _controller =>
      ref.read(browserRegistryProvider.notifier).existing(widget.paneId);

  @override
  void initState() {
    super.initState();
    final registry = ref.read(browserRegistryProvider.notifier);
    _subs
      ..add(
        registry.shortcuts
            .where((s) => s.paneId == widget.paneId)
            .listen((s) => _onChord(s.chord)),
      )
      ..add(
        registry.contentClicks.where((id) => id == widget.paneId).listen((_) {
          ref.read(terminalTabsProvider.notifier).focusPane(widget.paneId);
          widget.contentFocus.requestFocus();
        }),
      );
    widget.contentFocus.addListener(_contentFocusChanged);
    _addressFocus.addListener(_addressFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _state;
      if (mounted && widget.focused && state?.url == aboutBlank) {
        _addressFocus.requestFocus(); // D7: nothing to show yet → type an address
      }
    });
  }

  @override
  void didUpdateWidget(BrowserPaneView old) {
    super.didUpdateWidget(old);
    if (old.contentFocus != widget.contentFocus) {
      old.contentFocus.removeListener(_contentFocusChanged);
      widget.contentFocus.addListener(_contentFocusChanged);
    }
    if ((old.addressFocus ?? _ownAddressFocus) != _addressFocus) {
      (old.addressFocus ?? _ownAddressFocus).removeListener(_addressFocusChanged);
      _addressFocus.addListener(_addressFocusChanged);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    widget.contentFocus.removeListener(_contentFocusChanged);
    _addressFocus.removeListener(_addressFocusChanged);
    _ownAddressFocus.dispose();
    _address.dispose();
    super.dispose();
  }

  BrowserPaneState? get _state => ref
      .read(terminalTabsProvider)
      .tabOfPane(widget.paneId)
      ?.browsers[widget.paneId];

  // D16: Flutter focus ↔ the engine's keyboard.
  void _contentFocusChanged() {
    final has = widget.contentFocus.hasFocus;
    if (has == _contentHadFocus) return;
    _contentHadFocus = has;
    final c = _controller;
    if (c == null) return;
    unawaited(has ? c.focusContent() : c.releaseFocus());
  }

  void _addressFocusChanged() {
    if (_addressFocus.hasFocus) {
      final state = _state;
      if (state != null) _address.text = state.url == aboutBlank ? '' : state.url.toString();
      _address.selection = TextSelection(baseOffset: 0, extentOffset: _address.text.length);
    }
  }

  KeyEventResult _onAddressKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _invalid = false);
      final state = _state;
      if (state != null) _address.text = displayAddress(state.url);
      widget.contentFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit(String text) {
    final uri = parseAddressInput(text);
    final l10n = AppLocalizations.of(context);
    if (uri == null) {
      setState(() => _invalid = true);
      unawaited(SemanticsService.sendAnnouncement(View.of(context), l10n.browserAddressInvalid, Directionality.of(context)));
      return;
    }
    setState(() => _invalid = false);
    unawaited(_controller?.navigate(uri, byUser: true));
    widget.contentFocus.requestFocus();
  }

  void _onChord(String chord) {
    final intent = intentForForwardedChord(chord, defaultTargetPlatform);
    final context = _contentKey.currentContext;
    if (intent != null && context != null) Actions.maybeInvoke(context, intent);
  }

  void _syncForwarded(BrowserPaneState state) {
    if (_forwardedLoading == state.loading) return;
    _forwardedLoading = state.loading;
    unawaited(
      _controller?.setForwardedChords(
        browserForwardedChords(defaultTargetPlatform, loading: state.loading),
      ),
    );
  }

  void _openExternal(Uri url) =>
      unawaited(ref.read(desktopServicesProvider).urlOpener.openWebPage(url));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(browserRegistryProvider); // rebuild when the engine appears
    final state = ref.watch(
      terminalTabsProvider.select((s) => s.tabOfPane(widget.paneId)?.browsers[widget.paneId]),
    );
    ref.listen(
      terminalTabsProvider.select((s) => s.tabOfPane(widget.paneId)?.browsers[widget.paneId]),
      (before, after) {
        if (before == null || after == null) return;
        if (before.loading && !after.loading && after.error == null && after.userNavigation) {
          unawaited(SemanticsService.sendAnnouncement(
            View.of(context),
            l10n.browserAnnounceLoaded(after.title.isEmpty ? after.url.host : after.title),
            Directionality.of(context),
          ));
        }
      },
    );
    if (state == null) return const SizedBox.shrink();
    final controller = _controller;
    if (controller != null) _syncForwarded(state);
    if (!_addressFocus.hasFocus) {
      final shown = displayAddress(state.url);
      if (_address.text != shown) _address.text = shown;
    }
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return Shortcuts(
      shortcuts: browserPaneShortcuts(defaultTargetPlatform),
      child: Actions(
        actions: {
          BrowserFocusAddressIntent: CallbackAction<BrowserFocusAddressIntent>(
            onInvoke: (_) => _addressFocus.requestFocus(),
          ),
          BrowserReloadIntent: _BrowserAction<BrowserReloadIntent>(
            controller != null,
            () => controller?.reload(byUser: true),
          ),
          BrowserBackIntent: _BrowserAction<BrowserBackIntent>(
            state.canGoBack,
            () => controller?.back(byUser: true),
          ),
          BrowserForwardIntent: _BrowserAction<BrowserForwardIntent>(
            state.canGoForward,
            () => controller?.forward(byUser: true),
          ),
          // D15: disabled when idle, so Esc reaches the page.
          BrowserStopIntent: _BrowserAction<BrowserStopIntent>(
            state.loading,
            () => controller?.stop(),
          ),
        },
        child: Column(
          children: [
            _Toolbar(
              state: state,
              mac: mac,
              address: _address,
              addressFocus: _addressFocus,
              invalid: _invalid,
              onSubmit: _submit,
              onBack: state.canGoBack ? () => controller?.back(byUser: true) : null,
              onForward: state.canGoForward ? () => controller?.forward(byUser: true) : null,
              onReloadOrStop: () => state.loading ? controller?.stop() : controller?.reload(byUser: true),
              onExternal: isNavigable(state.url) && state.url != aboutBlank ? () => _openExternal(state.url) : null,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Focus(
                      key: _contentKey,
                      focusNode: widget.contentFocus,
                      child: controller?.buildView() ??
                          const ColoredBox(color: ShellxDesktopColors.bgTerminal),
                    ),
                  ),
                  if (state.error case final kind?)
                    Positioned.fill(
                      child: BrowserErrorView(
                        key: const Key('browser.error'),
                        kind: kind,
                        url: state.url,
                        onRetry: () => controller?.reload(byUser: true),
                        onOpenExternal: () => _openExternal(state.url),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _BrowserAction<T extends Intent> extends Action<T> {
  _BrowserAction(this._enabled, this._run);
  final bool _enabled;
  final VoidCallback _run;
  @override
  bool isEnabled(T intent) => _enabled;
  @override
  Object? invoke(T intent) {
    _run();
    return null;
  }
}
```

Then, in the same file, the toolbar, the error page and the header content, built **exactly** to UI-A6 §1–§3 (every size from `ShellxSizes.browser*`, colours from `ShellxDesktopColors`, strings from §7):

```dart
/// UI-A6 §2.1: |6| ‹ |2| › |2| ⟳/✕ |6| address |6| [Agent] |6| ↗ |6|, 32 high.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.mac,
    required this.address,
    required this.addressFocus,
    required this.invalid,
    required this.onSubmit,
    required this.onBack,
    required this.onForward,
    required this.onReloadOrStop,
    required this.onExternal,
  });

  final BrowserPaneState state;
  final bool mac;
  final TextEditingController address;
  final FocusNode addressFocus;
  final bool invalid;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onReloadOrStop;
  final VoidCallback? onExternal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final height = [ShellxSizes.browserToolbar, textScaler.scale(16) + 16]
        .reduce((a, b) => a > b ? a : b);
    Widget button(Key key, IconData icon, String label, String tooltip, VoidCallback? onPressed) =>
        Semantics(
          key: key,
          button: true,
          enabled: onPressed != null,
          label: label,
          excludeSemantics: true,
          child: ShellxIconButton(
            icon: icon,
            semanticLabel: label,
            tooltip: TextSpan(text: tooltip),
            onPressed: onPressed ?? () {},
            color: onPressed == null ? ShellxDesktopColors.dim : ShellxDesktopColors.textSecondary,
            hitSize: ShellxSizes.browserButton,
          ),
        );
    final origin = state.origin;
    return Semantics(
      container: true,
      label: l10n.browserToolbarRegionLabel,
      child: Container(
        key: const Key('browser.toolbar'),
        height: height,
        color: ShellxDesktopColors.bgSidebar,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ShellxSizes.browserToolbarPadH),
              child: Row(
                children: [
                  button(const Key('browser.back'), Icons.arrow_back, l10n.browserBack('').trim(),
                      l10n.browserBack(mac ? '⌘[' : 'Alt+←'), onBack),
                  const SizedBox(width: ShellxSizes.browserButtonGap),
                  button(const Key('browser.forward'), Icons.arrow_forward, l10n.browserForward('').trim(),
                      l10n.browserForward(mac ? '⌘]' : 'Alt+→'), onForward),
                  const SizedBox(width: ShellxSizes.browserButtonGap),
                  state.loading
                      ? button(const Key('browser.reload'), Icons.close, l10n.browserStop.split('  ').first,
                          l10n.browserStop, onReloadOrStop)
                      : button(const Key('browser.reload'), Icons.refresh, l10n.browserReload('').trim(),
                          l10n.browserReload(mac ? '⌘R' : 'F5'), onReloadOrStop),
                  const SizedBox(width: ShellxSizes.browserToolbarPadH),
                  Expanded(
                    child: _AddressField(
                      controller: address,
                      focusNode: addressFocus,
                      origin: origin,
                      invalid: invalid,
                      onSubmit: onSubmit,
                    ),
                  ),
                  if (state.agentActive) ...[
                    const SizedBox(width: ShellxSizes.browserToolbarPadH),
                    const _AgentMark(key: Key('browser.agent')),
                  ],
                  const SizedBox(width: ShellxSizes.browserToolbarPadH),
                  button(const Key('browser.external'), Icons.open_in_new, l10n.browserOpenExternal,
                      l10n.browserOpenExternal, onExternal),
                ],
              ),
            ),
            if (state.loading)
              Positioned(
                left: 0,
                bottom: 0,
                child: _ProgressBar(progress: state.progress, width: box.maxWidth),
              ),
          ],
          ),
        ),
      ),
    );
  }
}
```

`_AddressField` (24 high, `r6`, `surfaceInset` fill, 1 px `line` border → `accent` + `primarySoft` 2 px halo on focus → `err` when `invalid`; `|8| origin mark 14 |6| text |8|`; `TextField` with `key: const Key('browser.address')`, `textInputAction: TextInputAction.go`, `onSubmitted: onSubmit`, `style: body`, hint `browserAddressHint` in `textPlaceholder`, `Semantics(textField: true, label: browserAddressLabel)`; while `invalid` wrap it in `Tooltip(message: l10n.browserAddressInvalid)` shown at once and hidden after 3 s), the origin mark (`Key('browser.origin')`; UI-A6 §2.2 table: `computer_outlined` / `lock_outline` `textSecondary`, `warning_amber_rounded` `warn` + `caption` w600 `browserOriginInsecure`; each in `Semantics(label: …)`), `_AgentMark` (UI-A6 §2.1: `smart_toy_outlined` 14 + "Agent" `caption` w600 `warn` on `warnBg`, `warnBorder` 1 px, `rPill`, height 20, `Tooltip(browserAgentMarkTooltip)`), and `_ProgressBar({required int? progress, required double width})` (`Key('browser.progress')`, height 2, colour `accent`, width = `width × progress / 100`, or 30 % of `width` when `progress == null` (Windows, D13); `AnimatedContainer` with the A1 `fast` duration (80 ms) unless `MediaQuery.disableAnimationsOf(context)`; wrapped in `Semantics(label: browserLoadingLabel, value: progress == null ? null : '$progress %')`) follow those specs. Run `dart format` after pasting — the toolbar's `LayoutBuilder` nesting above is indented loosely.

`BrowserErrorView({super.key, required BrowserLoadErrorKind kind, required Uri url, required VoidCallback onRetry, required VoidCallback onOpenExternal})`: `bgTerminal` fill; centred column, max width `browserErrorMaxWidth`, padding 24; title (`textTitle`, title style, `Semantics(liveRegion: true)`), 8, body (`textSecondary`, body, centred), 24, buttons in A1 platform order (`ShellxPrimaryButton(browserErrorRetry)` + secondary `browserOpenExternal`). Copy per UI-A6 §3: `refused` with `isLocalHost(url.host)` → `browserErrorLocalRefusedTitle(host)` / `…Body` where `host` = `url.host` plus `:port` when `url.hasPort`; `refused`/`unreachable` → `browserErrorUnreachableTitle/Body`; `dns` → `browserErrorDnsTitle/Body`; `timeout` → `browserErrorTimeoutTitle` + `browserErrorUnreachableBody`; `certificate` → `browserErrorCertTitle/Body` and **no** retry button (only "Mở trong trình duyệt hệ thống"); `crashed` → `browserErrorCrashedTitle/Body`, primary label `browserReload('')`.trim(); `unavailable` → `browserErrorRuntimeTitle/Body`, single primary `browserErrorRuntimeAction` that calls `urlOpener.openWebPage(Uri.parse('https://developer.microsoft.com/microsoft-edge/webview2/'))`; `other` → `browserErrorGenericTitle` + `browserErrorUnreachableBody`.

`BrowserPaneHeaderContent({required BrowserPaneState state, required bool focused})`: `Icons.public` 12 in a 12 box (`accent` while `state.loading`, else `textPrimary` focused / `textSecondary` not), 6, title = `state.title` → `state.url.host` → `browserUntitled` (`small`, one line, ellipsis); title updates throttled to ≤ 4/s with a `Timer` (UI-A6 §2.5).

- [ ] **Step 5: Wire into the pane tree, the workspace page, the sidebar and `main.dart`**

`pane_tree_view.dart` (A3):
- The leaf builder: `isBrowserPaneId(id)` → `BrowserPaneView(paneId: id, focused: selected && id == tab.focusedPaneId, contentFocus: <the node A3 gives the focused pane, else a per-pane node>, addressFocus: <the workspace's browserAddressFocus for the focused pane only>)`; terminal leaves unchanged.
- The pane header: refactor A3's header so its leading dot + title come from a `Widget leading`/`Widget title` pair; for browser leaves pass `BrowserPaneHeaderContent` and no phone/eye/unread marks (UI-A6 §2.5). × / middle-click / double-click behave as A3 (close → `closePane(id)`, which handles negative ids).
- Semantics label for browser leaves: `browserPaneRegionLabel(index, count, title)` instead of `paneRegionLabel`.
- Divider clamp and A3 `PaneMetrics`: the minimum of a browser leaf is `kBrowserMinSize` (UI-A6 §1.2) wherever A3 uses `minPane` for a leaf.
- A pointer-down on a browser leaf's toolbar calls `focusPane(id)` (A3's `Listener`); on the page itself the engine's `ContentClicked` does it (macOS clicks never reach Flutter).

`terminal_workspace_page.dart`:
- Actions: `OpenBrowserPaneIntent` → `try { tabs.openBrowser(); } on BrowserError { /* notice already shown */ }`.
- `final FocusNode _browserAddressFocus = FocusNode(debugLabel: 'browser.address')` passed down; the region cycle (A1 §3.6, `NextRegionIntent`/`PreviousRegionIntent`) becomes `[pane focus, if focused pane is a browser: _browserAddressFocus, sidebar, strip]` (UI-A6 §6).
- Listen to `browserRegistryProvider.notifier.notices`: `schemeBlocked` → `tabs.showNotice(const BrowserSchemeBlockedNotice())`, `downloadBlocked` → `BrowserDownloadBlockedNotice()`, `agentStarted` → `SemanticsService.sendAnnouncement(…, l10n.browserAnnounceAgent, …)`.
- Listen to `browserDialogsProvider` (a `ChangeNotifier`): while `current != null` show the A1 short confirm dialog in the page's dialog overlay — title `browserDialogTitle(host)`, body = message (selectable, ≤ 2 000 characters shown), alert: one "OK" primary; confirm: Hủy + OK; prompt: a text field (A1 §3.4) prefilled with `defaultText` + Hủy/OK — then `complete(null | true/false | text)`.
- Terminal menu (A3 D21 / UI-A6 §4.2): add "Mở pane trình duyệt ⌘⇧B" (`l10n.browserOpenPane`) after "Chia xuống dưới".

`terminal_overlays.dart` `NoticeToast`: text cases `BrowserLimitNotice(:final max) => l10n.browserLimitReached(max)`, `BrowserSchemeBlockedNotice() => l10n.browserSchemeBlocked`, `BrowserDownloadBlockedNotice() => l10n.browserDownloadBlocked`; all three in the neutral list.

`session_tab_row.dart` / `session_sidebar.dart`:
- `SessionTabRow` gains `final void Function(int port)? onOpenPortInPane;`; the port link's tap reads `HardwareKeyboard.instance.isAltPressed` → `onOpenPortInPane(port)` instead of `onOpen(port)`; the port tooltip gets the second line `browserPortAltClickHint(mac ? '⌥' : 'Alt')`.
- `session_sidebar.dart` `_openPortInPane(int tabId, int port)`:

```dart
  /// A6 D8: ⌥-click / row menu — reuse a browser pane of this tab already
  /// on that local port, else split one right of the focused pane.
  void _openPortInPane(int tabId, int port) {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final tab = ref.read(terminalTabsProvider).tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null) return;
    for (final MapEntry(key: id, value: b) in tab.browsers.entries) {
      if (isLocalHost(b.url.host) && b.url.port == port) {
        tabs.focusPane(id);
        return;
      }
    }
    tabs.select(tabId);
    try {
      tabs.openBrowser(tabId: tabId, url: Uri.parse('http://localhost:$port/'));
    } on BrowserError {
      // The notice is already on screen.
    }
  }
```

- Row menu (UI-A6 §4.3): "Mở pane trình duyệt" after "Chia xuống dưới" (selects the tab, then `openBrowser(tabId:)`); next to each A2 port item, `browserOpenPortInPane(port)` (one or two ports), or the `browserOpenPortInPaneMenu` submenu from three ports (up to five smallest), each calling `_openPortInPane`.
- Row semantics custom actions: add "Mở pane trình duyệt".

`main.dart` (after the settings store and the app-support directory exist, before `runApp`):

```dart
  final bootstrap = await rootBundle.loadString('assets/browser/browser_bootstrap.js');
  final macNative = Platform.isMacOS ? BrowserNativeMac() : null;
  final dialogs = BrowserDialogQueue();
  final profile = BrowserProfile(
    isWindows: Platform.isWindows,
    keepData: () => settings.getBool(SettingKeys.browserKeepData, defaultValue: false),
    localAppData: Platform.environment['LOCALAPPDATA'],
    clearer: macNative,
  );
  final shots = ShotsDir(
    Platform.isWindows
        ? '${Platform.environment['LOCALAPPDATA']}\\ShellX\\browser\\shots'
        : '${appSupport.path}/browser/shots',
    isWindows: Platform.isWindows,
  );
  unawaited(shots.sweep(all: true));
  if (Platform.isMacOS) unawaited(profile.prepare()); // D26: also covers a crash
  BrowserEngine engineFor(int paneId) => Platform.isMacOS
      ? WkWebViewEngine(native: macNative!, bootstrap: bootstrap, dialogs: dialogs.present)
      : WebView2Engine(environmentReady: initWebView2Environment(profile), bootstrap: bootstrap);
```

and add to the `ProviderScope` overrides: `browserEngineFactoryProvider.overrideWithValue(engineFor)`, `browserProfileProvider.overrideWithValue(profile)`, `shotsDirProvider.overrideWithValue(shots)`, `browserDialogsProvider.overrideWithValue(dialogs)`. In the quit path (A5a `flushAll(clean: true)` → before `exit`): `await profile.onQuit(); await shots.sweep(all: true);` (each wrapped in a 1 s `timeout` so quitting never hangs).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/browser_pane_view_test.dart test/ui/browser_entry_points_test.dart test/platform/url_opener_test.dart && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`
Expected: PASS, including every A3 pane test (a tab without browser panes is unchanged).

- [ ] **Step 7: ⚠ MANUAL — the whole feature on macOS and Windows**

Spec §1 criteria 1–6, 9 and 12 on both platforms (Windows criterion 12: Narrator limitation recorded, not fixed). Also: a Flutter menu, toast, the A4 notifications panel and a dialog draw above the page; dragging an A3 divider next to a browser pane resizes the page live; zoom/unzoom keeps the page loaded (no reload); 150 % scaling on Windows. Record `Task 9: …` in the ledger.

- [ ] **Step 8: Format, analyze, commit**

```bash
~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed apps/desktop/lib apps/desktop/test
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/ui/terminal/browser_pane_view.dart apps/desktop/lib/src/browser/browser_dialogs.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/lib/src/platform/url_opener.dart apps/desktop/lib/main.dart apps/desktop/test/ui/browser_pane_view_test.dart apps/desktop/test/ui/browser_entry_points_test.dart apps/desktop/test/platform/url_opener_test.dart apps/desktop/test/support docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "feat(desktop): browser pane UI — toolbar, address field, error page, focus regions, ⌘⇧B, menus, ⌥-click ports (A6 D7, D8, D12-D17, D25, D32)"
```

---

### Task 10: A7 command shapes, restore, privacy, HANDOFF §16, full verification (D24, D29, D33, D35, D38)

**Files:**
- Create: `apps/desktop/lib/src/browser/browser_commands.dart`, `apps/desktop/lib/src/browser/browser_host.dart`
- Modify (A5a): `apps/desktop/lib/src/restore/restore_snapshot.dart`, `restore_persistence.dart`, `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`restore`)
- Modify: `release/windows/shellx.iss`, `release/tests/inno.test.mjs`, `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `HANDOFF.md`, `docs/superpowers/ledgers/a1-desktop-terminal.md`
- Test: `apps/desktop/test/browser/browser_commands_test.dart`, `apps/desktop/test/browser/browser_host_test.dart`, `apps/desktop/test/restore/restore_browser_test.dart`

**Interfaces:**
- Consumes: Tasks 2–9; A5a `SavedPaneNode`, `SavedPane`, `SavedSplit`, `SavedTab`, `RestoreSnapshot.tryParse/encode/fromState`, `RestorePlan`, `TerminalTabs.restore`, `RestorePersistence` key map.
- Produces:
  - `browser_commands.dart`: `enum BrowserSplit { right, down }`, `BrowserPaneRef {pane, tab, state}`, `abstract interface class BrowserHost`, `BrowserCommandHandler(BrowserHost).handle(Map<String, Object?>) → Future<Map<String, Object?>>`, `({int width, int height})? pngSize(Uint8List)`.
  - `browser_host.dart`: `final class AppBrowserHost implements BrowserHost { AppBrowserHost(Ref ref); }`; `final browserCommandHandlerProvider = Provider<BrowserCommandHandler>` — **not** connected to any IPC (A7 registers it for `ui.browser.*`).
  - A5a: `final class SavedBrowser extends SavedPaneNode { const SavedBrowser({required String key, String? url}); }`; JSON leaf `{"browser": key, "url": url|null}`.
  - `TerminalTabs.openBrowserRestored({required int tabId, required Uri url}) → int` (used only by `restore`; no notice, no focus change, no registry load until the tab is shown).

- [ ] **Step 1: Write the failing command handler test**

(It pins the default timeouts: a request without `timeoutMs` must use the controller's 10 s eval / 15 s wait defaults, not the caps.)

Create `apps/desktop/test/browser/browser_commands_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_desktop/src/browser/browser_commands.dart';
import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import '../support/fake_browser_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeHost implements BrowserHost {
  final Map<int, BrowserController> controllers = {};
  final Map<int, FakeBrowserEngine> engines = {};
  final List<String> calls = [];
  BrowserError? openError;
  int _next = -1;
  bool anyOrigin = false;

  BrowserController add(String url, {int? id}) {
    final pane = id ?? _next--;
    final engine = FakeBrowserEngine();
    engines[pane] = engine;
    return controllers[pane] = BrowserController(
      paneId: pane,
      engine: engine,
      initialUrl: Uri.parse(url),
      allowAnyOrigin: () => anyOrigin,
      onState: (_) {},
      nonce: () => 'n',
    );
  }

  @override
  List<BrowserPaneRef> panes() => [
    for (final e in controllers.entries)
      BrowserPaneRef(pane: e.key, tab: 7, state: e.value.state),
  ];

  @override
  BrowserController? controller(int pane) => controllers[pane];

  @override
  ({int pane, int tab}) open({
    required Uri url,
    int? tab,
    int? target,
    required BrowserSplit split,
    required bool focus,
  }) {
    if (openError != null) throw openError!;
    calls.add('open $url tab=$tab target=$target ${split.name} focus=$focus');
    final c = add(url.toString());
    return (pane: c.paneId, tab: tab ?? 7);
  }

  @override
  void close(int pane) {
    calls.add('close $pane');
    controllers.remove(pane);
  }

  @override
  Future<String> saveShot(Uint8List png) async => '/shots/abc.png';
}

late FakeHost host;
late BrowserCommandHandler handler;

Future<Map<String, Object?>> call(Map<String, Object?> r) => handler.handle(r);

Uint8List png(int w, int h) {
  final b = ByteData(24);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(16, w);
  b.setUint32(20, h);
  return b.buffer.asUint8List();
}

void main() {
  setUp(() {
    host = FakeHost();
    handler = BrowserCommandHandler(host);
  });

  test('list', () async {
    host.add('http://localhost:8000/', id: -1);
    final r = await call({'t': 'ui.browser.list', 'q': 1});
    expect(r, {
      't': 'result',
      'q': 1,
      'panes': [
        {
          'pane': -1,
          'tab': 7,
          'url': 'http://localhost:8000/',
          'title': '',
          'loading': false,
          'origin': 'local',
        },
      ],
    });
  });

  test(
    'open: defaults right, no focus; parses the URL like the address field',
    () async {
      final r = await call({'t': 'ui.browser.open', 'url': '3000'});
      expect(r['pane'], -1);
      expect(
        host.calls.single,
        'open http://localhost:3000/ tab=null target=null right focus=false',
      );
      expect(host.controllers[-1]!.state.agentActive, isTrue);
      expect(
        (await call({
          't': 'ui.browser.open',
          'url': 'javascript:alert(1)',
        }))['code'],
        'bad_request',
      );
      expect(
        (await call({
          't': 'ui.browser.open',
          'url': 'x.com',
          'direction': 'up',
        }))['code'],
        'bad_request',
      );
      host.openError = const BrowserError('browser_limit');
      expect(
        (await call({'t': 'ui.browser.open', 'url': '3000'}))['code'],
        'browser_limit',
      );
    },
  );

  test('navigate waits for load by default', () async {
    final c = host.add('http://localhost:8000/', id: -1);
    final engine = host.engines[-1]!;
    final pending = call({
      't': 'ui.browser.navigate',
      'pane': -1,
      'url': 'localhost:8000/docs',
      'q': 'a',
    });
    await Future<void>.delayed(Duration.zero);
    engine.emit(const LoadStarted());
    engine.emit(const TitleChanged('Docs'));
    engine.emit(const LoadFinished());
    expect(await pending, {
      't': 'result',
      'q': 'a',
      'url': 'http://localhost:8000/docs',
      'title': 'Docs',
    });
    expect(c.state.agentActive, isTrue);
  });

  test('eval returns JSON text; errors carry codes', () async {
    host.add('http://localhost:8000/', id: -1);
    final engine = host.engines[-1]!;
    final pending = call({
      't': 'ui.browser.eval',
      'pane': -1,
      'script': 'return {a: [1]};',
    });
    await Future<void>.delayed(Duration.zero);
    engine.emit(
      BridgeReceived(
        jsonEncode({'t': 'eval', 'n': 'n', 'ok': true, 'json': '{"a":[1]}'}),
      ),
    );
    expect((await pending)['json'], '{"a":[1]}');
    expect(
      (await call({'t': 'ui.browser.eval', 'pane': -1}))['code'],
      'bad_request',
    );
    expect(
      (await call({
        't': 'ui.browser.eval',
        'pane': -9,
        'script': 'return 1',
      }))['code'],
      'not_found',
    );
    host.add('https://example.com/', id: -2);
    expect(
      (await call({
        't': 'ui.browser.eval',
        'pane': -2,
        'script': 'return 1',
      }))['code'],
      'forbidden_origin',
    );
  });

  test('screenshot returns path and PNG size', () async {
    host.add('http://localhost:8000/', id: -1);
    host.engines[-1]!.png = png(1280, 800);
    expect(await call({'t': 'ui.browser.screenshot', 'pane': -1}), {
      't': 'result',
      'path': '/shots/abc.png',
      'width': 1280,
      'height': 800,
      'bytes': 24,
    });
  });

  test('console and network pages carry next and partial', () async {
    host.add('http://localhost:8000/', id: -1);
    final engine = host.engines[-1]!;
    engine.emit(
      BridgeReceived(
        jsonEncode({'t': 'console', 'level': 'log', 'text': 'xin chào'}),
      ),
    );
    engine.emit(
      BridgeReceived(
        jsonEncode({
          't': 'net',
          'url': 'http://localhost:8000/a',
          'type': 'fetch',
          'status': 404,
        }),
      ),
    );
    final c = await call({'t': 'ui.browser.console', 'pane': -1});
    expect((c['entries'] as List).single, containsPair('text', 'xin chào'));
    expect(c['next'], 1);
    final n = await call({'t': 'ui.browser.network', 'pane': -1, 'since': 1});
    expect((n['entries'] as List).single, containsPair('status', 404));
    expect(n['partial'], isTrue);
    expect(
      (await call({
        't': 'ui.browser.console',
        'pane': -1,
        'limit': 'x',
      }))['code'],
      'bad_request',
    );
  });

  test('close, unknown type', () async {
    host.add('http://localhost:8000/', id: -1);
    expect(await call({'t': 'ui.browser.close', 'pane': -1}), {'t': 'result'});
    expect(host.calls, ['close -1']);
    expect(
      (await call({'t': 'ui.browser.close', 'pane': -1}))['code'],
      'not_found',
    );
    expect((await call({'t': 'ui.browser.fly'}))['code'], 'unknown_type');
  });

  test('eval without timeoutMs uses the 10 s default, not the 30 s cap', () {
    fakeAsync((async) {
      host.add('http://localhost:8000/', id: -1);
      Map<String, Object?>? r;
      call({
        't': 'ui.browser.eval',
        'pane': -1,
        'script': 'return 1;',
      }).then((v) => r = v);
      async.elapse(const Duration(seconds: 11));
      expect(r?['code'], 'timeout');
      expect(
        (call({
          't': 'ui.browser.eval',
          'pane': -1,
          'script': 'x',
          'timeoutMs': 0,
        })),
        completion(containsPair('code', 'bad_request')),
      );
      async.flushMicrotasks();
    });
  });

  test('pngSize', () {
    expect(pngSize(png(3, 4)), (width: 3, height: 4));
    expect(pngSize(Uint8List(10)), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/browser/browser_commands_test.dart`
Expected: FAIL — `browser_commands.dart` does not exist.

- [ ] **Step 3: Implement the handler**

Create `apps/desktop/lib/src/browser/browser_commands.dart`:

```dart
/// A6 D38, §3.6: the `ui.browser.*` command shapes A7 will expose. A6
/// implements and tests them; A7 only routes A5b `ui.*` frames here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'browser_bridge.dart';
import 'browser_controller.dart';
import 'browser_url.dart';

enum BrowserSplit { right, down }

final class BrowserPaneRef {
  const BrowserPaneRef({
    required this.pane,
    required this.tab,
    required this.state,
  });
  final int pane;
  final int tab;
  final BrowserPaneState state;
}

/// What the handler needs from the app (implemented over `TerminalTabs` +
/// `BrowserRegistry` in Task 10; a fake in tests).
abstract interface class BrowserHost {
  List<BrowserPaneRef> panes();

  /// The pane's controller, creating its engine if the pane was never shown
  /// (D29 lazy load); `null` when there is no such browser pane.
  BrowserController? controller(int pane);

  /// Opens a pane; throws [BrowserError] `not_found` (tab/target),
  /// `browser_limit` (D28) or `no_room` (A3 D4 / D31).
  ({int pane, int tab}) open({
    required Uri url,
    int? tab,
    int? target,
    required BrowserSplit split,
    required bool focus,
  });

  void close(int pane);

  /// D24: writes the PNG to the shots directory, returns its path.
  Future<String> saveShot(Uint8List png);
}

final class BrowserCommandHandler {
  BrowserCommandHandler(this._host);
  final BrowserHost _host;

  /// One A5b-style request `{"t", "q"?, …}` → `{"t": "result", "q", …}` or
  /// `{"t": "error", "q", "code", "message"?}`.
  Future<Map<String, Object?>> handle(Map<String, Object?> request) async {
    final q = request['q'];
    try {
      final result = await _dispatch(request);
      return {'t': 'result', 'q': ?q, ...result};
    } on BrowserError catch (e) {
      return {'t': 'error', 'q': ?q, 'code': e.code, 'message': ?e.message};
    }
  }

  Future<Map<String, Object?>> _dispatch(Map<String, Object?> r) async {
    switch (r['t']) {
      case 'ui.browser.list':
        return {
          'panes': [
            for (final p in _host.panes())
              {
                'pane': p.pane,
                'tab': p.tab,
                'url': p.state.url.toString(),
                'title': p.state.title,
                'loading': p.state.loading,
                'origin': p.state.origin.name,
              },
          ],
        };
      case 'ui.browser.open':
        final url = _url(r);
        final direction = r['direction'] ?? 'right';
        if (direction != 'right' && direction != 'down') throw _bad;
        final opened = _host.open(
          url: url,
          tab: _optInt(r, 'tab'),
          target: _optInt(r, 'target'),
          split: direction == 'down' ? BrowserSplit.down : BrowserSplit.right,
          focus: _optBool(r, 'focus') ?? false,
        );
        _host.controller(opened.pane)?.agentCommand();
        return {'pane': opened.pane, 'tab': opened.tab};
      case 'ui.browser.navigate':
        final c = _pane(r);
        final url = _url(r);
        final wait = r['wait'] ?? 'load';
        if (wait != 'load' && wait != 'none') throw _bad;
        await c.navigate(url);
        if (wait == 'load')
          await c.waitForLoad(timeout: _timeout(r, kWaitTimeout));
        return _page(c);
      case 'ui.browser.back':
        await _pane(r).back();
        return {};
      case 'ui.browser.forward':
        await _pane(r).forward();
        return {};
      case 'ui.browser.reload':
        await _pane(r).reload();
        return {};
      case 'ui.browser.stop':
        await _pane(r).stop();
        return {};
      case 'ui.browser.wait':
        final c = _pane(r);
        await c.waitForLoad(timeout: _timeout(r, kWaitTimeout));
        return _page(c);
      case 'ui.browser.eval':
        final c = _pane(r);
        final script = r['script'];
        if (script is! String || script.length > kEvalScriptMax) throw _bad;
        final value = await c.evalJs(
          script,
          timeout: _timeout(r, kEvalTimeout),
        );
        return {'json': jsonEncode(value)};
      case 'ui.browser.screenshot':
        final png = await _pane(r).screenshot();
        final size = pngSize(png);
        return {
          'path': await _host.saveShot(png),
          'width': size?.width,
          'height': size?.height,
          'bytes': png.length,
        };
      case 'ui.browser.console':
        final c = _pane(r);
        final level = r['level'];
        if (level != null && level is! String) throw _bad;
        final entries = c.console(
          since: _optInt(r, 'since') ?? 0,
          limit: _optInt(r, 'limit') ?? kListLimit,
          level: level as String?,
        );
        return {
          'entries': [
            for (final e in entries)
              {
                'seq': e.seq,
                'ts': e.ts.toUtc().toIso8601String(),
                'level': e.level,
                'text': e.text,
                'url': e.url,
              },
          ],
          'next': entries.isEmpty
              ? (_optInt(r, 'since') ?? 0)
              : entries.last.seq,
        };
      case 'ui.browser.network':
        final c = _pane(r);
        final entries = c.network(
          since: _optInt(r, 'since') ?? 0,
          limit: _optInt(r, 'limit') ?? kListLimit,
        );
        return {
          'entries': [
            for (final e in entries)
              {
                'seq': e.seq,
                'ts': e.ts.toUtc().toIso8601String(),
                'url': e.url,
                'type': e.type,
                'method': ?e.method,
                'status': ?e.status,
                'durationMs': ?e.durationMs,
                'size': ?e.size,
              },
          ],
          'next': entries.isEmpty
              ? (_optInt(r, 'since') ?? 0)
              : entries.last.seq,
          'partial': true,
        };
      case 'ui.browser.close':
        final pane = _int(r, 'pane');
        if (_host.controller(pane) == null) throw _notFound;
        _host.close(pane);
        return {};
    }
    throw const BrowserError('unknown_type');
  }

  static const BrowserError _bad = BrowserError('bad_request');
  static const BrowserError _notFound = BrowserError('not_found');

  BrowserController _pane(Map<String, Object?> r) {
    final c = _host.controller(_int(r, 'pane'));
    if (c == null) throw _notFound;
    c.agentCommand();
    return c;
  }

  static Map<String, Object?> _page(BrowserController c) => {
    'url': c.state.url.toString(),
    'title': c.state.title,
  };

  static Uri _url(Map<String, Object?> r) {
    final text = r['url'];
    if (text is! String) throw _bad;
    final uri = parseAddressInput(text);
    if (uri == null) throw _bad;
    return uri;
  }

  static int _int(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v is! int) throw _bad;
    return v;
  }

  static int? _optInt(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v == null) return null;
    if (v is! int) throw _bad;
    return v;
  }

  static bool? _optBool(Map<String, Object?> r, String key) {
    final v = r[key];
    if (v == null) return null;
    if (v is! bool) throw _bad;
    return v;
  }

  /// `timeoutMs` or [fallback] (the controller's default for that call).
  static Duration _timeout(Map<String, Object?> r, Duration fallback) {
    final ms = _optInt(r, 'timeoutMs');
    if (ms == null) return fallback;
    if (ms <= 0) throw _bad;
    return Duration(milliseconds: ms);
  }
}

/// PNG IHDR width/height, `null` if [png] is not a PNG.
({int width, int height})? pngSize(Uint8List png) {
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (png.length < 24) return null;
  for (var i = 0; i < 8; i++) {
    if (png[i] != sig[i]) return null;
  }
  final data = ByteData.sublistView(png, 16, 24);
  return (width: data.getUint32(0), height: data.getUint32(4));
}
```

- [ ] **Step 4: The app host (not wired to IPC)**

Create `apps/desktop/lib/src/browser/browser_host.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/pane_layout.dart';
import '../terminal/terminal_tabs.dart';
import 'browser_commands.dart';
import 'browser_controller.dart';
import 'browser_registry.dart';
import 'shots_dir.dart';

/// D38: [BrowserHost] over the real tabs and registry. A7 registers
/// [browserCommandHandlerProvider] for the A5b `ui.*` frames it forwards;
/// A6 exposes nothing (D35: only the UI process has browser panes).
final class AppBrowserHost implements BrowserHost {
  AppBrowserHost(this._ref);
  final Ref _ref;

  @override
  List<BrowserPaneRef> panes() => [
    for (final tab in _ref.read(terminalTabsProvider).tabs)
      for (final MapEntry(key: id, value: state) in tab.browsers.entries)
        BrowserPaneRef(pane: id, tab: tab.id, state: state),
  ];

  @override
  BrowserController? controller(int pane) =>
      _ref.read(browserRegistryProvider.notifier).controller(pane);

  @override
  ({int pane, int tab}) open({
    required Uri url,
    int? tab,
    int? target,
    required BrowserSplit split,
    required bool focus,
  }) {
    final tabs = _ref.read(terminalTabsProvider.notifier);
    final id = tabs.openBrowser(
      tabId: tab,
      target: target,
      url: url,
      axis: split == BrowserSplit.down ? SplitAxis.column : SplitAxis.row,
      focus: focus,
      notify: false, // agent calls: errors go back to the agent, no toast
    );
    return (pane: id, tab: _ref.read(terminalTabsProvider).tabOfPane(id)!.id);
  }

  @override
  void close(int pane) =>
      _ref.read(terminalTabsProvider.notifier).closePane(pane);

  @override
  Future<String> saveShot(Uint8List png) => _ref.read(shotsDirProvider).write(png);
}

final browserCommandHandlerProvider = Provider<BrowserCommandHandler>(
  (ref) => BrowserCommandHandler(AppBrowserHost(ref)),
);
```

Create `apps/desktop/test/browser/browser_host_test.dart` — boot the container like `browser_registry_test.dart` (plus `shotsDirProvider.overrideWithValue(ShotsDir(tmp.path, isWindows: false))`), then:

```dart
  test('open → list → eval → close through the real tabs', () async {
    local.add(local.summary(1));
    boot();
    final handler = container.read(browserCommandHandlerProvider);
    final opened = await handler.handle({'t': 'ui.browser.open', 'url': '8000'});
    final pane = opened['pane']! as int;
    expect(pane, isNegative);
    expect(state().tabs.single.focusedPaneId, 1); // agent opens do not take focus
    final list = await handler.handle({'t': 'ui.browser.list'});
    expect((list['panes']! as List).single, containsPair('url', 'http://localhost:8000/'));
    expect(await handler.handle({'t': 'ui.browser.close', 'pane': pane}), {'t': 'result'});
    expect(state().tabs.single.browsers, isEmpty);
  });

  test('limit errors come back to the agent without a toast', () async {
    local.add(local.summary(1));
    boot();
    final handler = container.read(browserCommandHandlerProvider);
    for (var i = 0; i < kMaxBrowserPanes; i++) {
      await handler.handle({'t': 'ui.browser.open', 'url': '8000', 'target': 1});
    }
    final r = await handler.handle({'t': 'ui.browser.open', 'url': '8000'});
    expect(r['code'], 'browser_limit');
    expect(state().notice, isNull);
  });
```

- [ ] **Step 5: Restore — failing test (requires A5a merged; see Prerequisite)**

Create `apps/desktop/test/restore/restore_browser_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

const k1 = '0123456789abcdef0123456789abcdef';
const k2 = 'fedcba9876543210fedcba9876543210';

Map<String, Object?> layout(Object? browserLeaf) => {
  'v': 1,
  'savedAt': '2026-10-07T14:32:05.123Z',
  'cleanExit': true,
  'daemon': null,
  'selectedTab': k1,
  'workspaces': [
    {'id': 'default', 'tabs': [k1]},
  ],
  'tabs': [
    {
      'key': k1,
      'name': null,
      'focused': k2,
      'zoomed': null,
      'layout': {
        'split': 'row',
        'ratio': 0.4,
        'first': {'pane': k1, 'cwd': '/w', 'session': 3},
        'second': browserLeaf,
      },
    },
  ],
};

void main() {
  test('a browser leaf round-trips (D29)', () {
    final snap = RestoreSnapshot.tryParse(
      jsonEncode(layout({'browser': k2, 'url': 'http://localhost:8000/docs'})),
    )!;
    final split = snap.tabs.single.layout as SavedSplit;
    expect(split.axis, SplitAxis.row);
    final leaf = split.second as SavedBrowser;
    expect(leaf.key, k2);
    expect(leaf.url, 'http://localhost:8000/docs');
    expect(RestoreSnapshot.tryParse(snap.encode())!.sameLayoutAs(snap), isTrue);
  });

  test('null url restores as about:blank; bad leaves reject the file (A5a D11)', () {
    expect(RestoreSnapshot.tryParse(jsonEncode(layout({'browser': k2, 'url': null}))), isNotNull);
    for (final bad in [
      {'browser': 'short', 'url': null},
      {'browser': k2, 'url': 'file:///etc/passwd'},
      {'browser': k2, 'url': 'http://localhost/${'x' * 2048}'},
      {'browser': k2, 'url': 42},
    ]) {
      expect(RestoreSnapshot.tryParse(jsonEncode(layout(bad))), isNull, reason: '$bad');
    }
  });

  test('a tab whose leaves are all browsers is invalid (D5)', () {
    final m = layout({'browser': k2, 'url': null});
    final tab = (m['tabs']! as List).single as Map<String, Object?>;
    tab['layout'] = {'browser': k1, 'url': null};
    tab['focused'] = k1;
    expect(RestoreSnapshot.tryParse(jsonEncode(m)), isNull);
  });
}
```

Append to A5a's `apps/desktop/test/terminal/terminal_tabs_restore_test.dart` (its harness, `FakeLocalSessions`, `FakeBrowserEngine` factory override):

```dart
  test('restore rebuilds browser leaves with new negative ids; the page '
      'loads only when its tab is shown (D29)', () async {
    // plan: tab A (selected) = terminal | browser http://localhost:8000/,
    //       tab B = terminal | browser http://localhost:9000/
    final outcome = await tabs().restore(planWithBrowsers());
    expect(outcome.tabsRestored, 2);
    final a = state().tabs.first;
    final b = state().tabs.last;
    expect(a.browsers.values.single.url.toString(), 'http://localhost:8000/');
    expect(b.browsers.keys.single, isNegative);
    await pumpEventQueue();
    expect(engines.values.map((e) => e.loads.single.toString()), ['http://localhost:8000/']);
    tabs().select(b.id);
    await pumpEventQueue();
    expect(engines.length, 2);
    expect(local.openCwds.length, 2); // browser leaves never open sessions
  });
```

(`planWithBrowsers()` builds the `RestorePlan` with `SavedBrowser` leaves the same way the file's other helpers build `SavedPane` plans.)

- [ ] **Step 6: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_browser_test.dart test/terminal/terminal_tabs_restore_test.dart`
Expected: FAIL — `SavedBrowser` undefined.

- [ ] **Step 7: Implement restore**

`restore_snapshot.dart`:

```dart
/// A6 D29: a browser pane — its URL (http/https, no credentials, no
/// fragment, ≤ 2048) or null (about:blank). Never page state.
final class SavedBrowser extends SavedPaneNode {
  const SavedBrowser({required this.key, this.url});
  final String key;
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is SavedBrowser && other.key == key && other.url == url;
  @override
  int get hashCode => Object.hash(key, url);
}
```

- Encoding: `SavedBrowser` → `{'browser': key, 'url': url}`.
- Parsing (inside A5a's leaf parser, before the `pane` branch): a map with `browser` → key must be 32 lower-hex, `url` must be `null` or a `String` for which `urlForRestore(Uri.tryParse(url)) == url` (so `file:`, credentials, fragments and > 2048 fail); else the whole file is invalid (A5a D11). Browser keys count toward the 32-leaf and duplicate-key checks.
- A5a's per-tab validation: a tab must contain at least one `SavedPane` leaf (A6 D5).
- `paneKeys` includes browser keys (they have no scrollback files: A5a D15's orphan sweep only deletes files, so nothing changes there).
- `fromState` (capture): a leaf with `isBrowserPaneId(id)` → `SavedBrowser(key: keyFor(id), url: urlForRestore(tab.browsers[id]!.url))`; `RestorePersistence` assigns `paneKey`s to negative ids exactly like session ids (A5a D14) and re-captures the layout when a browser pane's URL changes (`updateBrowser` → `terminalTabsProvider` change → the existing 1 s debounce; compare `url` only, never titles or loading flags, so loading churn does not write the file).

`terminal_tabs.dart`:

```dart
  /// A5a restore only (A6 D29): a browser leaf in a tab being rebuilt —
  /// no notice, focus untouched; the registry loads it when the tab shows.
  int openBrowserRestored({required int tabId, required Uri url}) {
    final id = _nextBrowserId--;
    final tab = _tab(tabId)!;
    _replaceTab(
      tab.copyWith(browsers: {...tab.browsers, id: BrowserPaneState(url: url)}),
    );
    return id;
  }
```

and in `restore(RestorePlan plan)` where A5a maps each saved leaf to a live id: `SavedBrowser(:final key, :final url)` → when `state.browserCount < kMaxBrowserPanes`, `openBrowserRestored(tabId: …, url: url == null ? aboutBlank : Uri.parse(url))` and remember `key ↔ id` in `RestoreOutcome.keyBySession` (it is keyed by pane id, negative ids included); over the limit → `removePane` the leaf like a failed session (counts into A5a's "Không mở lại được {n} pane" toast). Browser leaves never call `_local.open`. A5b reattach mode (A5b D18): browser leaves are rebuilt the same way (they never have a live session).

- [ ] **Step 8: Run the restore tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/ test/terminal/terminal_tabs_restore_test.dart`
Expected: PASS.

- [ ] **Step 9: Uninstaller, privacy page, HANDOFF, daemon note**

- `release/windows/shellx.iss` `[UninstallDelete]`: add `Type: filesandordirs; Name: "{localappdata}\ShellX\webview"` and `Type: filesandordirs; Name: "{localappdata}\ShellX\browser"`; extend `release/tests/inno.test.mjs` with the two paths (same assertion style as A5a's `restore` entry). Run `node --test release/tests/` → PASS.
- `web/src/pages/privacy.md` §4 (vi) add: "Pane trình duyệt của ShellX dùng hồ sơ riêng trên máy (không dùng hồ sơ Safari/Chrome/Edge của bạn); cookie và dữ liệu trang bị xoá mỗi lần thoát trừ khi bạn bật “Giữ dữ liệu trình duyệt”. Bố cục được khôi phục lưu địa chỉ trang của từng pane trình duyệt (có thể chứa mã trong địa chỉ, ví dụ Jupyter). Không dữ liệu duyệt web nào rời khỏi máy." `web/src/pages/en/privacy.md` §4 the English equivalent: "ShellX browser panes use a private profile on your computer (never your Safari/Chrome/Edge profile); cookies and site data are cleared every time you quit unless you turn on “Keep browser data”. The restored layout stores each browser pane's page address (which may contain tokens, for example Jupyter). No browsing data leaves your computer."
- `HANDOFF.md`: new section **§16 "Pane trình duyệt — A6 (2026-10-07)"**: what shipped (one paragraph); engines and versions (D1, D2 + `third_party/webview_windows/SHELLX_PATCHES.md`); known limits — Windows Narrator cannot read page content (D2), network list is best effort (D23), no downloads/file pickers/page zoom (D36), Esc on Windows depends on `AcceleratorKeyPressed` (Task 8 note); the ⚠ MANUAL checklist from Tasks 7–9 with the ledger results; the A7 contract (`browserCommandHandlerProvider`, §3.6 of the spec) and D35 (daemon has no browser).
- A5b note (D35): verify the headless daemon's explicit plugin registration list (A5b D2/D3) does **not** include `webview_flutter_wkwebview`/`webview_windows`; if A5b is merged, add a one-line test in A5b's daemon plugin-list test asserting their absence.
- Ledger: append under "## A6 (browser pane) — spike" the line `A6 merged checks: …` with Task 7/8/9 manual results.

- [ ] **Step 10: Full verification**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
cd ../../packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test
cd ../.. && node --check apps/desktop/assets/browser/browser_bootstrap.js && node --test release/tests/
git diff --stat main -- packages/shellx_core apps/mobile term relay   # must print nothing (D30)
```

Expected: analyzer clean, every suite green with the pre-Task-1 counts plus the new tests, no diff outside desktop/release/web/docs/third_party.

- [ ] **Step 11: Commit**

```bash
git add apps/desktop/lib/src/browser/browser_commands.dart apps/desktop/lib/src/browser/browser_host.dart apps/desktop/lib/src/restore apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/test/browser/browser_commands_test.dart apps/desktop/test/browser/browser_host_test.dart apps/desktop/test/restore/restore_browser_test.dart apps/desktop/test/terminal/terminal_tabs_restore_test.dart release/windows/shellx.iss release/tests/inno.test.mjs web/src/pages/privacy.md web/src/pages/en/privacy.md HANDOFF.md docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "feat(desktop): ui.browser command shapes for A7, browser pane restore, privacy and HANDOFF §16 (A6 D24, D29, D33, D35, D38)"
```

---

## Self-Review

**Spec coverage** (spec §1 criteria → tasks): 1 ⌘⇧B with port/blank → T5 (`openBrowser` default URL), T6 (chord), T9 (action, focus); 2 ⌥-click reuse → T9 (`_openPortInPane`, entry-point test); 3 toolbar + address rules → T2 (D9 table), T9 (widget tests, `openWebPage`); 4 security mark → T2 (`classifyOrigin`), T9 (origin mark, cert error page); 5 keys in page → T6 (forwarded chords), T7/T8 (native forwarding, ⚠), T9 (chord → intent test); 6 focus + Ctrl+F6 → T9 (region test), T7/T8 (`focusContent`/`releaseFocus`, ⚠); 7 agent API → T3 (eval script, run in Node during planning), T4 (controller), T10 (handler, host); 8 gate → T3, T4, T6 (setting + confirm); 9 isolation → T6 (profile), T7/T8 (clear, user data folder, ⚠); 10 restore → T10 (A5a); 11 phone unchanged → Global Constraints + T10 Step 10 diff check; 12 accessibility → T9 (labels, announcements), T1/T7/T8 (VoiceOver/Narrator ⚠); 13 no regression → every task runs the full suite, T10 Step 9 daemon plugin list. D3 fallback → T1 gate (stop and escalate). D32 dialogs → T7 (engine), T9 (queue + dialog). D36 → T8 (permissions denied), nothing else to build.

**Placeholder scan:** code steps carry code; the two places that describe UI composition in prose (Task 9 `_AddressField`/`_AgentMark`/`_ProgressBar`/`BrowserErrorView`, Task 9 Step 5 wiring into A3 widgets) name every size, token, string key, key and behaviour from UI-A6 because the exact A3 widget code is not on `main` yet; Task 9's widget tests pin them.

**Type consistency:** `BrowserPaneState`, `BrowserController` members, `BrowserError` codes, `BrowserEngine` (including `focusContent`/`releaseFocus`), `BridgeTransport`, `isBrowserPaneId`, `kMaxBrowserPanes`, `kBrowserMinSize`, `openBrowser(..., notify:)`, `existing()`/`controller()` on the registry, `chordString` format (Dart, Swift, C++ identical: alt, ctrl, meta, shift, key) — checked across Tasks 4–10. The pure Dart files of Tasks 2–4, 6 and 10 and their tests were compiled and run (85 tests green) with Dart 3.11 / Flutter 3.41.4 while writing this plan; the chord helpers ran under `flutter test`.

**Review Focus:** 1 → T4 "loading at once" + T10 navigate test; 2 → T5 D5 tests; 3 → T3 origin-check test + T4 screenshot test; 4 → T6 chord tests, T9 forwarded-chord/Esc tests, T7/T8 ⚠; 5 → T2 table + T9 address test.
