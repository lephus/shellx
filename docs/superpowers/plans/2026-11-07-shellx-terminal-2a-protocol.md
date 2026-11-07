# ShellX Link terminal views (2A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `terminal_view` and `terminal_create` features to ShellX Link: the complete wire format in `shellx-link/spec/PROTOCOL.md` (new section 11, rewritten section 10), golden vectors, and the Swift codec, frame splitter, frame assembler, screen model, host-side protocols, `LinkHost` wiring, `LinkClient` API and `shellx-link-probe` commands that the Mac (2B), the iPhone (2C) and Android (3G) build on.

**Architecture:** The phone receives the grid of styled cells the Mac's terminal already drew, never PTY bytes. Frames are snapshots, deltas or history frames, numbered by a per-view revision with no gaps and split into parts that each fit one 65 519-byte frame. `ShellXLinkCore` holds pure value code (types, codec, `TerminalFrameSplitter`, `TerminalFrameAssembler`, `TerminalScreen`, `TerminalInputCheck`) shared by the iPhone, the Mac's tests and the probe. `ShellXLinkSession` gets the host-side protocols the Mac implements (`TerminalViewSource`, `TerminalView`, `TerminalCreator`), a per-session view slot (one view per session, ordered input) and a pull-based frame pump (numbering, splitting, 240-row snapshot then a background history fill, resync, bounded memory), plus `LinkClient` methods and a `terminalPushes` stream.

**Tech Stack:** Swift 6 language mode (SwiftPM package `shellx-link`, macOS 14 / iOS 17), XCTest, JSON vector files, Markdown.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-mobile-terminal-design.md` (S2, all of §3 and §5) on top of `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md` §7.2, §9, §10, §11. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1 (landing) and §6 (message names).

## Global Constraints

- Change files only under `shellx-link/`. The package stays `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`, platforms `.macOS(.v14), .iOS(.v17)`; no new targets, no `.package(url:)`, no `path:` outside `shellx-link/`.
- Licence: `shellx-link` is MIT. Reading GPL code (`Sources/`, `Packages/`, `ios/`, `cmux-tui/`, `shellx-core/`, `ghostty/`) for reference is allowed; copying any of it is not. Numbers taken from it (240, 4 000, 2 000, 20–300, 5–120) are facts, not code. No string `Manaflow` under `shellx-link/Sources`.
- Protocol: `v` stays 1; every addition is additive and offered through `welcome.features` (`terminal_view`, `terminal_create`); a frame is at most 65 519 UTF-8 bytes (`LinkCodec.maxFrameBytes`); field names are snake_case; optional fields are omitted, never `null`.
- Names: `message.case` / wire `t` exactly as contracts §6 (table in Task 2); Swift names exactly as this plan's Interfaces blocks.
- Compatibility: existing `LinkHost.init` call sites keep compiling (new parameters have defaults and sit after `terminalControl:`); no `LinkClientError` case is added; no public API is removed or renamed.
- Privacy: never log terminal content, typed or pasted text, keys, workspace or tab titles; log codes and counts only (`linkLog`, `privacy: .public` only for codes).
- Never quit, relaunch or replace the user's running ShellX or cmux app; never run `xcodebuild`; this plan builds and tests the SwiftPM package only.
- Run build, test and git commands through `toknix run <command>` (user instruction); the expected output below is what the underlying command prints.
- Commits: conventional (`docs(shellx-link): …`, `feat(shellx-link): …`), staged with explicit `git add <paths>`, on branch `feat/shellx-terminal-2a-protocol`.
- Landing (contracts §1): after the final review, merge into `develop` and push `develop`. Never merge to `main`, never deploy, never publish a release, never upload to a store.

## Review Focus

1. **Multi-byte text at the input limits** (Vietnamese Telex output, emoji): limits count UTF-8 bytes, not characters — 2 048 × `é` (4 096 bytes) is accepted, 2 049 is refused. Pinned in Task 2 (`input_checks` vectors `text_4096_utf8_bytes`, `text_4098_utf8_bytes`).
2. **The Return key arriving as `"\n"` inside typed text** (phone keyboards insert it): the client refuses it before sending, so the app must send `key enter`; the host refuses it too. Pinned in Task 2 (vector `text_with_newline`) and Task 8 (`testClientRefusesTypedNewlineBeforeSending`).
3. **Fast chip swipes** (close A then open B, or open A twice while frames are in flight): no frame of the old view after the new `ok`, the new view starts with a revision-1 snapshot, and input typed before the close is still applied. Pinned in Task 7 (`testReopenRestartsTheView`) and Task 8 (`testInputBeforeCloseIsStillApplied`).
4. **A flood over a slow link** (`yes | head -100000`, `cat` of a 5 MB file): the host holds at most one unsent frame per view, never calls `nextFrame()` concurrently, and the phone ends on the final screen. Pinned in Task 9 (`testSlowPhoneGetsTheLastScreenWithBoundedFrames`).
5. **Output during the history fill**: rows scrolling into history at the newest end while older rows are prepended — the phone's history stays contiguous and in order. Pinned in Task 9 (`testDeltaDuringTheFillKeepsTheHistoryInOrder`).

---

## Wire specification (normative)

Task 1 appends the block below to `shellx-link/spec/PROTOCOL.md` as section 11, word for word. Every later task implements it; where a task and this text disagree, this text wins.

~~~~markdown
## 11. Terminal views

A phone can show one terminal of the host and type into it (`terminal_view`), and open a new terminal tab in a
workspace (`terminal_create`). The phone gets the screen the Mac's terminal has already drawn, as a grid of styled
cells, not the bytes the program wrote: it draws cells and never parses escape sequences. A terminal is named by the
`terminal_id` of a Terminal in the workspace list (section 4, Workspace).

### 11.1 Views

- `terminal.view.open` asks to view a terminal at the size the phone can show (`cols`, `rows`, 11.3). The host answers
  `terminal.view.open.result` with an `outcome` (an open enum; a client treats a value it does not know as `failed`):
  - `ok`: the view is open; its frames follow (11.4), the first a snapshot at revision 1;
  - `not_found`: no terminal with this id in a local workspace the host lists;
  - `refused`: the Mac blocks remote control (device management);
  - `busy`: this session already views another terminal;
  - `failed`: the host could not start the view.
- A session views at most one terminal. An open for another terminal while one is open answers `busy` and changes
  nothing: the client closes the first view, then opens the next. An open for the terminal the session already views
  restarts the view: the old one ends without a `terminal.view.ended`, and the answer is that of a new open. Several
  phones, each in its own session, may view the same terminal.
- `terminal.view.close` ends the session's view of that terminal. It has no answer, and the tab stays on the Mac
  (`terminal.close`, section 4, closes a tab). A close for a terminal the session does not view is ignored. A view also
  ends when its session ends. Input that arrived before a close, a restart or the session's end is still applied. When
  a view ends, the terminal goes back to the Mac's own size (11.3).
- `terminal.view.ended` tells the phone that a view ended without the phone asking, or that the phone named a terminal
  it does not view. `reason` is an open enum (a client treats a value it does not know as `failed`):
  - `gone`: the terminal no longer exists (its tab or its workspace was closed);
  - `refused`: the Mac began to block remote control; the phone does not open it again;
  - `failed`: the host could not keep the view going; the phone may open it again;
  - `not_open`: the answer to a `terminal.view.input`, `terminal.view.resize` or `terminal.view.resync` that names a
    terminal the session does not view (never opened, closed, or ended); nothing was applied.

  A client ignores a `terminal.view.ended` for a terminal it does not view.
- Order. The host sends `terminal.view.open.result` before the view's first frame, and no frame of a view after its
  end. A client starts a fresh assembler (11.7) when an `ok` arrives: every frame of that terminal after it belongs to
  the new view. It ignores frames of a terminal it does not view, and frames that arrive before the answer to its
  latest open (frames of an earlier view may still be on the way).
- `terminal.view.open` is a call (section 3). `terminal.view.input`, `terminal.view.resize`, `terminal.view.resync`
  and `terminal.view.close` carry no `call_id` and get no answer, apart from `terminal.view.ended` `not_open` and
  `error` `bad_request` (without `call_id`) for one that breaks a rule of 11.2 or 11.3, which then has no effect.
- A host without `terminal_view` answers `terminal.view.open` with `error` `unsupported` and its `call_id`, and
  ignores the other `terminal.view.*` messages, as a host that predates them does (section 7).

### 11.2 Input

`terminal.view.input` carries `units`: 1 to 64 input units, applied in order; the messages of a view are applied in
the order they arrive. A unit is an object whose `k` (an open enum) selects its other fields:

| `k` | Other fields | What the host does |
| --- | --- | --- |
| `text` | `text` string | Types it, as key presses of its characters. 1 or more UTF-8 bytes, and no control character: nothing in U+0000 to U+001F, U+007F, or U+0080 to U+009F (newline, tab, escape and backspace are keys) |
| `key` | `key` string, `mods` array of strings (optional, omitted when empty) | Presses the named key with the modifiers through the terminal's own key handling, so the program gets what that key sends at the Mac (application cursor keys and the like apply) |
| `paste` | `text` string | Pastes it through the Mac's paste path: bracketed when the program asked for it, so a multi-line text does not run line by line. 1 to 16 384 UTF-8 bytes; tab (U+0009), line feed (U+000A) and carriage return (U+000D) are the only control characters it may hold |
| `scroll` | `lines` int | Turns the terminal's mouse wheel by that many lines: positive toward older content (up), negative toward newer (down), 1 to 100 either way. Only on the alternate screen, where the terminal reports the wheel to the program or turns it into arrow keys as it does at the Mac; on the main screen the host ignores it (the phone scrolls its own history, 11.6) |

- `key` names (an open enum): `enter`, `tab`, `backspace`, `escape`, `delete` (forward delete), `space`, `up`,
  `down`, `left`, `right`, `home`, `end`, `page_up`, `page_down`, and the lowercase letters `a` to `z` (meant for
  chords such as `ctrl` with `c`). `mods` names (an open enum): `ctrl`, `alt`, `shift`, each at most once, in any
  order. There is no `cmd`, `super` or `meta`.
- The `text` of all `text` units of one message is at most 4 096 UTF-8 bytes in all, and that of all `paste` units at
  most 16 384. A phone sends only committed text: text an input method is still composing (marked text) stays on the
  phone, and a backspace that edits it is not sent.
- A host skips a unit whose `k`, `key` or a modifier it does not know and applies the others: a later version may add
  names.
- A message with no unit or more than 64, an empty or oversized `text`, a forbidden control character, a `lines` of 0
  or beyond 100, or a repeated modifier is answered `error` `bad_request` (without `call_id`), and none of its units is
  applied.
- Input reaches only the terminal the session views: a `terminal.view.input` for another `terminal_id` is answered
  `terminal.view.ended` `not_open` and reaches no terminal.
- A host holds at most 64 input and resize messages of a view that it has not applied yet (not counting the one it is
  applying) and drops later ones while that many wait.

### 11.3 Size

`terminal.view.open` and `terminal.view.resize` carry `cols` and `rows`: the grid the phone can show at its font size.
Each is an integer of at least 1; 0 or less is answered `error` `bad_request` (with the `call_id` of an open). The
host clamps `cols` into 20 to 300 and `rows` into 5 to 120, the bounds the Mac accepts from a phone.

The grid has the size of whoever used the terminal last, like tmux's `latest` rule: the phone's size after the phone
opens the view, resizes it or types; the Mac's window size after the user types or resizes there. Frames carry the
grid's actual `cols` and `rows` (up to 1 000 each, so beyond the 300 and 120 a phone may ask for while the Mac's
window owns the size), and a phone draws whatever they say (it scales a wider grid down to fit). When the
view ends, the terminal goes back to the Mac's own size. A `terminal.view.resize` for a terminal the session does not
view is answered `terminal.view.ended` `not_open`.

### 11.4 Frames and parts

`terminal.view.frame` carries one part of one frame of the open view. A frame is a **snapshot** (the whole grid,
which replaces what the phone holds), a **delta** (what changed since the frame before it) or a **history** frame
(older rows for the phone's history, 11.8). Fields:

| Field | Type | Notes |
| --- | --- | --- |
| `terminal_id` | string | The terminal the view shows |
| `revision` | int | 1 or more: the frame's number in its view (11.7) |
| `part` | int | 0 to `parts` - 1: which part of the frame this message carries |
| `parts` | int | 1 to 256: how many messages carry the frame |
| `head` | Head | Required in part 0, absent in the others |
| `styles` | array of Style | Optional, omitted when empty |
| `lines` | array of Line | Optional, omitted when empty |

A frame is the `head` of its part 0, the `styles` of all its parts (one table) and the `lines` of all its parts in
part order. The host sends the parts of a frame in order, with no part of another frame of that terminal in between,
each in one message within the frame limit (section 3).

### 11.5 The grid

The grid has `rows` screen rows of `cols` cells; on the main screen it also has history rows above it.

**Head** (part 0):

| Field | Type | Notes |
| --- | --- | --- |
| `kind` | string | `snapshot`, `delta` or `history` (open enum) |
| `cols`, `rows` | int | The grid size, 1 to 1 000 each |
| `alt` | bool | True while the alternate screen is active (full-screen programs such as vim, less, htop). It has no history |
| `cursor` | Cursor | Required in snapshots and deltas, absent in history frames |
| `palette` | Palette | Required in snapshots, absent otherwise |
| `history` | int | 0 or more, optional (omitted when 0): the history rows this frame carries (11.6) |
| `scroll` | int | 0 or more, deltas only, optional (omitted when 0): rows that left the top of the screen since the frame before |

**Cursor**: `x` int (column, 0 at the left), `y` int (screen row, 0 at the top), `shape` string (`block`, `bar`,
`underline` or `block_hollow`; an open enum, drawn as `block` when unknown), `visible` bool, `blink` bool.

**Palette**: `fg` and `bg` colors (the terminal's default foreground and background, with any change a program made to
them), `cursor` color (optional; absent means the cursor takes the foreground color), `colors` array of exactly 256
colors (the indexed palette). A color is `#` followed by 6 hexadecimal digits (`#rrggbb`; either case is read, hosts
send lowercase).

**Style**: `id` int (1 to 65 535, unique within the frame); `fg` int (a palette index, 0 to 255) or `fg_rgb` color, at
most one of the two, neither meaning the default foreground; `bg` or `bg_rgb` likewise for the background; `attrs`
array of strings (optional, omitted when empty; an open enum whose unknown values a receiver ignores): `bold`,
`faint`, `italic`, `underline`, `blink`, `inverse` (foreground and background swapped), `invisible` (only the
background is drawn), `strike`, `overline`. The colors are those the Mac draws with: a host that shows bold text in
bright colors sends the bright index. The default style (default colors, no attribute) has id 0 and is never listed.
A style id means something only in its frame.

**Line**: `y` int (the row: 0 to `rows` - 1 for the screen, -1 to -`history` for the frame's history rows, -1 being
the newest, right above screen row 0) and `runs` array of Run (optional, omitted when empty; a line without runs is a
blank row). A frame may carry several lines with the same `y`: together, in order, their runs make the row.

