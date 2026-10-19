### Task 7: Virtual PTY in `cmux-tui-core` (production port of the spike)

Runs in parallel with Tasks 3–6 (second implementer; disjoint files).

**Files:**
- Create: `cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs` (from `shellx/w0-bridge` @ `4e1ed7bc41`, `git show 4e1ed7bc41:cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs`)
- Modify: `cmux-tui/crates/cmux-tui-core/src/lib.rs` (`#[cfg(unix)] mod virtual_pty; // ShellX:`), `cmux-tui/crates/cmux-tui-core/src/surface.rs` (apply the spike's hunks at `:2437-2549`, `:2569-2579`, `:2699-2714` — `git show 4e1ed7bc41 -- cmux-tui/crates/cmux-tui-core/src/surface.rs`; re-anchor if lines moved; mark each hunk `// ShellX:`)

**Interfaces:**
- Consumes: frame protocol from the spike header (`[type u8][len u32 BE][payload]`; daemon→app `H` hello JSON, `I` input, `R` resize wish, `K` kill; app→daemon `A` ack JSON, `O` output, `S` real grid, `E` exit). Enabled by env `CMUX_SHELLX_BRIDGE_SOCKET`.
- Produces (for Task 11): hello JSON `{"protocol":1,"cols","rows","cwd"}`; ack JSON `{"surface_id","workspace_id","mode":"attach"|"create"}`; frame size cap 16 MiB; after `open`, an app `S` frame always resizes the mirror (the forced echo); `E` or EOF ends the child; `K` is sent by `ChildKiller::kill`.
- Changes vs spike: (a) before `connect`, refuse a socket whose parent dir is a symlink, not owned by euid, or has any `0o077` bit (error contains `"shellx bridge: insecure socket directory"`); (b) hello carries `"protocol":1`; (c) replace `eprintln!` traces with the logging used next to `surface.rs:2699` (or drop them); never log payload bytes; (d) header comment: "ShellX file in an upstream crate; see docs/superpowers/plans/2026-10-19-native-desktop-w2-mac-remote.md Task 7".

- [ ] **Step 1: Write the failing tests** (in `virtual_pty.rs` `mod tests`, using the spike's fake-app pattern; each test makes its socket dir `0700`)

```rust
#[test] fn virtual_pty_round_trips_output_input_and_sizes() { /* spike test, kept */ }
#[test] fn virtual_pty_forwards_vietnamese_utf8_unchanged() {        // Review Focus 4
    writer.write_all("tiếng Việt\r".as_bytes()).unwrap();
    assert_eq!(app_received_input(), vec![0x74,0x69,0xe1,0xba,0xbf,0x6e,0x67,0x20,0x56,0x69,0xe1,0xbb,0x87,0x74,0x0d]);
}
#[test] fn split_utf8_output_reaches_reader_in_order() { /* app sends O "Vi\xe1\xbb" then O "\x87t"; reader yields "Việt" bytes */ }
#[test] fn forced_host_size_reaches_handler_even_if_unchanged() { /* S 44x37 twice → handler called twice */ }
#[test] fn app_exit_frame_ends_child() { /* app sends E → child.wait() returns, try_wait Some */ }
#[test] fn refuses_socket_in_world_accessible_dir() { /* dir 0777 → open() Err contains "insecure socket directory" */ }
#[test] fn hello_carries_protocol_1() {}
#[test] fn oversize_frame_is_rejected() {}
```

- [ ] **Step 2: Push and run on CI (not locally — disk):** `git push … shellx/l5-remote && gh workflow run cmux-tui.yml -R lephus/shellx-pro -f commit=$(git rev-parse HEAD) -f mode=focused -f test_filter=virtual_pty -f request_id=l5-vpty-$(date +%s)` — Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the port and the four changes.
- [ ] **Step 4: Rerun the CI command** — Expected: the focused job is green and its log lists the 8 `virtual_pty::tests::*` as `ok`. Locally only `cargo check -p cmux-tui-core` (with `CARGO_TARGET_DIR` shared) if `df -h ~` shows ≥ 15 GB free.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): virtual PTY seam in cmux-tui-core for Mac-owned terminals (from W0 bridge spike)"`

