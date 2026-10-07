---
name: shellx-config
description: Change ShellX for the user — fonts, colours and themes, cursor, padding, scrollback, Option-as-Alt, close confirmation, new-tab folder, keyboard shortcuts (Ghostty keybind syntax) and command-palette commands — by editing ShellX's plain-text config file and reloading it. Use when the user asks to change a ShellX shortcut, font, theme or behaviour, or to add a command to ShellX's command palette.
---

# Configuring ShellX

ShellX reads one plain-text file in Ghostty syntax: `key = value`, `#` starts a comment line. It also takes fonts and colours from the user's Ghostty config unless the file says `ghostty-config = false`.

## Steps

1. Find the file: `shellx config path` (add `--ghostty` to also list the Ghostty files ShellX reads). It works without ShellX running. The file may not exist yet: create it and its folder.
2. See what is in effect and where each value comes from: `shellx config show`. Every key at its default, as a commented file: `shellx config show --defaults`.
3. Edit by appending lines, or changing lines the user agreed to change. Later lines win; `keybind`, `command`, `snippet`, `palette` and `font-family` add up; `key =` (empty) resets a key.
4. **Never edit between** `# >>> shellx-managed keybinds >>>` and `# <<< shellx-managed keybinds <<<`. ShellX's shortcut editor owns that block. Put your lines above it. If the user wants a chord the block also sets, tell them to change it in ShellX (Command palette, "Keyboard shortcuts").
5. Check, then apply: `shellx config check` (exit 1 = errors; each problem is printed as `file:line: severity: message`), fix what you introduced, then `shellx config reload`. ShellX also reloads by itself about a second after a save.
6. Tell the user what you changed and how to undo it (delete the line).

`check`, `reload` and `show` talk to the running ShellX (exit 3: it is not running, tell the user; do not start it). Exit 6 with `cli_disabled`: ask the user to tick "Allow controlling ShellX from the command line" in the ShellX tray menu. Exit 6 with `forbidden` from outside a ShellX pane: ask them to tick "Allow other terminals" there, or run the command from a ShellX pane.

## Keys

| Key | Values | Default |
|---|---|---|
| `font-family` | a font name; repeat for fallbacks | JetBrains Mono |
| `font-size` | 9 to 28 | 13 (or the size set with Cmd/Ctrl +/-) |
| `theme` | a name (file in `themes/` next to the config, or a Ghostty theme), a path, or `light:A,dark:B` | ShellX |
| `background`, `foreground`, `cursor-color`, `selection-background` | `#RRGGBB` | ShellX colours |
| `palette` | `N=#RRGGBB`, N 0 to 15 | ShellX colours |
| `cursor-style` | `block`, `bar`, `underline` | `block` |
| `scrollback-limit` | 1000 to 100000 lines (new panes) | 10000 |
| `window-padding-x`, `window-padding-y` | `N` or `A,B`, 0 to 64 | 10 / 6 |
| `macos-option-as-alt` | `false`, `true`, `left`, `right` | `false` |
| `confirm-close-surface` | `true` (ask while a command runs), `false`, `always` | `true` |
| `working-directory` | `home`, `inherit`, an absolute path (new tabs, also from `shellx new-tab`) | `home` |
| `keybind` | `trigger=action` (below) | ShellX's shortcuts |
| `command`, `snippet` | `Name = text` (below) | none |
| `ghostty-config` | `true`, `false` | `true` |
| `config-file` | another file to read (relative, `~/`, `?` prefix = optional) | none |

## Keyboard shortcuts

`keybind = <trigger>=<action>`. Modifiers: `ctrl`, `alt` (`opt`), `shift`, `super` (`cmd`), joined with `+`. Keys: a letter or digit, or a name: `enter`, `tab`, `escape`, `space`, `backspace`, `delete`, `insert`, `home`, `end`, `page_up`, `page_down`, `left`, `right`, `up`, `down`, `f1` to `f24`, `comma`, `period`, `plus`, `minus`, `equal`, `slash`, `backslash`, `semicolon`, `quote`, `backquote`, `bracket_left`, `bracket_right`. Two steps: `ctrl+a>c=new_tab`. `keybind = <trigger>=unbind` frees a chord; `keybind = clear` drops every default.

ShellX refuses (and `shellx config check` reports): plain keys without ctrl, alt or super (except F1 to F24), F6 and Shift+F6, and chords the system owns (for example Cmd+Q, Cmd+Tab, Cmd+Space on macOS; Alt+F4, Alt+Tab and anything with the Windows key on Windows). Avoid chords a shell needs (Ctrl+C, Ctrl+D, Ctrl+R, Ctrl+A) unless the user asks.

Actions: `new_tab`, `close_surface` (the pane, or the tab when it has one pane), `close_tab`, `new_workspace`, `ssh_connect` (Connect to a server; Cmd+Shift+K / Ctrl+Shift+K by default), `tmux_attach` (Attach a tmux session; no default chord), `goto_tab:1` to `goto_tab:9`, `next_tab`, `previous_tab`, `new_split:right|down`, `goto_split:left|right|up|down`, `resize_split:left|right|up|down`, `toggle_split_zoom`, `equalize_splits`, `toggle_notifications`, `jump_to_unread`, `copy_to_clipboard`, `paste_from_clipboard`, `select_all`, `start_search` (Find in terminal; Cmd+F / Ctrl+Shift+F), `navigate_search:next|previous` (Cmd+G, Cmd+Shift+G / Ctrl+Shift+G, Ctrl+Shift+Alt+G), `end_search`, `increase_font_size:N`, `decrease_font_size:N` (N 0.5 to 8), `reset_font_size`, `next_region`, `previous_region`, `reload_config`, `open_config`, `toggle_command_palette`, `show_shortcuts`, `show_config_problems`, `run_command:<Name>`, `text:<string>`, `csi:<string>`, `esc:<string>`, `ignore`, `unbind`.

## Commands and snippets

`command = Lint = npm run lint` appears in ShellX's command palette and runs in the focused pane (pasted, then Enter). `snippet = Name = text` pastes without Enter. Quote the text to use escapes: `snippet = Status = "git status\n"`. Give one a key: `keybind = super+shift+l=run_command:Lint`.

## Etiquette

- Ask before changing a line the user wrote; prefer appending.
- Keep defaults unless asked.
- Never leave errors: run `shellx config check` after every edit.