**Run**, a stretch of cells of one style: `x` int (optional: the first column; when absent, the column right after
the previous run of the same line, or 0 for the line's first run), `t` string (1 or more UTF-8 bytes), `s` int
(optional: the style id; absent or 0 for the default style), `w` int (optional, 1 or 2):

- without `w` the run is narrow cells: each Unicode scalar of `t` is one cell, one column wide, at `x`, `x` + 1, and
  so on;
- with `w` the run is exactly one cell holding all of `t` (a grapheme cluster: a letter with its combining marks, an
  emoji sequence, a flag) and `w` columns wide; a wide cell (`w` 2) covers its column and the next.

Cells no run covers are blank: a space in the default style. A run ends at `x` plus its number of scalars (narrow) or
plus `w` (one cell).

A host sends every character that combines with others, or that is not one column wide, as a cell of its own with
`w`; puts at most 32 UTF-8 bytes in one cell (cutting a longer cluster on a scalar boundary); and sends no runs that
overlap or reach past `cols`. A receiver is lenient, so a slip draws wrong but never breaks the view: it drops cells
at or past `cols` (and a wide cell that does not fit whole), lets a later run overwrite an earlier one cell by cell,
ignores a line whose `y` is outside the frame's range, uses the default style for a style id the frame does not list,
and moves a cursor that lies outside the grid to the nearest cell.

### 11.6 Applying a frame

A client keeps, for the view: the grid size, `alt`, the cursor, the palette, the screen rows, and the history rows,
oldest first. It applies a frame that passed the rules of 11.7:

- **snapshot**: everything is replaced. The size, `alt`, cursor and palette are the head's; the screen is rows 0 to
  `rows` - 1; the history is rows -`history` to -1, oldest first (none on the alternate screen).
- **delta**: first the scroll. With `s` the `scroll` and `k` = min(`s`, `rows`), the top `k` screen rows go to the end
  of the history, followed by the delta's history rows -`history` to -1, oldest first; the other screen rows move up
  by `k`, and `k` blank rows enter at the bottom. When more rows scrolled than the screen holds (`s` > `rows`), the
  `s` - `rows` rows in between never reached the phone: the delta carries the newest of them as its history rows (at
  most `s` - `rows`; a receiver ignores the oldest beyond that) and the rest are not shown. Then each screen row the
  delta has lines for is replaced by them (a line without runs blanks it); the other rows stay as they are. Last, the
  cursor is the head's. A delta of the alternate screen has no scroll (a receiver ignores one there).
- **history**: its rows -`history` to -1 go above the oldest history row the client holds, oldest first: the history
  grows upward.
- A client keeps as many history rows as it likes and drops the oldest first. Once it has dropped any since the last
  snapshot (or did not keep all of that snapshot's), it ignores history frames until the next snapshot: their rows
  could no longer join.

### 11.7 Revisions, gaps and resync

Within a view the host numbers its frames 1, 2, 3, ... whatever their kind, with no gap, the first being a snapshot.
A client keeps the revision of the last frame it applied (its current revision, 0 before the first) and assembles
parts:

- A part 0 starts a frame. If the frame before it still lacked parts, that frame is lost: a gap.
- Any other part must continue the frame being assembled: same `revision` and `parts`, and `part` one more than the
  last. Otherwise it is a gap, and the client drops that frame and the part.
- With its last part, the frame is complete:
  - a snapshot whose revision is above the current one is applied;
  - a delta or history frame whose revision is the current one + 1, and whose `cols`, `rows` and `alt` equal the
    client's, is applied;
  - a frame whose revision is at or below the current one is ignored (the client already has what it says);
  - anything else is a gap: a delta or history frame further ahead, of another size or screen, or before the first
    snapshot; a `kind` the client does not know; a snapshot without cursor or palette, or a delta without cursor; a
    size beyond 1 000.
- On a gap the client sends `terminal.view.resync` once, then ignores deltas and history frames until a snapshot
  arrives, and sends no other resync before that snapshot. The host answers a resync with a snapshot (11.8).

### 11.8 What a host sends

- After `ok`, a snapshot. A snapshot of the main screen carries at most the newest 240 history rows, so the view
  appears fast. Right after it the host sends older history of the same capture in history frames, the rows just
  above those 240 first, at most 240 rows per frame, until the snapshot and its history frames hold 4 000 rows, or
  until the history frames' messages would pass 262 144 bytes, whichever comes first. A history frame never holds up a
  delta: the host sends one only while no other frame of the view waits.
- Then a delta whenever the terminal changes, against the frame sent before it. The host merges changes instead of
  queueing them: it asks the terminal for the next frame only when no frame it made is waiting, so it holds at most
  one frame per view that it has not begun to send, and a slow phone or network gets fewer, larger deltas. A delta
  carries at most 2 000 history rows.
- A new size, a switch between the main and the alternate screen, and a new palette come as a snapshot. A new
  snapshot drops what is left of the fill of the one before and begins its own: after a resize that rewraps the
  history, the phone gets it again the same way.
- On `terminal.view.resync` the host drops the deltas and history frames it has not begun to send and sends a
  snapshot next. Resyncs that arrive before that snapshot share it.
- The host never logs terminal content, or keys or text a phone typed or pasted.

### 11.9 New terminals

`terminal.create` (`terminal_create`) opens a new terminal tab in a workspace the host lists, in the pane the Mac has
selected in that workspace, running the user's default shell, as when the user adds a tab there. It does not change
what the Mac has selected (the workspace, the pane, the tab shown in each pane), moves no focus and brings no window
to the front. `terminal.create.result` carries an `outcome` (the open enum of the workspace calls: `ok`; `not_found`
for a workspace the host does not list; `refused` when the Mac blocks remote control or its own rules forbid it;
`failed`) and, only with `ok`, the new `terminal_id`. A `workspace.changed` lists the new terminal too; it and the
answer may arrive in either order. The call carries a `workspace_id` and nothing else: no command, path, directory,
program or environment. A client does not send it again after losing the connection; it reads the workspace list
instead. A host without `terminal_create` answers `error` `unsupported`.

### 11.10 Limits

| Limit | Value |
| --- | --- |
| `cols`, `rows` a phone asks for | at least 1; the host clamps them into 20 to 300 and 5 to 120 |
| Grid size in a frame | 1 to 1 000 columns and rows |
| Parts of one frame | 1 to 256 |
| Text of one cell (a run with `w`) | at most 32 UTF-8 bytes |
| History rows in a snapshot | at most 240 |
| History frames | at most 240 rows each; snapshot plus its history frames at most 4 000 rows; their messages at most 262 144 bytes |
| History rows in a delta | at most 2 000, and at most `scroll` - `rows` |
| Units in one input message | 1 to 64 |
| Typed text in one input message | each unit 1 byte or more; 4 096 UTF-8 bytes in all |
| Pasted text in one input message | each unit 1 to 16 384 UTF-8 bytes; 16 384 in all |
| `lines` of a scroll unit | 1 to 100, either sign |
| Input and resize messages waiting per view | 64 |
| Views per session | 1 |
| Frames per view made but not yet being sent | 1 |
~~~~

---

## File map

| Path | Responsibility | Task |
| --- | --- | --- |
| `shellx-link/spec/PROTOCOL.md` | §3, §4, §6, §8 cross-references; new §11; §10 rewrite | 1, 10 |
| `shellx-link/spec/vectors/messages.json` | Vectors of the ten new messages | 2, 3 |
| `shellx-link/spec/vectors/terminal.json` (new) | Palette, limits, key names, input checks, screens | 2, 4 |
| `Sources/ShellXLinkCore/ShellXLink.swift` | The two feature names | 2 |
| `Sources/ShellXLinkCore/ShellXLink+Terminal.swift` (new) | Terminal limits | 2 |
| `Sources/ShellXLinkCore/Messages/TerminalView.swift` (new) | Outcomes, end reasons, keys, modifiers, input units | 2 |
| `Sources/ShellXLinkCore/Messages/TerminalInputCheck.swift` (new) | Input rules of 11.2 | 2 |
| `Sources/ShellXLinkCore/Messages/LinkMessage.swift`, `LinkCodec.swift` | Ten cases and their wire form | 2, 3 |
| `Sources/ShellXLinkCore/Terminal/TerminalGrid.swift` (new) | Grid wire types (11.4, 11.5) | 3 |
| `Sources/ShellXLinkCore/Terminal/TerminalFrameAssembler.swift` (new) | Parts, revisions, gaps (11.7) | 4 |
| `Sources/ShellXLinkCore/Terminal/TerminalScreen.swift` (new) | Applying frames (11.6) | 4 |
| `Sources/ShellXLinkCore/Terminal/TerminalFrameSplitter.swift` (new) | One frame into parts | 5 |
| `Sources/ShellXLinkSession/TerminalCreator.swift` (new) | Host protocol for `terminal.create` | 6 |
| `Sources/ShellXLinkSession/TerminalViewSource.swift` (new) | Host protocols for views | 7 |
| `Sources/ShellXLinkSession/TerminalViewSlot.swift` (new, internal) | One view per session, input lane | 7, 8 |
| `Sources/ShellXLinkSession/TerminalViewPump.swift` (new, internal) | Pull, number, split, send, fill, resync | 7, 8, 9 |
| `Sources/ShellXLinkSession/LinkHost.swift`, `LinkClient.swift` | Wiring and client API | 2, 3, 6, 7, 8 |
| `Sources/shellx-link-probe/Terminal.swift` (new), `main.swift`, `Support.swift`, `shellx-link/README.md` | Probe commands and docs | 11 |
| `Tests/ShellXLinkCoreTests/…` | `LinkCodecTests` (extended), `TerminalVectorTests`, `TerminalFrameCodecTests`, `TerminalScreenTests`, `TerminalFrameSplitterTests` | 2–5 |
| `Tests/ShellXLinkSessionTests/…` | `TerminalSessionTestCase`, `FakeTerminalViewSource`, `TerminalSessionTests`, `TerminalFillTests` | 2, 3, 6–9 |

(`Sources/…` and `Tests/…` are under `shellx-link/`.)

---

### Task 0: Set up the worktree

**Files:** none.

- [ ] **Step 1: Create the worktree** with superpowers:using-git-worktrees. This repository keeps worktrees in `.worktrees/` (excluded through `.git/info/exclude`).

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git worktree add .worktrees/terminal-2a-protocol -b feat/shellx-terminal-2a-protocol develop
cd .worktrees/terminal-2a-protocol
```

- [ ] **Step 2: Note where the plans live.** This plan and the contracts file may be untracked in the main checkout, so the worktree does not have them. Read them from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/`; never add them to this branch.

- [ ] **Step 3: Check the baseline**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: the summary ends `with 0 failures (0 unexpected)` (RelayIntegrationTests skip: `CMUX_RELAY_BIN` is not set).
Run: `bash scripts/shellx/check-link-license.sh; echo "exit=$?"`
Expected: `exit=0`. If either is red, stop and report it before any change.

---

### Task 1: The protocol text (PROTOCOL.md section 11 and its cross-references)

**Files:**
- Modify: `shellx-link/spec/PROTOCOL.md` (line numbers as on `develop` before this task: §3 lines 65-68 and 79-89, §4 after line 142 and lines 146-149, Features after line 189, §6 lines 497-498, §8 lines 574-575 and after line 618, append §11)

**Interfaces:**
- Produces: the normative text every later task (and 2B, 2C, 3G) implements.

- [ ] **Step 1: §4 message table.** Insert after the row of `terminal.close.result` (line 142), before `ping`:

```markdown
| `terminal.view.open` | client | The user opens a terminal pane: start a view (section 11) | `call_id` string, `terminal_id` string, `cols` int, `rows` int |
| `terminal.view.open.result` | host | Reply to every acceptable `terminal.view.open` | `call_id` string, `outcome` string |
| `terminal.view.frame` | host | One part of a frame of the open view | `terminal_id` string, `revision` int, `part` int, `parts` int, `head` object (part 0 only), `styles` array (optional), `lines` array (optional); section 11 |
| `terminal.view.input` | client | The user types, presses a key, pastes or scrolls in the open view | `terminal_id` string, `units` array of input units (section 11) |
| `terminal.view.resize` | client | The phone's terminal area changed size | `terminal_id` string, `cols` int, `rows` int |
| `terminal.view.resync` | client | The phone missed part of the stream and needs a snapshot | `terminal_id` string |
| `terminal.view.close` | client | The user leaves the terminal pane (the tab stays on the Mac) | `terminal_id` string |
| `terminal.view.ended` | host | A view ended without the phone asking, or the phone named a terminal it does not view | `terminal_id` string, `reason` string |
| `terminal.create` | client | The user opens a new terminal tab in a workspace | `call_id` string, `workspace_id` string |
| `terminal.create.result` | host | Reply to every acceptable `terminal.create` | `call_id` string, `outcome` string, `terminal_id` string (the new terminal; present only when `outcome` is `ok`) |
```

- [ ] **Step 2: Error codes.** In the `unsupported` parenthesis (lines 147-148; the phrase breaks after "no agent") replace `no agent control or no terminal control, or does not know` with `no agent control or no terminal control, offers no terminal views or no terminal creation, or does not know`.

- [ ] **Step 3: Features.** Append after the `terminal_close` bullet (line 189):

```markdown
- `terminal_view`: the host takes `terminal.view.open`, `terminal.view.input`, `terminal.view.resize`,
  `terminal.view.resync` and `terminal.view.close`, and sends `terminal.view.frame` and `terminal.view.ended`
  (section 11).
- `terminal_create`: the host takes `terminal.create` (section 11).
```

- [ ] **Step 4: §3.** (a) Replace the whole "Every string enum field is an open enum" bullet (lines 65-68, through "it is never `bad_json`.") with:

```markdown
- Every string enum field is an open enum: `kind` (of a PendingItem, of a decision, of a ChatEntry, of an
  `attach.begin` and of a terminal frame's head), `mode`, `outcome`, `state` (of an AgentSession), `role` (of a
  ChatEntry), `reason` (of a `terminal.view.ended`), `k`, `key` and the `mods` entries (of a terminal input unit),
  `shape` (of a terminal cursor), the `attrs` entries (of a terminal style), and the enum fields later versions add.
  A value this version does not know still decodes (an implementation keeps the raw string, for example as
  `.other(raw)`); it is never `bad_json`.
```

(b) In "Call ids" replace `` `agent.close` and `terminal.close` (and the requests`` with `` `agent.close`, `terminal.close`, `terminal.view.open` and `terminal.create` (and the requests``, and replace `` `agent.close.result`, `terminal.close.result`), or an `error` `` with `` `agent.close.result`, `terminal.close.result`, `terminal.view.open.result`, `terminal.create.result`), or an `error` ``.

- [ ] **Step 5: §6.** The sentence at lines 497-498, "Splitting one logical message into several frames is not defined in v1, except for `chat.entries` (below).", ends instead with ``except for `chat.entries` (below) and `terminal.view.frame` (section 11.4).``

- [ ] **Step 6: §8.** (a) Lines 574-575 become: ``` `message.case` names the message; the other `message` keys use the JSON field names (`decision`, PendingItem objects, and the `head`, `styles`, `lines` and `units` of the terminal messages use their wire form). All 51 cases: ```. (b) Insert after the `terminal_close_result` row (line 618), before `unknown`:

```markdown
| `terminal_view_open` | `terminal.view.open` | `call_id`, `terminal_id`, `cols`, `rows` |
| `terminal_view_open_result` | `terminal.view.open.result` | `call_id`, `outcome` |
| `terminal_view_frame` | `terminal.view.frame` | `terminal_id`, `revision`, `part`, `parts`, `head` (optional), `styles` (optional), `lines` (optional) |
| `terminal_view_input` | `terminal.view.input` | `terminal_id`, `units` |
| `terminal_view_resize` | `terminal.view.resize` | `terminal_id`, `cols`, `rows` |
| `terminal_view_resync` | `terminal.view.resync` | `terminal_id` |
| `terminal_view_close` | `terminal.view.close` | `terminal_id` |
| `terminal_view_ended` | `terminal.view.ended` | `terminal_id`, `reason` |
| `terminal_create` | `terminal.create` | `call_id`, `workspace_id` |
| `terminal_create_result` | `terminal.create.result` | `call_id`, `outcome`, `terminal_id` (optional) |
```

(c) After the table, before `## 9`, add:

```markdown
`spec/vectors/terminal.json` holds the vectors of section 11:

- `palette`: a Palette. In `screens`, a head whose `palette` is the string `"@palette"` stands for it: a test puts the
  object in before decoding.
- `limits` (the values of 11.10, by name), `keys` and `modifiers` (the names of 11.2, in the order given there).
- `input_checks`: `{name, units, ok}`. `units` is the `units` of a `terminal.view.input`; `ok` is true when a host
  applies the message (it skips unknown kinds, keys and modifiers) and false when it answers `bad_request`.
- `screens`: `{name, max_history_rows (optional: how many history rows the client keeps), frames, expect}`. A client
  that follows 11.6 and 11.7 is given the `frames` (whole `terminal.view.frame` messages) in order; afterwards it must
  hold `expect`: `revision` (its current revision), `resyncs` (how many `terminal.view.resync` it sent), `cols`,
  `rows`, `alt`, `cursor` (optional), `screen` and `history` (each row as text: the cells' text from left to right, a
  blank cell as a space, nothing for the second column of a wide cell, trailing spaces removed) and `cells`
  (optional): `{x, y, kind}` with `kind` `glyph` (and `t`, `w`, and `style` with `fg`, `fg_rgb`, `bg`, `bg_rgb`,
  `attrs`, absent for the default style), `blank`, or `continuation` (the second column of a wide cell); a negative
  `y` counts history rows from the newest (-1).
```

- [ ] **Step 7: Append section 11** — the "Wire specification (normative)" block of this plan, word for word, after section 10.

- [ ] **Step 8: Verify**

Run:
```bash
grep -c '^## 11\. Terminal views$' shellx-link/spec/PROTOCOL.md
grep -c '^| `terminal\.view\.' shellx-link/spec/PROTOCOL.md
grep -c '^| `terminal_view_\|^| `terminal_create' shellx-link/spec/PROTOCOL.md
grep -c 'All 51 cases' shellx-link/spec/PROTOCOL.md
grep -c '^### 11\.' shellx-link/spec/PROTOCOL.md
```
Expected: `1`, `8`, `10`, `1`, `10`.

- [ ] **Step 9: Commit**

```bash
git add shellx-link/spec/PROTOCOL.md
git commit -m "docs(shellx-link): terminal views and terminal.create in PROTOCOL.md"
```

---

### Task 2: Call-level types, input rules and the codec of nine messages

**Files:**
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/TerminalView.swift`
- Create: `shellx-link/Sources/ShellXLinkCore/Messages/TerminalInputCheck.swift`
- Create: `shellx-link/Sources/ShellXLinkCore/ShellXLink+Terminal.swift`
- Modify: `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift:26` (add two features after `terminalCloseFeature`)
- Modify: `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift:55` (nine cases after `terminalCloseResult`)
- Modify: `shellx-link/Sources/ShellXLinkCore/Messages/LinkCodec.swift` (`T` names 18-39, bodies 41-86, encode 126-239, decode 266-377)
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift:429-441`, `shellx-link/Sources/ShellXLinkSession/LinkClient.swift:551-585` (the exhaustive switches)
- Modify: `shellx-link/spec/vectors/messages.json`
- Create: `shellx-link/spec/vectors/terminal.json`
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift:750-851` (`message(from:)`), create `shellx-link/Tests/ShellXLinkCoreTests/TerminalVectorTests.swift`, create `shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTestCase.swift` and `shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTests.swift`

**Interfaces:**
- Produces (ShellXLinkCore):

```swift
// ShellXLink.swift
public static let terminalViewFeature = "terminal_view"
public static let terminalCreateFeature = "terminal_create"

// ShellXLink+Terminal.swift: extension ShellXLink
public static let terminalColumns: ClosedRange<Int> = 20...300
public static let terminalRows: ClosedRange<Int> = 5...120
public static let terminalMaxGridSize = 1000
public static let terminalMaxFrameParts = 256
public static let terminalMaxCellTextBytes = 32
public static let terminalSnapshotHistoryRows = 240
public static let terminalHistoryRowBudget = 4000
public static let terminalHistoryFillMaxBytes = 262_144
public static let terminalMaxDeltaHistoryRows = 2000
public static let terminalMaxInputUnits = 64
public static let terminalMaxTextBytes = 4096
public static let terminalMaxPasteBytes = 16_384
public static let terminalMaxScrollLines = 100
public static let terminalMaxQueuedInputs = 64

// TerminalView.swift (all LinkWireEnum: unknown wire strings decode to .other(raw))
public enum TerminalViewOpenOutcome: LinkWireEnum { case ok, notFound, refused, busy, failed; case other(String) }
    // "ok", "not_found", "refused", "busy", "failed"
public enum TerminalViewEndReason: LinkWireEnum { case gone, refused, failed, notOpen; case other(String) }
    // "gone", "refused", "failed", "not_open"
public enum TerminalKey: LinkWireEnum {
    case enter, tab, backspace, escape, delete, space, up, down, left, right, home, end, pageUp, pageDown
    case letter(Character)        // wire: one of "a"..."z" (lowercase ASCII only)
    case other(String)
    /// The 40 names of PROTOCOL.md 11.2 in that order: the 14 named keys, then .letter("a") ... .letter("z").
    public static let allKnown: [TerminalKey]
}   // pageUp <-> "page_up", pageDown <-> "page_down", the rest are their own names
public enum TerminalModifier: LinkWireEnum { case ctrl, alt, shift; case other(String) }
public enum TerminalInputUnit: Codable, Equatable, Sendable {
    case text(String)                                  // {"k":"text","text":…}
    case key(TerminalKey, mods: [TerminalModifier])    // {"k":"key","key":…,"mods":[…]} mods omitted when empty
    case paste(String)                                 // {"k":"paste","text":…}
    case scroll(lines: Int)                            // {"k":"scroll","lines":…}
    case other(kind: String)                           // unknown k: other fields dropped; encodes {"k":kind}
}

// TerminalInputCheck.swift
public struct TerminalInputError: Error, Equatable, Sendable { public let reason: String; public init(reason: String) }
public enum TerminalInputCheck {
    /// The rules of PROTOCOL.md 11.2. `reason` is a fixed English phrase and never quotes the units.
    public static func check(_ units: [TerminalInputUnit]) throws(TerminalInputError)
}

// LinkMessage.swift, after terminalCloseResult
case terminalViewOpen(callId: String, terminalId: String, cols: Int, rows: Int)
case terminalViewOpenResult(callId: String, outcome: TerminalViewOpenOutcome)
case terminalViewInput(terminalId: String, units: [TerminalInputUnit])
case terminalViewResize(terminalId: String, cols: Int, rows: Int)
case terminalViewResync(terminalId: String)
case terminalViewClose(terminalId: String)
case terminalViewEnded(terminalId: String, reason: TerminalViewEndReason)
case terminalCreate(callId: String, workspaceId: String)
case terminalCreateResult(callId: String, outcome: WorkspaceControlOutcome, terminalId: String?)
```

- Produces (tests): `class TerminalSessionTestCase: XCTestCase` with `struct Rig { host, hostKey, clientKey }`, `makeHost() -> Rig`, `startServe(_ rig: Rig, wrap: @escaping @Sendable (any RelayCircuit) -> any RelayCircuit = { $0 }) -> (end: any RelayCircuit, served: Flag)`, `connect(_ rig: Rig, wrap: …) async throws -> LinkClient`, `rawSession(_ rig: Rig) async throws -> SecureChannel` (handshake, `hello`, `welcome` read), and `tearDown` that closes clients and cancels serve tasks — the same pattern as `WorkspaceSessionTests.swift:541-630`. Tasks 6 and 7 add parameters to `makeHost`; later tasks add helpers.

Wire table (contracts §6; `TerminalViewFrame` comes in Task 3):

| `message.case` | `t` | Swift case |
| --- | --- | --- |
| `terminal_view_open` | `terminal.view.open` | `terminalViewOpen` |
| `terminal_view_open_result` | `terminal.view.open.result` | `terminalViewOpenResult` |
| `terminal_view_input` | `terminal.view.input` | `terminalViewInput` |
| `terminal_view_resize` | `terminal.view.resize` | `terminalViewResize` |
| `terminal_view_resync` | `terminal.view.resync` | `terminalViewResync` |
| `terminal_view_close` | `terminal.view.close` | `terminalViewClose` |
| `terminal_view_ended` | `terminal.view.ended` | `terminalViewEnded` |
| `terminal_create` | `terminal.create` | `terminalCreate` |
| `terminal_create_result` | `terminal.create.result` | `terminalCreateResult` |

- [ ] **Step 1: Add the message vectors** to `shellx-link/spec/vectors/messages.json`.

Append to `vectors` (each `json` is `message` without `case`, plus `"v": 1` and its `t` from the table):

```json
{"name": "terminal_view_open", "message": {"case": "terminal_view_open", "call_id": "c100", "terminal_id": "t-1", "cols": 46, "rows": 30}, "json": {"v": 1, "t": "terminal.view.open", "call_id": "c100", "terminal_id": "t-1", "cols": 46, "rows": 30}},
{"name": "terminal_view_open_result_ok", "message": {"case": "terminal_view_open_result", "call_id": "c100", "outcome": "ok"}, "json": {"v": 1, "t": "terminal.view.open.result", "call_id": "c100", "outcome": "ok"}},
{"name": "terminal_view_open_result_busy", "message": {"case": "terminal_view_open_result", "call_id": "c100", "outcome": "busy"}, "json": {"v": 1, "t": "terminal.view.open.result", "call_id": "c100", "outcome": "busy"}},
{"name": "terminal_view_open_result_not_found", "message": {"case": "terminal_view_open_result", "call_id": "c100", "outcome": "not_found"}, "json": {"v": 1, "t": "terminal.view.open.result", "call_id": "c100", "outcome": "not_found"}},
{"name": "terminal_view_input_text_and_enter", "message": {"case": "terminal_view_input", "terminal_id": "t-1", "units": [{"k": "text", "text": "ls -la"}, {"k": "key", "key": "enter"}]}, "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "text", "text": "ls -la"}, {"k": "key", "key": "enter"}]}},
{"name": "terminal_view_input_ctrl_c", "message": {"case": "terminal_view_input", "terminal_id": "t-1", "units": [{"k": "key", "key": "c", "mods": ["ctrl"]}]}, "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "key", "key": "c", "mods": ["ctrl"]}]}},
{"name": "terminal_view_input_paste_and_scroll", "message": {"case": "terminal_view_input", "terminal_id": "t-1", "units": [{"k": "paste", "text": "echo a\necho b"}, {"k": "scroll", "lines": -3}]}, "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "paste", "text": "echo a\necho b"}, {"k": "scroll", "lines": -3}]}},
{"name": "terminal_view_resize", "message": {"case": "terminal_view_resize", "terminal_id": "t-1", "cols": 80, "rows": 24}, "json": {"v": 1, "t": "terminal.view.resize", "terminal_id": "t-1", "cols": 80, "rows": 24}},
{"name": "terminal_view_resync", "message": {"case": "terminal_view_resync", "terminal_id": "t-1"}, "json": {"v": 1, "t": "terminal.view.resync", "terminal_id": "t-1"}},
{"name": "terminal_view_close", "message": {"case": "terminal_view_close", "terminal_id": "t-1"}, "json": {"v": 1, "t": "terminal.view.close", "terminal_id": "t-1"}},
{"name": "terminal_view_ended_gone", "message": {"case": "terminal_view_ended", "terminal_id": "t-1", "reason": "gone"}, "json": {"v": 1, "t": "terminal.view.ended", "terminal_id": "t-1", "reason": "gone"}},
{"name": "terminal_view_ended_not_open", "message": {"case": "terminal_view_ended", "terminal_id": "t-2", "reason": "not_open"}, "json": {"v": 1, "t": "terminal.view.ended", "terminal_id": "t-2", "reason": "not_open"}},
{"name": "terminal_create", "message": {"case": "terminal_create", "call_id": "c101", "workspace_id": "ws-1"}, "json": {"v": 1, "t": "terminal.create", "call_id": "c101", "workspace_id": "ws-1"}},
{"name": "terminal_create_result_ok", "message": {"case": "terminal_create_result", "call_id": "c101", "outcome": "ok", "terminal_id": "t-9"}, "json": {"v": 1, "t": "terminal.create.result", "call_id": "c101", "outcome": "ok", "terminal_id": "t-9"}},
{"name": "terminal_create_result_refused", "message": {"case": "terminal_create_result", "call_id": "c101", "outcome": "refused"}, "json": {"v": 1, "t": "terminal.create.result", "call_id": "c101", "outcome": "refused"}}
```

Append to `decode_only`:

```json
{"name": "terminal_view_open_result_unknown_outcome", "json": {"v": 1, "t": "terminal.view.open.result", "call_id": "c100", "outcome": "later"}, "message": {"case": "terminal_view_open_result", "call_id": "c100", "outcome": "later"}},
{"name": "terminal_view_ended_unknown_reason", "json": {"v": 1, "t": "terminal.view.ended", "terminal_id": "t-1", "reason": "evicted"}, "message": {"case": "terminal_view_ended", "terminal_id": "t-1", "reason": "evicted"}},
{"name": "terminal_view_input_unknown_unit_kind", "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "gesture", "dx": 1}, {"k": "text", "text": "a"}]}, "message": {"case": "terminal_view_input", "terminal_id": "t-1", "units": [{"k": "gesture"}, {"k": "text", "text": "a"}]}},
{"name": "terminal_view_input_unknown_key_and_modifier", "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "key", "key": "f13", "mods": ["hyper", "ctrl"]}]}, "message": {"case": "terminal_view_input", "terminal_id": "t-1", "units": [{"k": "key", "key": "f13", "mods": ["hyper", "ctrl"]}]}},
{"name": "terminal_view_input_empty_mods", "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "key", "key": "tab", "mods": []}]}, "message": {"case": "terminal_view_input", "terminal_id": "t-1", "units": [{"k": "key", "key": "tab"}]}}
```

Append to `decode_errors`:

```json
{"name": "terminal_view_open_without_call_id", "json": {"v": 1, "t": "terminal.view.open", "terminal_id": "t-1", "cols": 46, "rows": 30}, "error": "bad_json"},
{"name": "terminal_view_open_missing_rows", "json": {"v": 1, "t": "terminal.view.open", "call_id": "c102", "terminal_id": "t-1", "cols": 46}, "error": "bad_json", "call_id": "c102"},
{"name": "terminal_view_input_key_without_key", "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "key"}]}, "error": "bad_json"},
{"name": "terminal_view_input_text_not_a_string", "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"k": "text", "text": 5}]}, "error": "bad_json"},
{"name": "terminal_view_input_unit_without_k", "json": {"v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": [{"text": "a"}]}, "error": "bad_json"},
{"name": "terminal_create_missing_workspace_id", "json": {"v": 1, "t": "terminal.create", "call_id": "c103"}, "error": "bad_json", "call_id": "c103"},
{"name": "terminal_create_result_missing_outcome", "json": {"v": 1, "t": "terminal.create.result", "call_id": "c104"}, "error": "bad_json", "call_id": "c104"}
```

- [ ] **Step 2: Create `shellx-link/spec/vectors/terminal.json`** with these top-level keys (write long strings literally; a throwaway generator script is fine, do not commit it):
  - `comment`: one sentence pointing to PROTOCOL.md section 8 for how to read the file.
  - `palette`: `{"fg": "#d0d0d0", "bg": "#101010", "cursor": "#ff8800", "colors": [...]}` where `colors[i]` is `"#%02x%02x%02x" % (i, i, i)` for i in 0…255 (`"#000000"` … `"#ffffff"`).
  - `limits`: `{"columns": [20, 300], "rows": [5, 120], "max_grid_size": 1000, "max_frame_parts": 256, "max_cell_text_bytes": 32, "snapshot_history_rows": 240, "history_row_budget": 4000, "history_fill_max_bytes": 262144, "max_delta_history_rows": 2000, "max_input_units": 64, "max_text_bytes": 4096, "max_paste_bytes": 16384, "max_scroll_lines": 100, "max_queued_inputs": 64}`
  - `keys`: `["enter", "tab", "backspace", "escape", "delete", "space", "up", "down", "left", "right", "home", "end", "page_up", "page_down", "a", …, "z"]` (40 names).
  - `modifiers`: `["ctrl", "alt", "shift"]`
  - `screens`: `[]` (Task 4 fills it).
  - `input_checks` (name → `units` → `ok`):

| name | `units` | ok |
| --- | --- | --- |
| `text_ascii` | `[{"k":"text","text":"ls -la"}]` | true |
| `text_vietnamese` | `[{"k":"text","text":"Tiếng Việt có dấu"}]` | true |
| `text_4096_utf8_bytes` | one text unit of `"é"` (U+00E9) × 2048 | true |
| `text_4096_bytes_across_units` | two text units of `"a"` × 2048 | true |
| `key_enter` | `[{"k":"key","key":"enter"}]` | true |
| `ctrl_c` | `[{"k":"key","key":"c","mods":["ctrl"]}]` | true |
| `three_modifiers` | `[{"k":"key","key":"left","mods":["shift","alt","ctrl"]}]` | true |
| `paste_with_tab_and_line_breaks` | `[{"k":"paste","text":"echo a\n\techo b\r\n"}]` | true |
| `paste_16384_bytes` | one paste unit of `"a"` × 16384 | true |
| `scroll_both_ends` | `[{"k":"scroll","lines":100},{"k":"scroll","lines":-100}]` | true |
| `unknown_kind_key_and_modifier_are_skipped` | `[{"k":"gesture"},{"k":"key","key":"f13"},{"k":"key","key":"c","mods":["hyper"]}]` | true |
| `sixty_four_units` | 64 × `{"k":"key","key":"tab"}` | true |
| `no_units` | `[]` | false |
| `sixty_five_units` | 65 × `{"k":"key","key":"tab"}` | false |
| `empty_text` | `[{"k":"text","text":""}]` | false |
| `text_with_newline` | `[{"k":"text","text":"ls\n"}]` | false |
| `text_with_escape` | `[{"k":"text","text":"\u001b[31m"}]` | false |
| `text_with_delete_character` | `[{"k":"text","text":"\u007f"}]` | false |
| `text_with_c1_control` | `[{"k":"text","text":"\u0085"}]` | false |
| `text_4098_utf8_bytes` | one text unit of `"é"` × 2049 | false |
| `text_over_4096_bytes_across_units` | text units `"a"` × 2048, `"a"` × 2048, `"a"` | false |
| `empty_paste` | `[{"k":"paste","text":""}]` | false |
| `paste_with_escape` | `[{"k":"paste","text":"\u001b[201~x"}]` | false |
| `paste_16385_bytes` | one paste unit of `"a"` × 16385 | false |
| `scroll_zero` | `[{"k":"scroll","lines":0}]` | false |
| `scroll_101` | `[{"k":"scroll","lines":101}]` | false |
| `repeated_modifier` | `[{"k":"key","key":"c","mods":["ctrl","ctrl"]}]` | false |

- [ ] **Step 3: Write the failing tests**

(a) `LinkCodecTests.message(from:)` gains these cases (hand-written, independent of the codec), plus a helper `static func terminalUnits(_ o: Any?) throws -> [TerminalInputUnit]` mapping `k` `text` → `.text(text)`, `key` → `.key(TerminalKey(wire: key), mods: (mods ?? []).map(TerminalModifier.init(wire:)))`, `paste` → `.paste(text)`, `scroll` → `.scroll(lines:)`, any other `k` → `.other(kind: k)`:

```swift
case "terminal_view_open":
    return .terminalViewOpen(callId: try s("call_id"), terminalId: try s("terminal_id"),
                             cols: try n("cols").intValue, rows: try n("rows").intValue)
case "terminal_view_open_result":
    return .terminalViewOpenResult(callId: try s("call_id"), outcome: TerminalViewOpenOutcome(wire: try s("outcome")))
case "terminal_view_input": return .terminalViewInput(terminalId: try s("terminal_id"), units: try terminalUnits(m["units"]))
case "terminal_view_resize":
    return .terminalViewResize(terminalId: try s("terminal_id"), cols: try n("cols").intValue, rows: try n("rows").intValue)
case "terminal_view_resync": return .terminalViewResync(terminalId: try s("terminal_id"))
case "terminal_view_close": return .terminalViewClose(terminalId: try s("terminal_id"))
case "terminal_view_ended":
    return .terminalViewEnded(terminalId: try s("terminal_id"), reason: TerminalViewEndReason(wire: try s("reason")))
case "terminal_create": return .terminalCreate(callId: try s("call_id"), workspaceId: try s("workspace_id"))
case "terminal_create_result":
    return .terminalCreateResult(callId: try s("call_id"), outcome: WorkspaceControlOutcome(wire: try s("outcome")),
                                 terminalId: m["terminal_id"] as? String)
```

(b) `TerminalVectorTests` (loads `spec/vectors/terminal.json` like `LinkCodecTests.loadVectors()`):

```swift
func testLimitsMatchTheVectors() throws {
    let l = try XCTUnwrap(try Self.vectors()["limits"] as? [String: Any])
    XCTAssertEqual(l["columns"] as? [Int], [ShellXLink.terminalColumns.lowerBound, ShellXLink.terminalColumns.upperBound])
    XCTAssertEqual(l["rows"] as? [Int], [ShellXLink.terminalRows.lowerBound, ShellXLink.terminalRows.upperBound])
    XCTAssertEqual(l["max_grid_size"] as? Int, ShellXLink.terminalMaxGridSize)
    XCTAssertEqual(l["max_frame_parts"] as? Int, ShellXLink.terminalMaxFrameParts)
    XCTAssertEqual(l["max_cell_text_bytes"] as? Int, ShellXLink.terminalMaxCellTextBytes)
    XCTAssertEqual(l["snapshot_history_rows"] as? Int, ShellXLink.terminalSnapshotHistoryRows)
    XCTAssertEqual(l["history_row_budget"] as? Int, ShellXLink.terminalHistoryRowBudget)
    XCTAssertEqual(l["history_fill_max_bytes"] as? Int, ShellXLink.terminalHistoryFillMaxBytes)
    XCTAssertEqual(l["max_delta_history_rows"] as? Int, ShellXLink.terminalMaxDeltaHistoryRows)
    XCTAssertEqual(l["max_input_units"] as? Int, ShellXLink.terminalMaxInputUnits)
    XCTAssertEqual(l["max_text_bytes"] as? Int, ShellXLink.terminalMaxTextBytes)
    XCTAssertEqual(l["max_paste_bytes"] as? Int, ShellXLink.terminalMaxPasteBytes)
    XCTAssertEqual(l["max_scroll_lines"] as? Int, ShellXLink.terminalMaxScrollLines)
    XCTAssertEqual(l["max_queued_inputs"] as? Int, ShellXLink.terminalMaxQueuedInputs)
}

func testKeyAndModifierNames() throws {
    let file = try Self.vectors()
    let keys = try XCTUnwrap(file["keys"] as? [String])
    XCTAssertEqual(keys.count, 40)
    XCTAssertEqual(TerminalKey.allKnown.map(\.wire), keys)
    for key in keys { XCTAssertEqual(TerminalKey(wire: key).wire, key) }
    XCTAssertEqual(TerminalKey(wire: "page_up"), .pageUp)
    XCTAssertEqual(TerminalKey(wire: "c"), .letter("c"))
    XCTAssertEqual(TerminalKey(wire: "C"), .other("C"))
    XCTAssertEqual(TerminalKey(wire: "f13"), .other("f13"))
    XCTAssertEqual([TerminalModifier.ctrl, .alt, .shift].map(\.wire), try XCTUnwrap(file["modifiers"] as? [String]))
    XCTAssertEqual(TerminalModifier(wire: "cmd"), .other("cmd"))
}

func testInputChecks() throws {
    let checks = try XCTUnwrap(try Self.vectors()["input_checks"] as? [[String: Any]])
    XCTAssertEqual(checks.count, 27)
    for check in checks {
        let name = check["name"] as? String ?? "?"
        let frame: [String: Any] = ["v": 1, "t": "terminal.view.input", "terminal_id": "t-1", "units": try XCTUnwrap(check["units"])]
        guard case let .terminalViewInput(_, units) = try LinkCodec.decode(try JSONSerialization.data(withJSONObject: frame)) else {
            return XCTFail("\(name) did not decode as terminal.view.input")
        }
        let passed = (try? TerminalInputCheck.check(units)) != nil
        XCTAssertEqual(passed, try XCTUnwrap(check["ok"] as? Bool), name)
    }
}

func testInputErrorNeverQuotesTheText() {
    XCTAssertThrowsError(try TerminalInputCheck.check([.text("hunter2\n")])) { error in
        XCTAssertFalse((error as? TerminalInputError)?.reason.contains("hunter2") ?? true)
    }
}

func testFeatureNames() {
    XCTAssertEqual(ShellXLink.terminalViewFeature, "terminal_view")
    XCTAssertEqual(ShellXLink.terminalCreateFeature, "terminal_create")
}
```

(c) `TerminalSessionTests.testTerminalCallsWithoutSources` (a `TerminalSessionTestCase`): on `rawSession(makeHost())` send, in order, `.terminalViewOpen(callId: "c1", terminalId: "t-1", cols: 46, rows: 30)` → receive `.error(code: "unsupported", _, callId: "c1")`; `.terminalCreate(callId: "c2", workspaceId: "ws-1")` → `.error("unsupported", _, "c2")`; then `.terminalViewInput(terminalId: "t-1", units: [.text("a")])`, `.terminalViewResize(terminalId: "t-1", cols: 80, rows: 24)`, `.terminalViewResync(terminalId: "t-1")`, `.terminalViewClose(terminalId: "t-1")`, `.ping(nonce: 7)` → the next message is `.pong(nonce: 7)` (nothing answered the four); `.terminalViewOpenResult(callId: "c3", outcome: .ok)` → `.error("bad_request", _, "c3")`; `.terminalCreateResult(callId: "c4", outcome: .ok, terminalId: nil)` → `.error("bad_request", _, "c4")`; `.terminalViewEnded(terminalId: "t-1", reason: .gone)` → `.error("bad_request", _, nil)`.

- [ ] **Step 4: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter 'LinkCodecTests|TerminalVectorTests|TerminalSessionTests'`
Expected: FAIL — the build stops with `error: cannot find 'TerminalViewOpenOutcome' in scope` (or another "cannot find … in scope" for a new name).

- [ ] **Step 5: Implement.** The types, constants and `check` as in Interfaces; in the codec, `T` names from the wire table, one private body struct per shape (`TerminalViewOpen {callId, terminalId, cols, rows}`, `TerminalViewOpenResult {callId, outcome}`, `TerminalViewInput {terminalId, units}`, `TerminalViewSize {terminalId, cols, rows}`, `TerminalRef {terminalId}` for resync and close, `TerminalViewEnded {terminalId, reason}`, `TerminalCreate {callId, workspaceId}`, `TerminalCreateResult {callId, outcome, terminalId?}`); the two calls and two results decode through `call(_:_:)` and encode through `requireValid`. `TerminalInputUnit` has hand-written `Codable` keyed by `k`, `text`, `key`, `mods`, `lines` (like `LinkDecision`). `check` applies, in this order, with these exact reasons: count outside 1…64 → `"an input message carries 1 to 64 units"`; empty text → `"text is empty"`; text scalar in U+0000…U+001F, U+007F, U+0080…U+009F → `"text holds a control character"`; text total > 4096 bytes → `"typed text is over 4096 bytes"`; empty paste → `"pasted text is empty"`; paste control scalar other than U+0009, U+000A, U+000D → `"pasted text holds a control character"`; paste total > 16 384 bytes → `"pasted text is over 16384 bytes"`; scroll `lines` 0 or |lines| > 100 → `"scroll lines must be 1 to 100 either way"`; a modifier wire string repeated in one key → `"a modifier is repeated"`. `.other` units, unknown keys and unknown modifiers pass. In `LinkHost.converse` add: `.terminalViewOpen(callId, …)` → `sendError("unsupported", "this host offers no terminal views", callId:)`; `.terminalCreate(callId, _)` → `sendError("unsupported", "this host takes no terminal creation", callId:)`; `.terminalViewInput, .terminalViewResize, .terminalViewResync, .terminalViewClose` → no answer; `.terminalViewEnded` joins the call-less `bad_request` arm (line 431); `.terminalViewOpenResult(callId, _)` and `.terminalCreateResult(callId, _, _)` join the `bad_request`-with-`call_id` arm (lines 434-440). In `LinkClient.handle`, the two results join the waiter arm (line 551-558) and every other new case joins the ignore arm (lines 581-584).

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path shellx-link --filter 'LinkCodecTests|TerminalVectorTests|TerminalSessionTests'`
Expected: PASS (`… with 0 failures (0 unexpected)`).
Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add shellx-link/Sources/ShellXLinkCore shellx-link/Sources/ShellXLinkSession/LinkHost.swift \
  shellx-link/Sources/ShellXLinkSession/LinkClient.swift shellx-link/spec/vectors/messages.json \
  shellx-link/spec/vectors/terminal.json shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift \
  shellx-link/Tests/ShellXLinkCoreTests/TerminalVectorTests.swift \
  shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTestCase.swift \
  shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTests.swift
git commit -m "feat(shellx-link): terminal view calls, input units and their codec"
```

---

### Task 3: Grid wire types and `terminal.view.frame`

**Files:**
- Create: `shellx-link/Sources/ShellXLinkCore/Terminal/TerminalGrid.swift`
- Modify: `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift` (one more case), `LinkCodec.swift` (frame body; internal `encodedByteCount`)
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift` (client-sent frame is `bad_request`), `LinkClient.swift` (ignore for now)
- Modify: `shellx-link/spec/vectors/messages.json`
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift` (frame mapping), create `shellx-link/Tests/ShellXLinkCoreTests/TerminalFrameCodecTests.swift`, `shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTests.swift`

**Interfaces:**
- Consumes: Task 2's codec helpers.
- Produces:

```swift
public enum TerminalFrameKind: LinkWireEnum { case snapshot, delta, history; case other(String) }
public enum TerminalCursorShape: LinkWireEnum { case block, bar, underline, blockHollow; case other(String) } // "block_hollow"
public enum TerminalAttribute: LinkWireEnum {
    case bold, faint, italic, underline, blink, inverse, invisible, strike, overline; case other(String)
}
public struct TerminalCursor: Codable, Equatable, Sendable {
    public var x: Int, y: Int; public var shape: TerminalCursorShape; public var visible: Bool, blink: Bool
    public init(x: Int, y: Int, shape: TerminalCursorShape = .block, visible: Bool = true, blink: Bool = false)
}
public struct TerminalPalette: Codable, Equatable, Sendable {
    public var fg: String, bg: String; public var cursor: String?; public var colors: [String]
    public init(fg: String, bg: String, cursor: String? = nil, colors: [String])
}
public struct TerminalCellStyle: Equatable, Sendable {
    public var fg: Int?, fgRgb: String?, bg: Int?, bgRgb: String?; public var attrs: [TerminalAttribute]
    public static let `default`: TerminalCellStyle
    public init(fg: Int? = nil, fgRgb: String? = nil, bg: Int? = nil, bgRgb: String? = nil, attrs: [TerminalAttribute] = [])
}
public struct TerminalStyle: Codable, Equatable, Sendable {
    public var id: Int; public var fg: Int?, fgRgb: String?, bg: Int?, bgRgb: String?; public var attrs: [TerminalAttribute]
    public var cellStyle: TerminalCellStyle { get }
    public init(id: Int, fg: Int? = nil, fgRgb: String? = nil, bg: Int? = nil, bgRgb: String? = nil, attrs: [TerminalAttribute] = [])
}
public struct TerminalRun: Codable, Equatable, Sendable {      // wire keys x, t, s, w
    public var x: Int?; public var text: String; public var style: Int?; public var width: Int?
    public init(x: Int? = nil, text: String, style: Int? = nil, width: Int? = nil)
}
public struct TerminalLine: Codable, Equatable, Sendable {     // runs omitted when empty
    public var y: Int; public var runs: [TerminalRun]
    public init(y: Int, runs: [TerminalRun] = [])
}
public struct TerminalFrameHead: Codable, Equatable, Sendable { // history, scroll omitted when 0
    public var kind: TerminalFrameKind; public var cols: Int, rows: Int; public var alt: Bool
    public var cursor: TerminalCursor?; public var palette: TerminalPalette?; public var history: Int, scroll: Int
    public init(kind: TerminalFrameKind, cols: Int, rows: Int, alt: Bool = false, cursor: TerminalCursor? = nil,
                palette: TerminalPalette? = nil, history: Int = 0, scroll: Int = 0)
}
public struct TerminalFramePart: Equatable, Sendable {
    public var revision: Int, part: Int, parts: Int
    public var head: TerminalFrameHead?; public var styles: [TerminalStyle]; public var lines: [TerminalLine]
    public init(revision: Int, part: Int = 0, parts: Int = 1, head: TerminalFrameHead? = nil,
                styles: [TerminalStyle] = [], lines: [TerminalLine] = [])
}
/// One whole frame (all parts merged): what a host's source yields and what the assembler admits.
public struct TerminalGridFrame: Equatable, Sendable {
    public var head: TerminalFrameHead; public var styles: [TerminalStyle]; public var lines: [TerminalLine]
    public init(head: TerminalFrameHead, styles: [TerminalStyle] = [], lines: [TerminalLine] = [])
}
// LinkMessage
case terminalViewFrame(terminalId: String, frame: TerminalFramePart)
// LinkCodec (internal): same encoder settings as `enc`; used by the splitter
static func encodedByteCount<T: Encodable>(_ value: T) throws -> Int
```

Codec rules: a body struct `TerminalFrameBody {terminalId, revision, part, parts, head?, styles?, lines?}` (empty arrays encode as absent, absent decodes to empty). Validation runs on encode and on decode, and a violation is `LinkCodecError.badJSON(callId: nil)`: `revision` ≥ 1; `parts` 1…256; `part` 0…`parts`-1; head `cols` ≥ 1, `rows` ≥ 1, `history` ≥ 0, `scroll` ≥ 0; cursor `x` ≥ 0, `y` ≥ 0; palette `fg`, `bg`, `cursor` are colors and `colors` holds exactly 256 colors; style `id` 1…65 535, `fg`/`bg` 0…255, `fg_rgb`/`bg_rgb` colors, never both `fg` and `fg_rgb` (nor `bg` and `bg_rgb`); run `t` non-empty, `w` nil or 1…2, `x` nil or ≥ 0, `s` nil or ≥ 0. A color is `#` plus 6 hex digits, either case. Keep the `CodingKeys` raw values camelCase (`fgRgb`, `bgRgb`): `LinkCodec`'s snake-case strategies turn them into `fg_rgb` / `bg_rgb`; only `TerminalRun` maps `text`/`style`/`width` to `t`/`s`/`w`.

- [ ] **Step 1: Add the frame vectors to `messages.json`**

`vectors`:

```json
{"name": "terminal_view_frame_delta", "message": {"case": "terminal_view_frame", "terminal_id": "t-1", "revision": 7, "part": 0, "parts": 1, "head": {"kind": "delta", "cols": 46, "rows": 30, "alt": false, "cursor": {"x": 4, "y": 29, "shape": "block", "visible": true, "blink": true}, "scroll": 1}, "styles": [{"id": 1, "fg": 2, "attrs": ["bold"]}], "lines": [{"y": 29, "runs": [{"t": "$ ", "s": 1}, {"t": "ls"}]}]}, "json": {"v": 1, "t": "terminal.view.frame", "terminal_id": "t-1", "revision": 7, "part": 0, "parts": 1, "head": {"kind": "delta", "cols": 46, "rows": 30, "alt": false, "cursor": {"x": 4, "y": 29, "shape": "block", "visible": true, "blink": true}, "scroll": 1}, "styles": [{"id": 1, "fg": 2, "attrs": ["bold"]}], "lines": [{"y": 29, "runs": [{"t": "$ ", "s": 1}, {"t": "ls"}]}]}},
{"name": "terminal_view_frame_later_part", "message": {"case": "terminal_view_frame", "terminal_id": "t-1", "revision": 1, "part": 1, "parts": 2, "styles": [{"id": 2, "fg_rgb": "#336699", "bg": 0}], "lines": [{"y": -1, "runs": [{"x": 2, "t": "中", "w": 2, "s": 2}]}, {"y": 3}]}, "json": {"v": 1, "t": "terminal.view.frame", "terminal_id": "t-1", "revision": 1, "part": 1, "parts": 2, "styles": [{"id": 2, "fg_rgb": "#336699", "bg": 0}], "lines": [{"y": -1, "runs": [{"x": 2, "t": "中", "w": 2, "s": 2}]}, {"y": 3}]}}
```

`decode_only`:

```json
{"name": "terminal_view_frame_empty_arrays", "json": {"v": 1, "t": "terminal.view.frame", "terminal_id": "t-1", "revision": 2, "part": 1, "parts": 2, "styles": [], "lines": [{"y": 0, "runs": []}]}, "message": {"case": "terminal_view_frame", "terminal_id": "t-1", "revision": 2, "part": 1, "parts": 2, "lines": [{"y": 0}]}},
{"name": "terminal_view_frame_unknown_enums", "json": {"v": 1, "t": "terminal.view.frame", "terminal_id": "t-1", "revision": 3, "part": 0, "parts": 1, "head": {"kind": "sparkle", "cols": 2, "rows": 1, "alt": false, "cursor": {"x": 0, "y": 0, "shape": "heart", "visible": true, "blink": false}}, "styles": [{"id": 1, "attrs": ["bold", "glow"]}]}, "message": {"case": "terminal_view_frame", "terminal_id": "t-1", "revision": 3, "part": 0, "parts": 1, "head": {"kind": "sparkle", "cols": 2, "rows": 1, "alt": false, "cursor": {"x": 0, "y": 0, "shape": "heart", "visible": true, "blink": false}}, "styles": [{"id": 1, "attrs": ["bold", "glow"]}]}}
```

`decode_errors` (every entry `"error": "bad_json"`, no `call_id`; base `{"v": 1, "t": "terminal.view.frame", "terminal_id": "t-1"}` plus):

| name | other fields |
| --- | --- |
| `terminal_view_frame_part_not_below_parts` | `"revision": 1, "part": 1, "parts": 1` |
| `terminal_view_frame_revision_zero` | `"revision": 0, "part": 1, "parts": 2` |
| `terminal_view_frame_parts_over_256` | `"revision": 1, "part": 1, "parts": 257` |
| `terminal_view_frame_bad_rgb` | `"revision": 1, "part": 1, "parts": 2, "styles": [{"id": 1, "bg_rgb": "#12345"}]` |
| `terminal_view_frame_palette_index_256` | `"revision": 1, "part": 1, "parts": 2, "styles": [{"id": 1, "fg": 256}]` |
| `terminal_view_frame_fg_and_fg_rgb` | `"revision": 1, "part": 1, "parts": 2, "styles": [{"id": 1, "fg": 1, "fg_rgb": "#ffffff"}]` |
| `terminal_view_frame_style_id_zero` | `"revision": 1, "part": 1, "parts": 2, "styles": [{"id": 0}]` |
| `terminal_view_frame_cell_width_3` | `"revision": 1, "part": 1, "parts": 2, "lines": [{"y": 0, "runs": [{"t": "x", "w": 3}]}]` |
| `terminal_view_frame_empty_run_text` | `"revision": 1, "part": 1, "parts": 2, "lines": [{"y": 0, "runs": [{"t": ""}]}]` |
| `terminal_view_frame_palette_without_256_colors` | `"revision": 1, "part": 0, "parts": 1, "head": {"kind": "snapshot", "cols": 2, "rows": 1, "alt": false, "cursor": {"x": 0, "y": 0, "shape": "block", "visible": true, "blink": false}, "palette": {"fg": "#ffffff", "bg": "#000000", "colors": ["#000000"]}}` |
| `terminal_view_frame_negative_history` | `"revision": 1, "part": 0, "parts": 1, "head": {"kind": "delta", "cols": 2, "rows": 1, "alt": false, "cursor": {"x": 0, "y": 0, "shape": "block", "visible": true, "blink": false}, "history": -1}` |

- [ ] **Step 2: Write the failing tests**

(a) `LinkCodecTests.message(from:)`: `case "terminal_view_frame": return .terminalViewFrame(terminalId: try s("terminal_id"), frame: try terminalFramePart(m))`, with a hand-written `static func terminalFramePart(_ m: [String: Any]) throws -> TerminalFramePart` that maps `revision`, `part`, `parts`, `head` (`kind`, `cols`, `rows`, `alt`, `cursor` {`x`, `y`, `shape`, `visible`, `blink`}, `palette` {`fg`, `bg`, `cursor`, `colors`}, `history` and `scroll` defaulting to 0), `styles` (`id`, `fg`, `fg_rgb`, `bg`, `bg_rgb`, `attrs` defaulting to []) and `lines` (`y`, `runs` defaulting to [] with `x`, `t`, `s`, `w`), each absent array becoming `[]`.

(b) `TerminalFrameCodecTests`:

```swift
func testPaletteRoundTrips() throws {
    let palette = TerminalPalette(fg: "#d0d0d0", bg: "#101010", cursor: "#ff8800",
                                  colors: (0..<256).map { String(format: "#%02x%02x%02x", $0, $0, $0) })
    let head = TerminalFrameHead(kind: .snapshot, cols: 80, rows: 24, cursor: TerminalCursor(x: 0, y: 0), palette: palette, history: 3)
    let message = LinkMessage.terminalViewFrame(terminalId: "t-1", frame: TerminalFramePart(revision: 1, head: head))
    XCTAssertEqual(try LinkCodec.decode(try LinkCodec.encode(message)), message)
}

func testEmptyFieldsAreOmitted() throws {
    let part = TerminalFramePart(revision: 2, part: 1, parts: 2, lines: [TerminalLine(y: 0)])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try LinkCodec.encode(.terminalViewFrame(terminalId: "t-1", frame: part))) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["v", "t", "terminal_id", "revision", "part", "parts", "lines"])
    XCTAssertEqual((object["lines"] as? [[String: Any]])?.first?.keys.sorted(), ["y"])
    let head = TerminalFrameHead(kind: .delta, cols: 2, rows: 1, cursor: TerminalCursor(x: 0, y: 0))
    let headObject = try XCTUnwrap((JSONSerialization.jsonObject(with: try LinkCodec.encode(
        .terminalViewFrame(terminalId: "t-1", frame: TerminalFramePart(revision: 1, head: head)))) as? [String: Any])?["head"] as? [String: Any])
    XCTAssertEqual(Set(headObject.keys), ["kind", "cols", "rows", "alt", "cursor"])
}

func testEncodingChecksTheSameRulesAsDecoding() {
    let bad: [TerminalFramePart] = [
        TerminalFramePart(revision: 0),
        TerminalFramePart(revision: 1, part: 1, parts: 1),
        TerminalFramePart(revision: 1, part: 1, parts: 2, styles: [TerminalStyle(id: 1, fg: 256)]),
        TerminalFramePart(revision: 1, part: 1, parts: 2, styles: [TerminalStyle(id: 1, bgRgb: "336699")]),
        TerminalFramePart(revision: 1, part: 1, parts: 2, lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "x", width: 3)])]),
        TerminalFramePart(revision: 1, part: 1, parts: 2, lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "")])]),
    ]
    for part in bad {
        XCTAssertThrowsError(try LinkCodec.encode(.terminalViewFrame(terminalId: "t-1", frame: part)), "\(part)") {
            XCTAssertEqual($0 as? LinkCodecError, .badJSON(callId: nil))
        }
    }
}
```

(c) `TerminalSessionTests.testFramesFromAClientAreBadRequest`: on `rawSession(makeHost())` send `.terminalViewFrame(terminalId: "t-1", frame: TerminalFramePart(revision: 1, part: 1, parts: 2))` → receive `.error("bad_request", _, nil)`.

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter 'LinkCodecTests|TerminalFrameCodecTests|TerminalSessionTests'`
Expected: FAIL — `error: cannot find 'TerminalFramePart' in scope`.

- [ ] **Step 4: Implement** the types, the case, the codec body and validation, `encodedByteCount`, and add `.terminalViewFrame` to the call-less `bad_request` arm of `LinkHost` and to the ignore arm of `LinkClient`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add shellx-link/Sources/ShellXLinkCore shellx-link/Sources/ShellXLinkSession/LinkHost.swift \
  shellx-link/Sources/ShellXLinkSession/LinkClient.swift shellx-link/spec/vectors/messages.json \
  shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift shellx-link/Tests/ShellXLinkCoreTests/TerminalFrameCodecTests.swift \
  shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTests.swift
git commit -m "feat(shellx-link): terminal grid frames and their codec"
```

---

### Task 4: Frame assembler and screen model

**Files:**
- Create: `shellx-link/Sources/ShellXLinkCore/Terminal/TerminalFrameAssembler.swift`
- Create: `shellx-link/Sources/ShellXLinkCore/Terminal/TerminalScreen.swift`
- Modify: `shellx-link/spec/vectors/terminal.json` (`screens`)
- Test: `shellx-link/Tests/ShellXLinkCoreTests/TerminalVectorTests.swift` (add `testScreens`), create `shellx-link/Tests/ShellXLinkCoreTests/TerminalScreenTests.swift`

**Interfaces:**
- Consumes: Task 3 types.
- Produces:

```swift
public struct TerminalAssemblyResult: Equatable, Sendable {
    public var frame: TerminalGridFrame?   // a complete frame to apply now (11.7), or nil
    public var resync: Bool                // send terminal.view.resync now (at most once per gap)
    public init(frame: TerminalGridFrame? = nil, resync: Bool = false)
}
public struct TerminalFrameAssembler: Equatable, Sendable {
    public private(set) var revision: Int          // the current revision, 0 before the first snapshot
    public private(set) var awaitingSnapshot: Bool // true from a gap until the next snapshot
    public init()
    public mutating func receive(_ part: TerminalFramePart) -> TerminalAssemblyResult
}
public enum TerminalCell: Equatable, Sendable {
    case blank
    case glyph(text: String, width: Int, style: TerminalCellStyle)
    case continuation                      // the second column of a wide cell
}
public struct TerminalStyledRun: Equatable, Sendable {
    public var x: Int; public var text: String; public var width: Int?; public var style: TerminalCellStyle
    public init(x: Int, text: String, width: Int? = nil, style: TerminalCellStyle = .default)
}
public struct TerminalRow: Equatable, Sendable {
    public var runs: [TerminalStyledRun]
    public init(runs: [TerminalStyledRun] = [])
    public func cells(cols: Int) -> [TerminalCell]   // exactly `cols` entries, later runs overwrite earlier ones
    public func text(cols: Int) -> String            // the row text rule of PROTOCOL.md §8 (terminal.json)
}
public struct TerminalScreen: Equatable, Sendable {
    public static let defaultMaxHistoryRows = 10_000
    public let maxHistoryRows: Int
    public private(set) var cols: Int, rows: Int, alt: Bool     // 0, 0, false before the first snapshot
    public private(set) var cursor: TerminalCursor?             // clamped into the grid
    public private(set) var palette: TerminalPalette?
    public private(set) var screenRows: [TerminalRow]           // `rows` rows
    public private(set) var historyRows: [TerminalRow]          // oldest first, at most maxHistoryRows
    public init(maxHistoryRows: Int = TerminalScreen.defaultMaxHistoryRows)
    public mutating func apply(_ frame: TerminalGridFrame)      // 11.6; resolves x, clips, resolves style ids
    public func cell(x: Int, y: Int) -> TerminalCell            // y >= 0 screen row; y < 0 history from the newest (-1)
    public func screenText() -> [String]
    public func historyText() -> [String]
}
```

The assembler implements 11.7 exactly (kind-specific checks, sizes above `ShellXLink.terminalMaxGridSize`, a gap before the first snapshot, one resync per gap). `TerminalScreen` implements 11.6 and the receiver rules of 11.5, and keeps an internal flag "history continuous since the last snapshot" that history frames need.

- [ ] **Step 1: Fill `screens` in `terminal.json`.** Every frame is a whole message `{"v": 1, "t": "terminal.view.frame", "terminal_id": "t-1", "revision": …, "part": …, "parts": …, …}` (`part` 0 and `parts` 1 unless the table says `p/n`). `SNAP C×R` abbreviates the head `{"kind": "snapshot", "cols": C, "rows": R, "alt": false, "cursor": {"x": 0, "y": 0, "shape": "block", "visible": true, "blink": false}, "palette": "@palette"}` and `DELTA C×R` the same with `"kind": "delta"` and no `palette`; "cursor xA yB" changes only the cursor's `x` and `y`; a line written `y0 "hello"` is `{"y": 0, "runs": [{"t": "hello"}]}`. Write everything out in full in the file. In the file every `expect` carries `revision`, `resyncs`, `cols`, `rows`, `alt`, `screen` and `history`; the table leaves out `resyncs` when 0 and `cols`, `rows`, `alt` when they are those of the last snapshot in the frames.

| name | frames | expect |
| --- | --- | --- |
| `snapshot_basic` | r1 0/1 SNAP 10×3, cursor `{"x":2,"y":2,"shape":"bar","visible":true,"blink":false}`, `"history": 2`; lines y-2 "old 1", y-1 "old 2", y0 "hello", y2 "$ " | revision 1, resyncs 0, cols 10, rows 3, alt false, cursor as sent, screen `["hello","","$"]`, history `["old 1","old 2"]` |
| `two_parts_then_delta` | r1 0/2 SNAP 10×3, `"styles": [{"id":1,"fg":1,"attrs":["bold"]}]`, line y0 `[{"t":"top","s":1}]`; r1 1/2 (no head) lines y1 "middle", y2 "bottom"; r2 0/1 DELTA 10×3 cursor x3 y1, lines y1 "MID", `{"y":2}` | revision 2, resyncs 0, screen `["top","MID",""]`, history `[]`, cursor x3 y1 block visible, cells `(0,0)` glyph "t" w1 style `{"fg":1,"attrs":["bold"]}`, `(0,1)` glyph "M" w1, `(3,1)` blank |
| `delta_scroll` | r1 SNAP 10×3 cursor x1 y2 `"history": 1`, lines y-1 "h0", y0 "a", y1 "b", y2 "c"; r2 DELTA 10×3 cursor x1 y2 `"scroll": 1`, line y2 "d" | revision 2, screen `["b","c","d"]`, history `["h0","a"]` |
| `delta_burst` | r1 SNAP 10×2 cursor x0 y1, lines y0 "r1", y1 "r2"; r2 DELTA 10×2 cursor x0 y1 `"scroll": 5, "history": 2`, lines y-2 "r4", y-1 "r5", y0 "r6", y1 "r7" | revision 2, screen `["r6","r7"]`, history `["r1","r2","r4","r5"]` |
| `wide_and_combining` | r1 SNAP 8×1, line y0 `[{"t":"a"},{"t":"中","w":2},{"t":"e\u0301","w":1},{"t":"🇻🇳","w":2},{"t":"z"}]` (🇻🇳 = U+1F1FB U+1F1F3; `e\u0301` is "e" followed by U+0301 COMBINING ACUTE ACCENT, two scalars in one cell: write it in the file as the JSON escape, never as a precomposed é) | revision 1, screen `["a中e\u0301🇻🇳z"]`, cells `(1,0)` glyph "中" w2, `(2,0)` continuation, `(3,0)` glyph "e\u0301" w1, `(4,0)` glyph "🇻🇳" w2, `(5,0)` continuation, `(6,0)` glyph "z" w1, `(7,0)` blank |
| `runs_without_x_and_split_rows` | r1 0/2 SNAP 12×1, line y0 `[{"x":2,"t":"ab"},{"t":"中","w":2},{"t":"cd"}]`; r1 1/2 line y0 `[{"x":10,"t":"e"}]` | revision 1, screen `["  ab中cd  e"]`, cells `(4,0)` glyph "中" w2, `(8,0)` blank, `(10,0)` glyph "e" w1 |
| `gap_asks_one_resync` | r1 SNAP 10×1 line y0 "one"; r3 DELTA 10×1 y0 "three"; r4 DELTA y0 "four"; r5 SNAP y0 "five"; r6 DELTA y0 "six" | revision 6, resyncs 1, screen `["six"]` |
| `missing_part_asks_resync` | r1 0/2 SNAP 10×1 y0 "a"; r2 0/1 DELTA 10×1 y0 "b"; r3 0/1 SNAP 10×1 y0 "fresh" | revision 3, resyncs 1, screen `["fresh"]` |
| `stale_frames_are_ignored` | r1 SNAP 10×1 y0 "a"; r2 DELTA y0 "b"; r2 DELTA y0 "c"; r2 SNAP y0 "d" | revision 2, resyncs 0, screen `["b"]` |
| `delta_of_another_size_asks_resync` | r1 SNAP 10×2 y0 "x"; r2 DELTA cols 12 rows 2 y0 "y" | revision 1, resyncs 1, cols 10, rows 2, screen `["x",""]` |
| `history_frames_grow_upward` | r1 SNAP 10×1 `"history": 2`, lines y-2 "h3", y-1 "h4", y0 "screen"; r2 head `{"kind":"history","cols":10,"rows":1,"alt":false,"history":2}` lines y-2 "h1", y-1 "h2"; r3 same head with `"history": 1`, line y-1 "h0" | revision 3, screen `["screen"]`, history `["h0","h1","h2","h3","h4"]` |
| `alternate_screen` | r1 SNAP 10×1 `"history": 1`, lines y-1 "h", y0 "$"; r2 SNAP 10×1 `"alt": true` y0 "vim"; r3 DELTA 10×1 `"alt": true` y0 "vim2" | revision 3, alt true, screen `["vim2"]`, history `[]` |
| `lenient_clipping` | r1 SNAP 5×2 cursor x9 y9, lines y0 "abcdefg", `{"y":5,"runs":[{"t":"ignored"}]}`, `{"y":1,"runs":[{"x":4,"t":"中","w":2}]}` | revision 1, screen `["abcde",""]`, cursor x4 y1 block visible blink false |
| `styles_resolve_per_frame` | r1 SNAP 10×1, `"styles": [{"id":7,"fg":2,"bg_rgb":"#336699","attrs":["italic","underline"]}]`, line y0 `[{"t":"ab","s":7},{"t":"c","s":99}]` | revision 1, screen `["abc"]`, cells `(0,0)` and `(1,0)` glyph w1 style `{"fg":2,"bg_rgb":"#336699","attrs":["italic","underline"]}`, `(2,0)` glyph "c" w1 default style |
| `trimmed_history_stops_the_fill` (`"max_history_rows": 3`) | r1 SNAP 10×2 `"history": 2`, lines y-2 "h3", y-1 "h4", y0 "s0", y1 "s1"; r2 DELTA 10×2 `"scroll": 2` lines y0 "n0", y1 "n1"; r3 history head (10×2, `"history": 2`) lines y-2 "h1", y-1 "h2" | revision 3, screen `["n0","n1"]`, history `["h4","s0","s1"]` |
| `fill_beyond_the_limit_keeps_the_newest` (`"max_history_rows": 3`) | r1 SNAP 10×1 `"history": 1`, lines y-1 "h2", y0 "x"; r2 history head (10×1, `"history": 3`) lines y-3 "a", y-2 "b", y-1 "c"; r3 history head (`"history": 1`) line y-1 "z" | revision 3, history `["b","c","h2"]` |
| `delta_before_the_first_snapshot` | r1 DELTA 10×1 y0 "x"; r2 SNAP 10×1 y0 "s" | revision 2, resyncs 1, screen `["s"]` |

- [ ] **Step 2: Write the failing tests**

(a) `TerminalVectorTests.testScreens`: for every `screens` entry, replace a head `palette` equal to `"@palette"` by the top-level `palette`, decode each frame with `LinkCodec.decode`, require `.terminalViewFrame(terminalId: "t-1", frame:)`, feed `TerminalFrameAssembler.receive`, apply every returned `frame` to `TerminalScreen(maxHistoryRows: entry["max_history_rows"] ?? TerminalScreen.defaultMaxHistoryRows)` and count `resync`. Then assert `assembler.revision == revision`, the count `== resyncs`, `cols`, `rows`, `alt`, `cursor` when present, `screenText() == screen`, `historyText() == history`, and for each `cells` entry `screen.cell(x:y:)` equals `.blank`, `.continuation` or `.glyph(text: t, width: w, style: TerminalCellStyle(fg:fgRgb:bg:bgRgb:attrs:))` built from `style` (absent → `.default`). Also `XCTAssertEqual(screens.count, 17)`.

(b) `TerminalScreenTests`:

```swift
func testRowTextSkipsTheSecondColumnOfAWideCell() {
    let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "a"), TerminalStyledRun(x: 1, text: "中", width: 2)])
    XCTAssertEqual(row.text(cols: 5), "a中")
    XCTAssertEqual(row.cells(cols: 5), [.glyph(text: "a", width: 1, style: .default),
                                       .glyph(text: "中", width: 2, style: .default), .continuation, .blank, .blank])
}
func testLaterRunOverwritesCellByCell() {
    let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "abc"), TerminalStyledRun(x: 1, text: "Z")])
    XCTAssertEqual(row.text(cols: 3), "aZc")
}
func testScreenStartsEmpty() {
    let screen = TerminalScreen()
    XCTAssertEqual(screen.cols, 0); XCTAssertNil(screen.cursor)
    XCTAssertEqual(screen.screenText(), []); XCTAssertEqual(screen.historyText(), [])
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter 'TerminalVectorTests|TerminalScreenTests'`
Expected: FAIL — `error: cannot find 'TerminalFrameAssembler' in scope`.

- [ ] **Step 4: Implement** both files.

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --package-path shellx-link --filter 'TerminalVectorTests|TerminalScreenTests'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shellx-link/Sources/ShellXLinkCore/Terminal shellx-link/spec/vectors/terminal.json \
  shellx-link/Tests/ShellXLinkCoreTests/TerminalVectorTests.swift shellx-link/Tests/ShellXLinkCoreTests/TerminalScreenTests.swift
git commit -m "feat(shellx-link): terminal frame assembler and screen model"
```

---

### Task 5: Splitting a frame into parts

**Files:**
- Create: `shellx-link/Sources/ShellXLinkCore/Terminal/TerminalFrameSplitter.swift`
- Test: create `shellx-link/Tests/ShellXLinkCoreTests/TerminalFrameSplitterTests.swift` (`@testable import ShellXLinkCore`)

**Interfaces:**
- Consumes: `LinkCodec.encodedByteCount(_:)`, `LinkCodec.encode`, Task 3 types, Task 4 assembler and screen (tests).
- Produces:

```swift
public enum TerminalFrameSplitter {
    /// The parts of `frame` at `revision`, in order (PROTOCOL.md 11.4). Part 0 carries `frame.head`; the styles come
    /// first, then the lines, in order. Each part, encoded as `.terminalViewFrame(terminalId:frame:)`, fits
    /// `LinkCodec.maxFrameBytes`. A line too large for one part becomes several lines with the same `y`, each later one
    /// starting with a run whose `x` is explicit. Throws `LinkCodecError.frameTooLarge` past
    /// `ShellXLink.terminalMaxFrameParts` parts, or when one run alone does not fit an empty part.
    public static func parts(of frame: TerminalGridFrame, revision: Int, terminalId: String) throws -> [TerminalFramePart]
    // internal, for tests: the same with other bounds
    static func parts(of frame: TerminalGridFrame, revision: Int, terminalId: String, maxBytes: Int, maxParts: Int) throws -> [TerminalFramePart]
}
```

Approach: size each style and each line once with `encodedByteCount`, pack greedily (styles, then lines) into the room of a part (`maxBytes` minus the encoded size of that part with no styles and lines, minus 64 bytes for separators and digit growth), split an oversized line into runs that fit (resolving the column of its first run), set `parts` on every part at the end, then encode each finished part once and, if it is still over `maxBytes`, move its last item to the next part.

- [ ] **Step 1: Write the failing tests**

```swift
func testSmallFrameIsOnePart() throws {
    let frame = TerminalGridFrame(head: TerminalFrameHead(kind: .delta, cols: 10, rows: 2, cursor: TerminalCursor(x: 0, y: 0)),
                                  lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "hi")])])
    XCTAssertEqual(try TerminalFrameSplitter.parts(of: frame, revision: 3, terminalId: "t-1"),
                   [TerminalFramePart(revision: 3, part: 0, parts: 1, head: frame.head, styles: [], lines: frame.lines)])
}

