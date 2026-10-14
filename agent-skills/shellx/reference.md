# ShellX command line — reference

Every command: `shellx <command> [args] [--json] [--socket ADDRESS] [--help]`.

- `--json` prints exactly one JSON object on stdout (events: one object per line). Errors with `--json` are also printed on **stdout** as `{"error":{"code":"…","message":"…"}}`; without `--json` they go to stderr as `shellx: <message> (<code>)`.
- Commands that create something print only the new id (for `$(…)`); other commands print nothing on success unless they read something.
- Text that comes from ShellX or a page (titles, names, console lines, error messages) is printed without control characters; `read` prints the terminal's text as it is.
- `--socket ADDRESS` overrides `$SHELLX_SOCKET` and the endpoint file's address (tests only).

## Targets

| Form | Means |
|---|---|
| `p<id>` | a terminal pane, e.g. `p1712` |
| `p-<n>` | a browser pane, e.g. `p-2` |
| `t<id>` | a tab, e.g. `t1712` (the first pane of a tab has the tab's id); where a pane is needed, the tab's focused pane |
| `w:<id>` or a name | a workspace (names ignore case; two with the same name → `ambiguous`, use `w:<id>`) |
| `@self` | your pane (`$SHELLX_PANE_ID`); for tab commands, your tab |
| `@tab` | your tab (`$SHELLX_TAB_ID`) |
| `@focused` | the focused pane of the selected tab (or that tab) |
| bare number | a pane, except for `rename` and `workspace move`, where it is a tab |

Ids are written without leading zeros (`p12`, not `p012`). `focus` and `close` take a pane or a tab, so use the prefix (a bare number is a pane). `@self`/`@tab` outside a ShellX pane exit 2. Commands that need a pane (`send`, `read`, `wait`, `split --pane`) take a tab `t<id>` as that tab's focused pane; `@tab` there exits 2, and `notify --pane` takes only a pane id or `@self`. Targets are accepted the same way by every command.

## Who may control ShellX

- Shells that ShellX opened carry `$SHELLX_CLI_TOKEN`; their `shellx` may use every command.
- Any other terminal (Terminal.app, iTerm, a cron job…) gets exit 6 `forbidden` for everything except `notify` without a pane, until the user ticks **"Allow other terminals"** in the ShellX tray menu (Command line). Ask the user to do it; never try to work around it.
- A shell left from an earlier ShellX launch (for example inside tmux) carries an old token: it gets exit 6 "This shell belongs to an earlier ShellX launch; open a new tab". Open a new ShellX tab.
- At most two such terminals (outside ShellX, not allowed) may be connected at once; more exit 1 `busy`.
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
| 1 | other error | `exited`, `no_room`, `session_limit`, `spawn_failed`, `busy`, `eval_error`, `load_failed`, `internal`, `not_installed`, `io`, `ssh_unavailable`, `tmux_unavailable`, `tmux_failed`, `config_errors` (`config check` or `reload` found errors) |
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
  "tabs":[{"id":"t1712","kind":"terminal","title":"vim","custom":false,"selected":true,"unread":2,"running":true,"agent":false,
    "panes":[{"id":"p1712","kind":"terminal","title":"vim","cwd":"/Users/me/app","branch":"main","ports":[3000],
              "running":true,"exited":false,"exitCode":null,"focused":true,"zoomed":false,"phone":false,"driver":"desktop","agent":false}]}]}],
 "selectedTab":"t1712","focusedPane":"p1712"}
