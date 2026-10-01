# shellx-term

Wraps an interactive shell in a PTY so ShellX can share that terminal window
with a paired phone. Design: `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md`.

    cargo test --features test-hooks        # unit + integration tests (real PTYs, /bin/sh)
    cargo build --release                   # target/release/shellx-term

`shell/block.zsh` and `shell/block.bash` are the canonical startup-file blocks.
`scripts/` holds development helpers; the ShellX app installs everything for real.
