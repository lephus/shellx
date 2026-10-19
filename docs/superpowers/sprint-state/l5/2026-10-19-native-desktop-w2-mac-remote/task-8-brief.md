### Task 8: Remote e2e harness and `shellx-remote.yml` (2 s tickets, Vietnamese, sealed-invite enrollment)

**Files:**
- Create: `scripts/shellx/remote-e2e/harness.py` (process control), `scripts/shellx/remote-e2e/fake_app.py` (spike `fake_app.py` + records every `I` payload to a log as hex), `tests/test_shellx_remote_e2e.py`, `.github/workflows/shellx-remote.yml`
- Modify: `tests/test-execution.toml` (`tests/test_shellx_remote_e2e.py`, `lane = "manual"`, `reason = "needs built cmux-tui, cmux-relay, shellx-core-cli and shellx-fake-api; run by .github/workflows/shellx-remote.yml"`)

**Interfaces:**
- Consumes: `shellx-core-cli` (Task 1), `shellx-fake-api` (Tasks 3–6), patched `cmux-tui` (Task 7), stock `cmux-relay` (same workspace).
- Produces: `harness.py` class `Harness(bin_dir, core_bin_dir, ticket_ttl)` with `start_relay()`, `stop_relay()`, `start_api()`, `machine(name) -> Machine` (own core state dir 0700 + `SHELLX_CORE_CONFIG`), `Machine.core(method, **params) -> dict`, `Machine.start_ticket_refresher(write_to, permission, target=None)` (thread: mint, then sleep `max(1, (exp-now)/2)`), `start_host_daemon(machine)` (fake app + `cmux-tui server start --session e2e-<name> --headless --ephemeral --socket … --remote-state-dir … --relay <route> --relay-slot <slot> --relay-ticket-file <core>/tickets/register.ticket`, env `CMUX_SHELLX_BRIDGE_SOCKET`), `pair(viewer, host) -> invitation_id` (viewer `pair.request` → host `pair.pending` → host `tickets.mint connect target=self write_to=invite-connect.ticket` → host `remote enroll create --session … --state-dir … --advertise <route> --relay-route <route> --relay-slot <slot> --relay-ticket-file … --ttl 300` → host `pair.approve` → viewer `pair.poll write_invite_to=invite.uri`), `connect_viewer(viewer, host)` (`remote connect <route> --invite-file … --relay-slot … --relay-ticket-file … --state-dir … --local-socket … --headless --device-name <name>`), `approve_pending(host, invitation_id)`, `viewer_cli(*args)`; every process runs under `env -i` with `HOME`/`TMPDIR` inside the harness dir; all temp secrets removed in `tearDown`.

- [ ] **Step 1: Write the failing tests**

```python
class RemoteE2E(unittest.TestCase):
    def test_enroll_via_sealed_invite_and_view(self):
        inv = self.h.pair(self.viewer, self.host); self.h.connect_viewer(self.viewer, self.host)
        pending = self.h.host_cli(self.host, "remote", "enroll", "pending", "--json")
        self.assertEqual([p["invitation_id"] for p in pending], [inv])        # only ours
        self.h.approve_pending(self.host, inv)
        ws = self.h.viewer_cli("workspace", "create", "--name", "e2e", "--json")
        term = self.h.first_terminal()
        self.assertIn("SHELLX-FAKE-APP", self.h.viewer_cli("terminal", term, "screen", "read"))
    def test_vietnamese_round_trip(self):                                    # Review Focus 4
        self.h.viewer_cli("terminal", self.term, "write", "--text", "tiếng Việt\r")
        self.assertTrue(self.h.fake_app_input().endswith(bytes.fromhex("7469e1babf6e672056 69e1bb8774 0d".replace(" ", ""))))
    def test_reconnect_after_relay_restart_with_2s_tickets(self):            # Review Focus 2 (ticket_ttl=2)
        self.h.stop_relay(); time.sleep(5)           # every ticket written before the outage has expired
        self.h.start_relay()                          # same port + secret
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("terminal", "list", "--json")))
        for log in self.h.logs(): self.assertNotRegex(log, r"v2\.[A-Za-z0-9_-]{20,}\.")   # no ticket in any log
    def test_enrolled_device_reconnects_after_daemon_restart(self):
        self.h.restart_host_daemon(self.host)         # same --remote-state-dir, fresh --ephemeral mux
        self.assertTrue(wait_until(45, lambda: self.h.viewer_ok("workspace", "list", "--json")))
        self.assertEqual(self.h.host_cli(self.host, "remote", "enroll", "pending", "--json"), [])
```

`setUp` builds nothing; it reads `SHELLX_E2E_BIN` (cmux-tui target dir) and `SHELLX_E2E_CORE_BIN` (shellx-core target dir), `skipTest` with the exact build commands if missing.

- [ ] **Step 2: Run locally only if disk allows, else CI:** `SHELLX_E2E_BIN=… SHELLX_E2E_CORE_BIN=… python3 tests/test_shellx_remote_e2e.py` — Expected: FAIL (harness missing).
- [ ] **Step 3: Implement** `harness.py`, `fake_app.py`, and `shellx-remote.yml`: triggers `push` on `shellx/**` with `paths` (`shellx-core/**`, `cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs`, `cmux-tui/crates/cmux-tui-core/src/surface.rs`, `scripts/shellx/remote-e2e/**`, `tests/test_shellx_remote*.py`, `Packages/Shared/ShellXBrand/**`, `.github/workflows/shellx-remote.yml`) + `workflow_dispatch`; `permissions: contents: read`; concurrency per ref, cancel in progress; actions pinned by full sha (copy pins from `cmux-tui.yml`). Jobs: `core` (matrix `ubuntu-24.04`, `macos-26`: `cargo test --workspace --locked` in `shellx-core`, `python3 scripts/check_deps.py`, `scripts/c-smoke.sh` on macOS); `swift-package` (`macos-26`: `swift test --package-path Packages/Shared/ShellXBrand`); `bridge-e2e` (`ubuntu-24.04`, timeout 60: `./scripts/install-zig-ci.sh`, `./.github/actions/setup-cmux-tui-rust`, env `CMUX_GHOSTTY_VT_ZIG_CPU=baseline`, `cargo test -p cmux-tui-core --lib virtual_pty --locked`, `cargo build -p cmux-tui -p cmux-relay --locked`, `cargo build --workspace --locked` in `shellx-core`, then the e2e test).
- [ ] **Step 4: Push and watch** `gh run watch -R lephus/shellx-pro $(gh run list -R lephus/shellx-pro -w shellx-remote -b shellx/l5-remote -L1 --json databaseId -q '.[0].databaseId')` — Expected: all three jobs green; the e2e log shows 4 tests `ok`.
- [ ] **Step 5: Commit** `git commit -m "test(shellx): remote e2e harness (fake API, cmux-relay, patched daemon) and shellx-remote CI"`
- [ ] **Step 6 (only if L0 refuses D3):** add `test_invite_with_placeholder_ticket` — host creates the invite with a ticket file containing `shellx-no-ticket` and the viewer connects with its own connect ticket; record pass/fail in the lane report; on fail, escalate to L0 (no other fallback is safe).