```

A tab has `"kind"`: `"terminal"`, or `"ai"` for an AI tab (a conversation with an agent, not a shell). An AI tab also has `"cwd"`, the folder its agent works in (`null` until one is chosen). Its `panes` list only terminal panes: none until a terminal is opened under the AI pane, and a command that needs a pane (`send`, `read`, `wait`…) answers `not_found` for such a tab. `focusedPane` is `null` while the AI pane has the focus. In the text tree an AI tab is a tab line with no pane lines. An older ShellX leaves `"kind"` out: read it as `"terminal"`.

A pane whose agent reported through its hooks (`shellx integrations`) also has `"agent_name"` (`claude`, `codex`, `gemini`, `opencode`) and `"agent_status"` (`running`, `needs_input`, `idle`, `done`); `"agent"` stays the "a command-line client just acted here" flag. `cwd`, `branch` and `exitCode` may be `null` (unknown / still running); `selectedTab` and `focusedPane` are `null` when no tab is open. Browser panes (when available) have `"kind":"browser"` and `url`.

Exit codes: 0, 3, 6, 7.

## shellx new-tab

`shellx new-tab [--workspace W] [--cwd DIR] [--cmd COMMAND] [--focus]` — open a tab; prints `t<id>`.

- `--workspace`: workspace id (`w:<id>`) or name. Without it, a command run inside a ShellX pane opens the tab in the workspace that pane is in *now* (a tab you dragged to another workspace counts; the pane is looked up by `$SHELLX_PANE_ID`, so it follows a pane moved to another tab), else that of `$SHELLX_TAB_ID`; from a script outside ShellX: the user's current workspace.
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

## shellx tab describe

`shellx tab describe TAB TEXT...` — set the one-line description shown under a tab in the sidebar (cut to 120 characters, control characters removed; an empty text `""` clears it). `TAB` is `tN`, `@tab` or `@self`. Does not change focus; the text never appears in `ls`.

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx tab status

`shellx tab status TAB STATE` — mark a tab's progress: `none`, `in_progress`, `review`, `blocked` or `done` (anything else exits 2). Does not change focus.

JSON: `{}`. Exit codes: 0, 2, 3, 4, 6, 7.

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

If ShellX is not running but you are in a ShellX pane (`$SHELLX_PANE_ID` set) with a terminal, it falls back to OSC 777 and exits 0. `--pane` takes a pane id (`p<id>`) or `@self`; `@focused` is refused (exit 2). Body at most 1024 characters, title 128; control characters are removed.

JSON: `{}`. Exit codes: 0, 2, 3, 4 (no such pane), 6, 7.

## shellx agent-event

`shellx agent-event AGENT EVENT [PAYLOAD] [--session ID] [--message TEXT]` — used by agent hooks (Claude Code, Codex, Gemini CLI, OpenCode), not by agents themselves: it tells ShellX that an agent in this pane started, is running, needs input, is idle or ended. It always exits 0, prints nothing (one line on stderr when run from a terminal) and does nothing outside a ShellX pane or when ShellX is not running or too old. The `ok` flag it may send (a failed turn) is accepted but not used for anything yet. It reads at most 64 KiB of hook JSON from stdin and sends only the event, the session id and a notification's text.

## shellx integrations

For the person, not for agents: do not run `install` or `uninstall` on your own. They edit an AI agent's own configuration file so that its hooks tell ShellX what the agent is doing (see `shellx agent-event`). Agents: `claude`, `codex`, `gemini`, `opencode`.

- `shellx integrations status [AGENT]` — one line per agent: installed, not installed, or its program is not on `PATH`. `--json`: `{"agents":[{"agent","installed","path","found"}]}`.
- `shellx integrations install AGENT [--yes] [--dry-run] [--print]` — prints the exact change (values of keys that look like secrets are hidden), asks `[y/N]` on the terminal and writes only after `y` or `--yes`. Without a terminal `--yes` is required (exit 2). `--dry-run` prints the change and writes nothing; `--print` prints what to add by hand. The old file is copied once to `<file>.shellx-bak`; the write is atomic, keeps the file's permissions and follows a symlink to its target. A file that changed while waiting is not written. Installing twice changes nothing. A file with comments, invalid JSON or an unexpected shape is refused (exit 1); Codex's `config.toml` is refused when it already sets its own `notify` (Codex allows only one; use `--print` and call `shellx agent-event codex turn-complete` from your own script). `--json`: `{"changed":bool,"backup":bool}`, no file content.
- `shellx integrations uninstall AGENT [--yes] [--dry-run]` — removes only the entries ShellX added (the ones running `shellx agent-event`); a file ShellX created and that is empty afterwards is deleted. OpenCode's plugin (`plugins/shellx-agent.js`) is a file ShellX owns outright: install refuses to replace a plugin file of the same name that is not ShellX's, and uninstall refuses (even with `--yes`) to delete one that was edited.

Exit codes: 0 (also "No changes made." and "Already installed."), 1 (refused, or the write failed), 2.

## shellx wait

`shellx wait PANE (--idle [--quiet MS] | --exit | --match REGEX [--from-now]) [--timeout SECONDS]` — block until the pane reaches a state. Exactly one mode. Default timeout 30 s, at most 3600 s; timing out exits 5.

- `--idle`: a shell with ShellX hooks is back at its prompt (no command running) and quiet for `--quiet` ms (default 500); a shell without hooks: quiet for 2 s. Prints nothing.
- `--exit`: the shell ended; prints its exit code (`shellx` itself exits 0). Works right after the pane closed. A pane closed (by the user or `shellx close`) before its shell ended has no code: it prints `closed` (JSON `{"exitCode":null,"closed":true}`).
- `--match REGEX`: JavaScript/Dart regular expression syntax, multi-line mode (`^`/`$` match at line ends), at most 1 KiB. It runs over the last 2000 logical lines (≤ 256 KiB) at the start and after each burst of output; `--from-now` only looks at text from the cursor onwards. Prints the matching line. `line` and `match` are at most 4096 characters each: a longer line is cut to a window around the match, a longer match keeps its start, and the answer then has `"clipped":true`. An invalid pattern exits 2; each scan has a 1 s budget — a pattern that needs longer (catastrophic backtracking) fails with exit 2 "pattern is too slow".
- If the pane exits while waiting for `--idle`/`--match`: exit 1 `exited`.
- Ctrl+C ends the wait on both sides.
- JSON: `{}` (idle), `{"exitCode":0}` (exit), `{"match":"ready","line":"ready in 4 ms"}` (match; plus `"clipped":true` when cut).

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
| `pane.moved` | `pane`, `from`, `to` | a pane moved to another tab (menu or palette); its shell keeps running, its id stays; `$SHELLX_TAB_ID` in that shell still names the old tab |
| `pane.focused` | `pane`, `tab` | |
| `pane.changed` | `pane`, `tab`, `title`, `cwd`, `branch`, `ports`, `running` | at most one per pane per 250 ms, only when something changed |
| `workspace.created` / `workspace.renamed` / `workspace.deleted` | `workspace` (+ `name`) | |
| `notice` | `pane`, `tab`, `type`, `title?`, `body?` | a notification; `type` is the notice kind (`kind` is the event kind) |
| `agent.status` | `pane`, `tab`, `agent`, `status` | what an agent shows in this pane changed (one event per pane, not per tab): `status` is `running`, `needs_input`, `idle`, `done`, or `none` (the agent ended or its pane went) |
| `overflow` | `dropped` | you read too slowly and `dropped` events were lost — call `shellx ls` to resync |

Ids are written as `p…`, `t…`, `w:…`. At most 4 listeners at once.

Exit codes: 0 (subscribed without `--follow`/`--for`, the `--for` time is up, or the reader of its output went away, e.g. `| head -1` — it notices within about a second, even when no event comes; on Windows only at its next event), 1 (output cannot be written), 3 (ShellX closed the stream), 6, 7.

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

`shellx browser eval PANE (--script JS | --file FILE | --file -) [--timeout SECONDS]` — run an async function body in the page; `return` a JSON value. Prints the JSON result (e.g. `"Directory listing for /"`); with `--json`: `{"json":<result>}`. At most 32 KiB, timeout ≤ 30 s. A script error exits 1 `eval_error`. Exit codes: 0, 1, 2, 3, 4, 5, 6, 7.

## shellx browser screenshot

`shellx browser screenshot PANE [--out FILE]` — capture the visible page; prints the PNG path (or FILE after copying it there). JSON: `{"path":"…",…}`. Exit codes: 0, 1, 3, 4, 6, 7.

## shellx browser console

`shellx browser console PANE [--since SEQ] [--level LEVEL] [--limit N]` — console entries: `seq  level  text`. Pass the last `seq` as `--since` to get only new ones. JSON: `{"entries":[{"seq":1,"level":"error","text":"…"}],…}`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx browser network

`shellx browser network PANE [--since SEQ] [--limit N]` — network entries (best effort): `seq  method status  url`. Exit codes: 0, 2, 3, 4, 6, 7.

## shellx browser query

`shellx browser query PANE SELECTOR [--limit N]` — tag, text (≤ 500 characters), value and href of up to N (default 50, max 200) matching elements, as JSON. Built on `eval` (same origin rule). Exit codes: as `eval`.

## shellx browser click

`shellx browser click PANE SELECTOR` — scroll the first match into view and click it; no match exits 1 `eval_error`. Prints nothing (`--json`: `{"json":true}`). Exit codes: as `eval`.

## shellx browser fill

`shellx browser fill PANE SELECTOR TEXT...` — set the first match's value and fire `input` and `change`. Frameworks that track values through their own setters (React) may not notice; use `eval` then. Exit codes: as `eval`.

## SSH and tmux

Open a server in a tab, or attach a tmux session, from a script. `shellx` itself does not exist on the server; a ShellX SSH pane has `shellx notify` as a shell function there, so notifications from the server still work. Sign-in (password, key passphrase, host key question) happens in the pane: ShellX never sees or stores it. Limit: the hello that releases `--cmd` carries no per-pane secret, so a hostile server could fake it before sign-in and receive the `--cmd` text at its own password prompt (it already receives the password itself; the host key question is unaffected). Only use `--cmd` on servers you trust.

## shellx ssh

`shellx ssh SERVER [--workspace W] [--cwd DIR] [--cmd COMMAND] [--no-hook] [--focus] [--json]` — open a tab on a server over SSH; prints its id (`t41`; `--json`: `{"tab":"t41","pane":"p41"}`). `SERVER` is an `~/.ssh/config` alias or `user@host[:port]`. `--cwd` is a folder on the server (`/...` or `~/...`; never made absolute locally). `--cmd` is typed only after the server shell says hello (the ShellX hook runs there), never into a sign-in prompt; it needs the hook, so `--no-hook` with `--cmd` (or a server set to no hook) is refused (exit 2, `bad_request`: "--cmd needs the server hook"), and it is dropped when the pane ends or no hello comes within 60 s (at most 16 KiB). `--no-hook` skips installing the ShellX hook on the server. The tab opens in the server's SSH workspace (made on first use) unless `--workspace` is given, and the user's focus is left alone unless `--focus`. Exit codes: 0, 1 (`ssh_unavailable`: no ssh on this computer; `spawn_failed`, `session_limit`, `busy`), 2, 3, 6, 7.

## shellx tmux ls

`shellx tmux ls [--host SERVER] [--json]` — list tmux sessions on this computer or on `--host`. Text: `name<TAB>N windows` plus `<TAB>attached` when a client is attached; nothing for no sessions. `--json`: `{"sessions":[{"name","windows","attached","activity"?}]}` (`activity` in Unix seconds). A server that needs a password is not listed: connect once with `shellx ssh`. Exit codes: 0, 1 (`tmux_unavailable`, `tmux_failed`), 2, 3, 6, 7.

## shellx tmux attach

`shellx tmux attach NAME [--host SERVER] [--create] [--focus] [--json]` — attach a tmux session as a tab; prints its id like `shellx ssh`. `--create` makes the session when it does not exist. A tmux session name has no `:` or `.` and is at most 64 characters. Exit codes: 0, 1 (`tmux_unavailable`, `tmux_failed`, `spawn_failed`), 2, 3, 6, 7.

Recipes:

- Open a server tab next to the user and run tests: `t=$(shellx ssh devbox --cwd ~/app --cmd 'make test')`, then `shellx wait p${t#t} --match 'PASS|FAIL' --timeout 600`.
- Attach the team's tmux session: `shellx tmux ls --host devbox --json`, then `shellx tmux attach main --host devbox`.

A pane that is remote shows in `shellx ls` as `[ssh host]` or `[tmux host:name]` (plus its state while it is not connected); `--json` carries `"remote":{"kind","host"?,"tmux"?,"state"}`. When a lost connection is restored the pane gets a new id: the old id keeps working for later commands, and `shellx events` reports one `pane.replaced` with `{old, new, tab}` instead of a close and an open.

## shellx config path

`shellx config path [--ghostty]` — print the path of ShellX's configuration file (with `--ghostty`, then the Ghostty files ShellX reads, one per line). Local: ShellX need not run. `--json`: `{"shellx":"…","ghostty":["…"]}`. Exit codes: 0, 2.

## shellx config check

`shellx config check` — check the configuration files as they are now, without applying anything. Prints `file:line: severity: message` per problem (`file: severity: message` when it concerns the whole file), or `no problems`. Exit 1 when there are errors (warnings alone exit 0). `--json`: `{"problems":[{"file","line","severity","code","key"?,"message"}],"generation"}`. Exit codes: 0, 1, 3, 6, 7, 8.

## shellx config validate

`shellx config validate` — the same as `shellx config check`: same request, same output, same exit codes (0, 1, 3, 6, 7, 8).

## shellx config reload

`shellx config reload` — reload now, as Cmd/Ctrl+Shift+, does. Silent when there are no errors; otherwise the problems as in `check`, exit 1. `--json`: the same object as `check`. Exit codes: 0, 1, 3, 6, 7, 8.

## shellx config show

`shellx config show [--defaults]` — every key in effect, as `key = value  # file:line` (`# default` when no line sets it). `--defaults`: a commented file with every key at its default. `--json`: `{"values":[{"key","value","source"}],"files":{"shellx","ghostty":["…"]}}` or `{"template":"…"}`. Exit codes: 0, 3, 6, 7, 8 (7 also on a ShellX older than this command).

## shellx doctor

`shellx doctor [--json]` — check the setup, one line per check: `✓ …` or `✗ …`. ShellX is running; `shellx` and ShellX are the same version (only when ShellX says its version); `shellx` is in your PATH; the agent skills are installed (`~/.claude/skills/shellx`, or the Codex folders); and, when ShellX runs, `Configuration: N errors, M warnings` (warnings alone pass). A failed check ends with `N problem(s) found.` and exit 1. It never prints file contents, problem texts or folders. `--json`: `{"checks":[{"id","ok","message"}],"ok":bool}` with ids `app`, `version`, `path`, `skills`, `config`. A failed check is the answer, not an error: nothing goes to stderr. Exit codes: 0, 1.

## shellx skills install

`shellx skills install [--claude] [--codex] [--dir DIR] [--force]` — install this skill (`SKILL.md`, `reference.md`) and the `shellx-config` skill (`SKILL.md`) into `~/.claude/skills/` (Claude Code), `~/.agents/skills/` (Codex; also `~/.codex/skills/` when `~/.codex` exists, for Codex builds that read it) or `DIR/` (one folder per skill). Without flags: every agent whose folder exists (`~/.claude`; `~/.codex` or `~/.agents`). A file you changed is not overwritten without asking ("Overwrite …? [y/N]"); without a terminal to ask, it exits 6 unless `--force`. An identical file is "up to date". A changed file you decline (or cannot be asked about) is kept and skipped; the other files are still installed and the command exits 6 at the end. `--json`: `{"installed":[…],"upToDate":[…],"skipped":[…]}` plus `"error"` when something was skipped. Never connects to ShellX. Exit codes: 0, 1, 6.

## shellx skills print

`shellx skills print [SKILL.md | reference | config]` — print the embedded skill file (`--json`: `{"files":[{"name":"reference.md","text":"…"}]}`). Exit codes: 0, 2.

## shellx help

`shellx help [COMMAND...]` — help for a command or a command group (`shellx help browser`). `shellx --version` prints `shellx <version> (api 1)`.

## shellx completions

`shellx completions zsh|bash|pwsh` — print a completion script (e.g. `shellx completions zsh > ~/.zfunc/_shellx`). Pane and tab arguments complete from `shellx ls --ids`.
