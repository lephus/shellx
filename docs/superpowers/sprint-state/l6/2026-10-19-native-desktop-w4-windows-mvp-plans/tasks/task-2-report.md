# Task 2 report: shellx-model palette/strings/keys/paste

Status: DONE. Commit: see `git log` on shellx/l6-windows ("feat(shellx-model): §7.4 palette, vi/en strings, Windows Terminal key map, safe bracketed paste"). Not pushed.

Built: palette.rs, strings.rs (49 keys, exhaustive match per language, generated from the brief table), keys.rs (map_key, Dir re-exported from lib.rs), paste.rs (newline normalize, loop-strip markers, bracket; empty -> empty). lib.rs only gained `pub mod` lines and `pub use keys::Dir`.

TDD: RED = tests-only files plus lib.rs mods: 255 compile errors. GREEN first run: 24 pass, 2 fail, both my test mistakes (Str::ALL count I guessed 51, real 49; Ctrl+Alt+Shift+Left is AltGr -> Text per brief rule 3, test changed to ctrl+shift+left). Final: 26 passed, 0 failed; clippy -D warnings clean; cargo fmt applied.

Notes: Ctrl+Alt+C with selection is not Copy (AltGr -> Text). Alt+Shift+arrow falls to chord "alt+shift+left". Space without modifiers is Text. Lang::from_env_value trims whitespace before the "en" prefix check.