func testBigSnapshotSplitsWithinTheFrameLimit() throws {
    // 300 x 120 cells, each its own style (36 000 styles), plus 240 history rows of text.
    let frame = Self.bigSnapshot()
    let parts = try TerminalFrameSplitter.parts(of: frame, revision: 1, terminalId: "t-1")
    XCTAssertGreaterThan(parts.count, 1)
    for (index, part) in parts.enumerated() {
        XCTAssertEqual(part.part, index); XCTAssertEqual(part.parts, parts.count); XCTAssertEqual(part.revision, 1)
        XCTAssertEqual(part.head != nil, index == 0)
        XCTAssertLessThanOrEqual(try LinkCodec.encode(.terminalViewFrame(terminalId: "t-1", frame: part)).count, LinkCodec.maxFrameBytes)
    }
    var assembler = TerminalFrameAssembler()
    let results = parts.map { assembler.receive($0) }
    XCTAssertEqual(results.last?.frame, frame)
    XCTAssertFalse(results.contains { $0.resync })
}

func testOversizedLineSplitsIntoLinesWithTheSameY() throws {
    let runs = (0..<1000).map { _ in TerminalRun(text: "e" + String(repeating: "\u{0301}", count: 15), width: 1) } // no x
    let frame = TerminalGridFrame(head: TerminalFrameHead(kind: .snapshot, cols: 1000, rows: 1, cursor: TerminalCursor(x: 0, y: 0),
                                                          palette: Self.palette), lines: [TerminalLine(y: 0, runs: runs)])
    let parts = try TerminalFrameSplitter.parts(of: frame, revision: 1, terminalId: "t-1", maxBytes: 4096, maxParts: 256)
    let lines = parts.flatMap(\.lines)
    XCTAssertGreaterThan(lines.count, 1)
    XCTAssertTrue(lines.allSatisfy { $0.y == 0 })
    XCTAssertEqual(lines.flatMap(\.runs).count, 1000)
    XCTAssertTrue(lines.dropFirst().allSatisfy { $0.runs.first?.x != nil })
    var assembler = TerminalFrameAssembler()
    let joined = try XCTUnwrap(parts.map { assembler.receive($0) }.last?.frame)
    var split = TerminalScreen(); split.apply(joined)
    var whole = TerminalScreen(); whole.apply(frame)
    XCTAssertEqual(split.screenRows[0].cells(cols: 1000), whole.screenRows[0].cells(cols: 1000))
}

