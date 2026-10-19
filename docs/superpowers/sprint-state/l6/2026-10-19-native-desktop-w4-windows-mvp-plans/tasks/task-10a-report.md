# Task 10a report (shellx-core bridge, non-UI)

Status: DONE. Branch shellx/l6-windows.

Commits: a56e3de390 (merge --no-ff of L5 eb9af97546, clean, no conflicts), 563cb95db7 (feat: bridge, paths, os_info, account.rs, smoke, Cargo deps + Cargo.lock). Pushed (index was empty before; only own paths committed).

Built
- windows/shellx-app/src/core_bridge.rs: CoreBridge(shellx_core::Core): CoreCall, CoreError -> CoreErr. Tests incl. e2e against shellx-fake-api (login -> list shows no this-machine -> register -> list has exactly one is_this_machine, platform windows -> heartbeat -> logout -> not_logged_in), unreachable API gives an error (no panic), unknown method / not_configured mapping.
- paths.rs (native_dir/core_dir/remote_dir), os_info.rs (winreg 0.55 under cfg(windows); "unknown" elsewhere; device_name via COMPUTERNAME, fallback "PC Windows"). Modules carry #![allow(dead_code)] until Task 10b wires them.
- windows/shellx-model/src/account.rs: AccountState/AccountEvent/AccountAction/AccountFlow per brief; password redacted in Debug and never stored. Extras: tick de-duplication (single pending ScheduleTick), startup network error -> Error + retry list on tick, login error -> Error and resubmittable (no auto retry), stale ListResult after logout ignored, second "no this machine after register" -> Error(not_registered) to avoid a register loop. 9 tests (the 4 named + 5).
- smoke.rs: core_bridge() called from run() (after ui_assets): config.set OK, machines.list -> not_logged_in (or unknown_method accepted), unknown method maps.
- Cargo: shellx-core path dep, serde_json, winreg (cfg(windows)); dev-deps shellx-fake-api (path), tempfile.

Evidence
- Mac: cargo test --locked -p shellx-model: 102 pass (CI count); shellx-app bin tests 26 pass incl. 4 core_bridge, paths, os_info. Mac --smoke prints "smoke-core: config.set OK, machines.list -> not_logged_in" (the later PowerShell step fails on Mac as before).
- CI: run 39171946097 (my push) was cancelled by the next push; run 39172747108 (contains 563cb95db7) all green: model, app (windows-msvc, 7m36s), remote-e2e, installer. Windows log: "smoke-core: config.set OK, machines.list -> not_logged_in", "smoke: PASS in 3.7561984s".
- rustls/openssl check: `cargo tree --locked -p shellx-core -e normal | grep -i -E "openssl|native-tls|aws-lc"` -> empty (rc 1); same for `-p shellx-app --target x86_64-pc-windows-msvc` -> empty. Windows build uses rustls-platform-verifier (platform-verifier feature of ureq).

Files: windows/Cargo.lock, windows/shellx-app/{Cargo.toml,src/main.rs,src/smoke.rs,src/core_bridge.rs,src/paths.rs,src/os_info.rs}, windows/shellx-model/src/{lib.rs,account.rs}.

K-change requests: none.

Concerns
- Heartbeat has no result event (per brief); heartbeat failures are ignored, a lost session is caught by the next list (not_logged_in).
- Windows store has no ACL hardening in shellx-core (known, per brief); state dir is under %LOCALAPPDATA% (per-user).
- 10b must call config.set before the first call, run all CoreBridge calls off the UI thread (they block on ureq), and deliver AccountEvent::Tick(now) at each ScheduleTick.
