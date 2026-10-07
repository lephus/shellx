# ShellX command line — reference

Every command: `shellx <command> [args] [--json] [--socket ADDRESS] [--help]`.

- `--json` prints exactly one JSON object on stdout (events: one object per line). Errors with `--json` are also printed on **stdout** as `{"error":{"code":"…","message":"…"}}`; without `--json` they go to stderr as `shellx: <message> (<code>)`.
- Commands that create something print only the new id (for `$(…)`); other commands print nothing on success unless they read something.
- `--socket ADDRESS` overrides `$SHELLX_SOCKET` and the endpoint file's address (tests only).

## Targets

| Form | Means |
|---|---|
| `p<id>` | a terminal pane, e.g. `p1712` |
| `p-<n>` | a browser pane, e.g. `p-2` |
| `t<id>` | a tab, e.g. `t1712` (the first pane of a tab has the tab's id) |
| `w:<id>` or a name | a workspace (names ignore case; two with the same name → `ambiguous`, use `w:<id>`) |
| `@self` | your pane (`$SHELLX_PANE_ID`); for tab commands, your tab |
| `@tab` | your tab (`$SHELLX_TAB_ID`) |
| `@focused` | the focused pane of the selected tab (or that tab) |
| bare number | a pane, except for `rename` and `workspace move`, where it is a tab |

Ids are written without leading zeros (`p12`, not `p012`). `focus` and `close` take a pane or a tab, so use the prefix (a bare number is a pane). `@self`/`@tab` outside a ShellX pane exit 2. Commands that need a pane refuse a tab (`t…`, `@tab`) with exit 2. Targets are accepted the same way by every command.

## Who may control ShellX

- Shells that ShellX opened carry `$SHELLX_CLI_TOKEN`; their `shellx` may use every command.
- Any other terminal (Terminal.app, iTerm, a cron job…) gets exit 6 `forbidden` for everything except `notify` without a pane, until the user ticks **"Allow other terminals"** in the ShellX tray menu (Command line). Ask the user to do it; never try to work around it.
- When the user unticks **"Allow controlling ShellX from the command line"**, every command except `notify` exits 6 `cli_disabled`.

## Limits

- `send` text (`--text` or `--stdin`): at most 48 KiB of UTF-8. `--cmd`: at most 16 KiB. `wait --match` pattern: at most 1 KiB.
- `read` returns pages of at most 48 KiB; `shellx read` fetches every page and prints them as one text.
- `notify`: body at most 1024 characters, title at most 128 (longer text is cut); control characters are removed.
- `browser eval` script: at most 32 KiB.

## Exit codes

| Code | Meaning | Error codes |
|---|---|---|
| 0 | ok | |
| 1 | other error | `exited`, `no_room`, `session_limit`, `spawn_failed`, `busy`, `eval_error`, `load_failed`, `internal`, `not_installed`, `io` |
| 2 | usage | `usage`, `bad_request` (also an invalid or too slow `--match` pattern) |
| 3 | ShellX is not running (no endpoint, stale endpoint, connection or handshake failed) | `not_running` |
| 4 | not found | `not_found`, `ambiguous` |
| 5 | timed out | `timeout` |
| 6 | refused | `forbidden` (outside ShellX: tick "Allow other terminals"), `cli_disabled`, `forbidden_origin`, `running_command` (use `--force`), a skill file you changed |
| 7 | incompatible | ShellX too old for this command (`incompatible`, `unknown_type`, `unsupported_role`); for `browser` commands: this ShellX has no browser panes yet |
| 8 | the ShellX window is closed | `no_ui` |

---

## shellx ls

`shellx ls [--ids] [--json]` — list workspaces, tabs and panes.

- Text: an indented tree — workspace (`w:<id>`, `(current)`), tab (`t<id>`, title, `●n` unread, `(selected)`, `[agent]`), pane (`p<id>`, title, `~/cwd`, branch, `:port`, `(focused)`, `[exited n]`).
- `--ids`: every tab id and pane id, one per line.
- `--json`:

```json
{"workspaces":[{"id":"w:default","name":"Default","current":true,"collapsed":false,
  "tabs":[{"id":"t1712","title":"vim","custom":false,"selected":true,"unread":2,"running":true,"agent":false,
    "panes":[{"id":"p1712","kind":"terminal","title":"vim","cwd":"/Users/me/app","branch":"main","ports":[3000],
              "running":true,"exited":false,"exitCode":null,"focused":true,"zoomed":false,"phone":false,"driver":"desktop","agent":false}]}]}],
 "selectedTab":"t1712","focusedPane":"p1712"}
```

`cwd`, `branch` and `exitCode` may be `null` (unknown / still running); `selectedTab` and `focusedPane` are `null` when no tab is open. Browser panes (when available) have `"kind":"browser"` and `url`.

Exit codes: 0, 3, 6, 7.

## shellx new-tab

`shellx new-tab [--workspace W] [--cwd DIR] [--cmd COMMAND] [--focus]` — open a tab; prints `t<id>`.

- `--workspace`: workspace id (`w:<id>`) or name; default the current workspace.
- `--cwd`: relative paths are made absolute from your directory; a missing directory falls back to home.
- `--cmd`: see "The `--cmd` rule".
- `--focus`: select the new tab (default: the user's selection stays).
- JSON: `{"tab":"t101","pane":"p101"}`.

Exit codes: 0, 1 (`session_limit`, `spawn_failed`, `busy`), 3, 4, 6, 7.

## shellx split

`shellx split [--right|--down] [--pane PANE] [--cwd DIR] [--cmd COMMAND] [--focus]` — split a pane; prints `p<id>`.

- `--pane`: the pane to split; default `@self` inside ShellX, else `@focused`. The tab need not be selected.
- `--cwd`: default the split pane's directory.
- `--focus`: focus the new pane and select its tab (default: focus and selection stay).
- JSON: `{"pane":"p102","tab":"t100"}`.

Exit codes: 0, 1 (`no_room`, `session_limit`, `spawn_failed`, `busy`), 2, 3, 4, 6, 7.

## The `--cmd` rule

The new shell starts normally (login files, hooks); COMMAND is then pasted and Enter pressed, like `send`, once the shell is ready: when it first reports its directory at the prompt, or, for a shell without ShellX hooks, after 1.5 s without output (at most 5 s). The pane stays open after the command ends.

## shellx focus

`shellx focus TARGET [--raise]` — select a tab (its workspace expands) or focus a pane (and select its tab). `--raise` also brings the ShellX window to the front; do not use it unless the user asked.

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx close

`shellx close TARGET [--force]` — close a pane, or a whole tab with `t<id>`. While a command runs it exits 6 `running_command` unless `--force` (no dialog opens). Close only what you created.

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx send

`shellx send PANE [--text TEXT | --stdin] [--key KEY]… [--enter]` — type into a terminal pane as the user would paste.

- Text goes through ShellX's paste: control characters are removed (an escape can never end bracketed paste early), newlines become carriage returns (multi-line text without bracketed paste runs line by line, as a manual paste would), and it is bracketed when the shell asked for it.
- `--key` (repeatable), after the text: `enter`, `tab`, `esc`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `ctrl-a` … `ctrl-z`, `ctrl-\`, `ctrl-]`.
- `--enter` presses Enter last.
- At most 48 KiB of text. A pane that exited → exit 1 `exited`; a browser pane → exit 2.

JSON: `{}`. Exit codes: 0, 1, 2, 3, 4, 6, 7.

## shellx read

`shellx read PANE [--lines N] [--ansi]` — print a pane's text.

- Without `--lines`: the current screen of the active buffer (the alternate screen while vim/less runs).
- `--lines N` (1–10000): the last N logical lines (wrapped rows joined) of the active buffer, scrollback included. Trailing blank lines are dropped.
- `--ansi`: keeps colours as SGR escapes only — re-encoded from the cells, never the raw program output (no titles, clipboard or mouse sequences).
- Output over 48 KiB comes in pages; `shellx` fetches them all. Text read while output arrives may be off by a line between pages; read again if needed.
- JSON: `{"text":"…"}`.

Exit codes: 0, 2, 3, 4, 6, 7.

## shellx rename

`shellx rename TAB NAME...` — rename a tab (trimmed, at most 64 characters; an empty name `""` restores the automatic title). A bare number is a tab.

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx workspace new

`shellx workspace new [NAME] [--focus]` — create a workspace ("Workspace N" without a name) with one tab; prints `w:<id>`. The current workspace and selection stay unless `--focus`.

JSON: `{"workspace":"w:abc","tab":"t105"}`. Exit codes: 0, 1, 3, 6, 7.

## shellx workspace rename

`shellx workspace rename WORKSPACE NAME...` — rename a workspace (`w:<id>` or its name; a blank name exits 2).

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx workspace move

`shellx workspace move TAB WORKSPACE` — move a tab to the end of a workspace. A bare number is a tab.

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx notify

`shellx notify [--title TITLE] [--pane PANE] TEXT...` — notify the user. The route, in order:

1. `--pane` or `$SHELLX_PANE_ID` set: the notice belongs to that pane — tab badge and notification panel in ShellX, and a push to the paired phone (at most 30 per minute per pane).
2. No pane, but this terminal window is shared with the phone (`$SHELLX_TERM` is this terminal): written as an OSC 777 notification to the terminal (push).
3. Otherwise: a ShellX system notification and a "Command line" entry in the notification panel (no push). This works from any terminal, even without "Allow other terminals".

If ShellX is not running but you are in a ShellX pane with a terminal, it falls back to OSC 777 and exits 0. Body at most 1024 characters, title 128; control characters are removed.

JSON: `{}`. Exit codes: 0, 2, 3, 4 (no such pane), 6, 7.

## shellx wait

`shellx wait PANE (--idle [--quiet MS] | --exit | --match REGEX [--from-now]) [--timeout SECONDS]` — block until the pane reaches a state. Exactly one mode. Default timeout 30 s, at most 3600 s; timing out exits 5.

- `--idle`: a shell with ShellX hooks is back at its prompt (no command running) and quiet for `--quiet` ms (default 500); a shell without hooks: quiet for 2 s. Prints nothing.
- `--exit`: the shell ended; prints its exit code (`shellx` itself exits 0). Works right after the pane closed.
- `--match REGEX`: JavaScript/Dart regular expression syntax, multi-line mode (`^`/`$` match at line ends), at most 1 KiB. It runs over the last 2000 logical lines (≤ 256 KiB) at the start and after each burst of output; `--from-now` only looks at text from the cursor onwards. Prints the matching line. An invalid pattern exits 2; each scan has a 1 s budget — a pattern that needs longer (catastrophic backtracking) fails with exit 2 "pattern is too slow".
- If the pane exits while waiting for `--idle`/`--match`: exit 1 `exited`.
- Ctrl+C ends the wait on both sides.
- JSON: `{}` (idle), `{"exitCode":0}` (exit), `{"match":"ready","line":"ready in 4 ms"}` (match).

Exit codes: 0, 1, 2, 3, 4, 5, 6, 7.

## shellx events

`shellx events [--follow | --for SECONDS] [--kinds LIST]` — print ShellX events as JSON lines (always JSON). Without `--follow`/`--for` it only subscribes and exits (a check). `--kinds tab.opened,notice` filters. Exits 3 when ShellX closes the stream.

| kind | fields | when |
|---|---|---|
| `tab.opened` | `tab`, `workspace` | a tab opened; the first pane of a new tab is reported only here (its pane id is the tab id) |
| `tab.closed` | `tab` | |
| `tab.renamed` | `tab`, `title` | only when the custom title changes; automatic titles arrive as `pane.changed` |
| `tab.selected` | `tab` | |
| `tab.moved` | `tab`, `workspace` | |
| `pane.opened` | `pane`, `tab` | a split |
| `pane.exited` | `pane`, `tab`, `exitCode` | the shell ended; comes **before** `pane.closed`. A pane closed from the phone or by its session may report a signal code (e.g. -15); a close from the window or `shellx close` reports only `pane.closed` |
| `pane.closed` | `pane`, `tab` | |
| `pane.focused` | `pane`, `tab` | |
| `pane.changed` | `pane`, `tab`, `title`, `cwd`, `branch`, `ports`, `running` | at most one per pane per 250 ms, only when something changed |
| `workspace.created` / `workspace.renamed` / `workspace.deleted` | `workspace` (+ `name`) | |
| `notice` | `pane`, `tab`, `type`, `title?`, `body?` | a notification; `type` is the notice kind (`kind` is the event kind) |
| `overflow` | `dropped` | you read too slowly and `dropped` events were lost — call `shellx ls` to resync |

Ids are written as `p…`, `t…`, `w:…`. At most 4 listeners at once.

Exit codes: 3 (stream closed), 6, 7.

## Browser panes

`shellx browser …` needs a ShellX with browser panes. A ShellX without them exits 7 "this ShellX has no browser panes yet". On pages that are not localhost, `eval`, `screenshot`, `console` and `network` (and the helpers built on `eval`) are refused with exit 6 `forbidden_origin` unless the user enabled "Allow agents to control every page".

## shellx browser ls

`shellx browser ls` — list browser panes: `p-<n>  t<id>  title  url`. JSON: `{"panes":[{"pane":"p-1","tab":"t100","title":"…","url":"…"}]}`. Exit codes: 0, 3, 6, 7.

## shellx browser open

`shellx browser open URL [--tab TAB | --pane PANE] [--down] [--focus]` — open a browser pane by splitting a tab (default the selected tab) or a pane; prints `p-<n>`. Exit codes: 0, 1, 2, 3, 4, 6, 7.

## shellx browser nav

`shellx browser nav PANE URL [--no-wait] [--timeout SECONDS]` — navigate; waits for the load (≤ 60 s) unless `--no-wait`. Exit codes: 0, 1 (`load_failed`), 2, 3, 4, 5, 6, 7.

## shellx browser back

`shellx browser back PANE` — go back. Exit codes: 0, 3, 4, 6, 7.

## shellx browser forward

`shellx browser forward PANE` — go forward. Exit codes: 0, 3, 4, 6, 7.

## shellx browser reload

`shellx browser reload PANE` — reload. Exit codes: 0, 3, 4, 6, 7.

## shellx browser stop

`shellx browser stop PANE` — stop loading. Exit codes: 0, 3, 4, 6, 7.

## shellx browser close

`shellx browser close PANE` — close a browser pane you opened. Exit codes: 0, 3, 4, 6, 7.

## shellx browser wait

`shellx browser wait PANE [--timeout SECONDS]` — wait until the page has loaded (≤ 60 s). Exit codes: 0, 1, 3, 4, 5, 6, 7.

## shellx browser eval

`shellx browser eval PANE (--script JS | --file FILE | --file -) [--timeout SECONDS]` — run an async function body in the page; `return` a JSON value. Prints the JSON result (e.g. `"Directory listing for /"`). At most 32 KiB, timeout ≤ 30 s. A script error exits 1 `eval_error`. Exit codes: 0, 1, 2, 3, 4, 5, 6, 7.

## shellx browser screenshot

`shellx browser screenshot PANE [--out FILE]` — capture the visible page; prints the PNG path (or FILE after copying it there). JSON: `{"path":"…",…}`. Exit codes: 0, 1, 3, 4, 6, 7.

## shellx browser console

`shellx browser console PANE [--since SEQ] [--level LEVEL] [--limit N]` — console entries: `seq  level  text`. Pass the last `seq` as `--since` to get only new ones. JSON: `{"entries":[{"seq":1,"level":"error","text":"…"}],…}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx browser network

`shellx browser network PANE [--since SEQ] [--limit N]` — network entries (best effort): `seq  method status  url`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx browser query

`shellx browser query PANE SELECTOR [--limit N]` — tag, text (≤ 500 characters), value and href of up to N (default 50, max 200) matching elements, as JSON. Built on `eval` (same origin rule). Exit codes: as `eval`.

## shellx browser click

`shellx browser click PANE SELECTOR` — scroll the first match into view and click it; no match exits 1 `eval_error`. Exit codes: as `eval`.

## shellx browser fill

`shellx browser fill PANE SELECTOR TEXT...` — set the first match's value and fire `input` and `change`. Frameworks that track values through their own setters (React) may not notice; use `eval` then. Exit codes: as `eval`.

## shellx skills install

`shellx skills install [--claude] [--codex] [--dir DIR] [--force]` — install this skill (`SKILL.md`, `reference.md`) into `~/.claude/skills/shellx/` (Claude Code), `~/.agents/skills/shellx/` (Codex) or `DIR/shellx/`. Without flags: every agent whose folder exists (`~/.claude`; `~/.codex` or `~/.agents`). A file you changed is not overwritten without asking ("Overwrite …? [y/N]"); without a terminal to ask, it exits 6 unless `--force`. An identical file is "up to date". Never connects to ShellX. Exit codes: 0, 1, 6.

## shellx skills print

`shellx skills print [SKILL.md | reference]` — print the embedded skill file. Exit codes: 0, 2.

## shellx help

`shellx help [COMMAND...]` — help for a command or a command group (`shellx help browser`). `shellx --version` prints `shellx <version> (api 1)`.

## shellx completions

`shellx completions zsh|bash|pwsh` — print a completion script (e.g. `shellx completions zsh > ~/.zfunc/_shellx`). Pane and tab arguments complete from `shellx ls --ids`.