func testTooManyPartsThrows() {
    let lines = (0..<100).map { TerminalLine(y: $0, runs: [TerminalRun(text: String(repeating: "x", count: 500))]) }
    let frame = TerminalGridFrame(head: TerminalFrameHead(kind: .delta, cols: 500, rows: 100, cursor: TerminalCursor(x: 0, y: 0)), lines: lines)
    XCTAssertThrowsError(try TerminalFrameSplitter.parts(of: frame, revision: 1, terminalId: "t-1", maxBytes: 1024, maxParts: 2)) {
        XCTAssertEqual($0 as? LinkCodecError, .frameTooLarge)
    }
}

func testStylesComeBeforeLines() throws {
    // 300 styles and 300 lines with a small limit: once a part has lines, no later part has styles
    let parts = try TerminalFrameSplitter.parts(of: Self.manyStylesAndLines(), revision: 1, terminalId: "t-1", maxBytes: 2048, maxParts: 256)
    let firstWithLines = try XCTUnwrap(parts.firstIndex { !$0.lines.isEmpty })
    XCTAssertTrue(parts[(firstWithLines + 1)...].allSatisfy { $0.styles.isEmpty })
}
```

(`bigSnapshot()`, `manyStylesAndLines()` and `palette` are private helpers of the test class; `palette` has 256 valid colors.)

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter TerminalFrameSplitterTests`
Expected: FAIL — `error: cannot find 'TerminalFrameSplitter' in scope`.

