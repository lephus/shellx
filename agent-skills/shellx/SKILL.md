---
name: shellx
description: Drive the ShellX terminal from the command line — split a pane to run a dev server, read its output, wait for a pattern, open a browser pane on localhost and inspect it, and notify the user. Use when $SHELLX is set (you run inside a ShellX pane) or the user asks to use ShellX panes, tabs or its browser.
---

# ShellX command line

You are inside ShellX when `$SHELLX` is `1`. `$SHELLX_PANE_ID` is your pane, `$SHELLX_TAB_ID` your tab. The `shellx` command talks to the ShellX window over a private local socket.

## Rules

- Never take the user's focus: do not pass `--focus` or `--raise` unless the user asked.
- Never close panes or tabs you did not create. Keep the ids you create and close only those.
- Use `--json` whenever you parse output. Ids look like `p123` (pane), `t123` (tab), `w:abc` (workspace), `p-2` (browser pane).
- `send` types like a paste. Prefer `--cmd` on `split`/`new-tab` to start a program.
- Tabs you open with `new-tab` (without `--workspace`) land in your own workspace, the one your pane is in. When something does not work, `shellx doctor` checks the setup (is ShellX running, is `shellx` in the PATH, are the skills installed, is the configuration valid).
- Exit 3 means ShellX is not running. Do not start it yourself; tell the user.
- Exit 6 with `cli_disabled`: tell the user to tick "Allow controlling ShellX from the command line" in the ShellX tray menu (Command line).
- Exit 6 with `forbidden` when you run outside a ShellX pane (no `$SHELLX_CLI_TOKEN`): only shells ShellX opened may control it. Ask the user to tick "Allow other terminals" in the ShellX tray menu (Command line), or run the command from a ShellX pane.
- To change ShellX itself (shortcuts, fonts, themes, palette commands) use the shellx-config skill.
- `shellx browser …` needs a ShellX with browser panes; exit 7 means browser panes are not available in this ShellX.

## Recipes

Run a dev server next to you and wait until it is ready:

```bash
p=$(shellx split --right --cmd "npm run dev")
shellx wait "$p" --match 'ready|listening|Local:' --timeout 60
shellx read "$p" --lines 40
```

Run a command in a pane and wait for it to finish:

```bash
shellx send "$p" --text "npm test" --enter
shellx wait "$p" --idle --timeout 600
shellx read "$p" --lines 200
```

Open the app in a browser pane and check it:

```bash
b=$(shellx browser open http://localhost:5173 --pane "$p")
shellx browser wait "$b"
shellx browser eval "$b" --script 'return document.title'
shellx browser query "$b" 'h1'
shellx browser console "$b" --level error
shellx browser screenshot "$b" --out /tmp/page.png
```

Tell the user you are done (shows on their computer and phone):

```bash
shellx notify --title "Claude" "Tests pass — ready for review"
```

Describe or mark your tab for the user (no focus change): `shellx tab describe @tab "fixing login"`, `shellx tab status @tab review` (`none`, `in_progress`, `review`, `blocked`, `done`; `describe @tab ""` clears it).

See everything that is open: `shellx ls` (or `shellx ls --json`). Follow what happens: `shellx events --follow` (one JSON object per line). Full reference: `shellx skills print reference`.

## Exit codes

0 ok · 1 error · 2 usage · 3 ShellX not running · 4 not found · 5 timeout · 6 refused · 7 ShellX too old (or no browser panes) · 8 ShellX window closed
