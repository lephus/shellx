### Task 5B: SSH remote helper built by ShellX (`shellx-remote`)

**Files (fork):**
- Modify: `daemon/remote` (Go): runtime names `~/.cmux/daemon/…` → `~/.shellx/daemon/…`, socket dir `/tmp/cmuxd-remote-<uid>/` → `/tmp/shellx-remote-<uid>/`, busybox argv[0] name `cmux` → `shellx`, binary name `cmuxd-remote` → `shellx-remote`
- Modify: `Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/RemoteSessionCoordinator+Bootstrap.swift` (binary/dir names; keep the dev-only fallback `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1` + `CMUX_REMOTE_DAEMON_BINARY`, and confirm Release builds ignore it), `scripts/verify_remote_daemon_release.py` (asset names, `releaseURL`/download base `https://download.shellx.pro/desktop/shellx-remote/<version>/`; manifest key `CMUXRemoteDaemonManifestJSON` unchanged)
- Create: `scripts/shellx/build_remote_daemon.sh` (Go cross-build for `darwin/arm64`, `darwin/amd64`, `linux/arm64`, `linux/amd64` into `dist/shellx-remote/<version>/` + `checksums.txt`; uploading to download.shellx.pro is Wave 3 and needs the user's OK)
- Test: `daemon/remote` Go tests, `tests/test_shellx_remote_daemon.py`

**Interfaces:**
- Consumes: Task 3 client-side names (`~/.shellx/bin/shellx` in `RemoteInteractiveShellBootstrapBuilder`).
- Produces: `scripts/shellx/build_remote_daemon.sh <version>` (Wave 3's release pipeline calls it); Task 10 tests SSH sections with `CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD=1 CMUX_REMOTE_DAEMON_BINARY=dist/shellx-remote/<version>/shellx-remote-<os>-<arch>` on a tagged Debug build.

- [ ] **Step 1: Install Go** at the version in `daemon/remote/go.mod` (not installed on this Mac yet); `go version` matches.

- [ ] **Step 2: Write the failing tests**

```python
def test_manifest_points_to_shellx_download_host():
    src = read("scripts/verify_remote_daemon_release.py")
    assert "download.shellx.pro/desktop/shellx-remote" in src
    assert "github.com/manaflow-ai" not in src
def test_no_cmux_runtime_names_in_go_daemon():
    assert offenders(r"\.cmux/|cmuxd-remote-|/tmp/cmuxd", roots=["daemon/remote"], allow=[]) == []
```

Update the existing Go tests that assert the old paths so they assert the new ones (they fail first).

- [ ] **Step 3: Run** `python3 -m pytest tests/test_shellx_remote_daemon.py -q` and `cd daemon/remote && go test ./...` — Expected: FAIL.

- [ ] **Step 4: Make the renames, write `build_remote_daemon.sh`.**

- [ ] **Step 5: Run the tests** — Expected: PASS. `scripts/shellx/build_remote_daemon.sh 0.1.0` produces four binaries and `checksums.txt`. With the dev fallback env vars, a tagged Debug build opens an SSH workspace to a test host (any Linux VM the user names, or `localhost` with Remote Login on) and the remote side shows `~/.shellx/daemon/`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(shellx): shellx-remote SSH helper built by ShellX, served from download.shellx.pro"
```