- [ ] **Step 3: Implement** `TerminalFrameSplitter`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path shellx-link --filter TerminalFrameSplitterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shellx-link/Sources/ShellXLinkCore/Terminal/TerminalFrameSplitter.swift shellx-link/Tests/ShellXLinkCoreTests/TerminalFrameSplitterTests.swift
git commit -m "feat(shellx-link): split terminal frames into parts"
```

---

### Task 6: `terminal.create` end to end

**Files:**
- Create: `shellx-link/Sources/ShellXLinkSession/TerminalCreator.swift`
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift` (both inits 42-74, features 160-165, the `terminalCreate` arm), `shellx-link/Sources/ShellXLinkSession/LinkClient.swift` (`createTerminal`, `hostFeatures` doc)
- Create: `shellx-link/Tests/ShellXLinkSessionTests/FakeTerminalViewSource.swift` (`FakeTerminalCreator` for now)
- Test: `shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTestCase.swift` (`makeHost(terminalCreator:)`), `TerminalSessionTests.swift`

**Interfaces:**
- Consumes: Task 2's `terminalCreate` / `terminalCreateResult`.
- Produces:

```swift
/// Opens a terminal tab in a workspace the host lists (PROTOCOL.md 11.9). A host that has one offers `terminal_create`.
///
/// The implementation adds the tab in the pane the Mac has selected in that workspace, running the user's default
/// shell, without changing the Mac's selection (workspace, pane, the tab each pane shows), focus or window order. It
/// answers `.notFound` for a workspace it does not list, `.refused` when remote control is blocked or its rules forbid
/// it, `.failed` when it could not act, and gives `terminalId` only with `.ok`. It never logs a workspace's title.
/// Calls arrive concurrently and may take a while; the host serves other calls meanwhile.
public protocol TerminalCreator: Sendable {
    func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?)
}
// LinkHost.init (public and internal): after `terminalControl:`, `terminalCreator: (any TerminalCreator)? = nil`
// LinkClient
public func createTerminal(workspaceId: String) async throws -> (outcome: WorkspaceControlOutcome, terminalId: String?)
// Tests
final class FakeTerminalCreator: TerminalCreator, @unchecked Sendable {
    var calls: [String] { get }
    func setCreate(_ outcome: WorkspaceControlOutcome, terminalId: String?)   // default (.ok, "t-new")
    func hold(until gate: Gate)                                             // later calls wait after they are logged
}
```

Host behaviour: with a creator, `welcome.features` gains `terminal_create` after `terminal_close` (and after `terminal_view` once Task 7 adds it); the call runs in a child task like `workspace.create`, and `terminal_id` goes out only when the outcome is `.ok`.

- [ ] **Step 1: Write the failing tests** in `TerminalSessionTests`:

```swift
func testWelcomeListsTerminalCreateOnlyWithACreator() async throws {
    XCTAssertEqual(try await welcomeFeatures(makeHost(terminalCreator: FakeTerminalCreator())), ["terminal_create"])
    XCTAssertEqual(try await welcomeFeatures(makeHost()), [])
}

func testCreateReachesTheCreator() async throws {
    let creator = FakeTerminalCreator()
    creator.setCreate(.ok, terminalId: "t-9")
    let client = try await connect(makeHost(terminalCreator: creator))
    let created = try await within { try await client.createTerminal(workspaceId: "ws-1") }
    XCTAssertEqual(created.outcome, .ok); XCTAssertEqual(created.terminalId, "t-9")
    for outcome in [WorkspaceControlOutcome.notFound, .refused, .failed, .other("busy")] {
        creator.setCreate(outcome, terminalId: "t-ignored")
        let answer = try await within { try await client.createTerminal(workspaceId: "ws-1") }
        XCTAssertEqual(answer.outcome, outcome); XCTAssertNil(answer.terminalId, "terminal_id only with ok")
    }
    XCTAssertEqual(creator.calls, Array(repeating: "ws-1", count: 5))
}

func testSlowCreateDoesNotBlockTheSession() async throws {
    let creator = FakeTerminalCreator(); let gate = Gate(); creator.hold(until: gate)
    let client = try await connect(makeHost(terminalCreator: creator))
    let pending = Task { try await client.createTerminal(workspaceId: "ws-1") }
    _ = try await within { try await client.snapshot() }     // answered while the create waits
    gate.open()
    XCTAssertEqual(try await pending.value.outcome, .ok)
}
```

(`welcomeFeatures(_:)` is added to `TerminalSessionTestCase` like `WorkspaceSessionTests.swift:603-614`.)

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter TerminalSessionTests`
Expected: FAIL — `error: cannot find type 'TerminalCreator' in scope` (or `extra argument 'terminalCreator' in call`).

- [ ] **Step 3: Implement** the protocol, the `LinkHost` parameter, feature and arm, `LinkClient.createTerminal` (through `call`, unpacking `.terminalCreateResult`, otherwise `.unexpectedAnswer`), and the fake.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add shellx-link/Sources/ShellXLinkSession/TerminalCreator.swift shellx-link/Sources/ShellXLinkSession/LinkHost.swift \
  shellx-link/Sources/ShellXLinkSession/LinkClient.swift shellx-link/Tests/ShellXLinkSessionTests
git commit -m "feat(shellx-link): terminal.create for phones"
```

---

### Task 7: Opening, streaming and closing a view

**Files:**
- Create: `shellx-link/Sources/ShellXLinkSession/TerminalViewSource.swift`
- Create: `shellx-link/Sources/ShellXLinkSession/TerminalViewSlot.swift` (internal actor)
- Create: `shellx-link/Sources/ShellXLinkSession/TerminalViewPump.swift` (internal actor)
- Modify: `shellx-link/Sources/ShellXLinkSession/LinkHost.swift` (inits, features, `terminalViewOpen` / `terminalViewClose` arms, ending the view on every way out of the established loop), `shellx-link/Sources/ShellXLinkSession/LinkClient.swift` (`terminalPushes`, `post`, open/close, `.opened` ordering)
- Modify: `shellx-link/Tests/ShellXLinkSessionTests/FakeTerminalViewSource.swift`, `TerminalSessionTestCase.swift`
- Test: `shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTests.swift`

**Interfaces:**
- Consumes: Task 3 types, Task 5 `TerminalFrameSplitter`, Task 4 assembler and screen (tests).
- Produces (public, copy the doc comments: they are the contract 2B implements):

