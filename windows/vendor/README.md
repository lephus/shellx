# Vendored crates

## gpui 0.2.2

`gpui-0.2.2/` is the crate `gpui` 0.2.2 as published on crates.io by Zed Industries under the
Apache License 2.0 (`gpui-0.2.2/LICENSE-APACHE`), unpacked byte for byte from
`gpui-0.2.2.crate`:

- crate sha256 `979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707`
  (the checksum `windows/Cargo.lock` carried before the copy);
- built from zed commit `69e2130295c2649963eb639fc70b4f2ee8ea1624`, `crates/gpui`
  (`gpui-0.2.2/.cargo_vcs_info.json`).

**Why it is here.** ShellX for Windows needs fixes inside gpui's Windows platform code that
cannot be made from outside the crate (design: `docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md`
§4.2). `windows/Cargo.toml` points `[patch.crates-io]` at this copy, so every build (Mac,
CI, the cross build) uses the same gpui, and excludes `vendor` from the workspace so the copy
is not a member (its dev-dependencies stay out of `Cargo.lock`, and `cargo fmt`/`cargo test`
leave it alone).

**Rules.**

- The commit that added the copy is the unmodified crate. Each patch is its own commit that
  says why, and adds a row to the table below.
- Apache-2.0 §4(b): the first line of every modified file is
  `// Modified by ShellX: <one-line reason>. See windows/vendor/README.md.`
- `windows/vendor/check-gpui.sh` must pass. It compares the copy with the published crate
  (from cargo's cache, else downloaded, checked against the sha256 above) and fails unless the
  files that differ are exactly the files that carry the notice line. It prints
  `gpui-0.2.2: pristine` or `gpui-0.2.2: N patched file(s): <list>`.
- A patch to gpui's Windows code must also pass `scripts/shellx/check-windows-build.sh` and
  `scripts/shellx/check-windows-build.sh --release`. The second type-checks the release-only code
  (the embedded shader bytes, `cfg(not(debug_assertions))`) with a stand-in for `fxc.exe` that
  compiles no shader. It builds no exe; only the VPS cross build compiles the real shaders.

| Patch | Files | Reason | Commit |
| --- | --- | --- | --- |
| (d) | `build.rs` | The shader step was gated on the build host (`#[cfg(target_os = "windows")]`), so a cross build on Linux never compiled the HLSL and the release build failed at `include!(…/shaders_bytes.rs)`; the two host gates are removed, the match on `CARGO_CFG_TARGET_OS` already selects the target. Replaces the cross-build container's script that edited the registry copy. | `vendor(windows): gpui patch (d)` |
| (a) | src/platform/windows/events.rs (the two key-up handlers; patch (c) also edits this file) | A VK_PACKET key-up (SendInput KEYEVENTF_UNICODE: Unikey, EVKey, OpenKey, password managers) went through translate_message, which forges a WM_KEYDOWN, so the character came twice or with a stray one (R2 F1). Both key-up handlers return early for VK_PACKET with the value they returned before, without TranslateMessage. | vendor(windows): gpui patch (a) |
| (b) | src/platform/windows/vsync.rs | When DWM reported a refresh period under 1 ms, the fallback passed the refresh rate to retrieve_duration, which divided by rate / 1 000 000 = 0; the VSyncProvider thread panicked and the window stopped repainting (R1 F6). The fallback now computes denominator / numerator seconds (default 16.666 ms when unusable), and a QPC frequency under 1 MHz no longer divides by zero. | vendor(windows): gpui patch (b) |
| (c) | src/platform/windows/directx_renderer.rs, src/platform/windows/events.rs (draw_window; patch (a) also edits this file, whose line 1 notice is patch (a)'s) | After DXGI_ERROR_DEVICE_REMOVED during a resize the render target was left dropped: the next paint panicked inside the window procedure (abort), a later resize panicked, and device-lost recovery released the render target and, on retries and at drop, the devices and resources a second time; a failed recovery attempt leaked its swap chain, and a successful one emptied the atlas while the old scene could still be presented (R1 F5). The render target is an Option, a failed resize is retried at the next draw, recovery releases the old objects once, releases what a failed attempt made and remembers the composition mode, and after a recovery nothing is drawn until draw_window forces a fresh frame (upstream's fix). | vendor(windows): gpui patch (c) |
