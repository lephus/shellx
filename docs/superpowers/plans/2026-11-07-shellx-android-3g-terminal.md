# ShellX Android terminal pane (3G) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Android shell pane's placeholder with the Mac's real terminal: a Kotlin port of ShellX Link's terminal views checked against the shared vectors, the iPhone's hub and view-model rules (plan 2C), a renderer that places every cell by column, soft-keyboard input that keeps Vietnamese composing on the phone, a key bar, hardware keys, scrolling, zoom, the ＋ chip, "View as Terminal", demo terminals and screenshot tests.

**Architecture:** Three layers, as on the iPhone. `shellx-link/kotlin/link-core` (MIT) gets the ten terminal messages of PROTOCOL.md §11 with their codec, `TerminalFrameAssembler`, `TerminalScreen` and the `LinkSession` terminal calls with `terminalPushes`. `shellx-android/core` gets 2C's pure rules (typing, batching, geometry, colours), Android hardware keys, an Android viewport, the hub's terminal calls, `TerminalViewModel` (rules R1–R12), the workspace model's terminal additions, and the fake Mac's terminals used by tests and the demo. `shellx-android/app` draws with `android.graphics` in a custom `View` (`TerminalSurfaceView`) that is also the keyboard's editor through its own `InputConnection`; a Compose `TerminalPane` hosts it, owns the gestures, the pane states and the key bar, and plugs into 3E's `PaneContent` shell slot.

**Tech Stack:** Kotlin/JVM 17 (link-core and `:core`: kotlinx-coroutines, kotlinx-serialization-json through its `JsonElement` API), JUnit 5 with `kotlin.test` and kotlinx-coroutines-test; `:app` with Jetpack Compose and Material 3, `android.view.inputmethod` (`BaseInputConnection`, `EditorInfo`, `InputMethodManager`), `android.graphics` (`Canvas`, `Paint`, `Typeface.MONOSPACE`), JUnit 4 with Robolectric, Compose UI tests, and Roborazzi through 3A's `ShellXSnapshots` and 3E's `assertRenders`; `shellx-android/scripts/dev.sh`. No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-mobile-terminal-design.md` (S2 §3, §4, §5) on top of `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md` §2.2 (criteria 3–5), §6.2, §6.3, §7.2 and §10; `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3) §5 and §7.5. Protocol: `shellx-link/spec/PROTOCOL.md` §11. This plan translates plan 2A (`docs/superpowers/plans/2026-11-07-shellx-terminal-2a-protocol.md`: its "Wire specification" and Interfaces) and plan 2C (`…-terminal-2c-ios.md`: "Design (decided)", rules R1–R12, its tests), and builds on 3A, 3B, 3C and 3E (`…-android-3a-scaffold.md`, `…-3b-link-kotlin.md`, `…-3c-core.md`, `…-3e-ui-work.md`: their Interfaces blocks). Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §5, §6, §9, §13, §14, §17, §18 and §20.

## Global Constraints