```swift
/// The host's terminals as phones view them (PROTOCOL.md section 11). A host that has one offers `terminal_view`.
public protocol TerminalViewSource: Sendable {
    /// Starts a view of `terminalId` for a phone that can show `cols` x `rows` (already clamped into
    /// `ShellXLink.terminalColumns` and `ShellXLink.terminalRows`). `.notOpened(.notFound)` for a terminal that is not in
    /// a local workspace the host lists, `.notOpened(.refused)` when remote control is blocked, `.notOpened(.failed)`
    /// when it could not start one. Never `.busy` (the host's own rule) nor `.ok`.
    func openView(terminalId: String, cols: Int, rows: Int) async -> TerminalViewOpenResult
}

/// One open view: what a phone's `terminal.view.open` started. The host calls each method from one task at a time.
public protocol TerminalView: Sendable {
    /// The next frame of the view, or its end. The first call returns a snapshot carrying up to
    /// `ShellXLink.terminalHistoryRowBudget` history rows on the main screen. Every later call returns a delta computed
    /// against the frame the call before returned, or a snapshot (new size, other screen, new palette, or after
    /// `requestSnapshot()`); it suspends until the terminal changed, and paces itself. It never returns `.history`
    /// frames (the host makes those). The host calls it again only when no frame it made is waiting, so a slow phone
    /// makes the view merge changes. It returns promptly when its task is cancelled or after `close()`.
    func nextFrame() async -> TerminalViewEvent
    /// Makes the frame of the next `nextFrame()` call that starts after this returns a snapshot.
    func requestSnapshot() async
    /// Applies the phone's units in order; the host has checked them (`TerminalInputCheck`). A unit, key or modifier the
    /// view does not know is skipped. Typing is the phone's activity for the terminal's size. When remote control
    /// becomes blocked (device management), the view ends: `nextFrame()` returns `.ended(.refused)` and later input is
    /// not applied. A `scroll` unit acts only while the alternate screen is active.
    func input(_ units: [TerminalInputUnit]) async
    /// The phone's size changed (already clamped).
    func resize(cols: Int, rows: Int) async
    /// The phone stopped viewing: the terminal goes back to the Mac's size. Called once.
    func close() async
}

public enum TerminalViewOpenResult: Sendable {
    case opened(any TerminalView)
    case notOpened(TerminalViewOpenOutcome)
}

public enum TerminalViewEvent: Equatable, Sendable {
    case frame(TerminalGridFrame)
    case ended(TerminalViewEndReason)
}

// LinkHost.init: after `terminalControl:`, `terminalViews: (any TerminalViewSource)? = nil` (then `terminalCreator:`)

/// A terminal push from the host, in arrival order (`LinkClient.terminalPushes`).
public enum TerminalViewPush: Equatable, Sendable {
    /// This client's `terminal.view.open` for `terminalId` was answered `ok`: start a fresh `TerminalFrameAssembler`;
    /// every frame of that terminal after this belongs to the new view.
    case opened(terminalId: String)
    case frame(terminalId: String, part: TerminalFramePart)
    case ended(terminalId: String, reason: TerminalViewEndReason)
}

// LinkClient
/// Every `terminal.view.frame` and `terminal.view.ended`, and `.opened` right before the first frame of a view this client
/// opened, in arrival order. Single consumer. It finishes when the session ends.
public nonisolated let terminalPushes: AsyncStream<TerminalViewPush>
/// Opens a view (`terminal.view.open`); on `.ok` it yields `.opened(terminalId:)` on `terminalPushes` before it returns.
/// Throws `.remote(code: "unsupported")` without `terminal_view`, `.remote(code: "bad_request")` for `cols` or `rows` below 1.
public func openTerminalView(terminalId: String, cols: Int, rows: Int) async throws -> TerminalViewOpenOutcome
/// Sends `terminal.view.close` (no answer). Throws `.sessionClosed` when the session ended.
public func closeTerminalView(terminalId: String) async throws
```

Internal: `actor TerminalViewSlot` (one per session; created in `converse` when `terminalViews` is set) with `open(callId:terminalId:cols:rows:)`, `close(terminalId:)`, `endSession()`, and later (Task 8) `input`, `resize`, `resync`; `actor TerminalViewPump` (one per view) with `start()`, `stop()`. `LinkClient.post(_ message: LinkMessage) async throws` sends a call-less message (`checkOpen()`, then the channel; a channel failure becomes `.sessionClosed`).

Slot rules (each pinned by a test below):
1. `open` with no view: await `openView`; `.notOpened(o)` → answer `o` (`.ok` → `.failed`); `.opened(view)` → answer `.ok`, then start the pump, so the answer precedes the first frame.
2. `open` of the terminal it views: stop that view (rule 5), then rule 1.
3. `open` of another terminal while one is open: answer `.busy`; `openView` is not called.
4. `close` of the viewed terminal: stop the view; of any other: nothing.
5. Stopping a view: (Task 8: apply the input it holds), cancel the pump and await it, then `view.close()` once.
6. The pump ends on `.ended(reason)`: it sends `terminal.view.ended(terminalId, reason)`, the slot forgets the view if it is still the current one, and `view.close()` runs once.
7. `endSession()`: stop the view. `LinkHost` calls it on every way out of the established receive loop.

`LinkHost` arms: `.terminalViewOpen` without source → `unsupported` (as Task 2); `cols < 1 || rows < 1` → `bad_request` with the `call_id` (`"cols and rows must be at least 1"`); else `await slot.open(…)` with both values clamped into `ShellXLink.terminalColumns` / `ShellXLink.terminalRows`, inline so later messages see the result. `.terminalViewClose` → `await slot?.close(terminalId:)`.

Pump (this task): a puller task loops `wait until the 1-slot mailbox is empty → await view.nextFrame() → put it in the mailbox → stop after .ended`; a sender task loops `take from the mailbox → .ended: send terminal.view.ended and finish; .frame: process`. `process` drops a frame that is not a snapshot while it waits for the first snapshot (asking `requestSnapshot()` once), raises the revision by 1, splits the frame with `TerminalFrameSplitter.parts(of:revision:terminalId:)` and sends every part in order with `channel.send(frame:)` after encoding it. A split that throws ends the view with `.failed` (send `terminal.view.ended` `failed`). `stop()` cancels both tasks and awaits them; a cancelled pump sends nothing more (it checks for cancellation before each send, so the `.ended(.failed)` a cancelled `nextFrame()` returns is never sent). Waiting on the mailbox honours cancellation.

Test fakes (in `FakeTerminalViewSource.swift`):

```swift
final class FakeTerminalViewSource: TerminalViewSource, @unchecked Sendable {
    struct Open: Equatable { let terminalId: String; let cols: Int; let rows: Int }
    var opens: [Open] { get }
    var views: [FakeTerminalView] { get }                                  // in open order
    func refuse(_ terminalId: String, with outcome: TerminalViewOpenOutcome)
    /// Runs on each new view of `terminalId` (with its 1-based count for that id) before the host gets it.
    func onOpen(_ terminalId: String, _ prepare: @escaping @Sendable (FakeTerminalView, Int) -> Void)
}
final class FakeTerminalView: TerminalView, @unchecked Sendable {
    enum Call: Equatable { case input([TerminalInputUnit]); case resize(cols: Int, rows: Int); case close }
    var calls: [Call] { get }
    var snapshotRequests: Int { get }
    var nextFrameCalls: Int { get }
    var maxConcurrentNextFrameCalls: Int { get }
    var inputsStarted: Int { get }                                         // input calls entered, held or not
    func emit(_ events: TerminalViewEvent...)                              // queued for nextFrame()
    /// With nothing queued, nextFrame() returns produce(n) (n = 1, 2, … per produced event); nil means wait.
    func produceOnDemand(_ produce: @escaping @Sendable (Int) -> TerminalViewEvent?)
    /// requestSnapshot() also queues these events; with a `gate`, nextFrame() hands them out only once it is open.
    func answerSnapshotRequests(after gate: Gate? = nil, with events: @escaping @Sendable () -> [TerminalViewEvent])
    /// Every later input/resize waits for `gate` before it is logged in `calls`.
    func holdInput(until gate: Gate)
}
let testPalette: TerminalPalette   // fg #d0d0d0, bg #101010, colors[i] = gray i
/// Screen row i is text[i] (narrow), history rows oldest first, cursor (0,0); `palette` testPalette.
func snapshotFrame(cols: Int, rows: Int, text: [String], history: [String] = [], alt: Bool = false) -> TerminalGridFrame
/// Replaces the given rows; `history` rows ride at y -history.count ... -1.
func deltaFrame(cols: Int, rows: Int, replacing: [Int: String], scroll: Int = 0, history: [String] = [], alt: Bool = false) -> TerminalGridFrame
```

`TerminalSessionTestCase` gains `makeHost(terminalViews:terminalCreator:)` and two helpers: `func assembled(_ pushes: [TerminalViewPush], terminalId: String = "t-1") -> (screen: TerminalScreen, kinds: [TerminalFrameKind], revisions: [Int], resyncs: Int)` (feeds the frames after the last `.opened(terminalId)` to a fresh assembler and screen) and `func waitFor(_ pushes: Collector<TerminalViewPush>, within: Duration = .seconds(5), _ condition: @escaping @Sendable ([TerminalViewPush]) -> Bool) async -> Bool`.

- [ ] **Step 1: Write the failing tests** in `TerminalSessionTests`:

```swift
func testWelcomeListsTerminalViewOnlyWithASource() async throws {
    XCTAssertEqual(try await welcomeFeatures(makeHost(terminalViews: FakeTerminalViewSource())), ["terminal_view"])
    XCTAssertEqual(try await welcomeFeatures(makeHost(terminalViews: FakeTerminalViewSource(),
                                                      terminalCreator: FakeTerminalCreator())), ["terminal_view", "terminal_create"])
}

func testOpenAnswersBeforeTheFirstFrame() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in view.emit(.frame(snapshotFrame(cols: 46, rows: 2, text: ["$"]))) }
    let raw = try await rawSession(makeHost(terminalViews: views))
    try await raw.send(.terminalViewOpen(callId: "c1", terminalId: "t-1", cols: 46, rows: 30))
    XCTAssertEqual(try await within { try await raw.receive() }, .terminalViewOpenResult(callId: "c1", outcome: .ok))
    guard case let .terminalViewFrame("t-1", part) = try await within({ try await raw.receive() }) else { return XCTFail("no frame") }
    XCTAssertEqual(part.revision, 1); XCTAssertEqual(part.head?.kind, .snapshot)
}

func testOpenClampsTheSizeAndRefusesNonPositiveOnes() async throws {
    let views = FakeTerminalViewSource()
    let client = try await connect(makeHost(terminalViews: views))
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 10, rows: 2) }
    try await client.closeTerminalView(terminalId: "t-1")
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 999, rows: 999) }
    await expectRemote("bad_request") { try await client.openTerminalView(terminalId: "t-1", cols: 0, rows: 24) }
    XCTAssertEqual(views.opens, [.init(terminalId: "t-1", cols: 20, rows: 5), .init(terminalId: "t-1", cols: 300, rows: 120)])
}

func testOpenOutcomesFromTheSource() async throws {
    let views = FakeTerminalViewSource()
    views.refuse("gone", with: .notFound); views.refuse("mdm", with: .refused); views.refuse("bad", with: .failed)
    let client = try await connect(makeHost(terminalViews: views))
    for (id, outcome) in [("gone", TerminalViewOpenOutcome.notFound), ("mdm", .refused), ("bad", .failed)] {
        XCTAssertEqual(try await within { try await client.openTerminalView(terminalId: id, cols: 46, rows: 30) }, outcome)
    }
}

func testAnotherTerminalIsBusy() async throws {
    let views = FakeTerminalViewSource()
    let client = try await connect(makeHost(terminalViews: views))
    XCTAssertEqual(try await within { try await client.openTerminalView(terminalId: "t-1", cols: 46, rows: 30) }, .ok)
    XCTAssertEqual(try await within { try await client.openTerminalView(terminalId: "t-2", cols: 46, rows: 30) }, .busy)
    XCTAssertEqual(views.opens.map(\.terminalId), ["t-1"])
    XCTAssertEqual(views.views[0].calls, [], "the first view stays open")
}

func testReopenRestartsTheView() async throws {   // Review Focus 3
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, n in
        view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["view \(n)"])))
        if n == 1 { view.produceOnDemand { i in i <= 50 ? .frame(deltaFrame(cols: 20, rows: 1, replacing: [0: "tick \(i)"])) : nil } }
    }
    let slow = PausableBox()
    let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
    let pushes = collect(client.terminalPushes)
    slow.circuit.pause(afterSends: 2)                   // the answer and the first snapshot, then the network stalls
    XCTAssertEqual(try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }, .ok)
    let second = Task { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
    try await Task.sleep(for: .milliseconds(100))
    slow.circuit.resume()
    XCTAssertEqual(try await second.value, .ok)
    let settled = await waitFor(pushes) { assembledText($0) == ["view 2"] }
    XCTAssertTrue(settled)
    let state = assembled(pushes.items)
    XCTAssertEqual(state.revisions.first, 1); XCTAssertEqual(state.kinds.first, .snapshot)
    XCTAssertEqual(state.screen.screenText(), ["view 2"], "no frame of the first view after the second ok")
    XCTAssertEqual(views.views[0].calls.filter { $0 == .close }.count, 1)
}

func testCloseEndsTheViewAndFreesTheSession() async throws {
    let views = FakeTerminalViewSource()
    let client = try await connect(makeHost(terminalViews: views))
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 46, rows: 30) }
    try await client.closeTerminalView(terminalId: "t-1")
    XCTAssertEqual(try await within { try await client.openTerminalView(terminalId: "t-2", cols: 46, rows: 30) }, .ok)
    XCTAssertEqual(views.views[0].calls, [.close])
}

func testSourceEndingSendsEnded() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["$"])), .ended(.gone)) }
    let client = try await connect(makeHost(terminalViews: views))
    let pushes = collect(client.terminalPushes)
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
    let ended = await waitFor(pushes) { $0.contains(.ended(terminalId: "t-1", reason: .gone)) }
    XCTAssertTrue(ended)
    XCTAssertEqual(try await within { try await client.openTerminalView(terminalId: "t-2", cols: 20, rows: 5) }, .ok)
    XCTAssertEqual(views.views[0].calls, [.close])
}

func testSessionEndClosesTheView() async throws {
    let views = FakeTerminalViewSource()
    let client = try await connect(makeHost(terminalViews: views))
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 46, rows: 30) }
    await client.close()
    let closed = await eventually { views.views.first?.calls == [.close] }
    XCTAssertTrue(closed, "the terminal must go back to the Mac's size")
}

func testFramesArriveInOrderAfterOpened() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 20, rows: 2, text: ["a", "b"])),
                  .frame(deltaFrame(cols: 20, rows: 2, replacing: [0: "c"])),
                  .frame(deltaFrame(cols: 20, rows: 2, replacing: [1: "d"])))
    }
    let client = try await connect(makeHost(terminalViews: views))
    let pushes = collect(client.terminalPushes)
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
    let done = await waitFor(pushes) { assembled($0).revisions.last == 3 }
    XCTAssertTrue(done)
    XCTAssertEqual(pushes.items.first, .opened(terminalId: "t-1"))
    XCTAssertEqual(assembled(pushes.items).revisions, [1, 2, 3])
    XCTAssertEqual(assembled(pushes.items).screen.screenText(), ["c", "d"])
}
```

(Test helpers that arrive in this step, in `FakeTerminalViewSource.swift`: `final class PausableCircuit: RelayCircuit, @unchecked Sendable` wraps the host's end — `init(_ inner: any RelayCircuit)`, `pause(afterSends n: Int)` lets `n` more sends through and holds later ones until `resume()`, `sendsWaiting: Int` counts held sends, `receive` and `close` pass through; `final class PausableBox: @unchecked Sendable` with `func wrap(_ inner: any RelayCircuit) -> any RelayCircuit` (returns a new `PausableCircuit` and keeps it) and `var circuit: PausableCircuit` (the kept one), so `connect(rig, wrap: box.wrap)` slows the host's sends. In `TerminalSessionTestCase`: `assembledText(_ pushes:) -> [String]` is `assembled(pushes).screen.screenText()`, and `expectRemote` is copied from `WorkspaceSessionTests.swift:616-630`.)

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter TerminalSessionTests`
Expected: FAIL — `error: cannot find type 'TerminalViewSource' in scope`.

- [ ] **Step 3: Implement** the protocols, slot, pump, `LinkHost` and `LinkClient` changes. `LinkClient` records the `terminal_id` of each `terminal.view.open` it sends by its `call_id`; in `handle`, an `ok` answer to such a call first yields `.opened(terminalId:)` and then resumes the call; the record goes when the call ends (answered, timed out, cancelled). `.terminalViewFrame` and `.terminalViewEnded` yield `.frame` / `.ended`; `end()` and `deinit` finish the stream.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add shellx-link/Sources/ShellXLinkSession shellx-link/Tests/ShellXLinkSessionTests
git commit -m "feat(shellx-link): open, stream and close terminal views"
```

---

### Task 8: Typing, resizing and resync

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkSession/TerminalViewSlot.swift` (input lane, `not_open`), `TerminalViewPump.swift` (`resync()`), `LinkHost.swift` (arms), `LinkClient.swift` (three methods)
- Test: `shellx-link/Tests/ShellXLinkSessionTests/TerminalSessionTests.swift`

**Interfaces:**
- Consumes: Task 2 `TerminalInputCheck`, Task 7 slot and pump.
- Produces:

```swift
// LinkClient
/// Checks `units` with `TerminalInputCheck` (throws `TerminalInputError` and sends nothing when they break a rule),
/// then sends `terminal.view.input`. Throws `LinkClientError.sessionClosed` when the session ended.
public func sendTerminalInput(terminalId: String, units: [TerminalInputUnit]) async throws
public func resizeTerminalView(terminalId: String, cols: Int, rows: Int) async throws
public func resyncTerminalView(terminalId: String) async throws
// TerminalViewSlot (internal)
func input(terminalId: String, units: [TerminalInputUnit]) async
func resize(terminalId: String, cols: Int, rows: Int) async
func resync(terminalId: String) async
// TerminalViewPump (internal)
func resync() async
```

Rules: `LinkHost` answers `.terminalViewInput` whose units fail `TerminalInputCheck` with `error` `bad_request` (`"invalid terminal input: " + reason`, no `call_id`) and applies nothing; `.terminalViewResize` with `cols < 1 || rows < 1` likewise (`"cols and rows must be at least 1"`); without a source all three are ignored. The slot answers input, resize and resync naming any terminal but the viewed one with `terminal.view.ended(terminalId, .notOpen)`. Input and resize of the view go through one FIFO lane applied by one task (`view.input` / `view.resize`), at most `ShellXLink.terminalMaxQueuedInputs` waiting besides the one being applied (later ones are dropped and logged by count only). Stopping a view applies what the lane holds before `view.close()`. `resync()`: when not already waiting for a snapshot, it starts waiting, drops a non-snapshot frame in the mailbox (and, after Task 9, the fill) and calls `view.requestSnapshot()`; while waiting it drops every non-snapshot frame.

- [ ] **Step 1: Write the failing tests**

```swift
func testInputReachesTheViewInOrder() async throws {
    let (client, view) = try await openedView()     // helper: connect, open t-1, return its FakeTerminalView
    try await client.sendTerminalInput(terminalId: "t-1", units: [.text("ls")])
    try await client.sendTerminalInput(terminalId: "t-1", units: [.key(.enter, mods: [])])
    try await client.sendTerminalInput(terminalId: "t-1", units: [.key(.letter("c"), mods: [.ctrl])])
    let all = await eventually { view.calls.count == 3 }
    XCTAssertTrue(all)
    XCTAssertEqual(view.calls, [.input([.text("ls")]), .input([.key(.enter, mods: [])]), .input([.key(.letter("c"), mods: [.ctrl])])])
}

func testInvalidInputIsBadRequestAndNotApplied() async throws {
    let views = FakeTerminalViewSource()
    let raw = try await rawSession(makeHost(terminalViews: views))
    try await raw.send(.terminalViewOpen(callId: "c1", terminalId: "t-1", cols: 46, rows: 30))
    _ = try await within { try await raw.receive() }
    try await raw.send(.terminalViewInput(terminalId: "t-1", units: [.text("ls\n")]))
    guard case let .error(code, _, callId) = try await within({ try await raw.receive() }) else { return XCTFail("no error") }
    XCTAssertEqual(code, "bad_request"); XCTAssertNil(callId)
    XCTAssertEqual(views.views[0].calls, [])
}

