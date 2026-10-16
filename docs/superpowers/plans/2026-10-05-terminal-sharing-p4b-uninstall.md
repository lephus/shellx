# P4b: `shellx-term uninstall` + FAQ entry

Goal (spec §5.1, §10.2, §10.6): `shellx-term uninstall` removes the ShellX block
(`# >>> ShellX >>>` .. `# <<< ShellX <<<`) from every config file and deletes the
bin directory; idempotent; preserves everything else byte-exactly (UTF-8, UTF-8
BOM, UTF-16 LE/BE, LF/CRLF); prints a summary; exit 0 (also when nothing
installed), 1 on I/O errors.

Files
- term/src/uninstall.rs (new): `remove_block(bytes) -> Option<Vec<u8>>`, `run(&Env) -> Report`.
- term/src/cli.rs: `Command::Uninstall` (`uninstall`, no extra args).
- term/src/main.rs: wire on unix and windows.
- term/tests/uninstall.rs: binary run with a temp HOME.
- web/src/i18n/ui.ts + Home.astro: FAQ entry 6 (vi, en).

Tasks
1. Tests + `remove_block` (encodings, line endings, idempotence, unterminated block untouched, several blocks).
2. `run`: file list per platform, bin dir removal, report; unit tests on temp dirs.
3. CLI parse + main wiring + integration test.
4. FAQ entry; web build/tests.
