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

| Patch | Files | Reason | Commit |
| --- | --- | --- | --- |