func testClientRefusesTypedNewlineBeforeSending() async throws {   // Review Focus 2
    let (client, view) = try await openedView()
    do {
        try await client.sendTerminalInput(terminalId: "t-1", units: [.text("ls\n")])
        XCTFail("a newline must be key enter")
    } catch let error as TerminalInputError {
        XCTAssertFalse(error.reason.contains("ls"))
    }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(view.calls, [])
}

func testInputResizeAndResyncForAnotherTerminalAreNotOpen() async throws {
    let (client, view, pushes) = try await openedViewWithPushes()
    try await client.sendTerminalInput(terminalId: "t-2", units: [.text("x")])
    try await client.resizeTerminalView(terminalId: "t-2", cols: 80, rows: 24)
    try await client.resyncTerminalView(terminalId: "t-2")
    let three = await waitFor(pushes) { $0.filter { $0 == .ended(terminalId: "t-2", reason: .notOpen) }.count == 3 }
    XCTAssertTrue(three)
    XCTAssertEqual(view.calls, [])
}

func testInputAfterCloseIsNotOpen() async throws {
    let (client, _, pushes) = try await openedViewWithPushes()
    try await client.closeTerminalView(terminalId: "t-1")
    try await client.sendTerminalInput(terminalId: "t-1", units: [.text("x")])
    let ended = await waitFor(pushes) { $0.contains(.ended(terminalId: "t-1", reason: .notOpen)) }
    XCTAssertTrue(ended)
}

func testResizeIsClampedAndKeepsOrderWithInput() async throws {
    let (client, view) = try await openedView()
    try await client.sendTerminalInput(terminalId: "t-1", units: [.text("a")])
    try await client.resizeTerminalView(terminalId: "t-1", cols: 10, rows: 2)
    try await client.sendTerminalInput(terminalId: "t-1", units: [.text("b")])
    try await client.resizeTerminalView(terminalId: "t-1", cols: 999, rows: 999)
    let all = await eventually { view.calls.count == 4 }
    XCTAssertTrue(all)
    XCTAssertEqual(view.calls, [.input([.text("a")]), .resize(cols: 20, rows: 5), .input([.text("b")]), .resize(cols: 300, rows: 120)])
}

func testInputBeforeCloseIsStillApplied() async throws {   // Review Focus 3
    let (client, view) = try await openedView()
    let gate = Gate(); view.holdInput(until: gate)
    try await client.sendTerminalInput(terminalId: "t-1", units: [.text("ls")])
    try await client.sendTerminalInput(terminalId: "t-1", units: [.key(.enter, mods: [])])
    try await client.closeTerminalView(terminalId: "t-1")
    try await Task.sleep(for: .milliseconds(100))
    gate.open()
    let closed = await eventually { view.calls.last == .close }
    XCTAssertTrue(closed)
    XCTAssertEqual(view.calls, [.input([.text("ls")]), .input([.key(.enter, mods: [])]), .close])
}

func testQueuedInputIsBounded() async throws {
    let (client, view) = try await openedView()
    let gate = Gate(); view.holdInput(until: gate)
    try await client.sendTerminalInput(terminalId: "t-1", units: [.text("0")])
    let started = await eventually { view.inputsStarted == 1 }
    XCTAssertTrue(started)
    for i in 1...70 { try await client.sendTerminalInput(terminalId: "t-1", units: [.text("\(i)")]) }
    _ = try await within { try await client.snapshot() }       // the host has read all 71
    gate.open()
    let applied = await eventually { view.calls.count == 65 }
    XCTAssertTrue(applied)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(view.calls, (0...64).map { .input([.text("\($0)")]) })
}

func testResyncSendsOneSnapshotAndDropsStaleDeltas() async throws {
    let views = FakeTerminalViewSource()
    let answer = Gate()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["one"])))
        view.answerSnapshotRequests(after: answer) {
            [.frame(deltaFrame(cols: 20, rows: 1, replacing: [0: "stale"])), .frame(snapshotFrame(cols: 20, rows: 1, text: ["again"]))]
        }
    }
    let client = try await connect(makeHost(terminalViews: views))
    let pushes = collect(client.terminalPushes)
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
    let first = await waitFor(pushes) { assembled($0).revisions == [1] }
    XCTAssertTrue(first)
    for _ in 0..<3 { try await client.resyncTerminalView(terminalId: "t-1") }
    _ = try await within { try await client.snapshot() }       // the host has read all three resyncs
    answer.open()
    let again = await waitFor(pushes) { assembledText($0) == ["again"] }
    XCTAssertTrue(again)
    XCTAssertEqual(views.views[0].snapshotRequests, 1, "resyncs before the snapshot share it")
    XCTAssertEqual(assembled(pushes.items).kinds, [.snapshot, .snapshot])
    XCTAssertEqual(assembled(pushes.items).revisions, [1, 2])
}
```

(`openedView()` and `openedViewWithPushes()` are added to `TerminalSessionTestCase`: connect a host with a fresh `FakeTerminalViewSource`, open `t-1` at 46 × 30, and return the client, `views.views[0]` and, for the second, `collect(client.terminalPushes)` started before the open.)

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter TerminalSessionTests`
Expected: FAIL — `error: value of type 'LinkClient' has no member 'sendTerminalInput'`.

- [ ] **Step 3: Implement** the lane, `not_open`, resync, the `LinkHost` arms and the `LinkClient` methods.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add shellx-link/Sources/ShellXLinkSession shellx-link/Tests/ShellXLinkSessionTests
git commit -m "feat(shellx-link): typing, resize and resync in terminal views"
```

---

### Task 9: History fill, source guards and backpressure

**Files:**
- Modify: `shellx-link/Sources/ShellXLinkSession/TerminalViewPump.swift`
- Test: create `shellx-link/Tests/ShellXLinkSessionTests/TerminalFillTests.swift` (a `TerminalSessionTestCase`)

**Interfaces:**
- Consumes: `ShellXLink.terminalSnapshotHistoryRows`, `.terminalHistoryRowBudget`, `.terminalHistoryFillMaxBytes`, `.terminalMaxDeltaHistoryRows`, `.terminalMaxGridSize`; Task 7 fakes and `PausableCircuit`.
- Produces: no new API; the pump now follows PROTOCOL.md 11.8 in full.

The sender loop and `process` (the scheduling the tests below pin; names are the implementer's):

```text
sender loop:
  if the mailbox holds an event          -> take it, handle it
  else if fill rows remain and the next block's encoded bytes fit the remaining cap
                                         -> send one history frame (block), add its bytes
  else                                   -> clear the fill; wait for the mailbox; handle what arrives

handle .frame(f):
  if f.head.cols or rows is outside 1...terminalMaxGridSize  -> send ended(.failed), stop
  waitingForSnapshot && f.kind != .snapshot                 -> drop f; requestSnapshot once
  f.kind == .snapshot:
     keep history rows y >= -terminalHistoryRowBudget; quick = min(240, history)
     send the snapshot with head.history = quick and only lines with y >= -quick
       (if splitting throws, retry once with quick = 0; if that throws too: ended(.failed))
     fill = the rows y < -quick of this capture, newest first; fill bytes = 0; remember cols, rows, alt
  f.kind == .delta:
     cols, rows or alt differ from the last snapshot sent    -> drop f; waitingForSnapshot; requestSnapshot once
     allowed = min(history, terminalMaxDeltaHistoryRows, max(0, scroll - rows)); drop lines with y < -allowed;
       head.history = allowed; send
  f.kind is anything else (a source never sends history)   -> drop f; requestSnapshot once

block: the next min(240, remaining) capture rows above what was sent, re-numbered so the newest is y = -1,
       head (kind .history, cols, rows, alt false, history = block rows), only the styles its runs use
```

- [ ] **Step 1: Write the failing tests**

```swift
func testSnapshotCarriesTheNewest240HistoryRows() async throws {
    let (client, pushes) = try await openWithSnapshot(history: (1...1000).map { "h\($0)" })
    let first = try XCTUnwrap(await firstFrameHead(pushes))
    XCTAssertEqual(first.kind, .snapshot); XCTAssertEqual(first.history, 240)
    _ = client
}

func testHistoryFramesFillUpToTheRowBudget() async throws {
    let source = (1...5000).map { "h\($0)" }
    let (_, pushes) = try await openWithSnapshot(history: source)
    let done = await waitFor(pushes) { assembled($0).revisions.last == 17 }
    XCTAssertTrue(done)
    await waitUntilQuiet(pushes)
    let state = assembled(pushes.items)
    XCTAssertEqual(state.kinds, [.snapshot] + Array(repeating: .history, count: 16))   // 240 + 15 x 240 + 160 = 4000
    XCTAssertEqual(state.screen.historyText(), Array(source.suffix(4000)))
}

func testHistoryFillStopsAtTheByteCap() async throws {
    let source = (1...3000).map { String(repeating: "x", count: 995) + String(format: "%05d", $0) }   // 1 000-byte rows
    let (_, pushes) = try await openWithSnapshot(history: source)
    await waitUntilQuiet(pushes)
    let bytes = try historyFrameBytes(pushes.items)            // encoded size of every part of every history frame
    XCTAssertLessThanOrEqual(bytes, ShellXLink.terminalHistoryFillMaxBytes)
    let history = assembled(pushes.items).screen.historyText()
    XCTAssertEqual(history.count, 480)                          // 240 + one 240-row frame (~247 KB); a second would pass the cap
    XCTAssertEqual(history, Array(source.suffix(480)))
}

func testDeltaDuringTheFillKeepsTheHistoryInOrder() async throws {   // Review Focus 5
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 20, rows: 2, text: ["s0", "s1"], history: (1...1000).map { "h\($0)" })))
    }
    let slow = PausableBox()
    let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
    let pushes = collect(client.terminalPushes)
    slow.circuit.pause(afterSends: 3)                  // answer, snapshot, first history frame; the second waits
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 2) }
    let stalled = await eventually { slow.circuit.sendsWaiting == 1 }
    XCTAssertTrue(stalled)
    views.views[0].emit(.frame(deltaFrame(cols: 20, rows: 2, replacing: [0: "n0", 1: "n1"], scroll: 2)))
    try await Task.sleep(for: .milliseconds(100))
    slow.circuit.resume()
    await waitUntilQuiet(pushes)
    let state = assembled(pushes.items)
    XCTAssertEqual(state.kinds, [.snapshot, .history, .history, .delta, .history, .history])
    XCTAssertEqual(state.screen.historyText(), (1...1000).map { "h\($0)" } + ["s0", "s1"])
    XCTAssertEqual(state.screen.screenText(), ["n0", "n1"])
}

func testNewSnapshotDropsTheOldFill() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["a"], history: (1...1000).map { "h\($0)" })),
                  .frame(snapshotFrame(cols: 30, rows: 1, text: ["b"])))
    }
    let slow = PausableBox()
    let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
    let pushes = collect(client.terminalPushes)
    slow.circuit.pause(afterSends: 1)                  // the answer; snapshot "a" waits on the network
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 5) }
    let pulled = await eventually { views.views.first?.nextFrameCalls == 2 && slow.circuit.sendsWaiting == 1 }
    XCTAssertTrue(pulled, "snapshot b waits in the host while snapshot a is being sent")
    slow.circuit.resume()
    await waitUntilQuiet(pushes)
    XCTAssertEqual(assembled(pushes.items).kinds, [.snapshot, .snapshot])
    XCTAssertEqual(assembled(pushes.items).screen.historyText(), [])
}

func testSlowPhoneGetsTheLastScreenWithBoundedFrames() async throws {   // Review Focus 4
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 20, rows: 1, text: ["tick 0"])))
        view.produceOnDemand { n in n <= 200 ? .frame(deltaFrame(cols: 20, rows: 1, replacing: [0: "tick \(n)"])) : nil }
    }
    let slow = PausableBox()
    let client = try await connect(makeHost(terminalViews: views), wrap: slow.wrap)
    let pushes = collect(client.terminalPushes)
    slow.circuit.pause(afterSends: 2)                  // answer and snapshot
    _ = try await within { try await client.openTerminalView(terminalId: "t-1", cols: 20, rows: 1) }
    try await Task.sleep(for: .milliseconds(300))
    let view = views.views[0]
    XCTAssertLessThanOrEqual(view.nextFrameCalls, 3, "the snapshot, the delta being sent, one waiting")
    slow.circuit.resume()
    let last = await waitFor(pushes) { assembledText($0) == ["tick 200"] }
    XCTAssertTrue(last)
    XCTAssertEqual(view.maxConcurrentNextFrameCalls, 1)
}

func testDeltaOfAnotherShapeAsksForASnapshot() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 10, rows: 2, text: ["a"])), .frame(deltaFrame(cols: 12, rows: 2, replacing: [0: "b"])))
        view.answerSnapshotRequests { [.frame(snapshotFrame(cols: 12, rows: 2, text: ["c"]))] }
    }
    let (_, pushes) = try await open(views)
    await waitUntilQuiet(pushes)
    XCTAssertEqual(assembled(pushes.items).kinds, [.snapshot, .snapshot])
    XCTAssertEqual(views.views[0].snapshotRequests, 1)
}

func testFirstFrameThatIsNotASnapshotIsDropped() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(deltaFrame(cols: 10, rows: 1, replacing: [0: "x"])))
        view.answerSnapshotRequests { [.frame(snapshotFrame(cols: 10, rows: 1, text: ["s"]))] }
    }
    let (_, pushes) = try await open(views)
    await waitUntilQuiet(pushes)
    XCTAssertEqual(assembled(pushes.items).revisions, [1]); XCTAssertEqual(assembledText(pushes.items), ["s"])
}

func testDeltaHistoryIsClamped() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in
        view.emit(.frame(snapshotFrame(cols: 10, rows: 2, text: ["a"])),
                  .frame(deltaFrame(cols: 10, rows: 2, replacing: [:], scroll: 3000, history: (1...2500).map { "b\($0)" })))
    }
    let (_, pushes) = try await open(views)
    await waitUntilQuiet(pushes)
    let history = assembled(pushes.items).screen.historyText()
    XCTAssertEqual(Array(history.suffix(2000)), (501...2500).map { "b\($0)" })
    XCTAssertEqual(history.count, 2002)                          // the two old screen rows, then 2 000 carried rows
}

func testGridBeyondTheLimitEndsTheView() async throws {
    let views = FakeTerminalViewSource()
    views.onOpen("t-1") { view, _ in view.emit(.frame(snapshotFrame(cols: 1001, rows: 1, text: ["x"]))) }
    let (_, pushes) = try await open(views)
    let ended = await waitFor(pushes) { $0.contains(.ended(terminalId: "t-1", reason: .failed)) }
    XCTAssertTrue(ended)
}
```

(Helpers in `TerminalFillTests`: `open(_ views:)` connects and opens `t-1` at 20 × 5, returning the client and the started push collector; `openWithSnapshot(history:)` does the same with a source whose first frame is `snapshotFrame(cols: 20, rows: 2, text: ["s0", "s1"], history:)`; `firstFrameHead(_:)` waits for and returns the `head` of the first `.frame` push; `historyFrameBytes(_:)` sums `LinkCodec.encode(.terminalViewFrame(…)).count` over the parts of every frame whose part 0 head is `.history`. `waitUntilQuiet(_ pushes: Collector<TerminalViewPush>, quiet: Duration = .milliseconds(300)) async` (returns once no push arrived for `quiet`, or after 5 s) joins `TerminalSessionTestCase`.)

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-link --filter TerminalFillTests`
Expected: FAIL — the fill tests fail their assertions (for example `XCTAssertEqual failed: ("Optional(1000)") is not equal to ("Optional(240)")`).

