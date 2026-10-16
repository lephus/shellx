# xterm 4.0.0 — ShellX copy

Vendored from pub.dev `xterm` 4.0.0 (https://github.com/TerminalStudio/xterm.dart,
MIT, see `LICENSE`). `apps/desktop` and `apps/mobile` depend on it by path. The first
commit that added this directory is the pristine package (`lib/`, licence, readme,
changelog; tests, examples and media left out); every later change is listed here and
marked with `ShellX:` comments.

## `lib/src/ui/render.dart`

| Change | Why |
|---|---|
| `RenderTerminal.debugScrollHook`: an optional static callback, null by default (no effect in normal use), invoked at the end of `performLayout` with the scroll state (offset, max extent, viewport, buffer line count, alt-buffer, stick-to-bottom). | Diagnose "the terminal won't scroll" on a real device without reproducing in widget tests: the desktop app wires it to a file when started with `SHELLX_SCROLL_TRACE=<file>`. |

## `lib/src/ui/custom_text_edit.dart`

| Change | Why |
|---|---|
| On macOS, and on mobile (with `deleteDetection`), the platform document keeps the word being typed (trailing letters, marks and digits, at most 32 characters) instead of being reset to empty after every character. An edit of that word reaches the terminal as one Backspace per replaced character plus the new text. A key the terminal handles itself updates it (Backspace takes one character off, anything else ends the word); a new or closed connection empties it. On mobile the word sits behind the two `deleteDetection` guard spaces, so a soft-keyboard Backspace at an empty word is still detected. | macOS and mobile Vietnamese Telex/VNI edit typed text in place rather than composing it: after "chao", "f" replaces "chao" with "chào". With an empty document there was nothing to edit and the raw "f" was typed. Windows keeps upstream behaviour. |
