# shellx-term

Wraps an interactive shell in a PTY so ShellX can share that terminal window
with a paired phone. Design: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`.

    cargo test --features test-hooks        # unit + integration tests (real PTYs, /bin/sh)
    cargo build --release                   # target/release/shellx-term

`shell/block.zsh`, `shell/block.bash` and `shell/block.ps1` are the canonical startup-file blocks.
Their inner-shell branch (the shell `shellx-term` started) also installs the command hooks of push
notifications (OSC 633;E, 133;C, 133;D and a `shellx notify` function; push spec §4.5) — the same code
as the ShellX session hooks in `packages/shellx_agent/lib/src/pty/shell_hook_scripts.dart`, kept in
sync by `packages/shellx_agent/test/pty/shell_hook_sync_test.dart`.
`scripts/` holds development helpers; the ShellX app installs everything for real.