- [ ] **Step 3: Implement** the fill, the guards and the scheduling in `TerminalViewPump`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add shellx-link/Sources/ShellXLinkSession/TerminalViewPump.swift shellx-link/Tests/ShellXLinkSessionTests
git commit -m "feat(shellx-link): terminal history fill and backpressure"
```

---

### Task 10: Rewrite PROTOCOL.md section 10 (phone commands)

**Files:**
- Modify: `shellx-link/spec/PROTOCOL.md` section 10 (lines 694-874 before this task; anchors below)

**Interfaces:**
- Produces: the safety analysis that answers the three questions of `skills/cmux-socket-policy/references/remote-relay-authorization.md` for `terminal.view.*` and `terminal.create` (base spec §9; S2 §3.8d). 2B's PR quotes it.

- [ ] **Step 1: Replace the opening paragraph** (from "A phone can make the Mac act" to "or open arbitrary content on the Mac.") with:

~~~~markdown
A phone can make the Mac act: decide an agent's pending request, type into an agent session, interrupt it, close the
terminal it runs in, close any terminal tab of a listed workspace, make, rename or close a workspace, open a new
terminal tab in a listed workspace, and view one terminal of a listed workspace and type into it. This section is the
safety analysis for those commands. It follows the rules a remote command channel must meet: deny by default, allow
only the calls a product flow needs, scope every call to objects the caller may touch, and never let a call execute
or open arbitrary content on the Mac. Typing into a terminal the user opened on the phone is the one place where what
the phone sends runs as the user's input, on purpose (Terminal views below).
~~~~

- [ ] **Step 2: Replace the "Default deny" paragraph** (through "see Attachments below.)") with:

~~~~markdown
**Default deny.** A host acts only on the calls in the table below. Every other `t` gets no effect: a
call of a later version is answered `error` `unsupported` (section 3), any other unknown frame is
ignored, and a host frame type sent by a client is ignored or answered `bad_request` (section 7). No
field of any message names a command line, a program, a directory or other path on the host, an environment variable,
or a URL for the host to open or run. Only `terminal.view.input` names a terminal to type into, and only the one
terminal its session opened with `terminal.view.open` (Terminal views below); `chat.send` and `chat.interrupt` name an
agent session, and the host types only into that session's terminal (Shell fall-through below). A call names a
workspace only to rename or close one that the host's own list holds (`workspace.rename`, `workspace.close`), to find a
tab in it (`terminal.close`), or to add a terminal tab to it (`terminal.create`), and `workspace.create` names nothing:
the host chooses where the new workspace goes. `agent.close` names an agent session and nothing else, and the host
closes only the terminal that session is bound to (Agents below). `terminal.close` names a workspace and one of its
terminals in the host's own list, to close that tab and for nothing else (Tabs below). `terminal.view.open` names a
terminal of the host's own list, to show it and for nothing else.
(`attach.begin.name` is a label that the host sanitises, never a path: see Attachments below.)
~~~~

- [ ] **Step 3: Add rows to "Allowed calls"**, after the `terminal.close` row and before `ping`:

```markdown
| `terminal.view.open` | Starts sending that terminal's screen and its history (at most 4 000 rows) to the phone, and counts the phone among the parties of the terminal's size (section 11.3). Changes no selection, focus or window order on the Mac | One terminal of a local workspace in the host's list, by `terminal_id`; `not_found` for any other id; at most one per session (`busy`) |
| `terminal.view.input` | Types text, presses keys from a fixed list (no ⌘), pastes text, or turns the mouse wheel (alternate screen only) in that terminal, as the user at the Mac's keyboard would: whatever runs there gets it | Only the terminal this session views; for any other `terminal_id` nothing is typed and the answer is `terminal.view.ended` `not_open`. At most 4 096 bytes of typed text and 16 384 of pasted text per message, no control characters in typed text |
| `terminal.view.resize`, `terminal.view.resync`, `terminal.view.close` | Reports the phone's size, which the terminal takes while the phone is the last to use it; sends a new snapshot; ends the view (the terminal goes back to the Mac's size) | The terminal this session views |
| `terminal.create` | Opens a new terminal tab in that workspace's selected pane, running the user's default shell, as the Mac's add-tab button does. Changes no selection, focus or window order | One local workspace in the host's list, by `workspace_id`; `not_found` otherwise. The call carries nothing else: no command, path, directory, program or environment |
```

- [ ] **Step 4: Replace the "Scope" paragraph** with:

~~~~markdown
**Scope.** The host serves only its own Claude Code agent sessions and their pending requests, and its own
local workspaces with their terminals. `session_id`, `request_id`, `workspace_id` and `terminal_id` are looked up in
the host's own lists; an id it does not have is `not_found` (`unknown` for a reply). A phone cannot name a workspace
that is not in the list (an SSH or other remote workspace never is), nor a file, machine or account, nor a terminal
outside those workspaces; `terminal.close` and `terminal.view.open` reach a terminal of a listed workspace by its
`terminal_id`, `terminal.view.input` reaches only the terminal its session opened, and `agent.close` reaches a
terminal only through a live agent session the host lists in one of those local workspaces. Only a phone the Mac
trusts gets this far: signed in to the same account, holding a proof from a QR code the Mac showed, and allowed by
the user on that Mac (section 9).
~~~~

- [ ] **Step 5: Shell fall-through** — append to the end of that paragraph (after "whatever runs there (Tabs, below)."): ``Typing into a shell is what a terminal view is for, but only into a terminal the user opened as one on the phone (`terminal.view.input`, Terminal views below); `chat.send` and `chat.interrupt` stay bound to live agents.``

- [ ] **Step 6: Workspaces block.** Replace its first sentence with ``**Workspaces.** `workspace.create` starts something on the Mac (so does `terminal.create`, Terminal views below), so `workspace.*` answers the three questions a remote command channel must answer, one by one.`` In its first bullet, the clause that begins "and no call types into that shell" and ends "(Shell fall-through above)." (it spans a line break) becomes ``and no workspace call types into that shell: `chat.send` still reaches only the terminal of a live agent (Shell fall-through above), and only a terminal view the user opened types into a shell (Terminal views below).``

- [ ] **Step 7: Insert a "Terminal views" block** after the "Tabs" block (before "More rules"):

~~~~markdown
**Terminal views.** `terminal.view.*` and `terminal.create` let a phone use the Mac's terminals, so they answer the
same three questions.

- Does it run commands or open content on the Mac? Yes, on purpose: `terminal.view.input` types into the one terminal
  the session opened, exactly as the user at the Mac's keyboard could, so whatever runs there (a shell, an editor, an
  agent) gets what the phone types and acts on it. Nothing else is reachable. No message carries a command line, path,
  directory, environment variable, URL or program name for the host to run or open. Typed text cannot hold control
  characters, so no escape sequence reaches the Mac's terminal (the Mac turns typed text into key presses, and would
  hand an escape sequence in it to its display parser rather than to the program); keys come from a fixed list with
  `ctrl`, `alt` and `shift` only, so the Mac app's ⌘ shortcuts cannot be pressed (a key the user bound to a terminal
  action in the terminal's own configuration does what it does at the Mac); pasted text goes through the Mac's paste
  path and may hold only tabs and line breaks as control characters; the mouse wheel acts only on the alternate
  screen. `terminal.create` starts the user's default shell in a new tab, in a directory the Mac chooses, and types
  nothing into it.
- Does it change or destroy what the phone does not own? It reaches only terminals of the Mac's own local workspaces,
  by ids the host looks up in its own list; SSH and other remote workspaces are not listed, so `not_found`. Input goes
  only to the terminal its session opened, never to another (`not_open`), and a view ends with its session, its
  terminal or device management. The phone's size applies to that terminal only while the phone is the last to use
  it, and the terminal goes back to the Mac's size when the view ends (closed, another terminal opened, session
  ended, phone removed). None of these calls changes the Mac's selection or focus or brings a window to the front.
  `terminal.create` adds a tab and closes nothing.
- Does it read state the phone has no business seeing? It reads the screen of the terminal the phone opened, at most
  4 000 rows (and 262 144 bytes) of its history, and the terminal's colors: what the user sees in that terminal on the
  Mac. It reads no other terminal, no file, no environment variable and no setting beyond the terminal's colors. One
  view per session, one frame per view waiting to be sent, and bounded input queues keep what a phone can make the
  Mac capture and hold small (section 11.8).
~~~~

- [ ] **Step 8: Replace the "More rules" paragraph** with:

~~~~markdown
More rules: a Mac whose device management (MDM) blocks remote control does not run a Link host at all, and a
host that sees that policy change during a session answers every `workspace.create`, `workspace.rename`,
`workspace.close`, `agent.close`, `terminal.close`, `terminal.create` and `terminal.view.open` with `refused` without
acting, and ends an open view with `terminal.view.ended` `refused` (input that arrives after that is not applied).
Removing a phone on the Mac closes its sessions at once (above), and with them its view. A control call,
`agent.close`, `terminal.close` and `terminal.create` included, runs on its own, so a slow Mac does not hold up the
session's other calls; the input of a view is applied in order without holding them up either. The host never logs a
workspace title, directory, branch or tab title, the title of an agent session, terminal content, or text and keys a
phone typed or pasted. These are ShellX Link calls, not cmux socket methods: the allowlist of the `cmux ssh` relay
does not change.
~~~~

- [ ] **Step 9: Replace the "Why the rest is acceptable" paragraph** with:

~~~~markdown
**Why the rest is acceptable.** A paired phone is trusted like the user sitting at the Mac: it is signed in
to the user's account, and the user allowed that phone on that Mac in person; the relay can neither create
that trust nor widen it (section 9). Removing the phone on the Mac untrusts its key at once: its live
sessions close and its next handshake is refused. Removing it on the phone deletes the grant, so the relay
mints it no new connect ticket, and the Mac drops the key when it next checks the grants. Within that
trust, typing into the user's own agent session, stopping it, closing its terminal or any of its tabs, answering
its requests, making, renaming and closing its workspaces, opening terminal tabs in them, and watching and typing
into one of their terminals are what the user could do at the keyboard; the allowed calls limit *which objects* a
phone reaches (this Mac's live agent sessions and their pending requests, and its local workspaces with their
terminal tabs), not what the user may do with them. Out of reach for a phone in this version: spawning or respawning
terminals other than a new workspace's first terminal and the new tab of `terminal.create`, keys or text for a
terminal its session has not opened, the Mac app's ⌘ shortcuts, opening URLs or files, the Mac's settings, the
`bypass` modes, other machines and other accounts. The host never logs message text, attachment names or bytes, tool
inputs, workspace or tab names, terminal content, typed keys or text, tickets or tokens.
~~~~

- [ ] **Step 10: Verify**

Run:
```bash
grep -c 'keys or text for anything but a live agent' shellx-link/spec/PROTOCOL.md
grep -c 'none names a terminal to type into' shellx-link/spec/PROTOCOL.md
grep -c '^\*\*Terminal views\.\*\*' shellx-link/spec/PROTOCOL.md
grep -c '^| `terminal\.view\.' shellx-link/spec/PROTOCOL.md
grep -c '^| `terminal\.create` |' shellx-link/spec/PROTOCOL.md
```
Expected: `0`, `0`, `1`, `11` (8 in §4, 3 in §10), `2`.

- [ ] **Step 11: Commit**

```bash
git add shellx-link/spec/PROTOCOL.md
git commit -m "docs(shellx-link): safety analysis for terminal views and terminal.create"
```

---

### Task 11: Probe commands and README

**Files:**
- Create: `shellx-link/Sources/shellx-link-probe/Terminal.swift`
- Modify: `shellx-link/Sources/shellx-link-probe/main.swift` (usage text 12-60, command switch 65-131), `shellx-link/Sources/shellx-link-probe/Support.swift:9` (flag `dry-run`)
- Modify: `shellx-link/README.md`

**Interfaces:**
- Consumes: `LinkClient` terminal API (Tasks 6-8), `TerminalFrameAssembler`, `TerminalScreen`, `TerminalKey`, `TerminalModifier`, `Session.open`, `Log`, `Arguments`, `ExitStatus`, `TextFile`.
- Produces: `enum TerminalCommands { static func view(_ args: Arguments) async throws; static func type(_ args: Arguments) async throws; static func create(_ args: Arguments) async throws }` and the commands below (2B uses them for live checks).

Usage lines (add after the `terminal-close` line):

```text
  shellx-link-probe terminal-view <terminal_id> --state <dir> [--machine <id>] [--cols <n>] [--rows <n>] [--seconds <n>]
  shellx-link-probe terminal-type <terminal_id> --state <dir> [--machine <id>] [--cols <n>] [--rows <n>] [--text <text>] [--key <key>]... [--paste-file <file>] [--wait-ms <n>] [--dry-run]
  shellx-link-probe terminal-create <workspace_id> --state <dir> [--machine <id>]
```

Usage explanation (add after the `terminal-close` paragraph):

```text
terminal-view opens a view of a terminal (take the id from workspaces) at --cols x --rows (80 x 24 when left
out), logs every frame it applies and prints the screen after each snapshot and when it stops, until the view
or its session ends (exit 4) or --seconds pass (exit 0). terminal-type opens a view, waits for its first snapshot, sends one
input message (the --paste-file text, then --text, then each --key in order), logs the time until the next
frame (the echo), waits --wait-ms (1000 when left out), prints the screen and closes the view. A key is a name
(enter, tab, backspace, escape, delete, space, up, down, left, right, home, end, page_up, page_down, a to z)
after any of ctrl, alt and shift joined with +, like ctrl+c or shift+tab. With --dry-run it prints the
terminal.view.input message instead of connecting. terminal-create opens a terminal tab in a workspace without
changing what the Mac shows; it exits 2 unless the Mac answers ok. All three exit 3 when the Mac does not offer
the feature (terminal_view, terminal_create).
```

Behaviour: `terminal-view` and `terminal-type` read `client.terminalPushes` in a task, run a `TerminalFrameAssembler` and a `TerminalScreen` from each `.opened`, call `resyncTerminalView` when the assembler asks, and log `frame r=<revision> <kind> <cols>x<rows> alt=<bool> history=<n> scroll=<n> parts=<n>` per applied frame, `first snapshot <ms> ms after the open`, `gap: asked for a snapshot`, and `terminal.view.ended reason=<reason>`; screen rows are printed through `Log.shown`, one per line, prefixed by four spaces. `terminal-type` validates its units with `TerminalInputCheck.check` (exit 1 with the reason), parses `--key` as `+`-joined names whose last part is a `TerminalKey` and the others `TerminalModifier`s (an unknown name is an error), and logs `echo <ms> ms`. `--dry-run` prints `LinkCodec.encode(.terminalViewInput(terminalId:units:))` as UTF-8 and exits 0 without reading `--state`. `--key` is repeatable.

- [ ] **Step 1: Build and check the current probe has no such command**

Run: `swift build --package-path shellx-link && shellx-link/.build/debug/shellx-link-probe terminal-type t-1 --state /tmp/x --text ls; echo "exit=$?"`
Expected: `shellx-link-probe: unknown command` … and `exit=1` (leave `--dry-run` out here: until Step 2 adds the flag, the parser stops earlier with `--dry-run needs a value`).

- [ ] **Step 2: Implement** `Terminal.swift`, the usage and switch cases (`terminal-view`: positional 1, options `state machine cols rows seconds`; `terminal-type`: positional 1, options `state machine cols rows text key paste-file wait-ms dry-run`, repeatable `key`; `terminal-create`: positional 1, options `state machine`), and the `dry-run` flag.

- [ ] **Step 3: Verify the dry run and the help**

Run: `swift build --package-path shellx-link && shellx-link/.build/debug/shellx-link-probe terminal-type t-1 --state /tmp/unused --text ls --key enter --key ctrl+c --dry-run`
Expected: one line of JSON with `"t":"terminal.view.input"`, `"terminal_id":"t-1"` and `"units":[{"k":"text","text":"ls"},{"k":"key","key":"enter"},{"k":"key","key":"c","mods":["ctrl"]}]` (key order may differ).
Run: `shellx-link/.build/debug/shellx-link-probe terminal-type t-1 --state /tmp/unused --key cmd+q --dry-run; echo "exit=$?"`
Expected: an error naming the unknown key name, `exit=1`.
Run: `shellx-link/.build/debug/shellx-link-probe help | grep -c 'terminal-'`
Expected: `5` or more (the three usage lines and the explanation).

- [ ] **Step 4: README.** In the command block after the `terminal-close` line add:

```bash
$probe terminal-view <terminal_id> --state $state [--cols 80 --rows 24] [--seconds 30]
$probe terminal-type <terminal_id> --state $state --text "ls" --key enter
$probe terminal-create <workspace_id> --state $state
```

and append these bullets to the list after the block:

```markdown
- `terminal-view` shows a terminal of the Mac the way a phone does (`terminal_view`, `spec/PROTOCOL.md`
  section 11): it logs every frame and prints the screen after each snapshot. A session views one terminal at a
  time, so the probe holds its view until it exits.
- `terminal-type` measures the echo: the time from sending the input to the next frame. A key is `name` or
  `mod+name` (`ctrl+c`, `shift+tab`); `--dry-run` prints the `terminal.view.input` message without connecting.
- `terminal-create` opens a new terminal tab (`terminal_create`) without changing what the Mac shows.
```

and, in the opening paragraph, after "a message codec, a relay client and sessions", add ``, and terminal views (`ShellXLinkCore` holds the grid format with its splitter, assembler and screen model, which the iOS app and the Mac's tests share)``.

- [ ] **Step 5: Run the whole package**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add shellx-link/Sources/shellx-link-probe shellx-link/README.md
git commit -m "feat(shellx-link): probe commands for terminal views"
```

---

### Task 12: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Full verification**

Run: `swift test --package-path shellx-link 2>&1 | tail -3`
Expected: `with 0 failures`.
Run: `bash scripts/shellx/check-link-license.sh; echo "exit=$?"`
Expected: `exit=0`.
Run: `python3 scripts/verify-local.py; echo "exit=$?"`
Expected: `exit=0` (it parses the changed Swift files and runs the affected static checks).
Run: `git diff --name-only develop...HEAD | grep -v '^shellx-link/'`
Expected: no output (nothing outside `shellx-link/`).

- [ ] **Step 2: Localization audit.** Record in the hand-off: no app UI, settings, menu or catalog string changed; the new text is developer documentation and probe output inside the MIT `shellx-link` package, which has no string catalog (the same as every earlier probe command).

- [ ] **Step 3: Whole-branch review.** Run a fresh review of `develop...feat/shellx-terminal-2a-protocol` (superpowers:requesting-code-review; correctness first), pointing the reviewer at this plan's "Wire specification" and "Review Focus". Fix what it finds (a behavioural bug gets its failing test committed first, CLAUDE.md), re-run Step 1, and commit fixes as `fix(shellx-link): …`.

- [ ] **Step 4: Land on develop** (contracts §1; never `main`, no deploy, no release):

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git checkout develop
git merge --no-ff feat/shellx-terminal-2a-protocol -m "Merge branch 'feat/shellx-terminal-2a-protocol' into develop"
swift test --package-path shellx-link 2>&1 | tail -3      # expect: with 0 failures
git push origin develop
git worktree remove .worktrees/terminal-2a-protocol
git branch -d feat/shellx-terminal-2a-protocol
```

- [ ] **Step 5: Report** to the user: the merge commit, the test count, the verification results, the localization audit, and that live use of the probe commands waits for 2B (the Mac implements `TerminalViewSource` and `TerminalCreator`).

---

## Spec notes

1. **Assembler location.** S2 §5 places the assembler and revision tests in `ShellXAppCore` (iPhone) and `core` (Android). Per this programme's split, the assembler and the screen model live in `ShellXLinkCore` (MIT) so the iPhone, the Mac's tests and the probe share one implementation; 2C still tests its use, 3G ports it, and `terminal.json` is shared by Swift and Kotlin.
2. **`not_found` for input.** Base spec §9 answers input to a terminal that is not open with `not_found`; contracts §6 gives `terminal.view.input` no `call_id`, so the host answers `terminal.view.ended` `not_open` instead (nothing applied, never another terminal).
3. **Scroll path.** Base spec §7.2 routes scrolling through `mobile.terminal.mouse`; the code's scroll path is `mobile.terminal.scroll` with `delta_lines` (`Sources/TerminalController.swift:16494-16524`, `TerminalSurface.mobileScroll` in `Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Surface/TerminalSurface+Mobile.swift:15`), as S2 §3.8a says. The wire `lines` are mouse-wheel lines, positive toward older content; 2B maps the sign onto `ghostty_surface_mouse_scroll` and tests it. Base spec §7.2 says swiping on the main screen only scrolls the phone, so the host ignores `scroll` units there.
4. **Paste limit.** Base spec §7.2's 4 096-byte limit is kept for typed text; a paste gets 16 384 bytes (the `chat.send` limit), since it is one block.
5. **Size bounds.** The Mac already clamps a phone's report to 20–300 columns and 5–120 rows (`Sources/TerminalController.swift:16937-16938`); the protocol adopts these bounds.
6. **Key names.** The Mac's named-key path (`pendingKeyEvent`, `TerminalSurface+Input.swift:854`) has no function keys and no digits; the key list matches what it can press, and the open enum leaves room to add names. `cmd`/`super` are left out on purpose so the Mac app's ⌘ shortcuts stay out of reach.
7. **History fill.** S2 §3.8c ("nạp nền một lần") is one fill per snapshot from the same capture, sent as several history frames so a delta never waits behind it; no client message asks for it and there is no paging. S2 leaves the byte cap open: 262 144 bytes (256 KiB), the coordinator's decision of 2026-11-07, so each snapshot's fill costs at most about 0.25 MB of mobile data; the 4 000-row budget still applies, whichever comes first. The row budget is cmux's default, `MobileTerminalScrollbackPreference.defaultRows` = 4 000. Because a snapshot replaces the history, every main-screen snapshot (open, resize, return from vim or less, palette change, resync) gets its own fill, so leaving a full-screen program can resend up to the cap.
8. **Wide cells and the Mac.** Ghostty's export gives every wide or multi-scalar cell its own span (`ghostty/src/apprt/embedded.zig:3736-3738`), but a span of exactly two scalars and two columns can be either two narrow cells or one cluster (a flag, `U+2764 U+FE0F`). 2B must turn each Ghostty cell into exactly one Link cell (for example by Swift `Character` count) and has a test for flags.
9. **`terminal.create` selection.** Verified: `v2MobileTerminalCreate` (`Sources/TerminalController.swift:16174-16204`) does not pass `preserveBonsplitSelectionWhenUnfocused` (`Sources/Workspace.swift:9636`, default `false`), so it changes the Mac's tab selection, as S2 §3.3 says; 2B's `TerminalCreator` must pass it and test that the selection stays.

## Contract additions

Names other plans need that contracts §6 does not list (2A cannot edit the contracts; the orchestrator adds them):

- **Wire.** Frame envelope `revision` (≥ 1, +1 per frame within a view), `part`, `parts` (1–256), `head` (part 0), `styles`, `lines`; head `kind` (`snapshot`, `delta`, `history`), `cols`, `rows`, `alt`, `cursor`, `palette`, `history`, `scroll`; run keys `x`, `t`, `s`, `w`. `terminal.view.open.result` outcomes `ok`, `not_found`, `refused`, `busy`, `failed`; `terminal.create.result` reuses the workspace outcomes. `terminal.view.ended` reasons `gone`, `refused`, `failed`, `not_open`. Key names and modifiers as PROTOCOL.md 11.2; limits as 11.10.
- **ShellXLinkCore.** `TerminalViewOpenOutcome`, `TerminalViewEndReason`, `TerminalKey`, `TerminalModifier`, `TerminalInputUnit`, `TerminalInputCheck`, `TerminalInputError`, `TerminalFrameKind`, `TerminalCursorShape`, `TerminalCursor`, `TerminalPalette`, `TerminalAttribute`, `TerminalCellStyle`, `TerminalStyle`, `TerminalRun`, `TerminalLine`, `TerminalFrameHead`, `TerminalFramePart`, `TerminalGridFrame`, `TerminalFrameSplitter`, `TerminalFrameAssembler`, `TerminalAssemblyResult`, `TerminalScreen`, `TerminalRow`, `TerminalStyledRun`, `TerminalCell`; `ShellXLink.terminalViewFeature`, `ShellXLink.terminalCreateFeature` and the `ShellXLink.terminal*` limits; `LinkMessage` cases `terminalViewOpen`, `terminalViewOpenResult`, `terminalViewFrame`, `terminalViewInput`, `terminalViewResize`, `terminalViewResync`, `terminalViewClose`, `terminalViewEnded`, `terminalCreate`, `terminalCreateResult`.
- **ShellXLinkSession.** Host side (2B implements): `TerminalViewSource`, `TerminalView`, `TerminalViewOpenResult`, `TerminalViewEvent`, `TerminalCreator`, and `LinkHost.init(…, terminalViews:, terminalCreator:, …)`. Client side (2C uses): `TerminalViewPush` (`opened`, `frame`, `ended`), `LinkClient.terminalPushes`, `openTerminalView(terminalId:cols:rows:)`, `closeTerminalView(terminalId:)`, `sendTerminalInput(terminalId:units:)`, `resizeTerminalView(terminalId:cols:rows:)`, `resyncTerminalView(terminalId:)`, `createTerminal(workspaceId:)`.
- **Probe.** `shellx-link-probe terminal-view`, `terminal-type`, `terminal-create` (2B's live checks).