- **Branch and landing (contracts §1).** Branch `feat/shellx-android-3g-terminal`, worktree `.worktrees/android-3g-terminal`, from `develop`, after 2A, 2C and 3A–3E are merged (Task 0 checks). Merge into `develop` and push `develop` only after the final review and the user's OK (Task 15). Never merge to `main`; never deploy, upload or publish.
- **Scope.** Change only `shellx-link/kotlin/`, `shellx-android/core/`, `shellx-android/app/`, `docs/superpowers/ledgers/shellx-android-parity.md`, `shellx-android/scripts/strings-ios-only.txt` (only by 3A Task 11 Step 1's rule, in Task 15 Step 1), and the one entry `workspace.shell.placeholder` of `shellx-ios/ShellX/Localizable.xcstrings` (Task 14). Never edit `shellx-link/Sources`, `shellx-link/Tests`, `shellx-link/spec`, `shellx-link/vectors`, any other `shellx-ios/` file, or the plan and contracts files.
- **Licence (S3 §5).** `shellx-link/kotlin` is MIT and translates only `shellx-link/Sources` and `shellx-link/Tests`. `shellx-android` is closed source and translates only `shellx-ios/`, the Kotlin Link and the plans. Reading GPL code (`Sources/`, `Packages/`, `ios/`, `cmux-tui/`, `shellx-core/`, `ghostty/`) for reference is allowed; copying any of it is not. No new dependency, no bundled font, no terminal library. Never write the upstream company name.
- **Names.** As this plan's Interfaces blocks: 2A's Swift names in Kotlin style (contracts §13), 3B's patterns (an open enum is `@JvmInline value class X(val wire: String)` with constants; a Swift `…Error` is a `…Exception`), 3C's mirror rule in `:core` (`ShellXAppCore/Terminal/X.swift` → `core:terminal/X.kt`) and 3E's in `:app` (`ShellX/UI/Terminal/X.swift` → `app:ui/terminal/X.kt`). Where the code on `develop` names something differently, the code wins: use its name and list the difference in the report.
- **Protocol (PROTOCOL.md §11, contracts §17).** The phone takes any grid of 1 to 1 000 columns and 1 to 1 000 rows; the 20–300 / 5–120 clamp is the host's, on what a phone asks for. `terminal.view.open` carries `call_id`, `terminal_id`, `cols`, `rows` and nothing else (2A's `openView` has no device name).
- **Fixed values** (2C's, in Android units).

  | What | Value |
  | --- | --- |
  | Font | `Typeface.MONOSPACE`, 12 dp (dp, not sp: the grid never follows the system font size; pinch zoom instead), regular, bold, italic, bold italic |
  | Padding | 4 dp |
  | Zoom | from the fit-to-width scale up to 2.0 |
  | Resize | sent 200 ms after the last size change |
  | `busy` | retried every 300 ms, at most 5 times |
  | Failed open | retried once after 1 s |
  | Alternate-screen scroll | summed for 50 ms per message |
  | Echo | waited for at most 2 s |
  | History kept | 10 000 rows (`TerminalScreen.DEFAULT_MAX_HISTORY_ROWS`) |
  | Paste | at most 262 144 UTF-8 bytes (`TerminalInputBatcher.MAX_PASTE_BYTES`); beyond, the notice `terminal_paste_too_large` and nothing sent |
  | Notices over the terminal | 4 s (3E's `AgentView.NOTICE_DURATION`) |
  | Key bar | esc, tab, ctrl, ←, ↑, ↓, →, then hide keyboard at the trailing end; row 48 dp; keys drawn 40 dp high and at least 48 dp wide, each key's touch target the full 48 dp row height (`Modifier.minimumInteractiveComponentSize()`; 3E's 48 dp rule in place of 44 pt) |
- **Keyboard.** The editor's `EditorInfo` is the one in Design, "Soft keyboard". Never `TYPE_NULL`, never a password variation.
- **Strings.** 2C's 20 iPhone keys arrive through 3A's importer (`terminal_needs_update`, `terminal_connecting`, `terminal_offline`, `terminal_gone`, `terminal_failed`, `terminal_retry`, `terminal_surface_label`, `terminal_paste_too_large`, `terminal_key_escape`, `terminal_key_tab`, `terminal_key_ctrl`, `terminal_key_ctrl_latched`, `terminal_key_left`, `terminal_key_up`, `terminal_key_down`, `terminal_key_right`, `terminal_key_hide_keyboard`, `terminal_new`, `workspace_menu_view_as_terminal`, `workspace_menu_view_as_chat`). Android-only text goes into `res/values*/strings_android.xml` (Task 13). Never hand-edit the generated files.
- **Threading (3C, 3E).** `TerminalViewModel` is main-confined; its `run()` runs only while the workspace screen is STARTED; its outbox and delays run in `scope.hub.scope`. `TerminalScreen`, `TerminalFrameAssembler` and `TerminalTyping` are mutable and have one owner on the main thread. Never swallow a `CancellationException`.
- **Android API 26 floor in main sources.** No `java.util.HexFormat`, `java.net.http`, `InputStream.readAllBytes` or `transferTo`. `Paint.underlinePosition` and `underlineThickness` (API 29) only behind a version check.
- **Privacy.** Never log terminal content, typed or pasted text, keys, or workspace and tab titles: `LinkLog` and `CoreLog` lines carry event names and counts only. `TerminalInputUnit.Text`, `TerminalInputUnit.Paste` and `TerminalRun` print `<N bytes>` instead of their text (3B's rule for message content). The keyboard does not learn from what is typed (`IME_FLAG_NO_PERSONALIZED_LEARNING`).
- **Tests.** link-core: JUnit 5, `@Test fun x() { runBlocking { … } }` with a block body (3B). `:core`: JUnit 5, `@Test fun x() { runTest { … } }`, long-lived objects in `backgroundScope` (3C). `:app`: JUnit 4 with the Robolectric runner on every class (3E); Compose UI tests and render tests in `app/src/testDebug`; render tests in `com.shellx.app.screenshots` with 3E's `assertRenders`, one `@Test` per render name, no golden images. No real sleeps except 3E's `eventually` polling.
- **Commands.** Prefix build, test and git commands with `toknix run` (user instruction). The expected output below is what the command itself prints. `toknix run` starts a new bash, which cannot see the shell functions of Conventions (`gwl`, `gw`, `counts`): either call them without the prefix, or give `toknix run` the whole line, definitions included, as one quoted string.
- **Commits.** When a task has logic, commit the failing tests (`test(shellx-link): …` or `test(shellx-android): …`) before the implementation (`feat(…): …`), each with an explicit `git add <paths>`. Ledger rows change in the same commit as the code they describe.
- **Never** quit, relaunch or replace the user's running ShellX (`/Applications/ShellX.app`) or cmux; never install `com.shellx.prod` on the phone; never pass `--launch` to `scripts/reload.sh`.

## Review Focus

Inputs the spec implies that no translated iPhone test exercises, most likely first. Each has a test in the task that owns the code.

1. **A word the keyboard commits after the page moved to another terminal** (a chip swipe while composing, the keyboard finishing its word on focus loss): nothing reaches either terminal. Tests: Task 13 `aCommitAfterTheTerminalChangedIsDropped`, `onlyTheTerminalShownTakesKeys`.
2. **Multi-line text the keyboard commits as if typed** (Gboard's clipboard chip, voice typing): its line breaks would become Enter keys and run line by line; it goes as one paste. Test: Task 13 `aMultiLineCommitIsPastedNotTyped`.
3. **Keyboards that send Backspace and Enter their own way** (DEL key events, `deleteSurroundingText` with or without a composition, `performEditorAction`, `commitText("\n")`, digits as key events): exactly one backspace or Enter reaches the Mac, and a Backspace inside a composition stays on the phone. Tests: Task 13 `backspaceWithNothingComposedSendsOneBackspacePerCall`, `backspaceWhileComposingEditsTheWordOnThePhone`, `enterArrivesOnceWhicheverWayTheKeyboardSendsIt`, `hardwareKeysReachTheMacAsNamedKeysOrText`.
4. **A terminal inside the pager:** a vertical swipe never turns the page, a sideways swipe at fit does, and a zoomed-in grid pans instead of paging. Tests: Task 12 `aVerticalSwipeNeverTurnsThePage`, `aHorizontalSwipeAtFitTurnsThePage`, `zoomedInAHorizontalSwipePansTheGrid`.
5. **Glyphs the system monospace font lacks** (Vietnamese letters on some phones, CJK, emoji, symbols drawn by fallback fonts of other widths): every later cell stays in its column. Tests: Task 12 `aGlyphThatIsNotOneCellWideStaysInItsCell`, `aClusterWiderThanItsCellsIsSqueezedIntoThem`, render `terminal-wide`.

---

## Design (decided)

### Where things live

| Layer | Package | What |
| --- | --- | --- |
| link-core (MIT) | `com.shellx.link.core` | 2A's names: input units and rules, grid types, the ten messages, `TerminalFrameAssembler`, `TerminalScreen`, `TerminalViewPush`, the `LinkSession` terminal calls. No `TerminalFrameSplitter`: only a host splits, and the fake Mac sends each frame as one part |
| `:core` | `com.shellx.core.terminal` | 2C's `TerminalLink`, `TerminalTyping`, `TerminalInputBatcher`, `TerminalGeometry`, `TerminalZoom`, `TerminalColors`, `TerminalViewModel`; Android's `TerminalHardwareKeys` (key codes) and `TerminalViewport` |
| `:core` | `com.shellx.core.link`, `.workspaces`, `.demo` | the hub's terminal calls, the workspace model's additions, the fake Mac's terminals and `DemoTerminalScreens` |
| `:app` | `com.shellx.app.ui.terminal` | `TerminalFont`, `TerminalRowLayout`, `TerminalRowCache`, `TerminalSurfaceView`, `TerminalInputConnection`, `TerminalIme`, `TerminalKeyBar`, `TerminalPane` |

### Renderer: `android.graphics` in a custom View, gestures in Compose

- **Why a View.** An `InputConnection` needs a `View` (`onCreateInputConnection`), and composing text is the heart of S2 §3.6. Positioned glyphs with fallback fonts are direct with `Canvas.drawText`. A frame redraws the visible rows from cached draw lists with no recomposition; a Compose `Canvas` would lay out text per draw unless cached by hand, after a recomposition on the main thread (criteria 4 and 5).
- **Rows.** `TerminalRowLayout` turns a row's cells into segments of one resolved style and precomputed draw operations; `TerminalRowCache` keeps layouts by row object (a `TerminalRow` keeps its object while it moves from the screen into history), rebuilds only rows whose object changed, and drops layouts of rows more than 40 rows outside the visible range.
- **Cells by column.** Narrow cells whose glyph advance equals the cell width (within 0.5 px) join one `drawText` run starting at their first column. A narrow glyph of another width is drawn alone in its cell: centred when narrower, squeezed horizontally to the cell width when wider. A wide or multi-scalar cell is drawn alone, centred in its 1 or 2 columns, squeezed when wider. Later cells never move.
- **Passes.** Every visible row's backgrounds first, then every row's text and lines, then the cursor, then the composing text, so a diacritic that rises into the row above is never painted over.
- **Scale.** The canvas is scaled by `TerminalViewport.scale` (fit-to-width for any width the head reports, pinch up to 2.0); text is drawn in grid units at the 12 dp font.
- **Gestures.** `TerminalPane` puts them on the `AndroidView`, and the View's `onTouchEvent` returns false. A vertical `scrollable` scrolls history on the main screen, or sends scroll lines on the alternate screen while the grid fits the height (no fling there). A horizontal `scrollable` is enabled only while the grid is wider than the pane. A two-finger detector in the Initial pass consumes what it uses, so the pager never sees a pinch. While the grid is wider than the pane, or a pinch is under way, the pane asks 3E's `WorkspaceScreen` for `pagingLocked`, and the chips still switch pages.
- **Size.** The page shown reports the phone grid (`TerminalGeometry.phoneGrid` at the 12 dp cell) from its content box on every size change, in every state, so a terminal still loading reports its size (the model waits for one before it opens). The model debounces resizes by 200 ms (R11), which turns the keyboard's show and hide animations into one resize.

### Soft keyboard: the document is only the composing text

The surface is the keyboard's editor (`onCheckIsTextEditor()` true, focusable in touch mode). `onCreateInputConnection` fills `EditorInfo` and returns a `TerminalInputConnection`, which extends `BaseInputConnection(view, fullEditor = true)` and forwards to a `TerminalTextInput` (the model).

**`EditorInfo`.**

| Field | Value | Why |
| --- | --- | --- |
| `inputType` | `TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_NO_SUGGESTIONS or TYPE_TEXT_FLAG_MULTI_LINE` | A text class keeps each language's composing: Gboard's and Laban Key's Telex and VNI build the word as composing text. No suggestions, so an English word is not held as composing text for suggestions (letters go out and echo one by one, criterion 4). No `CAP_*`, `AUTO_CORRECT` or `AUTO_COMPLETE` flag: nothing is capitalised or rewritten. Multi-line, so Enter is the newline key, never an action |
| `imeOptions` | `IME_FLAG_NO_EXTRACT_UI or IME_FLAG_NO_FULLSCREEN or IME_FLAG_NO_ENTER_ACTION or IME_FLAG_NO_PERSONALIZED_LEARNING` | No full-screen text box in landscape over the terminal; Enter is never an action; the keyboard does not learn commands or secrets typed at a prompt |
| `initialSelStart`, `initialSelEnd` | the document's length | The cursor is at the end of the composing text |
| `initialCapsMode` | 0 | |

Rejected: `TYPE_NULL` (keyboards treat the editor as a raw key sink: Gboard sends key events and never composes, so Telex and VNI never form a word and CJK input breaks); `TYPE_TEXT_VARIATION_PASSWORD` and `VISIBLE_PASSWORD` (keyboards turn off their language features and often force a Latin layout); plain `TYPE_CLASS_TEXT` with suggestions (English words would echo only when a word ends). A keyboard that composes English words anyway is still correct: the word shows at the cursor and goes out when committed.

**The document.** What the keyboard sees is only the text being composed (`input.markedText`), with the cursor at its end; otherwise an empty document with the cursor at 0. Committed text is not kept: it went to the Mac. After each change the connection calls its `report(document, composing)`, which the surface turns into `TerminalIme.updateSelection(view, n, n, c0, c1)`: `n` is the document's length, and `(c0, c1)` is `(0, n)` while composing, else `(-1, -1)`. Inside a batch edit it reports once, at the outermost `endBatchEdit`.

**The calls.** Every forwarding call first checks `accepts()` (the surface's terminal is the model's terminal); otherwise it drops the call and returns true.

| Keyboard call | What the connection does |
| --- | --- |
| `setComposingText(text, _)` | `input.setMarkedText(text)`; the document becomes `input.markedText` (empty when a latched ctrl took the first letter) |
| `setComposingRegion(start, end)` | within the document: no change, true; anything else: false |
| `finishComposingText()` | `input.unmarkText()` (sends what was composed) |
| `commitText(text, _)` | `body` = `text` without one trailing line break (`\r\n`, `\n` or `\r`). When `body` still holds a line break: `input.paste(text)`. Otherwise `input.insertText(text)`, which replaces the composing text, as Android's `commitText` does |
| `deleteSurroundingText(before, _)`, `deleteSurroundingTextInCodePoints(before, _)` | `before > 0`: one `input.deleteBackward()` per call (it edits the composing text when there is one, else sends one backspace); `after` is ignored |
| `sendKeyEvent(event)` | `keys(event)`: the surface's hardware-key path; true |
| `performEditorAction(_)` | `input.press(TerminalKey.ENTER)` |
| `performContextMenuAction(id)` | `android.R.id.paste`: `clipboardText()?.let(input::paste)`, true; any other id: false |
| `getTextBeforeCursor(n, _)` | the last `n` chars of the document |
| `getTextAfterCursor(_, _)`, `getSelectedText(_)` | `""`, `null` |
| `getCursorCapsMode(_)` | 0 |
| `getExtractedText(_, _)` | the document, its selection at the end |
| `setSelection(_, _)` | no change (the cursor stays at the end), true |
| `commitContent(…)` | false; `commitCompletion`, `commitCorrection`: no change, true |
| `requestCursorUpdates(_)` | false |
| `closeConnection()` | `finishComposingText()`, then `super.closeConnection()` |

**Keeping the keyboard in step.** When the model's marked text differs from what the keyboard believes, the surface calls `TerminalIme.restart(view)` once, posted to the next main-loop turn, so the keyboard drops its composition. That happens after a call the model did not follow as sent (a latched ctrl took the first letter), and after a change from outside the keyboard (a key bar key, a hardware key, a paste, another terminal shown).

**Focus.** A tap or a long press focuses the surface and shows the keyboard (posted `TerminalIme.show`), only while the phase is `Live` or `Connecting`. The key bar shows while the surface has focus. When the soft keyboard goes from shown to hidden while the surface has focus (system Back, the keyboard's own hide key), the surface gives up its focus, so the key bar hides as on the iPhone. A hardware keyboard never shows the soft one, so the focus and the bar stay.

### Hardware keys

`TerminalSurfaceView.handleKey(event)` handles `ACTION_DOWN` (repeats included), consumes the `ACTION_UP` of a key whose down it handled, and turns `ACTION_MULTIPLE` with `KEYCODE_UNKNOWN` into `insertText(event.characters)`. A dead key (`getUnicodeChar` with `KeyCharacterMap.COMBINING_ACCENT`) is held and joined to the next character with `KeyEvent.getDeadChar`; when they do not join, the accent is typed first. Everything else goes through `TerminalHardwareKeys.action` (Task 7), with `plainChar = event.getUnicodeChar(event.metaState and (META_CTRL_MASK or META_ALT_MASK or META_META_MASK).inv())` and `altChar = event.getUnicodeChar(event.metaState and (META_CTRL_MASK or META_META_MASK).inv())`:

| Action | The surface calls |
| --- | --- |
| `Send(key, mods)` | `model.press(key, mods)`: a word being composed is committed first, and the keyboard restarts |
| `Type(text)` | `model.insertText(text)` (a latched ctrl applies; `"\n"` becomes `enter`) |
| `DeleteBackward` | `model.deleteBackward()` |
| `Paste` | `TerminalClipboard.text(context)?.let(model::paste)` |
| `System` | returns false: Back, volume, Meta shortcuts and function keys stay the system's |

Android gives keys to the input method before the view, so a key that reaches the view was passed on by it. The iPhone's "every key goes to the input method while composing" becomes "a key that reaches the terminal commits the word first" (ledger row A-g3).

### Android changes to 2C's rules

`TerminalViewModel` implements rules R1–R12 of plan 2C's "Design (decided)" word for word, with their constants, plus these changes:

- **A1 (R1, R9).** No `suspend()` or `resume()`; where R3 and R7 say `resume`, read "a new `run()`". `active` means the newest `run()` is running. 3E runs `run()` only while the workspace screen is STARTED, so going to the background, another screen covering the workspace, or a rotation cancels it (the view closes) and the next STARTED starts it again (it reopens).
- **A2 (R9).** The cleanup of a cancelled `run()` is deferred by one dispatch: it is launched in `scope` and yields once. A `run()` started in the same main-loop turn (a restarted effect) takes over. Then, if no newer `run()` started, the model stops being active and reconciles (the close is queued and still goes out).
- **A3 (state).** The observable part is `state: StateFlow<TerminalViewState>`, with `markedText` and `ctrlLatched` copied out of the mutable `TerminalTyping` after every change. `screen` is the mutable `TerminalScreen`, replaced by R2 and changed in place by R7 (`screenRevision` says when).
- **A4 (`close()`).** `close(): Job` stops the model for good. It queues the close of its view, lets the outbox drain, cancels its delays, and ignores every later call. The screen's holder calls it from `onCleared()`. The outbox drainer starts with the first `run()`, in `scope`.
- **A5 (clock).** The first-screen, apply and echo clocks read `now: TimeSource.WithComparableMarks`.
- **A6 (R12).** The notice of a paste over `MAX_PASTE_BYTES` is `pasteTooLarge`, a counter in the state raised by one per refused paste; the pane shows `terminal_paste_too_large` for 4 s when it rises.

---

## Conventions

- **Path prefixes.**
  - `link/` = `shellx-link/kotlin/link-core/src/main/kotlin/com/shellx/link/core/`; `link-test/` = `shellx-link/kotlin/link-core/src/test/kotlin/com/shellx/link/core/`.
  - `core/`, `core-test/` = 3C's (`shellx-android/core/src/main/kotlin/com/shellx/core/`, `…/src/test/kotlin/com/shellx/core/`).
  - `app/`, `app-test/`, `app-ui-test/`, `res/` = 3E's (`shellx-android/app/src/main/kotlin/com/shellx/app/`, `app/src/test/kotlin/com/shellx/app/`, `app/src/testDebug/kotlin/com/shellx/app/`, `app/src/main/res/`).
  - Swift references: `swift-link/` = `shellx-link/Sources/`, `swift-link-tests/` = `shellx-link/Tests/`, `ios-core/` = `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/`, `ios-core-tests/` = `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/`, `ios-app/` = `shellx-ios/ShellX/`, `ios-app-tests/` = `shellx-ios/ShellXTests/`, and `<DEMO_PKG>` (Task 0 Step 5).
- **Read the Swift first.** The Swift file a task names is the reference for every body this plan does not write out. Keep its behaviour.
- **Gradle.** Paste these definitions at the start of every shell call that uses them (shell state does not carry over):

  ```bash
  J="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  gwl() { R="$(git rev-parse --show-toplevel)"; (cd "$R/shellx-link/kotlin" && JAVA_HOME="$J" ./gradlew --console=plain "$@"); }
  gw() { R="$(git rev-parse --show-toplevel)"; JAVA_HOME="$J" ANDROID_HOME="$HOME/Library/Android/sdk" "$R/shellx-android/gradlew" -p "$R/shellx-android" --console=plain "$@"; }
  counts() { R="$(git rev-parse --show-toplevel)"; case "$1" in link) d=shellx-link/kotlin/link-core/build/test-results/test; p=com.shellx.link.core;; core) d=shellx-android/core/build/test-results/test; p=com.shellx.core;; app) d=shellx-android/app/build/test-results/testDebugUnitTest; p=com.shellx.app;; esac; shift; for c in "$@"; do echo "$c $(grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' "$R/$d/TEST-$p.$c.xml" | head -1)"; done; }
  ```

  - A **red** run ends with `BUILD FAILED`, plus the compile error naming the step's symbol or the failing test the step names.
  - A **green** run ends with `BUILD SUCCESSFUL` and has no `FAILED` line.
  - "N tests" means `counts <link|core|app> <Class or package.Class>` prints `tests="N" skipped="0" failures="0" errors="0"`.
- **Porting a Swift test file** follows 3C's convention ("Porting a Swift test file" and its table) in `:core`, 3B's in link-core and 3E's in `:app`. Additions for the terminal:

  | Swift | Kotlin |
  | --- | --- |
  | `.text("ls")`, `.key(.enter, mods: [])`, `.key(.letter("c"), mods: [.ctrl])`, `.paste(t)`, `.scroll(lines: 3)` | `Text("ls")`, `Key(TerminalKey.ENTER)`, `Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL))`, `Paste(t)`, `Scroll(3)` (import `TerminalInputUnit.*`) |
  | `.opened(terminalId:)`, `.frame(terminalId:part:)`, `.ended(terminalId:reason:)` | `TerminalViewPush.Opened(id)`, `Frame(id, part)`, `Ended(id, reason)` |
  | `.push(machineID:, p)`, `.state(machineID:, s)` | `TerminalHubEvent.Push(machineId, p)`, `State(machineId, s)` |
  | `.outcome(.ok)`, `.notSent`, `.noAnswer` | `TerminalOpenResult.Outcome(TerminalViewOpenOutcome.OK)`, `NotSent`, `NoAnswer` |
  | `.connecting`, `.live`, `.offline`, `.unsupported`, `.unavailable(.gone)` | `TerminalViewPhase.Connecting`, `Live`, `Offline`, `Unsupported`, `Unavailable(TerminalUnavailableReason.GONE)` |
  | `model.typing.markedText`, `model.typing.ctrlLatched` | `model.markedText`, `model.ctrlLatched` |
  | `.open("t1", cols: 50, rows: 20)`, `.close("t1")`, `.input("t1", u)`, `.resize(…)`, `.resync("t1")` | `Call.Open("t1", 50, 20)`, `Call.Close("t1")`, `Call.Input("t1", u)`, `Call.Resize(…)`, `Call.Resync("t1")` |
  | `SteppedNow`, `clock.advance(by: .milliseconds(600))` | `ManualClock()`, `clock.advance(600.milliseconds)`, its `monotonic` given as `now` |
  | `Collector(stream)` | `Collector(flow, backgroundScope)` |
  | `CGSize(width: 7.2, height: 15)`, `CGFloat` | two `Float` arguments (`7.2f, 15f`), `Float` |
  | `TerminalRGB(red:green:blue:)`, `TerminalCellStyle.default` | `TerminalRgb(r, g, b)`, `TerminalCellStyle.DEFAULT` |
  | `model.suspend()`, `model.resume()` | cancel the `run()` job; launch a new `run()` after the old one finished (A1) |
- **Ledger.** A row whose Plan cell names 3G gets `done (3G)` in the commit that finishes it. New Android-only rows go at the end of "Android-only differences" with the next free `A-` numbers, in this plan's order; below they are called `A-g1` to `A-g5`.

## File map

| Area | Files | Task |
| --- | --- | --- |
| Input names and the nine call messages | `link/{ShellXLink,TerminalView,TerminalInputCheck,LinkMessage,LinkCodec}.kt`; `link-test/{Vectors,VectorMessages,LinkCodecVectorTest,TerminalVectorTest,TerminalInputTest}.kt` | 1 |
| Grid and `terminal.view.frame` | `link/TerminalGrid.kt`, codec; `link-test/TerminalFrameCodecTest.kt` | 2 |
| Assembler and screen | `link/{TerminalFrameAssembler,TerminalScreen}.kt`; `link-test/TerminalScreenTest.kt` | 3 |
| Client API | `link/{LinkSession,LinkClient}.kt`; `link-test/LinkClientTerminalTest.kt` | 4 |
| Fake Mac terminals, demo screens | `core/demo/{DemoTerminalScreens,FakeMacTerminals,FakeMac,FakeMacSession,FakeMacWorkspaces}.kt`; `core-test/testing/TerminalTestSupport.kt` | 5 |
| Hub | `core/terminal/TerminalLink.kt`, `core/link/{HubTerminals,MachineHub,HubState,MachineEvent,MachineConnection}.kt`, `core/diagnostics/LatencyLog.kt` | 6 |
| Typing, batching, hardware keys | `core/terminal/{TerminalTextInput,TerminalTyping,TerminalInputBatcher,TerminalHardwareKeys}.kt` | 7 |
| Geometry, zoom, colours, viewport | `core/terminal/{TerminalGeometry,TerminalColors,TerminalViewport}.kt` | 8 |
| The model | `core/terminal/TerminalViewModel.kt`; `core-test/testing/{ScriptedTerminalLink,TerminalFixtures}.kt` | 9, 10 |
| Workspace model, demo | `core/workspaces/WorkspaceScreenModel.kt`, `core/demo/DemoEnvironment.kt` | 11 |
| Drawing | `app/ui/terminal/{TerminalFont,TerminalRowLayout,TerminalRowCache,TerminalSurfaceView,TerminalPane}.kt`, `app/ui/workspaces/ShellPanePlaceholder.kt` | 12 |
| Typing | `app/ui/terminal/{TerminalIme,TerminalInputConnection,TerminalKeyBar}.kt`, `res/values*/strings_android.xml` | 13 |
| Workspace wiring | `app/ui/workspaces/{WorkspaceScreen,PaneChips,WorkspaceView,WorkspaceFeedback}.kt`, `shellx-ios/ShellX/Localizable.xcstrings` (one entry) | 14 |

---

### Task 0: Set up the worktree and check what 3G builds on

**Files:** none.

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees. Without a native tool: `git worktree add .worktrees/android-3g-terminal -b feat/shellx-android-3g-terminal develop`. Work only there. Plan files may be untracked in the main checkout: read them at `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/` and never commit them here.
- [ ] **Step 2: Check that 2A, 2C and 3A–3E are merged.**

  ```bash
  for b in terminal-2a-protocol terminal-2c-ios android-3a-scaffold android-3b-link-kotlin android-3c-core android-3d-ui-shell android-3e-ui-work; do
    echo "$b $(git log develop --merges --oneline | grep -c "feat/shellx-$b")"; done
  test -f shellx-link/spec/vectors/terminal.json \
    && grep -q 'terminalPushes' shellx-link/Sources/ShellXLinkSession/LinkClient.swift \
    && test -f shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalViewModel.swift \
    && grep -rq 'interface LinkSession' shellx-link/kotlin/link-core/src/main \
    && grep -rq 'class MachineHub' shellx-android/core/src/main \
    && grep -rq 'fun PaneContent' shellx-android/app/src/main \
    && test -f docs/superpowers/ledgers/shellx-android-parity.md && echo ready
  echo "terminal-2b-mac $(git log develop --merges --oneline | grep -c 'feat/shellx-terminal-2b-mac')"
  ```

  Expected: every line before `ready` ends with a count of 1 or more, then `ready`. Otherwise stop and report "plans 2A, 2C and 3A–3E must be merged into develop first". Change nothing. The last line is information only: `0` means plan 2B (the Mac host) is not on `develop`, so Task 15 Step 8 Part B (items 12–20) and Step 9 stay pending; do not stop for it.
- [ ] **Step 3: Run the baseline.** Run `shellx-android/scripts/dev.sh test all`. Expected: `==> test all: passed`. If it fails before any change, stop and report.
- [ ] **Step 4: Read what this plan builds on.**
  - The Swift of 2A: `swift-link/ShellXLinkCore/ShellXLink+Terminal.swift`, `Messages/{TerminalView,TerminalInputCheck,LinkCodec,LinkMessage}.swift`, `Terminal/{TerminalGrid,TerminalFrameAssembler,TerminalScreen}.swift`, `swift-link/ShellXLinkSession/{LinkClient,TerminalViewSlot}.swift`, and their tests in `swift-link-tests/`.
  - The Swift of 2C: `ios-core/Terminal/*.swift`, `ios-core/Link/MachineHub+Terminal.swift`, `ios-core/Workspaces/WorkspaceScreenModel.swift`, `ios-app/UI/Terminal/*.swift`, `ios-app/UI/Workspaces/{WorkspaceScreen,PaneChips,WorkspaceView,WorkspaceFeedback}.swift`, `<DEMO_PKG>/{DemoTerminalScreens,FakeMacTerminals}.swift`, and their tests.
  - The Kotlin of 3B (`link/LinkSession.kt`, `LinkClient.kt`, `LinkCodec.kt`, `JsonFields.kt`, `link-test/{Vectors,VectorMessages,LinkCodecVectorTest,TestHosts,TestSupport}.kt`), 3C (`core/link/{MachineHub,HubState,MachineEvent,MachineConnection}.kt`, `core/workspaces/WorkspaceScreenModel.kt`, `core/demo/*`, `core-test/testing/*`), and 3E (`app/ui/workspaces/*`, `app-test/testing/*`, `app-ui-test/screenshots/RenderAssertions.kt`).
  - Wherever a name or signature differs from this plan, keep the real one and write the difference down for the report.
- [ ] **Step 5: Note four facts.**

  ```bash
  dirname "$(git ls-files 'shellx-ios/Packages/ShellXAppCore/Sources/*/DemoTerminalScreens.swift')"
  grep -n 'TERMINAL_VIEW_CASES\|isTerminalViewFrame\|terminal' shellx-link/kotlin/link-core/src/test/kotlin/com/shellx/link/core/{Vectors,VectorMessages,LinkCodecVectorTest}.kt
  grep -cE 'name="(terminal_(needs_update|connecting|offline|gone|failed|retry|surface_label|paste_too_large|key_[a-z_]+|new)|workspace_menu_view_as_(terminal|chat))"' shellx-android/app/src/main/res/values/strings.xml
  grep -rn 'workspace_shell_placeholder' shellx-android/app/src --include='*.kt'
  ```

  Expected:
  - the `<DEMO_PKG>` folder (`…/Sources/ShellXDemo` or `…/Sources/ShellXAppTestSupport`);
  - the lines where 3B skips terminal vectors (Tasks 1 and 2 remove every one);
  - `20` (2C's 20 keys of Global Constraints). When it is lower, run `python3 shellx-android/scripts/import-strings.py`. If it refuses a key, stop and report the key. Otherwise commit the two regenerated files as `chore(shellx-android): import the terminal strings`. If the count is still below 20, stop and report which name is missing: its iPhone key must come from plan 2C's catalog (2C's text counts 19 and may have left out `terminal.paste.tooLarge`), and this plan edits no other catalog entry;
  - the Kotlin uses of `workspace_shell_placeholder` (3E's `ShellPanePlaceholder` and maybe a test), which Task 12 switches to `terminal_needs_update`.

---

### Task 1: link-core — input units, input rules and the nine call messages

**Files:**
- Modify: `link/ShellXLink.kt`, `link/LinkMessage.kt`, `link/LinkCodec.kt` (and `link/JsonFields.kt` only for a missing reader)
- Create: `link/TerminalView.kt`, `link/TerminalInputCheck.kt`
- Modify: `link-test/Vectors.kt`, `link-test/VectorMessages.kt`, `link-test/LinkCodecVectorTest.kt`
- Test: create `link-test/TerminalVectorTest.kt`, `link-test/TerminalInputTest.kt`

Reference: `swift-link/ShellXLinkCore/ShellXLink+Terminal.swift`, `Messages/TerminalView.swift`, `Messages/TerminalInputCheck.swift`, `Messages/LinkCodec.swift`; `swift-link-tests/ShellXLinkCoreTests/TerminalVectorTests.swift` and `LinkCodecTests.swift` (`message(from:)`, `terminalUnits`).

**Interfaces:**
- Consumes: 3B's `LinkCodec`, `LinkMessage`, `LinkMessage.Answer`, `LinkCodecException`, `WorkspaceControlOutcome`, the strict readers of `JsonFields.kt`.
- Produces (`com.shellx.link.core`):

```kotlin
// ShellXLink.kt: object ShellXLink gains
const val TERMINAL_VIEW_FEATURE = "terminal_view"
const val TERMINAL_CREATE_FEATURE = "terminal_create"
val TERMINAL_COLUMNS: IntRange = 20..300
val TERMINAL_ROWS: IntRange = 5..120
const val TERMINAL_MAX_GRID_SIZE = 1000
const val TERMINAL_MAX_FRAME_PARTS = 256
const val TERMINAL_MAX_CELL_TEXT_BYTES = 32
const val TERMINAL_SNAPSHOT_HISTORY_ROWS = 240
const val TERMINAL_HISTORY_ROW_BUDGET = 4000
const val TERMINAL_HISTORY_FILL_MAX_BYTES = 262_144
const val TERMINAL_MAX_DELTA_HISTORY_ROWS = 2000
const val TERMINAL_MAX_INPUT_UNITS = 64
const val TERMINAL_MAX_TEXT_BYTES = 4096
const val TERMINAL_MAX_PASTE_BYTES = 16_384
const val TERMINAL_MAX_SCROLL_LINES = 100
const val TERMINAL_MAX_QUEUED_INPUTS = 64

// TerminalView.kt. Open enums: an unknown wire value is kept as is.
@JvmInline value class TerminalViewOpenOutcome(val wire: String)   // OK, NOT_FOUND, REFUSED, BUSY, FAILED
@JvmInline value class TerminalViewEndReason(val wire: String)     // GONE, REFUSED, FAILED, NOT_OPEN
@JvmInline value class TerminalModifier(val wire: String)          // CTRL, ALT, SHIFT
@JvmInline value class TerminalKey(val wire: String) {
    /** 'a'..'z' when the wire is one lowercase ASCII letter, else null. */
    val letter: Char?
    /** One of ALL_KNOWN. */
    val isKnown: Boolean
    companion object {
        val ENTER; val TAB; val BACKSPACE; val ESCAPE; val DELETE; val SPACE   // wire = the lower-case name
        val UP; val DOWN; val LEFT; val RIGHT; val HOME; val END
        val PAGE_UP = TerminalKey("page_up"); val PAGE_DOWN = TerminalKey("page_down")
        /** IllegalArgumentException unless c is in 'a'..'z'. */
        fun letter(c: Char): TerminalKey
        /** The 40 names of PROTOCOL.md 11.2 in its order: the 14 named keys, then a … z. */
        val ALL_KNOWN: List<TerminalKey>
    }
}
sealed interface TerminalInputUnit {
    data class Text(val text: String) : TerminalInputUnit          // toString: Text(<N bytes>)
    data class Key(val key: TerminalKey, val mods: List<TerminalModifier> = emptyList()) : TerminalInputUnit
    data class Paste(val text: String) : TerminalInputUnit         // toString: Paste(<N bytes>)
    data class Scroll(val lines: Int) : TerminalInputUnit
    /** A unit of a later version: its other fields are dropped; it encodes as {"k": kind}. */
    data class Other(val kind: String) : TerminalInputUnit
}
// TerminalInputCheck.kt
data class TerminalInputException(val reason: String) : Exception(reason)
object TerminalInputCheck {
    /** The rules of PROTOCOL.md 11.2; `reason` is one of 2A's fixed phrases and never quotes the units. */
    fun check(units: List<TerminalInputUnit>)                       // throws TerminalInputException
}
// LinkMessage.kt, nested in LinkMessage (A = an Answer, `override val callId`)
data class TerminalViewOpen(val callId: String, val terminalId: String, val cols: Int, val rows: Int)
data class TerminalViewOpenResult(override val callId: String, val outcome: TerminalViewOpenOutcome)                         // A
data class TerminalViewInput(val terminalId: String, val units: List<TerminalInputUnit>)
data class TerminalViewResize(val terminalId: String, val cols: Int, val rows: Int)
data class TerminalViewResync(val terminalId: String)
data class TerminalViewClose(val terminalId: String)
data class TerminalViewEnded(val terminalId: String, val reason: TerminalViewEndReason)
data class TerminalCreate(val callId: String, val workspaceId: String)
data class TerminalCreateResult(override val callId: String, val outcome: WorkspaceControlOutcome, val terminalId: String? = null) // A
```

  Wire table (contracts §6; `TerminalViewFrame` is Task 2):

  | Class | `t` | `message.case` |
  | --- | --- | --- |
  | `TerminalViewOpen` | `terminal.view.open` | `terminal_view_open` |
  | `TerminalViewOpenResult` | `terminal.view.open.result` | `terminal_view_open_result` |
  | `TerminalViewInput` | `terminal.view.input` | `terminal_view_input` |
  | `TerminalViewResize` | `terminal.view.resize` | `terminal_view_resize` |
  | `TerminalViewResync` | `terminal.view.resync` | `terminal_view_resync` |
  | `TerminalViewClose` | `terminal.view.close` | `terminal_view_close` |
  | `TerminalViewEnded` | `terminal.view.ended` | `terminal_view_ended` |
  | `TerminalCreate` | `terminal.create` | `terminal_create` |
  | `TerminalCreateResult` | `terminal.create.result` | `terminal_create_result` |

  Codec rules (3B's strict readers; violations are `BadJson` with the frame's valid `call_id`):
  - `units`: an array of objects. Each needs a string `k`. `text` and `paste` need a string `text`; `key` needs a string `key`, and `mods` is an optional array of strings; `scroll` needs an integer `lines`; any other `k` becomes `Other(k)` whatever its fields.
  - Encoding writes `mods` only when it is not empty, and `terminal_id` of `TerminalCreateResult` only when it is not null.
  - `TerminalInputCheck.check` applies 2A Task 2 Step 5's rules in that order, with exactly these reasons: `"an input message carries 1 to 64 units"`, `"text is empty"`, `"text holds a control character"`, `"typed text is over 4096 bytes"`, `"pasted text is empty"`, `"pasted text holds a control character"`, `"pasted text is over 16384 bytes"`, `"scroll lines must be 1 to 100 either way"`, `"a modifier is repeated"`. Sizes are UTF-8 bytes. Other units, unknown keys and unknown modifiers pass.

- [ ] **Step 1: Write the failing tests.**
  - **`Vectors.kt`.** Add `val terminal: JsonObject get() = json("../../spec/vectors/terminal.json")`. Change every terminal skip that Task 0 Step 5 listed so that only `terminal.view.frame` is still skipped (`TERMINAL_VIEW_CASES = setOf("terminal_view_frame")`, `isTerminalViewFrame(t) = t == "terminal.view.frame"`), and apply that one skip in all three sections: `vectors`, `decode_only` (2A put two frame entries there) and `decode_errors`.
  - **`VectorMessages.kt`.** `fromVector` gains the nine cases of the table, built by hand like the Swift `message(from:)`. A private `terminalUnits(e: JsonElement?)` maps `k`: `text` → `Text`; `key` → `Key(TerminalKey(key), mods?.map(::TerminalModifier) ?: emptyList())`; `paste` → `Paste`; `scroll` → `Scroll`; anything else → `Other(k)`. `SENDABLE_CASES` gains the nine names.
  - **`TerminalVectorTest`** (the ports of `TerminalVectorTests.swift`):

```kotlin
class TerminalVectorTest {
    private val file = Vectors.terminal
    private fun JsonObject.ints(k: String) = getValue(k).jsonArray.map { it.jsonPrimitive.int }
    private fun JsonObject.int(k: String) = getValue(k).jsonPrimitive.int

    @Test fun limitsMatchTheVectors() {
        val l = file.getValue("limits").jsonObject
        assertEquals(listOf(ShellXLink.TERMINAL_COLUMNS.first, ShellXLink.TERMINAL_COLUMNS.last), l.ints("columns"))
        assertEquals(listOf(ShellXLink.TERMINAL_ROWS.first, ShellXLink.TERMINAL_ROWS.last), l.ints("rows"))
        assertEquals(ShellXLink.TERMINAL_MAX_GRID_SIZE, l.int("max_grid_size"))
        assertEquals(ShellXLink.TERMINAL_MAX_FRAME_PARTS, l.int("max_frame_parts"))
        assertEquals(ShellXLink.TERMINAL_MAX_CELL_TEXT_BYTES, l.int("max_cell_text_bytes"))
        assertEquals(ShellXLink.TERMINAL_SNAPSHOT_HISTORY_ROWS, l.int("snapshot_history_rows"))
        assertEquals(ShellXLink.TERMINAL_HISTORY_ROW_BUDGET, l.int("history_row_budget"))
        assertEquals(ShellXLink.TERMINAL_HISTORY_FILL_MAX_BYTES, l.int("history_fill_max_bytes"))
        assertEquals(ShellXLink.TERMINAL_MAX_DELTA_HISTORY_ROWS, l.int("max_delta_history_rows"))
        assertEquals(ShellXLink.TERMINAL_MAX_INPUT_UNITS, l.int("max_input_units"))
        assertEquals(ShellXLink.TERMINAL_MAX_TEXT_BYTES, l.int("max_text_bytes"))
        assertEquals(ShellXLink.TERMINAL_MAX_PASTE_BYTES, l.int("max_paste_bytes"))
        assertEquals(ShellXLink.TERMINAL_MAX_SCROLL_LINES, l.int("max_scroll_lines"))
        assertEquals(ShellXLink.TERMINAL_MAX_QUEUED_INPUTS, l.int("max_queued_inputs"))
    }
    @Test fun keyAndModifierNames() {
        val keys = file.getValue("keys").jsonArray.map { it.jsonPrimitive.content }
        assertEquals(40, keys.size)
        assertEquals(keys, TerminalKey.ALL_KNOWN.map { it.wire })
        for (k in keys) assertTrue(TerminalKey(k).isKnown, k)
        assertEquals(TerminalKey.PAGE_UP, TerminalKey("page_up"))
        assertEquals(TerminalKey.letter('c'), TerminalKey("c")); assertEquals('c', TerminalKey("c").letter)
        assertFalse(TerminalKey("C").isKnown); assertNull(TerminalKey("C").letter); assertFalse(TerminalKey("f13").isKnown)
        assertEquals(file.getValue("modifiers").jsonArray.map { it.jsonPrimitive.content },
            listOf(TerminalModifier.CTRL, TerminalModifier.ALT, TerminalModifier.SHIFT).map { it.wire })
        assertNotEquals(TerminalModifier.CTRL, TerminalModifier("cmd"))
    }
    @Test fun inputChecks() {
        val checks = file.getValue("input_checks").jsonArray.map { it.jsonObject }
        assertEquals(27, checks.size)
        for (c in checks) {
            val name = c.getValue("name").jsonPrimitive.content
            val frame = buildJsonObject {
                put("v", 1); put("t", "terminal.view.input"); put("terminal_id", "t-1"); put("units", c.getValue("units"))
            }
            val message = LinkCodec.decode(Json.encodeToString(JsonObject.serializer(), frame).encodeToByteArray())
            val units = assertIs<LinkMessage.TerminalViewInput>(message, name).units
            val passed = try { TerminalInputCheck.check(units); true } catch (e: TerminalInputException) { false }
            assertEquals(c.getValue("ok").jsonPrimitive.boolean, passed, name)
        }
    }
    @Test fun inputErrorNeverQuotesTheText() {
        val e = assertFailsWith<TerminalInputException> { TerminalInputCheck.check(listOf(TerminalInputUnit.Text("hunter2\n"))) }
        assertFalse("hunter2" in e.reason); assertFalse("hunter2" in e.message.orEmpty())
    }
    @Test fun featureNames() {
        assertEquals("terminal_view", ShellXLink.TERMINAL_VIEW_FEATURE); assertEquals("terminal_create", ShellXLink.TERMINAL_CREATE_FEATURE)
    }
}
```

  - **`TerminalInputTest`** (Kotlin only; `import com.shellx.link.core.TerminalInputUnit.*`):

```kotlin
class TerminalInputTest {
    private fun units(m: LinkMessage) = Json.parseToJsonElement(LinkCodec.encode(m).decodeToString()).jsonObject.getValue("units")
    @Test fun unitsEncodeTheirWireFormAndEmptyModsAreOmitted() {
        val m = LinkMessage.TerminalViewInput("t-1", listOf(Text("ls"), Key(TerminalKey.ENTER),
            Key(TerminalKey.letter('c'), listOf(TerminalModifier.CTRL)), Paste("a\nb"), Scroll(-3)))
        assertEquals(Json.parseToJsonElement("""[{"k":"text","text":"ls"},{"k":"key","key":"enter"},
            {"k":"key","key":"c","mods":["ctrl"]},{"k":"paste","text":"a\nb"},{"k":"scroll","lines":-3}]"""), units(m))
    }
    @Test fun anUnknownUnitKindKeepsOnlyItsKind() {
        val m = LinkCodec.decode("""{"v":1,"t":"terminal.view.input","terminal_id":"t-1","units":[{"k":"gesture","dx":1}]}""".encodeToByteArray())
        assertEquals(LinkMessage.TerminalViewInput("t-1", listOf(Other("gesture"))), m)
        assertEquals(Json.parseToJsonElement("""[{"k":"gesture"}]"""), units(m))
    }
    @Test fun typedAndPastedTextIsNeverPrinted() {
        assertFalse("hunter2" in Text("hunter2").toString()); assertFalse("hunter2" in Paste("hunter2").toString())
        assertFalse("hunter2" in LinkMessage.TerminalViewInput("t-1", listOf(Text("hunter2"))).toString())
        assertTrue("7 bytes" in Text("hunter2").toString())
    }
    @Test fun letterKeysAreLowercaseAsciiOnly() {
        assertEquals("a", TerminalKey.letter('a').wire)
        assertFailsWith<IllegalArgumentException> { TerminalKey.letter('A') }
        assertFailsWith<IllegalArgumentException> { TerminalKey.letter('đ') }
    }
}
```

- [ ] **Step 2: Run (red).** Run `gwl :link-core:test --tests 'com.shellx.link.core.Terminal*' --tests 'com.shellx.link.core.LinkCodecVectorTest'`. Expected: `BUILD FAILED` with `Unresolved reference` naming `TerminalInputUnit` (or another new name).
- [ ] **Step 3: Commit the tests.** `git add shellx-link/kotlin/link-core/src/test` and `git commit -m "test(shellx-link): Kotlin terminal input units and call messages against the vectors"`.
- [ ] **Step 4: Implement** `TerminalView.kt`, `TerminalInputCheck.kt`, the constants, the nine classes and their codec bodies, as Interfaces says.
- [ ] **Step 5: Run (green).** Run the Step 2 command. Expected: PASS; `counts link TerminalVectorTest TerminalInputTest LinkCodecVectorTest` shows 5, 4 and 4 tests. Then `shellx-android/scripts/dev.sh test link`. Expected: `==> test link: passed`.
- [ ] **Step 6: Commit.** `git add shellx-link/kotlin/link-core/src/main` and `git commit -m "feat(shellx-link): Kotlin terminal input units and the terminal call messages"`.

---

### Task 2: link-core — grid types and `terminal.view.frame`

**Files:**
- Create: `link/TerminalGrid.kt`
- Modify: `link/LinkMessage.kt`, `link/LinkCodec.kt`
- Modify: `link-test/Vectors.kt`, `link-test/VectorMessages.kt`, `link-test/LinkCodecVectorTest.kt`
- Test: create `link-test/TerminalFrameCodecTest.kt`

Reference: `swift-link/ShellXLinkCore/Terminal/TerminalGrid.swift`, the frame body of `Messages/LinkCodec.swift`; `swift-link-tests/ShellXLinkCoreTests/TerminalFrameCodecTests.swift`.

**Interfaces:**
- Consumes: Task 1.
- Produces (`com.shellx.link.core`):

```kotlin
@JvmInline value class TerminalFrameKind(val wire: String)     // SNAPSHOT, DELTA, HISTORY
@JvmInline value class TerminalCursorShape(val wire: String)   // BLOCK, BAR, UNDERLINE, BLOCK_HOLLOW = "block_hollow"
@JvmInline value class TerminalAttribute(val wire: String)     // BOLD, FAINT, ITALIC, UNDERLINE, BLINK, INVERSE, INVISIBLE, STRIKE, OVERLINE
data class TerminalCursor(val x: Int, val y: Int, val shape: TerminalCursorShape = TerminalCursorShape.BLOCK,
                          val visible: Boolean = true, val blink: Boolean = false)
data class TerminalPalette(val fg: String, val bg: String, val cursor: String? = null, val colors: List<String>)
data class TerminalCellStyle(val fg: Int? = null, val fgRgb: String? = null, val bg: Int? = null, val bgRgb: String? = null,
                             val attrs: List<TerminalAttribute> = emptyList()) { companion object { val DEFAULT = TerminalCellStyle() } }
data class TerminalStyle(val id: Int, val fg: Int? = null, val fgRgb: String? = null, val bg: Int? = null, val bgRgb: String? = null,
                         val attrs: List<TerminalAttribute> = emptyList()) { val cellStyle: TerminalCellStyle }
/** Wire keys x, t, s, w. toString prints <N bytes> for the text. */
data class TerminalRun(val x: Int? = null, val text: String, val style: Int? = null, val width: Int? = null)
data class TerminalLine(val y: Int, val runs: List<TerminalRun> = emptyList())
data class TerminalFrameHead(val kind: TerminalFrameKind, val cols: Int, val rows: Int, val alt: Boolean = false,
                             val cursor: TerminalCursor? = null, val palette: TerminalPalette? = null, val history: Int = 0, val scroll: Int = 0)
data class TerminalFramePart(val revision: Long, val part: Int = 0, val parts: Int = 1, val head: TerminalFrameHead? = null,
                             val styles: List<TerminalStyle> = emptyList(), val lines: List<TerminalLine> = emptyList())
/** One whole frame, all parts merged: what the assembler hands out and the screen applies. */
data class TerminalGridFrame(val head: TerminalFrameHead, val styles: List<TerminalStyle> = emptyList(), val lines: List<TerminalLine> = emptyList())
// LinkMessage: data class TerminalViewFrame(val terminalId: String, val frame: TerminalFramePart)
//   t "terminal.view.frame", case "terminal_view_frame"
```

  Codec rules (2A Task 3). Validation runs on encode and on decode, and every violation is `BadJson(null)`:
  - `revision` ≥ 1, `parts` 1–256, `part` 0 to `parts` − 1;
  - head `cols` ≥ 1, `rows` ≥ 1, `history` ≥ 0, `scroll` ≥ 0; cursor `x` ≥ 0, `y` ≥ 0;
  - palette `fg`, `bg` and `cursor` are colours, and `colors` holds exactly 256 colours. A colour is `#` and 6 hex digits, in either case;
  - style `id` 1–65 535; `fg` and `bg` 0–255; `fg_rgb` and `bg_rgb` colours; never both `fg` and `fg_rgb`, nor both `bg` and `bg_rgb`;
  - run `t` not empty; `w` null or 1–2; `x` null or ≥ 0; `s` null or ≥ 0.

  Empty `styles`, `lines`, `runs` and `attrs` are left out, as are `history` and `scroll` when 0 and `cursor`, `palette`, `head` and `x`/`s`/`w` when null. Absent arrays decode as empty lists.

- [ ] **Step 1: Write the failing tests.**
  - `Vectors.kt` and `LinkCodecVectorTest.kt`: delete the last terminal skip and its uses. `VectorMessages.kt`: `terminal_view_frame` → `TerminalViewFrame(terminalId, terminalFramePart(m))`, with a private `terminalFramePart` that maps every key of 2A's `terminalFramePart(_:)` (absent arrays → `emptyList()`, absent `history`/`scroll` → 0); `SENDABLE_CASES` gains `terminal_view_frame` (50 names in all).
  - `TerminalFrameCodecTest` (the three ports of `TerminalFrameCodecTests.swift`, then one Kotlin test):

```kotlin
class TerminalFrameCodecTest {
    private val palette = TerminalPalette("#d0d0d0", "#101010", "#ff8800", (0 until 256).map { "#%02x%02x%02x".format(it, it, it) })
    private fun json(m: LinkMessage) = Json.parseToJsonElement(LinkCodec.encode(m).decodeToString()).jsonObject

    @Test fun paletteRoundTrips() {
        val head = TerminalFrameHead(TerminalFrameKind.SNAPSHOT, 80, 24, cursor = TerminalCursor(0, 0), palette = palette, history = 3)
        val m = LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(revision = 1, head = head))
        assertEquals(m, LinkCodec.decode(LinkCodec.encode(m)))
    }
    @Test fun emptyFieldsAreOmitted() {
        val o = json(LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(2, part = 1, parts = 2, lines = listOf(TerminalLine(0)))))
        assertEquals(setOf("v", "t", "terminal_id", "revision", "part", "parts", "lines"), o.keys)
        assertEquals(setOf("y"), o.getValue("lines").jsonArray[0].jsonObject.keys)
        val head = TerminalFrameHead(TerminalFrameKind.DELTA, 2, 1, cursor = TerminalCursor(0, 0))
        val h = json(LinkMessage.TerminalViewFrame("t-1", TerminalFramePart(1, head = head))).getValue("head").jsonObject
        assertEquals(setOf("kind", "cols", "rows", "alt", "cursor"), h.keys)
    }
    @Test fun encodingChecksTheSameRulesAsDecoding() {
        val bad = listOf(TerminalFramePart(0), TerminalFramePart(1, part = 1, parts = 1),
            TerminalFramePart(1, 1, 2, styles = listOf(TerminalStyle(1, fg = 256))),
            TerminalFramePart(1, 1, 2, styles = listOf(TerminalStyle(1, bgRgb = "336699"))),
            TerminalFramePart(1, 1, 2, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "x", width = 3))))),
            TerminalFramePart(1, 1, 2, lines = listOf(TerminalLine(0, listOf(TerminalRun(text = ""))))))
        for (p in bad) {
            val e = assertFailsWith<LinkCodecException>(p.toString()) { LinkCodec.encode(LinkMessage.TerminalViewFrame("t-1", p)) }
            assertEquals(LinkCodecException.BadJson(null), e)
        }
    }
    @Test fun runsNeverPrintTheirText() {
        assertFalse("secret" in TerminalRun(text = "secret").toString())
        assertFalse("secret" in TerminalLine(0, listOf(TerminalRun(text = "secret"))).toString())
    }
}
```

- [ ] **Step 2: Run (red).** Run `gwl :link-core:test --tests 'com.shellx.link.core.TerminalFrameCodecTest' --tests 'com.shellx.link.core.LinkCodecVectorTest'`. Expected: `BUILD FAILED`, `Unresolved reference` naming `TerminalFramePart`.
- [ ] **Step 3: Commit the tests.** `git add shellx-link/kotlin/link-core/src/test` and `git commit -m "test(shellx-link): Kotlin terminal frames against the vectors"`.
- [ ] **Step 4: Implement** `TerminalGrid.kt`, the frame class and its codec body with the validation above.
- [ ] **Step 5: Run (green).** Run the Step 2 command. Expected: PASS; `counts link TerminalFrameCodecTest LinkCodecVectorTest` shows 4 and 4; `grep -c 'TERMINAL_VIEW_CASES\|isTerminalViewFrame' shellx-link/kotlin/link-core/src/test/kotlin/com/shellx/link/core/*.kt` prints `0` for every file.
- [ ] **Step 6: Commit.** `git add shellx-link/kotlin/link-core/src/main` and `git commit -m "feat(shellx-link): Kotlin terminal grid frames and their codec"`.

---

### Task 3: link-core — the frame assembler and the screen model

**Files:**
- Create: `link/TerminalFrameAssembler.kt`, `link/TerminalScreen.kt`
- Modify: `link-test/TerminalVectorTest.kt` (`screens`)
- Test: create `link-test/TerminalScreenTest.kt`

Reference: `swift-link/ShellXLinkCore/Terminal/TerminalFrameAssembler.swift`, `TerminalScreen.swift`; `swift-link-tests/ShellXLinkCoreTests/TerminalVectorTests.swift` (`testScreens`), `TerminalScreenTests.swift`; PROTOCOL.md §11.5–11.7.

**Interfaces:**
- Consumes: Task 2.
- Produces:

```kotlin
data class TerminalAssemblyResult(val frame: TerminalGridFrame? = null, val resync: Boolean = false)
/** PROTOCOL.md 11.7. Mutable, one owner. */
class TerminalFrameAssembler {
    val revision: Long                  // 0 before the first snapshot
    val awaitingSnapshot: Boolean       // from a gap until the next snapshot
    fun receive(part: TerminalFramePart): TerminalAssemblyResult
}
sealed interface TerminalCell {
    data object Blank : TerminalCell
    data class Glyph(val text: String, val width: Int, val style: TerminalCellStyle) : TerminalCell
    data object Continuation : TerminalCell          // the second column of a wide cell
}
data class TerminalStyledRun(val x: Int, val text: String, val width: Int? = null, val style: TerminalCellStyle = TerminalCellStyle.DEFAULT)
/** Immutable. A row keeps its object while it moves from the screen into history (the renderer caches by object). */
data class TerminalRow(val runs: List<TerminalStyledRun> = emptyList()) {
    fun cells(cols: Int): List<TerminalCell>         // exactly cols entries; a later run overwrites an earlier one cell by cell
    fun text(cols: Int): String                      // PROTOCOL.md §8's row text rule
}
/** PROTOCOL.md 11.6 and the receiver rules of 11.5. Mutable: its owner applies frames and reads it on the same thread. */
class TerminalScreen(val maxHistoryRows: Int = DEFAULT_MAX_HISTORY_ROWS) {
    companion object { const val DEFAULT_MAX_HISTORY_ROWS = 10_000 }
    val cols: Int; val rows: Int; val alt: Boolean   // 0, 0, false before the first snapshot
    val cursor: TerminalCursor?                       // moved into the grid
    val palette: TerminalPalette?
    val screenRows: List<TerminalRow>                 // `rows` entries
    val historyRows: List<TerminalRow>                // oldest first, at most maxHistoryRows
    fun apply(frame: TerminalGridFrame)
    fun cell(x: Int, y: Int): TerminalCell            // y >= 0: a screen row; y < 0: history from the newest (-1)
    fun screenText(): List<String>
    fun historyText(): List<String>
}
```

  A Unicode scalar is a code point (`String.codePointAt` and `Character.charCount`), and sizes count UTF-8 bytes. History is a `kotlin.collections.ArrayDeque` that drops from the front. A delta moves the row objects it scrolls; it never copies them.

- [ ] **Step 1: Write the failing tests.**
  - `TerminalVectorTest.screens`, the port of `testScreens`. The helpers are private: `withPalette(frame, palette)` replaces a head `palette` equal to `"@palette"` with the file's top-level `palette`; `cursor(o)` builds a `TerminalCursor`; `expectedCell(o)` builds, by the entry's `kind` (2A's `{x, y, kind}`), `Blank` (`blank`), `Continuation` (`continuation`), or `Glyph(t, w, style)` (`glyph`), where `style` is `TerminalCellStyle(fg, fgRgb, bg, bgRgb, attrs)` and an absent one is `DEFAULT`.

```kotlin
@Test fun screens() {
    val palette = file.getValue("palette")
    val screens = file.getValue("screens").jsonArray.map { it.jsonObject }
    assertEquals(17, screens.size)
    for (s in screens) {
        val name = s.getValue("name").jsonPrimitive.content
        val assembler = TerminalFrameAssembler()
        val screen = TerminalScreen(s["max_history_rows"]?.jsonPrimitive?.int ?: TerminalScreen.DEFAULT_MAX_HISTORY_ROWS)
        var resyncs = 0
        for (f in s.getValue("frames").jsonArray) {
            val bytes = Json.encodeToString(JsonObject.serializer(), withPalette(f.jsonObject, palette)).encodeToByteArray()
            val message = assertIs<LinkMessage.TerminalViewFrame>(LinkCodec.decode(bytes), name)
            assertEquals("t-1", message.terminalId, name)
            val result = assembler.receive(message.frame)
            if (result.resync) resyncs++
            result.frame?.let(screen::apply)
        }
        val e = s.getValue("expect").jsonObject
        assertEquals(e.getValue("revision").jsonPrimitive.long, assembler.revision, name)
        assertEquals(e.getValue("resyncs").jsonPrimitive.int, resyncs, name)
        assertEquals(e.getValue("cols").jsonPrimitive.int, screen.cols, name)
        assertEquals(e.getValue("rows").jsonPrimitive.int, screen.rows, name)
        assertEquals(e.getValue("alt").jsonPrimitive.boolean, screen.alt, name)
        e["cursor"]?.let { assertEquals(cursor(it.jsonObject), screen.cursor, name) }
        assertEquals(e.getValue("screen").jsonArray.map { it.jsonPrimitive.content }, screen.screenText(), name)
        assertEquals(e.getValue("history").jsonArray.map { it.jsonPrimitive.content }, screen.historyText(), name)
        e["cells"]?.jsonArray?.forEach { c ->
            val o = c.jsonObject
            assertEquals(expectedCell(o), screen.cell(o.getValue("x").jsonPrimitive.int, o.getValue("y").jsonPrimitive.int), "$name $o")
        }
    }
}
```

  - `TerminalScreenTest`: the three ports of `TerminalScreenTests.swift`, then two Kotlin tests. `snapshot(cols, rows, text, history = emptyList())` and `delta(cols, rows, replacing, scroll = 0)` are private helpers that build whole frames like 2A's `snapshotFrame` / `deltaFrame` (cursor (0, 0), a palette of 256 greys):

```kotlin
class TerminalScreenTest {
    @Test fun rowTextSkipsTheSecondColumnOfAWideCell() {
        val row = TerminalRow(listOf(TerminalStyledRun(0, "a"), TerminalStyledRun(1, "中", width = 2)))
        assertEquals("a中", row.text(5))
        val d = TerminalCellStyle.DEFAULT
        assertEquals(listOf(TerminalCell.Glyph("a", 1, d), TerminalCell.Glyph("中", 2, d), TerminalCell.Continuation,
            TerminalCell.Blank, TerminalCell.Blank), row.cells(5))
    }
    @Test fun laterRunOverwritesCellByCell() {
        assertEquals("aZc", TerminalRow(listOf(TerminalStyledRun(0, "abc"), TerminalStyledRun(1, "Z"))).text(3))
    }
    @Test fun screenStartsEmpty() {
        val s = TerminalScreen()
        assertEquals(0, s.cols); assertNull(s.cursor); assertEquals(emptyList(), s.screenText()); assertEquals(emptyList(), s.historyText())
    }
    @Test fun historyKeepsAtMostMaxRowsDroppingTheOldest() {
        val s = TerminalScreen(maxHistoryRows = 3)
        s.apply(snapshot(10, 1, listOf("x"), history = listOf("h1", "h2", "h3", "h4", "h5")))
        assertEquals(listOf("h3", "h4", "h5"), s.historyText())
    }
    @Test fun aRowThatScrollsIntoHistoryIsTheSameObject() {
        val s = TerminalScreen(); s.apply(snapshot(10, 2, listOf("a", "b")))
        val top = s.screenRows[0]; val bottom = s.screenRows[1]
        s.apply(delta(10, 2, replacing = mapOf(1 to "c"), scroll = 1))
        assertSame(top, s.historyRows.last()); assertSame(bottom, s.screenRows[0])
    }
}
```

- [ ] **Step 2: Run (red).** Run `gwl :link-core:test --tests 'com.shellx.link.core.TerminalVectorTest' --tests 'com.shellx.link.core.TerminalScreenTest'`. Expected: `BUILD FAILED`, `Unresolved reference: TerminalFrameAssembler`.
- [ ] **Step 3: Commit the tests.** `git add shellx-link/kotlin/link-core/src/test` and `git commit -m "test(shellx-link): Kotlin terminal screens against the vectors"`.
- [ ] **Step 4: Implement** both files by porting the Swift bodies.
- [ ] **Step 5: Run (green).** Run the Step 2 command. Expected: PASS; `counts link TerminalVectorTest TerminalScreenTest` shows 6 and 5.
- [ ] **Step 6: Commit.** `git add shellx-link/kotlin/link-core/src/main` and `git commit -m "feat(shellx-link): Kotlin terminal frame assembler and screen model"`.

---

### Task 4: link-core — terminal calls on `LinkSession` and `LinkClient`

**Files:**
- Modify: `link/LinkSession.kt`, `link/LinkClient.kt`
- Test: create `link-test/LinkClientTerminalTest.kt`

Reference: `swift-link/ShellXLinkSession/LinkClient.swift` (`terminalPushes`, `post`, the open record and its `.opened`, the five view methods, `createTerminal`); the client-facing tests in `swift-link-tests/ShellXLinkSessionTests/TerminalSessionTests.swift`.

**Interfaces:**
- Consumes: Tasks 1–3; 3B's `LinkClient` internals (`call`, the reader, `end`, the channels), `HostRig` and `within`/`eventually` in the tests.
- Produces:

```kotlin
// LinkSession.kt
/** A terminal push from the host, in arrival order. */
sealed interface TerminalViewPush {
    val terminalId: String
    /** This session's open of terminalId was answered OK: start a fresh assembler; every later frame of it is the new view's. */
    data class Opened(override val terminalId: String) : TerminalViewPush
    data class Frame(override val terminalId: String, val part: TerminalFramePart) : TerminalViewPush
    data class Ended(override val terminalId: String, val reason: TerminalViewEndReason) : TerminalViewPush
}
data class TerminalCreated(val outcome: WorkspaceControlOutcome, val terminalId: String?)
interface LinkSession {
    // … 3B's members unchanged, then these, with defaults so that 3C's fakes and wrappers keep compiling:
    /** Every terminal.view.frame and terminal.view.ended, and Opened right before the first frame of a view this session
     *  opened, in arrival order. Single consumer; completes when the session ends. */
    val terminalPushes: Flow<TerminalViewPush> get() = emptyFlow()
    /** terminal.view.open. On OK, Opened(terminalId) is on terminalPushes before this returns. Remote("unsupported") from a
     *  host without terminal_view; Remote("bad_request") for cols or rows below 1. */
    suspend fun openTerminalView(terminalId: String, cols: Int, rows: Int): TerminalViewOpenOutcome =
        throw LinkClientException.Remote("unsupported", "this session has no terminal views")
    /** The four below send without an answer; SessionClosed when the session has ended. */
    suspend fun closeTerminalView(terminalId: String) {}
    /** TerminalInputCheck first: TerminalInputException, and nothing is sent. */
    suspend fun sendTerminalInput(terminalId: String, units: List<TerminalInputUnit>) {}
    suspend fun resizeTerminalView(terminalId: String, cols: Int, rows: Int) {}
    suspend fun resyncTerminalView(terminalId: String) {}
    /** terminal.create; terminalId only with OK, as the host sends it. */
    suspend fun createTerminal(workspaceId: String): TerminalCreated =
        throw LinkClientException.Remote("unsupported", "this session takes no terminal creation")
}
// LinkClient overrides all seven, and gains
internal suspend fun post(message: LinkMessage)
```

  `LinkClient` rules:
  - **`post`.** When the session has ended, throw its end error. Otherwise `channel.send(message)`: a `LinkCodecException` propagates, and any other failure becomes `SessionClosed()`.
  - **The open record.** `openTerminalView` calls `call { id -> records[id] = terminalId; TerminalViewOpen(id, terminalId, cols, rows) }`. `records` is guarded by the call lock, and the record goes in the call's `finally`. The reader, for a `TerminalViewOpenResult` with `OK` and a record, `trySend`s `Opened(terminalId)` on the terminal channel before it completes the waiter. A late `OK` for a call that already ended has no record, so it yields no `Opened`.
  - **The reader.** `TerminalViewFrame(id, part)` → `Frame(id, part)`; `TerminalViewEnded(id, reason)` → `Ended(id, reason)`, both on a fifth `Channel(UNLIMITED)`; the client-only terminal types are ignored. `end(error)` closes the fifth channel with the other four.
  - **The answers.** `openTerminalView` returns the outcome of `TerminalViewOpenResult`; `createTerminal` returns `TerminalCreated(outcome, terminalId)` from `TerminalCreateResult`. Any other answer → `UnexpectedAnswer()`.

- [ ] **Step 1: Write the failing tests** in `LinkClientTerminalTest`. Each comment line is a `@Test`, written in 3B's style (`val host = async { rig.host() }; val client = rig.client(); val (ch, _) = host.await()`, then scripting `ch`), with `HostRig(features = listOf("terminal_view", "terminal_create"))` unless the line says otherwise. `snap` is `TerminalFramePart(1, head = TerminalFrameHead(SNAPSHOT, 20, 1, cursor = TerminalCursor(0, 0), palette = <256 greys>), lines = listOf(TerminalLine(0, listOf(TerminalRun(text = "$")))))`:

```kotlin
class LinkClientTerminalTest {
    // openAnswersOkAndOpenedComesBeforeTheFirstFrame: the host receives TerminalViewOpen(id, "t-1", 46, 30), answers
    //   TerminalViewOpenResult(id, OK), then TerminalViewFrame("t-1", snap) → openTerminalView returns OK and
    //   terminalPushes.take(2).toList() == [Opened("t-1"), Frame("t-1", snap)]
    // anOpenThatIsNotOkYieldsNoOpened: answers BUSY, NOT_FOUND, REFUSED, FAILED and TerminalViewOpenOutcome("later") come back as
    //   they are; then the host sends TerminalViewEnded("t-1", GONE) → the first push is Ended("t-1", GONE)
    // openErrorsAreRemote: Error("unsupported", "no views", id) → Remote("unsupported", "no views");
    //   Error("bad_request", "cols", id) → Remote("bad_request", "cols")
    // aLateOkOfATimedOutOpenYieldsNoOpened: requestTimeout 300 ms; the host holds the answer → TimedOut; then it answers OK
    //   for that id and sends TerminalViewEnded("t-1", GONE) → the first push is Ended("t-1", GONE)
    // framesAndEndsArriveInOrder: Frame("t-1", snap), Frame("t-1", a revision-2 delta), TerminalViewEnded("t-2", NOT_OPEN) →
    //   the three pushes in that order
    // callLessMessagesReachTheHost: closeTerminalView("t-1"), resizeTerminalView("t-1", 80, 24), resyncTerminalView("t-1"),
    //   sendTerminalInput("t-1", [Text("ls"), Key(ENTER)]) → the host receives TerminalViewClose("t-1"),
    //   TerminalViewResize("t-1", 80, 24), TerminalViewResync("t-1"), TerminalViewInput("t-1", [Text("ls"), Key(ENTER)]) in order
    // aTypedNewlineIsRefusedBeforeSending (2A Review Focus 2): sendTerminalInput("t-1", [Text("ls\n")]) throws
    //   TerminalInputException with "ls" in neither reason nor message; then resyncTerminalView("t-1") → the host's next
    //   receive() is TerminalViewResync("t-1")
    // createTerminalUnpacksItsAnswer: TerminalCreate(id, "ws-1") answered TerminalCreateResult(id, OK, "t-9") → TerminalCreated(OK, "t-9");
    //   answered (id, REFUSED) → TerminalCreated(REFUSED, null); answered ChatSendResult(id, SUBMITTED) → UnexpectedAnswer
    // closeCompletesTerminalPushesAndLaterSendsThrow: client.close() → terminalPushes.toList() completes;
    //   closeTerminalView("t-1") throws SessionClosed
    // anUndecodableFrameIsDroppedAndTheNextArrives: ch.sendFrame("""{"v":1,"t":"terminal.view.frame","terminal_id":"t-1",
    //   "revision":0,"part":0,"parts":1}""") then Frame("t-1", snap) → the first push is Frame("t-1", snap)
}
```

- [ ] **Step 2: Run (red).** Run `gwl :link-core:test --tests 'com.shellx.link.core.LinkClientTerminalTest'`. Expected: `BUILD FAILED`, `Unresolved reference: terminalPushes`.
- [ ] **Step 3: Commit the tests.** `git add shellx-link/kotlin/link-core/src/test` and `git commit -m "test(shellx-link): Kotlin client terminal views and terminal.create"`.
- [ ] **Step 4: Implement** the rules above.
- [ ] **Step 5: Run (green).** Run `gwl :link-core:test` three times. Expected: PASS each time; `counts link LinkClientTerminalTest` shows 10. Then `shellx-android/scripts/dev.sh test link`. Expected: `==> test link: passed`.
- [ ] **Step 6: Commit.** `git add shellx-link/kotlin/link-core/src/main` and `git commit -m "feat(shellx-link): Kotlin terminal views and terminal.create on LinkSession"`.

---

### Task 5: core — the fake Mac's terminals and the demo screens

**Files:**
- Create: `core/demo/DemoTerminalScreens.kt`, `core/demo/FakeMacTerminals.kt` (internal)
- Modify: `core/demo/FakeMac.kt`, `core/demo/FakeMacSession.kt`, `core/demo/FakeMacWorkspaces.kt`
- Create (test kit): `core-test/testing/TerminalTestSupport.kt`
- Test: create `core-test/demo/DemoTerminalScreensTest.kt`, `core-test/demo/FakeMacTerminalsTest.kt`; modify `core-test/demo/FakeMacTest.kt`

Reference: `<DEMO_PKG>/DemoTerminalScreens.swift` and `FakeMacTerminals.swift` (2C Task 1's rules 1–6 and fixture table); `ios-core-tests/DemoTerminalScreensTests.swift`, `FakeMacTerminalsTests.swift`, `Support/TerminalTestSupport.swift`; the host rules of PROTOCOL.md §11.1–11.3 and `swift-link/ShellXLinkSession/TerminalViewSlot.swift`. On Android there is no `LinkHost`: the fake Mac's session is the host the phone talks to (3C Task 8).

**Interfaces:**
- Consumes: Tasks 1–4; 3C's `FakeMac`, `FakeMacSession`, `FakeMacWorkspaces`, `com.shellx.core.text.graphemes()`.
- Produces (`com.shellx.core.demo`; everything public that the app or a test uses):

```kotlin
data class DemoTerminalFixture(
    val cols: Int, val rows: Int, val alt: Boolean = false,
    val palette: TerminalPalette = DemoTerminalScreens.PALETTE, val styles: List<TerminalStyle> = DemoTerminalScreens.STYLES,
    val history: List<List<TerminalRun>> = emptyList(),          // oldest first, main screen only
    val screen: List<List<TerminalRun>>,                          // from the top; rows past the end are blank
    val cursor: TerminalCursor,
    val prompt: List<TerminalRun>? = null,                        // a shell: screen[cursor.y] is this prompt
    val ticks: List<List<TerminalRun>> = emptyList(), val tickInterval: Duration? = null,
) { val snapshot: TerminalGridFrame }                             // 2C's DemoTerminalFixture.snapshot
object DemoTerminalScreens {
    val PALETTE: TerminalPalette; val STYLES: List<TerminalStyle>
    fun xterm256(base: List<String>): List<String>
    fun runs(markup: String): List<TerminalRun>
    val SHELL: DemoTerminalFixture; val SHELL_TYPING: TerminalGridFrame; val DEV_SERVER: DemoTerminalFixture
    val WIDE: DemoTerminalFixture; val VIM: DemoTerminalFixture; val HTOP: DemoTerminalFixture; val AGENT: DemoTerminalFixture
    fun prompt(cols: Int, rows: Int): DemoTerminalFixture
}
// FakeMac: constructor gains, after acceptsTerminalClose, `servesTerminalViews: Boolean = true, acceptsTerminalCreate: Boolean = true`
data class TerminalViewSize(val terminalId: String, val cols: Int, val rows: Int)   // nested: FakeMac.TerminalViewSize
fun setTerminalFixtures(fixtures: Map<String, DemoTerminalFixture>)                  // by terminal id; others get prompt(cols, rows)
fun refuseTerminalView(terminalId: String, outcome: TerminalViewOpenOutcome)
fun holdTerminalViewOpens(); fun releaseTerminalViewOpens()
fun emitTerminalFrame(terminalId: String, frame: TerminalGridFrame)                   // to that terminal's current views
fun endTerminalView(terminalId: String, reason: TerminalViewEndReason)
fun setNextTerminalCreateOutcome(outcome: WorkspaceControlOutcome)
val terminalViewOpens: List<TerminalViewSize>; val terminalViewResizes: List<TerminalViewSize>; val terminalViewCloses: List<String>
fun terminalViewInputs(terminalId: String): List<List<TerminalInputUnit>>
fun terminalViewSnapshotRequests(terminalId: String): Int
val terminalCreates: List<String>                                                    // workspace ids, in order
// FakeMacWorkspaces (internal): fun listsTerminal(terminalId: String): Boolean; fun addTerminal(workspaceId: String): String?
// core-test/testing/TerminalTestSupport.kt
class Collector<T>(flow: Flow<T>, scope: CoroutineScope) { val items: List<T> }
/** Reads pushes as they come; screen is the newest view of terminalId (a fresh assembler and screen at each Opened(terminalId)). */
class TerminalPushReader(pushes: Flow<TerminalViewPush>, terminalId: String, scope: CoroutineScope) {
    val pushes: List<TerminalViewPush>; val screen: TerminalScreen
}
```

  **The fake Mac's session as the host:**

  | Call | Answer |
  | --- | --- |
  | `openTerminalView(id, cols, rows)` | cols or rows < 1 → `Remote("bad_request", "cols and rows must be at least 1")`. Without `servesWorkspaces && servesTerminalViews` → `Remote("unsupported", "this host offers no terminal views")`. The session views another terminal → `BUSY`, nothing recorded. The same terminal → its view closes (recorded in `terminalViewCloses`), then as a new open. A new open is 2C Task 1's rule 1, after clamping into `TERMINAL_COLUMNS` and `TERMINAL_ROWS`. With a view: the session's `terminalPushes` gets `Opened(id)` before the call returns `OK`, then the view's snapshot at revision 1 |
  | frames | Revision +1 per frame of a view. Each frame is one part (`part` 0 of 1): in memory there is no frame limit. A snapshot carries the fixture's whole history (no history frames). A delta is 2C Task 1's rule 2 |
  | `sendTerminalInput(id, units)` | `TerminalInputCheck.check` (throws, nothing recorded); not the session's view → `Ended(id, NOT_OPEN)`; otherwise recorded and applied by rule 3 (the fake shell), then a delta when the content changed |
  | `resizeTerminalView(id, cols, rows)` | cols or rows < 1 → nothing; not viewed → `Ended(id, NOT_OPEN)`; otherwise clamped and recorded (the fake keeps its fixture's size) |
  | `resyncTerminalView(id)` | not viewed → `Ended(id, NOT_OPEN)`; otherwise counted in `terminalViewSnapshotRequests`, then a snapshot |
  | `closeTerminalView(id)` | the viewed terminal → its view closes (recorded); any other → nothing |
  | the session closes, `dropLiveSessions()` | its view closes (recorded) |
  | `endTerminalView(id, reason)` | every session viewing `id` gets `Ended(id, reason)`, and those views close (recorded) |
  | `emitTerminalFrame(id, frame)` | the next revision of every view of `id` |
  | ticks | rule 5, with `delay` in the FakeMac's scope |
  | `createTerminal(workspaceId)` | without `servesWorkspaces && acceptsTerminalCreate` → `Remote("unsupported", "this host takes no terminal creation")`; otherwise rule 6, answering `TerminalCreated` |
  | `hostFeatures` | 3C's, plus `terminal_view` when `servesWorkspaces && servesTerminalViews`, and `terminal_create` when `servesWorkspaces && acceptsTerminalCreate` |

  Every terminal call counts in `phoneCallCount`; collecting `terminalPushes` does not. Each session's pushes go through its own `Channel(UNLIMITED)`, closed when the session ends.

  **`DemoTerminalScreens`** ports every literal of `DemoTerminalScreens.swift`. `runs(markup)` walks graphemes (`graphemes()`), and uses the Swift's East Asian wide ranges. Java 17 has no Emoji_Presentation property, so a grapheme is also wide when its first code point is in U+1F1E6–1F1FF, U+1F300–1F64F, U+1F680–1F6FF, U+1F900–1F9FF or U+1FA70–1FAFF, or is one of U+231A, 231B, 23E9–23EC, 23F0, 23F3, 25FD, 25FE, 2614, 2615, 2648–2653, 267F, 2693, 26A1, 26AA, 26AB, 26BD, 26BE, 26C4, 26C5, 26CE, 26D4, 26EA, 26F2, 26F3, 26F5, 26FA, 26FD, 2705, 270A, 270B, 2728, 274C, 274E, 2753–2755, 2757, 2795–2797, 27B0, 27BF, 2B1B, 2B1C, 2B50, 2B55.

- [ ] **Step 1: Write the failing tests.**
  - **`DemoTerminalScreensTest`.** Port the four tests of `DemoTerminalScreensTests.swift`. In `everyFixtureSplitsAndAssemblesIntoItself`, each fixture's snapshot goes to the assembler as one part (`TerminalFramePart(1, 0, 1, head, styles, lines)`); there is no splitter. Then add:

```kotlin
@Test fun fixtureCharactersHaveTheIPhoneWidths() {
    for (w in listOf("中", "：", "ー", "한", "🚀", "✅", "👍🏽", "🇻🇳", "👨‍👩‍👧"))
        assertEquals(listOf(TerminalRun(text = w, width = 2)), DemoTerminalScreens.runs(w), w)
    for (n in listOf("✔", "➜", "✻", "●", "⎿", "╭", "─", "ắ", "·"))
        assertEquals(listOf(TerminalRun(text = n)), DemoTerminalScreens.runs(n), n)
    assertEquals(listOf(TerminalRun(text = "e\u0301", width = 1)), DemoTerminalScreens.runs("e\u0301"))
}
```

  - **`FakeMacTerminalsTest`.** Port the nine tests of `FakeMacTerminalsTests.swift`, reading pushes with `TerminalPushReader(session.terminalPushes, …, backgroundScope)`. Then add these five; each comment line is a `@Test`:

```kotlin
// anotherTerminalIsBusyAndTheSameOneRestarts: open t1 → OK; open t2 → BUSY and terminalViewOpens holds only t1; open t1 again → OK,
//   terminalViewCloses == ["t1"], and the reader's newest view starts again at revision 1
// openedComesBeforeTheFirstFrame: after an open, the pushes start with Opened("t1"), then Frame("t1", part) with revision 1 and
//   head kind SNAPSHOT
// sizesAreClampedAndNonPositiveOnesRefused: open 10 × 2 → terminalViewOpens == [TerminalViewSize("t1", 20, 5)]; resize 999 × 999
//   → terminalViewResizes == [TerminalViewSize("t1", 300, 120)]; openTerminalView("t1", 0, 24) throws Remote("bad_request", …)
// inputResizeAndResyncOfAnotherTerminalAreNotOpen: viewing t1, input, resize and resync for t2 → three Ended("t2", NOT_OPEN);
//   terminalViewInputs("t2") and terminalViewSnapshotRequests("t2") stay empty and 0
// sessionEndClosesTheView: a session views t1, a second views t2; the first closes → terminalViewCloses == ["t1"];
//   dropLiveSessions() → ["t1", "t2"]
```

  - **`FakeMacTest.featuresFollowWhatTheMacServes`.** The default set gains `"terminal_view"` and `"terminal_create"`, and so does the `servesSessionsAndChat = false` set; `servesWorkspaces = false` stays `setOf("attachments", "agent_close")`. Add `servesTerminalViews = false` → no `"terminal_view"`, and `acceptsTerminalCreate = false` → no `"terminal_create"`. Fix any other 3C test that lists the whole feature set the same way (`grep -rn 'terminal_close"' shellx-android/core/src/test`).
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.demo.*'`. Expected: `BUILD FAILED`, `Unresolved reference: DemoTerminalScreens`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): the fake Mac's terminals and the demo terminal screens"`.
- [ ] **Step 4: Implement** the files listed, as Interfaces and 2C Task 1's rules say.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS each time; `counts core demo.DemoTerminalScreensTest demo.FakeMacTerminalsTest demo.FakeMacTest` shows 5, 14 and 11. Then `shellx-android/scripts/dev.sh test core`. Expected: `==> test core: passed`.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main` and `git commit -m "feat(shellx-android): fake Mac terminals and demo terminal screens"`.

---

### Task 6: core — terminal views through the hub

**Files:**
- Create: `core/terminal/TerminalLink.kt`, `core/link/HubTerminals.kt` (internal)
- Modify: `core/link/MachineEvent.kt`, `core/link/MachineConnection.kt`, `core/link/MachineHub.kt`, `core/link/HubState.kt`, `core/diagnostics/LatencyLog.kt`, `core-test/testing/EventLog.kt`
- Test: create `core-test/link/MachineHubTerminalTest.kt`; modify `core-test/link/MachineConnectionTest.kt`

Reference: `ios-core/Terminal/TerminalLink.swift`, `ios-core/Link/MachineHub+Terminal.swift`, the terminal parts of `MachineConnection.swift` and `MachineHub.swift`; `ios-core-tests/MachineHubTerminalTests.swift`; 2C Task 2's "Behaviour".

**Interfaces:**
- Consumes: Task 4; Task 5's FakeMac (tests); 3C's `MachineHub` (`apply`, `revoke`, `detachAll`, `stopAll`, `chatUpdates()`, the private `withLink` and `workspaceCommand`), `HubState`, `MachineLinkState`, `WorkspaceRef`, `WorkspaceCommandResult`, `LinkCallException`, `LatencyLog`, `CoreLog`, `hubRig`, `EventLog`.
- Produces:

```kotlin
// com.shellx.core.terminal (TerminalLink.kt)
sealed interface TerminalHubEvent {
    data class Push(val machineId: String, val push: TerminalViewPush) : TerminalHubEvent
    /** Online comes again after every reconnect; a view opened before it is gone. */
    data class State(val machineId: String, val state: MachineLinkState) : TerminalHubEvent
}
sealed interface TerminalOpenResult {
    data class Outcome(val outcome: TerminalViewOpenOutcome) : TerminalOpenResult
    /** Nothing was sent: the Mac is not online or does not list terminal_view. */
    data object NotSent : TerminalOpenResult
    /** Sent, but no answer came: the session ended or the call timed out. */
    data object NoAnswer : TerminalOpenResult
}
data class TerminalCreation(val result: WorkspaceCommandResult, val terminalId: String?)
/** Main-confined. The hub as a terminal page uses it; MachineHub is the real one, tests script one. */
interface TerminalLink {
    fun terminalEvents(): Flow<TerminalHubEvent>
    fun isOnline(machineId: String): Boolean
    fun supportsTerminalView(machineId: String): Boolean
    suspend fun openTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int): TerminalOpenResult
    suspend fun closeTerminalView(machineId: String, terminalId: String)
    suspend fun sendTerminalInput(machineId: String, terminalId: String, units: List<TerminalInputUnit>)
    suspend fun resizeTerminalView(machineId: String, terminalId: String, cols: Int, rows: Int)
    suspend fun resyncTerminalView(machineId: String, terminalId: String)
    fun recordLatency(metric: LatencyMetric, duration: Duration)
}
// MachineEvent gains: data class Terminal(val push: TerminalViewPush) : MachineEvent
// LatencyMetric gains: TERMINAL_FIRST_SCREEN("terminalFirstScreen"), TERMINAL_KEY_ECHO("terminalKeyEcho"), TERMINAL_FRAME_APPLY("terminalFrameApply")
// HubState gains: fun supportsTerminalView(machineId: String): Boolean; fun supportsTerminalCreate(machineId: String): Boolean
// MachineHub becomes `: DecisionSending, TerminalLink`; its overrides delegate to HubTerminals; plus
fun supportsTerminalCreate(machineId: String): Boolean
suspend fun createTerminal(ref: WorkspaceRef): TerminalCreation
internal val terminalSubscriberCount: Int
```

  Behaviour (2C Task 2, in 3C's terms):
  - **`terminalEvents()`** works like `chatUpdates()`: each call registers a `Channel(UNLIMITED)` at once and returns it as a Flow; a collector that ends unregisters it; nothing is replayed.
  - **Publishing.** `apply` publishes `Push(model id, push)` for `MachineEvent.Terminal(push)`, and `State(id, state)` right after it sets a state. `revoke` publishes `State(id, Revoked)`. `detachAll` publishes `State(id, Reconnecting)` for each Mac it moves from `Online`. `stopAll` closes every terminal subscriber.
  - **Queries.** `isOnline` is `state == Online`. `supportsTerminalView` and `supportsTerminalCreate` read `hostFeatures`, as `supportsTerminalClose` does.
  - **`openTerminalView`.** A Mac not online, or without `terminal_view` → `NotSent`, and nothing is sent. Otherwise through `withLink`: the outcome → `Outcome`; `LinkCallException` → `NotSent`; `LinkClientException.Remote` → `Outcome(FAILED)`; any other non-cancellation exception → `NoAnswer`.
  - **The four call-less calls** use the same guard. Their errors are logged and swallowed: `CoreLog.log("terminal_send_failed")`, or `"terminal_input_refused"` for a `TerminalInputException`.
  - **`createTerminal`** runs through `workspaceCommand(ref.machineId, ShellXLink.TERMINAL_CREATE_FEATURE)`. Its body returns `WorkspaceCommandResult.of(created.outcome)` and keeps `created.terminalId` only when the outcome is `OK`.
  - **`recordLatency`** → `latency.record`.
  - **The hub's helpers.** `withLink` and `workspaceCommand` become `internal`, and `latency` an `internal val`.
  - **`MachineConnection.read`** gains a child `launch` that collects `session.terminalPushes` into `MachineEvent.Terminal(push)`. It is read even when no page shows a terminal: the client buffers without bound.
  - **Exhaustive `when`s.** Every exhaustive `when` over `MachineEvent` gains the `Terminal` branch. The test kit's `EventLog` keeps those pushes in `terminalPushes: List<TerminalViewPush>`.

- [ ] **Step 1: Write the failing tests.** Port the eight tests of `MachineHubTerminalTests.swift` into `MachineHubTerminalTest`, over `hubRig(listOf(mac), start = true)` with a FakeMac whose `ws-a` holds `t1` and `t2`; `mac.phoneFrameCount` becomes `mac.phoneCallCount`. Add to `MachineConnectionTest`:

```kotlin
@Test fun terminalPushesAreEventsInOrder() { runTest {
    // a FakeMac with ws-a holding t1; the connection online; then:
    connection.call { it.openTerminalView("t1", 30, 6) }
    assertTrue(eventually { log.terminalPushes.size >= 2 })
    assertEquals(TerminalViewPush.Opened("t1"), log.terminalPushes[0])
    assertIs<TerminalViewPush.Frame>(log.terminalPushes[1])
} }
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.link.MachineHubTerminalTest' --tests 'com.shellx.core.link.MachineConnectionTest'`. Expected: `BUILD FAILED`, `Unresolved reference: terminalEvents`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): terminal views through the machine hub"`.
- [ ] **Step 4: Implement** the files and changes listed.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts core link.MachineHubTerminalTest link.MachineConnectionTest` shows 8 and 19. Then `shellx-android/scripts/dev.sh test core`. Expected: `==> test core: passed`.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main shellx-android/core/src/test/kotlin/com/shellx/core/testing` and `git commit -m "feat(shellx-android): terminal views through the machine hub"`.

---

### Task 7: core — typing, input batching and Android hardware keys

**Files:**
- Create: `core/terminal/TerminalTextInput.kt`, `core/terminal/TerminalTyping.kt`, `core/terminal/TerminalInputBatcher.kt`, `core/terminal/TerminalHardwareKeys.kt`
- Test: create `core-test/terminal/TerminalTypingTest.kt`, `core-test/terminal/TerminalInputBatcherTest.kt`, `core-test/terminal/TerminalHardwareKeysTest.kt`

Reference: `ios-core/Terminal/TerminalTyping.swift`, `TerminalInputBatcher.swift`, `TerminalHardwareKeys.swift` (2C Task 3's algorithms); `ios-core-tests/TerminalTypingTests.swift`, `TerminalInputBatcherTests.swift`.

**Interfaces:**
- Consumes: Task 1; 3C's `com.shellx.core.text` (`graphemes()`, `utf8Size`).
- Produces (`com.shellx.core.terminal`):

```kotlin
/** The keyboard's calls in the iPhone's words (marked text = Android's composing text). TerminalViewModel implements it. */
interface TerminalTextInput {
    val markedText: String
    fun insertText(text: String)
    fun setMarkedText(text: String)
    fun unmarkText()
    fun deleteBackward()
    fun press(key: TerminalKey, mods: List<TerminalModifier> = emptyList())
    fun paste(text: String)
}
/** 2C's TerminalTyping, its algorithm as given there. Mutable, one owner. */
class TerminalTyping(markedText: String = "", ctrlLatched: Boolean = false) {
    val markedText: String; val ctrlLatched: Boolean
    fun toggleCtrl()
    fun insert(text: String): List<TerminalInputUnit>
    fun setMarked(text: String): List<TerminalInputUnit>
    fun unmark(): List<TerminalInputUnit>
    fun deleteBackward(): List<TerminalInputUnit>
    fun key(key: TerminalKey, mods: List<TerminalModifier> = emptyList()): List<TerminalInputUnit>
}
object TerminalInputBatcher {
    const val MAX_PASTE_BYTES = 262_144
    fun messages(units: List<TerminalInputUnit>): List<List<TerminalInputUnit>>   // cuts at grapheme boundaries
    fun pasteUnits(text: String): List<TerminalInputUnit>
    /** True when the cleaned paste (as pasteUnits would send it) is at most MAX_PASTE_BYTES UTF-8 bytes. */
    fun pasteFits(text: String): Boolean
    fun scrollUnits(lines: Int): List<TerminalInputUnit>
}
/** android.view.KeyEvent's values; app-test pins each one against KeyEvent. */
object TerminalKeyCodes {
    const val DPAD_UP = 19; const val DPAD_DOWN = 20; const val DPAD_LEFT = 21; const val DPAD_RIGHT = 22
    const val TAB = 61; const val SPACE = 62; const val ENTER = 66; const val DEL = 67; const val PAGE_UP = 92
    const val PAGE_DOWN = 93; const val ESCAPE = 111; const val FORWARD_DEL = 112; const val MOVE_HOME = 122
    const val MOVE_END = 123; const val NUMPAD_ENTER = 160
}
data class TerminalHardwareModifiers(val shift: Boolean = false, val ctrl: Boolean = false, val alt: Boolean = false, val meta: Boolean = false)
sealed interface TerminalHardwareAction {
    data class Send(val key: TerminalKey, val mods: List<TerminalModifier>) : TerminalHardwareAction
    data class Type(val text: String) : TerminalHardwareAction
    data object DeleteBackward : TerminalHardwareAction
    data object Paste : TerminalHardwareAction
    /** Not the terminal's: Back, volume, Meta shortcuts, function keys. */
    data object System : TerminalHardwareAction
}
object TerminalHardwareKeys {
    /** plainChar: the layout's character without ctrl, alt and meta (0 when none); altChar: with alt (0 when none). */
    fun action(keyCode: Int, plainChar: Int, altChar: Int, modifiers: TerminalHardwareModifiers): TerminalHardwareAction
}
/** The key bar's keys in its order; `key` null for CTRL, which latches for the next key. */
enum class TerminalBarKey(val key: TerminalKey?) { ESCAPE(TerminalKey.ESCAPE), TAB(TerminalKey.TAB), CTRL(null),
    LEFT(TerminalKey.LEFT), UP(TerminalKey.UP), DOWN(TerminalKey.DOWN), RIGHT(TerminalKey.RIGHT) }
```

  `TerminalHardwareKeys.action`. `mods` holds `CTRL`, `ALT`, `SHIFT` in that order, each when pressed. The first rule that matches wins:
  1. `meta` → `System`.
  2. `ESCAPE`, `TAB`, `DPAD_UP/DOWN/LEFT/RIGHT`, `MOVE_HOME`, `MOVE_END`, `PAGE_UP`, `PAGE_DOWN`, `FORWARD_DEL` → `Send(named key, mods)`.
  3. `ENTER`, `NUMPAD_ENTER` → with ctrl or alt, `Send(ENTER, mods)`; else `Type("\n")`.
  4. `DEL` → with ctrl or alt, `Send(BACKSPACE, mods)`; else `DeleteBackward`.
  5. `SPACE` with ctrl → `Send(SPACE, mods)`.
  6. ctrl, and `plainChar` an ASCII letter → `Paste` when shift is held and the letter is `v`; else `Send(letter(lowercase), mods)`. Ctrl with any other character → `System`.
  7. alt without ctrl → `altChar` ≠ 0: `Type(altChar)`; else `System`.
  8. `plainChar` ≠ 0 → `Type(plainChar)`.
  9. Otherwise → `System`.

- [ ] **Step 1: Write the failing tests.** Port `TerminalTypingTests.swift` (12 tests) and `TerminalInputBatcherTests.swift` (8 tests, `pasteLimitIs256KiB` included with its values: 262 144 `a` fit, 262 145 do not, 262 144 `a` plus `"\u001b"` fit). Write `TerminalHardwareKeysTest`:

```kotlin
class TerminalHardwareKeysTest {
    private val K = TerminalKeyCodes
    private val ctrl = TerminalHardwareModifiers(ctrl = true); private val alt = TerminalHardwareModifiers(alt = true)
    private val shift = TerminalHardwareModifiers(shift = true); private val meta = TerminalHardwareModifiers(meta = true)
    private fun a(keyCode: Int, plain: Char? = null, altChar: Char? = plain, mods: TerminalHardwareModifiers = TerminalHardwareModifiers()) =
        TerminalHardwareKeys.action(keyCode, plain?.code ?: 0, altChar?.code ?: 0, mods)
    private fun send(key: TerminalKey, vararg mods: TerminalModifier) = TerminalHardwareAction.Send(key, mods.toList())
    private val System = TerminalHardwareAction.System

    @Test fun namedKeysAreSentWithTheirModifiers() {
        assertEquals(send(TerminalKey.ESCAPE), a(K.ESCAPE)); assertEquals(send(TerminalKey.TAB), a(K.TAB, '\t'))
        assertEquals(send(TerminalKey.TAB, TerminalModifier.SHIFT), a(K.TAB, '\t', mods = shift))
        assertEquals(listOf(send(TerminalKey.LEFT), send(TerminalKey.RIGHT), send(TerminalKey.UP), send(TerminalKey.DOWN)),
            listOf(K.DPAD_LEFT, K.DPAD_RIGHT, K.DPAD_UP, K.DPAD_DOWN).map { a(it) })
        assertEquals(send(TerminalKey.LEFT, TerminalModifier.ALT), a(K.DPAD_LEFT, mods = alt))
        assertEquals(send(TerminalKey.UP, TerminalModifier.CTRL, TerminalModifier.SHIFT),
            a(K.DPAD_UP, mods = TerminalHardwareModifiers(ctrl = true, shift = true)))
        assertEquals(listOf(send(TerminalKey.HOME), send(TerminalKey.END), send(TerminalKey.PAGE_UP), send(TerminalKey.PAGE_DOWN),
            send(TerminalKey.DELETE)), listOf(K.MOVE_HOME, K.MOVE_END, K.PAGE_UP, K.PAGE_DOWN, K.FORWARD_DEL).map { a(it) })
    }
    @Test fun ctrlLettersAreKeysByTheLayoutsLetter() {
        assertEquals(send(TerminalKey.letter('c'), TerminalModifier.CTRL), a(31, 'c', mods = ctrl))           // KEYCODE_C
        assertEquals(send(TerminalKey.letter('a'), TerminalModifier.CTRL, TerminalModifier.SHIFT),
            a(29, 'A', mods = TerminalHardwareModifiers(ctrl = true, shift = true)))                               // KEYCODE_A
        assertEquals(send(TerminalKey.letter('a'), TerminalModifier.CTRL), a(45, 'a', mods = ctrl))           // KEYCODE_Q on AZERTY
        assertEquals(System, a(8, '1', mods = ctrl))                                                           // KEYCODE_1
    }
    @Test fun ctrlVIsTheKeyAndCtrlShiftVPastes() {
        assertEquals(send(TerminalKey.letter('v'), TerminalModifier.CTRL), a(50, 'v', mods = ctrl))           // KEYCODE_V
        assertEquals(TerminalHardwareAction.Paste, a(50, 'V', mods = TerminalHardwareModifiers(ctrl = true, shift = true)))
    }
    @Test fun lettersReturnBackspaceAndSpaceGoThroughTyping() {
        assertEquals(TerminalHardwareAction.Type("c"), a(31, 'c')); assertEquals(TerminalHardwareAction.Type("C"), a(31, 'C', mods = shift))
        assertEquals(TerminalHardwareAction.Type("1"), a(8, '1'))
        assertEquals(TerminalHardwareAction.Type("\n"), a(K.ENTER)); assertEquals(TerminalHardwareAction.Type("\n"), a(K.NUMPAD_ENTER))
        assertEquals(TerminalHardwareAction.DeleteBackward, a(K.DEL)); assertEquals(TerminalHardwareAction.Type(" "), a(K.SPACE, ' '))
    }
    @Test fun returnBackspaceAndSpaceWithModifiersAreKeys() {
        assertEquals(send(TerminalKey.ENTER, TerminalModifier.CTRL), a(K.ENTER, mods = ctrl))
        assertEquals(send(TerminalKey.BACKSPACE, TerminalModifier.ALT), a(K.DEL, mods = alt))
        assertEquals(send(TerminalKey.SPACE, TerminalModifier.CTRL), a(K.SPACE, ' ', mods = ctrl))
    }
    @Test fun altTypesWhatTheLayoutGivesElseNothing() {
        assertEquals(TerminalHardwareAction.Type("å"), a(29, 'a', altChar = 'å', mods = alt))
        assertEquals(System, a(29, 'a', altChar = null, mods = alt))
    }
    @Test fun metaShortcutsFunctionKeysAndBackGoToTheSystem() {
        assertEquals(System, a(31, 'c', mods = meta)); assertEquals(System, a(K.ESCAPE, mods = meta))
        assertEquals(System, a(131)); assertEquals(System, a(4)); assertEquals(System, a(24))                // F1, BACK, VOLUME_UP
    }
    @Test fun keyBarOrderAndKeys() {
        assertEquals(listOf("ESCAPE", "TAB", "CTRL", "LEFT", "UP", "DOWN", "RIGHT"), TerminalBarKey.entries.map { it.name })
        assertEquals(listOf(TerminalKey.ESCAPE, TerminalKey.TAB, null, TerminalKey.LEFT, TerminalKey.UP, TerminalKey.DOWN,
            TerminalKey.RIGHT), TerminalBarKey.entries.map { it.key })
    }
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.terminal.*'`. Expected: `BUILD FAILED`, `Unresolved reference: TerminalTyping`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): terminal typing, input batching and hardware keys"`.
- [ ] **Step 4: Implement** the four files: `TerminalTyping` and the batcher port the Swift bodies; `TerminalHardwareKeys` follows the rules above.
- [ ] **Step 5: Run (green).** Run the Step 2 command. Expected: PASS; `counts core terminal.TerminalTypingTest terminal.TerminalInputBatcherTest terminal.TerminalHardwareKeysTest` shows 12, 8 and 8.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main` and `git commit -m "feat(shellx-android): terminal typing, input batching and hardware keys"`.

---

### Task 8: core — geometry, zoom, colours and the viewport

**Files:**
- Create: `core/terminal/TerminalGeometry.kt` (with `TerminalGridSize`, `TerminalScrollStep`, `TerminalZoom`), `core/terminal/TerminalColors.kt`, `core/terminal/TerminalViewport.kt`
- Test: create `core-test/terminal/TerminalGeometryTest.kt`, `TerminalZoomTest.kt`, `TerminalColorsTest.kt`, `TerminalViewportTest.kt`

Reference: `ios-core/Terminal/TerminalGeometry.swift`, `TerminalColors.swift`; `ios-core-tests/TerminalGeometryTests.swift` (both classes), `TerminalColorsTests.swift`; the "Surface" paragraph of 2C Task 8 (what the viewport replaces).

**Interfaces:**
- Consumes: Task 2 (`TerminalPalette`, `TerminalCellStyle`, `TerminalAttribute`).
- Produces (`com.shellx.core.terminal`; every length is in the caller's unit, px in the app):

```kotlin
data class TerminalGridSize(val cols: Int, val rows: Int)
data class TerminalScrollStep(val lines: Int, val carry: Float)
object TerminalGeometry {
    const val PADDING_DP = 4f
    const val MAX_ZOOM = 2f
    fun phoneGrid(viewportWidth: Float, viewportHeight: Float, cellWidth: Float, cellHeight: Float, padding: Float): TerminalGridSize
    fun fitScale(cols: Int, cellWidth: Float, viewportWidth: Float, padding: Float): Float
    fun scrollLines(translation: Float, carry: Float, lineHeight: Float, scale: Float): TerminalScrollStep
}
/** 2C's TerminalZoom. Immutable: each change returns the changed copy. */
data class TerminalZoom(val zoom: Float? = null, val cols: Int? = null) {
    fun gridChanged(cols: Int): TerminalZoom
    fun pinch(to: Float, fit: Float): TerminalZoom
    fun scale(fit: Float): Float
}
data class TerminalRgb(val red: Int, val green: Int, val blue: Int)
data class TerminalResolvedStyle(val foreground: TerminalRgb, val background: TerminalRgb?, val bold: Boolean, val italic: Boolean,
                                 val underline: Boolean, val strike: Boolean, val overline: Boolean, val drawsText: Boolean)
object TerminalColors {
    fun rgb(hex: String): TerminalRgb?
    fun foreground(palette: TerminalPalette): TerminalRgb; fun background(palette: TerminalPalette): TerminalRgb
    fun cursor(palette: TerminalPalette): TerminalRgb
    fun resolve(style: TerminalCellStyle, palette: TerminalPalette): TerminalResolvedStyle
}
/** Android only (the iPhone's UIScrollView keeps this): where the pane looks into the drawn grid. Immutable. */
data class TerminalViewport(
    val cellWidth: Float, val cellHeight: Float, val padding: Float,
    val width: Float = 0f, val height: Float = 0f,
    val cols: Int = 0, val shownRows: Int = 0,       // shownRows: history rows (main screen) plus screen rows
    val zoom: TerminalZoom = TerminalZoom(),
    val scrollX: Float = 0f, val scrollY: Float = 0f, // the content point at the viewport's top left
    val followsBottom: Boolean = true,
) {
    val fit: Float                    // TerminalGeometry.fitScale(cols, cellWidth, width, padding)
    val scale: Float                  // zoom.scale(fit)
    val contentWidth: Float           // 2 × padding + cols × cellWidth × scale
    val contentHeight: Float          // 2 × padding + shownRows × cellHeight × scale
    val maxScrollX: Float; val maxScrollY: Float      // max(0, content − size)
    /** The shown rows the viewport touches (0 = the oldest history row on the main screen); IntRange.EMPTY when none. */
    val visibleRows: IntRange
    fun resized(width: Float, height: Float): TerminalViewport
    /** The model changed: topShiftDelta rows were added above (negative: dropped from the top); toBottom: a new snapshot or typing. */
    fun contentChanged(cols: Int, shownRows: Int, topShiftDelta: Int, toBottom: Boolean): TerminalViewport
    fun scrolledBy(dx: Float, dy: Float): TerminalViewport
    fun pinched(factor: Float, focusX: Float, focusY: Float): TerminalViewport
}
```

  `TerminalViewport`'s rules:
  - Every result has `scrollX` in `0..maxScrollX` and `scrollY` in `0..maxScrollY`.
  - `resized` keeps the scroll, and a viewport that follows the bottom stays at `maxScrollY`.
  - `contentChanged` first applies `zoom.gridChanged(cols)`. With `toBottom` or `followsBottom` the result is at `maxScrollY` with `followsBottom = true`. Otherwise `scrollY` moves by `topShiftDelta × cellHeight × scale`.
  - `scrolledBy` adds `dx` and `dy`, then sets `followsBottom = scrollY >= maxScrollY - 0.5f`.
  - `pinched`: let `s0 = scale`. The new zoom is `zoom.pinch(s0 × factor, fit)`, and `s1` its scale. Then `scrollX' = (scrollX + focusX − padding) × s1 / s0 + padding − focusX`, and the same for `y`. Clamp, and set `followsBottom` as in `scrolledBy`.
  - `visibleRows`: with `rowHeight = cellHeight × scale`, from `floor((scrollY − padding) / rowHeight)` to `ceil((scrollY + height − padding) / rowHeight) − 1`, both clamped into `0 until shownRows`.

- [ ] **Step 1: Write the failing tests.** Port `TerminalGeometryTests` (3), `TerminalZoomTests` (3) and `TerminalColorsTests` (6) with padding `4f` (for example `phoneGrid(375f, 646f, 7.2f, 15f, 4f) == TerminalGridSize(50, 42)`). Write `TerminalViewportTest` with `fun v(cols: Int, rows: Int, w: Float = 200f, h: Float = 100f) = TerminalViewport(10f, 20f, 4f).resized(w, h).contentChanged(cols, rows, 0, toBottom = true)`:

```kotlin
class TerminalViewportTest {
    @Test fun aNewSnapshotOrTypingShowsTheBottom() {
        val p = v(10, 50).scrolledBy(0f, -300f).contentChanged(10, 50, 0, toBottom = true)
        assertEquals(908f, p.maxScrollY); assertEquals(908f, p.scrollY); assertTrue(p.followsBottom)  // 8 + 50 × 20 − 100
    }
    @Test fun scrolledUpTheViewKeepsItsRowsWhenHistoryGrowsAbove() {
        val p = v(10, 50).scrolledBy(0f, -300f); assertFalse(p.followsBottom)
        assertEquals(668f, p.contentChanged(10, 53, topShiftDelta = 3, toBottom = false).scrollY)          // 608 + 3 × 20
    }
    @Test fun scrolledUpTheViewKeepsItsRowsWhenRowsDropFromTheTop() {
        assertEquals(568f, v(10, 50).scrolledBy(0f, -300f).contentChanged(10, 50, topShiftDelta = -2, toBottom = false).scrollY)
    }
    @Test fun followingTheBottomStaysThereAsRowsArrive() {
        val p = v(10, 50).contentChanged(10, 51, 0, toBottom = false)
        assertEquals(p.maxScrollY, p.scrollY); assertEquals(928f, p.scrollY)
    }
    @Test fun aWiderGridFitsTheWidthAndANewWidthGoesBackToFit() {
        val wide = v(320, 30); assertEquals(192f / 3200f, wide.scale, 0.0001f)
        val zoomed = wide.pinched(10f, 0f, 0f); assertEquals(0.6f, zoomed.scale, 0.0001f)
        assertEquals(0.6f, zoomed.contentChanged(320, 30, 0, toBottom = false).scale, 0.0001f)
        assertEquals(192f / 1000f, zoomed.contentChanged(100, 30, 0, toBottom = false).scale, 0.0001f)
    }
    @Test fun aPinchKeepsThePointUnderTheFingers() {
        val p = v(40, 400, h = 300f).scrolledBy(0f, -1000f)
        val before = (p.scrollY + 150f - 4f) / p.scale
        val q = p.pinched(1.5f, 100f, 150f)
        assertEquals(before, (q.scrollY + 150f - 4f) / q.scale, 0.01f)
    }
    @Test fun aPinchStaysBetweenFitAndTwo() {
        val p = v(40, 30); assertEquals(p.fit, p.pinched(0.1f, 0f, 0f).scale); assertEquals(2f, p.pinched(100f, 0f, 0f).scale)
    }
    @Test fun visibleRowsCoverTheViewport() {
        val p = v(10, 100); val q = p.scrolledBy(0f, 504f - p.scrollY)
        assertEquals(504f, q.scrollY); assertEquals(25..29, q.visibleRows)
    }
    @Test fun aKeyboardThatShrinksThePaneKeepsTheBottom() {
        val p = v(10, 100, h = 300f).resized(200f, 150f)
        assertEquals(p.maxScrollY, p.scrollY); assertTrue(p.followsBottom)
    }
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.terminal.*'`. Expected: `BUILD FAILED`, `Unresolved reference: TerminalGeometry`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): terminal geometry, zoom, colours and viewport"`.
- [ ] **Step 4: Implement** the three files (geometry, zoom and colours port the Swift bodies).
- [ ] **Step 5: Run (green).** Run the Step 2 command. Expected: PASS; `counts core terminal.TerminalGeometryTest terminal.TerminalZoomTest terminal.TerminalColorsTest terminal.TerminalViewportTest` shows 3, 3, 6 and 9.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main` and `git commit -m "feat(shellx-android): terminal geometry, zoom, colours and viewport"`.

---

### Task 9: core — the terminal view model: lifecycle and frames

**Files:**
- Create: `core/terminal/TerminalViewModel.kt`
- Create (test kit): `core-test/testing/ScriptedTerminalLink.kt`, `core-test/testing/TerminalFixtures.kt`
- Test: create `core-test/terminal/TerminalViewModelTest.kt`, `core-test/terminal/TerminalViewLiveTest.kt`

Reference: `ios-core/Terminal/TerminalViewModel.swift`; 2C's "Rules of `TerminalViewModel`" (R1–R9 and the first-grid part of R11) with A1–A5 of this plan's Design; `ios-core-tests/TerminalViewModelTests.swift`, `TerminalViewLiveTests.swift`, `Support/TerminalTestSupport.swift` (`ScriptedTerminalLink`, frame helpers).

**Interfaces:**
- Consumes: Tasks 3, 6, 7, 8; 3C's `ManualSleeper`, `Gate`, `ManualClock`, `eventually`, `hubRig`.
- Produces (`com.shellx.core.terminal`; copy 2C's rules and A1–A5 into the class's KDoc):

```kotlin
enum class TerminalUnavailableReason { GONE, REFUSED, FAILED }
sealed interface TerminalViewPhase {
    data object Connecting : TerminalViewPhase      // opening, or waiting for the first screen
    data object Live : TerminalViewPhase
    data object Offline : TerminalViewPhase         // the last screen (if any) stays, dimmed
    data object Unsupported : TerminalViewPhase     // the Mac's ShellX shows no terminals
    data class Unavailable(val reason: TerminalUnavailableReason) : TerminalViewPhase
}
data class TerminalViewState(
    val terminalId: String? = null, val phase: TerminalViewPhase = TerminalViewPhase.Connecting,
    val screenRevision: Long = 0, val snapshots: Int = 0, val topShift: Int = 0,
    val markedText: String = "", val ctrlLatched: Boolean = false,
    val sentInputs: Int = 0, val pasteTooLarge: Int = 0,          // Task 10 raises the last two
)
/** Main-confined. One workspace screen's terminal (2C R1–R12, this plan's A1–A6). */
class TerminalViewModel(
    val machineId: String, link: TerminalLink, scope: CoroutineScope,
    maxHistoryRows: Int = TerminalScreen.DEFAULT_MAX_HISTORY_ROWS,
    sleep: suspend (Duration) -> Unit = { delay(it) },
    now: TimeSource.WithComparableMarks = TimeSource.Monotonic,
) {                                                               // Task 10 adds `: TerminalTextInput`
    companion object {
        val RESIZE_DELAY: Duration = 200.milliseconds; val BUSY_RETRY_DELAY: Duration = 300.milliseconds
        const val BUSY_RETRIES = 5; val FAILED_RETRY_DELAY: Duration = 1.seconds
        val SCROLL_COALESCING: Duration = 50.milliseconds; val ECHO_TIMEOUT: Duration = 2.seconds
        /** Shows `screen` in `phase` and sends nothing (render tests); never run. snapshots is 1 when screen has a size. */
        fun fixed(terminalId: String, screen: TerminalScreen = TerminalScreen(), phase: TerminalViewPhase = TerminalViewPhase.Live,
                  markedText: String = "", ctrlLatched: Boolean = false): TerminalViewModel
    }
    val state: StateFlow<TerminalViewState>
    val terminalId: String?; val phase: TerminalViewPhase; val screenRevision: Long; val snapshots: Int; val topShift: Int
    val markedText: String; val ctrlLatched: Boolean; val sentInputs: Int; val pasteTooLarge: Int
    /** The screen shown: replaced by show() of another terminal, changed in place by each frame. Main thread only. */
    val screen: TerminalScreen
    suspend fun run()
    fun show(terminalId: String?)
    fun setPhoneGrid(cols: Int, rows: Int)
    fun retry()
    fun close(): Job
    // Task 10: insertText, setMarkedText, unmarkText, deleteBackward, press, toggleCtrl, paste, scroll
}
// core-test/testing/ScriptedTerminalLink.kt: 2C's ScriptedTerminalLink in Kotlin
class ScriptedTerminalLink : TerminalLink {
    sealed interface Call {
        data class Open(val id: String, val cols: Int, val rows: Int) : Call; data class Close(val id: String) : Call
        data class Input(val id: String, val units: List<TerminalInputUnit>) : Call
        data class Resize(val id: String, val cols: Int, val rows: Int) : Call; data class Resync(val id: String) : Call
    }
    val calls: MutableList<Call>; var online: Boolean; var supportsViews: Boolean
    val openAnswers: MutableList<TerminalOpenResult>; var openGate: Gate?
    val samples: MutableList<Pair<LatencyMetric, Duration>>
    val latencies: List<LatencyMetric>; val opens: List<String>; val inputs: List<List<TerminalInputUnit>>
    fun emit(event: TerminalHubEvent)
}
// core-test/testing/TerminalFixtures.kt: val testPalette; fun snapshotPart(…); fun deltaPart(…); fun historyPart(…), as 2C's
```

  `fixed` uses a private link that is never online and supports nothing, and a scope it never launches in, so it is never active.

- [ ] **Step 1: Write the failing tests.**
  - **`TerminalViewModelTest`.** Port the 20 tests of `TerminalViewModelTests.swift`. `makeModel(link, sleeper, maxHistoryRows, clock)` builds `TerminalViewModel("m1", link, backgroundScope, maxHistoryRows, sleeper.sleep, clock.monotonic)` and launches `run()` in `backgroundScope`, returning the job too. Two tests change with A1:
    - `testBackgroundClosesAndForegroundReopens` becomes `stoppingTheRunClosesAndALaterRunReopens`. After `live(…)`, cancel the run job, then wait: `eventually { link.calls.last() == Call.Close("t1") }` and the screen still reads `"$"`. Launch `run()` again; then `eventually { link.opens == listOf("t1", "t1") }`.
    - `testBackgroundDuringTheOpenClosesAfterIt` becomes `stoppingDuringTheOpenClosesAfterIt`. Set `openGate`, then `show("t1")`, and wait for `opens == ["t1"]`. Cancel the run job, then `gate.open()`. Expect `calls == [Open("t1", 50, 20), Close("t1")]`. The opened push and a snapshot still leave the phase not `Live`.
  - `testARestartedRunKeepsTheViewOpen` stays as it is: `first.cancel()` and `backgroundScope.launch { model.run() }` in the same turn, then `advanceTimeBy(100.milliseconds)` → `calls == [Open("t1", 50, 20)]` (A2). Then add:

```kotlin
@Test fun closeQueuesTheCloseAndStopsForGood() { runTest {
    val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
    model.close().join()
    assertEquals(ScriptedTerminalLink.Call.Close("t1"), link.calls.last())
    model.show("t2"); model.setPhoneGrid(40, 10); runCurrent()
    assertFalse(link.opens.contains("t2"))
} }
```

  - **`TerminalViewLiveTest`.** Port the three tests of `TerminalViewLiveTests.swift` over `hubRig(listOf(mac), start = true)`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.terminal.TerminalView*'`. Expected: `BUILD FAILED`, `Unresolved reference: TerminalViewModel`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): terminal view model lifecycle and frames"`.
- [ ] **Step 4: Implement** `TerminalViewModel` per R1–R9, R11's first grid and A1–A5.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts core terminal.TerminalViewModelTest terminal.TerminalViewLiveTest` shows 21 and 3.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main` and `git commit -m "feat(shellx-android): terminal view model"`.

---

### Task 10: core — the terminal view model: typing, paste, scrolling and resizing

**Files:**
- Modify: `core/terminal/TerminalViewModel.kt`
- Test: create `core-test/terminal/TerminalViewModelInputTest.kt`; modify `core-test/terminal/TerminalViewLiveTest.kt`

Reference: 2C's R10, the resize part of R11, and R12 (with `pasteFits` and the `pasteTooLarge` notice); `ios-core-tests/TerminalViewModelInputTests.swift`, the live typing test of `TerminalViewLiveTests.swift`.

**Interfaces:**
- Consumes: Task 7 (`TerminalTyping`, `TerminalInputBatcher`), Task 9.
- Produces: `TerminalViewModel` now implements `TerminalTextInput` (`markedText` becomes its `override`), with:

```kotlin
override fun insertText(text: String); override fun setMarkedText(text: String); override fun unmarkText()
override fun deleteBackward(); override fun press(key: TerminalKey, mods: List<TerminalModifier>); fun toggleCtrl()
/** R12: over MAX_PASTE_BYTES → nothing sent, pasteTooLarge += 1 (A6); otherwise pasteUnits → messages, with a view. */
override fun paste(text: String)
fun scroll(lines: Int)
```

  Each call copies `markedText` and `ctrlLatched` out of `TerminalTyping` into the state (A3). `sentInputs` rises by one per input message queued.

- [ ] **Step 1: Write the failing tests.** Port the 14 tests of `TerminalViewModelInputTests.swift` (same helpers as Task 9). Add:

```kotlin
@Test fun aPasteOverTheLimitIsRefusedWithANotice() { runTest {
    val link = ScriptedTerminalLink(); val (model, _) = makeModel(link); live(model, link)
    model.paste("a".repeat(262_145)); runCurrent()
    assertEquals(emptyList(), link.inputs); assertEquals(1, model.pasteTooLarge)
    model.paste("a".repeat(262_144) + "\u001b")
    assertTrue(eventually { link.inputs.size == 16 })
    assertTrue(link.inputs.all { it == listOf(TerminalInputUnit.Paste("a".repeat(16_384))) }); assertEquals(1, model.pasteTooLarge)
} }
```

  Add the live test `typingEchoesThroughAFakeMac` (the port of `testTypingEchoesThroughAFakeMac`) to `TerminalViewLiveTest`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.terminal.TerminalView*'`. Expected: `BUILD FAILED`, `Unresolved reference: insertText`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): typing, paste, scrolling and resizing in the terminal model"`.
- [ ] **Step 4: Implement** R10, the resize part of R11 and R12. Each delay is a coroutine in `scope` that awaits `sleep(…)` and is cancelled when a newer change replaces it. The echo clock keeps a start mark and a token, so a stale timeout does nothing.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts core terminal.TerminalViewModelInputTest terminal.TerminalViewLiveTest terminal.TerminalViewModelTest` shows 15, 4 and 21. Then `shellx-android/scripts/dev.sh test core`. Expected: `==> test core: passed`.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main` and `git commit -m "feat(shellx-android): typing, paste, scrolling and resizing in the terminal model"`.

---

### Task 11: core — the workspace model knows the terminal shown; the demo Mac's terminals

**Files:**
- Modify: `core/workspaces/WorkspaceScreenModel.kt`, `core/demo/DemoEnvironment.kt`
- Test: modify `core-test/workspaces/WorkspaceScreenModelTest.kt`, `core-test/demo/DemoEnvironmentTest.kt`

Reference: `ios-core/Workspaces/WorkspaceScreenModel.swift` (2C Task 7); `<APP_DEMO>`'s `DemoComposition.swift` (`terminals`, 2C Task 11); `ios-core-tests/WorkspaceScreenModelTests.swift` (the four terminal tests), `ios-app-tests/DemoCompositionTests.swift` (`testDemoMacShowsItsTerminals`).

**Interfaces:**
- Consumes: 3C's `WorkspaceScreenModel`, `WorkspaceScreenState`, `WorkspacePane.isAgent`, `DemoEnvironment`; Tasks 5 and 9.
- Produces:

```kotlin
// WorkspaceScreenState gains: val shownAsTerminal: Set<String> = emptySet()
// WorkspaceScreenModel gains
val shownAsTerminal: Set<String>
/** Switches the agent chip terminalId to its terminal (true) or back to its chat; an id the workspace does not have is ignored. */
fun showAsTerminal(terminalId: String, on: Boolean)
/** The terminal of the page shown: the chip shown when it is a shell, or an agent chip shown as its terminal; null for an
 *  agent's chat or no chip. Reads state and hub.state. */
val terminalShown: String?
/** The Mac made terminalId for this screen (＋): it is selected as soon as the list has it; picking a chip first drops it. */
fun expect(terminalId: String)
// DemoEnvironment.companion gains
val TERMINALS: Map<String, DemoTerminalFixture>   // demo-shellx-t1 and demo-web-t1 → AGENT, demo-shellx-t2 → SHELL,
                                                  // demo-relay-t1 → DEV_SERVER, demo-notes-t1 → WIDE
```

  `reconcile()` selects an expected id once the list has it (settled) and forgets it; `select(_)` forgets it. `prepare()` calls `first.setTerminalFixtures(TERMINALS)` right after it gives the first Mac `WORKSPACES`.

- [ ] **Step 1: Write the failing tests.** Port the four terminal tests of `WorkspaceScreenModelTests.swift`. Port `testDemoMacShowsItsTerminals` into `DemoEnvironmentTest` as `demoMacShowsItsTerminals`, over `DemoEnvironment(backgroundScope, ManualClock(), <temp dir>, StandardTestDispatcher(testScheduler), approvalDelay = Duration.ZERO)`, with a `TerminalViewModel(id, hub, hub.scope)` running in `backgroundScope`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.workspaces.WorkspaceScreenModelTest' --tests 'com.shellx.core.demo.DemoEnvironmentTest'`. Expected: `BUILD FAILED`, `Unresolved reference: terminalShown`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): the workspace screen knows its terminal; the demo Mac's terminals"`.
- [ ] **Step 4: Implement** the members and the one line in `prepare()`.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts core workspaces.WorkspaceScreenModelTest demo.DemoEnvironmentTest` shows 36 and 5. Then `shellx-android/scripts/dev.sh test core`. Expected: `==> test core: passed`.
- [ ] **Step 6: Commit.** `git add shellx-android/core/src/main` and `git commit -m "feat(shellx-android): the terminal shown, View as Terminal, the expected terminal and the demo's terminals"`.

---

### Task 12: app — draw the Mac's terminal in a pane

**Files:**
- Create in `app/ui/terminal/`: `TerminalFont.kt`, `TerminalRowLayout.kt`, `TerminalRowCache.kt`, `TerminalSurfaceView.kt`, `TerminalPane.kt`
- Modify: `app/ui/workspaces/ShellPanePlaceholder.kt` (its text), and every 3E test that Task 0 Step 5 found reading `workspace_shell_placeholder` (it reads `terminal_needs_update` from now on)
- Test: create `app-test/ui/terminal/TerminalRowLayoutTest.kt`, `app-test/ui/terminal/TerminalRowCacheTest.kt`, `app-ui-test/screenshots/TerminalRenderTest.kt`, `app-ui-test/ui/terminal/TerminalPaneGestureTest.kt`

Reference: `ios-app/UI/Terminal/{TerminalFont,TerminalRowLayout,TerminalCanvasView,TerminalSurfaceView,TerminalPane}.swift` and 2C Task 8's "How the pieces behave"; `ios-app-tests/TerminalRowLayoutTests.swift`, `TerminalRenderTests.swift`; this plan's Design, "Renderer".

**Interfaces:**
- Consumes: Tasks 3, 5, 8, 9; 3E's `ShellPanePlaceholder`, `NoticeCapsule`, `SecondaryButton`, `assertRenders`, `WorkRig`, `eventually`; 3A's `ShellXTheme`.
- Produces (`com.shellx.app.ui.terminal`):

```kotlin
/** The cell and the glyph widths a layout places text by. Tests give their own. */
interface TerminalGlyphMetrics {
    val cellWidth: Float; val cellHeight: Float; val baseline: Float; val underlineOffset: Float; val lineThickness: Float
    fun advance(text: String, bold: Boolean, italic: Boolean): Float      // the drawn width of text in that face, px
}
/** Typeface.MONOSPACE at SIZE_DP: four faces; cellWidth = the regular face's advance of "0";
 *  cellHeight = ceil(descent − ascent + leading); baseline = −ascent + leading / 2; underline position and thickness from
 *  Paint on API 29+, else 0.1 × textSize and max(1 px, textSize / 14); advances cached per face (at most 4 096 each);
 *  font features "liga" 0, "clig" 0, "calt" 0. */
class TerminalFont(context: Context) : TerminalGlyphMetrics {
    companion object { const val SIZE_DP = 12f }
    fun paint(bold: Boolean, italic: Boolean): Paint
}
/** One row laid out once from its cells and drawn from that until the row changes. */
class TerminalRowLayout(row: TerminalRow, cols: Int, palette: TerminalPalette, metrics: TerminalGlyphMetrics) {
    data class Cell(val column: Int, val width: Int, val text: String)
    data class Segment(val columns: IntRange, val style: TerminalResolvedStyle, val narrow: List<Cell>, val clusters: List<Cell>)
    /** One drawText: `text` with its left at x (grid px), squeezed horizontally by scaleX (1 = as is). */
    data class TextOp(val text: String, val x: Float, val scaleX: Float, val color: Int, val bold: Boolean, val italic: Boolean)
    val segments: List<Segment>
    val ops: List<TextOp>
    /** The glyph cell covering `column` (the second column of a wide cell gives the wide cell) and its style; null for a blank. */
    fun cell(column: Int): Pair<Cell, TerminalResolvedStyle>?
    fun drawBackground(canvas: Canvas, top: Float)
    fun drawText(canvas: Canvas, top: Float, font: TerminalFont)
    companion object { fun segments(cells: List<TerminalCell>, palette: TerminalPalette): List<Segment> }
}
/** Layouts by row object (identity), rebuilt only for rows whose object changed; cleared when cols or the palette change. */
class TerminalRowCache(metrics: TerminalGlyphMetrics) {
    fun layout(row: TerminalRow, cols: Int, palette: TerminalPalette): TerminalRowLayout
    fun retain(rows: Collection<TerminalRow>)       // drops every other layout
    val builds: Int                                  // layouts built so far (tests)
}
/** Draws model.screen (it keeps no copy) through `viewport`; Task 13 adds the keyboard. Its onTouchEvent returns false. */
class TerminalSurfaceView(context: Context, val model: TerminalViewModel, val terminalId: String, val font: TerminalFont) : View(context) {
    var onViewportChange: (TerminalViewport) -> Unit
    val viewport: TerminalViewport
    fun render(state: TerminalViewState)
    /** Main screen: a finger moving down (delta > 0) shows older rows; returns the px used. Alternate screen while the grid fits
     *  the height: TerminalGeometry.scrollLines → model.scroll(lines), using all of delta. */
    fun dragVertically(delta: Float): Float
    fun endVerticalDrag()                            // the scroll-line carry starts again at 0
    fun dragHorizontally(delta: Float): Float        // pans while the grid is wider than the pane; returns the px used
    fun pinch(factor: Float, focusX: Float, focusY: Float)
}
/** A shell chip's page, and an agent chip's shown as its terminal. `shown`: the page the pager settled on (3E's PaneContent). */
@Composable fun TerminalPane(model: TerminalViewModel, terminalId: String, title: String, shown: Boolean, modifier: Modifier = Modifier,
                             locksPaging: (Boolean) -> Unit = {})
```

  How the pieces behave (2C Task 8, in Android terms):
  - **Pane states.** When `!shown` or `state.terminalId != terminalId`, the page is `ShellPanePlaceholder()` while the phase is `Unsupported`, else an empty `surfaceContainer` box. Otherwise, by phase:
    - `Unsupported` → `ShellPanePlaceholder()`;
    - `Unavailable(GONE)` → `Icons.Filled.CancelPresentation` and `terminal_gone`;
    - `Unavailable(REFUSED)` → `Icons.Filled.Lock` and `workspaces_alert_refused_control`;
    - `Unavailable(FAILED)` → `Icons.Filled.Warning`, `terminal_failed`, and `SecondaryButton` `terminal_retry` (`model.retry()`, tag `terminal.retry`);
    - `Connecting` with `snapshots == 0` → `CircularProgressIndicator` over `terminal_connecting`;
    - `Offline` with `snapshots == 0` → `Icons.Filled.WifiOff` and `workspaces_alert_offline`;
    - anything else → the surface. `Offline`: 50 % alpha, with `NoticeCapsule(terminal_offline)` over its top. `Connecting`: a 16 dp spinner at its top end.

    Message pages take `ShellPanePlaceholder`'s shape, padding and colours, merge their semantics, and carry the tags `terminal.connecting`, `terminal.unavailable` and `terminal.offline`.
  - **Size.** On the page shown (`shown` and `state.terminalId == terminalId`), every state draws into one content box that fills the page above the key bar's place (Task 13). That box reports `TerminalGeometry.phoneGrid(w, h, font.cellWidth, font.cellHeight, padding px)` to `model.setPhoneGrid` in a `LaunchedEffect` keyed by its size. The root has `imePadding()`.
  - **Surface host.** `AndroidView(factory = { TerminalSurfaceView(it, model, terminalId, font) }, update = { it.render(state) })`, with tag `terminal.surface`. Its semantics: `contentDescription = terminal_surface_label(title)`, and `text` = the screen rows joined by `"\n"`, built inside the semantics block (only when an accessibility service or a test asks). The View is `IMPORTANT_FOR_ACCESSIBILITY_NO`.
  - **`render(state)`.**
    - The surface keeps the last `snapshots`, `topShift` and `sentInputs` it saw. `shownRows` is the history count (0 on the alternate screen) plus `rows`.
    - It updates `viewport = viewport.contentChanged(cols, shownRows, topShift − lastTopShift, toBottom = snapshots or sentInputs changed)` and invalidates.
    - `onSizeChanged` applies `viewport.resized`. Every viewport change calls `onViewportChange`.
  - **`onDraw`.**
    - Fill with the palette's background (`TerminalColors.background`), or `surfaceContainer` before a palette.
    - Translate by `(−scrollX + padding, −scrollY + padding)` and scale by `viewport.scale`.
    - For each visible row index (history rows first on the main screen, then screen rows): `cache.layout(row, cols, palette)`, then all backgrounds, then all text, at `y = index × cellHeight`. Then `cache.retain(rows within visibleRows ± 40)`.
    - The cursor is drawn only while the phase is `Live`, `cursor.visible` is true and nothing is composed. Its box is the cell under it (2 columns for a wide cell). `BLOCK` (and unknown shapes) fills the box with `TerminalColors.cursor` and draws that cell's text again in the background colour; `BAR` is 2 dp wide at its left; `UNDERLINE` is 2 dp high at its bottom; `BLOCK_HOLLOW` is a 1 dp stroke. It never blinks.
    - Then the marked text, at the cursor's cell, in the regular face: palette foreground on palette background, with a 1 dp underline under its width.
  - **Row layout.**
    - `segments` walks `row.cells(cols)`. A `Continuation` is skipped; a `Blank` is a narrow `" "` in the default style. A `Glyph` is narrow when its width is 1 and its text is one code point, else a cluster. Consecutive cells with equal `TerminalColors.resolve` form one segment.
    - `ops`, in column order: inside a segment that draws text, consecutive narrow cells whose `advance` is within 0.5 px of `cellWidth` form one op at their first column's x. A narrow cell of another advance is an op of its own: centred in its cell when narrower, at the cell's left with `scaleX = cellWidth / advance` when wider. A cluster is an op of its own, centred in `width × cellWidth`, or squeezed the same way when wider.
    - `drawBackground` fills each segment's columns that has a background. `drawText` runs the ops, then underline (baseline + `underlineOffset`), strike (baseline − 0.3 × `cellHeight`) and overline (the row's top), each `lineThickness` high across the segment.
    - Colours become ARGB as `0xFF shl 24 or (r shl 16) or (g shl 8) or b`.
  - **Gestures.** As in Design, "Renderer".
    - The vertical `scrollable` uses `dragVertically`, with fling on the main screen only. Its `DragInteraction.Stop` and `Cancel` call `endVerticalDrag()`.
    - The horizontal `scrollable` uses `dragHorizontally`, enabled while `viewport.maxScrollX > 0`.
    - The pinch detector runs in `PointerEventPass.Initial`: while two or more pointers are down it calls `pinch(calculateZoom(), centroid)` and consumes those changes.
    - `locksPaging(pinching || viewport.maxScrollX > 0)` is called whenever either value changes.
  - **`ShellPanePlaceholder`** shows `terminal_needs_update` in place of `workspace_shell_placeholder`. Its KDoc: the page of a shell chip on a Mac whose ShellX shows no terminals. Keep its test tag `workspace.shell.placeholder` (3E's `WorkspaceScreenTest.tappingAChipShowsItsPage` finds it): only the string resource changes.

- [ ] **Step 1: Write the failing tests.**
  - **`TerminalRowLayoutTest`** (Robolectric runner). `FakeMetrics(advances: Map<String, Float> = emptyMap()) : TerminalGlyphMetrics` has `cellWidth` 10, `cellHeight` 20, `baseline` 15, `underlineOffset` 2 and `lineThickness` 1, and answers `advance(text, …) = advances[text] ?: 10f × <code points of text>`. Port the three tests of `TerminalRowLayoutTests.swift` (`cellsOfOneStyleFormOneSegment`, `wideAndClusterCellsAreDrawnOnTheirOwn`, `theCellUnderTheCursorIsFound`) over `FakeMetrics()`, then add:

```kotlin
@Test fun aRunOfUniformGlyphsIsOneDrawCall() {
    val layout = TerminalRowLayout(TerminalRow(listOf(TerminalStyledRun(0, "hello"))), 5, DemoTerminalScreens.PALETTE, FakeMetrics())
    assertEquals(listOf("hello"), layout.ops.map { it.text }); assertEquals(0f, layout.ops[0].x)
}
@Test fun aGlyphThatIsNotOneCellWideStaysInItsCell() {   // Review Focus 5
    val metrics = FakeMetrics(advances = mapOf("ắ" to 15f, "x" to 6f))
    val layout = TerminalRowLayout(TerminalRow(listOf(TerminalStyledRun(0, "aắbxc"))), 5, DemoTerminalScreens.PALETTE, metrics)
    assertEquals(listOf("a", "ắ", "b", "x", "c"), layout.ops.map { it.text })
    assertEquals(listOf(0f, 10f, 20f, 32f, 40f), layout.ops.map { it.x })          // x is centred: 30 + (10 − 6) / 2
    assertEquals(10f / 15f, layout.ops[1].scaleX, 0.0001f); assertEquals(1f, layout.ops[3].scaleX)
}
@Test fun aClusterWiderThanItsCellsIsSqueezedIntoThem() {
    val metrics = FakeMetrics(advances = mapOf("👨‍👩‍👧" to 30f, "中" to 18f))
    val row = TerminalRow(listOf(TerminalStyledRun(0, "👨‍👩‍👧", width = 2), TerminalStyledRun(2, "中", width = 2), TerminalStyledRun(4, "z")))
    val layout = TerminalRowLayout(row, 5, DemoTerminalScreens.PALETTE, metrics)
    assertEquals(listOf(0f, 21f, 40f), layout.ops.map { it.x })                     // 20 + (20 − 18) / 2
    assertEquals(20f / 30f, layout.ops[0].scaleX, 0.0001f); assertEquals("z", layout.ops[2].text)
}
```

  - **`TerminalRowCacheTest`** (Robolectric runner). `fiveRows()` is a snapshot of 20 × 5 whose rows read `r0` … `r4`, with `DemoTerminalScreens.PALETTE`; `delta(line, scroll)` is a `DELTA` head of 20 × 5 with cursor (0, 0) and that one line:

```kotlin
class TerminalRowCacheTest {
    private fun TerminalScreen.layOut(cache: TerminalRowCache, palette: TerminalPalette = this.palette!!) =
        (historyRows + screenRows).forEach { cache.layout(it, cols, palette) }
    @Test fun aDeltaRebuildsOnlyTheRowsItReplaced() {
        val s = TerminalScreen().apply { apply(fiveRows()) }; val cache = TerminalRowCache(FakeMetrics())
        s.layOut(cache); assertEquals(5, cache.builds)
        s.apply(delta(TerminalLine(2, listOf(TerminalRun(text = "ls"))), scroll = 0)); s.layOut(cache)
        assertEquals(6, cache.builds)
    }
    @Test fun rowsThatScrollIntoHistoryKeepTheirLayout() {
        val s = TerminalScreen().apply { apply(fiveRows()) }; val cache = TerminalRowCache(FakeMetrics())
        s.layOut(cache)
        s.apply(delta(TerminalLine(4, listOf(TerminalRun(text = "r5"))), scroll = 1)); s.layOut(cache)
        assertEquals(listOf("r0"), s.historyText()); assertEquals(6, cache.builds)
    }
    @Test fun aNewPaletteRebuildsEveryRow() {
        val s = TerminalScreen().apply { apply(fiveRows()) }; val cache = TerminalRowCache(FakeMetrics())
        s.layOut(cache); s.layOut(cache, s.palette!!.copy(bg = "#000000"))
        assertEquals(10, cache.builds)
    }
}
```

  - **`TerminalRenderTest`** (`@RunWith(AndroidJUnit4::class)`, `@GraphicsMode(NATIVE)`, `@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)`). `screen(fixture, deltas)` applies `fixture.snapshot`, then each delta, to a `TerminalScreen()`. `page(model)` is a `Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background))` with a `TopAppBar(title = { Text("shellx-ios") })`, then `TerminalPane(model, model.terminalId ?: "t", "zsh", shown = true, modifier = Modifier.weight(1f))`. One `@Test` per render name:
    - `rendersANormalShell` (`terminal-shell`): `SHELL` with `SHELL_TYPING`, first checking that `cursor?.x == 29`;
    - `rendersVimOnTheAlternateScreen` (`terminal-vim`): first `alt` and no history;
    - `rendersHtopFittedToWidth` (`terminal-htop`): first the fit for 100 columns at the device width is below 1 and above 0.3;
    - `rendersA320ColumnGridFittedToWidth` (`terminal-320-columns`): the 320 × 130 fixture of 2C's `testRendersA320ColumnGridFittedToWidth`; fit below 0.2 and above 0;
    - `rendersWideCharacters` (`terminal-wide`);
    - `rendersAnAgentsTerminal` (`terminal-agent`);
    - `rendersTheMacTooOldPlaceholder` (`terminal-needs-update`): `fixed(phase = Unsupported)`;
    - `rendersConnecting`, `rendersOffline` (the shell's screen), `rendersGone`, `rendersRefused`, `rendersFailed` (`terminal-connecting`, `terminal-offline`, `terminal-gone`, `terminal-refused`, `terminal-failed`);
    - `theFiveStatesLookDifferent`: capture the five with `ShellXSnapshots.capture` and require five different light-en pixel arrays.
  - **`TerminalPaneGestureTest`** (Compose, `createAndroidComposeRule<ComponentActivity>()`, in `ShellXTheme`). `surface()` finds the `TerminalSurfaceView` in `activity.window.decorView`. The pager rig is `HorizontalPager(rememberPagerState { 2 }, userScrollEnabled = !locked)`: page 0 is `TerminalPane(model, "t-zsh", "zsh", shown = pager.settledPage == 0, locksPaging = { locked = it })`, and page 1 a box tagged `other`. Each comment line is a `@Test`:

```kotlin
// aVerticalSwipeOnTheMainScreenScrollsTheHistory: fixed SHELL (30 history rows) → swipeDown on terminal.surface →
//   surface().viewport.scrollY < its maxScrollY and followsBottom is false
// aVerticalSwipeNeverTurnsThePage (RF 4): swipeUp and swipeDown on terminal.surface → currentPage stays 0
// aHorizontalSwipeAtFitTurnsThePage (RF 4): fixed SHELL (50 columns fit) → swipeLeft on terminal.surface → settledPage == 1
// aPinchZoomsBetweenFitAndTwoAndLocksPaging: fixed HTOP (fit < 1) → pinch outward → fit < viewport.scale <= 2 and locked is true;
//   pinch inward past fit → scale == fit and locked is false
// zoomedInAHorizontalSwipePansTheGrid (RF 4): fixed HTOP, surface().pinch(4f, 0f, 0f) → swipeLeft → viewport.scrollX > 0 and
//   currentPage stays 0
// onTheAlternateScreenAVerticalSwipeSendsScrollUnits: WorkRig with rig.mac.setTerminalFixtures(mapOf("t-zsh" to VIM)), a running
//   TerminalViewModel(rig.machineId, rig.hub, rig.hub.scope) showing t-zsh → live → swipeDown → eventually
//   rig.mac.terminalViewInputs("t-zsh") holds a Scroll unit with lines > 0
// theLoadingPageStillReportsThePhoneGrid: WorkRig, rig.mac.holdTerminalViewOpens(), the model shows t-zsh, the pane composed →
//   eventually rig.mac.terminalViewOpens.single().cols >= 20; terminal.connecting is displayed
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.terminal.*' --tests 'com.shellx.app.screenshots.TerminalRenderTest'`. Expected: `BUILD FAILED`, `Unresolved reference: TerminalRowLayout`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): draw the Mac's terminal in a pane"`.
- [ ] **Step 4: Implement** the five files and the placeholder change.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts app ui.terminal.TerminalRowLayoutTest ui.terminal.TerminalRowCacheTest screenshots.TerminalRenderTest ui.terminal.TerminalPaneGestureTest` shows 6, 3, 13 and 7. Then `shellx-android/scripts/dev.sh test app`. Expected: `==> test app: passed`.
- [ ] **Step 6: Look.** Run `SHOTS="$(mktemp -d)"; shellx-android/scripts/dev.sh screenshots record "$SHOTS"`. Expected: `screenshots written to …`. Open `terminal-wide-light-vi.png`, `terminal-htop-dark-en.png`, `terminal-320-columns-light-en.png` and `terminal-vim-dark-vi.png`, and check four things: CJK and emoji sit in their two columns with the next character right after them; htop and the 320 columns fit the width; vim's status bar spans the row; no text is clipped.
- [ ] **Step 7: Commit.** `git add shellx-android/app/src/main` and `git commit -m "feat(shellx-android): draw the Mac's terminal in a shell pane"`.

---

### Task 13: app — type into the terminal

**Files:**
- Create in `app/ui/terminal/`: `TerminalIme.kt`, `TerminalInputConnection.kt`, `TerminalKeyBar.kt`
- Modify: `app/ui/terminal/TerminalSurfaceView.kt` (editor, keys, focus), `app/ui/terminal/TerminalPane.kt` (tap, long press, paste menu, key bar, notices, keyboard visibility)
- Modify: `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md` (rows A-g1 to A-g4)
- Test: create `app-test/ui/terminal/TerminalInputConnectionTest.kt`, `app-test/ui/terminal/TerminalKeyCodesTest.kt`, `app-test/ui/terminal/TerminalSurfaceInputTest.kt`, `app-ui-test/ui/terminal/TerminalPaneInputTest.kt`; modify `app-ui-test/screenshots/TerminalRenderTest.kt`

Reference: `ios-app/UI/Terminal/TerminalSurfaceView+TextInput.swift`, `TerminalKeyBar.swift` and 2C Task 9; `ios-app-tests/TerminalSurfaceTests.swift`; this plan's Design, "Soft keyboard" and "Hardware keys".

**Interfaces:**
- Consumes: Tasks 7, 10, 12; 3E's `WorkRig`, `eventually`, `NoticeCapsule`, `AgentView.NOTICE_DURATION`, `assertRenders`.
- Produces (`com.shellx.app.ui.terminal`):

```kotlin
/** The keyboard calls the surface makes; SystemTerminalIme wraps InputMethodManager, tests record. */
interface TerminalIme {
    fun show(view: View); fun hide(view: View); fun restart(view: View)
    fun updateSelection(view: View, selStart: Int, selEnd: Int, composingStart: Int, composingEnd: Int)
}
class SystemTerminalIme(context: Context) : TerminalIme
val LocalTerminalIme: ProvidableCompositionLocal<TerminalIme?>      // staticCompositionLocalOf { null }; null → SystemTerminalIme
class TerminalInputConnection(
    view: View, private val input: TerminalTextInput, private val accepts: () -> Boolean,
    private val keys: (KeyEvent) -> Boolean, private val clipboardText: () -> String?,
    private val report: (document: String, composing: Boolean) -> Unit, private val restart: () -> Unit,
) : BaseInputConnection(view, true) {
    val document: String
    /** The model's marked text changed outside the keyboard: take it as the document and restart the keyboard. */
    fun resync(markedText: String)
}
object TerminalClipboard { fun hasText(context: Context): Boolean; fun text(context: Context): String? }   // never reads in hasText
// TerminalSurfaceView: the constructor gains `ime: TerminalIme`; it overrides onCheckIsTextEditor, onCreateInputConnection,
// onKeyDown, onKeyUp, onKeyMultiple, onFocusChanged; and adds
var onFocusChange: (Boolean) -> Unit
fun focusAndShowKeyboard()            // only while the phase is Live or Connecting
fun clearTerminalFocus()              // hides the soft keyboard and gives up the focus
fun handleKey(event: KeyEvent): Boolean
sealed interface TerminalKeyBarItem { data class Key(val key: TerminalBarKey) : TerminalKeyBarItem; data object HideKeyboard : TerminalKeyBarItem }
@Composable fun TerminalKeyBar(ctrlLatched: Boolean, press: (TerminalKeyBarItem) -> Unit, modifier: Modifier = Modifier)
object TerminalPane {
    /** A key → model.press(key); CTRL → model.toggleCtrl(); HideKeyboard → hideKeyboard(). */
    fun perform(item: TerminalKeyBarItem, model: TerminalViewModel, hideKeyboard: () -> Unit)
}
// TerminalPane gains `showsKeyBar: Boolean = false` (tests: the bar without focus)
```

  The details:
  - **Connection and keys.** As Design, "Soft keyboard" and "Hardware keys". `accepts` is `model.terminalId == terminalId`, checked by every forwarding call and by `handleKey`.
  - **Keeping the keyboard in step.** `render(state)` calls `connection.resync(state.markedText)` when the two differ, and `restart` posts `ime.restart(this)` to the next main-loop turn.
  - **Taps.** `TerminalPane`'s `detectTapGestures`: `onTap` → `focusAndShowKeyboard()`; `onLongPress` → `focusAndShowKeyboard()`, then a `DropdownMenu` at the touch with one item, `terminal_paste` (tag `terminal.paste`), enabled while `TerminalClipboard.hasText`, which calls `TerminalClipboard.text(context)?.let(model::paste)`.
  - **The key bar.** It shows under the surface while `focused || showsKeyBar`, calling `TerminalPane.perform(item, model) { surface.clearTerminalFocus() }`.
  - **The keyboard hides.** When `WindowInsets.ime` goes from a bottom above 0 to 0 while focused, `clearTerminalFocus()`.
  - **The paste notice.** A rise of `state.pasteTooLarge` shows `NoticeCapsule(terminal_paste_too_large)` over the top of the pane for `AgentView.NOTICE_DURATION`, in a polite live region.
  - **`TerminalKeyBar` layout.** A 48 dp row on `surfaceContainer` with a 1 dp `outlineVariant` line on top; keys drawn 40 dp high with a 48 dp touch target (`minimumInteractiveComponentSize()`), at least 48 dp wide, 8 dp corners, 6 dp apart, 8 dp side padding, on `MaterialTheme.colorScheme.background`, each with `Modifier.focusProperties { canFocus = false }`.
    - The caps are `terminal_cap_esc`, `terminal_cap_tab` and `terminal_cap_ctrl` in monospace 15 sp medium. The arrows are `Icons.Filled.West`, `North`, `South` and `East`. After a `Spacer`, `Icons.Filled.KeyboardHide`.
    - A latched ctrl: `accent` at 20 % behind `accentText`, a 1 dp `accent` outline at 45 %, `selected = true`, and `stateDescription = terminal_key_ctrl_latched`.
    - Descriptions `terminal_key_escape`, `terminal_key_tab`, `terminal_key_ctrl`, `terminal_key_left`, `terminal_key_up`, `terminal_key_down`, `terminal_key_right` and `terminal_key_hide_keyboard`; tags `terminal.key.escape`, `.tab`, `.ctrl`, `.left`, `.up`, `.down`, `.right` and `terminal.key.hideKeyboard`.
  - **Android-only strings.** `values/strings_android.xml` gains `<string name="terminal_paste">Paste</string>` and, with `translatable="false"`, `terminal_cap_esc` `esc`, `terminal_cap_tab` `tab` and `terminal_cap_ctrl` `ctrl`. `values-vi/strings_android.xml` gains `<string name="terminal_paste">Dán</string>`.

- [ ] **Step 1: Write the failing tests.**
  - **`TerminalInputConnectionTest`** (Robolectric). `TypingRecorder : TerminalTextInput` wraps a real `TerminalTyping` and records the units each call returns (`paste` records `Paste(text)`) in `units`. `connection(accepts = { true })` builds the connection over a plain `View(context)`, recording `report` calls in `reports`, `restart` calls in `restarts` and key events in `keyEvents`. Each comment line is a `@Test`:

```kotlin
class TerminalInputConnectionTest {
    // composingStaysLocalAndACommitSendsTheWord: setComposingText("v",1), ("vi",1), ("việ",1) → units empty, document "việ";
    //   commitText("việt", 1) → units == [Text("việt")], document ""
    // finishingTheCompositionSendsIt: setComposingText("Tiế",1); finishComposingText() → [Text("Tiế")]
    // backspaceWhileComposingEditsTheWordOnThePhone (RF 3): setComposingText("việ",1); setComposingText("vi",1) → units empty;
    //   deleteSurroundingText(1, 0) → units empty, document "v"
    // backspaceWithNothingComposedSendsOneBackspacePerCall (RF 3): deleteSurroundingText(1, 0), deleteSurroundingText(2, 0),
    //   deleteSurroundingTextInCodePoints(1, 0) → [Key(BACKSPACE)] × 3; deleteSurroundingText(0, 1) → nothing more
    // enterArrivesOnceWhicheverWayTheKeyboardSendsIt (RF 3): commitText("\n",1) → [Key(ENTER)]; performEditorAction(IME_ACTION_UNSPECIFIED)
    //   → one more Key(ENTER); sendKeyEvent(ENTER down) → keyEvents has it and units has no third ENTER
    // aMultiLineCommitIsPastedNotTyped (RF 2): commitText("echo a\necho b", 1) → [Paste("echo a\necho b")];
    //   commitText("ls\n", 1) → [Text("ls"), Key(ENTER)] more
    // aCommitAfterTheTerminalChangedIsDropped (RF 1): accepts = { false }; setComposingText("viê",1), commitText("việt",1),
    //   finishComposingText(), deleteSurroundingText(1,0) → units empty; every call returned true
    // theKeyboardSeesOnlyTheComposingText: nothing composed → getTextBeforeCursor(100,0) == "", getExtractedText(..).text == "";
    //   setComposingText("viê",1) → getTextBeforeCursor(100,0) == "viê", getTextBeforeCursor(1,0) == "ê", getTextAfterCursor(9,0) == "",
    //   getSelectedText(0) == null, getCursorCapsMode(TextUtils.CAP_MODE_SENTENCES) == 0
    // theSelectionIsReportedAfterEachChangeAndOnceForABatch: commitText("a",1) → reports.last() == ("", false);
    //   setComposingText("vi",1) → ("vi", true); beginBatchEdit(); setComposingText("v",1); setComposingText("vi",1); endBatchEdit()
    //   → exactly one more report
    // whenTheModelDoesNotKeepWhatTheKeyboardComposedItRestarts: recorder.toggleCtrl(); setComposingText("c",1) →
    //   units == [Key(letter('c'), [CTRL])], document "", restarts == 1
    // closingTheConnectionCommitsTheWord: setComposingText("viê",1); closeConnection() → [Text("viê")]
    // aComposingRegionOutsideTheWordIsRefused: setComposingRegion(0, 5) with nothing composed → false; setComposingText("vi",1);
    //   setComposingRegion(0, 2) → true and document "vi"
    // imagesFromTheKeyboardAreRefused: commitContent(InputContentInfo(Uri.parse("content://x"), ClipDescription("i",
    //   arrayOf("image/png"))), 0, null) → false
}
```

  - **`TerminalKeyCodesTest`** (Robolectric), one test: each `TerminalKeyCodes` constant equals its `android.view.KeyEvent.KEYCODE_*` (`DPAD_UP` … `NUMPAD_ENTER`).
  - **`TerminalSurfaceInputTest`** (Robolectric, over `WorkRig`). A running `TerminalViewModel(rig.machineId, rig.hub, rig.hub.scope)` with `setPhoneGrid(40, 10)` and `show("t-zsh")`, waited to `Live`; a `TerminalSurfaceView(activity, model, "t-zsh", TerminalFont(activity), RecordingIme())` attached to a Robolectric activity. `RecordingIme` (a test class beside these tests) counts `shows`, `hides` and `restarts` and keeps every `updateSelection` call. Each comment line is a `@Test`:

```kotlin
// theEditorInfoKeepsComposingAndTurnsOffWhatATerminalMustNotHave: EditorInfo().also { surface.onCreateInputConnection(it) } →
//   inputType == TYPE_CLASS_TEXT or TYPE_TEXT_FLAG_NO_SUGGESTIONS or TYPE_TEXT_FLAG_MULTI_LINE (so no CAP_*, AUTO_CORRECT, password
//   variation or TYPE_NULL); imeOptions has IME_FLAG_NO_EXTRACT_UI, IME_FLAG_NO_FULLSCREEN, IME_FLAG_NO_ENTER_ACTION and
//   IME_FLAG_NO_PERSONALIZED_LEARNING; surface.onCheckIsTextEditor() is true
// telexComposingReachesTheMacOnlyWhenCommitted: through the returned connection, setComposingText "T", "Ti", "Tie", "Tiê", "Tiên",
//   "Tiến", "Tiếng" → after 200 ms terminalViewInputs("t-zsh") is empty; commitText("Tiếng", 1) → eventually [[Text("Tiếng")]]
// hardwareKeysReachTheMacAsNamedKeysOrText (RF 3): dispatchKeyEvent of KEYCODE_ESCAPE, KEYCODE_DPAD_LEFT, KEYCODE_C with META_CTRL_ON,
//   KEYCODE_X, KEYCODE_1 (as a keyboard's digit key event), KEYCODE_DEL, KEYCODE_V with META_CTRL_ON → eventually the inputs are
//   [[Key(ESCAPE)], [Key(LEFT)], [Key(c, [CTRL])], [Text("x")], [Text("1")], [Key(BACKSPACE)], [Key(v, [CTRL])]]
// ctrlShiftVPastesTheClipboard: the clipboard holds "echo a\necho b"; KEYCODE_V with the meta state (META_CTRL_ON or META_SHIFT_ON) →
//   eventually [[Paste("echo a\necho b")]]
// aKeyBarKeyWhileComposingCommitsTheWordAndRestartsTheKeyboard: setComposingText("việ",1); TerminalPane.perform(Key(LEFT), model) {};
//   surface.render(model.state.value) → eventually [[Text("việ"), Key(LEFT)]]; after the main looper idles, RecordingIme.restarts == 1
// onlyTheTerminalShownTakesKeys (RF 1): model.show("t-claude"); the surface (still t-zsh) gets KEYCODE_X and commitText("x",1) →
//   handleKey returns false and terminalViewInputs("t-zsh") gains nothing
```

  - **`TerminalPaneInputTest`** (Compose over `WorkRig`, `CompositionLocalProvider(LocalTerminalIme provides ime)`). Each comment line is a `@Test`:

```kotlin
// aTapFocusesAndShowsTheKeyboardAndTheKeyBar: click terminal.surface → ime.shows == 1 and terminal.key.escape is displayed
// theKeyBarDrivesTheModel: click terminal.key.ctrl → it is selected with stateDescription terminal_key_ctrl_latched; click
//   terminal.key.escape → eventually inputs == [[Key(ESCAPE, [CTRL])]]; click terminal.key.hideKeyboard → ime.hides == 1 and
//   terminal.key.escape no longer exists
// aLongPressOffersPasteThatSendsOnePasteUnit: clipboard "echo a\necho b"; longClick terminal.surface → click terminal.paste →
//   eventually inputs == [[Paste("echo a\necho b")]]
// aPasteOverTheLimitShowsTheNoticeAndSendsNothing: clipboard "a" × 262 145; long press → Paste → terminal_paste_too_large shown;
//   inputs empty; mainClock.advanceTimeBy(4_100) → the notice is gone
// withNothingToPasteTheItemIsDisabled: empty clipboard → terminal.paste is not enabled
```

  - **`TerminalRenderTest`** gains `rendersTheKeyBar` (`terminal-key-bar`: `fixed(SHELL)` with `showsKeyBar = true`) and `rendersTheKeyBarWithCtrlLatched` (`terminal-key-bar-ctrl`: `fixed(SHELL, markedText = "việ", ctrlLatched = true)` with `showsKeyBar = true`). The second also captures both with `ShellXSnapshots.capture` and requires their light-en pixels to differ.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.terminal.*' --tests 'com.shellx.app.screenshots.TerminalRenderTest'`. Expected: `BUILD FAILED`, `Unresolved reference: TerminalInputConnection`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): type into the terminal"`.
- [ ] **Step 4: Implement** the files and changes listed, and the strings.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts app ui.terminal.TerminalInputConnectionTest ui.terminal.TerminalKeyCodesTest ui.terminal.TerminalSurfaceInputTest ui.terminal.TerminalPaneInputTest screenshots.TerminalRenderTest` shows 13, 1, 6, 5 and 15. Then `python3 shellx-android/scripts/import-strings.py --check` (expected `import-strings: ok (…)`) and `shellx-android/scripts/dev.sh test app` (expected `==> test app: passed`).
- [ ] **Step 6: Ledger.** Add four rows at the end of "Android-only differences", in the format of the rows there, with the next free numbers (A-g1 to A-g4), each `differs (3G): by design`:
  - **A-g1.** Ctrl+V on a hardware keyboard sends ctrl+v, and Ctrl+Shift+V pastes. Why: Ctrl+letter belongs to the terminal (S2 §3.7), and Android has no ⌘ (the iPhone pastes with ⌘V). Android: `core:terminal/TerminalHardwareKeys.kt`.
  - **A-g2.** Text the keyboard commits on more than one line (its clipboard chip, voice typing) is pasted as one paste, not typed. Why: typed line breaks become Enter keys, which run each line. Android: `app:ui/terminal/TerminalInputConnection.kt`.
  - **A-g3.** A hardware key that reaches the terminal while a word is being composed commits the word first. Why: Android hands keys to the input method before the view (the iPhone gives every key to the input method while composing). Android: `app:ui/terminal/TerminalSurfaceView.kt`.
  - **A-g4.** The keyboard does not learn from what is typed into a terminal. Why: commands and secrets typed at prompts; the iPhone has no per-field switch. Android: `app:ui/terminal/TerminalSurfaceView.kt` (`IME_FLAG_NO_PERSONALIZED_LEARNING`).
- [ ] **Step 7: Commit.** `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): type into the terminal: composing, key bar, hardware keys and paste"`.

---

### Task 14: app — terminal pages, the ＋ chip and View as Terminal

**Files:**
- Modify: `app/ui/workspaces/WorkspaceScreen.kt` (`WorkspaceScreenActions`, `WorkspaceMenuItem`, `WorkspaceScreen`), `app/ui/workspaces/PaneChips.kt` (`NewTerminalChip`), `app/ui/workspaces/WorkspaceView.kt` (`WorkspaceScreenHolder`, the screen's values), the file that holds `WorkspaceCommand` and `WorkspaceFeedback` (`app/ui/workspaces/WorkspaceFeedback.kt` by the mirror rule)
- Modify: `shellx-ios/ShellX/Localizable.xcstrings` (delete the `workspace.shell.placeholder` entry), the two generated `strings.xml` (regenerated), `docs/superpowers/ledgers/shellx-android-parity.md` (row 6.1-9, A-g5, "iPhone changes since the reference")
- Test: modify 3E's `app-test/ui/workspaces/WorkspaceTextsTest.kt`, `app-test/ui/workspaces/WorkspaceActionsTest.kt`, `app-ui-test/ui/workspaces/WorkspaceScreenTest.kt`, `app-ui-test/ui/workspaces/WorkspaceViewTest.kt`, `app-ui-test/screenshots/WorkspaceRenderTest.kt`

Reference: `ios-app/UI/Workspaces/{WorkspaceScreen,PaneChips,WorkspaceView,WorkspaceFeedback}.swift` (2C Task 10's "Wiring"); `ios-app-tests/WorkspaceRenderTests.swift`, `WorkspaceViewTests.swift`, `WorkspaceLiveRenderTests.swift` (2C's additions); 3E Task 8's Interfaces (contracts §20).

**Interfaces:**
- Consumes: Tasks 6 (`supportsTerminalView`, `supportsTerminalCreate`, `createTerminal`), 9–11, 12 and 13 (`TerminalPane`); 3E's `PaneContent(pane, shown, agent, shell)` (unchanged), `WorkspaceScreen(…, pagingLocked, pane = { pane, shown -> … })`, `PaneChips(…, trailing)`, `WorkspaceScreenActions.make`, `WorkspaceScreenHolder`, `WorkspaceFeedback`, `WorkspaceAlert`.
- Produces (`com.shellx.app.ui.workspaces`):

```kotlin
class WorkspaceScreenActions(/* 3E's select, rename, close, closeTab, then */ val createTerminal: () -> Unit = {},
                             val showAsTerminal: (String, Boolean) -> Unit = { _, _ -> })
enum class WorkspaceMenuItem(@StringRes val title: Int) {
    RENAME(R.string.workspace_menu_rename), VIEW_AS_TERMINAL(R.string.workspace_menu_view_as_terminal),
    VIEW_AS_CHAT(R.string.workspace_menu_view_as_chat), CLOSE_TAB(R.string.terminal_close_menu), CLOSE_WORKSPACE(R.string.workspace_menu_close);
    /** How the agent chip shown shows its page, when ⋮ may switch it (its Mac shows terminals). */
    enum class AgentChip { CHAT, TERMINAL }
    val isDestructive: Boolean                    // CLOSE_TAB and CLOSE_WORKSPACE only
    companion object {
        /** RENAME; VIEW_AS_TERMINAL for CHAT or VIEW_AS_CHAT for TERMINAL; CLOSE_TAB when canCloseTab; CLOSE_WORKSPACE. */
        fun items(canCloseTab: Boolean, agentChip: AgentChip? = null): List<WorkspaceMenuItem>
    }
}
// WorkspaceScreen gains, after canCloseTab:
//   canCreateTerminal: Boolean = false, canViewTerminals: Boolean = false, shownAsTerminal: Set<String> = emptySet()
/** The ＋ chip after the last chip: 3E's chip shape on surfaceContainer, Icons.Filled.Add, description terminal_new, tag workspace.chip.add. */
@Composable fun NewTerminalChip(enabled: Boolean, onClick: () -> Unit)
// WorkspaceCommand gains CREATE_TERMINAL
class WorkspaceScreenHolder(val model: WorkspaceScreenModel, val terminal: TerminalViewModel) : ViewModel() {
    override fun onCleared()                      // terminal.close()
}
```

  Wiring (2C Task 10 on 3E's names):
  - **`WorkspaceScreen`.**
    - `PaneChips(…, trailing = { if (canCreateTerminal) NewTerminalChip(enabled = canControl, onClick = actions.createTerminal) })`.
    - The menu shows `items(canCloseTab && shownPane != null, agentChip)`. `agentChip` is null unless `canViewTerminals` and the pane shown is an agent's: then `TERMINAL` when it is in `shownAsTerminal`, else `CHAT`. `VIEW_AS_TERMINAL` → `actions.showAsTerminal(pane.id, true)`, `VIEW_AS_CHAT` → `actions.showAsTerminal(pane.id, false)`.
  - **`WorkspaceScreenActions.make`.**
    - `createTerminal` runs through 3E's `run(WorkspaceCommand.CREATE_TERMINAL) { val answer = hub.createTerminal(model.ref); answer.terminalId?.let(model::expect); answer.result }`.
    - `showAsTerminal = { id, on -> model.showAsTerminal(id, on) }`.
  - **`WorkspaceFeedback.of`.** `CREATE_TERMINAL` joins `CREATE, RENAME, CLOSE` for `NotFound` (`Refresh`), and `CREATE, RENAME` for `Refused` (`Alert(REFUSED_CONTROL)`). `Ok` is `None`.
  - **`WorkspaceView`.**
    - The holder is `WorkspaceScreenHolder(WorkspaceScreenModel(ref, scope.hub), TerminalViewModel(ref.machineId, scope.hub, scope.hub.scope))`.
    - The STARTED block that runs `model.run()` also `launch`es `holder.terminal.run()`.
    - `LaunchedEffect(model.terminalShown) { holder.terminal.show(model.terminalShown) }`.
    - `var terminalLocksPaging by remember { mutableStateOf(false) }`, and `pagingLocked = <3E's voice lock> || terminalLocksPaging`.
    - `canCreateTerminal = scope.hub.supportsTerminalCreate(ref.machineId)`, `canViewTerminals = scope.hub.supportsTerminalView(ref.machineId)`, `shownAsTerminal = model.shownAsTerminal`.
    - With `terminal(p, shown) = TerminalPane(holder.terminal, p.id, PaneChips.label(p, res), shown, locksPaging = { terminalLocksPaging = it })`, the `pane` lambda is `{ p, shown -> if (p.id in model.shownAsTerminal) terminal(p, shown) else PaneContent(p, shown, agent = <3E's agent>, shell = { q, s -> terminal(q, s) }) }`.

- [ ] **Step 1: Write the failing tests.**
  - **`WorkspaceTextsTest`.** The menu test becomes the port of 2C's `testTheMenuOffersRenameViewAsTerminalCloseTabAndCloseWorkspace`:

```kotlin
@Test fun theMenuOffersRenameViewAsTerminalCloseTabAndCloseWorkspace() {
    assertEquals(listOf(WorkspaceMenuItem.RENAME, WorkspaceMenuItem.CLOSE_WORKSPACE), WorkspaceMenuItem.items(canCloseTab = false))
    assertEquals(listOf(WorkspaceMenuItem.RENAME, WorkspaceMenuItem.CLOSE_TAB, WorkspaceMenuItem.CLOSE_WORKSPACE), WorkspaceMenuItem.items(true))
    assertEquals(listOf(WorkspaceMenuItem.RENAME, WorkspaceMenuItem.VIEW_AS_TERMINAL, WorkspaceMenuItem.CLOSE_TAB, WorkspaceMenuItem.CLOSE_WORKSPACE),
        WorkspaceMenuItem.items(true, WorkspaceMenuItem.AgentChip.CHAT))
    assertEquals(listOf(WorkspaceMenuItem.RENAME, WorkspaceMenuItem.VIEW_AS_CHAT, WorkspaceMenuItem.CLOSE_TAB, WorkspaceMenuItem.CLOSE_WORKSPACE),
        WorkspaceMenuItem.items(true, WorkspaceMenuItem.AgentChip.TERMINAL))
    val titles = WorkspaceMenuItem.entries.map { res.getString(it.title) }
    assertEquals(listOf(R.string.workspace_menu_rename, R.string.workspace_menu_view_as_terminal, R.string.workspace_menu_view_as_chat,
        R.string.terminal_close_menu, R.string.workspace_menu_close).map(res::getString), titles)
    assertEquals(5, titles.toSet().size)
    assertEquals(listOf(WorkspaceMenuItem.CLOSE_TAB, WorkspaceMenuItem.CLOSE_WORKSPACE), WorkspaceMenuItem.entries.filter { it.isDestructive })
}
```

  - **`WorkspaceActionsTest`** gains the ports of 2C's four `WorkspaceViewTests` additions: `aNewTerminalReachesTheMacAndItsChipShows` (`feedback == None`, `rig.mac.terminalCreates == ["ws-shellx"]`, then eventually `selectedTerminalId` starts with `"ws-shellx-new-"` and there is no alert); `aRefusedNewTerminalIsAnAlert`; `viewAsTerminalSwitchesTheAgentChipsPage` (over `model.terminalShown`); and `aNewTerminalsAnswers` (the six `WorkspaceFeedback.of` lines).
  - **`WorkspaceScreenTest`** gains three tests; each comment line is a `@Test`:

```kotlin
// thePlusChipOpensANewTerminal: canCreateTerminal → click workspace.chip.add → createTerminals == 1; canControl = false →
//   workspace.chip.add is not enabled; canCreateTerminal = false → workspace.chip.add does not exist
// theMenuSwitchesAnAgentChipToItsTerminalAndBack: canViewTerminals, selected "t-claude" → workspace.menu → workspace_menu_view_as_terminal
//   → showAsTerminal == [("t-claude", true)]; with shownAsTerminal {"t-claude"} the menu offers workspace_menu_view_as_chat
// aShellChipNeverOffersViewAsTerminal: canViewTerminals, selected "t-zsh" → the menu has neither view item
```

  - **`WorkspaceViewTest`** gains two tests; each comment line is a `@Test`:

```kotlin
// theShellPaneOpensItsTerminalAtThePhoneSize: the Mac shows t-zsh → eventually rig.mac.terminalViewOpens.first().terminalId == "t-zsh"
//   with cols >= 20, and terminal.surface is displayed
// viewAsTerminalOpensTheAgentsTerminal: select t-claude → workspace.menu → workspace_menu_view_as_terminal → eventually
//   rig.mac.terminalViewOpens holds t-claude, and the t-zsh view was closed first (terminalViewCloses == ["t-zsh"])
```

  - **`WorkspaceRenderTest`** gains `workspace-new-terminal` (the shell selected with `canCreateTerminal`; its light-en pixels differ from `workspace-shell`'s), `workspace-agent-as-terminal` (`canViewTerminals`, `shownAsTerminal = setOf("t-claude")`, the agent page a `TerminalPane(fixed("t-claude", <AGENT screen>), "t-claude", "claude", shown = true)`) and `workspace-live-terminal` (`WorkspaceView` over `WorkRig` with `setTerminalFixtures(mapOf("t-zsh" to SHELL))`, the shell shown).
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.workspaces.*' --tests 'com.shellx.app.screenshots.WorkspaceRenderTest'`. Expected: `BUILD FAILED`, `Unresolved reference: VIEW_AS_TERMINAL`.
- [ ] **Step 3: Commit the tests.** `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): terminal pages, the new terminal chip and View as Terminal"`.
- [ ] **Step 4: Implement** the wiring.
- [ ] **Step 5: Retire `workspace.shell.placeholder`** (2C's contract addition gives this to 3G).
  1. Run `grep -rnE 'localized: "workspace\.shell\.placeholder"|LocalizedStringResource\("workspace\.shell\.placeholder"\)' shellx-ios --include='*.swift'; grep -rn 'workspace_shell_placeholder' shellx-android/app/src --include='*.kt'`. Expected: no output. If either prints a line, skip the rest of this step and report the line. The iPhone's `.accessibilityIdentifier("workspace.shell.placeholder")` and Android's test tag of the same text are identifiers, not the string: leave them.
  2. Delete the `"workspace.shell.placeholder" : { … }` entry from `shellx-ios/ShellX/Localizable.xcstrings` with the Edit tool. Remove only its lines and the comma that joins it to its neighbour, and keep the file's formatting.
  3. Run `python3 shellx-ios/scripts/check-strings.py` (expected `check-strings: ok (<n> keys)`), then `python3 shellx-android/scripts/import-strings.py` and `--check` (expected `import-strings: ok (…)`).
- [ ] **Step 6: Run (green).** Run the Step 2 command three times. Expected: PASS; `counts app ui.workspaces.WorkspaceActionsTest ui.workspaces.WorkspaceScreenTest ui.workspaces.WorkspaceViewTest screenshots.WorkspaceRenderTest` shows 15, 11, 4 and 16. Then `shellx-android/scripts/dev.sh test app`. Expected: `==> test app: passed`.
- [ ] **Step 7: Ledger.**
  - Row `6.1-9`: iPhone `ShellX/UI/Terminal/TerminalPane.swift`; Android `app:ui/terminal/TerminalPane.kt` (with `core:terminal/TerminalViewModel.kt`); state `done (3G)`.
  - Row A-g5 (next free number): "The terminal view closes whenever the workspace screen stops (the background, another screen on top of it, a rotation) and opens again when it starts"; why: "3E runs models only while STARTED; Android has no scene phase, and a stopped screen should give the terminal back to the Mac's size"; Android `core:terminal/TerminalViewModel.kt`; `differs (3G): by design`.
  - "iPhone changes since the reference" gains two rows (skip one that an earlier plan already added). The first is the 2C merge commit (`git log develop --merges --oneline | grep 'feat/shellx-terminal-2c-ios' | head -1 | cut -d' ' -f1`), "the terminal pane, key bar, paste limit, ＋ chip, View as Terminal / View as Chat, demo terminals (plan 2C)", rows `6.1-8, 6.1-9`, `done (3G)`. The second reads "`workspace.shell.placeholder` removed from the catalog (plan 3G)", row `6.1-9`, `done (3G)`.
- [ ] **Step 8: Commit.** `git add shellx-android/app/src/main shellx-ios/ShellX/Localizable.xcstrings docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): terminal pages, the new terminal chip and View as Terminal"`.

---

### Task 15: Verify and hand off

**Files:** none new, apart from the ledger's measurements. A fix found here gets a failing test first, in the task that owns the code.

- [ ] **Step 1: Catch up with `develop`.** Run `git merge --no-edit develop`, then `python3 shellx-android/scripts/import-strings.py --check || python3 shellx-android/scripts/import-strings.py`. Handle new iPhone keys by 3A Task 11 Step 1's rule, and commit any change with its ledger row.
- [ ] **Step 2: Full verification.**

  ```bash
  shellx-android/scripts/dev.sh test all
  shellx-android/scripts/dev.sh test all
  bash scripts/shellx/check-android-license.sh
  bash scripts/shellx/check-link-license.sh; echo "exit=$?"
  python3 shellx-android/scripts/import-strings.py --check
  python3 shellx-ios/scripts/check-strings.py
  shellx-android/scripts/dev.sh build-release
  python3 scripts/verify-local.py; echo "exit=$?"
  ```

  Expected:
  - `==> test all: passed`, twice;
  - `check-android-license: ok`, then `exit=0`;
  - `import-strings: ok (…)` and `check-strings: ok (<n> keys)`;
  - `release checks passed (…)`;
  - a line starting `PASSED:`, then `exit=0`. A check that also fails on `develop` in the main checkout is pre-existing: report it and do not fix it here.
- [ ] **Step 3: Run the boundary greps.** Each command must print nothing:

  ```bash
  git diff --name-only develop...HEAD | grep -v -e '^shellx-link/kotlin/' -e '^shellx-android/' -e '^docs/superpowers/ledgers/shellx-android-parity.md$' -e '^shellx-ios/ShellX/Localizable.xcstrings$'
  git diff develop...HEAD -- shellx-ios/ShellX/Localizable.xcstrings | grep '^+[^+]'
  grep -rnE 'HexFormat|java\.net\.http|readAllBytes|transferTo|ofVirtual' shellx-link/kotlin/link-core/src/main shellx-android/core/src/main shellx-android/app/src/main
  grep -rn 'import android\.' shellx-android/core/src
  grep -rniE 'manaflow' shellx-link/kotlin shellx-android
  grep -rnE 'Log\.(d|i|w|e|v)\(' shellx-android/app/src/main/kotlin | grep -viE 'CoreLog'
  grep -rnE 'TYPE_NULL|VARIATION_(VISIBLE_)?PASSWORD' shellx-android/app/src/main/kotlin/com/shellx/app/ui/terminal
  grep -rnE 'Text\("[^"]' shellx-android/app/src/main/kotlin/com/shellx/app/ui/terminal
  ```

- [ ] **Step 4: Look at the screens.** Run `SHOTS="$(mktemp -d)"; shellx-android/scripts/dev.sh screenshots record "$SHOTS"`. Open `terminal-shell-dark-en.png`, `terminal-wide-light-vi.png`, `terminal-320-columns-light-en.png`, `terminal-key-bar-ctrl-light-vi.png`, `workspace-new-terminal-dark-en.png` and `workspace-agent-as-terminal-light-vi.png`. Compare each with the iPhone render of the same name: the same structure, order and words, with Android controls, cells in their columns, and a translation everywhere.
- [ ] **Step 5: Check the ledger.** Row `6.1-9` says `done (3G)`; rows A-g1 to A-g5 exist; "iPhone changes since the reference" has the two Task 14 rows. Commit any fix with `docs(shellx-android): ledger rows for the terminal`.
- [ ] **Step 6: Localization audit.** Put in the hand-off:
  - the 20 imported names with their en and vi, from `grep -E 'name="(terminal_(needs_update|connecting|offline|gone|failed|retry|surface_label|paste_too_large|key_[a-z_]+|new)|workspace_menu_view_as_(terminal|chat))"' shellx-android/app/src/main/res/values{,-vi}/strings.xml`;
  - the four Android-only strings of Task 13;
  - the removed key `workspace.shell.placeholder`;
  - that the Step 3 `Text("` grep printed nothing.
- [ ] **Step 7: Review.** Run a review subagent on `git diff develop...HEAD`, through superpowers:requesting-code-review and `skills/cmux-review/SKILL.md` (correctness first). Give it this plan's Design and Review Focus, plan 2C's "Design (decided)", plan 2A's "Wire specification", and contracts §17, §18 and §20. Fix each confirmed finding with a failing test first, then repeat Steps 2–6.
- [ ] **Step 8: USER — check on the real Android phone.** Run `shellx-android/scripts/dev.sh device`. Expected: `==> ShellX Dev is running on <serial>`. Then ask the user to do the following and tell you what they saw.

  **Part A works today, through "Try without an account":**
  1. Open workspace `shellx-ios` › chip `zsh`: the shell shows in colour; a downward swipe scrolls its 30 history rows.
  2. Tap the terminal: the keyboard and the key bar show. Type `ls` and Return: `ls` appears after the prompt, and a new prompt row follows.
  3. Gboard, Vietnamese, Telex: type `echo Tieengs Vieetj` and Return. While a word is underlined it sits at the cursor and nothing reaches the shell; Backspace edits the underlined word; the row ends up `echo Tiếng Việt`. VNI: `Tie61ng` gives `Tiếng`. If Laban Key is installed, repeat with its Telex.
  4. Key bar: ctrl then `c` → `^C` and a new prompt; the arrows and esc send without error. The hide-keyboard key hides the keyboard and the bar; so does system Back.
  5. Long-press › Paste a two-line text: two lines arrive. Paste a text over 256 KB: the "too large" notice shows and nothing is typed.
  6. Workspace `notes` › `zsh`: Vietnamese, Chinese, Japanese, Korean and emoji sit in their columns.
  7. Workspace `relay` › `npm`: a log line every 3 s and the view follows the bottom; scrolled up, it holds still.
  8. `shellx-ios` › `claude` › ⋮ › View as Terminal: the agent's terminal; ⋮ › View as Chat goes back.
  9. The ＋ chip adds a `zsh` chip and shows it.
  10. A pinch zooms between fit and 2×; rotating the phone fits the width again.
  11. A Bluetooth keyboard, if one is at hand: letters, Return, Backspace, Tab, Esc, arrows, Ctrl+C, and Ctrl+Shift+V pastes.

  **Part B needs a relay where the Android app can sign in** (plans 1A and 1D) **and plan 2B's Mac build:**

  12. Build the **Release** tagged Mac app (contracts §17) in the main checkout on `develop`: `CMUX_DEV_BACKEND_MODE=local CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" ./scripts/reload.sh --tag terminal-2b-mac --release` (the agent may run it; never `--launch`). The USER opens "ShellX DEV terminal-2b-mac", signed in to the same account.
  13. The USER turns the phone's Wi-Fi off (4G), signs in with Google, and pairs with the tagged Mac by its QR code.
  14. The agent starts the capture: `adb -s <serial> logcat -c`, then, in the background, `adb -s <serial> logcat -v brief | grep --line-buffered -E 'terminal(FirstScreen|KeyEcho|FrameApply) [0-9]+ ms' > ~/Desktop/terminal-latency-android.txt`.
  15. Criterion 3: in a workspace with two shell chips, swipe between them 20 times. Criterion 6: meanwhile the Mac keeps its selected workspace and tab, and no Mac window comes forward.
  16. Criterion 4: tap a terminal and type 20 single letters about a second apart.
  17. Criterion 5: run `yes | head -100000`, then `head -c 5000000 /dev/urandom | base64`. The app keeps scrolling and swiping, the Mac stays responsive, and the phone's last screen matches the Mac's.
  18. `vim`: a swipe scrolls the file; `:q` returns to the shell with its history. `htop` after typing on the Mac (the Mac's size wins): the phone fits the width, a pinch zooms, and typing on the phone brings the phone's size back.
  19. The ＋ chip opens a terminal, and the Mac's selected tab does not change.
  20. Home, then back: the Mac's terminal goes back to the Mac's size, and on return it reopens.

  When Part B cannot run yet, record "Part B pending: needs a relay with 1A (and 1D's Android client) and the 2B Mac build".
- [ ] **Step 9: Measurements.** Stop the capture, then run 2C Task 12 Step 7's Python script on `~/Desktop/terminal-latency-android.txt`. Targets: `terminalFirstScreen` p95 < 1 000 ms, `terminalKeyEcho` p95 < 300 ms, `terminalFrameApply` p95 < 16 ms. Append a section `## Terminal on Android (plan 3G)` to the parity ledger, with a table `Metric | n | p50 | p95 | Target | Met?`, the phone's maker, model and Android version, and one line per item of Parts A and B (passed, or what was wrong). Commit it as `docs(shellx-android): terminal measurements on Android`. A missed target is reported to the user, not fixed silently.
- [ ] **Step 10: Land (contracts §1).** This is an app UI and runtime change, so merge only after the user's explicit OK in Step 8. An OK on Part A with Part B pending counts when the user says so. In the checkout that has `develop`:
  1. `git pull --ff-only`;
  2. `git merge --no-ff feat/shellx-android-3g-terminal -m "Merge branch 'feat/shellx-android-3g-terminal' into develop"`;
  3. `shellx-android/scripts/dev.sh test all`. Expected: `==> test all: passed`;
  4. `git push origin develop`.

  Never merge to `main`. Never deploy, upload or publish. Remove the worktree afterwards (superpowers:finishing-a-development-branch).
- [ ] **Step 11: Report**, in Vietnamese, to the user. Include:
  - the merge commit and the test counts;
  - every name that differed from this plan (Task 0 Step 4);
  - the localization audit;
  - the USER check's results and the measurements, or what is still pending;
  - the deliberate deviations: the fixed 12 dp font with pinch zoom instead of the system font size, the hide-keyboard key, and rows A-g1 to A-g5;
  - the Spec notes and Contract additions below, for the orchestrator.

---

## Spec notes

1. **No splitter on the phone.** 2A's `TerminalFrameSplitter` is host code. The fake Mac is in memory, so it sends each frame as one part and its snapshot with the fixture's whole history (at most 30 rows): no history frames. Multi-part assembly and history frames are covered by the `terminal.json` screens.
2. **Ctrl+V (A-g1).** Contracts §18 says paste comes from "⌘V / Ctrl+V". S2 §3.7 makes Ctrl+letter the named-key path with no app shortcuts, and vim and bash use ctrl+v. So Ctrl+V is sent, and Ctrl+Shift+V (the Linux terminal convention) pastes.
3. **A key while composing (A-g3).** 2C hands every hardware key to the input method while composing. On Android the input method sees keys first, so a key that reaches the view commits the word, and the keyboard restarts.
4. **Multi-line commits (A-g2).** An input path the iPhone does not have: Gboard's clipboard chip and voice typing commit whole texts. A commit that still holds a line break after one trailing line break is dropped goes as a paste (bracketed on the Mac); a commit with one trailing line break, such as `ls\n`, is still typed text and Enter.
5. **Background and rotation (A-g5, A1).** 2C's `suspend()` / `resume()` become 3E's STARTED-bound `run()`. A rotation recreates the activity and so closes and reopens the view: the same cost as the resize a rotation causes anyway (a snapshot and its history fill).
6. **Size while loading.** 2C reports the grid from the surface's layout, and its pane shows a spinner page while connecting. Android reports it from the pane's content box in every state, so the first open never waits for a surface that only exists once a screen arrived.
7. **Font.** Contracts §18 allows the system monospace or a bundled OFL font. S3 §5's licence list names no font licence, so the plan uses `Typeface.MONOSPACE` and keeps fallback glyphs in their cells. It uses 12 dp, not sp, mirroring the iPhone's fixed 12 pt (2C Spec note 5).
8. **Demo emoji widths.** 2C's markup uses Swift's `isEmojiPresentation`. Java 17 has no such property, so a coarse table stands in, pinned by `fixtureCharactersHaveTheIPhoneWidths` for every non-ASCII character of the fixtures.
9. **`TerminalScreen` is mutable**, where 2A's is a Swift value type. It keeps row objects as rows move into history, which `TerminalRowCache` relies on, and avoids copying up to 10 000 rows per frame (criterion 5).
10. **`LinkSession` defaults.** The seven terminal members have defaults (an empty flow, no-ops, `Remote("unsupported")`), so 3C's test fakes and delegating wrappers keep compiling. `LinkClient` and `FakeMacSession` override all of them.
11. **The fake Mac is the host.** 3B ports no `LinkHost`, so the fake Mac's session keeps the host rules the phone can observe: `busy`, restart on the same terminal, `not_open`, the clamp, `bad_request`, and `Opened` before the frames.
12. **Keyboard learning (A-g4)** is off through `IME_FLAG_NO_PERSONALIZED_LEARNING` (API 26). It protects what is typed at a prompt; the iPhone has no per-field switch.
13. **Keyboards that rewrite committed text.** The document is only the composing text (the iPhone's model), so a keyboard that edits text it already committed (through `deleteSurroundingText` plus `commitText`, without composing) cannot transform it. Gboard's and Laban Key's Telex and VNI compose, and the USER check (Part A, item 3) tests both. A keyboard that fails there is reported, not worked around in this plan.
14. **`workspace.shell.placeholder`** is removed from the iPhone catalog here, as 2C's contract addition says, once no Swift and no Android code uses it. Contracts §18's "stays in the catalog for older Macs" paraphrases 2C loosely: 2C keeps the key only because 3E's Android placeholder reads it until this plan (2C Spec note 11), and older Macs get `terminal.needsUpdate` on both phones.
15. **The paste menu label** is the Android-only `terminal_paste`: the iPhone uses the system's edit menu, which brings its own word.
16. **Paging while zoomed.** UIKit hands a zoomed scroll view's edge over to the page swipe. Android locks paging while the grid is wider than the pane, so a sideways drag always pans; the chips still switch pages.
17. **Measurements** go into the parity ledger (this plan's brief); 2C wrote the iPhone's into `shellx-mobile-workspaces.md`.
18. **2C's counts.** `TerminalInputBatcherTests` has 8 tests with `testPasteLimitIs256KiB` (2C's "Executed 26" predates it). 2C's Contract additions list 19 strings, but its Task 8 adds `terminal.paste.tooLarge`, making 20.
19. **`ShellPanePlaceholder` stays.** Contracts §5 says 3G replaces it with `TerminalPane`. As on the iPhone, it stays as the page of a Mac whose ShellX shows no terminals, with the needs-update text.
20. **The notice name.** 2C's R12 names the notice `pasteTooLarge` without fixing a Swift property. Android uses `TerminalViewState.pasteTooLarge`, a counter.

## Contract additions

Names other plans or later work rely on. This plan does not edit the contracts; the orchestrator adds them.

- **Kotlin Link (`com.shellx.link.core`).**
  - Open enums `TerminalViewOpenOutcome`, `TerminalViewEndReason`, `TerminalModifier`, `TerminalFrameKind`, `TerminalCursorShape`, `TerminalAttribute`, and `TerminalKey` (`letter(c)`, `letter`, `isKnown`, `ALL_KNOWN`).
  - `TerminalInputUnit` (`Text`, `Key`, `Paste`, `Scroll`, `Other`), `TerminalInputCheck`, `TerminalInputException(reason)`.
  - The grid types; `TerminalFrameAssembler`, `TerminalAssemblyResult`; `TerminalScreen` (mutable, `DEFAULT_MAX_HISTORY_ROWS`), `TerminalRow`, `TerminalStyledRun`, `TerminalCell`.
  - The ten `LinkMessage` classes `TerminalViewOpen` … `TerminalCreateResult`; the `ShellXLink.TERMINAL_*` constants.
  - `TerminalViewPush` (`Opened`, `Frame`, `Ended`), `TerminalCreated`, and the `LinkSession` members `terminalPushes`, `openTerminalView`, `closeTerminalView`, `sendTerminalInput`, `resizeTerminalView`, `resyncTerminalView`, `createTerminal`, with defaults.
  - No `TerminalFrameSplitter` in Kotlin.
- **`:core`.**
  - `com.shellx.core.terminal`: `TerminalLink`, `TerminalHubEvent`, `TerminalOpenResult`, `TerminalCreation`, `TerminalTextInput`, `TerminalTyping`, `TerminalInputBatcher` (`MAX_PASTE_BYTES`, `pasteFits`), `TerminalKeyCodes`, `TerminalHardwareModifiers`, `TerminalHardwareAction`, `TerminalHardwareKeys`, `TerminalBarKey`, `TerminalGeometry`, `TerminalGridSize`, `TerminalScrollStep`, `TerminalZoom`, `TerminalViewport`, `TerminalColors`, `TerminalRgb`, `TerminalResolvedStyle`, `TerminalViewModel`, `TerminalViewState` (with `pasteTooLarge`), `TerminalViewPhase`, `TerminalUnavailableReason`.
  - `MachineHub : TerminalLink` with `supportsTerminalCreate`, `createTerminal(ref)`; `HubState.supportsTerminalView` and `supportsTerminalCreate`; `MachineEvent.Terminal`; `LatencyMetric.TERMINAL_FIRST_SCREEN`, `TERMINAL_KEY_ECHO`, `TERMINAL_FRAME_APPLY`.
  - `WorkspaceScreenModel.shownAsTerminal`, `showAsTerminal`, `terminalShown`, `expect`.
  - The demo: `DemoTerminalFixture`, `DemoTerminalScreens`, `DemoEnvironment.TERMINALS`, and the `FakeMac` terminal API, whose `hostFeatures` now include `terminal_view` and `terminal_create` by default.
- **`:app`.**
  - `com.shellx.app.ui.terminal`: `TerminalPane(model, terminalId, title, shown, modifier, locksPaging, showsKeyBar)` and `TerminalPane.perform`, `TerminalSurfaceView`, `TerminalInputConnection`, `TerminalIme` / `SystemTerminalIme` / `LocalTerminalIme`, `TerminalClipboard`, `TerminalKeyBar` / `TerminalKeyBarItem`, `TerminalFont`, `TerminalGlyphMetrics`, `TerminalRowLayout`, `TerminalRowCache`.
  - On 3E's workspace screen: `WorkspaceMenuItem.VIEW_AS_TERMINAL`, `VIEW_AS_CHAT` and `AgentChip`; `WorkspaceCommand.CREATE_TERMINAL`; `WorkspaceScreen(…, canCreateTerminal, canViewTerminals, shownAsTerminal, …)`; `WorkspaceScreenActions(…, createTerminal, showAsTerminal)`; `NewTerminalChip`; `WorkspaceScreenHolder(model, terminal)`.
- **Strings.** The Android-only `terminal_paste` (en/vi) and `terminal_cap_esc`, `terminal_cap_tab`, `terminal_cap_ctrl` (not translated). The iPhone key `workspace.shell.placeholder` is deleted from `shellx-ios/ShellX/Localizable.xcstrings` (Task 14 Step 5), so Android's generated `workspace_shell_placeholder` goes too; older Macs get `terminal.needsUpdate` / `terminal_needs_update` on both phones. This supersedes contracts §18's "stays in the catalog for older Macs" and its count of 19 keys (2C's catalog adds 20, `terminal.paste.tooLarge` included).
- **Keyboard rule for any later Android text surface that must keep Vietnamese composing:** the `EditorInfo` of Design, "Soft keyboard".
- **Ledger.** Rows A-g1 to A-g5, under their final numbers.
