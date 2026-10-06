# ShellX Desktop A8 — SSH Workspaces and tmux Attach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Work on a server as on this computer: one sidebar workspace per server, tabs and splits that open straight onto it through the system `ssh` (multiplexed on macOS, so no second password), the server's folder, git branch and listening ports in the sidebar (ports open locally through an SSH forward), panes that wait and reconnect when the network drops, and tmux sessions (here or on a server) attached as tabs — restored by A5a, kept alive by the A5b daemon, scriptable through the A7 CLI, visible on the phone like any session.

**Architecture:** An SSH pane is an ordinary `LocalSessions` session whose PTY runs `/usr/bin/ssh` (Windows `ssh.exe`) instead of a login shell: `LocalSessions.open` gains a `SessionLaunch` (`SshLaunch` / `TmuxLaunch`, `packages/shellx_agent/lib/src/remote/`). The remote command is one base64-wrapped POSIX `sh` bootstrap that reports `OSC 6973` (hello, pid, home), writes the **unchanged** ShellX zsh/bash hooks plus a small branch add-on into `~/.cache/shellx/remote-<hash>/` on the server and `exec`s the user's login shell (or `tmux attach`). `SessionManager` reads the remote OSC 7/6973 into `SessionSummary.remote`, cwd and branch, and a `RemotePortWatcher` probes `ps` + `ss`/`lsof` over the multiplexed connection (`SshControl`, `BatchMode=yes`). The desktop keeps `PaneSession.remote`, inherits the launch on splits and in SSH workspaces (`Workspace.ssh`), shows a lost-connection strip, reconnects into the same pane slot (`TerminalTabs.reconnect` → `replacePaneSession`, `SshReconnector` with 3→60 s backoff), and forwards remote ports (`RemotePortForwards`). tmux windows/panes are **not** mapped onto ShellX tabs/panes (spec D27): a tmux session is one tab running a real tmux client.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 via fvm (`~/fvm/versions/3.41.4/bin/dart`, `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter`), `package:test` + `fake_async`, `flutter_test`, flutter_riverpod 3, xterm 4.0.0; system OpenSSH (`/usr/bin/ssh`, Win32-OpenSSH `ssh.exe`), `/bin/sh`, tmux; Rust 2021 (`~/.cargo/bin/cargo`) for the A7 CLI commands only. **No new dependencies** anywhere.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-ssh-a8-design.md` (binding; S1–S7 and D1–D44 are final). UI: `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a8.md` (binding for look, copy, accessibility). Read alongside: A3 spec D1–D17 + plan Task 3 (`TerminalTabs` panes), A5a plan Tasks 2–6 (`SavedPane`, `RestoreSnapshot`, `TerminalTabs.restore`, `RestorePersistence`), A5b plan Tasks 2–5 (mux codec) if merged, A7 plan Tasks 1, 4, 6, 9, 10 (`open(tabId:)`, `COMMANDS`, `UiCommandHandler`, `openTabFor`/`splitPane`, `run.rs`).

## Prerequisite: A3, A4, A5a, A6 and A7 merged; A5b optional

Start `feat/desktop-a8` from `main` **after A3, A4, A5a, A6 and A7 are merged** (spec D1). Check once at the start and record the answers in `docs/superpowers/ledgers/a1-desktop-terminal.md` under a new heading `## A8 (SSH/tmux) — execution`:

```bash
test -f apps/desktop/lib/src/restore/restore_snapshot.dart && echo "A5a merged" || echo "A5a MISSING — stop"
test -f apps/desktop/lib/src/cli/ui_command_handler.dart && echo "A7 merged" || echo "A7 MISSING — Tasks 1–12 only, Task 14 waits"
test -f packages/shellx_agent/lib/src/mux/mux_server.dart && echo "A5b merged" || echo "A5b not merged — Task 13 skips the mux step"
grep -q "keybindings" apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart 2>/dev/null && echo "A9 merged — register ssh.connect in its table (Task 11)" || echo "A9 not merged"
```

The code below is written against the **post-A7** sources: `LocalSessions.open({cols, rows, cwd, tabId})`, `TerminalTabs.openTabFor` / `splitPane` / `OpenBusyException` / `PaneGoneException`, `UiCommandHandler`, `CliType`, `kCliCaps`, A5a `SavedPane`. Where a name differs in the merged code, use the merged name and record the rename in the ledger.

Tasks marked **⚠ MANUAL** need a real Mac (macOS 13+), a reachable SSH server (a Linux VM or a second Mac with Remote Login on; zsh, bash and fish accounts), and a real Windows 10 1809+/11 machine with the OpenSSH Client. An executor without them records "pending manual" in the ledger section and continues — **the branch is not merged until every ⚠ step is recorded as passed.**

Baseline before Task 1 (record the counts in the ledger):

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
cd term && ~/.cargo/bin/cargo test && cd ..
```

## Global Constraints

- The spec wins. User-facing strings in vi + en ARB (UI addendum §7); "SSH", "tmux", "pane", "tab", "workspace", "hook" stay English in Vietnamese copy. CLI output English only (A7 D11).
- **Byte-identical local hooks:** `zshHookEnv`, `zshHookBody`, `bashHookRc`, `bashHookBody`, `powerShellHook` in `packages/shellx_agent/lib/src/pty/shell_hook_scripts.dart` and `term/shell/*` are not edited; the remote hook **appends** its own text (Task 3 asserts `contains(zshHookEnv)`).
- **Phone protocol unchanged:** no edits to `packages/shellx_core/lib/src/protocol/messages.dart`, `apps/mobile`, `relay/`. No new dependencies in any `pubspec.yaml` or `term/Cargo.toml`.
- **Injection safety (D4, D38):** user text reaches `ssh` only as `SshTarget.destinationArgs` (after `--`) or inside the generated script through `shQuote` / environment variables; the outer remote command contains only `[A-Za-z0-9+/=]`, spaces and fixed sh syntax — never `'` inside the quotes, never `!`. Everything read from `layout.json`, settings or the CLI is re-validated with `SshTarget.parse` / `isValidTmuxName` / `isValidRemoteCwd`.
- **Never prompt invisibly (D38g):** every helper `ssh` (`-G`, `-O`, probe, tmux list, forward) runs with `BatchMode=yes` or uses only the control socket; panes never get `BatchMode`.
- **Privacy (D37):** never log targets, hosts, users, SSH ports, remote paths, `home`, branches, tmux names, scripts, commands, stdout/stderr of helpers, forwarded port numbers. Logs carry an event kind, an exit code, a `runtimeType`, a count. `toString()` of new value classes that hold such data returns `'…'`.
- Limits (D39): ≤ 32 sessions total (A1 D8); ≤ 16 probed hosts; recent targets ≤ 10; config hosts ≤ 256; bootstrap script ≤ 24 KiB; tmux names 1–64 chars without `:`/`.`/controls; remote cwd ≤ 4096 bytes, starting `/`, `~` or `~/`; ≤ 32 forwards per host.
- Timings: master wait ≤ 3 s polling 100 ms (D9); `ssh -G` cache 60 s, timeout 2 s (D13); keepalive `ServerAliveInterval=15`, `ServerAliveCountMax=3`; probe 5 s macOS / 15 s Windows, timeout 4 s, 3 failures → 60 s (D18); hookless "connected" after 10 s (D11); reconnect delays 3, 6, 12, 24, 48, 60, 60… s, give up after 30 min (D20); tmux list timeout 5 s (D25); `ControlPersist=60`.
- Settings (UI-owned, A5b D13): `ssh_recent_targets` (string list), `ssh_plain_targets` (string list), `ssh_remote_hook` (bool, default `true`).
- Every interface gaining members updates **every** implementer in the same task (`SessionManager`, `FakeLocalSessions`, and `RemoteLocalSessions` + mux codec when A5b is merged).
- Code blocks in this plan are not pre-formatted: run `dart format` on the files you touched before the `--set-exit-if-changed` check. Tasks 1–6 were executed once against a scratch copy of `packages/shellx_agent` while writing this plan (all their tests green, `dart analyze` clean); Tasks 7–14 depend on A5a/A6/A7 sources that did not exist yet.
- Code style as in A1–A7. Every task ends green (its tests + the full suite of every package it touched), `dart format --set-exit-if-changed`, `flutter analyze`/`dart analyze`, `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` for the Rust step, and a commit containing only the listed files — never `git add -A`.

## Review Focus

1. **Hostile text reaches `ssh` or the server's shell** — a target `-oProxyCommand=…`, a cwd `'; rm -rf ~ #`, a tmux name with `$(…)`, an edited `layout.json` — it must be refused or arrive as data, never as an option or code. Pinned by `ssh_target_test` "anything that could read as an ssh option is refused", `remote_bootstrap_test` "user text only through shQuote and the environment", `session_launch_test` "bad data from a file is refused" (Tasks 1, 3) and `restore_remote_test` (Task 13).
2. **The bootstrap breaks a login** — read-only home, `.ok` left without files, fish/csh as login shell, an existing `ZDOTDIR`, a second pane connecting at the same moment — the user must always get a working login shell (with or without hooks). Pinned by `remote_bootstrap_run_test` (Task 3, real `/bin/sh`).
3. **A reconnect leaves the pane inconsistent** — tab id, focus, zoom, MRU, A4 unread, A5a pane key, A7 ids; or retries forever against a wrong password. Pinned by `terminal_tabs_remote_test` "reconnect swaps the leaf in place" (Task 7), `ssh_reconnector_test` "failed never retries by itself" and "gives up after 30 minutes" (Task 9).
4. **A helper prompts or leaks** — a probe asking for a password nobody sees, a log line with a host or path. Pinned by `ssh_control_test` "every helper runs BatchMode or over the socket" (Task 4), `remote_port_watcher_test` "needs sign-in stops probing" and the privacy log tests (Tasks 5, 6).
5. **The control socket lives somewhere another user controls** — pinned by `ssh_control_test` "an unsafe control directory turns multiplexing off" (Task 4).

---

## File Structure

| File | Responsibility |
|---|---|
| Create `packages/shellx_agent/lib/src/remote/ssh_target.dart` | `SshTarget` (D4, D5) |
| Create `packages/shellx_agent/lib/src/remote/session_launch.dart` | `SessionLaunch`, `SshLaunch`, `TmuxLaunch`, `SessionRemote`, validators (D24, D25, D29) |
| Create `packages/shellx_agent/lib/src/remote/command_runner.dart` | `CommandResult`, `CommandRunner`, `runCommand` |
| Create `packages/shellx_agent/lib/src/remote/ssh_config_hosts.dart` | `~/.ssh/config` hosts (D6) |
| Create `packages/shellx_agent/lib/src/remote/tmux_sessions.dart` | tmux list format, parse, classify (D25) |
| Create `packages/shellx_agent/lib/src/remote/remote_probe.dart` | probe script + parser (D18) |
| Create `packages/shellx_agent/lib/src/remote/remote_bootstrap.dart` | bootstrap script, remote hook add-on, `shQuote`, `remoteExecCommand`, tmux list script (D10, D15) |
| Create `packages/shellx_agent/lib/src/remote/ssh_command.dart` | `sshPathFor`, `tmuxPathFor`, `buildSshCommand`, `buildLocalTmuxCommand` (D3, D12, D13, D25) |
| Create `packages/shellx_agent/lib/src/remote/ssh_control.dart` | `SshControl`, `prepareControlDirectory`, forwards (D8, D9, D13, D18, D19, D40) |
| Create `packages/shellx_agent/lib/src/remote/remote_tools.dart` | `RemoteTools`, `resolveRemoteTools` |
| Create `packages/shellx_agent/lib/src/remote/remote_port_watcher.dart` | `RemotePortWatcher`, `RemoteShell` (D18) |
| Modify `packages/shellx_agent/lib/src/notify/osc_event_parser.dart` | `RemoteMetaReported` (OSC 6973, D16) |
| Modify `packages/shellx_agent/lib/src/context/cwd_url.dart` | `parseRemoteCwdPath` (D14) |
| Modify `packages/shellx_agent/lib/src/session/{local_sessions,session_manager}.dart` | `open(launch:)`, `SessionSummary.remote`, remote state, ports (D2, D9, D14–D18, D36) |
| Modify `packages/shellx_agent/lib/shellx_agent.dart` | exports |
| Modify `apps/desktop/test/support/fake_local_sessions.dart` | `launch`, `remote` |
| Create `apps/desktop/lib/src/remote/{remote_state,ssh_settings,ssh_actions,ssh_reconnector,remote_port_forwards,remote_tools_provider}.dart` | desktop remote logic |
| Modify `apps/desktop/lib/src/terminal/{pane_layout,terminal_tabs,sidebar_workspaces}.dart` | `replaceLeaf`, remote panes, reconnect, `Workspace.ssh` |
| Modify `apps/desktop/lib/src/platform/settings_store.dart` | three keys |
| Modify `apps/desktop/lib/src/agent/session_core.dart`, `apps/desktop/lib/main.dart` | tools wiring |
| Create `apps/desktop/lib/src/ui/terminal/{remote_marks,remote_strip,ssh_connect_dialog}.dart` | marks, strip, dialog |
| Modify `apps/desktop/lib/src/ui/terminal/{session_tab_row,pane_tree_view,workspace_header,session_sidebar,terminal_shortcuts,terminal_workspace_page,terminal_overlays}.dart`, `apps/desktop/lib/src/ui/window_router.dart`, `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` | UI |
| Modify `apps/desktop/lib/src/tray/{tray_action,tray_menu,tray_actions}.dart` | "SSH" submenu |
| Modify `apps/desktop/lib/l10n/app_en.arb`, `app_vi.arb` (+ generated) | strings |
| Modify `apps/desktop/lib/src/restore/{restore_snapshot,restore_persistence}.dart`, `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`restore`) | `launch` in leaves (D29) |
| Modify (A5b) `packages/shellx_agent/lib/src/mux/{mux_session_codec or mux_messages,remote_local_sessions,mux_server}.dart` | `launch`, `remote` on the wire (D31) |
| Modify `apps/desktop/lib/src/cli/{ui_command_handler,cli_event_bus}.dart`, `packages/shellx_agent/lib/src/mux/cli_wire.dart` | `ui.ssh.open`, `ui.tmux.*`, `remote` in `ls`, `pane.replaced` (D22, D33) |
| Modify `term/src/api/{args,run}.rs`, `agent-skills/shellx/reference.md` | CLI commands (D33) |
| Modify `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `docs/superpowers/HANDOFF.md`, ledger | privacy, manual checklist (D37) |

---

### Task 1: Agent — `SshTarget`, `SessionLaunch`, `SessionRemote` (D4, D5, D24, D25, D29)

**Files:**
- Create: `packages/shellx_agent/lib/src/remote/ssh_target.dart`, `packages/shellx_agent/lib/src/remote/session_launch.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/remote/ssh_target_test.dart`, `packages/shellx_agent/test/remote/session_launch_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `final class SshTarget { String host; String? user; int? port; static SshTarget? parse(String input); String get key; List<String> get destinationArgs; }` — value equality on `key`; `toString()` → `'SshTarget(…)'`.
  - `bool isValidTmuxName(String)`, `bool isPlainTmuxName(String)`, `bool isValidRemoteCwd(String)`.
  - `sealed class SessionLaunch { SshTarget? get host; String get hostLabel; Map<String, Object?> toJson(); SessionLaunch? forSplit(String? cwd); SessionLaunch forReconnect(String? cwd); static SessionLaunch? fromJson(Object? json); }`
  - `final class SshLaunch extends SessionLaunch { const SshLaunch(SshTarget target, {String? remoteCwd, bool hook = true}); }`
  - `final class TmuxLaunch extends SessionLaunch { const TmuxLaunch(String session, {SshTarget? host, bool create = false, bool hook = true}); }`
  - `final class SessionRemote { const SessionRemote({required SessionLaunch launch, bool connected = false, String? home}); bool get isTmux; String? get tmuxSession; String? get hostKey; }`

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/remote/ssh_target_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  group('SshTarget.parse (A8 D4)', () {
    test('alias, host, user, port, ssh:// URL', () {
      final a = SshTarget.parse('devbox')!;
      expect((a.host, a.user, a.port), ('devbox', null, null));
      final b = SshTarget.parse(' me@dev.example.com:2222 ')!;
      expect((b.host, b.user, b.port), ('dev.example.com', 'me', 2222));
      final c = SshTarget.parse('host_1:22')!;
      expect((c.host, c.port), ('host_1', 22));
      final d = SshTarget.parse('SSH://ops@10.0.0.5:2200/')!;
      expect((d.host, d.user, d.port), ('10.0.0.5', 'ops', 2200));
    });

    test('IPv6 with and without a port', () {
      final a = SshTarget.parse('[fe80::1%en0]:2222')!;
      expect((a.host, a.port), ('fe80::1%en0', 2222));
      expect(a.key, '[fe80::1%en0]:2222');
      final b = SshTarget.parse('me@::1')!;
      expect((b.host, b.user, b.port), ('::1', 'me', null));
      expect(b.key, 'me@::1');
    });

    test('anything that could read as an ssh option is refused', () {
      for (final bad in [
        '-oProxyCommand=touch /tmp/x',
        '-p',
        'me@-oProxyCommand=x',
        '-host',
        '.hidden',
        'a b',
        'ho\tst',
        'host\nother',
        'me@@host',
        '@host',
        'host:',
        'host:0',
        'host:65536',
        'host:22a',
        'devbox:22:33',
        '[::1',
        '[::1]x',
        '',
        ' ',
        'x' * 256,
        'us er@host',
        'ü@host',
        'host;rm -rf ~',
        "host'",
        r'host$(id)',
        'ho\u0085st',
      ]) {
        expect(SshTarget.parse(bad), isNull, reason: bad);
      }
    });

    test('the key is canonical and parses back to the same target (D5)', () {
      for (final text in [
        'devbox',
        'me@devbox',
        'devbox:2222',
        'me@devbox:2222',
        '[::1]:22',
        '::1',
      ]) {
        final target = SshTarget.parse(text)!;
        expect(target.key, text);
        expect(SshTarget.parse(target.key), target);
      }
    });

    test('ssh arguments never put user text before --', () {
      expect(SshTarget.parse('me@devbox:2222')!.destinationArgs, [
        '-l',
        'me',
        '-p',
        '2222',
        '--',
        'devbox',
      ]);
      expect(SshTarget.parse('devbox')!.destinationArgs, ['--', 'devbox']);
    });

    test('toString never shows the host (D37)', () {
      expect('${SshTarget.parse('devbox')}', isNot(contains('devbox')));
    });
  });
}
```

`packages/shellx_agent/test/remote/session_launch_test.dart`:

```dart
import 'dart:convert';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final devbox = SshTarget.parse('me@devbox:2222')!;

  group('SessionLaunch JSON (A8 D29)', () {
    test('round trip', () {
      for (final launch in <SessionLaunch>[
        SshLaunch(devbox),
        SshLaunch(devbox, remoteCwd: '/srv/app', hook: false),
        SshLaunch(devbox, remoteCwd: '~/work'),
        const TmuxLaunch('main'),
        TmuxLaunch('build 2', host: devbox, create: true, hook: false),
      ]) {
        final json = jsonDecode(jsonEncode(launch.toJson()));
        expect(SessionLaunch.fromJson(json), launch);
      }
    });

    test('bad data from a file is refused', () {
      for (final bad in <Object?>[
        null,
        'ssh',
        <String, Object?>{'kind': 'ftp'},
        <String, Object?>{'kind': 'ssh'},
        <String, Object?>{'kind': 'ssh', 'target': '-oProxyCommand=x'},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'cwd': 'rel'},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'cwd': '/a\u0007'},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'cwd': 7},
        <String, Object?>{'kind': 'ssh', 'target': 'devbox', 'hook': 'yes'},
        <String, Object?>{'kind': 'tmux', 'session': 'a:b'},
        <String, Object?>{'kind': 'tmux', 'session': ''},
        <String, Object?>{'kind': 'tmux', 'session': 'x' * 65},
        <String, Object?>{'kind': 'tmux', 'session': 'main', 'host': 'a b'},
        <String, Object?>{'kind': 'tmux', 'session': 'main', 'create': 1},
      ]) {
        expect(SessionLaunch.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('an entry without "hook" uses the hook', () {
      expect(
        SessionLaunch.fromJson({'kind': 'ssh', 'target': 'devbox'}),
        SshLaunch(SshTarget.parse('devbox')!),
      );
    });
  });

  group('split and reconnect (A8 D21, D24)', () {
    test('an SSH pane splits onto the same server, in its folder', () {
      expect(
        SshLaunch(devbox, hook: false).forSplit('/srv/app'),
        SshLaunch(devbox, remoteCwd: '/srv/app', hook: false),
      );
      expect(SshLaunch(devbox, remoteCwd: '/x').forSplit(null), SshLaunch(devbox));
      expect(SshLaunch(devbox).forSplit(r'C:\x'), SshLaunch(devbox));
    });

    test('a tmux pane splits into a plain shell on the same machine', () {
      expect(TmuxLaunch('main', host: devbox).forSplit('/x'), SshLaunch(devbox));
      expect(
        TmuxLaunch('main', host: devbox, hook: false).forSplit(null),
        SshLaunch(devbox, hook: false),
      );
      expect(const TmuxLaunch('main').forSplit('/x'), isNull);
    });

    test('reconnect keeps the launch and the last folder; tmux attaches', () {
      expect(
        SshLaunch(devbox, remoteCwd: '/a').forReconnect('/b'),
        SshLaunch(devbox, remoteCwd: '/b'),
      );
      expect(
        SshLaunch(devbox, remoteCwd: '/a').forReconnect(null),
        SshLaunch(devbox, remoteCwd: '/a'),
      );
      expect(
        TmuxLaunch('main', host: devbox, create: true).forReconnect('/b'),
        TmuxLaunch('main', host: devbox),
      );
    });
  });

  test('tmux names (D25, D11) and remote folders (D14)', () {
    expect(isValidTmuxName('main'), isTrue);
    expect(isValidTmuxName('my session 2'), isTrue);
    for (final bad in ['', 'a:b', 'a.b', 'x' * 65, 'a\u001bb']) {
      expect(isValidTmuxName(bad), isFalse, reason: bad);
    }
    expect(isPlainTmuxName('build-2_x'), isTrue);
    expect(isPlainTmuxName('my session'), isFalse);
    expect(isValidRemoteCwd('/srv/app'), isTrue);
    expect(isValidRemoteCwd('~'), isTrue);
    expect(isValidRemoteCwd('~/w'), isTrue);
    expect(isValidRemoteCwd('~root'), isFalse);
    expect(isValidRemoteCwd('rel/x'), isFalse);
  });

  test('labels and SessionRemote', () {
    expect(SshLaunch(devbox).hostLabel, 'me@devbox:2222');
    expect(const TmuxLaunch('main').hostLabel, '');
    final remote = SessionRemote(launch: TmuxLaunch('main', host: devbox));
    expect(remote.isTmux, isTrue);
    expect(remote.tmuxSession, 'main');
    expect(remote.hostKey, 'me@devbox:2222');
    expect(remote.connected, isFalse);
    expect('$remote', isNot(contains('devbox')));
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/ssh_target_test.dart test/remote/session_launch_test.dart`
Expected: FAIL — `SshTarget`, `SessionLaunch` undefined.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/remote/ssh_target.dart`:

```dart
/// A server to SSH to (A8 D4, D5): an alias from `~/.ssh/config`, a DNS
/// name or an IP address, with an optional user and port. Only text that
/// can never be read as an `ssh` option gets through [parse]; the host is
/// always passed after `--` ([destinationArgs]).
final class SshTarget {
  const SshTarget._(this.host, this.user, this.port);

  /// Alias, DNS name, IPv4 or IPv6 (without brackets).
  final String host;
  final String? user;
  final int? port;

  static final _host = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,252}$');
  static final _ipv6 = RegExp(
    r'^[0-9A-Fa-f.]*:[0-9A-Fa-f:.]*(%[A-Za-z0-9._-]+)?$',
  );
  static final _user = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,31}$');
  static final _digits = RegExp(r'^[0-9]{1,5}$');

  static bool _control(int rune) =>
      rune <= 0x20 || rune == 0x7F || (rune >= 0x80 && rune <= 0x9F);

  /// Null for anything outside D4: whitespace or control characters, a
  /// leading `-` or `.`, two `@`, a bad port, over 255 characters.
  static SshTarget? parse(String input) {
    var text = input.trim();
    if (text.isEmpty || text.length > 255 || text.runes.any(_control)) {
      return null;
    }
    if (text.toLowerCase().startsWith('ssh://')) {
      text = text.substring('ssh://'.length);
      if (text.endsWith('/')) text = text.substring(0, text.length - 1);
    }
    String? user;
    final at = text.indexOf('@');
    if (at >= 0) {
      if (text.indexOf('@', at + 1) >= 0) return null;
      user = text.substring(0, at);
      if (!_user.hasMatch(user)) return null;
      text = text.substring(at + 1);
    }
    if (text.startsWith('[')) {
      final close = text.indexOf(']');
      if (close < 0) return null;
      final host = text.substring(1, close);
      if (!_ipv6.hasMatch(host)) return null;
      final rest = text.substring(close + 1);
      if (rest.isEmpty) return SshTarget._(host, user, null);
      if (!rest.startsWith(':')) return null;
      final port = _port(rest.substring(1));
      return port == null ? null : SshTarget._(host, user, port);
    }
    final colons = ':'.allMatches(text).length;
    if (colons > 1) {
      return _ipv6.hasMatch(text) ? SshTarget._(text, user, null) : null;
    }
    var host = text;
    int? port;
    if (colons == 1) {
      final i = text.indexOf(':');
      host = text.substring(0, i);
      port = _port(text.substring(i + 1));
      if (port == null) return null;
    }
    if (!_host.hasMatch(host)) return null;
    return SshTarget._(host, user, port);
  }

  static int? _port(String text) {
    if (!_digits.hasMatch(text)) return null;
    final value = int.parse(text);
    return value >= 1 && value <= 65535 ? value : null;
  }

  /// D5: `[user@]host[:port]`, IPv6 in brackets when a port follows.
  String get key {
    final h = host.contains(':') && port != null ? '[$host]' : host;
    return '${user == null ? '' : '$user@'}$h${port == null ? '' : ':$port'}';
  }

  /// `[-l user] [-p port] -- host` (D4).
  List<String> get destinationArgs => [
    if (user case final u?) ...['-l', u],
    if (port case final p?) ...['-p', '$p'],
    '--',
    host,
  ];

  @override
  bool operator ==(Object other) => other is SshTarget && other.key == key;

  @override
  int get hashCode => key.hashCode;

  /// Never the host (D37).
  @override
  String toString() => 'SshTarget(…)';
}
```

`packages/shellx_agent/lib/src/remote/session_launch.dart`:

```dart
import 'ssh_target.dart';

bool _hasControl(String text) => text.runes.any(
  (r) => r < 0x20 || r == 0x7F || (r >= 0x80 && r <= 0x9F),
);

/// A8 D25: tmux forbids `:` and `.` in session names.
bool isValidTmuxName(String name) =>
    name.isNotEmpty &&
    name.length <= 64 &&
    !name.contains(':') &&
    !name.contains('.') &&
    !_hasControl(name);

final _plainTmux = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// D11: names a hookless connection may pass to the server's shell as a
/// bare word (no quoting is involved there).
bool isPlainTmuxName(String name) => _plainTmux.hasMatch(name);

/// D14/D29: a folder on the server, as reported (`/…`) or typed (`~/…`).
bool isValidRemoteCwd(String path) =>
    path.isNotEmpty &&
    path.length <= 4096 &&
    !_hasControl(path) &&
    (path.startsWith('/') || path == '~' || path.startsWith('~/'));

/// What a new session runs instead of a local login shell (A8 D2). Saved in
/// the A5a layout, sent over the A5b socket and by the A7 CLI as [toJson];
/// whatever comes back is re-checked by [fromJson].
sealed class SessionLaunch {
  const SessionLaunch();

  /// The server; null for a tmux session on this computer.
  SshTarget? get host;

  /// [SshTarget.key] of [host], or '' (D5).
  String get hostLabel => host?.key ?? '';

  Map<String, Object?> toJson();

  /// D24: what a split of this pane starts, [cwd] being the pane's folder;
  /// null = a local shell.
  SessionLaunch? forSplit(String? cwd);

  /// D21: the same launch after a lost connection, in the last folder.
  SessionLaunch forReconnect(String? cwd);

  static SessionLaunch? fromJson(Object? json) {
    if (json is! Map) return null;
    final hook = json['hook'] ?? true;
    if (hook is! bool) return null;
    switch (json['kind']) {
      case 'ssh':
        final target = json['target'];
        final cwd = json['cwd'];
        if (target is! String) return null;
        final parsed = SshTarget.parse(target);
        if (parsed == null || parsed.key != target.trim()) return null;
        if (cwd != null && (cwd is! String || !isValidRemoteCwd(cwd))) {
          return null;
        }
        return SshLaunch(parsed, remoteCwd: cwd as String?, hook: hook);
      case 'tmux':
        final session = json['session'];
        final host = json['host'];
        final create = json['create'] ?? false;
        if (session is! String || !isValidTmuxName(session)) return null;
        if (create is! bool) return null;
        SshTarget? target;
        if (host != null) {
          if (host is! String) return null;
          target = SshTarget.parse(host);
          if (target == null) return null;
        }
        return TmuxLaunch(session, host: target, create: create, hook: hook);
      default:
        return null;
    }
  }
}

final class SshLaunch extends SessionLaunch {
  const SshLaunch(this.target, {this.remoteCwd, this.hook = true});

  final SshTarget target;

  /// Where the shell starts on the server; null = its home.
  final String? remoteCwd;

  /// D10/D11: the bootstrap writes the ShellX hooks on the server.
  final bool hook;

  @override
  SshTarget get host => target;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'ssh',
    'target': target.key,
    if (remoteCwd != null) 'cwd': remoteCwd,
    'hook': hook,
  };

  @override
  SshLaunch forSplit(String? cwd) => SshLaunch(
    target,
    remoteCwd: cwd != null && isValidRemoteCwd(cwd) ? cwd : null,
    hook: hook,
  );

  @override
  SshLaunch forReconnect(String? cwd) => SshLaunch(
    target,
    remoteCwd: cwd != null && isValidRemoteCwd(cwd) ? cwd : remoteCwd,
    hook: hook,
  );

  @override
  bool operator ==(Object other) =>
      other is SshLaunch &&
      other.target == target &&
      other.remoteCwd == remoteCwd &&
      other.hook == hook;

  @override
  int get hashCode => Object.hash(target, remoteCwd, hook);

  @override
  String toString() => 'SshLaunch(…)';
}

final class TmuxLaunch extends SessionLaunch {
  const TmuxLaunch(
    this.session, {
    SshTarget? host,
    this.create = false,
    this.hook = true,
  }) : _host = host;

  final String session;
  final SshTarget? _host;

  /// `new-session -A` instead of `attach-session` (dialog "Create").
  final bool create;

  /// For a server: the bootstrap (without hook files) may run (D11).
  final bool hook;

  @override
  SshTarget? get host => _host;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'tmux',
    'session': session,
    if (_host != null) 'host': _host.key,
    if (create) 'create': true,
    'hook': hook,
  };

  @override
  SessionLaunch? forSplit(String? cwd) {
    final server = _host;
    return server == null ? null : SshLaunch(server, hook: hook);
  }

  @override
  TmuxLaunch forReconnect(String? cwd) =>
      TmuxLaunch(session, host: _host, hook: hook);

  @override
  bool operator ==(Object other) =>
      other is TmuxLaunch &&
      other.session == session &&
      other._host == _host &&
      other.create == create &&
      other.hook == hook;

  @override
  int get hashCode => Object.hash(session, _host, create, hook);

  @override
  String toString() => 'TmuxLaunch(…)';
}

/// What `SessionSummary.remote` says about a remote or tmux session.
final class SessionRemote {
  const SessionRemote({required this.launch, this.connected = false, this.home});

  final SessionLaunch launch;

  /// D17: the server answered (OSC 6973 hello), or 10 s without the hook,
  /// or at once for a local tmux client.
  final bool connected;

  /// The server's `$HOME` (OSC 6973), to show `~`.
  final String? home;

  bool get isTmux => launch is TmuxLaunch;

  String? get tmuxSession => switch (launch) {
    TmuxLaunch(:final session) => session,
    SshLaunch() => null,
  };

  String? get hostKey => launch.host?.key;

  @override
  bool operator ==(Object other) =>
      other is SessionRemote &&
      other.launch == launch &&
      other.connected == connected &&
      other.home == home;

  @override
  int get hashCode => Object.hash(launch, connected, home);

  @override
  String toString() => 'SessionRemote(connected: $connected, …)';
}
```

In `packages/shellx_agent/lib/shellx_agent.dart`, after the `src/pty/…` exports, add:

```dart
export 'src/remote/session_launch.dart';
export 'src/remote/ssh_target.dart';
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/ && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: PASS, no format changes, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/remote/ssh_target.dart packages/shellx_agent/lib/src/remote/session_launch.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/remote/ssh_target_test.dart packages/shellx_agent/test/remote/session_launch_test.dart
git commit -m "feat(agent): SshTarget and SessionLaunch — validated SSH targets, ssh/tmux launches with JSON, split and reconnect rules (A8 D4, D5, D24, D25, D29)"
```

---

### Task 2: Agent — command runner, `~/.ssh/config` hosts, tmux list, remote probe parsing (D6, D18, D25)

**Files:**
- Create: `packages/shellx_agent/lib/src/remote/command_runner.dart`, `packages/shellx_agent/lib/src/remote/ssh_config_hosts.dart`, `packages/shellx_agent/lib/src/remote/tmux_sessions.dart`, `packages/shellx_agent/lib/src/remote/remote_probe.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/remote/ssh_config_hosts_test.dart`, `packages/shellx_agent/test/remote/tmux_sessions_test.dart`, `packages/shellx_agent/test/remote/remote_probe_test.dart`, `packages/shellx_agent/test/remote/command_runner_test.dart`

**Interfaces:**
- Consumes: Task 1 `SshTarget.parse`, `isValidTmuxName`.
- Produces:
  - `final class CommandResult { const CommandResult(int exitCode, String stdout, String stderr, {bool timedOut = false}); }`; `typedef CommandRunner = Future<CommandResult> Function(String executable, List<String> arguments, {Duration timeout});`; `Future<CommandResult> runCommand(...)` (missing executable → exit 127; timeout → kill, `timedOut: true`, exit −1).
  - `SshConfigFile parseSshConfig(String text)` (`hosts`, `includes`); `Future<List<String>> readSshConfigHosts({required String home, bool windows = false, Future<String?> Function(String path)? read, Future<List<String>> Function(String directory)? list})`; `const kMaxConfigHosts = 256`.
  - `const tmuxListFormat`; `final class TmuxSessionInfo {name, windows, attached, activity}`; `List<TmuxSessionInfo> parseTmuxSessions(String)`; `sealed class TmuxListResult` = `TmuxSessions(List)` | `TmuxUnavailable()` | `TmuxListFailed(TmuxListFailure)`; `enum TmuxListFailure { auth, timeout, other }`; `TmuxListResult classifyTmuxList(CommandResult, {required bool remote})`.
  - `const String remoteProbeScript`; `Map<int, List<int>> parseRemoteProbe(String output, Iterable<int> shellPids)`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/remote/ssh_config_hosts_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('Host names without patterns, in order; Include values (D6)', () {
    final file = parseSshConfig('''
# comment
Host devbox dev-db *.corp !bastion
  HostName 10.0.0.5
  User me
host=staging
HOST "quoted name" plain
Include config.d/*
  Include ~/.ssh/extra "other file"
Host -oProxyCommand=x
''');
    expect(file.hosts, ['devbox', 'dev-db', 'staging', 'plain']);
    expect(file.includes, ['config.d/*', '~/.ssh/extra', 'other file']);
  });

  test('includes: relative to ~/.ssh, ~ expanded, globs sorted, cycles and '
      'depth bounded, missing files skipped', () async {
    final files = {
      '/h/.ssh/config': 'Host a\nInclude config.d/*.conf\nInclude ~/.ssh/loop',
      '/h/.ssh/config.d/2.conf': 'Host c',
      '/h/.ssh/config.d/1.conf': 'Host b\nInclude /abs/deep1',
      '/h/.ssh/config.d/notes.txt': 'Host ignored',
      '/h/.ssh/loop': 'Host d\nInclude config',
      '/abs/deep1': 'Host e\nInclude /abs/deep2',
      '/abs/deep2': 'Host f\nInclude /abs/deep3',
      '/abs/deep3': 'Host g\nInclude /abs/deep4',
      '/abs/deep4': 'Host h\nInclude /abs/deep5',
      '/abs/deep5': 'Host too_deep',
    };
    final hosts = await readSshConfigHosts(
      home: '/h',
      read: (path) async => files[path],
      list: (dir) async => [
        for (final p in files.keys)
          if (p.startsWith('$dir/') && !p.substring(dir.length + 1).contains('/'))
            p.substring(dir.length + 1),
      ],
    );
    // deep4 is depth 5: skipped (≤ 4 levels of Include).
    expect(hosts, ['a', 'b', 'e', 'f', 'g', 'c', 'd']);
  });

  test('at most 256 names, duplicates once', () async {
    final text = [for (var i = 0; i < 300; i++) 'Host h$i\nHost h0'].join('\n');
    final hosts = await readSshConfigHosts(
      home: '/h',
      read: (path) async => path == '/h/.ssh/config' ? text : null,
      list: (_) async => const [],
    );
    expect(hosts, hasLength(kMaxConfigHosts));
    expect(hosts.first, 'h0');
    expect(hosts.toSet(), hasLength(kMaxConfigHosts));
  });

  test('Windows paths', () async {
    final hosts = await readSshConfigHosts(
      home: r'C:\Users\me',
      windows: true,
      read: (path) async =>
          path == r'C:\Users\me\.ssh\config' ? 'Host winbox' : null,
      list: (_) async => const [],
    );
    expect(hosts, ['winbox']);
  });
}
```

`packages/shellx_agent/test/remote/tmux_sessions_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('parses tab-separated sessions and skips noise (D25)', () {
    final sessions = parseTmuxSessions(
      'Welcome to the server\n'
      'main\t3\t0\t1759831200\n'
      'my build\t1\t2\t1759744800\n'
      'bad:name\t1\t0\t1\n'
      'short\t1\n',
    );
    expect(sessions.map((s) => s.name), ['main', 'my build']);
    expect(sessions.first.windows, 3);
    expect(sessions.first.attachedElsewhere, isFalse);
    expect(sessions.last.attached, 2);
    expect(
      sessions.first.activity,
      DateTime.fromMillisecondsSinceEpoch(1759831200 * 1000),
    );
  });

  test('classifies results', () {
    expect(
      classifyTmuxList(const CommandResult(0, 'a\t1\t0\t1\n', ''), remote: false),
      isA<TmuxSessions>().having((r) => r.sessions.length, 'n', 1),
    );
    expect(
      classifyTmuxList(
        const CommandResult(1, '', 'no server running on /tmp/tmux-501/default'),
        remote: false,
      ),
      isA<TmuxSessions>().having((r) => r.sessions, 'sessions', isEmpty),
    );
    expect(
      classifyTmuxList(
        const CommandResult(1, '', 'error connecting to /tmp/tmux-1000/default (No such file or directory)'),
        remote: true,
      ),
      isA<TmuxSessions>(),
    );
    expect(
      classifyTmuxList(const CommandResult(127, '', 'sh: tmux: command not found'), remote: true),
      isA<TmuxUnavailable>(),
    );
    expect(
      classifyTmuxList(const CommandResult(255, '', 'Permission denied'), remote: true),
      isA<TmuxListFailed>().having((r) => r.reason, 'reason', TmuxListFailure.auth),
    );
    expect(
      classifyTmuxList(const CommandResult(-1, '', '', timedOut: true), remote: true),
      isA<TmuxListFailed>().having((r) => r.reason, 'reason', TmuxListFailure.timeout),
    );
    expect(
      classifyTmuxList(const CommandResult(1, '', 'something else'), remote: false),
      isA<TmuxListFailed>().having((r) => r.reason, 'reason', TmuxListFailure.other),
    );
  });
}
```

`packages/shellx_agent/test/remote/remote_probe_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  const ps = '''
#ps
    1     0
  100     1
  200   100
  201   200
  300     1
  400   300
''';

  test('Linux ss: ports of each shell\'s descendants (D18)', () {
    final ports = parseRemoteProbe(
      '$ps#ss\n'
      'State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process\n'
      'LISTEN 0      4096   127.0.0.1:8000     0.0.0.0:*    users:(("python3",pid=201,fd=3))\n'
      'LISTEN 0      511    [::]:5173          [::]:*       users:(("node",pid=201,fd=20),("node",pid=200,fd=20))\n'
      'LISTEN 0      128    0.0.0.0:22         0.0.0.0:*\n'
      'LISTEN 0      128    *:9000             *:*          users:(("x",pid=400,fd=1))\n',
      [100, 300, 999],
    );
    expect(ports, {100: [5173, 8000], 300: [9000], 999: <int>[]});
  });

  test('macOS/BSD lsof -F pn', () {
    final ports = parseRemoteProbe(
      '$ps#lsof\np201\nf3\nn*:3000\nn127.0.0.1:3000\nn[::1]:3001\np400\nn10.0.0.2:5000->10.0.0.3:41000\n',
      [100, 300],
    );
    expect(ports, {100: [3000, 3001], 300: <int>[]});
  });

  test('no listing tool, garbage, a pid cycle: no ports, no hang', () {
    expect(parseRemoteProbe('#ps\n1 1\n2 1\nnonsense\n', [1]), {1: <int>[]});
    expect(parseRemoteProbe('', [5]), {5: <int>[]});
  });

  test('the script lists processes and one listener source', () {
    expect(remoteProbeScript, contains('ps -A -o pid= -o ppid='));
    expect(remoteProbeScript, contains('ss -ltnp'));
    expect(remoteProbeScript, contains('lsof -nP -iTCP -sTCP:LISTEN -F pn'));
  });
}
```

`packages/shellx_agent/test/remote/command_runner_test.dart`:

```dart
@TestOn('mac-os || linux')
library;

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('output, exit code, missing executable, timeout', () async {
    final ok = await runCommand('/bin/sh', ['-c', 'printf out; printf err >&2; exit 3']);
    expect((ok.exitCode, ok.stdout, ok.stderr, ok.timedOut), (3, 'out', 'err', false));
    final missing = await runCommand('/nonexistent/tool', const []);
    expect(missing.exitCode, 127);
    final slow = await runCommand(
      '/bin/sh',
      ['-c', 'sleep 5'],
      timeout: const Duration(milliseconds: 200),
    );
    expect(slow.timedOut, isTrue);
    expect(slow.exitCode, -1);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/remote/command_runner.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a finished helper command printed (`ssh -G`, `ssh -O`, probes,
/// `tmux list-sessions`). Never logged (A8 D37).
final class CommandResult {
  const CommandResult(
    this.exitCode,
    this.stdout,
    this.stderr, {
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Killed after its timeout ([exitCode] is −1).
  final bool timedOut;

  @override
  String toString() => 'CommandResult($exitCode, timedOut: $timedOut)';
}

typedef CommandRunner =
    Future<CommandResult> Function(
      String executable,
      List<String> arguments, {
      Duration timeout,
    });

const int _maxOutput = 1024 * 1024;

/// Runs a helper without a shell; kills it once [timeout] passes. A
/// missing executable is exit 127, as a shell reports it. Stdin is closed
/// at once (ssh then sends EOF to the remote command).
Future<CommandResult> runCommand(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException {
    return const CommandResult(127, '', '');
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  final out = _collect(process.stdout);
  final err = _collect(process.stderr);
  var timedOut = false;
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  const grace = Duration(seconds: 1);
  return CommandResult(
    code,
    await out.timeout(grace, onTimeout: () => ''),
    await err.timeout(grace, onTimeout: () => ''),
    timedOut: timedOut,
  );
}

Future<String> _collect(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (bytes.length < _maxOutput) bytes.add(chunk);
  }
  return const Utf8Decoder(allowMalformed: true).convert(bytes.takeBytes());
}
```

`packages/shellx_agent/lib/src/remote/ssh_config_hosts.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'ssh_target.dart';

/// A8 D6.
const int kMaxConfigHosts = 256;
const int _maxConfigBytes = 1024 * 1024;
const int _maxIncludeDepth = 4;

final class SshConfigFile {
  const SshConfigFile({required this.hosts, required this.includes});

  /// `Host` names without `*`, `?`, `!` that [SshTarget.parse] accepts.
  final List<String> hosts;

  /// `Include` values as written.
  final List<String> includes;
}

final _keyword = RegExp(r'^([A-Za-z]+)(?:\s*=\s*|\s+)(.*)$');
final _pattern = RegExp(r'[*?!]');

SshConfigFile parseSshConfig(String text) {
  final hosts = <String>[];
  final includes = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = _keyword.firstMatch(line);
    if (match == null) continue;
    final values = _words(match[2]!);
    switch (match[1]!.toLowerCase()) {
      case 'host':
        for (final value in values) {
          if (_pattern.hasMatch(value)) continue;
          if (SshTarget.parse(value) != null) hosts.add(value);
        }
      case 'include':
        includes.addAll(values);
    }
  }
  return SshConfigFile(hosts: hosts, includes: includes);
}

/// Whitespace-separated words; `"…"` keeps spaces (ssh_config(5)).
List<String> _words(String text) {
  final words = <String>[];
  final current = StringBuffer();
  var quoted = false;
  var started = false;
  for (final ch in text.split('')) {
    if (ch == '"') {
      quoted = !quoted;
      started = true;
      continue;
    }
    if (!quoted && (ch == ' ' || ch == '\t')) {
      if (started) {
        words.add(current.toString());
        current.clear();
        started = false;
      }
      continue;
    }
    current.write(ch);
    started = true;
  }
  if (started) words.add(current.toString());
  return words;
}

/// Every usable `Host` name of `~/.ssh/config` and what it includes, in
/// order, once each, at most [kMaxConfigHosts]. Unreadable, missing or
/// oversized files are skipped silently (never logged: paths are private).
Future<List<String>> readSshConfigHosts({
  required String home,
  bool windows = false,
  Future<String?> Function(String path)? read,
  Future<List<String>> Function(String directory)? list,
}) async {
  final sep = windows ? r'\' : '/';
  final sshDir = '$home$sep.ssh';
  final readFile = read ?? _readSmallFile;
  final listDir = list ?? _listNames;
  final hosts = <String>{};
  final seen = <String>{};

  Future<void> visit(String path, int depth) async {
    if (depth > _maxIncludeDepth || hosts.length >= kMaxConfigHosts) return;
    if (!seen.add(path)) return;
    final text = await readFile(path);
    if (text == null) return;
    final file = parseSshConfig(text);
    for (final host in file.hosts) {
      if (hosts.length >= kMaxConfigHosts) return;
      hosts.add(host);
    }
    for (final pattern in file.includes) {
      final paths = await _expand(
        pattern,
        home: home,
        sshDir: sshDir,
        sep: sep,
        list: listDir,
      );
      for (final included in paths) {
        await visit(included, depth + 1);
      }
    }
  }

  await visit('$sshDir${sep}config', 0);
  return hosts.toList();
}

Future<List<String>> _expand(
  String pattern, {
  required String home,
  required String sshDir,
  required String sep,
  required Future<List<String>> Function(String directory) list,
}) async {
  var path = pattern;
  if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
    path = '$home${path.substring(1)}';
  }
  final absolute =
      path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  if (!absolute) path = '$sshDir$sep$path';
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  if (cut < 0) return const [];
  final directory = path.substring(0, cut);
  final name = path.substring(cut + 1);
  if (!name.contains(RegExp(r'[*?]'))) return [path];
  final glob = RegExp(
    '^${name.split('').map((c) => switch (c) {
      '*' => '.*',
      '?' => '.',
      _ => RegExp.escape(c),
    }).join()}\$',
  );
  final names = (await list(directory)).where(glob.hasMatch).toList()..sort();
  return [for (final n in names) '$directory${path[cut]}$n'];
}

Future<String?> _readSmallFile(String path) async {
  try {
    final file = File(path);
    if (await file.length() > _maxConfigBytes) return null;
    return await file.readAsString();
  } on Object {
    return null;
  }
}

Future<List<String>> _listNames(String directory) async {
  try {
    return [
      await for (final entry in Directory(directory).list())
        if (entry is File) entry.uri.pathSegments.last,
    ];
  } on Object {
    return const [];
  }
}
```

`packages/shellx_agent/lib/src/remote/tmux_sessions.dart`:

```dart
import 'command_runner.dart';
import 'session_launch.dart' show isValidTmuxName;

/// A8 D25: one line per session, tab-separated.
const String tmuxListFormat =
    '#{session_name}\t#{session_windows}\t#{session_attached}\t'
    '#{session_activity}';

final class TmuxSessionInfo {
  const TmuxSessionInfo({
    required this.name,
    required this.windows,
    required this.attached,
    this.activity,
  });

  final String name;
  final int windows;

  /// Clients attached right now (another terminal, another computer).
  final int attached;
  final DateTime? activity;

  bool get attachedElsewhere => attached > 0;

  @override
  bool operator ==(Object other) =>
      other is TmuxSessionInfo &&
      other.name == name &&
      other.windows == windows &&
      other.attached == attached &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(name, windows, attached, activity);

  @override
  String toString() => 'TmuxSessionInfo(…)';
}

/// Lines of [tmuxListFormat]; anything else (a login banner) is skipped.
List<TmuxSessionInfo> parseTmuxSessions(String stdout) => [
  for (final line in stdout.split('\n')) ?_parse(line.replaceAll('\r', '')),
];

TmuxSessionInfo? _parse(String line) {
  final parts = line.split('\t');
  if (parts.length != 4 || !isValidTmuxName(parts[0])) return null;
  final windows = int.tryParse(parts[1]);
  final attached = int.tryParse(parts[2]);
  final activity = int.tryParse(parts[3]);
  if (windows == null || attached == null) return null;
  return TmuxSessionInfo(
    name: parts[0],
    windows: windows,
    attached: attached,
    activity: activity == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(activity * 1000),
  );
}

sealed class TmuxListResult {
  const TmuxListResult();
}

final class TmuxSessions extends TmuxListResult {
  const TmuxSessions(this.sessions);
  final List<TmuxSessionInfo> sessions;
}

final class TmuxUnavailable extends TmuxListResult {
  const TmuxUnavailable();
}

enum TmuxListFailure { auth, timeout, other }

final class TmuxListFailed extends TmuxListResult {
  const TmuxListFailed(this.reason);
  final TmuxListFailure reason;
}

/// D25: "no server running" is an empty list, 127 / "not found" means no
/// tmux, 255 over ssh means the server wants a password (BatchMode).
TmuxListResult classifyTmuxList(CommandResult r, {required bool remote}) {
  if (r.timedOut) return const TmuxListFailed(TmuxListFailure.timeout);
  if (r.exitCode == 0) return TmuxSessions(parseTmuxSessions(r.stdout));
  if (remote && r.exitCode == 255) {
    return const TmuxListFailed(TmuxListFailure.auth);
  }
  final err = r.stderr.toLowerCase();
  if (err.contains('no server running') ||
      err.contains('error connecting to') ||
      err.contains('no sessions')) {
    return const TmuxSessions([]);
  }
  if (r.exitCode == 127 || err.contains('not found')) {
    return const TmuxUnavailable();
  }
  return const TmuxListFailed(TmuxListFailure.other);
}
```

`packages/shellx_agent/lib/src/remote/remote_probe.dart`:

```dart
import 'dart:collection';

/// A8 D18: processes and TCP listeners of the server, in one round trip.
/// `ss` (Linux) shows the pids of the user's own sockets; `lsof` (macOS,
/// BSD) the same. Run by `remoteExecCommand` under `/bin/sh`.
const String remoteProbeScript = r'''
PATH="$PATH:/usr/sbin:/sbin"; export PATH
echo '#ps'
ps -A -o pid= -o ppid= 2>/dev/null
if command -v ss >/dev/null 2>&1; then
  echo '#ss'
  ss -ltnp 2>/dev/null
elif command -v lsof >/dev/null 2>&1; then
  echo '#lsof'
  lsof -nP -iTCP -sTCP:LISTEN -F pn 2>/dev/null
fi
''';

final _spaces = RegExp(r'\s+');
final _pid = RegExp(r'pid=(\d+)');

/// Shell pid → sorted listening ports of that shell and its descendants;
/// every pid of [shellPids] gets an entry (empty when none).
Map<int, List<int>> parseRemoteProbe(String output, Iterable<int> shellPids) {
  final children = <int, List<int>>{};
  final listening = <int, Set<int>>{};
  var section = '';
  int? lsofPid;
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      section = line;
      lsofPid = null;
      continue;
    }
    switch (section) {
      case '#ps':
        final parts = line.split(_spaces);
        if (parts.length != 2) continue;
        final pid = int.tryParse(parts[0]);
        final parent = int.tryParse(parts[1]);
        if (pid == null || parent == null || pid == parent) continue;
        (children[parent] ??= []).add(pid);
      case '#ss':
        if (!line.startsWith('LISTEN')) continue;
        final cols = line.split(_spaces);
        if (cols.length < 5) continue;
        final port = _portOf(cols[3]);
        if (port == null) continue;
        for (final m in _pid.allMatches(line)) {
          (listening[int.parse(m[1]!)] ??= {}).add(port);
        }
      case '#lsof':
        if (line.startsWith('p')) {
          lsofPid = int.tryParse(line.substring(1));
        } else if (line.startsWith('n') && lsofPid != null) {
          if (line.contains('->')) continue;
          final port = _portOf(line.substring(1));
          if (port != null) (listening[lsofPid] ??= {}).add(port);
        }
    }
  }
  final result = <int, List<int>>{};
  for (final shell in shellPids) {
    final ports = SplayTreeSet<int>();
    final seen = <int>{shell};
    final queue = Queue<int>()..add(shell);
    while (queue.isNotEmpty && seen.length <= 100000) {
      final pid = queue.removeFirst();
      ports.addAll(listening[pid] ?? const {});
      for (final child in children[pid] ?? const <int>[]) {
        if (seen.add(child)) queue.add(child);
      }
    }
    result[shell] = List.unmodifiable(ports);
  }
  return result;
}

int? _portOf(String address) {
  final colon = address.lastIndexOf(':');
  if (colon < 0) return null;
  final port = int.tryParse(address.substring(colon + 1));
  return port != null && port > 0 && port < 65536 ? port : null;
}
```

Add the exports to `packages/shellx_agent/lib/shellx_agent.dart`:

```dart
export 'src/remote/command_runner.dart';
export 'src/remote/remote_probe.dart';
export 'src/remote/ssh_config_hosts.dart';
export 'src/remote/tmux_sessions.dart';
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/ && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/remote/command_runner.dart packages/shellx_agent/lib/src/remote/ssh_config_hosts.dart packages/shellx_agent/lib/src/remote/tmux_sessions.dart packages/shellx_agent/lib/src/remote/remote_probe.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/remote/ssh_config_hosts_test.dart packages/shellx_agent/test/remote/tmux_sessions_test.dart packages/shellx_agent/test/remote/remote_probe_test.dart packages/shellx_agent/test/remote/command_runner_test.dart
git commit -m "feat(agent): ssh config hosts, tmux session list, remote port probe parser and a timed command runner (A8 D6, D18, D25)"
```

---

### Task 3: Agent — remote bootstrap, remote hook add-on, ssh/tmux command lines (D3, D10–D13, D15, D25)

**Files:**
- Create: `packages/shellx_agent/lib/src/remote/remote_bootstrap.dart`, `packages/shellx_agent/lib/src/remote/ssh_command.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/remote/remote_bootstrap_test.dart`, `packages/shellx_agent/test/remote/remote_bootstrap_run_test.dart`, `packages/shellx_agent/test/remote/remote_hook_branch_test.dart`, `packages/shellx_agent/test/remote/ssh_command_test.dart`

**Interfaces:**
- Consumes: Task 1 `SessionLaunch`, `isPlainTmuxName`; Task 2 `tmuxListFormat`; `zshHookEnv`, `bashHookRc` (unchanged); `ShellCommand`.
- Produces:
  - `String shQuote(String value)`.
  - `const String remoteMetaFunction`; `const String remoteZshHook` (= `zshHookEnv` + add-on), `const String remoteBashHook` (= `bashHookRc` + add-on); `final String remoteHookVersion` (12 hex).
  - `final class RemoteBootstrap { const RemoteBootstrap({String? cwd, String? tmuxSession, bool tmuxCreate = false, bool writeHooks = true}); }`; `String remoteBootstrapScript(RemoteBootstrap)`; `String remoteExecCommand(String script)`; `String remoteTmuxListScript()`; `const int kMaxBootstrapBytes = 24 * 1024`.
  - `Future<String?> sshPathFor({required String operatingSystem, required Map<String, String> environment, Future<bool> Function(String)? fileExists})`, `Future<String?> tmuxPathFor(...)`.
  - `final class SshCommandOptions { const SshCommandOptions({required String sshPath, String? controlPath, bool keepalive = true}); }`; `List<String> controlOptions(String? controlPath, {required String master})`; `ShellCommand buildSshCommand(SessionLaunch launch, SshCommandOptions options)` (throws `ArgumentError` for a local launch or a hookless non-plain tmux name); `ShellCommand buildLocalTmuxCommand(TmuxLaunch launch, String tmuxPath)`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/remote/remote_bootstrap_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_agent/src/pty/shell_hook_scripts.dart';
import 'package:test/test.dart';

String _decode(String command) {
  final b64 = RegExp(r'b=([A-Za-z0-9+/=]+);').firstMatch(command)![1]!;
  return utf8.decode(base64.decode(b64));
}

void main() {
  test('the outer command is safe in every login shell (D10)', () {
    final command = remoteExecCommand(
      remoteBootstrapScript(const RemoteBootstrap(cwd: "/srv/it's here")),
    );
    expect(command, startsWith("/bin/sh -c 'eval "));
    expect(command, endsWith("'"));
    final inner = command.substring("/bin/sh -c '".length, command.length - 1);
    expect(inner, isNot(contains("'")));
    expect(command, isNot(contains('!')));
    expect(command.codeUnits.every((c) => c >= 0x20 && c < 0x7F), isTrue);
    expect(command.length, lessThan(kMaxBootstrapBytes + 400));
  });

  test('the hooks are the local hooks byte for byte, plus the add-on', () {
    expect(remoteZshHook, startsWith(zshHookEnv));
    expect(remoteBashHook, startsWith(bashHookRc));
    expect(remoteZshHook, contains('__shellx_remote_meta'));
    expect(remoteBashHook, contains('__shellx_remote_meta'));
    expect(remoteHookVersion, matches(RegExp(r'^[0-9a-f]{12}$')));
    final script = remoteBootstrapScript(const RemoteBootstrap());
    expect(script, contains(zshHookEnv));
    expect(script, contains(bashHookRc));
    expect(zshHookEnv, isNot(contains('__SHELLX_EOF_')));
    expect(bashHookRc, isNot(contains('__SHELLX_EOF_')));
  });

  test('user text only through shQuote and the environment (D38b)', () {
    final script = remoteBootstrapScript(
      const RemoteBootstrap(cwd: r"/x'; rm -rf ~ #$(id)"),
    );
    expect(script, contains(shQuote(r"/x'; rm -rf ~ #$(id)")));
    final tmux = remoteBootstrapScript(
      const RemoteBootstrap(tmuxSession: r'a $(id) "b"', writeHooks: false),
    );
    expect(tmux, contains("SHELLX_TMUX=${shQuote(r'a $(id) "b"')}"));
    expect(tmux, contains(r'attach-session -t "=$SHELLX_TMUX"'));
    expect(tmux, isNot(contains('__SHELLX_EOF_ZSH__')));
    final create = remoteBootstrapScript(
      const RemoteBootstrap(tmuxSession: 'main', tmuxCreate: true, writeHooks: false),
    );
    expect(create, contains(r'new-session -A -s "$SHELLX_TMUX"'));
    expect(_decode(remoteExecCommand(tmux)), tmux);
  });

  test('~ folders expand on the server', () {
    expect(
      remoteBootstrapScript(const RemoteBootstrap(cwd: '~/w x')),
      contains('cd -- "\$HOME"/${shQuote('w x')} 2>/dev/null || cd'),
    );
    expect(remoteBootstrapScript(const RemoteBootstrap(cwd: '~')), contains('\ncd\n'));
  });

  test('every script parses with sh -n', () async {
    for (final b in const [
      RemoteBootstrap(),
      RemoteBootstrap(cwd: '/a b'),
      RemoteBootstrap(tmuxSession: 'main', writeHooks: false),
    ]) {
      final r = await Process.run('/bin/sh', ['-n', '-c', remoteBootstrapScript(b)]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }
    final r = await Process.run('/bin/sh', ['-n', '-c', remoteTmuxListScript()]);
    expect(r.exitCode, 0);
  }, testOn: 'mac-os || linux');

  test('shQuote survives sh', () async {
    for (final value in ["it's", r'$HOME', 'a\nb', '', '"\\']) {
      final r = await Process.run('/bin/sh', ['-c', 'printf %s ${shQuote(value)}']);
      expect(r.stdout, value);
    }
  }, testOn: 'mac-os || linux');
}
```

`packages/shellx_agent/test/remote/remote_bootstrap_run_test.dart` (runs the real script under `/bin/sh`, with a fake login shell that prints what it was given):

```dart
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

late Directory temp;
late String home;

/// A fake login shell named [name] that prints its arguments, ZDOTDIR,
/// SHELLX_TMUX and its folder, so the script's `exec` can be checked.
String fakeShell(String name) {
  final bin = Directory('${temp.path}/bin')..createSync(recursive: true);
  final file = File('${bin.path}/$name')
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'printf "ARGS:%s\\n" "\$*"\n'
      'printf "ZDOTDIR:%s\\n" "\${ZDOTDIR-unset}"\n'
      'printf "USERZ:%s\\n" "\${SHELLX_USER_ZDOTDIR-unset}"\n'
      'printf "BASHLOGIN:%s\\n" "\${SHELLX_BASH_LOGIN-unset}"\n'
      'printf "TMUX:%s\\n" "\${SHELLX_TMUX-unset}"\n'
      'printf "REMOTE:%s\\n" "\${SHELLX_REMOTE-unset}"\n'
      'printf "PWD:%s\\n" "\$(pwd -P)"\n',
    );
  Process.runSync('/bin/chmod', ['755', file.path]);
  return file.path;
}

Future<ProcessResult> run(RemoteBootstrap b, String shell, {Map<String, String>? env}) =>
    Process.run(
      '/bin/sh',
      ['-c', remoteExecCommand(remoteBootstrapScript(b))],
      environment: {'HOME': home, 'SHELL': shell, 'PATH': '/usr/bin:/bin', ...?env},
      includeParentEnvironment: false,
    );

void main() {
  setUp(() {
    temp = Directory.systemTemp.createTempSync('shellx-a8-boot-');
    home = (Directory('${temp.path}/home')..createSync()).resolveSymbolicLinksSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('zsh: hello, pid, home, hooks written private, ZDOTDIR restored '
      'through SHELLX_USER_ZDOTDIR, login shell', () async {
    final shell = fakeShell('zsh');
    final r = await run(const RemoteBootstrap(), shell, env: {'ZDOTDIR': '/u/z'});
    final out = r.stdout as String;
    expect(out, startsWith('\x1b]6973;hello=1\x07\x1b]6973;pid='));
    expect(out, contains('\x1b]6973;home=$home\x07'));
    final dir = '$home/.cache/shellx/remote-$remoteHookVersion';
    expect(out, contains('ARGS:-l\n'));
    expect(out, contains('ZDOTDIR:$dir/zsh\n'));
    expect(out, contains('USERZ:/u/z\n'));
    expect(out, contains('REMOTE:1\n'));
    expect(File('$dir/zsh/.zshenv').readAsStringSync(), remoteZshHook);
    expect(File('$dir/bash/rc.bash').readAsStringSync(), remoteBashHook);
    expect(File('$dir/.ok').existsSync(), isTrue);
    final mode = Process.runSync('/bin/ls', ['-ld', '$home/.cache/shellx', '$dir/zsh/.zshenv']).stdout as String;
    expect(mode, contains('drwx------'));
    expect(mode, contains('-rw-------'));
    expect(Directory('$dir/zsh').listSync().map((e) => e.path.split('/').last), ['.zshenv']);
  });

  test('bash: --rcfile of the hook, login files requested', () async {
    final r = await run(const RemoteBootstrap(cwd: '/'), fakeShell('bash'));
    final dir = '$home/.cache/shellx/remote-$remoteHookVersion';
    expect(r.stdout, contains('ARGS:--rcfile $dir/bash/rc.bash -i\n'));
    expect(r.stdout, contains('BASHLOGIN:1\n'));
    expect(r.stdout, contains('PWD:/\n'));
  });

  test('fish and other shells: plain login shell, still hello', () async {
    final r = await run(const RemoteBootstrap(), fakeShell('fish'));
    expect(r.stdout, contains('\x1b]6973;hello=1\x07'));
    expect(r.stdout, contains('ARGS:-l\n'));
    expect(r.stdout, contains('ZDOTDIR:unset\n'));
  });

  test('a read-only home: no hooks, still a login shell', () async {
    Process.runSync('/bin/chmod', ['555', home]);
    addTearDown(() => Process.runSync('/bin/chmod', ['755', home]));
    final r = await run(const RemoteBootstrap(), fakeShell('zsh'));
    expect(r.stdout, contains('ARGS:-l\n'));
    expect(r.stdout, contains('ZDOTDIR:unset\n'));
  });

  test('.ok without its files is not trusted', () async {
    final dir = Directory('$home/.cache/shellx/remote-$remoteHookVersion')..createSync(recursive: true);
    File('${dir.path}/.ok').writeAsStringSync('');
    final r = await run(const RemoteBootstrap(), fakeShell('zsh'));
    expect(r.stdout, contains('ZDOTDIR:${dir.path}/zsh\n'));
    expect(File('${dir.path}/zsh/.zshenv').existsSync(), isTrue);
  });

  test('cwd: missing folder → home; ~/ expands', () async {
    Directory('$home/w x').createSync();
    final a = await run(const RemoteBootstrap(cwd: '/does/not/exist'), fakeShell('zsh'));
    expect(a.stdout, contains('PWD:$home\n'));
    final b = await run(const RemoteBootstrap(cwd: '~/w x'), fakeShell('zsh'));
    expect(b.stdout, contains('PWD:$home/w x\n'));
  });

  test('tmux: the login shell runs tmux with the name from the environment', () async {
    final r = await run(
      const RemoteBootstrap(tmuxSession: r'a $(id)', writeHooks: false),
      fakeShell('zsh'),
    );
    expect(r.stdout, contains(r'ARGS:-l -c exec tmux attach-session -t "=$SHELLX_TMUX"'));
    expect(r.stdout, contains(r'TMUX:a $(id)'));
    expect(Directory('$home/.cache/shellx').existsSync(), isFalse);
  });
}
```

`packages/shellx_agent/test/remote/remote_hook_branch_test.dart` (real bash and zsh with the remote hook; branch from `.git/HEAD` without git):

```dart
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart' show FixedShellResolver;

void main() {
  for (final kind in ['bash', 'zsh']) {
    final exe = '/bin/$kind';
    test('$kind: OSC 6973 branch at the first prompt, on cd, on a worktree '
        '.git file, once per change (A8 D15)', () async {
      final temp = Directory.systemTemp.createTempSync('shellx-a8-branch-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final home = Directory('${temp.path}/home')..createSync();
      final repo = Directory('${temp.path}/repo/.git')..createSync(recursive: true);
      File('${repo.path}/HEAD').writeAsStringSync('ref: refs/heads/feat/x\n');
      final wt = Directory('${temp.path}/wt/sub')..createSync(recursive: true);
      Directory('${temp.path}/gitdirs/wt').createSync(recursive: true);
      File('${temp.path}/gitdirs/wt/HEAD').writeAsStringSync('0123456789abcdef\n');
      File('${temp.path}/wt/.git').writeAsStringSync('gitdir: ${temp.path}/gitdirs/wt\n');
      final hooks = Directory('${temp.path}/hooks')..createSync();
      final ShellCommand command;
      final env = <String, String>{
        'HOME': home.path,
        'PATH': '/usr/bin:/bin',
        'LANG': 'en_US.UTF-8',
        'BASH_SILENCE_DEPRECATION_WARNING': '1',
      };
      if (kind == 'bash') {
        File('${hooks.path}/rc.bash').writeAsStringSync(remoteBashHook);
        command = ShellCommand(executable: exe, arguments: ['--rcfile', '${hooks.path}/rc.bash', '-i'], name: 'bash');
      } else {
        File('${hooks.path}/.zshenv').writeAsStringSync(remoteZshHook);
        env['ZDOTDIR'] = hooks.path;
        command = ShellCommand(executable: exe, arguments: ['-i'], name: 'zsh');
      }
      final manager = SessionManager(
        ptyFactory: const ProcessPtyFactory(),
        shellResolver: FixedShellResolver(command),
        homeDirectory: home.path,
        baseEnvironment: env,
      );
      addTearDown(manager.closeAll);
      final view = manager.view(await manager.open(cols: 100, rows: 30));
      final text = StringBuffer();
      final sub = view.output.listen((d) => text.write(utf8.decode(d, allowMalformed: true)));
      addTearDown(sub.cancel);
      Future<void> waitFor(String needle, {int from = 0}) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!text.toString().substring(from).contains(needle)) {
          if (DateTime.now().isAfter(deadline)) fail('no ${jsonEncode(needle)}');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await waitFor('\x1b]6973;branch=\x07'); // home: not a repository
      var mark = text.length;
      view.write(utf8.encode("cd '${temp.path}/repo'\n"));
      await waitFor('\x1b]6973;branch=feat/x\x07', from: mark);
      mark = text.length;
      view.write(utf8.encode('true\n'));
      await waitFor('\x1b]7;', from: mark);
      expect(text.toString().substring(mark), isNot(contains('6973;branch')));
      mark = text.length;
      view.write(utf8.encode("cd '${wt.path}'\n"));
      await waitFor('\x1b]6973;branch=0123456\x07', from: mark);
    });
  }
}
```

`packages/shellx_agent/test/remote/ssh_command_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final devbox = SshTarget.parse('me@devbox:2222')!;
  const mac = SshCommandOptions(sshPath: '/usr/bin/ssh', controlPath: '/tmp/shellx-ssh-501/%C');

  test('an SSH pane: -t, control, keepalive, destination, one remote command (D8, D12, D13)', () {
    final c = buildSshCommand(SshLaunch(devbox, remoteCwd: '/srv'), mac);
    expect(c.executable, '/usr/bin/ssh');
    expect(c.name, 'ssh');
    expect(c.arguments.sublist(0, c.arguments.length - 1), [
      '-t',
      '-o', 'ControlMaster=auto',
      '-o', 'ControlPath=/tmp/shellx-ssh-501/%C',
      '-o', 'ControlPersist=60',
      '-o', 'ServerAliveInterval=15',
      '-o', 'ServerAliveCountMax=3',
      '-l', 'me', '-p', '2222', '--', 'devbox',
    ]);
    expect(c.arguments.last, startsWith("/bin/sh -c 'eval"));
  });

  test('Windows / no control, keepalive configured, no hook', () {
    final c = buildSshCommand(
      SshLaunch(devbox, hook: false),
      const SshCommandOptions(sshPath: r'C:\Windows\System32\OpenSSH\ssh.exe', keepalive: false),
    );
    expect(c.arguments, ['-t', '-l', 'me', '-p', '2222', '--', 'devbox']);
  });

  test('tmux on a server: bootstrap without hook files; hookless needs a plain name', () {
    final withHook = buildSshCommand(TmuxLaunch('my s', host: devbox), mac);
    expect(withHook.arguments.last, startsWith("/bin/sh -c 'eval"));
    final plain = buildSshCommand(TmuxLaunch('main', host: devbox, hook: false), mac);
    expect(plain.arguments.last, 'tmux attach-session -t main');
    final create = buildSshCommand(TmuxLaunch('main', host: devbox, hook: false, create: true), mac);
    expect(create.arguments.last, 'tmux new-session -A -s main');
    expect(
      () => buildSshCommand(TmuxLaunch('my s', host: devbox, hook: false), mac),
      throwsArgumentError,
    );
    expect(() => buildSshCommand(const TmuxLaunch('main'), mac), throwsArgumentError);
  });

  test('local tmux: argv, exact name, no shell', () {
    expect(
      buildLocalTmuxCommand(const TmuxLaunch('my s'), '/opt/homebrew/bin/tmux').arguments,
      ['attach-session', '-t', '=my s'],
    );
    expect(
      buildLocalTmuxCommand(const TmuxLaunch('n', create: true), '/usr/bin/tmux').arguments,
      ['new-session', '-A', '-s', 'n'],
    );
  });

  test('tool paths (D3, D25)', () async {
    Future<bool> only(Set<String> files, String p) async => files.contains(p);
    expect(await sshPathFor(operatingSystem: 'macos', environment: const {'PATH': '/opt/homebrew/bin'},
        fileExists: (p) => only({'/usr/bin/ssh', '/opt/homebrew/bin/ssh'}, p)), '/usr/bin/ssh');
    expect(await sshPathFor(operatingSystem: 'windows', environment: const {'SystemRoot': r'C:\Windows', 'Path': r'D:\Git\usr\bin'},
        fileExists: (p) => only({r'D:\Git\usr\bin\ssh.exe'}, p)), r'D:\Git\usr\bin\ssh.exe');
    expect(await sshPathFor(operatingSystem: 'windows', environment: const {'SystemRoot': r'C:\Windows'},
        fileExists: (p) => only({r'C:\Windows\System32\OpenSSH\ssh.exe'}, p)), r'C:\Windows\System32\OpenSSH\ssh.exe');
    expect(await sshPathFor(operatingSystem: 'macos', environment: const {}, fileExists: (_) async => false), isNull);
    expect(await tmuxPathFor(operatingSystem: 'macos', environment: const {'PATH': '/x'},
        fileExists: (p) => only({'/usr/local/bin/tmux', '/x/tmux'}, p)), '/usr/local/bin/tmux');
    expect(await tmuxPathFor(operatingSystem: 'windows', environment: const {}, fileExists: (_) async => true), isNull);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/remote_bootstrap_test.dart test/remote/remote_bootstrap_run_test.dart test/remote/remote_hook_branch_test.dart test/remote/ssh_command_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement `remote_bootstrap.dart`**

```dart
import 'dart:convert';

import '../pty/shell_hook_scripts.dart';
import 'tmux_sessions.dart' show tmuxListFormat;

/// A8 D39.
const int kMaxBootstrapBytes = 24 * 1024;

/// One sh word holding exactly [value].
String shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// D15: the branch of `$PWD` from `.git/HEAD` (or a `.git` file's
/// `gitdir:`), with builtins only — no fork, no git. Printed as
/// `OSC 6973;branch=` only when it changed ('' = not a repository).
/// The same text runs in bash and zsh.
const String remoteMetaFunction = r'''
__shellx_remote_meta() {
  local d="$PWD" h= b= g=
  while :; do
    if [ -f "$d/.git/HEAD" ]; then h="$d/.git/HEAD"; break; fi
    if [ -f "$d/.git" ]; then
      IFS= read -r g < "$d/.git"
      g="${g#gitdir: }"
      case "$g" in /*) ;; *) g="$d/$g" ;; esac
      if [ -f "$g/HEAD" ]; then h="$g/HEAD"; fi
      break
    fi
    if [ -z "$d" ] || [ "$d" = / ]; then break; fi
    d="${d%/*}"
  done
  if [ -n "$h" ]; then
    IFS= read -r b < "$h"
    case "$b" in
      "ref: refs/heads/"*) b="${b#ref: refs/heads/}" ;;
      *) b="${b:0:7}" ;;
    esac
  fi
  if [ -z "${__shellx_branch_set-}" ] || [ "$b" != "$__shellx_branch" ]; then
    __shellx_branch_set=1
    __shellx_branch="$b"
    builtin printf '\033]6973;branch=%s\007' "$b"
  fi
}
''';

/// zsh: wraps the hook's `__shellx_osc7` (called at every prompt) once.
const String _zshAddon =
    r'''
# ShellX remote add-on (A8): branch of the server's folder.
if [[ -o interactive ]] && (( ${+functions[__shellx_osc7]} )) && (( ! ${+functions[__shellx_osc7_base]} )); then
''' +
    remoteMetaFunction +
    r'''
  functions[__shellx_osc7_base]=${functions[__shellx_osc7]}
  __shellx_osc7() { __shellx_osc7_base; __shellx_remote_meta; }
fi
''';

/// bash: the same wrap through `declare -f` (one fork, at startup only).
const String _bashAddon =
    r'''
# ShellX remote add-on (A8): branch of the server's folder.
if [[ $- == *i* ]] && declare -F __shellx_osc7 >/dev/null && ! declare -F __shellx_osc7_base >/dev/null; then
''' +
    remoteMetaFunction +
    r'''
  __shellx_def=$(declare -f __shellx_osc7)
  eval "__shellx_osc7_base${__shellx_def#__shellx_osc7}"
  unset __shellx_def
  __shellx_osc7() { __shellx_osc7_base; __shellx_remote_meta; }
fi
''';

/// The files written on the server (D10): the local hooks unchanged, then
/// the add-on.
const String remoteZshHook = '$zshHookEnv\n$_zshAddon';
const String remoteBashHook = '$bashHookRc\n$_bashAddon';

/// First 12 hex digits of FNV-1a 64 over both files: a new ShellX with new
/// hooks writes a new folder; an unchanged one reuses the old.
final String remoteHookVersion = _fnv64Hex('$remoteZshHook\u0000$remoteBashHook');

String _fnv64Hex(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash *= 0x100000001b3; // wraps at 64 bits on the VM
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0').substring(0, 12);
}

final class RemoteBootstrap {
  const RemoteBootstrap({
    this.cwd,
    this.tmuxSession,
    this.tmuxCreate = false,
    this.writeHooks = true,
  });

  /// `/…`, `~` or `~/…` (checked by the caller with `isValidRemoteCwd`).
  final String? cwd;

  /// Non-null: `exec tmux` instead of the login shell (D25).
  final String? tmuxSession;
  final bool tmuxCreate;
  final bool writeHooks;
}

const String _prelude = r'''
printf '\033]6973;hello=1\007'
printf '\033]6973;pid=%s\007' "$$"
case "$HOME" in
  /*[![:print:]]*) ;;
  /*) printf '\033]6973;home=%s\007' "$HOME" ;;
esac
SHELLX=1; SHELLX_REMOTE=1; export SHELLX SHELLX_REMOTE
s=${SHELL:-/bin/sh}
d=
''';

const String _hooksTemplate = r'''
c="${XDG_CACHE_HOME:-$HOME/.cache}/shellx/remote-@VERSION@"
if [ -f "$c/.ok" ] && [ -f "$c/zsh/.zshenv" ] && [ -f "$c/bash/rc.bash" ]; then
  d=$c
elif (umask 077 && mkdir -p "$c/zsh" "$c/bash") 2>/dev/null; then
  o=$(umask)
  umask 077
  w=1
  cat >"$c/zsh/.zshenv.$$" <<'__SHELLX_EOF_ZSH__' || w=
@ZSH@
__SHELLX_EOF_ZSH__
  cat >"$c/bash/rc.bash.$$" <<'__SHELLX_EOF_BASH__' || w=
@BASH@
__SHELLX_EOF_BASH__
  if [ -n "$w" ] && mv -f "$c/zsh/.zshenv.$$" "$c/zsh/.zshenv" && mv -f "$c/bash/rc.bash.$$" "$c/bash/rc.bash" && : >"$c/.ok"; then
    d=$c
  else
    rm -f "$c/zsh/.zshenv.$$" "$c/bash/rc.bash.$$" 2>/dev/null
  fi
  umask "$o"
fi
''';

const String _shellExec = r'''
case "${s##*/}" in
  zsh)
    if [ -n "$d" ]; then
      if [ -n "${ZDOTDIR+x}" ]; then SHELLX_USER_ZDOTDIR=$ZDOTDIR; export SHELLX_USER_ZDOTDIR; fi
      ZDOTDIR="$d/zsh"; export ZDOTDIR
    fi
    exec "$s" -l ;;
  bash)
    if [ -n "$d" ]; then SHELLX_BASH_LOGIN=1; export SHELLX_BASH_LOGIN; exec "$s" --rcfile "$d/bash/rc.bash" -i; fi
    exec "$s" -l ;;
  *) exec "$s" -l ;;
esac
''';

const String _tmuxExec = r'''
case "${s##*/}" in
  bash|zsh|sh|dash|ksh|mksh|fish) exec "$s" -l -c 'exec tmux @TMUX@' ;;
  *) PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"; export PATH; exec tmux @TMUX@ ;;
esac
''';

/// D10: the POSIX sh text the server runs. Only [RemoteBootstrap.cwd] and
/// [RemoteBootstrap.tmuxSession] come from the user, through [shQuote].
String remoteBootstrapScript(RemoteBootstrap b) {
  final out = StringBuffer(_prelude);
  if (b.writeHooks && b.tmuxSession == null) {
    out.write(
      _hooksTemplate
          .replaceAll('@VERSION@', remoteHookVersion)
          // Both hooks end with a newline: the files hold them byte for byte.
          .replaceAll('@ZSH@\n', remoteZshHook)
          .replaceAll('@BASH@\n', remoteBashHook),
    );
  }
  final cwd = b.cwd;
  if (cwd != null) {
    if (cwd == '~') {
      out.write('cd\n');
    } else if (cwd.startsWith('~/')) {
      out.write('cd -- "\$HOME"/${shQuote(cwd.substring(2))} 2>/dev/null || cd\n');
    } else {
      out.write('cd -- ${shQuote(cwd)} 2>/dev/null || cd\n');
    }
  }
  final session = b.tmuxSession;
  if (session == null) {
    out.write(_shellExec);
  } else {
    out
      ..write('SHELLX_TMUX=${shQuote(session)}; export SHELLX_TMUX\n')
      ..write(
        _tmuxExec.replaceAll(
          '@TMUX@',
          b.tmuxCreate
              ? r'new-session -A -s "$SHELLX_TMUX"'
              : r'attach-session -t "=$SHELLX_TMUX"',
        ),
      );
  }
  return out.toString();
}

/// D25: `tmux list-sessions` through the login shell's PATH.
String remoteTmuxListScript() =>
    'SHELLX_FMT=${shQuote(tmuxListFormat)}; export SHELLX_FMT\n'
    r'''
s=${SHELL:-/bin/sh}
case "${s##*/}" in
  bash|zsh|sh|dash|ksh|mksh|fish) exec "$s" -l -c 'exec tmux list-sessions -F "$SHELLX_FMT"' ;;
  *) PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"; export PATH; exec tmux list-sessions -F "$SHELLX_FMT" ;;
esac
''';

/// D10: the one remote command. The server's login shell (sh, bash, zsh,
/// fish, csh…) only sees a single-quoted word of base64 and fixed syntax;
/// `/bin/sh` decodes the script with the first decoder that exists.
String remoteExecCommand(String script) {
  final b64 = base64.encode(utf8.encode(script));
  return "/bin/sh -c 'eval \"\$(b=$b64; "
      'printf %s "\$b" | base64 -d 2>/dev/null || '
      'printf %s "\$b" | base64 -D 2>/dev/null || '
      'printf %s "\$b" | openssl base64 -d -A)"'
      "'";
}
```

(`remoteZshHook`/`remoteBashHook` are `const` string concatenations of `const` parts — `zshHookEnv` and `bashHookRc` are `const` in `shell_hook_scripts.dart`.)

- [ ] **Step 4: Implement `ssh_command.dart`**

```dart
import 'dart:io';

import '../pty/pty.dart';
import 'remote_bootstrap.dart';
import 'session_launch.dart';

/// D3: `/usr/bin/ssh` on macOS (never PATH: GUI apps get a minimal one),
/// the Windows OpenSSH client, else the first `ssh` on PATH.
Future<String?> sshPathFor({
  required String operatingSystem,
  required Map<String, String> environment,
  Future<bool> Function(String path)? fileExists,
}) async {
  final exists = fileExists ?? _exists;
  switch (operatingSystem) {
    case 'macos':
      return await exists('/usr/bin/ssh') ? '/usr/bin/ssh' : null;
    case 'windows':
      final root =
          environment['SystemRoot'] ?? environment['SYSTEMROOT'] ?? r'C:\Windows';
      final system = '$root\\System32\\OpenSSH\\ssh.exe';
      if (await exists(system)) return system;
      return _onPath('ssh.exe', environment, exists, windows: true);
    default:
      return _onPath('ssh', environment, exists, windows: false);
  }
}

/// D25: Homebrew, MacPorts and system locations first (GUI PATH again).
Future<String?> tmuxPathFor({
  required String operatingSystem,
  required Map<String, String> environment,
  Future<bool> Function(String path)? fileExists,
}) async {
  if (operatingSystem == 'windows') return null;
  final exists = fileExists ?? _exists;
  for (final candidate in const [
    '/opt/homebrew/bin/tmux',
    '/usr/local/bin/tmux',
    '/opt/local/bin/tmux',
    '/usr/bin/tmux',
  ]) {
    if (await exists(candidate)) return candidate;
  }
  return _onPath('tmux', environment, exists, windows: false);
}

Future<bool> _exists(String path) => File(path).exists();

Future<String?> _onPath(
  String name,
  Map<String, String> environment,
  Future<bool> Function(String) exists, {
  required bool windows,
}) async {
  final path = environment['PATH'] ?? environment['Path'] ?? '';
  final sep = windows ? r'\' : '/';
  for (final entry in path.split(windows ? ';' : ':')) {
    final dir = entry.trim();
    if (dir.isEmpty) continue;
    final candidate = dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';
    if (await exists(candidate)) return candidate;
  }
  return null;
}

final class SshCommandOptions {
  const SshCommandOptions({
    required this.sshPath,
    this.controlPath,
    this.keepalive = true,
  });

  final String sshPath;

  /// D8: `<dir>/%C` on macOS; null = no multiplexing (Windows, unsafe dir).
  final String? controlPath;

  /// D13: add `ServerAliveInterval=15` / `ServerAliveCountMax=3`.
  final bool keepalive;
}

/// D8: [master] is `auto` for panes (first one becomes the master) and
/// `no` for helpers (use a master when there is one, never become one).
List<String> controlOptions(String? controlPath, {required String master}) =>
    controlPath == null
    ? const []
    : [
        '-o',
        'ControlMaster=$master',
        '-o',
        'ControlPath=$controlPath',
        if (master == 'auto') ...['-o', 'ControlPersist=60'],
      ];

/// D12: `ssh -t [control] [keepalive] [-l -p] -- host [remote command]`.
ShellCommand buildSshCommand(SessionLaunch launch, SshCommandOptions options) {
  final target = launch.host;
  if (target == null) {
    throw ArgumentError('a tmux session on this computer has no ssh command');
  }
  final remote = switch (launch) {
    SshLaunch(:final hook, :final remoteCwd) =>
      hook
          ? remoteExecCommand(remoteBootstrapScript(RemoteBootstrap(cwd: remoteCwd)))
          : null,
    TmuxLaunch(:final hook, :final session, :final create) =>
      hook
          ? remoteExecCommand(
              remoteBootstrapScript(
                RemoteBootstrap(tmuxSession: session, tmuxCreate: create, writeHooks: false),
              ),
            )
          : _plainTmux(session, create),
  };
  return ShellCommand(
    executable: options.sshPath,
    arguments: [
      '-t',
      ...controlOptions(options.controlPath, master: 'auto'),
      if (options.keepalive) ...[
        '-o',
        'ServerAliveInterval=15',
        '-o',
        'ServerAliveCountMax=3',
      ],
      ...target.destinationArgs,
      ?remote,
    ],
    name: 'ssh',
  );
}

/// D11: without the hook the name reaches the server's shell as a bare
/// word — only `[A-Za-z0-9_-]`, and no `=` prefix (zsh would expand it).
String _plainTmux(String session, bool create) {
  if (!isPlainTmuxName(session)) {
    throw ArgumentError('this tmux name needs the ShellX hook');
  }
  return create
      ? 'tmux new-session -A -s $session'
      : 'tmux attach-session -t $session';
}

/// D25: a local tmux client, argv only (no shell, exact-name `=`).
ShellCommand buildLocalTmuxCommand(TmuxLaunch launch, String tmuxPath) =>
    ShellCommand(
      executable: tmuxPath,
      arguments: launch.create
          ? ['new-session', '-A', '-s', launch.session]
          : ['attach-session', '-t', '=${launch.session}'],
      name: 'tmux',
    );
```

Add the exports to `packages/shellx_agent/lib/shellx_agent.dart`:

```dart
export 'src/remote/remote_bootstrap.dart';
export 'src/remote/ssh_command.dart';
```

- [ ] **Step 5: Run the tests**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/ test/pty/ && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: PASS (the `test/pty/` suite proves the local hooks are untouched). If `remote_hook_branch_test` fails for zsh only because `/bin/zsh` is missing (Linux CI), the test must be skipped there with `skip: !File('/bin/zsh').existsSync()` — add that argument, do not weaken the assertions.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent/lib/src/remote/remote_bootstrap.dart packages/shellx_agent/lib/src/remote/ssh_command.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/remote/remote_bootstrap_test.dart packages/shellx_agent/test/remote/remote_bootstrap_run_test.dart packages/shellx_agent/test/remote/remote_hook_branch_test.dart packages/shellx_agent/test/remote/ssh_command_test.dart
git commit -m "feat(agent): remote bootstrap — hello/pid/home, ShellX hooks in the server's cache, branch add-on, tmux exec; ssh and tmux command lines (A8 D3, D10-D13, D15, D25)"
```

---
### Task 4: Agent — `SshControl`, control directory, `resolveRemoteTools` (D8, D9, D13, D18, D19, D40)

**Files:**
- Create: `packages/shellx_agent/lib/src/remote/ssh_control.dart`, `packages/shellx_agent/lib/src/remote/remote_tools.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/remote/ssh_control_test.dart`, `packages/shellx_agent/test/remote/remote_tools_test.dart`

**Interfaces:**
- Consumes: Task 1 `SshTarget`; Task 2 `CommandRunner`, `CommandResult`, `runCommand`; Task 3 `controlOptions`, `remoteExecCommand`, `sshPathFor`, `tmuxPathFor`.
- Produces:
  - `abstract interface class LocalPorts { Future<bool> isFree(int port); Future<int> ephemeral(); }`; `abstract interface class ForwardProcess { Future<int> get exitCode; void kill(); }`; `typedef ForwardStarter = Future<ForwardProcess> Function(String executable, List<String> arguments);`; `final class ForwardFailedException implements Exception`.
  - `final class SshControl { SshControl({required String sshPath, String? controlDirectory, CommandRunner? run, ForwardStarter? startForward, LocalPorts? ports, DateTime Function()? now, Future<void> Function(Duration)? sleep}); String? get controlPath; Future<bool> keepaliveNeeded(SshTarget); Future<bool> masterAlive(SshTarget); Future<void> awaitMaster(SshTarget, {required bool Function() stillWaiting}); Future<CommandResult> runRemote(SshTarget, String script, {Duration timeout}); Future<int> forward(SshTarget, int remotePort); int? forwardedPort(SshTarget, int remotePort); Future<void> cancelForwards(SshTarget); Future<void> exitMasters(Iterable<SshTarget>); void noteMaster(SshTarget); Iterable<SshTarget> get mastersUsed; }`
  - `Future<String?> prepareControlDirectory({String base = '/tmp', CommandRunner? run, void Function(String)? log})`.
  - `final class RemoteTools { const RemoteTools({String? sshPath, String? tmuxPath, SshControl? control}); }`; `Future<RemoteTools> resolveRemoteTools({required String operatingSystem, required Map<String, String> environment, CommandRunner? run, Future<bool> Function(String)? fileExists, void Function(String)? log, String controlBase = '/tmp'})`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/remote/ssh_control_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class FakeRunner {
  final calls = <List<String>>[];
  CommandResult Function(List<String> args) answer = (args) =>
      const CommandResult(0, '', '');

  Future<CommandResult> call(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    calls.add(arguments);
    return answer(arguments);
  }
}

final class FakePorts implements LocalPorts {
  final busy = <int>{};
  int next = 53012;
  @override
  Future<bool> isFree(int port) async => !busy.contains(port);
  @override
  Future<int> ephemeral() async => next++;
}

final class FakeForward implements ForwardProcess {
  final exit = Completer<int>();
  bool killed = false;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void kill() {
    killed = true;
    if (!exit.isCompleted) exit.complete(-9);
  }
}

void main() {
  final devbox = SshTarget.parse('devbox')!;
  late FakeRunner runner;
  late FakePorts ports;
  final started = <List<String>>[];
  late FakeForward process;
  var now = DateTime(2026, 10, 7, 9);

  SshControl control({String? dir = '/tmp/shellx-ssh-501'}) => SshControl(
    sshPath: '/usr/bin/ssh',
    controlDirectory: dir,
    run: runner.call,
    ports: ports,
    now: () => now,
    sleep: (_) async {},
    startForward: (exe, args) async {
      started.add(args);
      return process;
    },
  );

  setUp(() {
    runner = FakeRunner();
    ports = FakePorts();
    started.clear();
    process = FakeForward();
  });

  test('keepalive comes from ssh -G and is remembered 60 s (D13)', () async {
    final c = control();
    runner.answer = (_) => const CommandResult(0, 'user me\nserveraliveinterval 0\n', '');
    expect(await c.keepaliveNeeded(devbox), isTrue);
    runner.answer = (_) => const CommandResult(0, 'serveraliveinterval 30\n', '');
    expect(await c.keepaliveNeeded(devbox), isTrue); // cached
    now = now.add(const Duration(seconds: 61));
    expect(await c.keepaliveNeeded(devbox), isFalse);
    expect(runner.calls.first, ['-G', '--', 'devbox']);
    runner.answer = (_) => const CommandResult(255, '', '');
    now = now.add(const Duration(seconds: 61));
    expect(await c.keepaliveNeeded(devbox), isTrue);
  });

  test('master check and wait (D8, D9)', () async {
    final c = control();
    runner.answer = (_) => const CommandResult(255, '', '');
    expect(await c.masterAlive(devbox), isFalse);
    expect(runner.calls.single, ['-o', 'ControlPath=/tmp/shellx-ssh-501/%C', '-O', 'check', '--', 'devbox']);
    runner.calls.clear();
    await c.awaitMaster(devbox, stillWaiting: () => true);
    expect(runner.calls, hasLength(30)); // 3 s at 100 ms
    runner.calls.clear();
    var checks = 0;
    runner.answer = (_) => CommandResult(++checks >= 3 ? 0 : 255, '', '');
    await c.awaitMaster(devbox, stillWaiting: () => true);
    expect(runner.calls, hasLength(3));
    runner.calls.clear();
    await c.awaitMaster(devbox, stillWaiting: () => false);
    expect(runner.calls, isEmpty);
    final windows = control(dir: null);
    expect(await windows.masterAlive(devbox), isFalse);
    await windows.awaitMaster(devbox, stillWaiting: () => true);
    expect(runner.calls, isEmpty);
  });

  test('runRemote: BatchMode, never a master, the script wrapped (D18, D38g)', () async {
    final c = control();
    await c.runRemote(devbox, 'echo hi', timeout: const Duration(seconds: 4));
    final args = runner.calls.single;
    expect(args.sublist(0, 7), ['-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=4', '-o', 'ControlMaster=no']);
    expect(args, containsAllInOrder(['-o', 'ControlPath=/tmp/shellx-ssh-501/%C', '--', 'devbox']));
    expect(args.last, remoteExecCommand('echo hi'));
    expect(args, isNot(contains('ControlPersist=60')));
  });

  test('forward over the master: same port when free, another when not, '
      'reused (D19)', () async {
    final c = control();
    expect(await c.forward(devbox, 8000), 8000);
    expect(runner.calls.last, containsAllInOrder(['-O', 'forward', '-L', '127.0.0.1:8000:localhost:8000', '--', 'devbox']));
    final before = runner.calls.length;
    expect(await c.forward(devbox, 8000), 8000);
    expect(runner.calls.length, before);
    ports.busy.add(3000);
    expect(await c.forward(devbox, 3000), 53012);
    expect(c.forwardedPort(devbox, 3000), 53012);
    runner.answer = (args) => CommandResult(args.contains('forward') ? 1 : 0, '', '');
    await expectLater(c.forward(devbox, 9000), throwsA(isA<ForwardFailedException>()));
  });

  test('forward without a master: a BatchMode -N process; its exit fails it', () async {
    final c = control(dir: null);
    var polls = 0;
    ports.busy.clear();
    final free = FakePorts();
    final probe = SshControl(
      sshPath: 'ssh.exe',
      run: runner.call,
      ports: _Bound(free, after: () => ++polls > 2),
      sleep: (_) async {},
      startForward: (exe, args) async {
        started.add(args);
        return process;
      },
    );
    expect(await probe.forward(devbox, 8000), 8000);
    expect(started.single, ['-N', '-T', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-L', '127.0.0.1:8000:localhost:8000', '--', 'devbox']);
    final dead = FakeForward()..exit.complete(255);
    final failing = SshControl(
      sshPath: 'ssh.exe',
      run: runner.call,
      ports: FakePorts(),
      sleep: (_) async {},
      startForward: (exe, args) async => dead,
    );
    await expectLater(failing.forward(devbox, 8000), throwsA(isA<ForwardFailedException>()));
    expect(c.controlPath, isNull);
  });

  test('cancel and exit: -O cancel / -O exit, processes killed (D40)', () async {
    final c = control();
    await c.forward(devbox, 8000);
    await c.cancelForwards(devbox);
    expect(runner.calls.last, containsAllInOrder(['-O', 'cancel', '-L', '127.0.0.1:8000:localhost:8000']));
    expect(c.forwardedPort(devbox, 8000), isNull);
    c.noteMaster(devbox);
    c.noteMaster(SshTarget.parse('me@other')!);
    await c.exitMasters(c.mastersUsed);
    final exits = runner.calls.where((a) => a.contains('exit')).toList();
    expect(exits, hasLength(2));
  });

  test('every helper runs BatchMode or only talks to the socket (D38g)', () async {
    final c = control();
    await c.keepaliveNeeded(devbox);
    await c.masterAlive(devbox);
    await c.runRemote(devbox, 'x');
    await c.forward(devbox, 8000);
    await c.cancelForwards(devbox);
    for (final args in runner.calls) {
      final safe = args.contains('BatchMode=yes') || args.contains('-O') || args.first == '-G';
      expect(safe, isTrue, reason: '$args');
    }
  });

  group('prepareControlDirectory (D8)', testOn: 'mac-os || linux', () {
    late Directory base;
    // A short base: the socket path must stay under 104 bytes.
    setUp(() => base = Directory('/tmp').createTempSync('sx'));
    tearDown(() => base.deleteSync(recursive: true));

    test('owned 0700 directory → used; anything else → off, logged without the path', () async {
      final r = FakeRunner()
        ..answer = (args) => switch (args) {
          ['-u'] => const CommandResult(0, '501\n', ''),
          ['700', _] => const CommandResult(0, '', ''),
          ['-f', _, _] => const CommandResult(0, '501 700 Directory\n', ''),
          _ => const CommandResult(1, '', ''),
        };
      expect(await prepareControlDirectory(base: base.path, run: r.call), '${base.path}/shellx-ssh-501');
      final logs = <String>[];
      r.answer = (args) => switch (args) {
        ['-u'] => const CommandResult(0, '501\n', ''),
        ['-f', _, _] => const CommandResult(0, '0 755 Directory\n', ''),
        _ => const CommandResult(0, '', ''),
      };
      expect(await prepareControlDirectory(base: base.path, run: r.call, log: logs.add), isNull);
      expect(logs, ['ssh: control dir unsafe']);
      expect(await prepareControlDirectory(base: '/${'x' * 60}', run: r.call), isNull);
    });
  });
}

/// Free until [after] says the forward bound it.
final class _Bound implements LocalPorts {
  _Bound(this.inner, {required this.after});
  final LocalPorts inner;
  final bool Function() after;
  var _chosen = false;
  @override
  Future<bool> isFree(int port) async {
    if (!_chosen) {
      _chosen = true;
      return true;
    }
    return !after();
  }

  @override
  Future<int> ephemeral() => inner.ephemeral();
}
```

`packages/shellx_agent/test/remote/remote_tools_test.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  Future<CommandResult> run(String exe, List<String> args, {Duration timeout = const Duration(seconds: 5)}) async =>
      switch (args) {
        ['-u'] => const CommandResult(0, '501\n', ''),
        ['-f', _, _] => const CommandResult(0, '501 700 Directory\n', ''),
        _ => const CommandResult(0, '', ''),
      };

  test('macOS: system ssh, Homebrew tmux, multiplexing (D3, D8)', () async {
    final tools = await resolveRemoteTools(
      operatingSystem: 'macos',
      environment: const {'PATH': '/usr/bin'},
      run: run,
      fileExists: (p) async => p == '/usr/bin/ssh' || p == '/opt/homebrew/bin/tmux',
      controlBase: '/tmp/sx-test',
    );
    expect(tools.sshPath, '/usr/bin/ssh');
    expect(tools.tmuxPath, '/opt/homebrew/bin/tmux');
    expect(tools.control!.controlPath, '/tmp/sx-test/shellx-ssh-501/%C');
  });

  test('Windows: no multiplexing, no local tmux', () async {
    final tools = await resolveRemoteTools(
      operatingSystem: 'windows',
      environment: const {'SystemRoot': r'C:\Windows'},
      run: run,
      fileExists: (p) async => p.endsWith(r'OpenSSH\ssh.exe'),
    );
    expect(tools.control!.controlPath, isNull);
    expect(tools.tmuxPath, isNull);
  });

  test('no ssh: no control', () async {
    final tools = await resolveRemoteTools(
      operatingSystem: 'macos',
      environment: const {},
      run: run,
      fileExists: (_) async => false,
    );
    expect(tools.sshPath, isNull);
    expect(tools.control, isNull);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/ssh_control_test.dart test/remote/remote_tools_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement `ssh_control.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'command_runner.dart';
import 'remote_bootstrap.dart';
import 'ssh_command.dart';
import 'ssh_target.dart';

abstract interface class LocalPorts {
  /// Nothing listens on 127.0.0.1:[port].
  Future<bool> isFree(int port);

  /// A port the OS gives out right now.
  Future<int> ephemeral();
}

abstract interface class ForwardProcess {
  Future<int> get exitCode;
  void kill();
}

typedef ForwardStarter =
    Future<ForwardProcess> Function(String executable, List<String> arguments);

final class ForwardFailedException implements Exception {
  const ForwardFailedException();
  @override
  String toString() => 'ForwardFailedException';
}

final class _SocketPorts implements LocalPorts {
  const _SocketPorts();

  @override
  Future<bool> isFree(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  @override
  Future<int> ephemeral() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}

final class _ProcessForward implements ForwardProcess {
  _ProcessForward(this._process) {
    unawaited(_process.stdin.close().catchError((Object _) {}));
    _process.stdout.drain<void>().ignore();
    _process.stderr.drain<void>().ignore();
  }
  final Process _process;
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  void kill() => _process.kill();
}

Future<ForwardProcess> _startForward(String executable, List<String> arguments) async =>
    _ProcessForward(await Process.start(executable, arguments));

final class _Forward {
  _Forward(this.target, this.remote, this.local, this.process);
  final SshTarget target;
  final int remote;
  final int local;
  final ForwardProcess? process;
  bool dead = false;
  String get spec => '127.0.0.1:$local:localhost:$remote';
}

/// The helpers around the panes' own `ssh` (A8 D8, D9, D13, D18, D19, D40).
/// Every call runs `BatchMode=yes` or only talks to the control socket:
/// nothing here can ever wait for a password nobody sees (D38g). Nothing
/// here logs.
final class SshControl {
  SshControl({
    required this.sshPath,
    this.controlDirectory,
    CommandRunner? run,
    ForwardStarter? startForward,
    LocalPorts? ports,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _run = run ?? runCommand,
       _start = startForward ?? _startForward,
       _ports = ports ?? const _SocketPorts(),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final String sshPath;

  /// D8: `/tmp/shellx-ssh-<uid>` checked by [prepareControlDirectory];
  /// null = no multiplexing (Windows, unsafe directory).
  final String? controlDirectory;
  final CommandRunner _run;
  final ForwardStarter _start;
  final LocalPorts _ports;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  final _keepalive = <String, ({DateTime at, bool needed})>{};
  final _forwards = <String, _Forward>{};
  final _masters = <String, SshTarget>{};

  String? get controlPath =>
      controlDirectory == null ? null : '$controlDirectory/%C';

  /// D13: `ssh -G` (local, no network) says `serveraliveinterval 0`, or
  /// cannot answer.
  Future<bool> keepaliveNeeded(SshTarget target) async {
    final now = _now();
    final cached = _keepalive[target.key];
    if (cached != null && now.difference(cached.at) < const Duration(seconds: 60)) {
      return cached.needed;
    }
    final r = await _run(
      sshPath,
      ['-G', ...target.destinationArgs],
      timeout: const Duration(seconds: 2),
    );
    var needed = true;
    if (r.exitCode == 0 && !r.timedOut) {
      for (final line in const LineSplitter().convert(r.stdout)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length == 2 && parts[0].toLowerCase() == 'serveraliveinterval') {
          needed = (int.tryParse(parts[1]) ?? 0) == 0;
        }
      }
    }
    _keepalive[target.key] = (at: now, needed: needed);
    return needed;
  }

  Future<bool> masterAlive(SshTarget target) async {
    final path = controlPath;
    if (path == null) return false;
    final r = await _run(
      sshPath,
      ['-o', 'ControlPath=$path', '-O', 'check', ...target.destinationArgs],
      timeout: const Duration(seconds: 2),
    );
    return r.exitCode == 0 && !r.timedOut;
  }

  /// D9: at most 3 s (30 checks, 100 ms apart) while [stillWaiting].
  Future<void> awaitMaster(
    SshTarget target, {
    required bool Function() stillWaiting,
  }) async {
    if (controlPath == null) return;
    for (var i = 0; i < 30 && stillWaiting(); i++) {
      if (await masterAlive(target)) return;
      await _sleep(const Duration(milliseconds: 100));
    }
  }

  /// D18, D25: [script] under `/bin/sh` on the server, never prompting,
  /// over the master when one exists.
  Future<CommandResult> runRemote(
    SshTarget target,
    String script, {
    Duration timeout = const Duration(seconds: 4),
  }) => _run(sshPath, [
    '-T',
    '-o',
    'BatchMode=yes',
    '-o',
    'ConnectTimeout=${max(1, timeout.inSeconds)}',
    ...controlOptions(controlPath, master: 'no'),
    ...target.destinationArgs,
    remoteExecCommand(script),
  ], timeout: timeout);

  /// A pane's ssh may have become a master for [target] (D40).
  void noteMaster(SshTarget target) {
    if (controlPath != null) _masters[target.key] = target;
  }

  Iterable<SshTarget> get mastersUsed => _masters.values;

  int? forwardedPort(SshTarget target, int remotePort) {
    final f = _forwards['${target.key}\u0000$remotePort'];
    return f == null || f.dead ? null : f.local;
  }

  /// D19: `127.0.0.1:L → localhost:remotePort` on the server; L = the same
  /// port when it is free here. Throws [ForwardFailedException].
  Future<int> forward(SshTarget target, int remotePort) async {
    final key = '${target.key}\u0000$remotePort';
    final existing = _forwards[key];
    if (existing != null && !existing.dead) return existing.local;
    if (_forwards.values.where((f) => f.target == target).length >= 32) {
      throw const ForwardFailedException();
    }
    final local = await _ports.isFree(remotePort) ? remotePort : await _ports.ephemeral();
    final spec = '127.0.0.1:$local:localhost:$remotePort';
    final path = controlPath;
    if (path != null && await masterAlive(target)) {
      final r = await _run(
        sshPath,
        ['-o', 'ControlPath=$path', '-O', 'forward', '-L', spec, ...target.destinationArgs],
        timeout: const Duration(seconds: 3),
      );
      if (r.exitCode != 0 || r.timedOut) throw const ForwardFailedException();
      _forwards[key] = _Forward(target, remotePort, local, null);
      return local;
    }
    final process = await _start(sshPath, [
      '-N',
      '-T',
      '-o',
      'BatchMode=yes',
      '-o',
      'ExitOnForwardFailure=yes',
      '-L',
      spec,
      ...target.destinationArgs,
    ]);
    final forward = _Forward(target, remotePort, local, process);
    var exited = false;
    unawaited(
      process.exitCode.then((_) {
        exited = true;
        forward.dead = true;
      }),
    );
    for (var i = 0; i < 50 && !exited; i++) {
      await _sleep(const Duration(milliseconds: 100));
      if (exited) break;
      if (!await _ports.isFree(local)) {
        _forwards[key] = forward;
        return local;
      }
    }
    process.kill();
    throw const ForwardFailedException();
  }

  /// The last pane of [target] closed (D19).
  Future<void> cancelForwards(SshTarget target) async {
    final mine = _forwards.entries.where((e) => e.value.target == target).toList();
    for (final entry in mine) {
      _forwards.remove(entry.key);
      final process = entry.value.process;
      if (process != null) {
        process.kill();
        continue;
      }
      final path = controlPath;
      if (path == null) continue;
      await _run(
        sshPath,
        ['-o', 'ControlPath=$path', '-O', 'cancel', '-L', entry.value.spec, ...target.destinationArgs],
        timeout: const Duration(seconds: 2),
      );
    }
  }

  /// D40: "Quit completely" — every forward process killed, every master
  /// ShellX may have started told to exit, in parallel, ≤ 2 s each.
  Future<void> exitMasters(Iterable<SshTarget> targets) async {
    for (final f in _forwards.values) {
      f.process?.kill();
    }
    _forwards.clear();
    final path = controlPath;
    if (path == null) return;
    final unique = {for (final t in targets) t.key: t}.values.toList();
    await Future.wait([
      for (final t in unique)
        _run(
          sshPath,
          ['-o', 'ControlPath=$path', '-O', 'exit', ...t.destinationArgs],
          timeout: const Duration(seconds: 2),
        ),
    ]);
  }
}

/// D8 (macOS): `<base>/shellx-ssh-<uid>`, owned by us, 0700, a real
/// directory — else null (no multiplexing). `ControlPath` plus ssh's
/// 17-character temporary suffix must stay under `sun_path` (104 bytes).
Future<String?> prepareControlDirectory({
  String base = '/tmp',
  CommandRunner? run,
  void Function(String message)? log,
}) async {
  final runner = run ?? runCommand;
  final id = await runner('/usr/bin/id', ['-u']);
  final uid = id.stdout.trim();
  if (id.exitCode != 0 || !RegExp(r'^[0-9]+$').hasMatch(uid)) return null;
  final dir = '$base/shellx-ssh-$uid';
  if (dir.length + 1 + 40 + 17 >= 104) return null;
  try {
    await Directory(dir).create();
  } on FileSystemException {
    // Exists already, or cannot be made: the checks below decide.
  }
  final stat = await runner('/usr/bin/stat', ['-f', '%u %Lp %HT', dir]);
  if (stat.exitCode != 0 || !stat.stdout.trim().startsWith('$uid ')) {
    log?.call('ssh: control dir unsafe'); // never the path (D37)
    return null;
  }
  await runner('/bin/chmod', ['700', dir]);
  final again = await runner('/usr/bin/stat', ['-f', '%u %Lp %HT', dir]);
  if (again.exitCode != 0 || again.stdout.trim() != '$uid 700 Directory') {
    log?.call('ssh: control dir unsafe');
    return null;
  }
  return dir;
}
```

(The test's fake answers both `stat` calls the same way; with `0 755 Directory` the first check already fails.)

`packages/shellx_agent/lib/src/remote/remote_tools.dart`:

```dart
import 'command_runner.dart';
import 'ssh_command.dart';
import 'ssh_control.dart';

/// What this computer has for A8 (D3, D8, D25), resolved once at startup.
final class RemoteTools {
  const RemoteTools({this.sshPath, this.tmuxPath, this.control});

  /// Null: no ssh — SSH panes fail with `ssh_unavailable`.
  final String? sshPath;

  /// Null: no local tmux (always on Windows).
  final String? tmuxPath;
  final SshControl? control;
}

Future<RemoteTools> resolveRemoteTools({
  required String operatingSystem,
  required Map<String, String> environment,
  CommandRunner? run,
  Future<bool> Function(String path)? fileExists,
  void Function(String message)? log,
  String controlBase = '/tmp',
}) async {
  final ssh = await sshPathFor(
    operatingSystem: operatingSystem,
    environment: environment,
    fileExists: fileExists,
  );
  final tmux = await tmuxPathFor(
    operatingSystem: operatingSystem,
    environment: environment,
    fileExists: fileExists,
  );
  if (ssh == null) return RemoteTools(tmuxPath: tmux);
  final dir = operatingSystem == 'macos'
      ? await prepareControlDirectory(base: controlBase, run: run, log: log)
      : null;
  return RemoteTools(
    sshPath: ssh,
    tmuxPath: tmux,
    control: SshControl(sshPath: ssh, controlDirectory: dir, run: run),
  );
}
```

Exports in `packages/shellx_agent/lib/shellx_agent.dart`:

```dart
export 'src/remote/remote_tools.dart';
export 'src/remote/ssh_control.dart';
```

- [ ] **Step 4: Run the tests**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/ && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/remote/ssh_control.dart packages/shellx_agent/lib/src/remote/remote_tools.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/remote/ssh_control_test.dart packages/shellx_agent/test/remote/remote_tools_test.dart
git commit -m "feat(agent): SshControl — owned control directory, ssh -G keepalive, master wait, BatchMode remote runs, port forwards, master exit (A8 D8, D9, D13, D18, D19, D40)"
```

---

### Task 5: Agent — OSC 6973, remote cwd, `SessionManager.open(launch:)`, `SessionSummary.remote` (D2, D9, D11, D14, D16, D17, D26, D36)

**Files:**
- Modify: `packages/shellx_agent/lib/src/notify/osc_event_parser.dart`, `packages/shellx_agent/lib/src/notify/command_tracker.dart`, `packages/shellx_agent/lib/src/context/cwd_url.dart`, `packages/shellx_agent/lib/src/session/local_sessions.dart`, `packages/shellx_agent/lib/src/session/session_manager.dart`
- Modify: `packages/shellx_agent/test/support/session_rig.dart` (`remoteTools`, `plainConnectedAfter`), `apps/desktop/test/support/fake_local_sessions.dart`; if A5b merged also `packages/shellx_agent/lib/src/mux/remote_local_sessions.dart` (signature only here — the wire comes in Task 13: until then `RemoteLocalSessions.open` throws `SpawnFailedException('ssh_unavailable')` when `launch != null`)
- Test: `packages/shellx_agent/test/session/session_remote_test.dart`, `packages/shellx_agent/test/notify/osc_event_parser_test.dart` (append), `packages/shellx_agent/test/context/cwd_url_test.dart` (append)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `final class RemoteMetaReported extends OscEvent { const RemoteMetaReported(String key, String value); }` (OSC 6973).
  - `String? parseRemoteCwdPath(String url)`.
  - `LocalSessions.open({required int cols, required int rows, String? cwd, int? tabId, SessionLaunch? launch})` — with `launch`, `cwd` is ignored (the folder is in the launch); throws `SpawnFailedException('ssh_unavailable' | 'tmux_unavailable' | 'bad_launch')`.
  - `SessionSummary.remote` (`SessionRemote?`).
  - `SessionManager({…, RemoteTools? remoteTools, Duration plainConnectedAfter = const Duration(seconds: 10), Duration remotePortInterval = const Duration(seconds: 5)})`.
  - `FakeLocalSessions.openLaunches` (`List<SessionLaunch?>`); `FakeLocalSessions.summary(…, SessionRemote? remote)`; `FakeLocalSessions.openError` covers launches too.

- [ ] **Step 1: Write the failing tests**

Append to `packages/shellx_agent/test/notify/osc_event_parser_test.dart` (inside `main`):

```dart
  group('OSC 6973 (A8 D16)', () {
    List<OscEvent> feed(String s) => OscEventParser().feed(utf8.encode(s));

    test('key=value with BEL or ST', () {
      expect(feed('\x1b]6973;hello=1\x07'), [const RemoteMetaReported('hello', '1')]);
      expect(feed('\x1b]6973;branch=feat;x\x1b\\'), [const RemoteMetaReported('branch', 'feat;x')]);
      expect(feed('\x1b]6973;branch=\x07'), [const RemoteMetaReported('branch', '')]);
    });

    test('no key or a control character: nothing', () {
      expect(feed('\x1b]6973;=x\x07'), isEmpty);
      expect(feed('\x1b]6973;hello\x07'), isEmpty);
      expect(feed('\x1b]6973;home=/a\u0085b\x07'), isEmpty);
    });
  });
```

Append to `packages/shellx_agent/test/context/cwd_url_test.dart`:

```dart
  test('parseRemoteCwdPath: any host, decoded path (A8 D14)', () {
    expect(parseRemoteCwdPath('file://devbox/home/me/work%20x'), '/home/me/work x');
    expect(parseRemoteCwdPath('file:///srv'), '/srv');
    expect(parseRemoteCwdPath('file://h/%E1%BA%BF'), '/ế');
    expect(parseRemoteCwdPath('file://h/a%00b'), isNull);
    expect(parseRemoteCwdPath('file://h/%ZZ'), isNull);
    expect(parseRemoteCwdPath('http://h/x'), isNull);
    expect(parseRemoteCwdPath('file://h'), isNull);
  });
```

In `packages/shellx_agent/test/support/session_rig.dart`, add constructor parameters `RemoteTools? remoteTools`, `Duration plainConnectedAfter = const Duration(seconds: 10)` and pass them to `SessionManager(…, remoteTools: remoteTools, plainConnectedAfter: plainConnectedAfter)`.

`packages/shellx_agent/test/session/session_remote_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

final devbox = SshTarget.parse('devbox')!;

String osc(String body) => '\x1b]$body\x07';

/// ssh -G says "no keepalive"; -O check says "no master" unless [master].
RemoteTools tools({
  List<List<String>>? calls,
  bool Function()? master,
  String? tmux = '/usr/local/bin/tmux',
  String keepalive = '0',
}) {
  Future<CommandResult> run(String exe, List<String> args, {Duration timeout = const Duration(seconds: 5)}) async {
    calls?.add(args);
    if (args.first == '-G') return CommandResult(0, 'serveraliveinterval $keepalive\n', '');
    if (args.contains('check')) return CommandResult((master?.call() ?? false) ? 0 : 255, '', '');
    return const CommandResult(255, '', '');
  }

  return RemoteTools(
    sshPath: '/usr/bin/ssh',
    tmuxPath: tmux,
    control: SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/shellx-ssh-501',
      run: run,
      sleep: (_) async {},
    ),
  );
}

final class _Heads implements GitBranchLookup {
  final asked = <String>[];
  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) async {
    asked.add(directory);
    return 'local';
  }
}

void main() {
  test('an SSH launch spawns ssh, not the shell, without the local hook (D2, D12)', () async {
    final rig = SessionRig(remoteTools: tools());
    final id = await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox, remoteCwd: '/srv'));
    final pty = rig.pty(0);
    expect(pty.command.executable, '/usr/bin/ssh');
    expect(pty.command.arguments.first, '-t');
    expect(pty.command.arguments, containsAllInOrder(['ServerAliveInterval=15', '--', 'devbox']));
    expect(pty.command.arguments.last, startsWith("/bin/sh -c 'eval"));
    expect(pty.workingDirectory, '/Users/test');
    expect(pty.environment['TERM'], 'xterm-256color');
    expect(pty.environment.containsKey('ZDOTDIR'), isFalse);
    final s = rig.manager.sessions.single;
    expect(s.id, id);
    expect(s.shell, 'ssh');
    expect(s.remote, SessionRemote(launch: SshLaunch(devbox, remoteCwd: '/srv')));
  });

  test('hello, pid, home, cwd, branch from the server; no local git lookup '
      '(D14, D15, D16)', () async {
    final heads = _Heads();
    final rig = SessionRig(remoteTools: tools(), gitHeads: heads);
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    rig.pty(0).emit(
      '${osc('6973;hello=1')}${osc('6973;pid=4242')}${osc('6973;home=/home/me')}'
      '${osc('7;file://devbox/home/me/work%20x')}${osc('6973;branch=feat/x')}',
    );
    await pumpEventQueue();
    final s = rig.manager.sessions.single;
    expect(s.remote!.connected, isTrue);
    expect(s.remote!.home, '/home/me');
    expect(s.cwd, '/home/me/work x');
    expect(s.gitBranch, 'feat/x');
    expect(heads.asked, isEmpty);
    rig.pty(0).emit(osc('6973;branch='));
    rig.pty(0).emit('\x1b]133;D;0\x07');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, isNull);
    expect(heads.asked, isEmpty);
  });

  test('a local shell ignores OSC 6973 and still forgets a remote OSC 7 (A2 D2)', () async {
    final rig = SessionRig(remoteTools: tools());
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit('${osc('7;file:///Users/test/w')}${osc('6973;branch=evil')}${osc('6973;hello=1')}');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, isNot('evil'));
    expect(rig.manager.sessions.single.remote, isNull);
    rig.pty(0).emit(osc('7;file://elsewhere/x'));
    await pumpEventQueue();
    expect(rig.manager.sessions.single.cwd, isNull);
  });

  test('without the hook the session counts as connected after 10 s (D11)', () {
    fakeAsync((async) {
      final rig = SessionRig(remoteTools: tools());
      unawaited(rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox, hook: false)));
      async.flushMicrotasks();
      expect(rig.pty(0).command.arguments.last, 'devbox');
      expect(rig.manager.sessions.single.remote!.connected, isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(rig.manager.sessions.single.remote!.connected, isTrue);
    });
  });

  test('no ssh / no tmux → named spawn failures (D3, D25)', () async {
    final none = SessionRig();
    await expectLater(
      none.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox)),
      throwsA(isA<SpawnFailedException>().having((e) => e.message, 'message', 'ssh_unavailable')),
    );
    final noTmux = SessionRig(remoteTools: tools(tmux: null));
    await expectLater(
      noTmux.manager.open(cols: 80, rows: 24, launch: const TmuxLaunch('main')),
      throwsA(isA<SpawnFailedException>().having((e) => e.message, 'message', 'tmux_unavailable')),
    );
    await expectLater(
      noTmux.manager.open(cols: 80, rows: 24, launch: TmuxLaunch('a b', host: devbox, hook: false)),
      throwsA(isA<SpawnFailedException>().having((e) => e.message, 'message', 'bad_launch')),
    );
  });

  test('local tmux: argv, connected at once, a stable title (D25, D26)', () async {
    final rig = SessionRig(remoteTools: tools());
    await rig.manager.open(cols: 80, rows: 24, launch: const TmuxLaunch('main'));
    expect(rig.pty(0).command.executable, '/usr/local/bin/tmux');
    expect(rig.pty(0).command.arguments, ['attach-session', '-t', '=main']);
    rig.pty(0).emit('\x1b]0;tmux set-titles\x07');
    await pumpEventQueue();
    final s = rig.manager.sessions.single;
    expect(s.remote!.connected, isTrue);
    expect(s.title, 'tmux: main');
  });

  test('a second pane to a server still signing in waits for its master (D9)', () async {
    final calls = <List<String>>[];
    final rig = SessionRig(remoteTools: tools(calls: calls));
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), isEmpty); // nobody to wait for
    calls.clear();
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), hasLength(30)); // 3 s, then on
    rig.pty(0).emit(osc('6973;hello=1'));
    rig.pty(1).emit(osc('6973;hello=1'));
    await pumpEventQueue();
    calls.clear();
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), isEmpty);
    var up = 0;
    final quick = SessionRig(remoteTools: tools(calls: calls, master: () => ++up > 2));
    await quick.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    calls.clear();
    await quick.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), hasLength(3)); // master up
  });

  test('a configured keepalive is left alone (D13)', () async {
    final rig = SessionRig(remoteTools: tools(keepalive: '30'));
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(rig.pty(0).command.arguments, isNot(contains('ServerAliveInterval=15')));
  });

  test('phones see the folder as host:path (D36)', () async {
    final rig = SessionRig(remoteTools: tools());
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    rig.pty(0).emit('${osc('6973;hello=1')}${osc('7;file://devbox/home/me')}');
    await pumpEventQueue();
    final info = rig.manager.sessionInfosWithContext.single;
    expect(info.cwd, 'devbox:/home/me');
    expect(rig.manager.sessionInfos.single.cwd, '');
  });

  test('logs never carry the host, the path or the branch (D37)', () async {
    final logs = <String>[];
    final rig = SessionRig(remoteTools: tools(), log: logs.add);
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox, remoteCwd: '/srv/secret'));
    rig.pty(0).emit('${osc('6973;hello=1')}${osc('7;file://devbox/srv/secret')}${osc('6973;branch=topsecret')}');
    rig.pty(0).exit(255);
    await pumpEventQueue();
    for (final line in logs) {
      expect(line, isNot(anyOf(contains('devbox'), contains('secret'))));
    }
  });
}
```

In `apps/desktop/test/support/fake_local_sessions.dart`:

```dart
  /// The launch of each [open] call, in order (null: a local shell).
  final openLaunches = <SessionLaunch?>[];

  @override
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
    SessionLaunch? launch,
  }) async {
    opens.add((cols, rows));
    openCwds.add(cwd);
    openTabIds.add(tabId); // A7
    openLaunches.add(launch);
    await openGate?.future;
    final error = openError;
    if (error != null) throw error;
    final id = nextId++;
    add(
      summary(
        id,
        origin: SessionOrigin.desktop,
        remote: launch == null ? null : SessionRemote(launch: launch),
      ),
      notify: false,
    );
    afterOpen?.call(id);
    return id;
  }
```

and give `summary(…)` a `SessionRemote? remote` parameter passed to `SessionSummary(remote: remote)`.

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/session/session_remote_test.dart test/notify/osc_event_parser_test.dart test/context/cwd_url_test.dart`
Expected: FAIL — `RemoteMetaReported`, `parseRemoteCwdPath`, `launch:`, `remote` undefined.

- [ ] **Step 3: OSC parser and cwd**

In `osc_event_parser.dart`, add after `BellRung`:

```dart
/// `OSC 6973 ; <key>=<value>`: ShellX's own report from a server's
/// bootstrap and hook (A8 D16) — `hello`, `pid`, `home`, `branch`. Only
/// remote sessions read it; the value never holds a control character.
final class RemoteMetaReported extends OscEvent {
  const RemoteMetaReported(this.key, this.value);
  final String key;
  final String value;
  @override
  bool operator ==(Object other) =>
      other is RemoteMetaReported && other.key == key && other.value == value;
  @override
  int get hashCode => Object.hash(key, value);
  // Never the value (A8 D37).
  @override
  String toString() => 'RemoteMetaReported($key, …)';
}
```

In `OscEventParser`, the number of an OSC may now have 4 digits — `_State.param` accepts `_param.length < 4` (was `< 3`) — and `_numbers` gains `'6973'`: `{'7', '9', '99', '133', '633', '777', '6973'}`. In `_finish()` add the case `'6973' => _shellx(text),` plus:

```dart
  static OscEvent? _shellx(String text) {
    final eq = text.indexOf('=');
    if (eq <= 0) return null;
    final value = text.substring(eq + 1);
    if (value.runes.any((r) => r < 0x20 || r == 0x7F || (r >= 0x80 && r <= 0x9F))) {
      return null;
    }
    return RemoteMetaReported(text.substring(0, eq), value);
  }
```

`command_tracker.dart`'s `handle` switches exhaustively over the sealed `OscEvent`: add `RemoteMetaReported()` to its no-op case (`NotifyRequested() || CwdReported() || KittyNotifyRequested() || BellRung() || RemoteMetaReported(): break;`).

In `cwd_url.dart`, add:

```dart
/// A8 D14: an SSH session's OSC 7 — any host, the decoded path as the
/// server sees it (no local check). Null when malformed, not absolute,
/// over 4096 characters or holding a NUL.
String? parseRemoteCwdPath(String url) {
  const scheme = 'file://';
  if (url.length <= scheme.length ||
      url.substring(0, scheme.length).toLowerCase() != scheme) {
    return null;
  }
  final rest = url.substring(scheme.length);
  final slash = rest.indexOf('/');
  if (slash < 0) return null;
  final path = _percentDecode(rest.substring(slash));
  if (path == null || path.contains('\u0000') || path.length > 4096) {
    return null;
  }
  return path;
}
```

- [ ] **Step 4: `LocalSessions`, `SessionSummary`, `SessionManager`**

`local_sessions.dart` — the `open` doc and signature:

```dart
  /// Starts a login shell in [cwd] when it is an absolute, local directory
  /// that exists (A3 D17), or — with [launch] — `ssh`/`tmux` as A8 D2
  /// describes ([cwd] is then ignored; a remote folder travels in the
  /// launch). Throws [SessionLimitException] or [SpawnFailedException]
  /// (`ssh_unavailable`, `tmux_unavailable`, `bad_launch` for A8).
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
    SessionLaunch? launch,
  });
```

`session_manager.dart`:

1. Imports: `'../remote/remote_tools.dart'`, `'../remote/session_launch.dart'`, `'../remote/ssh_command.dart'`, `'../remote/ssh_target.dart'`, `'../context/cwd_url.dart'` (already).

2. `SessionSummary` gains `this.remote` in the constructor and:

```dart
  /// A8: how this session reaches a server or a tmux session; null for a
  /// local shell.
  final SessionRemote? remote;
```

3. Next to `_Session`:

```dart
/// A8 D16, D17: what the server reported.
final class _RemoteState {
  _RemoteState(this.launch, {required this.connected});
  final SessionLaunch launch;
  bool connected;
  int? pid;
  String? home;
  Timer? plainTimer;
}
```

and in `_Session` a field `_RemoteState? remote;`.

4. Constructor parameters and fields:

```dart
    RemoteTools? remoteTools,
    Duration plainConnectedAfter = const Duration(seconds: 10),
    Duration remotePortInterval = const Duration(seconds: 5),
  }) : … ,
       _remoteTools = remoteTools,
       _plainConnectedAfter = plainConnectedAfter,
       …
```

```dart
  /// A8: ssh/tmux paths and the control helper; null = SSH unavailable.
  final RemoteTools? _remoteTools;
  final Duration _plainConnectedAfter;
```

5. `open` forwards `launch` to `_spawn(c, r, origin: SessionOrigin.desktop, cwd: cwd, tabId: tabId, launch: launch)`.

6. In `_spawn`, add the parameter `SessionLaunch? launch` and replace the try block that resolves the command with:

```dart
    try {
      final ShellLaunch started;
      final String workingDirectory;
      if (launch == null) {
        final command = await _shellResolver.resolve();
        workingDirectory = await _workingDirectoryFor(cwd);
        started = _launch(command /* A7: + pane/tab ids */);
      } else {
        workingDirectory = _homeDirectory;
        started = ShellLaunch(
          await _remoteCommand(launch),
          buildSessionEnvironment(_baseEnvironment /* A7: + pane/tab ids */),
        );
      }
      command = started.command;
      pty = _ptyFactory.spawn(
        started.command,
        workingDirectory: workingDirectory,
        environment: started.environment,
        cols: cols,
        rows: rows,
      );
    } on SpawnFailedException {
      rethrow;
    } catch (error) {
      throw SpawnFailedException('$error');
    } finally {
      _pendingOpens--;
    }
```

(Keep A7's id-before-spawn and environment additions exactly where A7 put them; only the branch on `launch` is new. `command` stays the variable the rest of `_spawn` reads for `shell: command.name`.)

After the session is registered (after `_sessions[session.id] = session;`):

```dart
    if (launch != null) _startRemote(session, launch);
```

7. New members:

```dart
  /// A8 D2, D3, D9, D12, D13, D25.
  Future<ShellCommand> _remoteCommand(SessionLaunch launch) async {
    final tools = _remoteTools;
    if (launch case TmuxLaunch(host: null)) {
      final tmux = tools?.tmuxPath;
      if (tmux == null) throw const SpawnFailedException('tmux_unavailable');
      return buildLocalTmuxCommand(launch, tmux);
    }
    final ssh = tools?.sshPath;
    if (ssh == null) throw const SpawnFailedException('ssh_unavailable');
    final target = launch.host!;
    final control = tools!.control;
    if (control != null && _connecting(target)) {
      await control.awaitMaster(target, stillWaiting: () => _connecting(target));
    }
    final keepalive = await (control?.keepaliveNeeded(target) ?? Future.value(true));
    control?.noteMaster(target);
    try {
      return buildSshCommand(
        launch,
        SshCommandOptions(sshPath: ssh, controlPath: control?.controlPath, keepalive: keepalive),
      );
    } on ArgumentError {
      throw const SpawnFailedException('bad_launch');
    }
  }

  /// D9: a session to [target] has not reached it yet.
  bool _connecting(SshTarget target) => _sessions.values.any(
    (s) =>
        !s.closing &&
        s.remote != null &&
        !s.remote!.connected &&
        s.remote!.launch.host == target,
  );

  static bool _usesBootstrap(SessionLaunch launch) => switch (launch) {
    SshLaunch(:final hook) => hook,
    TmuxLaunch(:final host, :final hook) => host != null && hook,
  };

  void _startRemote(_Session target, SessionLaunch launch) {
    final localTmux = launch is TmuxLaunch && launch.host == null;
    final remote = _RemoteState(launch, connected: localTmux);
    target.remote = remote;
    if (launch case TmuxLaunch(session: final name)) {
      // D26: a stable automatic title; tmux's own titles are ignored.
      target.title = 'tmux: $name';
    }
    if (!localTmux && !_usesBootstrap(launch)) {
      remote.plainTimer = Timer(_plainConnectedAfter, () {
        if (target.closing || remote.connected) return;
        remote.connected = true;
        _changes.add(null);
      });
    }
  }
```

8. `_track`: replace the title update and the `CwdReported`/`CommandFinished` cases, and add `RemoteMetaReported`:

```dart
      final title = session.titles.feed(data);
      final tmux = session.remote?.launch is TmuxLaunch;
      if (!tmux && title != null && title != session.title) {
        session.title = title;
        changed = true;
      }
      …
          case CwdReported(:final url):
            final changedCwd = session.remote != null
                ? _setRemoteCwd(session, url)
                : _setCwd(session, url);
            if (changedCwd) changed = true;
          case RemoteMetaReported(:final key, :final value):
            if (session.remote != null && _applyRemoteMeta(session, key, value)) {
              changed = true;
            }
          case CommandFinished():
            if (session.remote == null) _lookUpBranch(session, refresh: true);
```

```dart
  /// A8 D14.
  bool _setRemoteCwd(_Session session, String url) {
    final path = parseRemoteCwdPath(url);
    if (path == null || path == session.cwd) return false;
    session.cwd = path;
    return true;
  }

  /// A8 D16: hello / pid / home / branch from a remote session only.
  bool _applyRemoteMeta(_Session session, String key, String value) {
    final remote = session.remote!;
    switch (key) {
      case 'hello':
        if (remote.connected) return false;
        remote.connected = true;
        remote.plainTimer?.cancel();
        _remoteHello(remote.launch.host); // Task 6
        return true;
      case 'pid':
        if (!RegExp(r'^[0-9]{1,10}$').hasMatch(value)) return false;
        final pid = int.parse(value);
        if (pid < 1 || pid > 0x7FFFFFFF) return false;
        remote.pid = pid;
        _remoteShellsChanged(); // Task 6
        return false;
      case 'home':
        if (!value.startsWith('/') || value == remote.home) return false;
        remote.home = value;
        return true;
      case 'branch':
        if (value.length > 255) return false;
        final branch = value.isEmpty ? null : value;
        if (branch == session.gitBranch) return false;
        session.gitBranch = branch;
        return true;
    }
    return false;
  }

  // Task 6 fills these in.
  void _remoteHello(SshTarget? target) {}
  void _remoteShellsChanged() {}
```

9. `sessions` getter: add `remote: s.remote == null ? null : SessionRemote(launch: s.remote!.launch, connected: s.remote!.connected, home: s.remote!.home),`.

10. `_infos` (D36):

```dart
          cwd: context ? _phoneCwd(s) : '',
```

```dart
  String _phoneCwd(_Session s) {
    final cwd = s.cwd;
    if (cwd == null) return '';
    final host = s.remote?.launch.host;
    return host == null ? cwd : '${host.key}:$cwd';
  }
```

11. `_finish` and `closeSession`: `session.remote?.plainTimer?.cancel();`.

12. `_shellPids()`: skip `s.remote != null` (the local `ssh`/`tmux` process tree is not where the user's servers listen); `_applyPorts`: `if (s.remote != null) continue;` at the top of the loop.

If A5b is merged: `RemoteLocalSessions.open` gains the `launch` parameter and, until Task 13, throws `SpawnFailedException('ssh_unavailable')` when `launch != null`; `MuxServer` unchanged here.

- [ ] **Step 5: Run the tests**

Run:

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
```

Expected: PASS — the whole agent suite (local sessions unchanged) and the desktop suite with the extended fake.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent/lib/src/notify/osc_event_parser.dart packages/shellx_agent/lib/src/notify/command_tracker.dart packages/shellx_agent/lib/src/context/cwd_url.dart packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/test/support/session_rig.dart packages/shellx_agent/test/session/session_remote_test.dart packages/shellx_agent/test/notify/osc_event_parser_test.dart packages/shellx_agent/test/context/cwd_url_test.dart apps/desktop/test/support/fake_local_sessions.dart
# with A5b: also packages/shellx_agent/lib/src/mux/remote_local_sessions.dart
git commit -m "feat(agent): SSH and tmux sessions — open(launch:), OSC 6973 hello/pid/home/branch, remote cwd, master wait, SessionSummary.remote, host:path for phones (A8 D2, D9, D11, D14, D16, D17, D26, D36)"
```

---

### Task 6: Agent — `RemotePortWatcher` in `SessionManager` (D18)

**Files:**
- Create: `packages/shellx_agent/lib/src/remote/remote_port_watcher.dart`
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart`, `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/remote/remote_port_watcher_test.dart`, `packages/shellx_agent/test/session/session_remote_test.dart` (append)

**Interfaces:**
- Consumes: Task 2 `remoteProbeScript`, `parseRemoteProbe`; Task 4 `SshControl.runRemote`; Task 5 `_RemoteState`.
- Produces:
  - `final class RemoteShell { const RemoteShell({required SshTarget target, required int pid}); }`
  - `final class RemotePortWatcher { RemotePortWatcher({required SshControl control, required Map<int, RemoteShell> Function() shells, required void Function(Map<int, List<int>> ports) onPorts, Duration interval = const Duration(seconds: 5), Duration slowInterval = const Duration(seconds: 60), Duration timeout = const Duration(seconds: 4), int maxHosts = 16, void Function(String)? log}); void setVisible(bool); void sessionsChanged(); void resume(SshTarget); void dispose(); }` — `onPorts` gets **only** the sessions of the probed host (a partial update).

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/remote/remote_port_watcher_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final devbox = SshTarget.parse('devbox')!;
  final other = SshTarget.parse('other')!;
  const out = '#ps\n 10 1\n 11 10\n 20 1\n#ss\n'
      'LISTEN 0 1 127.0.0.1:8000 0.0.0.0:* users:(("p",pid=11,fd=3))\n';

  late List<List<String>> calls;
  late CommandResult Function(List<String>) answer;
  late List<Map<int, List<int>>> published;
  late Map<int, RemoteShell> shells;

  RemotePortWatcher watcher() => RemotePortWatcher(
    control: SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/sx',
      run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
        calls.add(args);
        return answer(args);
      },
    ),
    shells: () => shells,
    onPorts: published.add,
  );

  setUp(() {
    calls = [];
    published = [];
    answer = (_) => const CommandResult(0, out, '');
    shells = {
      1: RemoteShell(target: devbox, pid: 10),
      2: RemoteShell(target: devbox, pid: 20),
      3: RemoteShell(target: other, pid: 10),
    };
  });

  test('one probe per host while visible, every 5 s; ports per session (D18)', () {
    fakeAsync((async) {
      final w = watcher();
      w.sessionsChanged();
      async.flushTimers(flushPeriodicTimers: false);
      expect(calls, isEmpty); // hidden: nothing
      w.setVisible(true);
      async.elapse(Duration.zero);
      expect(calls, hasLength(2));
      expect(published, containsAll([
        {1: [8000], 2: <int>[]},
        {3: [8000]},
      ]));
      async.elapse(const Duration(seconds: 5));
      expect(calls, hasLength(4));
      w.setVisible(false);
      async.elapse(const Duration(seconds: 30));
      expect(calls, hasLength(4));
      w.dispose();
    });
  });

  test('3 failures → every 60 s; success → 5 s again', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      answer = (_) => const CommandResult(-1, '', '', timedOut: true);
      final w = watcher()..setVisible(true);
      async.elapse(const Duration(seconds: 11)); // t=0, 5, 10; next at 70
      expect(calls, hasLength(3));
      async.elapse(const Duration(seconds: 58)); // t=69
      expect(calls, hasLength(3));
      answer = (_) => const CommandResult(0, out, '');
      async.elapse(const Duration(seconds: 1));
      expect(calls, hasLength(4));
      async.elapse(const Duration(seconds: 5));
      expect(calls, hasLength(5));
      w.dispose();
    });
  });

  test('needs sign-in (255) stops probing that host until it says hello', () {
    fakeAsync((async) {
      shells = {1: RemoteShell(target: devbox, pid: 10)};
      answer = (_) => const CommandResult(255, '', 'Permission denied');
      final logs = <String>[];
      final w = RemotePortWatcher(
        control: SshControl(
          sshPath: '/usr/bin/ssh',
          run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
            calls.add(args);
            return answer(args);
          },
        ),
        shells: () => shells,
        onPorts: published.add,
        log: logs.add,
      )..setVisible(true);
      async.elapse(const Duration(seconds: 30));
      expect(calls, hasLength(1));
      expect(published.last, {1: <int>[]});
      expect(logs.join(), isNot(contains('devbox')));
      answer = (_) => const CommandResult(0, out, '');
      w.resume(devbox);
      async.elapse(Duration.zero);
      expect(calls, hasLength(2));
      w.dispose();
    });
  });

  test('every probe is BatchMode', () {
    fakeAsync((async) {
      watcher().setVisible(true);
      async.elapse(Duration.zero);
      expect(calls, everyElement(contains('BatchMode=yes')));
    });
  });
}
```

Append to `packages/shellx_agent/test/session/session_remote_test.dart`:

```dart
  test('remote ports reach the summary; local ports never overwrite them (D18)', () {
    fakeAsync((async) {
      final remote = tools();
      final probing = RemoteTools(
        sshPath: remote.sshPath,
        tmuxPath: remote.tmuxPath,
        control: SshControl(
          sshPath: '/usr/bin/ssh',
          run: (exe, args, {timeout = const Duration(seconds: 5)}) async =>
              args.first == '-G'
                  ? const CommandResult(0, 'serveraliveinterval 0\n', '')
                  : const CommandResult(0, '#ps\n 4242 1\n#ss\nLISTEN 0 1 *:8000 *:* users:(("p",pid=4242,fd=3))\n', ''),
        ),
      );
      final rig = SessionRig(remoteTools: probing);
      unawaited(rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox)));
      async.flushMicrotasks();
      rig.manager.watchPorts(true);
      rig.pty(0).emit('${osc('6973;hello=1')}${osc('6973;pid=4242')}');
      async.elapse(const Duration(milliseconds: 10));
      expect(rig.manager.sessions.single.ports, [8000]);
    });
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/remote/remote_port_watcher_test.dart test/session/session_remote_test.dart`
Expected: FAIL — `RemotePortWatcher` undefined; the summary has no remote ports.

- [ ] **Step 3: Implement the watcher**

`packages/shellx_agent/lib/src/remote/remote_port_watcher.dart`:

```dart
import 'dart:async';

import 'remote_probe.dart';
import 'ssh_control.dart';
import 'ssh_target.dart';

/// A remote session the watcher may probe: it said hello and its pid.
final class RemoteShell {
  const RemoteShell({required this.target, required this.pid});
  final SshTarget target;
  final int pid;
}

final class _Host {
  _Host(this.target);
  final SshTarget target;
  Timer? timer;
  bool running = false;
  bool stopped = false;
  int failures = 0;
}

/// A8 D18: listening ports on servers, one probe per server, only while
/// the window is shown. Logs never name the server (D37).
final class RemotePortWatcher {
  RemotePortWatcher({
    required SshControl control,
    required Map<int, RemoteShell> Function() shells,
    required void Function(Map<int, List<int>> ports) onPorts,
    this.interval = const Duration(seconds: 5),
    this.slowInterval = const Duration(seconds: 60),
    this.timeout = const Duration(seconds: 4),
    this.maxHosts = 16,
    void Function(String message)? log,
  }) : _control = control,
       _shells = shells,
       _onPorts = onPorts,
       _log = log;

  final SshControl _control;
  final Map<int, RemoteShell> Function() _shells;
  final void Function(Map<int, List<int>> ports) _onPorts;
  final void Function(String message)? _log;
  final Duration interval;
  final Duration slowInterval;
  final Duration timeout;
  final int maxHosts;

  final _hosts = <String, _Host>{};
  bool _visible = false;
  bool _disposed = false;

  void setVisible(bool visible) {
    _visible = visible;
    if (visible) {
      sessionsChanged();
      return;
    }
    for (final host in _hosts.values) {
      host.timer?.cancel();
      host.timer = null;
    }
  }

  /// A session of [target] said hello again: probe it again (D18).
  void resume(SshTarget target) {
    final host = _hosts[target.key];
    if (host == null) return;
    host.stopped = false;
    host.failures = 0;
    sessionsChanged();
  }

  void sessionsChanged() {
    if (_disposed) return;
    final targets = <String, SshTarget>{
      for (final shell in _shells().values) shell.target.key: shell.target,
    };
    for (final key in _hosts.keys.toList()) {
      if (!targets.containsKey(key)) _hosts.remove(key)!.timer?.cancel();
    }
    if (!_visible) return;
    for (final entry in targets.entries.take(maxHosts)) {
      final host = _hosts.putIfAbsent(entry.key, () => _Host(entry.value));
      if (host.stopped || host.running || host.timer != null) continue;
      host.timer = Timer(Duration.zero, () => _probe(entry.key));
    }
  }

  Future<void> _probe(String key) async {
    final host = _hosts[key];
    if (host == null || _disposed) return;
    host.timer = null;
    host.running = true;
    final result = await _control.runRemote(host.target, remoteProbeScript, timeout: timeout);
    host.running = false;
    if (_disposed || !identical(_hosts[key], host)) return;
    final shells = {
      for (final e in _shells().entries)
        if (e.value.target.key == key) e.key: e.value,
    };
    if (result.exitCode == 255 && !result.timedOut) {
      host.stopped = true;
      _log?.call('ssh probe: needs sign-in');
      _onPorts({for (final id in shells.keys) id: const <int>[]});
      return;
    }
    if (result.exitCode != 0 || result.timedOut) {
      host.failures++;
      _log?.call('ssh probe: failed (${result.timedOut ? 'timeout' : 'exit ${result.exitCode}'})');
    } else {
      host.failures = 0;
      final byPid = parseRemoteProbe(result.stdout, shells.values.map((s) => s.pid));
      _onPorts({
        for (final e in shells.entries) e.key: byPid[e.value.pid] ?? const <int>[],
      });
    }
    if (_visible && shells.isNotEmpty) {
      host.timer = Timer(host.failures >= 3 ? slowInterval : interval, () => _probe(key));
    }
  }

  void dispose() {
    _disposed = true;
    for (final host in _hosts.values) {
      host.timer?.cancel();
    }
    _hosts.clear();
  }
}
```

Export it from `packages/shellx_agent/lib/shellx_agent.dart`: `export 'src/remote/remote_port_watcher.dart';`.

- [ ] **Step 4: Wire it into `SessionManager`**

In the constructor body (next to the `PortWatcher` creation):

```dart
    if (remoteTools?.control case final control?) {
      _remotePorts = RemotePortWatcher(
        control: control,
        shells: _remoteShells,
        onPorts: _applyRemotePorts,
        interval: remotePortInterval,
        log: log,
      );
    }
```

Fields and helpers (replacing Task 5's two empty stubs):

```dart
  /// A8 D18; null without ssh.
  RemotePortWatcher? _remotePorts;

  Map<int, RemoteShell> _remoteShells() => {
    for (final s in _sessions.values)
      if (!s.closing &&
          !s.exited &&
          s.remote?.connected == true &&
          s.remote?.pid != null &&
          s.remote?.launch.host != null)
        s.id: RemoteShell(target: s.remote!.launch.host!, pid: s.remote!.pid!),
  };

  void _applyRemotePorts(Map<int, List<int>> ports) {
    var changed = false;
    for (final entry in ports.entries) {
      final s = _sessions[entry.key];
      if (s == null || s.remote == null || _sameInts(entry.value, s.ports)) continue;
      s.ports = List.unmodifiable(entry.value);
      changed = true;
    }
    if (changed) _changes.add(null);
  }

  void _remoteHello(SshTarget? target) {
    if (target != null) _remotePorts?.resume(target);
    _remotePorts?.sessionsChanged();
  }

  void _remoteShellsChanged() => _remotePorts?.sessionsChanged();
```

`watchPorts`: `_portWatcher?.setVisible(visible); _remotePorts?.setVisible(visible);`. In `_shellGone` and `_finish` also call `_remotePorts?.sessionsChanged()`. When the manager is torn down (wherever `_portWatcher` is disposed, or in `closeAll` if nothing disposes it) call `_remotePorts?.dispose()` in the same place.

`SessionCore` (desktop) passes `remotePortInterval: Platform.isWindows ? const Duration(seconds: 15) : const Duration(seconds: 5)` in Task 8.

- [ ] **Step 5: Run the tests**

Run: `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent/lib/src/remote/remote_port_watcher.dart packages/shellx_agent/lib/src/session/session_manager.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/remote/remote_port_watcher_test.dart packages/shellx_agent/test/session/session_remote_test.dart
git commit -m "feat(agent): remote listening ports — one BatchMode probe per server while the window shows, back-off, stop on sign-in, per-session descendants (A8 D18)"
```

---
### Task 7: Desktop — strings, remote panes in `TerminalTabs`, lost-connection line, `reconnect` in place (D17, D20–D22, D24)

**Files:**
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb` (+ regenerated `app_localizations*.dart`)
- Create: `apps/desktop/lib/src/remote/remote_state.dart`
- Modify: `apps/desktop/lib/src/terminal/pane_layout.dart`, `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `apps/desktop/lib/src/ui/terminal/terminal_overlays.dart`
- Test: `apps/desktop/test/terminal/pane_layout_test.dart` (append), `apps/desktop/test/terminal/terminal_tabs_remote_test.dart`, `apps/desktop/test/l10n/` (the existing ARB parity test must stay green)

**Interfaces:**
- Consumes: Task 1 `SessionLaunch`, `SessionRemote`; Task 5 `open(launch:)`, `SessionSummary.remote`, `FakeLocalSessions.openLaunches`; A7 `openTabFor`, `splitPane`, `OpenBusyException`, `PaneGoneException`.
- Produces:
  - Every A8 string of UI addendum §7 in both ARB files (keys exactly as listed there, except `tmuxTabTitle`, which the agent provides — D26).
  - `SessionLaunch launchWithoutHook(SessionLaunch)`; `enum RemoteState { connecting, connected, disconnected, failed, exited }`; `RemoteState? remoteStateOf({required SessionRemote? remote, required int? exitCode, required bool everConnected})` — null for local shells and local tmux.
  - `PaneSession.remote` (`SessionRemote?`), `PaneSession.everConnected` (`bool`), `PaneSession.remoteState`, `PaneSession.canReconnect`.
  - `PaneNode replaceLeaf(PaneNode node, int from, int to)`.
  - `final class PaneReplacement { const PaneReplacement({required int tabId, required int from, required int to}); }`; `TerminalTabs.paneReplacements` (`Stream<PaneReplacement>`, sync broadcast, emitted **before** the state change); `int TerminalTabs.resolveReplaced(int id)` (≤ 64 remembered); `Future<int?> TerminalTabs.reconnect(int sessionId, {bool withoutHook = false})`.
  - `TerminalTabs.openTab({SessionLaunch? launch})`, `openTabFor({String? cwd, SessionLaunch? launch, bool select = false})`, `split(SplitAxis axis, {bool local = false})`, `splitPane(int target, SplitAxis axis, {String? cwd, bool focus = false, bool local = false})`.
  - `final class SshUnavailableNotice extends TabNotice`, `final class TmuxUnavailableNotice extends TabNotice`, `final class RemotePortForwardFailedNotice extends TabNotice { final int port; }`; `TabNotice spawnNoticeFor(SpawnFailedException e)`.

- [ ] **Step 1: Strings**

Add to `apps/desktop/lib/l10n/app_en.arb` (before the closing brace; `@` entries as below), then the Vietnamese values to `app_vi.arb` — both exactly as UI addendum §7. English:

```json
  "sshConnectMenu": "Connect over SSH…",
  "tmuxAttachMenu": "Attach tmux session…",
  "sshDialogTitle": "Connect to a server",
  "sshDialogTabSsh": "SSH",
  "sshDialogTabTmux": "tmux",
  "sshHostLabel": "Server",
  "sshHostHint": "devbox or user@host:2222",
  "sshHostInvalid": "Not a valid server name",
  "sshSuggestionsConfig": "In ~/.ssh/config",
  "sshSuggestionsRecent": "Recent",
  "sshSuggestionsCount": "{count, plural, =1{1 suggestion} other{{count} suggestions}}",
  "@sshSuggestionsCount": {"placeholders": {"count": {"type": "int"}}},
  "sshRemoteDirLabel": "Folder on the server (optional)",
  "sshRemoteDirInvalid": "The path must start with / or ~",
  "sshNoHookLabel": "Don’t install the ShellX hook on this server",
  "sshNoHookHelp": "The hook tells ShellX the folder, branch and ports on the server. Turn it off for servers that aren’t Unix.",
  "sshConnectAction": "Connect",
  "sshUnavailable": "Can’t find the ssh command on this computer",
  "sshUnavailableWindows": "Can’t find ssh. Turn on “OpenSSH Client” in Settings → Apps → Optional features.",
  "tmuxSourceLabel": "tmux sessions on",
  "tmuxSourceLocal": "This computer",
  "tmuxLoading": "Loading sessions…",
  "tmuxEmpty": "No tmux sessions yet",
  "tmuxUnavailable": "tmux isn’t installed on {where}",
  "@tmuxUnavailable": {"placeholders": {"where": {"type": "String"}}},
  "tmuxListFailed": "Couldn’t list sessions on {where}. Connect to it over SSH once (so no password is needed), then try again.",
  "@tmuxListFailed": {"placeholders": {"where": {"type": "String"}}},
  "tmuxRetry": "Try again",
  "tmuxWindows": "{count, plural, =1{1 window} other{{count} windows}}",
  "@tmuxWindows": {"placeholders": {"count": {"type": "int"}}},
  "tmuxAttachedElsewhere": "attached elsewhere",
  "tmuxLastActive": "active {time}",
  "@tmuxLastActive": {"placeholders": {"time": {"type": "String"}}},
  "tmuxAttachAction": "Attach",
  "tmuxNewLabel": "New session name",
  "tmuxNameInvalid": "Use up to 64 characters, without “:” or “.”",
  "tmuxCreateAction": "Create and attach",
  "sidebarRemoteMark": "SSH: {host}",
  "@sidebarRemoteMark": {"placeholders": {"host": {"type": "String"}}},
  "sidebarTmuxMark": "tmux: {name}",
  "@sidebarTmuxMark": {"placeholders": {"name": {"type": "String"}}},
  "sidebarTmuxRemoteMark": "tmux: {name} · {host}",
  "@sidebarTmuxRemoteMark": {"placeholders": {"name": {"type": "String"}, "host": {"type": "String"}}},
  "sshStateConnecting": "Connecting to {host}",
  "@sshStateConnecting": {"placeholders": {"host": {"type": "String"}}},
  "sshStateDisconnected": "Lost connection to {host}",
  "@sshStateDisconnected": {"placeholders": {"host": {"type": "String"}}},
  "sshStateFailed": "Couldn’t connect to {host}",
  "@sshStateFailed": {"placeholders": {"host": {"type": "String"}}},
  "sshRetryIn": "{seconds, plural, =1{Retrying in 1 second} other{Retrying in {seconds} seconds}}",
  "@sshRetryIn": {"placeholders": {"seconds": {"type": "int"}}},
  "sshRetrying": "Reconnecting…",
  "sshAutoRetryStopped": "Stopped retrying",
  "sshFailedHookHint": "The server may not support the ShellX hook",
  "sshReconnectAction": "Reconnect",
  "sshRetryAction": "Try again",
  "sshRetryPlainAction": "Try without the hook",
  "sshClosePaneAction": "Close pane",
  "sshTmuxHint": "Run inside tmux to keep programs running when the connection drops",
  "sshDisconnectedLine": "[Lost connection to {host}] — press Enter to reconnect",
  "@sshDisconnectedLine": {"placeholders": {"host": {"type": "String"}}},
  "sshFailedLine": "[Couldn’t connect to {host}] — press Enter to try again",
  "@sshFailedLine": {"placeholders": {"host": {"type": "String"}}},
  "sshReconnectedDivider": "— Reconnected · {time} —",
  "@sshReconnectedDivider": {"placeholders": {"time": {"type": "String"}}},
  "workspaceNewRemoteTab": "New SSH tab on {host}",
  "@workspaceNewRemoteTab": {"placeholders": {"host": {"type": "String"}}},
  "workspaceNewLocalTab": "New local tab",
  "workspaceReconnectAll": "Reconnect all panes",
  "workspaceRemoteLabel": "SSH workspace {host}",
  "@workspaceRemoteLabel": {"placeholders": {"host": {"type": "String"}}},
  "rowReconnect": "Reconnect",
  "paneSplitLocalRight": "Split right on this computer",
  "remotePortTooltip": "Open port {port} on {host} (forwarded over SSH)",
  "@remotePortTooltip": {"placeholders": {"port": {"type": "int"}, "host": {"type": "String"}}},
  "remotePortForwarded": "localhost:{local} → {host}:{port}",
  "@remotePortForwarded": {"placeholders": {"local": {"type": "int"}, "host": {"type": "String"}, "port": {"type": "int"}}},
  "remotePortForwardFailed": "Couldn’t forward port {port}",
  "@remotePortForwardFailed": {"placeholders": {"port": {"type": "int"}}},
  "sshTrayMenu": "SSH",
  "sshTrayHook": "Install the ShellX hook on servers (folder, branch, ports)",
  "sshTrayClearRecent": "Clear recent servers",
  "sshRecentCleared": "Recent servers cleared",
  "sshAnnounceConnected": "Connected to {host}",
  "@sshAnnounceConnected": {"placeholders": {"host": {"type": "String"}}},
  "sshAnnounceDisconnected": "Lost connection to {host}",
  "@sshAnnounceDisconnected": {"placeholders": {"host": {"type": "String"}}},
  "sshAnnounceReconnected": "Reconnected to {host}",
  "@sshAnnounceReconnected": {"placeholders": {"host": {"type": "String"}}},
  "paneRemoteSuffix": ", on {host}",
  "@paneRemoteSuffix": {"placeholders": {"host": {"type": "String"}}}
```

`app_vi.arb` gets the same keys with the vi column of UI addendum §7 (no `@` entries, plurals as plain text like `sidebarPaneCount`): e.g. `"sshRetryIn": "Thử lại sau {seconds} giây"`, `"tmuxWindows": "{count} cửa sổ"`, `"sshSuggestionsCount": "{count} gợi ý"`, `"sshDisconnectedLine": "[Mất kết nối tới {host}] — Enter để kết nối lại"`, … (every row of §7). Regenerate:

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n && cd ../..
```

- [ ] **Step 2: Write the failing tests**

Append to `apps/desktop/test/terminal/pane_layout_test.dart`:

```dart
  test('replaceLeaf swaps one leaf, keeps shape and ratios (A8 D22)', () {
    const tree = PaneSplit(
      axis: SplitAxis.row,
      ratio: 0.3,
      first: PaneLeaf(1),
      second: PaneSplit(axis: SplitAxis.column, ratio: 0.6, first: PaneLeaf(2), second: PaneLeaf(3)),
    );
    expect(
      replaceLeaf(tree, 2, 9),
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: PaneLeaf(1),
        second: PaneSplit(axis: SplitAxis.column, ratio: 0.6, first: PaneLeaf(9), second: PaneLeaf(3)),
      ),
    );
    expect(replaceLeaf(tree, 7, 9), tree);
  });
```

(If `PaneSplit` has no value `==`, compare `paneIds(...)` and `nodeAt(...)` ratios instead.)

`apps/desktop/test/terminal/terminal_tabs_remote_test.dart`:

```dart
import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/remote_state.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

final devbox = SshTarget.parse('devbox')!;

SessionRemote ssh({bool connected = true}) =>
    SessionRemote(launch: SshLaunch(devbox), connected: connected, home: '/home/me');

void boot() {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('en'))),
    ],
  );
  state();
}

PaneSession pane(int id) => state().tabOfSession(id)!.panes[id]!;

/// The shell [id] died: gone from the listing, then its exit (as the agent does).
Future<void> lose(int id, int code) async {
  local.summaries.removeWhere((s) => s.id == id);
  local.views[id]!.end(code);
  await pumpEventQueue();
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('remote state follows the summary; everConnected sticks (D17)', () {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh(connected: false)));
    boot();
    expect(pane(1).remote!.hostKey, 'devbox');
    expect(pane(1).remoteState, RemoteState.connecting);
    expect(pane(1).everConnected, isFalse);
    local.replace(local.summary(1, origin: SessionOrigin.desktop, remote: ssh(), cwd: '/srv/app'));
    expect(pane(1).remoteState, RemoteState.connected);
    expect(pane(1).everConnected, isTrue);
    expect(pane(1).cwd, '/srv/app');
  });

  test('local shells and local tmux have no remote state', () {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2, origin: SessionOrigin.desktop, remote: const SessionRemote(launch: TmuxLaunch('main'), connected: true)));
    boot();
    expect(pane(1).remoteState, isNull);
    expect(pane(2).remoteState, isNull);
  });

  test('tabs open with a launch; splits inherit the server and its folder, '
      'or not when local (D24)', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh(), cwd: '/srv/app'));
    boot();
    await tabs().split(SplitAxis.row);
    expect(local.openLaunches.last, SshLaunch(devbox, remoteCwd: '/srv/app'));
    expect(local.openCwds.last, isNull);
    await tabs().split(SplitAxis.column, local: true);
    expect(local.openLaunches.last, isNull);
    await tabs().openTab(launch: const TmuxLaunch('main'));
    expect(local.openLaunches.last, const TmuxLaunch('main'));
  });

  test('a lost connection keeps the pane with a dim line; Enter reconnects '
      'in place — same terminal, tab id, focus, zoom (D20–D22)', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh(), cwd: '/srv/app'));
    boot();
    await tabs().split(SplitAxis.row, local: true); // pane 100, focused
    tabs().focusPane(1);
    tabs().toggleZoom();
    final replaced = <PaneReplacement>[];
    tabs().paneReplacements.listen(replaced.add);
    local.views[1]!.emit('hello\r\n');
    await pumpEventQueue();
    await lose(1, 255);
    final lost = pane(1);
    expect(lost.remoteState, RemoteState.disconnected);
    expect(lost.canReconnect, isTrue);
    final terminal = lost.terminal;
    expect(terminal.buffer.getText(), contains('[Lost connection to devbox] — press Enter to reconnect'));
    terminal.textInput('\r');
    await pumpEventQueue();
    expect(local.openLaunches.last, SshLaunch(devbox, remoteCwd: '/srv/app'));
    final fresh = local.nextId - 1;
    final tab = state().tabs.single;
    expect(tab.id, 1);
    expect(tab.paneOrder, [fresh, 100]);
    expect(tab.focusedPaneId, fresh);
    expect(tab.zoomedPaneId, fresh);
    expect(identical(tab.panes[fresh]!.terminal, terminal), isTrue);
    expect(tab.panes[fresh]!.everConnected, isTrue);
    expect(terminal.buffer.getText(), contains('hello'));
    expect(terminal.buffer.getText(), contains('— Reconnected · '));
    expect(replaced.single, const PaneReplacement(tabId: 1, from: 1, to: fresh));
    expect(tabs().resolveReplaced(1), fresh);
    expect(tabs().resolveReplaced(fresh), fresh);
    local.views[fresh]!.emit('world');
    await pumpEventQueue();
    expect(terminal.buffer.getText(), contains('world'));
    expect(local.views[1]!.disposed, isTrue);
  });

  test('never connected → failed line; any other exit after connecting → A1 exit line', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh(connected: false)));
    local.add(local.summary(2, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    await lose(1, 255);
    expect(pane(1).remoteState, RemoteState.failed);
    expect(pane(1).terminal.buffer.getText(), contains('[Couldn’t connect to devbox] — press Enter to try again'));
    await lose(2, 1);
    expect(pane(2).remoteState, RemoteState.exited);
    expect(pane(2).canReconnect, isFalse);
    expect(pane(2).terminal.buffer.getText(), contains('[Process exited with code 1]'));
    pane(2).terminal.textInput('\r');
    await pumpEventQueue();
    expect(state().tabOfSession(2), isNull); // Enter closes it (A3 D7)
  });

  test('reconnect: the pane closed meanwhile → the new shell is closed', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    await lose(1, 255);
    local.openGate = Completer<void>();
    final pending = tabs().reconnect(1);
    tabs().close(1);
    local.openGate!.complete();
    expect(await pending, isNull);
    expect(local.closed, contains(local.nextId - 1));
  });

  test('ssh / tmux missing → named toasts', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    local.openError = const SpawnFailedException('ssh_unavailable');
    await tabs().openTab(launch: SshLaunch(devbox));
    expect(state().notice, isA<SshUnavailableNotice>());
    local.openError = const SpawnFailedException('tmux_unavailable');
    await tabs().openTab(launch: const TmuxLaunch('main'));
    expect(state().notice, isA<TmuxUnavailableNotice>());
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/pane_layout_test.dart test/terminal/terminal_tabs_remote_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 4: Implement**

`apps/desktop/lib/src/remote/remote_state.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';

/// A8 D17, as the pane shows it.
enum RemoteState { connecting, connected, disconnected, failed, exited }

/// Null for a local shell and a tmux client on this computer (A1 rules).
/// UI-A8 §3.2 "Try without the hook" (D11).
SessionLaunch launchWithoutHook(SessionLaunch launch) => switch (launch) {
  SshLaunch(:final target, :final remoteCwd) => SshLaunch(target, remoteCwd: remoteCwd, hook: false),
  TmuxLaunch(:final session, :final host, :final create) =>
    TmuxLaunch(session, host: host, create: create, hook: false),
};

RemoteState? remoteStateOf({
  required SessionRemote? remote,
  required int? exitCode,
  required bool everConnected,
}) {
  if (remote == null || remote.launch.host == null) return null;
  if (exitCode != null) {
    if (!everConnected) return RemoteState.failed;
    return exitCode == 255 ? RemoteState.disconnected : RemoteState.exited;
  }
  return remote.connected ? RemoteState.connected : RemoteState.connecting;
}
```

`pane_layout.dart`, after `removePane`:

```dart
/// A8 D22: [node] with leaf [from] now holding [to]; unchanged when absent.
PaneNode replaceLeaf(PaneNode node, int from, int to) => switch (node) {
  PaneLeaf(:final sessionId) => sessionId == from ? PaneLeaf(to) : node,
  PaneSplit() => node.copyWith(
    first: replaceLeaf(node.first, from, to),
    second: replaceLeaf(node.second, from, to),
  ),
};
```

`terminal_tabs.dart`:

1. Imports: `'../remote/remote_state.dart'`.

2. Notices, after `PaneNoRoomNotice`:

```dart
/// A8 D3: no ssh binary.
final class SshUnavailableNotice extends TabNotice {
  const SshUnavailableNotice();
}

/// A8 D25: no tmux on this computer.
final class TmuxUnavailableNotice extends TabNotice {
  const TmuxUnavailableNotice();
}

/// A8 D19.
final class RemotePortForwardFailedNotice extends TabNotice {
  const RemotePortForwardFailedNotice(this.port);
  final int port;
}

TabNotice spawnNoticeFor(SpawnFailedException error) => switch (error.message) {
  'ssh_unavailable' => const SshUnavailableNotice(),
  'tmux_unavailable' => const TmuxUnavailableNotice(),
  _ => SpawnFailedNotice(spawnFailureOf(error.message)),
};

/// A8 D22: pane [from] of tab [tabId] is now session [to].
@immutable
final class PaneReplacement {
  const PaneReplacement({required this.tabId, required this.from, required this.to});
  final int tabId;
  final int from;
  final int to;
  @override
  bool operator ==(Object other) =>
      other is PaneReplacement && other.tabId == tabId && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(tabId, from, to);
}

/// A8 D22.
const int kReplacedMemory = 64;
```

Replace every `SpawnFailedNotice(spawnFailureOf(error.message))` in `TerminalTabs` with `spawnNoticeFor(error)`.

3. `PaneSession`: constructor `this.remote, this.everConnected = false,`; fields:

```dart
  /// A8: the session's remote launch and state; null for a local shell.
  final SessionRemote? remote;

  /// A8 D17: this pane reached its server at least once (kept across
  /// reconnects, so a retry that fails is "disconnected", not "failed").
  final bool everConnected;

  RemoteState? get remoteState => remoteStateOf(
    remote: remote,
    exitCode: exitCode,
    everConnected: everConnected,
  );

  bool get canReconnect => switch (remoteState) {
    RemoteState.disconnected || RemoteState.failed => true,
    _ => false,
  };
```

`copyWith` gains `Object? remote = _unset, bool? everConnected` and passes `remote: identical(remote, _unset) ? this.remote : remote as SessionRemote?, everConnected: everConnected ?? this.everConnected`.

4. `_merge`: in the pane `copyWith`, add `remote: s.remote, everConnected: p.everConnected || (s.remote?.connected ?? false),`.

5. `_attach(SessionSummary s, {TerminalGrid? size, DesktopTerminal? reuse, String? preface})`:

```dart
    final terminal = reuse ?? DesktopTerminal(platform: _platform());
    final feed = TerminalFeed(terminal.write);
    final link = _Link(view, terminal, feed);
    _links[s.id] = link;
    final grid = size ?? _grid;
    if (reuse == null) terminal.resize(grid.cols, grid.rows);
    if (preface != null) feed.add(Uint8List.fromList(utf8.encode(preface)));
    feed.add(view.backlog);
    feed.drain();
```

and the returned `PaneSession(…)` gets `remote: s.remote, everConnected: s.remote?.connected ?? false`. (Import `dart:typed_data` if not already.)

6. Opens with a launch — `openTab({SessionLaunch? launch})` passes `launch: launch` to `_local.open`; `openTabFor({String? cwd, SessionLaunch? launch, bool select = false})` likewise (A7 body unchanged otherwise). In `split` and `splitPane`, replace the `_local.open(...)` call with:

```dart
      final remote = pane.remote;
      final launch = local ? null : remote?.launch.forSplit(cwd ?? pane.cwd);
      final id = await _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: local || remote != null ? null : (cwd ?? pane.cwd),
        tabId: tab.id,
        launch: launch,
      );
```

(`split` has no `cwd` parameter: use `pane.cwd` there.) Add `{bool local = false}` to both signatures.

7. Lost connection in `_exited`, right after `link.feed.drain(); final terminal = link.terminal;`:

```dart
    final pane = state.tabOfSession(id)?.panes[id];
    final lost = pane == null
        ? null
        : remoteStateOf(remote: pane.remote, exitCode: code, everConnected: pane.everConnected);
    if (lost == RemoteState.disconnected || lost == RemoteState.failed) {
      final l10n = ref.read(appL10nProvider);
      final host = pane!.remote!.hostKey!;
      final line = lost == RemoteState.disconnected
          ? l10n.sshDisconnectedLine(host)
          : l10n.sshFailedLine(host);
      final newline = terminal.buffer.cursorX == 0 ? '' : '\r\n';
      // UI-A8 §3.2: dim, nothing red, cursor hidden (as A1's exit line).
      terminal.write('$newline\x1b[2m$line\x1b[0m\x1b[?25l');
      _updatePane(id, (p) => p.copyWith(exitCode: code));
      return;
    }
```

8. `_onUserInput`, the exited branch:

```dart
    if (pane.exited) {
      // UI §2.6 / UI-A8 §3.2: Enter closes an exited pane, or reconnects a
      // lost one; other keys are ignored.
      if (data.contains('\r')) {
        if (pane.canReconnect) {
          unawaited(reconnect(id));
        } else {
          _removePane(id);
        }
      }
      return;
    }
```

9. Reconnect and replacement (new members of `TerminalTabs`; dispose the controller in `_dispose`):

```dart
  final _replacements = StreamController<PaneReplacement>.broadcast(sync: true);
  final _replaced = <int, int>{};
  final _reconnecting = <int>{};

  /// A8 D22: emitted before the tab changes, so listeners can move what
  /// they keep for [PaneReplacement.from] first.
  Stream<PaneReplacement> get paneReplacements => _replacements.stream;

  /// A8 D22: the pane a reconnect made of [id] (followed along a chain);
  /// [id] itself when it was never replaced.
  int resolveReplaced(int id) {
    var current = id;
    for (var i = 0; i < kReplacedMemory; i++) {
      final next = _replaced[current];
      if (next == null) break;
      current = next;
    }
    return current;
  }

  /// A8 D20–D22: a new session for the lost pane [sessionId], in the same
  /// place of the same tab, writing into the same terminal. Null when the
  /// pane cannot reconnect, ShellX stayed busy opening for 10 s, the pane
  /// went meanwhile, or the open failed (with its toast).
  Future<int?> reconnect(int sessionId, {bool withoutHook = false}) async {
    if (!_reconnecting.add(sessionId)) return null;
    try {
      for (var i = 0; state.opening; i++) {
        if (i >= 200 || !ref.mounted) return null;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final before = state.tabOfSession(sessionId);
      final pane = before?.panes[sessionId];
      if (before == null || pane == null || !pane.canReconnect) return null;
      var launch = pane.remote!.launch.forReconnect(pane.cwd);
      if (withoutHook) launch = launchWithoutHook(launch); // UI-A8 §3.2
      final grid = (
        cols: max(1, pane.terminal.viewWidth),
        rows: max(1, pane.terminal.viewHeight),
      );
      _set(opening: true);
      _awaitingOpen = true;
      var synced = false;
      try {
        final id = await _local.open(
          cols: grid.cols,
          rows: grid.rows,
          tabId: before.id,
          launch: launch,
        );
        if (!ref.mounted) return id;
        _awaitingOpen = false;
        final tab = state.tabOfSession(sessionId);
        if (tab == null) {
          _local.close(id); // the pane was closed while we connected
          return null;
        }
        final summary = _local.sessions.where((s) => s.id == id).firstOrNull;
        if (summary == null) return null; // ended already: still lost
        final old = tab.panes[sessionId]!;
        final next = _attach(
          summary,
          size: grid,
          reuse: old.terminal,
          preface: _reconnectedDivider(),
        );
        if (next == null) return null;
        _swapPane(
          tab,
          sessionId,
          next.copyWith(everConnected: old.everConnected || next.everConnected),
        );
        _sync();
        synced = true;
        return id;
      } on SessionLimitException catch (error) {
        if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
        return null;
      } on SpawnFailedException catch (error) {
        if (ref.mounted) _set(notice: spawnNoticeFor(error));
        return null;
      } finally {
        _awaitingOpen = false;
        if (ref.mounted) {
          if (!synced) _sync();
          _set(opening: false);
        }
      }
    } finally {
      _reconnecting.remove(sessionId);
    }
  }

  /// UI-A8 §3.4: cursor back, a dim divider with the time (A5a D23 style).
  String _reconnectedDivider() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line = ref.read(appL10nProvider).sshReconnectedDivider('${two(now.hour)}:${two(now.minute)}');
    return '\x1b[?25h\r\n\x1b[0m\x1b[2m$line\x1b[0m\r\n';
  }

  void _swapPane(TerminalTab tab, int from, PaneSession pane) {
    final to = pane.id;
    _replaced[from] = to;
    while (_replaced.length > kReplacedMemory) {
      _replaced.remove(_replaced.keys.first);
    }
    _replacements.add(PaneReplacement(tabId: tab.id, from: from, to: to));
    _links.remove(from)?.dispose(); // the terminal stays: it moved to [pane]
    int map(int id) => id == from ? to : id;
    final zoomed = tab.zoomedPaneId;
    _replaceTab(
      tab.copyWith(
        layout: replaceLeaf(tab.layout, from, to),
        panes: {
          for (final e in tab.panes.entries)
            if (e.key == from) to: pane else e.key: e.value,
        },
        focusedPaneId: map(tab.focusedPaneId),
        zoomedPaneId: zoomed == null ? null : map(zoomed),
        paneHistory: [for (final id in tab.paneHistory) map(id)],
      ),
    );
    if (state.selectedId == tab.id) _visibleChanged();
  }
```

`_Link.dispose()` must not dispose the terminal (it does not today: it disposes subscriptions, feed, view, selection — keep it that way and add a comment).

10. `terminal_overlays.dart` — the notice switch gains:

```dart
    SshUnavailableNotice() => defaultTargetPlatform == TargetPlatform.windows
        ? l10n.sshUnavailableWindows
        : l10n.sshUnavailable,
    TmuxUnavailableNotice() => l10n.tmuxUnavailable(l10n.tmuxSourceLocal),
    RemotePortForwardFailedNotice(:final port) => l10n.remotePortForwardFailed(port),
```

(all three are error toasts — `noticeBg` style of A1 §2.8).

- [ ] **Step 5: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test`
Expected: PASS (whole desktop suite: A3 pane tests unchanged).

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/l10n/ apps/desktop/lib/src/remote/remote_state.dart apps/desktop/lib/src/terminal/pane_layout.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/terminal_overlays.dart apps/desktop/test/terminal/pane_layout_test.dart apps/desktop/test/terminal/terminal_tabs_remote_test.dart
git commit -m "feat(desktop): remote panes — launch on opens and splits, lost-connection line, reconnect in place keeping the terminal, id forwarding, A8 strings (A8 D17, D20-D22, D24)"
```

---

### Task 8: Desktop — settings, `Workspace.ssh`, `SshActions`, tools wiring (D6, D11, D23, D25, D42)

**Files:**
- Create: `apps/desktop/lib/src/remote/remote_tools_provider.dart`, `apps/desktop/lib/src/remote/ssh_settings.dart`, `apps/desktop/lib/src/remote/ssh_actions.dart`
- Modify: `apps/desktop/lib/src/platform/settings_store.dart`, `apps/desktop/lib/src/terminal/sidebar_workspaces.dart`, `apps/desktop/lib/src/agent/session_core.dart`, `apps/desktop/lib/main.dart` (and, with A5b, `apps/desktop/lib/daemon_main.dart`)
- Test: `apps/desktop/test/terminal/sidebar_workspaces_ssh_test.dart`, `apps/desktop/test/remote/ssh_actions_test.dart`, the settings key test (`SettingKeys.all`)

**Interfaces:**
- Consumes: Task 2 `readSshConfigHosts`, `classifyTmuxList`; Task 3 `remoteTmuxListScript`; Task 4 `RemoteTools`, `resolveRemoteTools`; Task 7 `openTab(launch:)`, `openTabFor(launch:)`.
- Produces:
  - `SettingKeys.sshRecentTargets = 'ssh_recent_targets'`, `sshPlainTargets = 'ssh_plain_targets'`, `sshRemoteHook = 'ssh_remote_hook'` (in `all` and, with A5b, `UiSettingKeys`).
  - `final remoteToolsProvider = Provider<RemoteTools>(…)` (overridden in `main.dart`); `final commandRunnerProvider = Provider<CommandRunner>((_) => runCommand)`; `final sshConfigHostsProvider = Provider<Future<List<String>> Function()>(…)`.
  - `bool sshHookFor(SettingsStore, String key)`; `List<SshTarget> recentTargets(SettingsStore)`; `Future<void> rememberTarget(SettingsStore, SshTarget)`; `Future<void> setPlainTarget(SettingsStore, String key, {required bool plain})`; `Future<void> clearRecentTargets(SettingsStore)`.
  - `Workspace.ssh` (`String?`, a valid `SshTarget.key`); `SidebarWorkspaces.workspaceForHost(String key) → String?`; `SidebarWorkspaces.createForHost(SshTarget target, {bool makeCurrent = true}) → String`; `SidebarWorkspaces.launchFor(String workspaceId) → SessionLaunch?`; `SidebarWorkspaces.openTabIn(String id, {SessionLaunch? launch})`.
  - `final sshActionsProvider = Provider<SshActions>(SshActions.new)`; `SshActions { bool hookFor(String key); Future<void> newTab(); Future<void> connect(SshTarget, {String? remoteCwd, bool? noHook}); Future<int> connectForCli(SshTarget, {String? workspaceId, String? remoteCwd, bool hook = true, bool select = false}); Future<TmuxListResult> listTmux(SshTarget? host); Future<void> attachTmux(String name, {SshTarget? host, bool create = false}); Future<int> attachTmuxForCli(String name, {SshTarget? host, bool create = false, bool select = false}); Future<SshSuggestions> suggestions(); Future<void> clearRecent(); }`; `final class SshSuggestions { final List<String> config; final List<String> recent; }`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/terminal/sidebar_workspaces_ssh_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';

import '../support/fake_local_sessions.dart';

void main() {
  test('Workspace.ssh round-trips; a bad or non-canonical value is dropped, '
      'the workspace kept (D23)', () {
    const w = Workspace(id: 'w1', name: 'devbox', ssh: 'me@devbox:2222');
    expect(Workspace.decode(w.encode()), w);
    expect(Workspace.decode('{"id":"w2","name":"x","ssh":"-oProxyCommand=y"}')!.ssh, isNull);
    expect(Workspace.decode('{"id":"w3","name":"x","ssh":"ssh://devbox"}')!.ssh, isNull);
    expect(Workspace.decode('{"id":"w4","name":"x","ssh":7}')!.ssh, isNull);
    expect(Workspace.decode('{"id":"w5","name":"x"}')!.ssh, isNull);
  });

  test('createForHost, workspaceForHost, launchFor, openTabIn opens SSH', () async {
    final local = FakeLocalSessions();
    final settings = InMemorySettingsStore();
    final container = ProviderContainer.test(overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
    ]);
    final side = container.read(sidebarWorkspacesProvider.notifier);
    final devbox = SshTarget.parse('devbox')!;
    expect(side.workspaceForHost('devbox'), isNull);
    final id = side.createForHost(devbox);
    final state = container.read(sidebarWorkspacesProvider);
    expect(state.currentId, id);
    expect(state.renaming, isNull);
    expect(state.workspace(id)!.name, 'devbox');
    expect(side.workspaceForHost('devbox'), id);
    expect(side.launchFor(id), SshLaunch(devbox));
    expect(side.launchFor(kDefaultWorkspaceId), isNull);
    await settings.setStrings(SettingKeys.sshPlainTargets, ['devbox']);
    expect(side.launchFor(id), SshLaunch(devbox, hook: false));
    await side.openTabIn(id);
    expect(local.openLaunches.single, SshLaunch(devbox, hook: false));
    expect(container.read(sidebarWorkspacesProvider).tabsOf(id), [100]);
    expect(settings.getStrings(SettingKeys.terminalWorkspaces).join(), contains('"ssh":"devbox"'));
  });
}
```

`apps/desktop/test/remote/ssh_actions_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/remote/ssh_actions.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late InMemorySettingsStore settings;
  late ProviderContainer container;
  late List<List<String>> runs;
  late CommandResult Function(String exe, List<String> args) answer;

  final devbox = SshTarget.parse('devbox')!;

  setUp(() {
    local = FakeLocalSessions();
    settings = InMemorySettingsStore();
    runs = [];
    answer = (_, _) => const CommandResult(0, 'main\t2\t0\t1759831200\n', '');
    Future<CommandResult> run(String exe, List<String> args, {Duration timeout = const Duration(seconds: 5)}) async {
      runs.add([exe, ...args]);
      return answer(exe, args);
    }

    container = ProviderContainer.test(overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
      commandRunnerProvider.overrideWithValue(run),
      remoteToolsProvider.overrideWithValue(RemoteTools(
        sshPath: '/usr/bin/ssh',
        tmuxPath: '/opt/homebrew/bin/tmux',
        control: SshControl(sshPath: '/usr/bin/ssh', run: run),
      )),
      sshConfigHostsProvider.overrideWithValue(() async => ['devbox', 'db']),
    ]);
  });

  SshActions actions() => container.read(sshActionsProvider);
  SidebarState side() => container.read(sidebarWorkspacesProvider);

  test('connect: the server\'s workspace (made once), recent targets (D23)', () async {
    await actions().connect(devbox, remoteCwd: '/srv');
    await actions().connect(devbox);
    final id = container.read(sidebarWorkspacesProvider.notifier).workspaceForHost('devbox')!;
    expect(side().workspaces.where((w) => w.ssh == 'devbox'), hasLength(1));
    expect(side().tabsOf(id), [100, 101]);
    expect(local.openLaunches, [SshLaunch(devbox, remoteCwd: '/srv'), SshLaunch(devbox)]);
    expect(settings.getStrings(SettingKeys.sshRecentTargets), ['devbox']);
    for (var i = 0; i < 12; i++) {
      await actions().connect(SshTarget.parse('h$i')!);
    }
    final recent = settings.getStrings(SettingKeys.sshRecentTargets);
    expect(recent, hasLength(10));
    expect(recent.first, 'h11');
  });

  test('connect with the box ticked remembers "no hook" for that server (D11)', () async {
    await actions().connect(devbox, noHook: true);
    expect(local.openLaunches.single, SshLaunch(devbox, hook: false));
    expect(actions().hookFor('devbox'), isFalse);
    await actions().connect(devbox, noHook: false);
    expect(actions().hookFor('devbox'), isTrue);
    await settings.setBool(SettingKeys.sshRemoteHook, false);
    expect(actions().hookFor('devbox'), isFalse);
  });

  test('⌘T: local in a local workspace, SSH in an SSH workspace', () async {
    await actions().newTab();
    expect(local.openLaunches.last, isNull);
    await actions().connect(devbox);
    await actions().newTab();
    expect(local.openLaunches.last, SshLaunch(devbox));
  });

  test('tmux: list here and on a server; attach places the tab (D25, D26)', () async {
    final here = await actions().listTmux(null);
    expect((here as TmuxSessions).sessions.single.name, 'main');
    expect(runs.last, ['/opt/homebrew/bin/tmux', 'list-sessions', '-F', tmuxListFormat]);
    final there = await actions().listTmux(devbox);
    expect(there, isA<TmuxSessions>());
    expect(runs.last, containsAll(['BatchMode=yes', '--', 'devbox']));
    answer = (_, _) => const CommandResult(255, '', '');
    expect(await actions().listTmux(devbox), isA<TmuxListFailed>());
    await actions().attachTmux('main');
    expect(local.openLaunches.last, const TmuxLaunch('main'));
    await actions().attachTmux('main', host: devbox, create: true);
    expect(local.openLaunches.last, TmuxLaunch('main', host: devbox, create: true));
    final id = container.read(sidebarWorkspacesProvider.notifier).workspaceForHost('devbox')!;
    expect(side().tabsOf(id), contains(local.nextId - 1));
  });

  test('suggestions: config then recent, recent without duplicates of config', () async {
    await actions().connect(SshTarget.parse('me@x:2222')!);
    await actions().connect(devbox);
    final s = await actions().suggestions();
    expect(s.config, ['devbox', 'db']);
    expect(s.recent, ['me@x:2222']);
    await actions().clearRecent();
    expect((await actions().suggestions()).recent, isEmpty);
  });

  test('CLI connect does not move focus and lands in the server workspace', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop)); // the user's tab, selected
    final tab = await actions().connectForCli(devbox, select: false);
    expect(container.read(terminalTabsProvider).selectedId, 1);
    final id = container.read(sidebarWorkspacesProvider.notifier).workspaceForHost('devbox')!;
    expect(side().tabsOf(id), [tab]);
    expect(side().currentId, kDefaultWorkspaceId);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/sidebar_workspaces_ssh_test.dart test/remote/ssh_actions_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement**

`settings_store.dart` — keys (and add them to `all`; with A5b also to `UiSettingKeys`):

```dart
  /// A8 D6: the last 10 servers connected to, newest first.
  static const String sshRecentTargets = 'ssh_recent_targets';

  /// A8 D11: servers that get no ShellX hook.
  static const String sshPlainTargets = 'ssh_plain_targets';

  /// A8 D11: tray "Install the ShellX hook on servers" (default on).
  static const String sshRemoteHook = 'ssh_remote_hook';
```

`apps/desktop/lib/src/remote/remote_tools_provider.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

/// A8: what `main.dart` resolved once (`resolveRemoteTools`); empty until
/// overridden (tests, early startup).
final remoteToolsProvider = Provider<RemoteTools>((ref) => const RemoteTools());

final commandRunnerProvider = Provider<CommandRunner>((ref) => runCommand);

/// D6: `~/.ssh/config` hosts, read fresh each time the dialog opens.
final sshConfigHostsProvider = Provider<Future<List<String>> Function()>(
  (ref) => () => readSshConfigHosts(
    home: Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '',
    windows: Platform.isWindows,
  ),
);
```

`apps/desktop/lib/src/remote/ssh_settings.dart`:

```dart
import 'package:shellx_agent/shellx_agent.dart';

import '../platform/settings_store.dart';

const int kRecentTargets = 10;

/// D11: the global switch and the per-server list.
bool sshHookFor(SettingsStore settings, String key) =>
    settings.getBool(SettingKeys.sshRemoteHook, defaultValue: true) &&
    !settings.getStrings(SettingKeys.sshPlainTargets).contains(key);

/// D6: stored keys that still parse (the file is user-editable).
List<SshTarget> recentTargets(SettingsStore settings) => [
  for (final key in settings.getStrings(SettingKeys.sshRecentTargets))
    if (SshTarget.parse(key) case final t? when t.key == key) t,
];

Future<void> rememberTarget(SettingsStore settings, SshTarget target) {
  final next = [
    target.key,
    for (final t in recentTargets(settings))
      if (t.key != target.key) t.key,
  ].take(kRecentTargets).toList();
  return settings.setStrings(SettingKeys.sshRecentTargets, next);
}

Future<void> setPlainTarget(SettingsStore settings, String key, {required bool plain}) {
  final current = settings.getStrings(SettingKeys.sshPlainTargets).where((k) => k != key);
  return settings.setStrings(SettingKeys.sshPlainTargets, [...current, if (plain) key]);
}

Future<void> clearRecentTargets(SettingsStore settings) =>
    settings.setStrings(SettingKeys.sshRecentTargets, const []);
```

`sidebar_workspaces.dart`:

- `Workspace` gains `this.ssh` (constructor), the field

```dart
  /// A8 D23: the server this workspace opens tabs on ([SshTarget.key]);
  /// null for a local workspace.
  final String? ssh;
```

`copyWith` keeps `ssh`; `encode()` adds `if (ssh != null) 'ssh': ssh`; `decode` reads it leniently:

```dart
    final rawSsh = value['ssh'];
    final ssh = rawSsh is String && SshTarget.parse(rawSsh)?.key == rawSsh ? rawSsh : null;
    …
    return Workspace(id: id, name: …, collapsed: …, ssh: id == kDefaultWorkspaceId ? null : ssh);
```

`==`/`hashCode` include `ssh`.

- `SidebarWorkspaces`:

```dart
  /// A8 D23: the first workspace (sidebar order) for server [key].
  String? workspaceForHost(String key) {
    for (final w in state.workspaces) {
      if (w.ssh == key) return w.id;
    }
    return null;
  }

  /// A8 D23: "devbox" at the end, no name field; current unless the CLI
  /// made it ([makeCurrent] false).
  String createForHost(SshTarget target, {bool makeCurrent = true}) {
    final id = _newId();
    state = state.copyWith(
      workspaces: [
        ...state.workspaces,
        Workspace(id: id, name: _clip(target.key), ssh: target.key),
      ],
      members: {...state.members, id: const <int>[]},
      currentId: makeCurrent ? id : state.currentId,
    );
    _save();
    return id;
  }

  /// A8 D23: what a new tab in [workspaceId] runs.
  SessionLaunch? launchFor(String workspaceId) {
    final key = state.workspace(workspaceId)?.ssh;
    final target = key == null ? null : SshTarget.parse(key);
    if (target == null) return null;
    return SshLaunch(target, hook: sshHookFor(ref.read(settingsStoreProvider), key!));
  }
```

and `openTabIn(String id, {SessionLaunch? launch})` calls `await _tabs.openTab(launch: launch ?? launchFor(id));`.

`apps/desktop/lib/src/remote/ssh_actions.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'remote_tools_provider.dart';
import 'ssh_settings.dart';

final class SshSuggestions {
  const SshSuggestions({required this.config, required this.recent});
  final List<String> config;
  final List<String> recent;
}

final sshActionsProvider = Provider<SshActions>(SshActions.new);

/// The one way in for keys, menus, the dialog, the tray and the CLI (A8).
final class SshActions {
  SshActions(this._ref);
  final Ref _ref;

  SettingsStore get _settings => _ref.read(settingsStoreProvider);
  SidebarWorkspaces get _side => _ref.read(sidebarWorkspacesProvider.notifier);
  TerminalTabs get _tabs => _ref.read(terminalTabsProvider.notifier);
  RemoteTools get _tools => _ref.read(remoteToolsProvider);

  bool hookFor(String key) => sshHookFor(_settings, key);

  String _workspaceFor(SshTarget target, {bool makeCurrent = true}) =>
      _side.workspaceForHost(target.key) ??
      _side.createForHost(target, makeCurrent: makeCurrent);

  /// ⌘T, sidebar `+` (D23).
  Future<void> newTab() async {
    final side = _ref.read(sidebarWorkspacesProvider);
    if (side.workspace(side.currentId)?.ssh != null) {
      return _side.openTabIn(side.currentId);
    }
    return _tabs.openTab();
  }

  /// The dialog's Connect (D23, D42). [noHook] is the box's value when the
  /// user could see it (null: leave the per-server setting alone).
  Future<void> connect(SshTarget target, {String? remoteCwd, bool? noHook}) async {
    if (noHook != null) await setPlainTarget(_settings, target.key, plain: noHook);
    await rememberTarget(_settings, target);
    await _side.openTabIn(
      _workspaceFor(target),
      launch: SshLaunch(target, remoteCwd: remoteCwd, hook: hookFor(target.key)),
    );
  }

  /// A7 `shellx ssh` (D33): no focus change unless [select]. Throws what
  /// `openTabFor` throws.
  Future<int> connectForCli(
    SshTarget target, {
    String? workspaceId,
    String? remoteCwd,
    bool hook = true,
    bool select = false,
  }) async {
    final workspace = workspaceId ?? _workspaceFor(target, makeCurrent: select);
    final tab = await _tabs.openTabFor(
      launch: SshLaunch(target, remoteCwd: remoteCwd, hook: hook && hookFor(target.key)),
      select: select,
    );
    _side.moveTab(tab, workspace);
    await rememberTarget(_settings, target);
    return tab;
  }

  /// D25: here, or on [host] without ever prompting.
  Future<TmuxListResult> listTmux(SshTarget? host) async {
    if (host == null) {
      final tmux = _tools.tmuxPath;
      if (tmux == null) return const TmuxUnavailable();
      final run = _ref.read(commandRunnerProvider);
      final r = await run(tmux, ['list-sessions', '-F', tmuxListFormat], timeout: const Duration(seconds: 5));
      return classifyTmuxList(r, remote: false);
    }
    final control = _tools.control;
    if (control == null) return const TmuxListFailed(TmuxListFailure.other);
    final r = await control.runRemote(host, remoteTmuxListScript(), timeout: const Duration(seconds: 5));
    return classifyTmuxList(r, remote: true);
  }

  TmuxLaunch _tmuxLaunch(String name, SshTarget? host, bool create) => TmuxLaunch(
    name,
    host: host,
    create: create,
    hook: host == null || hookFor(host.key),
  );

  /// D26: a server's session goes to its workspace; a local one to the
  /// current workspace.
  Future<void> attachTmux(String name, {SshTarget? host, bool create = false}) async {
    final launch = _tmuxLaunch(name, host, create);
    if (host == null) return _tabs.openTab(launch: launch);
    await rememberTarget(_settings, host);
    await _side.openTabIn(_workspaceFor(host), launch: launch);
  }

  Future<int> attachTmuxForCli(
    String name, {
    SshTarget? host,
    bool create = false,
    bool select = false,
  }) async {
    final tab = await _tabs.openTabFor(launch: _tmuxLaunch(name, host, create), select: select);
    if (host != null) _side.moveTab(tab, _workspaceFor(host, makeCurrent: select));
    return tab;
  }

  /// D6: config names, then recent ones not already listed.
  Future<SshSuggestions> suggestions() async {
    final config = await _ref.read(sshConfigHostsProvider)();
    final recent = [
      for (final t in recentTargets(_settings))
        if (!config.contains(t.key)) t.key,
    ];
    return SshSuggestions(config: config, recent: recent);
  }

  Future<void> clearRecent() => clearRecentTargets(_settings);
}
```

`session_core.dart`: `SessionCore` factory gains `RemoteTools? remoteTools` and passes `remoteTools: remoteTools, remotePortInterval: Platform.isWindows ? const Duration(seconds: 15) : const Duration(seconds: 5)` to `SessionManager`.

`main.dart`: before building `SessionCore`,

```dart
  final remoteTools = await resolveRemoteTools(
    operatingSystem: Platform.operatingSystem,
    environment: Platform.environment,
    log: (message) => debugPrint('ShellX ssh: $message'), // never a host (D37)
  );
```

pass `remoteTools: remoteTools` to `SessionCore(...)` and add `remoteToolsProvider.overrideWithValue(remoteTools)` to the root `ProviderScope` overrides. With A5b: `daemon_main.dart` resolves its own `RemoteTools` the same way for its `SessionCore`, and the UI keeps its own for `remoteToolsProvider` (forwards and tmux listing run in the UI, D31).

"Quit completely" (A5b D14; before A5b, A1's Quit): after the sessions are closed and before `exit(0)`, add (D40)

```dart
  final control = remoteTools.control;
  if (control != null) {
    await control.exitMasters(control.mastersUsed).timeout(const Duration(seconds: 2), onTimeout: () {});
  }
```

(with A5b this runs in the daemon's `daemon.quit` handler, where the sessions' `RemoteTools` live; the UI's own `SshControl` only kills its forward processes: `control.exitMasters(const [])`).

Replace the ⌘T / sidebar `+` handlers that call `terminalTabsProvider.notifier.openTab()` with `ref.read(sshActionsProvider).newTab()` (in `terminal_workspace_page.dart` for `NewTabIntent`, and the sidebar header `+` in `session_sidebar.dart`); the workspace header `+` already calls `openTabIn(id)`, which now picks the launch.

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/src/remote/remote_tools_provider.dart apps/desktop/lib/src/remote/ssh_settings.dart apps/desktop/lib/src/remote/ssh_actions.dart apps/desktop/lib/src/terminal/sidebar_workspaces.dart apps/desktop/lib/src/agent/session_core.dart apps/desktop/lib/main.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/terminal/sidebar_workspaces_ssh_test.dart apps/desktop/test/remote/ssh_actions_test.dart
# with A5b: also apps/desktop/lib/daemon_main.dart
git commit -m "feat(desktop): SSH workspaces — Workspace.ssh, connect/newTab/tmux actions, recent and hookless servers, tools resolved at startup (A8 D6, D11, D23, D25, D42)"
```

---

### Task 9: Desktop — `SshReconnector` (D20)

**Files:**
- Create: `apps/desktop/lib/src/remote/ssh_reconnector.dart`
- Modify: `apps/desktop/lib/main.dart` (start it, feed `WakeDetector`)
- Test: `apps/desktop/test/remote/ssh_reconnector_test.dart`

**Interfaces:**
- Consumes: Task 7 `remoteState`, `canReconnect`, `reconnect`, `paneReplacements`; Task 8 `sidebarWorkspacesProvider`.
- Produces:
  - `@immutable final class RetryInfo { final int attempt; final DateTime firstLost; final DateTime? nextAt; final bool retrying; final bool stopped; }`
  - `final reconnectClockProvider = Provider<DateTime Function()>((_) => DateTime.now)`
  - `final sshReconnectorProvider = NotifierProvider<SshReconnector, Map<int, RetryInfo>>(SshReconnector.new)`; `SshReconnector { static const delays = [3, 6, 12, 24, 48, 60]; static const giveUpAfter = Duration(minutes: 30); void onWake(); Future<void> reconnectNow(int sessionId, {bool withoutHook = false}); Future<void> reconnectAll(String workspaceId); }`
  - `TerminalTabs.onReconnectRequest` (`Future<void> Function(int id)?`): Enter on a lost pane goes through it when set (the reconnector sets it).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/remote/ssh_reconnector_test.dart`:

```dart
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/ssh_reconnector.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final devbox = SshTarget.parse('devbox')!;

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;
  late FakeAsync clock;

  void boot(FakeAsync async) {
    clock = async;
    container = ProviderContainer.test(overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('en'))),
      reconnectClockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 9).add(clock.elapsed)),
    ]);
    container.read(terminalTabsProvider);
    container.read(sshReconnectorProvider);
  }

  void add(int id, {bool connected = true}) => local.add(local.summary(
    id,
    origin: SessionOrigin.desktop,
    remote: SessionRemote(launch: SshLaunch(devbox), connected: connected),
  ));

  void lose(FakeAsync async, int id, [int code = 255]) {
    local.summaries.removeWhere((s) => s.id == id);
    local.views[id]!.end(code);
    async.flushMicrotasks();
  }

  Map<int, RetryInfo> retries() => container.read(sshReconnectorProvider);

  setUp(() => local = FakeLocalSessions());

  test('disconnected → 3 s, then 6 s after a failed attempt; connected clears (D20)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      expect(retries()[1]!.nextAt, DateTime(2026, 10, 7, 9, 0, 3));
      async.elapse(const Duration(seconds: 2));
      expect(local.openLaunches, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(local.openLaunches, [SshLaunch(devbox)]);
      final first = local.nextId - 1;
      expect(retries().containsKey(first), isTrue); // moved to the new id
      lose(async, first); // the retry never got through
      expect(retries()[first]!.attempt, 1);
      async.elapse(const Duration(seconds: 5));
      expect(local.openLaunches, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(local.openLaunches, hasLength(2));
      final second = local.nextId - 1;
      local.replace(local.summary(second, origin: SessionOrigin.desktop,
          remote: SessionRemote(launch: SshLaunch(devbox), connected: true)));
      async.flushMicrotasks();
      expect(retries(), isEmpty);
    });
  });

  test('failed (never connected) never retries by itself; Enter does', () {
    fakeAsync((async) {
      add(1, connected: false);
      boot(async);
      lose(async, 1);
      async.elapse(const Duration(minutes: 5));
      expect(local.openLaunches, isEmpty);
      container.read(sshReconnectorProvider.notifier).reconnectNow(1);
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
    });
  });

  test('gives up after 30 minutes (delays capped at 60 s)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      var current = 1;
      for (var i = 0; i < 60; i++) {
        final info = retries()[current];
        if (info == null || info.stopped) break;
        async.elapse(info.nextAt!.difference(DateTime(2026, 10, 7, 9).add(async.elapsed)));
        current = local.nextId - 1;
        lose(async, current);
      }
      final info = retries()[current]!;
      expect(info.stopped, isTrue);
      expect(local.openLaunches.length, lessThanOrEqualTo(34));
      final n = local.openLaunches.length;
      async.elapse(const Duration(hours: 1));
      expect(local.openLaunches.length, n);
    });
  });

  test('wake retries at once; closing the pane cancels', () {
    fakeAsync((async) {
      add(1);
      add(2);
      boot(async);
      lose(async, 1);
      lose(async, 2);
      container.read(terminalTabsProvider.notifier).close(2);
      async.flushMicrotasks();
      container.read(sshReconnectorProvider.notifier).onWake();
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
      async.elapse(const Duration(minutes: 1));
      expect(local.openLaunches, hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/remote/ssh_reconnector_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/remote/ssh_reconnector.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'remote_state.dart';

@immutable
final class RetryInfo {
  const RetryInfo({
    required this.attempt,
    required this.firstLost,
    this.nextAt,
    this.retrying = false,
    this.stopped = false,
  });

  final int attempt;
  final DateTime firstLost;

  /// When the next attempt starts (the strip's countdown); null while one
  /// runs or after giving up.
  final DateTime? nextAt;
  final bool retrying;

  /// D20: 30 minutes passed — only "Reconnect" now.
  final bool stopped;

  RetryInfo copyWith({int? attempt, Object? nextAt = _keep, bool? retrying, bool? stopped}) => RetryInfo(
    attempt: attempt ?? this.attempt,
    firstLost: firstLost,
    nextAt: identical(nextAt, _keep) ? this.nextAt : nextAt as DateTime?,
    retrying: retrying ?? this.retrying,
    stopped: stopped ?? this.stopped,
  );

  @override
  bool operator ==(Object other) =>
      other is RetryInfo &&
      other.attempt == attempt &&
      other.firstLost == firstLost &&
      other.nextAt == nextAt &&
      other.retrying == retrying &&
      other.stopped == stopped;

  @override
  int get hashCode => Object.hash(attempt, firstLost, nextAt, retrying, stopped);
}

const Object _keep = Object();

final reconnectClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final sshReconnectorProvider = NotifierProvider<SshReconnector, Map<int, RetryInfo>>(
  SshReconnector.new,
);

/// A8 D20: lost SSH panes come back by themselves — 3, 6, 12, 24, 48, 60…
/// seconds, at once after a wake, for 30 minutes; panes that never
/// connected only on request. Keyed by the pane's current session id.
class SshReconnector extends Notifier<Map<int, RetryInfo>> {
  static const delays = [3, 6, 12, 24, 48, 60];
  static const giveUpAfter = Duration(minutes: 30);

  final _timers = <int, Timer>{};

  DateTime _now() => ref.read(reconnectClockProvider)();
  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  @override
  Map<int, RetryInfo> build() {
    final sub = _tabs.paneReplacements.listen(_replaced);
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) => _scan(next));
    ref.onDispose(() {
      unawaited(sub.cancel());
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
    });
    Future.microtask(() => _scan(ref.read(terminalTabsProvider)));
    return const {};
  }

  void _scan(TerminalTabsState tabs) {
    if (!ref.mounted) return;
    final now = _now();
    final next = Map.of(state);
    final present = <int>{};
    for (final tab in tabs.tabs) {
      for (final pane in tab.panes.values) {
        present.add(pane.id);
        final info = next[pane.id];
        switch (pane.remoteState) {
          case RemoteState.connected:
            if (info != null) {
              next.remove(pane.id);
              _timers.remove(pane.id)?.cancel();
            }
          case RemoteState.disconnected:
            if (info == null) {
              next[pane.id] = _schedule(pane.id, RetryInfo(attempt: 0, firstLost: now), now);
            } else if (info.retrying) {
              next[pane.id] = _schedule(pane.id, info.copyWith(attempt: info.attempt + 1, retrying: false), now);
            }
          case RemoteState.failed:
            if (info != null && info.retrying) next.remove(pane.id); // a manual try failed
          default:
            break;
        }
      }
    }
    for (final id in next.keys.toList()) {
      if (!present.contains(id)) {
        next.remove(id);
        _timers.remove(id)?.cancel();
      }
    }
    if (!mapEquals(next, state)) state = next;
  }

  RetryInfo _schedule(int id, RetryInfo info, DateTime now) {
    _timers.remove(id)?.cancel();
    if (now.difference(info.firstLost) >= giveUpAfter) {
      return info.copyWith(stopped: true, nextAt: null);
    }
    final delay = Duration(seconds: delays[min(info.attempt, delays.length - 1)]);
    _timers[id] = Timer(delay, () => unawaited(_attempt(id)));
    return info.copyWith(nextAt: now.add(delay));
  }

  Future<void> _attempt(int id) async {
    _timers.remove(id)?.cancel();
    final info = state[id];
    if (info == null || !ref.mounted) return;
    state = {...state, id: info.copyWith(retrying: true, nextAt: null)};
    final fresh = await _tabs.reconnect(id);
    if (fresh != null || !ref.mounted) return;
    // Busy or the open failed: try again later.
    final current = state[id];
    if (current == null) return;
    state = {
      ...state,
      id: _schedule(id, current.copyWith(attempt: current.attempt + 1, retrying: false), _now()),
    };
  }

  void _replaced(PaneReplacement r) {
    final info = state[r.from];
    if (info == null) return;
    state = {...Map.of(state)..remove(r.from), r.to: info};
    final timer = _timers.remove(r.from);
    timer?.cancel();
  }

  /// D20: the computer woke — every waiting pane now (not given-up ones).
  void onWake() {
    for (final entry in state.entries.toList()) {
      if (entry.value.retrying || entry.value.stopped) continue;
      unawaited(_attempt(entry.key));
    }
  }

  /// Enter, the strip's button, the row menu: now, with a fresh 30 minutes.
  Future<void> reconnectNow(int sessionId, {bool withoutHook = false}) async {
    _timers.remove(sessionId)?.cancel();
    final now = _now();
    state = {
      ...state,
      sessionId: RetryInfo(attempt: 0, firstLost: now, retrying: true),
    };
    final fresh = await _tabs.reconnect(sessionId, withoutHook: withoutHook);
    if (fresh == null && ref.mounted && state[sessionId] != null) {
      state = {...state, sessionId: _schedule(sessionId, state[sessionId]!.copyWith(retrying: false), now)};
    }
  }

  /// UI-A8 §2.3 "Reconnect all panes".
  Future<void> reconnectAll(String workspaceId) async {
    final members = ref.read(sidebarWorkspacesProvider).tabsOf(workspaceId);
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      if (!members.contains(tab.id)) continue;
      for (final pane in tab.panes.values) {
        if (pane.canReconnect) await reconnectNow(pane.id);
      }
    }
  }
}
```

In `_onUserInput` (Task 7) Enter on a lost pane called `reconnect(id)` directly; switch it to the reconnector so the strip shows "Reconnecting…": in `TerminalTabs`, add a settable hook `Future<void> Function(int id)? onReconnectRequest;` and use it when set (`final request = onReconnectRequest; unawaited(request != null ? request(id) : reconnect(id));`), and in `SshReconnector.build` set `_tabs.onReconnectRequest = reconnectNow;` (clear it in `onDispose` if still ours) — the same pattern as `CloseSuccessor.choose`.

`main.dart`: after the container exists, `container.read(sshReconnectorProvider);` and

```dart
  final wake = WakeDetector(onWake: () => container.read(sshReconnectorProvider.notifier).onWake())..start();
```

(stop it where the app shuts down, next to the other detectors).

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/remote/ssh_reconnector.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/main.dart apps/desktop/test/remote/ssh_reconnector_test.dart
git commit -m "feat(desktop): SSH panes reconnect by themselves — 3 s to 60 s back-off, at once after wake, give up after 30 min, never for failed sign-ins (A8 D20)"
```

---

### Task 10: Desktop — `RemotePortForwards` (D19)

**Files:**
- Create: `apps/desktop/lib/src/remote/remote_port_forwards.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (`_openPort`), A6's ⌥-click / "Open :port in a browser pane" handler (look up its name in A6 plan Task 9: the code that turns a port into `http://localhost:<port>/` for a browser pane)
- Test: `apps/desktop/test/remote/remote_port_forwards_test.dart`

**Interfaces:**
- Consumes: Task 4 `SshControl.forward`, `forwardedPort`, `cancelForwards`; Task 7 `RemotePortForwardFailedNotice`; Task 8 `remoteToolsProvider`.
- Produces:
  - `final portOpenerProvider = Provider<Future<void> Function(int port)>(…)` (system browser for `http://localhost:<port>/`).
  - `final remotePortForwardsProvider = NotifierProvider<RemotePortForwards, Map<String, int>>(…)` — state: `'<hostKey>\u0000<remotePort>' → localPort`.
  - `RemotePortForwards { Future<int?> localPort(PaneSession pane, int port); Future<void> open(PaneSession pane, int port); int? forwarded(String hostKey, int port); }` — `localPort` returns [port] for local panes, the forwarded port for SSH panes, null after a toast.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/remote/remote_port_forwards_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/remote_port_forwards.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  final devbox = SshTarget.parse('devbox')!;

  test('local pane: the port as is; SSH pane: a forward, opened, remembered, '
      'cancelled with the last pane (D19)', () async {
    final local = FakeLocalSessions();
    final runs = <List<String>>[];
    var forwardExit = 0;
    final opened = <int>[];
    local.add(local.summary(1, origin: SessionOrigin.desktop, ports: const [5173]));
    local.add(local.summary(2, origin: SessionOrigin.desktop, ports: const [8000],
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true)));
    final container = ProviderContainer.test(overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('en'))),
      portOpenerProvider.overrideWithValue((port) async => opened.add(port)),
      remoteToolsProvider.overrideWithValue(RemoteTools(
        sshPath: '/usr/bin/ssh',
        control: SshControl(
          sshPath: '/usr/bin/ssh',
          controlDirectory: '/tmp/sx',
          run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
            runs.add(args);
            return CommandResult(args.contains('forward') ? forwardExit : 0, '', '');
          },
          ports: _AllFree(),
        ),
      )),
    ]);
    final tabs = container.read(terminalTabsProvider);
    final forwards = container.read(remotePortForwardsProvider.notifier);
    PaneSession pane(int id) => tabs.tabOfSession(id)!.panes[id]!;

    await forwards.open(pane(1), 5173);
    expect(opened, [5173]);
    expect(runs, isEmpty);
    await forwards.open(pane(2), 8000);
    expect(opened, [5173, 8000]);
    expect(runs.last, containsAllInOrder(['-O', 'forward', '-L', '127.0.0.1:8000:localhost:8000']));
    expect(forwards.forwarded('devbox', 8000), 8000);
    forwardExit = 1;
    expect(await forwards.localPort(pane(2), 9000), isNull);
    expect(container.read(terminalTabsProvider).notice, isA<RemotePortForwardFailedNotice>());
    container.read(terminalTabsProvider.notifier).close(2);
    await pumpEventQueue();
    expect(runs.last, containsAllInOrder(['-O', 'cancel']));
    expect(forwards.forwarded('devbox', 8000), isNull);
  });
}

final class _AllFree implements LocalPorts {
  @override
  Future<bool> isFree(int port) async => true;
  @override
  Future<int> ephemeral() async => 50000;
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/remote/remote_port_forwards_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/remote/remote_port_forwards.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../agent/desktop_services.dart';
import '../terminal/terminal_tabs.dart';
import 'remote_tools_provider.dart';

/// UI-A2 §2.4: `http://localhost:<port>/` in the system browser.
final portOpenerProvider = Provider<Future<void> Function(int port)>(
  (ref) => ref.watch(desktopServicesProvider).urlOpener.openLocalPort,
);

final remotePortForwardsProvider =
    NotifierProvider<RemotePortForwards, Map<String, int>>(RemotePortForwards.new);

String _key(String host, int port) => '$host\u0000$port';

/// A8 D19: a port on a server opens here through an SSH forward. Never
/// logs a host or a port (D37).
class RemotePortForwards extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, tabs) => _prune(tabs));
    return const {};
  }

  SshControl? get _control => ref.read(remoteToolsProvider).control;

  int? forwarded(String hostKey, int port) => state[_key(hostKey, port)];

  /// The port to open on this computer; null after the failure toast.
  Future<int?> localPort(PaneSession pane, int port) async {
    final host = pane.remote?.launch.host;
    if (host == null) return port;
    final control = _control;
    if (control == null) {
      ref.read(terminalTabsProvider.notifier).showNotice(const SshUnavailableNotice());
      return null;
    }
    try {
      final local = await control.forward(host, port);
      if (ref.mounted) state = {...state, _key(host.key, port): local};
      return local;
    } on ForwardFailedException {
      if (ref.mounted) {
        ref.read(terminalTabsProvider.notifier).showNotice(RemotePortForwardFailedNotice(port));
      }
      return null;
    }
  }

  /// The sidebar's port link (UI-A8 §2.1).
  Future<void> open(PaneSession pane, int port) async {
    final local = await localPort(pane, port);
    if (local == null) return;
    try {
      await ref.read(portOpenerProvider)(local);
    } catch (_) {
      ref.read(terminalTabsProvider.notifier).showNotice(const PortOpenFailedNotice());
    }
  }

  /// D19: forwards of a server with no live pane left are cancelled.
  void _prune(TerminalTabsState tabs) {
    final live = <String, SshTarget>{};
    for (final tab in tabs.tabs) {
      for (final pane in tab.panes.values) {
        final host = pane.remote?.launch.host;
        if (host != null && !pane.exited) live[host.key] = host;
      }
    }
    final gone = <String>{
      for (final key in state.keys)
        if (!live.containsKey(key.split('\u0000').first)) key.split('\u0000').first,
    };
    if (gone.isEmpty) return;
    state = {
      for (final e in state.entries)
        if (!gone.contains(e.key.split('\u0000').first)) e.key: e.value,
    };
    final control = _control;
    if (control == null) return;
    for (final host in gone) {
      final target = SshTarget.parse(host);
      if (target != null) unawaited(control.cancelForwards(target));
    }
  }
}
```

`session_sidebar.dart` — `_openPort(int port)` becomes `_openPort(TerminalTab tab, int port)` calling `ref.read(remotePortForwardsProvider.notifier).open(tab.focused, port)` (the row passes `onOpenPort: (port) => unawaited(_openPort(tab, port))`; the row menu's "Open port N…" entries call the same). A6's ⌥-click / "Open :N in a browser pane": before building `http://localhost:N/`, `final local = await ref.read(remotePortForwardsProvider.notifier).localPort(tab.focused, N); if (local == null) return;` and use `local`.

- [ ] **Step 4: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/remote/remote_port_forwards.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/remote/remote_port_forwards_test.dart
# plus the A6 browser-pane port handler file you changed
git commit -m "feat(desktop): server ports open here — SSH forward on click, same port when free, cancelled with the last pane (A8 D19)"
```

---
### Task 11: Desktop UI — marks, connecting dot, remote context line, workspace header, pane header, lost-connection strip, menus, announcements (UI-A8 §1–§3, §5.2, §8)

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/remote_marks.dart`, `apps/desktop/lib/src/ui/terminal/remote_strip.dart`
- Modify: `apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart` (sizes), `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, `apps/desktop/lib/src/ui/terminal/workspace_header.dart`, `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (terminal menu), `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (announcements)
- Test: `apps/desktop/test/ui/remote_marks_test.dart`, `apps/desktop/test/ui/remote_strip_test.dart`, `apps/desktop/test/ui/sidebar_remote_test.dart`

**Interfaces:**
- Consumes: Task 7 `PaneSession.remote/remoteState/canReconnect`, `closePane`, `splitPane(local:)`; Task 9 `sshReconnectorProvider`, `RetryInfo`; Task 10 `remotePortForwardsProvider`; Task 8 `sshActionsProvider`, `SidebarWorkspaces.launchFor`.
- Produces:
  - `ShellxSizes.remoteMark = 12`, `remoteMarkGap = 2`, `connectingDot = 4`, `remoteStrip = 32`, `remoteStripPadH = 8`, `remoteStripButton = 24`, `connectDialogWidth = 520`, `connectTabBar = 32`, `suggestionRow = 28`, `tmuxRow = 40`, `suggestionListMax = 8`; `static double remoteStripFor(TextScaler)`.
  - `class RemoteMark extends StatelessWidget { const RemoteMark(PaneSession pane); }` (key `mark.remote.<id>`), `class ConnectingDot extends StatelessWidget { const ConnectingDot({double box = ShellxSizes.dot}); }` (key `dot.connecting`), `String remoteSemantics(AppLocalizations, PaneSession)`, `String? remoteAnnouncement(AppLocalizations, PaneSession? before, PaneSession after)`.
  - `class RemoteStrip extends ConsumerStatefulWidget { const RemoteStrip({required PaneSession pane}); }` (key `remote.strip.<id>`).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ui/remote_marks_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/ui/terminal/remote_marks.dart';
import 'package:xterm/xterm.dart';

final devbox = SshTarget.parse('devbox')!;

PaneSession pane({SessionRemote? remote, int? exitCode, bool everConnected = true}) => PaneSession(
  id: 7,
  index: 1,
  shell: 'ssh',
  title: 'zsh',
  origin: SessionOrigin.desktop,
  phoneAttached: false,
  runningCommand: false,
  driver: DriverSide.desktop,
  terminal: DesktopTerminal(platform: TerminalTargetPlatform.macos),
  selection: TerminalController(),
  remote: remote,
  exitCode: exitCode,
  everConnected: everConnected,
);

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('SSH and tmux marks; nothing for a local pane (UI-A8 §2.1)', (tester) async {
    await tester.pumpWidget(app(RemoteMark(pane(remote: SessionRemote(launch: SshLaunch(devbox))))));
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    expect(find.byTooltip('SSH: devbox'), findsOneWidget);
    await tester.pumpWidget(app(RemoteMark(pane(remote: SessionRemote(launch: TmuxLaunch('main', host: devbox))))));
    expect(find.byIcon(Icons.view_quilt_outlined), findsOneWidget);
    expect(find.byTooltip('tmux: main · devbox'), findsOneWidget);
    await tester.pumpWidget(app(RemoteMark(pane(remote: const SessionRemote(launch: TmuxLaunch('main'))))));
    expect(find.byTooltip('tmux: main'), findsOneWidget);
    await tester.pumpWidget(app(RemoteMark(pane())));
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the connecting dot is a 4 px dot in the 8 px box', (tester) async {
    await tester.pumpWidget(app(const ConnectingDot()));
    expect(tester.getSize(find.byKey(const Key('dot.connecting'))), const Size(8, 8));
  });

  test('semantics suffix and announcements (UI-A8 §8)', () {
    final connecting = pane(remote: SessionRemote(launch: SshLaunch(devbox)), everConnected: false);
    final connected = pane(remote: SessionRemote(launch: SshLaunch(devbox), connected: true));
    final lost = pane(remote: SessionRemote(launch: SshLaunch(devbox), connected: true), exitCode: 255);
    expect(remoteSemantics(en, connecting), ', on devbox, Connecting to devbox');
    expect(remoteSemantics(en, connected), ', on devbox');
    expect(remoteSemantics(en, lost), ', on devbox, Lost connection to devbox');
    expect(remoteSemantics(en, pane()), '');
    expect(remoteAnnouncement(en, connecting, connected), 'Connected to devbox');
    expect(remoteAnnouncement(en, connected, lost), 'Lost connection to devbox');
    expect(remoteAnnouncement(en, lost, connected), 'Reconnected to devbox');
    expect(remoteAnnouncement(en, connected, connected), isNull);
    expect(remoteAnnouncement(en, null, connected), isNull);
  });
}
```

`apps/desktop/test/ui/remote_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/ssh_reconnector.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/remote_strip.dart';

import '../support/fake_local_sessions.dart';

void main() {
  final devbox = SshTarget.parse('devbox')!;

  Future<ProviderContainer> pump(WidgetTester tester, {required bool connected, int code = 255}) async {
    final local = FakeLocalSessions()
      ..add(FakeLocalSessions().summary(1, origin: SessionOrigin.desktop,
          remote: SessionRemote(launch: SshLaunch(devbox), connected: connected)));
    final container = ProviderContainer(overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('en'))),
      reconnectClockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 9)),
    ]);
    container.read(sshReconnectorProvider);
    local.summaries.clear();
    local.views[1]!.end(code);
    await tester.pump();
    final pane = container.read(terminalTabsProvider).tabOfSession(1)!.panes[1]!;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: Stack(children: [Positioned(left: 0, right: 0, bottom: 0, child: RemoteStrip(pane: pane))])),
      ),
    ));
    return container;
  }

  /// The reconnector's 3 s timer and the strip's ticker must be gone
  /// before the test ends.
  Future<void> done(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets('disconnected: countdown, Reconnect, Close pane (UI-A8 §3.2)', (tester) async {
    final c = await pump(tester, connected: true);
    expect(find.text('Lost connection to devbox'), findsOneWidget);
    expect(find.text('Retrying in 3 seconds'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reconnect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Close pane'), findsOneWidget);
    expect(find.byTooltip('Run inside tmux to keep programs running when the connection drops'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('failed after the hook: Try again, Try without the hook', (tester) async {
    final c = await pump(tester, connected: false, code: 127);
    expect(find.text('Couldn’t connect to devbox'), findsOneWidget);
    expect(find.text('The server may not support the ShellX hook'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Try without the hook'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('one live region, buttons are buttons', (tester) async {
    final c = await pump(tester, connected: true);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('remote.strip.1'))),
      matchesSemantics(isLiveRegion: true, label: 'Lost connection to devbox · Retrying in 3 seconds'),
    );
    handle.dispose();
    await done(tester, c);
  });
}
```

`apps/desktop/test/ui/sidebar_remote_test.dart` (uses the A2/A3 sidebar harness):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';

import 'sidebar_test_harness.dart';

void main() {
  setUpSidebar();
  final devbox = SshTarget.parse('devbox')!;

  testSidebar('an SSH row: mark, remote ~, connecting dot, label (UI-A8 §2)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, cwd: '/home/me/work/api', gitBranch: 'feat/x', ports: const [8000],
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true, home: '/home/me')));
    local.add(local.summary(2, origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(devbox))));
    await pumpSidebar(tester);
    expect(find.byKey(const Key('mark.remote.1')), findsOneWidget);
    expect(find.textContaining('~/work/api'), findsOneWidget);
    expect(find.descendant(of: row(2), matching: find.byKey(const Key('dot.connecting'))), findsOneWidget);
    expect(tester.getSemantics(row(1)).label, contains(', on devbox'));
    expect(tester.getSemantics(row(2)).label, contains('Connecting to devbox'));
  });

  testSidebar('an SSH workspace header shows the server icon', (tester) async {
    await pumpSidebar(tester);
    workspaces().createForHost(devbox);
    await tester.pump();
    expect(find.byIcon(Icons.dns_outlined), findsWidgets);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/remote_marks_test.dart test/ui/remote_strip_test.dart test/ui/sidebar_remote_test.dart`
Expected: FAIL — undefined widgets.

- [ ] **Step 3: Sizes**

In `ShellxSizes`:

```dart
  // A8 (UI-A8 §1.2).
  static const double remoteMark = 12;
  static const double remoteMarkGap = 2;
  static const double connectingDot = 4;
  static const double remoteStrip = 32;
  static const double remoteStripPadH = 8;
  static const double remoteStripButton = 24;
  static const double connectDialogWidth = 520;
  static const double connectTabBar = 32;
  static const double suggestionRow = 28;
  static const double tmuxRow = 40;
  static const int suggestionListMax = 8;

  /// UI-A8 §1.3.
  static double remoteStripFor(TextScaler scaler) =>
      max(remoteStrip, scaler.scale(18) + 14);
```

- [ ] **Step 4: `remote_marks.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/remote_state.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';

/// UI-A8 §2.1: the pane's SSH or tmux mark; nothing for a local shell.
class RemoteMark extends StatelessWidget {
  const RemoteMark(this.pane, {super.key});
  final PaneSession pane;

  @override
  Widget build(BuildContext context) {
    final remote = pane.remote;
    if (remote == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final host = remote.hostKey;
    final tmux = remote.tmuxSession;
    final message = tmux == null
        ? l10n.sidebarRemoteMark(host ?? '')
        : host == null
        ? l10n.sidebarTmuxMark(tmux)
        : l10n.sidebarTmuxRemoteMark(tmux, host);
    return Tooltip(
      message: message,
      excludeFromSemantics: true,
      child: Icon(
        tmux == null ? Icons.dns_outlined : Icons.view_quilt_outlined,
        key: Key('mark.remote.${pane.id}'),
        size: ShellxSizes.remoteMark,
        color: ShellxDesktopColors.textSecondary,
      ),
    );
  }
}

/// UI-A8 §2.2: "connecting" — a 4 px dot centred in the dot box, a shape
/// none of A1's three dots has (WCAG 1.4.1).
class ConnectingDot extends StatelessWidget {
  const ConnectingDot({super.key, this.box = ShellxSizes.dot});
  final double box;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('dot.connecting'),
    width: box,
    height: box,
    child: Center(
      child: Container(
        width: box / 2,
        height: box / 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: ShellxDesktopColors.textSecondary,
        ),
      ),
    ),
  );
}

/// UI-A8 §8: ", on devbox" and the connection state for row and pane labels.
String remoteSemantics(AppLocalizations l10n, PaneSession pane) {
  final host = pane.remote?.hostKey;
  if (host == null) return '';
  final state = switch (pane.remoteState) {
    RemoteState.connecting => ', ${l10n.sshStateConnecting(host)}',
    RemoteState.disconnected => ', ${l10n.sshStateDisconnected(host)}',
    RemoteState.failed => ', ${l10n.sshStateFailed(host)}',
    _ => '',
  };
  return '${l10n.paneRemoteSuffix(host)}$state';
}

/// UI-A8 §8: what to announce when the selected pane's state changes.
String? remoteAnnouncement(AppLocalizations l10n, PaneSession? before, PaneSession after) {
  final host = after.remote?.hostKey;
  if (before == null || host == null) return null;
  final was = before.remoteState;
  final now = after.remoteState;
  if (was == now) return null;
  return switch ((was, now)) {
    (RemoteState.connecting, RemoteState.connected) => l10n.sshAnnounceConnected(host),
    (RemoteState.disconnected || RemoteState.failed, RemoteState.connected ||
        RemoteState.connecting) => now == RemoteState.connected ? l10n.sshAnnounceReconnected(host) : null,
    (_, RemoteState.disconnected) => l10n.sshAnnounceDisconnected(host),
    _ => null,
  };
}
```

(A reconnect replaces the pane id, so the announcer compares "the focused pane of the selected tab" before and after, not the same id — see Step 7.)

- [ ] **Step 5: `remote_strip.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/remote_state.dart';
import '../../remote/ssh_reconnector.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';

/// UI-A8 §3.2: the bottom strip of a lost SSH pane. Drawn over the
/// terminal (no layout change, no resize).
class RemoteStrip extends ConsumerStatefulWidget {
  const RemoteStrip({super.key, required this.pane});
  final PaneSession pane;

  @override
  ConsumerState<RemoteStrip> createState() => _RemoteStripState();
}

class _RemoteStripState extends ConsumerState<RemoteStrip> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _keepTicking(bool counting) {
    if (counting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!counting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = widget.pane;
    final host = pane.remote?.hostKey ?? '';
    final state = pane.remoteState;
    final retry = ref.watch(sshReconnectorProvider)[pane.id];
    final now = ref.read(reconnectClockProvider)();
    final lost = state == RemoteState.disconnected;
    final hookHint = state == RemoteState.failed && pane.exitCode != 255 && _usesHook(pane);
    final main = lost ? l10n.sshStateDisconnected(host) : l10n.sshStateFailed(host);
    final nextAt = retry?.nextAt;
    _keepTicking(lost && nextAt != null);
    final String? detail = lost
        ? (retry == null || retry.retrying)
              ? l10n.sshRetrying
              : retry.stopped
              ? l10n.sshAutoRetryStopped
              : l10n.sshRetryIn(
                  nextAt == null ? 0 : (nextAt.difference(now).inMilliseconds / 1000).ceil().clamp(0, 60),
                )
        : hookHint
        ? l10n.sshFailedHookHint
        : null;
    final reconnector = ref.read(sshReconnectorProvider.notifier);
    final buttons = <Widget>[
      if (!lost || retry == null || !retry.retrying)
        _StripButton(
          label: lost ? l10n.sshReconnectAction : l10n.sshRetryAction,
          primary: true,
          onPressed: () => unawaited(reconnector.reconnectNow(pane.id)),
        ),
      if (hookHint)
        _StripButton(
          label: l10n.sshRetryPlainAction,
          onPressed: () => unawaited(reconnector.reconnectNow(pane.id, withoutHook: true)),
        ),
      _StripButton(
        label: l10n.sshClosePaneAction,
        onPressed: () => ref.read(terminalTabsProvider.notifier).closePane(pane.id),
      ),
    ];
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    final ordered = windows ? buttons : buttons.reversed.toList(); // A1 §4: macOS primary right
    final mainText = Text(
      main,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
    );
    return Semantics(
      key: Key('remote.strip.${pane.id}'),
      container: true,
      liveRegion: true,
      label: detail == null ? main : '$main · $detail',
      child: Container(
        height: ShellxSizes.remoteStripFor(MediaQuery.textScalerOf(context)),
        padding: const EdgeInsets.symmetric(horizontal: ShellxSizes.remoteStripPadH),
        decoration: const BoxDecoration(
          color: ShellxDesktopColors.bgSidebar,
          border: Border(top: BorderSide(color: ShellxDesktopColors.line)),
        ),
        child: ExcludeSemantics(
          excluding: false,
          child: Row(
            children: [
              const Icon(Icons.link_off, size: ShellxSizes.icon, color: ShellxDesktopColors.err),
              const SizedBox(width: ShellxSpace.s6),
              Flexible(
                child: ExcludeSemantics(
                  child: pane.remote?.isTmux == false && lost
                      ? Tooltip(message: l10n.sshTmuxHint, child: mainText)
                      : mainText,
                ),
              ),
              if (detail != null)
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, c) => c.maxWidth < 40
                        ? const SizedBox.shrink()
                        : ExcludeSemantics(
                            child: Text(
                              ' · $detail',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ShellxText.body.copyWith(color: ShellxDesktopColors.textSecondary),
                            ),
                          ),
                  ),
                ),
              const Spacer(),
              for (final b in ordered) ...[const SizedBox(width: ShellxSpace.s6), b],
            ],
          ),
        ),
      ),
    );
  }

  static bool _usesHook(PaneSession pane) => switch (pane.remote?.launch) {
    SshLaunch(:final hook) => hook,
    TmuxLaunch(:final hook, :final host) => hook && host != null,
    null => false,
  };
}

class _StripButton extends StatelessWidget {
  const _StripButton({required this.label, required this.onPressed, this.primary = false});
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ShellxSizes.remoteStripButton,
    child: TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
        minimumSize: const Size(64, ShellxSizes.remoteStripButton),
        backgroundColor: primary ? ShellxDesktopColors.primary : ShellxDesktopColors.rowSelected,
        foregroundColor: primary ? ShellxDesktopColors.onPrimary : ShellxDesktopColors.textPrimary,
        textStyle: ShellxText.small.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ShellxRadius.r6)),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}
```

(Import `package:shellx_agent/shellx_agent.dart` for `SshLaunch`/`TmuxLaunch`.)

- [ ] **Step 6: Wire the widgets in**

- `session_tab_row.dart`:
  - `TabStatusDot.build` starts with `if (tab.focused.remoteState == RemoteState.connecting) return const ConnectingDot();` (the lost states already draw A1's exited ring, UI-A8 §2.2).
  - After the pane-count block (UI-A8 §2.1 order: badge → pane count → SSH/tmux → 📱):

    ```dart
                    if (tab.focused.remote != null) ...[
                      const SizedBox(width: ShellxSpace.s4),
                      RemoteMark(tab.focused),
                    ],
    ```
  - The row's semantics label appends `remoteSemantics(l10n, tab.focused)` right after the title part.
  - `_ContextLine`: for a remote pane, `home` is `tab.focused.remote?.home ?? ''` and `windows` is `false`; the full-text tooltip of A2 §2.2 step 5 prefixes the path with `'${tab.focused.remote!.hostKey}:'`. A new row parameter `final String Function(int port)? portTooltip;` replaces the fixed `portOpenTooltip` text of `_PortLink` when given.
- `session_sidebar.dart`: `ref.watch(remotePortForwardsProvider)` in the sidebar build; each row gets

  ```dart
        portTooltip: (port) {
          final host = tab.focused.remote?.hostKey;
          if (host == null) return l10n.portOpenTooltip(port);
          final local = ref.read(remotePortForwardsProvider.notifier).forwarded(host, port);
          return local == null
              ? l10n.remotePortTooltip(port, host)
              : l10n.remotePortForwarded(local, host, port);
        },
  ```

  Row menu (A3 §4.2): when any pane of the tab `canReconnect`, a first item `l10n.rowReconnect` → `for (final p in tab.panes.values) if (p.canReconnect) unawaited(ref.read(sshReconnectorProvider.notifier).reconnectNow(p.id));`.
  Workspace header menu (A2 §5.2) for a workspace with `ssh != null`: first group `workspaceNewRemoteTab(host)` (→ `openTabIn(id)`), `workspaceNewLocalTab` (→ `openTabIn(id, launch: null)` — pass an explicit local launch by calling `ref.read(terminalTabsProvider.notifier).openTab()` after `workspaces().setCollapsed(id, false)` with the pending target set: add `SidebarWorkspaces.openLocalTabIn(String id)` that does `_pendingTarget = id; await _tabs.openTab();`), `workspaceReconnectAll` (enabled when a pane of the workspace `canReconnect`; → `reconnectAll(id)`), a separator, then the A2 items.
- `workspace_header.dart`: when `workspace.ssh != null`, `const Icon(Icons.dns_outlined, size: ShellxSizes.remoteMark, color: ShellxDesktopColors.textSecondary)` + 4 px before the name (inside `ExcludeSemantics`; the header label becomes `l10n.workspaceRemoteLabel(name)`), and the `+` tooltip `l10n.workspaceNewRemoteTab(workspace.ssh!)`.
- `pane_tree_view.dart` — pane header (UI-A8 §3.1): the status dot slot shows `ConnectingDot(box: ShellxSizes.paneHeaderDot)` when the pane is connecting; `RemoteMark(pane)` + 4 px before the title; the pane's semantics label appends `remoteSemantics(l10n, pane)`. In each pane's `Stack`, add last:

  ```dart
            if (pane.canReconnect)
              Positioned(left: 0, right: 0, bottom: 0, child: RemoteStrip(pane: pane)),
  ```
- `terminal_pane.dart` — terminal menu (A3 §4.1): for a pane with `remote != null`, after "Split down" add `l10n.paneSplitLocalRight` → `ref.read(terminalTabsProvider.notifier).splitPane(pane.id, SplitAxis.row, focus: true, local: true)` (catch the A7 exceptions into the A3 notices exactly as `split` does); for a pane that `canReconnect`, add `l10n.sshReconnectAction` as the first item.

- [ ] **Step 7: Announcements**

In `terminal_workspace_page.dart`, next to the existing A3/A4 announcement listeners:

```dart
    ref.listen<TerminalTabsState>(terminalTabsProvider, (before, after) {
      final was = before?.selected?.focused;
      final now = after.selected?.focused;
      if (now == null || before?.selectedId != after.selectedId) return;
      final text = remoteAnnouncement(AppLocalizations.of(context), was, now);
      if (text != null) announce(text); // the page's ≤ 1 / 3 s announcer (A4 D23)
    });
```

(`announce` is the page's existing polite announcer used for A3 pane announcements; use its real name.)

- [ ] **Step 8: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test`
Expected: PASS — including `one_pane_parity_test` and the A2/A3 sidebar tests (local rows unchanged).

- [ ] **Step 9: Commit**

```bash
git add apps/desktop/lib/src/ui/theme/shellx_desktop_theme.dart apps/desktop/lib/src/ui/terminal/remote_marks.dart apps/desktop/lib/src/ui/terminal/remote_strip.dart apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/lib/src/ui/terminal/workspace_header.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/terminal/terminal_pane.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/terminal/sidebar_workspaces.dart apps/desktop/test/ui/remote_marks_test.dart apps/desktop/test/ui/remote_strip_test.dart apps/desktop/test/ui/sidebar_remote_test.dart
git commit -m "feat(desktop): SSH/tmux marks, connecting dot, the server's ~ in the context line, forwarded-port tooltips, SSH workspace header, lost-connection strip, reconnect menus and announcements (UI-A8 §2, §3, §5.2, §8)"
```

---

### Task 12: Desktop UI — "Connect to a server" dialog, ⌘⇧K, `+` menu, tray "SSH" (D41, D42, UI-A8 §4, §5, §6)

**Files:**
- Create: `apps/desktop/lib/src/ui/terminal/ssh_connect_dialog.dart`
- Modify: `apps/desktop/lib/src/ui/window_router.dart` (`SshConnectRoute`), `apps/desktop/lib/src/ui/dialogs/route_dialog.dart` (renders it), `apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart` (`OpenSshConnectIntent`), `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart` (action), `apps/desktop/lib/src/ui/terminal/session_sidebar.dart` (`+` context menu), `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_actions.dart`
- Test: `apps/desktop/test/ui/ssh_connect_dialog_test.dart`, `apps/desktop/test/ui/terminal_shortcuts_test.dart` (append), `apps/desktop/test/tray/` (append to the tray menu test)

**Interfaces:**
- Consumes: Task 8 `SshActions` (`connect`, `suggestions`, `listTmux`, `attachTmux`, `hookFor`, `clearRecent`), `SettingKeys.sshRemoteHook`; Task 2 `TmuxListResult`; Task 1 `SshTarget.parse`, `isValidTmuxName`, `isValidRemoteCwd`.
- Produces:
  - `enum SshDialogTab { ssh, tmux }`; `final class SshConnectRoute extends WindowRoute { const SshConnectRoute([SshDialogTab tab = SshDialogTab.ssh]); }`.
  - `class SshConnectDialog extends ConsumerStatefulWidget { const SshConnectDialog({SshDialogTab initialTab = SshDialogTab.ssh}); }` with keys `ssh.host`, `ssh.dir`, `ssh.nohook`, `ssh.connect`, `ssh.tab.ssh`, `ssh.tab.tmux`, `tmux.source`, `tmux.row.<name>`, `tmux.new`, `tmux.create`, `tmux.attach`.
  - `class OpenSshConnectIntent extends Intent` bound to ⌘⇧K (macOS) / Ctrl+Shift+K (Windows).
  - `TrayAction.sshConnect`, `TrayAction.tmuxAttach`, `TrayAction.sshHookToggle`, `TrayAction.sshClearRecent` (or the tray's equivalent action type — follow A7's "Dòng lệnh" submenu pattern).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ui/ssh_connect_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/ui/terminal/ssh_connect_dialog.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late InMemorySettingsStore settings;
late CommandResult Function(List<String>) tmuxAnswer;

Future<ProviderContainer> pump(WidgetTester tester, {SshDialogTab tab = SshDialogTab.ssh}) async {
  local = FakeLocalSessions();
  settings = InMemorySettingsStore();
  Future<CommandResult> run(String exe, List<String> args, {Duration timeout = const Duration(seconds: 5)}) async =>
      tmuxAnswer(args);
  final container = ProviderContainer(overrides: [
    localSessionsProvider.overrideWithValue(local),
    settingsStoreProvider.overrideWithValue(settings),
    commandRunnerProvider.overrideWithValue(run),
    remoteToolsProvider.overrideWithValue(RemoteTools(
      sshPath: '/usr/bin/ssh',
      tmuxPath: '/usr/bin/tmux',
      control: SshControl(sshPath: '/usr/bin/ssh', run: run),
    )),
    sshConfigHostsProvider.overrideWithValue(() async => ['devbox', 'dev-db', 'prod']),
  ]);
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildDesktopTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: SshConnectDialog(initialTab: tab))),
    ),
  ));
  await settle(tester);
  return container;
}

/// Frames, then past the dialog's 300 ms "Loading…" delay (no timer left).
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() => tmuxAnswer = (_) => const CommandResult(0, 'main\t3\t0\t1759831200\nbuild\t1\t1\t1759744800\n', ''));

  testWidgets('type, filter, ↓ ↓, Enter connects; the dialog closes at once (D42)', (tester) async {
    await pump(tester);
    expect(tester.widget<TextField>(find.byKey(const Key('ssh.host'))).focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('ssh.host')), 'dev');
    await tester.pump();
    expect(find.text('devbox'), findsOneWidget);
    expect(find.text('dev-db'), findsOneWidget);
    expect(find.text('prod'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // devbox
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // dev-db
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(local.openLaunches.single, SshLaunch(SshTarget.parse('dev-db')!));
  });

  testWidgets('a bad server name stays in the dialog with an error', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('ssh.host')), '-oProxyCommand=x');
    await tester.tap(find.byKey(const Key('ssh.connect')));
    await tester.pump();
    expect(find.text('Not a valid server name'), findsOneWidget);
    expect(local.openLaunches, isEmpty);
  });

  testWidgets('folder and "no hook" travel with the connect', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('ssh.host')), 'me@box:2222');
    await tester.enterText(find.byKey(const Key('ssh.dir')), '~/srv');
    await tester.tap(find.byKey(const Key('ssh.nohook')));
    await tester.tap(find.byKey(const Key('ssh.connect')));
    await settle(tester);
    expect(local.openLaunches.single, SshLaunch(SshTarget.parse('me@box:2222')!, remoteCwd: '~/srv', hook: false));
    expect(settings.getStrings(SettingKeys.sshPlainTargets), ['me@box:2222']);
  });

  testWidgets('tmux tab: sessions here, attach; create a new one (D25)', (tester) async {
    await pump(tester, tab: SshDialogTab.tmux);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('3 windows'), findsOneWidget);
    expect(find.text('attached elsewhere'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tmux.attach')));
    await settle(tester);
    expect(local.openLaunches.single, const TmuxLaunch('main'));
  });

  testWidgets('tmux tab: no server here → empty text; on a server that needs a password → advice', (tester) async {
    tmuxAnswer = (_) => const CommandResult(1, '', 'no server running on /tmp/tmux-501/default');
    await pump(tester, tab: SshDialogTab.tmux);
    expect(find.text('No tmux sessions yet'), findsOneWidget);
    tmuxAnswer = (_) => const CommandResult(255, '', '');
    await tester.enterText(find.byKey(const Key('tmux.source')), 'devbox');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.textContaining('Couldn’t list sessions on devbox'), findsOneWidget);
  });

  testWidgets('tmux: an invalid new name is refused', (tester) async {
    await pump(tester, tab: SshDialogTab.tmux);
    await tester.enterText(find.byKey(const Key('tmux.new')), 'a:b');
    await tester.tap(find.byKey(const Key('tmux.create')));
    await tester.pump();
    expect(find.text('Use up to 64 characters, without “:” or “.”'), findsOneWidget);
  });
}
```

Append to `apps/desktop/test/ui/terminal_shortcuts_test.dart` (in its macOS/Windows groups, following the file's existing pattern for A3 chords): ⌘⇧K maps to `OpenSshConnectIntent` on macOS, Ctrl+Shift+K on Windows; no existing chord changed.

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ssh_connect_dialog_test.dart test/ui/terminal_shortcuts_test.dart`
Expected: FAIL — `SshConnectDialog` undefined.

- [ ] **Step 3: Implement the dialog**

`apps/desktop/lib/src/ui/terminal/ssh_connect_dialog.dart` — a `ConsumerStatefulWidget` rendered inside the A1 dialog container (`DialogLayout`/`route_dialog.dart` gives the surface, title row, Windows ✕ and Esc = close):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/ssh_actions.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

enum SshDialogTab { ssh, tmux }

class SshConnectDialog extends ConsumerStatefulWidget {
  const SshConnectDialog({super.key, this.initialTab = SshDialogTab.ssh});
  final SshDialogTab initialTab;

  @override
  ConsumerState<SshConnectDialog> createState() => _SshConnectDialogState();
}

class _SshConnectDialogState extends ConsumerState<SshConnectDialog> {
  late SshDialogTab _tab = widget.initialTab;
  final _host = TextEditingController();
  final _dir = TextEditingController();
  final _source = TextEditingController();
  final _newName = TextEditingController();
  final _hostFocus = FocusNode();
  SshSuggestions _suggestions = const SshSuggestions(config: [], recent: []);
  int? _cursor;
  bool _noHook = false;
  String? _hostError;
  String? _dirError;
  String? _nameError;
  TmuxListResult? _tmux;
  bool _tmuxSlow = false;
  int _tmuxGeneration = 0;
  int _tmuxCursor = 0;

  SshActions get _actions => ref.read(sshActionsProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuggestions());
    if (_tab == SshDialogTab.tmux) unawaited(_listTmux());
    _host.addListener(() => setState(() {
      _cursor = null;
      _hostError = null;
      final t = SshTarget.parse(_host.text);
      if (t != null) _noHook = !_actions.hookFor(t.key);
    }));
  }

  Future<void> _loadSuggestions() async {
    final s = await _actions.suggestions();
    if (mounted) setState(() => _suggestions = s);
  }

  @override
  void dispose() {
    for (final c in [_host, _dir, _source, _newName]) {
      c.dispose();
    }
    _hostFocus.dispose();
    super.dispose();
  }

  /// D42: substring, case-insensitive; config group first.
  List<(String, bool)> _filtered(TextEditingController field) {
    final q = field.text.trim().toLowerCase();
    bool keep(String s) => q.isEmpty || s.toLowerCase().contains(q);
    return [
      for (final s in _suggestions.config) if (keep(s)) (s, true),
      for (final s in _suggestions.recent) if (keep(s)) (s, false),
    ];
  }

  void _close() => ref.read(windowRouterProvider.notifier).close();

  Future<void> _connect() async {
    final rows = _filtered(_host);
    final text = _cursor != null && _cursor! < rows.length ? rows[_cursor!].$1 : _host.text;
    final target = SshTarget.parse(text);
    final dir = _dir.text.trim();
    setState(() {
      _hostError = target == null ? AppLocalizations.of(context).sshHostInvalid : null;
      _dirError = dir.isNotEmpty && !isValidRemoteCwd(dir) ? AppLocalizations.of(context).sshRemoteDirInvalid : null;
    });
    if (target == null || _dirError != null) {
      _hostFocus.requestFocus();
      return;
    }
    _close(); // D42: at once — sign-in happens in the pane
    await _actions.connect(target, remoteCwd: dir.isEmpty ? null : dir, noHook: _noHook);
  }

  SshTarget? get _tmuxHost {
    final text = _source.text.trim();
    if (text.isEmpty || text == AppLocalizations.of(context).tmuxSourceLocal) return null;
    return SshTarget.parse(text);
  }

  Future<void> _listTmux() async {
    final generation = ++_tmuxGeneration;
    setState(() {
      _tmux = null;
      _tmuxSlow = false;
      _tmuxCursor = 0;
    });
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && generation == _tmuxGeneration && _tmux == null) setState(() => _tmuxSlow = true);
    }));
    final result = await _actions.listTmux(_tmuxHost);
    if (mounted && generation == _tmuxGeneration) setState(() => _tmux = result);
  }

  Future<void> _attach(String name, {bool create = false}) async {
    _close();
    await _actions.attachTmux(name, host: _tmuxHost, create: create);
  }

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (!isValidTmuxName(name)) {
      setState(() => _nameError = AppLocalizations.of(context).tmuxNameInvalid);
      return;
    }
    await _attach(name, create: true);
  }

  KeyEventResult _hostKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final rows = _filtered(_host);
    if (rows.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _cursor = _cursor == null ? 0 : (_cursor! + 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _cursor = _cursor == null ? null : (_cursor! - 1).clamp(0, rows.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: ShellxSizes.connectDialogWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.sshDialogTitle, style: ShellxText.dialogTitle),
          const SizedBox(height: ShellxSpace.s12),
          _TabBar(
            selected: _tab,
            onSelect: (t) {
              setState(() => _tab = t);
              if (t == SshDialogTab.tmux && _tmux == null) unawaited(_listTmux());
            },
          ),
          const SizedBox(height: ShellxSpace.s16),
          if (_tab == SshDialogTab.ssh) ..._sshBody(l10n) else ..._tmuxBody(l10n),
        ],
      ),
    );
  }

  List<Widget> _sshBody(AppLocalizations l10n) {
    final rows = _filtered(_host);
    return [
      Text(l10n.sshHostLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      Focus(
        onKeyEvent: _hostKeys,
        child: Semantics(
          hint: l10n.sshSuggestionsCount(rows.length),
          child: TextField(
            key: const Key('ssh.host'),
            controller: _host,
            focusNode: _hostFocus,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.sshHostHint, errorText: _hostError),
            onSubmitted: (_) => unawaited(_connect()),
          ),
        ),
      ),
      if (rows.isNotEmpty) _SuggestionList(rows: rows, cursor: _cursor, query: _host.text, onPick: (s) {
        _host.text = s;
        unawaited(_connect());
      }),
      const SizedBox(height: ShellxSizes.fieldGap),
      Text(l10n.sshRemoteDirLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      TextField(
        key: const Key('ssh.dir'),
        controller: _dir,
        decoration: InputDecoration(hintText: '/srv/app', errorText: _dirError),
        onSubmitted: (_) => unawaited(_connect()),
      ),
      const SizedBox(height: ShellxSpace.s12),
      CheckboxListTile(
        key: const Key('ssh.nohook'),
        value: _noHook,
        onChanged: (v) => setState(() => _noHook = v ?? false),
        title: Text(l10n.sshNoHookLabel, style: ShellxText.dialogBody),
        subtitle: Text(l10n.sshNoHookHelp, style: ShellxText.caption),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: ShellxSpace.s24),
      _Buttons(primary: l10n.sshConnectAction, primaryKey: const Key('ssh.connect'), onPrimary: () => unawaited(_connect()), onCancel: _close),
    ];
  }

  List<Widget> _tmuxBody(AppLocalizations l10n) {
    final result = _tmux;
    final sessions = result is TmuxSessions ? result.sessions : const <TmuxSessionInfo>[];
    final where = _tmuxHost?.key ?? l10n.tmuxSourceLocal;
    return [
      Text(l10n.tmuxSourceLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      TextField(
        key: const Key('tmux.source'),
        controller: _source,
        decoration: InputDecoration(hintText: l10n.tmuxSourceLocal),
        onSubmitted: (_) => unawaited(_listTmux()),
      ),
      const SizedBox(height: ShellxSpace.s8),
      SizedBox(
        height: ShellxSizes.tmuxRow * 4,
        child: switch (result) {
          null => Center(child: _tmuxSlow ? Text(l10n.tmuxLoading) : const SizedBox.shrink()),
          TmuxUnavailable() => Center(child: Text(l10n.tmuxUnavailable(where))),
          TmuxListFailed() => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l10n.tmuxListFailed(where), textAlign: TextAlign.center),
              TextButton(onPressed: () => unawaited(_listTmux()), child: Text(l10n.tmuxRetry)),
            ]),
          ),
          TmuxSessions() when sessions.isEmpty => Center(child: Text(l10n.tmuxEmpty)),
          TmuxSessions() => ListView(
            children: [
              for (final (i, s) in sessions.indexed)
                _TmuxRow(
                  key: Key('tmux.row.${s.name}'),
                  info: s,
                  selected: i == _tmuxCursor,
                  onTap: () => setState(() => _tmuxCursor = i),
                  onDoubleTap: () => unawaited(_attach(s.name)),
                ),
            ],
          ),
        },
      ),
      const SizedBox(height: ShellxSizes.fieldGap),
      Text(l10n.tmuxNewLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('tmux.new'),
            controller: _newName,
            decoration: InputDecoration(errorText: _nameError),
            onSubmitted: (_) => unawaited(_create()),
          ),
        ),
        const SizedBox(width: ShellxSpace.s8),
        OutlinedButton(key: const Key('tmux.create'), onPressed: () => unawaited(_create()), child: Text(l10n.tmuxCreateAction)),
      ]),
      const SizedBox(height: ShellxSpace.s24),
      _Buttons(
        primary: l10n.tmuxAttachAction,
        primaryKey: const Key('tmux.attach'),
        onPrimary: sessions.isEmpty ? null : () => unawaited(_attach(sessions[_tmuxCursor].name)),
        onCancel: _close,
      ),
    ];
  }
}
```

The private widgets, in the same file:

```dart
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect});
  final SshDialogTab selected;
  final void Function(SshDialogTab) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget tab(SshDialogTab t, String label) {
      final on = t == selected;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          key: Key('ssh.tab.${t.name}'),
          onTap: () => onSelect(t),
          child: Container(
            height: ShellxSizes.connectTabBar,
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? ShellxDesktopColors.accent : Colors.transparent, width: 2)),
            ),
            child: Text(label, style: (on ? ShellxText.bodyStrong : ShellxText.body).copyWith(
              color: on ? ShellxDesktopColors.textTitle : ShellxDesktopColors.textDialog2,
            )),
          ),
        ),
      );
    }

    // UI-A8 §6: ←/→ switch tabs while a tab has focus.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SwitchIntent(SshDialogTab.ssh),
        SingleActivator(LogicalKeyboardKey.arrowRight): _SwitchIntent(SshDialogTab.tmux),
      },
      child: Actions(
        actions: {_SwitchIntent: CallbackAction<_SwitchIntent>(onInvoke: (i) => onSelect(i.tab))},
        child: Row(children: [tab(SshDialogTab.ssh, l10n.sshDialogTabSsh), tab(SshDialogTab.tmux, l10n.sshDialogTabTmux)]),
      ),
    );
  }
}

class _SwitchIntent extends Intent {
  const _SwitchIntent(this.tab);
  final SshDialogTab tab;
}

/// UI-A8 §4.1: grouped suggestions, the cursor row highlighted.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.rows, required this.cursor, required this.query, required this.onPick});
  final List<(String, bool)> rows; // (text, fromConfig)
  final int? cursor;
  final String query;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[];
    bool? group;
    for (final (i, (text, config)) in rows.indexed) {
      if (group != config) {
        group = config;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(ShellxSpace.s8, ShellxSpace.s6, ShellxSpace.s8, ShellxSpace.s2),
          child: ExcludeSemantics(
            child: Text(
              (config ? l10n.sshSuggestionsConfig : l10n.sshSuggestionsRecent).toUpperCase(),
              style: ShellxText.caption.copyWith(color: ShellxDesktopColors.textSecondary),
            ),
          ),
        ));
      }
      final on = i == cursor;
      children.add(Semantics(
        selected: on,
        button: true,
        child: InkWell(
          onTap: () => onPick(text),
          child: Container(
            height: ShellxSizes.suggestionRow,
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on ? ShellxDesktopColors.primarySoft : null,
              border: on ? const Border(left: BorderSide(color: ShellxDesktopColors.accent, width: 3)) : null,
            ),
            child: Text.rich(_highlight(text, query), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ));
    }
    return Container(
      margin: const EdgeInsets.only(top: ShellxSpace.s4),
      constraints: const BoxConstraints(maxHeight: ShellxSizes.suggestionRow * ShellxSizes.suggestionListMax),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surfaceInset,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      child: ListView(shrinkWrap: true, children: children),
    );
  }

  static TextSpan _highlight(String text, String query) {
    final q = query.trim().toLowerCase();
    final at = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    final base = ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary);
    if (at < 0) return TextSpan(text: text, style: base);
    return TextSpan(style: base, children: [
      TextSpan(text: text.substring(0, at)),
      TextSpan(text: text.substring(at, at + q.length), style: ShellxText.bodyStrong),
      TextSpan(text: text.substring(at + q.length)),
    ]);
  }
}

/// UI-A8 §4.2: name, windows, last activity, attached elsewhere.
class _TmuxRow extends StatelessWidget {
  const _TmuxRow({super.key, required this.info, required this.selected, required this.onTap, required this.onDoubleTap});
  final TmuxSessionInfo info;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activity = info.activity;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          height: ShellxSizes.tmuxRow,
          padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
          decoration: BoxDecoration(
            color: selected ? ShellxDesktopColors.primarySoft : null,
            border: selected ? const Border(left: BorderSide(color: ShellxDesktopColors.accent, width: 3)) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(info.name, style: ShellxText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(l10n.tmuxWindows(info.windows), style: ShellxText.caption.copyWith(color: ShellxDesktopColors.textSecondary)),
              ]),
              Row(children: [
                if (activity != null)
                  Text(l10n.tmuxLastActive(formatNoticeTime(context, activity)),
                      style: ShellxText.caption.copyWith(color: ShellxDesktopColors.textSecondary)),
                if (info.attachedElsewhere) ...[
                  const SizedBox(width: ShellxSpace.s8),
                  Text(l10n.tmuxAttachedElsewhere, style: ShellxText.caption.copyWith(color: ShellxDesktopColors.warn)),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A1 §4 button order: macOS `[Cancel] [Primary]`, Windows `[Primary] [Cancel]`.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.primary, required this.primaryKey, required this.onPrimary, required this.onCancel});
  final String primary;
  final Key primaryKey;
  final VoidCallback? onPrimary;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cancel = OutlinedButton(onPressed: onCancel, child: Text(l10n.dialogCancel));
    final main = FilledButton(key: primaryKey, onPressed: onPrimary, child: Text(primary));
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: windows
          ? [main, const SizedBox(width: ShellxSpace.s8), cancel]
          : [cancel, const SizedBox(width: ShellxSpace.s8), main],
    );
  }
}
```

`formatNoticeTime` is A4's notification-panel time formatter ("5 min ago", "yesterday 18:02") and `l10n.dialogCancel` A1's Cancel string — use their real names. The tmux list's `ListView` is wrapped in a `Focus` whose `onKeyEvent` moves `_tmuxCursor` with ↑/↓ and attaches on Enter (UI-A8 §6).

On Windows (`defaultTargetPlatform == TargetPlatform.windows`) the tmux source field has no "This computer" choice: an empty field there shows `tmuxUnavailable(l10n.tmuxSourceLocal)` without running anything.

- [ ] **Step 4: Route, shortcut, `+` menu, tray**

- `window_router.dart`: `final class SshConnectRoute extends WindowRoute { const SshConnectRoute([this.tab = SshDialogTab.ssh]); final SshDialogTab tab; }` (import the enum from the dialog file, or move the enum into `window_router.dart` and re-export it from the dialog).
- `route_dialog.dart`: render `SshConnectRoute(:final tab)` as `SshConnectDialog(initialTab: tab)` inside the standard A1 dialog container (width `connectDialogWidth`).
- `terminal_shortcuts.dart`: `class OpenSshConnectIntent extends Intent { const OpenSshConnectIntent(); }` mapped from `shifted(LogicalKeyboardKey.keyK)` (⌘⇧K / Ctrl+Shift+K, no repeat). If A9 is merged, register it in A9's binding table as action id `ssh.connect` with these defaults instead of the hard-coded map.
- `terminal_workspace_page.dart`: `OpenSshConnectIntent: CallbackAction(onInvoke: (_) => ref.read(windowRouterProvider.notifier).open(const SshConnectRoute()))`.
- `session_sidebar.dart`: secondary click / Shift+F10 / Menu key on the header `+` opens a menu (A2 menu style): "New tab ⌘T" (`sshActions.newTab()`), "Connect over SSH… ⌘⇧K" (`SshConnectRoute()`), "Attach tmux session…" (`SshConnectRoute(SshDialogTab.tmux)`).
- Tray (`tray_action.dart`, `tray_menu.dart`, `tray_actions.dart`): a submenu `sshTrayMenu` right after A7's "Dòng lệnh" in both signed-in and signed-out menus: `sshConnectMenu`, `tmuxAttachMenu` (both: show the window, then open the route), separator, checkbox `sshTrayHook` bound to `SettingKeys.sshRemoteHook` (default true), `sshTrayClearRecent` (disabled when `recentTargets(settings)` is empty; on click `clearRecentTargets` + neutral toast `sshRecentCleared`). Extend the tray menu test that lists submenu items with these four entries.

- [ ] **Step 5: Run the tests**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/ui/terminal/ssh_connect_dialog.dart apps/desktop/lib/src/ui/window_router.dart apps/desktop/lib/src/ui/dialogs/route_dialog.dart apps/desktop/lib/src/ui/terminal/terminal_shortcuts.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/lib/src/tray/tray_action.dart apps/desktop/lib/src/tray/tray_menu.dart apps/desktop/lib/src/tray/tray_actions.dart apps/desktop/test/ui/ssh_connect_dialog_test.dart apps/desktop/test/ui/terminal_shortcuts_test.dart apps/desktop/test/tray/
git commit -m "feat(desktop): Connect to a server — SSH and tmux in one dialog, ⌘⇧K, the + menu and the tray SSH submenu (A8 D41, D42; UI-A8 §4-§6)"
```

---

### Task 13: Restore (A5a) and the daemon wire (A5b) (D29, D31)

**Files:**
- Modify: `apps/desktop/lib/src/restore/restore_snapshot.dart` (`SavedPane.launch`), `apps/desktop/lib/src/restore/restore_persistence.dart` (snapshot from panes; `paneKey` follows `paneReplacements`), `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`restore` opens with the launch; a remote leaf is never dropped for not connecting)
- Modify (A5b merged only): the mux session codec (A5b plan Task 3/4: where `SessionSummary` and `sessions.open` are encoded), `packages/shellx_agent/lib/src/mux/remote_local_sessions.dart`, `packages/shellx_agent/lib/src/mux/mux_server.dart`
- Test: `apps/desktop/test/restore/restore_remote_test.dart`; (A5b) the shared `local_sessions_contract.dart` gains one remote case

**Interfaces:**
- Consumes: Task 1 `SessionLaunch.toJson/fromJson`, `forReconnect`; Task 7 `PaneSession.remote`, `paneReplacements`; A5a `SavedPane`, `RestoreSnapshot.fromState`/`tryParse`, `RestorePlan`, `TerminalTabs.restore`, `RestorePersistence`.
- Produces:
  - `SavedPane({required String key, String? cwd, int? session, SessionLaunch? launch})`; JSON leaf key `"launch"` (absent for local panes; v stays 1 — older builds ignore unknown keys, A5a D11).
  - (A5b) `sessions.open{…, launch?}`; summaries on the wire carry `remote: {launch, connected, home?}`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/restore/restore_remote_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/remote_state.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final devbox = SshTarget.parse('devbox')!;
final k1 = 'a' * 32;
final k2 = 'b' * 32;

RestoreSnapshot snap(SavedPaneNode layout) => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 9),
  cleanExit: true,
  selectedTab: k1,
  workspaces: [SavedWorkspace(id: 'default', tabs: [k1])],
  tabs: [SavedTab(key: k1, focused: k1, layout: layout)],
);

SavedPaneNode twoPanes({SessionLaunch? launch}) => SavedSplit(
  axis: SplitAxis.row,
  ratio: 0.5,
  first: SavedPane(key: k1, cwd: '/srv/app', launch: launch ?? SshLaunch(devbox, remoteCwd: '/srv/app')),
  second: SavedPane(key: k2, cwd: '/Users/me'),
);

void main() {
  test('a leaf keeps its launch through the file; old leaves are local (D29)', () {
    final back = RestoreSnapshot.tryParse(snap(twoPanes()).encode())!;
    final leaves = savedLeaves(back.tabs.single.layout);
    expect(leaves.first.launch, SshLaunch(devbox, remoteCwd: '/srv/app'));
    expect(leaves.last.launch, isNull);
    expect(snap(twoPanes()).encode(), contains('"launch":{"kind":"ssh","target":"devbox","cwd":"/srv/app","hook":true}'));
  });

  test('a launch that does not validate makes the file broken (A5a D11)', () {
    final text = snap(twoPanes()).encode().replaceAll('"target":"devbox"', '"target":"-oProxyCommand=touch /tmp/pwn"');
    expect(RestoreSnapshot.tryParse(text), isNull);
    final tmux = snap(twoPanes(launch: TmuxLaunch('main', host: devbox))).encode().replaceAll('"session":"main"', '"session":"a:b"');
    expect(RestoreSnapshot.tryParse(tmux), isNull);
  });

  test('restore opens SSH leaves with their launch, local ones with their cwd; '
      'an unreachable server stays in the tree as failed (D29)', () async {
    final local = FakeLocalSessions();
    final container = ProviderContainer.test(overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(lookupAppLocalizations(const Locale('en'))),
    ]);
    final tabs = container.read(terminalTabsProvider.notifier);
    await tabs.restore(RestorePlan(snapshot: snap(twoPanes()), textByKey: const {}));
    expect(local.openLaunches, [SshLaunch(devbox, remoteCwd: '/srv/app'), null]);
    expect(local.openCwds, [null, '/Users/me']);
    final sshId = local.nextId - 2;
    local.summaries.removeWhere((s) => s.id == sshId);
    local.views[sshId]!.end(255);
    await pumpEventQueue();
    final tab = container.read(terminalTabsProvider).tabs.single;
    expect(tab.paneCount, 2);
    expect(tab.panes[sshId]!.remoteState, RemoteState.failed);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/restore_remote_test.dart`
Expected: FAIL — `launch` unknown.

- [ ] **Step 3: Implement**

- `SavedPane`: field `final SessionLaunch? launch;`, constructor parameter, the leaf's JSON gains `if (launch != null) 'launch': launch!.toJson()`, parsing: `final rawLaunch = json['launch']; final launch = rawLaunch == null ? null : SessionLaunch.fromJson(rawLaunch); if (rawLaunch != null && launch == null) return null;` — an invalid leaf, so `tryParse` treats the whole file as broken (A5a D11: `.bak`, start fresh; only a hand-edited file gets here). `==`/`hashCode` include it.
- `captureSnapshot` (A5a Task 2): each leaf gets `launch: pane.remote?.launch.forReconnect(pane.cwd)`; `cwd: pane.cwd` stays as it is (A5a reads `cwd` only for local leaves; the remote folder travels in the launch).
- `TerminalTabs.restore`: for a leaf with `launch`, call `_local.open(cols, rows, launch: leaf.launch)` (no `cwd`); a `SpawnFailedException('ssh_unavailable')` removes the leaf like any spawn failure (A5a D7); a later exit before hello is handled by Task 7's `failed` state — the leaf stays.
- `RestorePersistence`: subscribe to `terminalTabsProvider.notifier.paneReplacements` and move the `paneKey` from `from` to `to` (`_keys[r.to] = _keys.remove(r.from)!`), then mark the layout dirty.

If A5b is merged: in the mux codec, encode `launch` in `sessions.open` as `launch.toJson()` (CBOR map) and decode with `SessionLaunch.fromJson` (bad → `bad_request`); encode `SessionSummary.remote` as `{launch, connected, home?}` and decode it back to `SessionRemote` (bad → summary without `remote`). `RemoteLocalSessions.open` forwards `launch` (replace Task 5's temporary refusal); `MuxServer` passes it to `SessionManager.open`. The contract suite (`local_sessions_contract.dart`) gains one case run against both implementations: `open(launch: const TmuxLaunch('main'))` with a fake tmux path returns a session whose summary has `remote.launch == const TmuxLaunch('main')` and `remote.connected == true`.

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/restore/restore_snapshot.dart apps/desktop/lib/src/restore/restore_persistence.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/test/restore/restore_remote_test.dart
# with A5b: the mux codec, remote_local_sessions.dart, mux_server.dart, packages/shellx_agent/test/mux/…
git commit -m "feat(desktop): SSH and tmux panes come back after a restart — launch saved per leaf, reconnected on restore, kept when unreachable; daemon wire carries launch and remote (A8 D29, D31)"
```

---

### Task 14: CLI (A7) — `shellx ssh`, `shellx tmux ls|attach`, `remote` in `ls`, replaced pane ids (D22, D33)

**Files:**
- Modify: `packages/shellx_agent/lib/src/mux/cli_wire.dart` (types, caps, errors), `apps/desktop/lib/src/cli/ui_command_handler.dart`, `apps/desktop/lib/src/cli/cli_targets.dart` (resolve through `resolveReplaced`), `apps/desktop/lib/src/cli/cli_event_bus.dart` (`pane.replaced`)
- Modify: `term/src/api/args.rs`, `term/src/api/run.rs`, `agent-skills/shellx/reference.md`
- Test: `apps/desktop/test/cli/ui_command_handler_ssh_test.dart`, the Rust tests at the bottom of `args.rs` and `run.rs`

**Interfaces:**
- Consumes: Task 8 `SshActions.connectForCli`, `attachTmuxForCli`, `listTmux`; Task 7 `resolveReplaced`, `paneReplacements`, `PaneSession.remote/remoteState`; A7 `UiCommandHandler`, `CliFailure`, `_opening`, `CliEventBus`, Rust `COMMANDS`, `Prepared`.
- Produces:
  - `CliType.uiSshOpen = 'ui.ssh.open'`, `uiTmuxList = 'ui.tmux.list'`, `uiTmuxAttach = 'ui.tmux.attach'`; `kCliCaps` gains `'ui.ssh'`, `'ui.tmux'`; `CliError.sshUnavailable = 'ssh_unavailable'`, `tmuxUnavailable = 'tmux_unavailable'`, `tmuxFailed = 'tmux_failed'`.
  - `ui.ssh.open{target, workspace?, cwd?, cmd?, hook, focus}` → `{tab, pane}`; `ui.tmux.list{host?}` → `{sessions: [{name, windows, attached, activity}]}`; `ui.tmux.attach{name, host?, create, focus}` → `{tab, pane}`; `ui.ls` panes gain `remote: {kind, host?, tmux?, state}`; event `pane.replaced{old, new}`.
  - Rust: commands `ssh`, `tmux ls`, `tmux attach`; exit 1 for the three new error codes.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/cli/ui_command_handler_ssh_test.dart` (build the container exactly like A7's `ui_command_handler_test.dart`; add the Task 8 overrides `remoteToolsProvider`, `commandRunnerProvider`, `sshConfigHostsProvider`):

```dart
  test('ui.ssh.open: validates, lands in the SSH workspace, no focus, --cmd waits (D33)', () async {
    final r = await handle({'t': 'ui.ssh.open', 'target': 'devbox', 'cwd': '/srv', 'hook': true});
    expect(r['tab'], isA<int>());
    expect(local.openLaunches.last, SshLaunch(SshTarget.parse('devbox')!, remoteCwd: '/srv'));
    expect(tabsState().selectedId, isNot(r['tab']));
    await expectLater(
      handle({'t': 'ui.ssh.open', 'target': '-oProxyCommand=x'}),
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', 'bad_request')),
    );
    await expectLater(
      handle({'t': 'ui.ssh.open', 'target': 'devbox', 'cwd': 'relative'}),
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', 'bad_request')),
    );
    local.openError = const SpawnFailedException('ssh_unavailable');
    await expectLater(
      handle({'t': 'ui.ssh.open', 'target': 'devbox'}),
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', 'ssh_unavailable')),
    );
  });

  test('ui.tmux.list / ui.tmux.attach', () async {
    final list = await handle({'t': 'ui.tmux.list'});
    expect(list['sessions'], [
      {'name': 'main', 'windows': 3, 'attached': 0, 'activity': 1759831200},
    ]);
    final a = await handle({'t': 'ui.tmux.attach', 'name': 'main'});
    expect(local.openLaunches.last, const TmuxLaunch('main'));
    expect(a['pane'], isA<int>());
    await expectLater(
      handle({'t': 'ui.tmux.attach', 'name': 'a:b'}),
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', 'bad_request')),
    );
  });

  test('ls carries remote; a replaced pane id still resolves (D22)', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(SshTarget.parse('devbox')!), connected: true)));
    final ls = await handle({'t': 'ui.ls'});
    final pane = ((ls['workspaces'] as List).first['tabs'] as List).first['panes'].first as Map;
    expect(pane['remote'], {'kind': 'ssh', 'host': 'devbox', 'state': 'connected'});
    local.summaries.removeWhere((s) => s.id == 1);
    local.views[1]!.end(255);
    await pumpEventQueue();
    final fresh = await tabs().reconnect(1);
    await handle({'t': 'ui.pane.send', 'pane': 1, 'text': 'ls'});
    expect(local.views[fresh]!.writes.join(), contains('ls'));
  });
```

(`handle(Map)` is the A7 test helper that wraps a map into a `MuxMessage` and calls `UiCommandHandler.handle`; use the file's real helper.)

Rust, at the bottom of `term/src/api/args.rs` `mod tests`:

```rust
    #[test]
    fn ssh_and_tmux_commands() {
        let x = run(&["ssh", "me@devbox:2222", "--cwd", "/srv", "--cmd", "make", "--no-hook", "--focus"]);
        assert_eq!(x.spec.path, &["ssh"]);
        assert_eq!(x.pos(0), Some("me@devbox:2222"));
        assert_eq!(x.flag("cwd"), Some("/srv"));
        assert!(x.has("no-hook"));
        let l = run(&["tmux", "ls", "--host", "devbox", "--json"]);
        assert_eq!(l.spec.path, &["tmux", "ls"]);
        assert!(l.json);
        let a = run(&["tmux", "attach", "main", "--create"]);
        assert_eq!(a.pos(0), Some("main"));
        assert!(a.has("create"));
        assert!(help_text(None).contains("ssh"));
        assert!(completion_script("zsh").unwrap().contains("attach"));
    }
```

and in `run.rs` tests (A7's fake-host pattern):

```rust
    #[test]
    fn ssh_prints_the_tab_and_maps_errors() {
        // fake host answers ui.ssh.open with {tab: 41, pane: 41}
        // → stdout "t41\n", exit 0; with --json → {"tab":"t41","pane":"p41"}
        // fake host answers error{code: ssh_unavailable} → exit 1, stderr "shellx: … (ssh_unavailable)"
        // a host without cap "ui.ssh" → exit 7 before any ui.ssh.open is sent
    }

    #[test]
    fn tmux_ls_prints_a_table_or_json() {
        // {sessions:[{name:"main",windows:3,attached:0,activity:1759831200}]}
        // → "main\t3 windows\n" (attached > 0 adds "\tattached"); --json prints the object as is
    }
```

Write both with A7's `FakeSession` helper; the comments are the exact expectations.

- [ ] **Step 2: Run them to see them fail**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli/ui_command_handler_ssh_test.dart; cd ../..
cd term && ~/.cargo/bin/cargo test api:: ; cd ..
```

Expected: FAIL.

- [ ] **Step 3: Implement (Dart)**

`cli_wire.dart`: the three types, two caps, three error codes (as Produces).

`ui_command_handler.dart` — in `handle`'s switch:

```dart
      CliType.uiSshOpen => _sshOpen(r),
      CliType.uiTmuxList => _tmuxList(r),
      CliType.uiTmuxAttach => _tmuxAttach(r),
```

```dart
  SshTarget _target(MuxMessage r, String key) {
    final text = _string(r, key, max: 255);
    final target = text == null ? null : SshTarget.parse(text);
    if (target == null) throw _bad('$key must be a server (alias or user@host:port)');
    return target;
  }

  Future<Map<String, Object?>> _sshOpen(MuxMessage r) async {
    final target = _target(r, 'target');
    final cwd = _string(r, 'cwd');
    if (cwd != null && !isValidRemoteCwd(cwd)) throw _bad('cwd must start with / or ~');
    final cmd = _string(r, 'cmd', max: 16384);
    final workspace = r.fields['workspace'] == null ? null : resolveWorkspace(_sideState, _string(r, 'workspace')!);
    final focus = _flag(r, 'focus');
    final tab = await _opening(() => _remote(() => _ssh.connectForCli(
      target,
      workspaceId: workspace,
      remoteCwd: cwd,
      hook: r.fields['hook'] != false,
      select: focus,
    )));
    _marks.touch(tab: tab, pane: tab);
    if (cmd != null) CommandInjector(_ref, pane: tab).inject(cmd); // A7 D16; ready = first OSC 7 (D32)
    return {'tab': tab, 'pane': tab};
  }

  Future<Map<String, Object?>> _tmuxList(MuxMessage r) async {
    final host = r.fields['host'] == null ? null : _target(r, 'host');
    final result = await _ssh.listTmux(host);
    return switch (result) {
      TmuxSessions(:final sessions) => {
        'sessions': [
          for (final s in sessions)
            {
              'name': s.name,
              'windows': s.windows,
              'attached': s.attached,
              if (s.activity != null) 'activity': s.activity!.millisecondsSinceEpoch ~/ 1000,
            },
        ],
      },
      TmuxUnavailable() => throw const CliFailure(CliError.tmuxUnavailable, 'tmux is not installed there'),
      TmuxListFailed(:final reason) => throw CliFailure(
        CliError.tmuxFailed,
        reason == TmuxListFailure.auth ? 'the server wants a password: connect once with shellx ssh' : 'could not list tmux sessions',
      ),
    };
  }

  Future<Map<String, Object?>> _tmuxAttach(MuxMessage r) async {
    final name = _string(r, 'name', max: 64);
    if (name == null || !isValidTmuxName(name)) throw _bad('name: 1-64 characters, no ":" or "."');
    final host = r.fields['host'] == null ? null : _target(r, 'host');
    final focus = _flag(r, 'focus');
    final tab = await _opening(() => _remote(() => _ssh.attachTmuxForCli(name, host: host, create: _flag(r, 'create'), select: focus)));
    _marks.touch(tab: tab, pane: tab);
    return {'tab': tab, 'pane': tab};
  }

  /// D33: the A8 spawn failures by name; everything else as A7's `_opening`.
  Future<T> _remote<T>(Future<T> Function() open) async {
    try {
      return await open();
    } on SpawnFailedException catch (e) {
      switch (e.message) {
        case 'ssh_unavailable':
          throw const CliFailure(CliError.sshUnavailable, 'ssh is not installed on this computer');
        case 'tmux_unavailable':
          throw const CliFailure(CliError.tmuxUnavailable, 'tmux is not installed on this computer');
      }
      rethrow;
    }
  }

  SshActions get _ssh => _ref.read(sshActionsProvider);
```

(`CommandInjector(...).inject` is A7 Task 7's `--cmd` path — call it exactly as `_tabNew` does. `resolveWorkspace` is A7 Task 6's.)

In `_ls`, each terminal pane map gains:

```dart
              if (p.remote case final remote?)
                'remote': {
                  'kind': remote.isTmux ? 'tmux' : 'ssh',
                  if (remote.hostKey != null) 'host': remote.hostKey,
                  if (remote.tmuxSession != null) 'tmux': remote.tmuxSession,
                  'state': (p.remoteState ?? RemoteState.connected).name,
                },
```

`cli_targets.dart` — wherever a numeric pane id is looked up in `TerminalTabsState`, look up `tabs.resolveReplaced(id)` first (D22). `cli_event_bus.dart` — subscribe to `paneReplacements` and emit `{'kind': 'pane.replaced', 'old': r.from, 'new': r.to, 'tab': r.tabId}`.

- [ ] **Step 4: Implement (Rust)**

`term/src/api/args.rs` — add to `COMMANDS` (after the `browser` rows):

```rust
    c(&["ssh"], &["TARGET"], &[v("workspace", "W", "workspace id or name (default: the server's SSH workspace)"), v("cwd", "DIR", "folder on the server (/… or ~/…)"), v("cmd", "COMMAND", "type COMMAND once the remote shell is ready"), f("no-hook", "do not install the ShellX hook on the server"), FOCUS], "open a tab on a server over SSH; prints its id"),
    c(&["tmux", "ls"], &[], &[v("host", "TARGET", "list on this server (default: this computer)")], "list tmux sessions"),
    c(&["tmux", "attach"], &["NAME"], &[v("host", "TARGET", "server (default: this computer)"), f("create", "create the session when it does not exist"), FOCUS], "attach a tmux session as a tab; prints its id"),
```

and add `"ssh"`, `"tmux ls"`, `"tmux attach"` to `every_spec_command_exists`.

`term/src/api/run.rs` — in `prepare`:

```rust
        "ssh" => {
            if pos(0).is_empty() {
                return Err(usage("ssh needs a TARGET (alias or user@host:port)"));
            }
            if p.flag("cmd").is_some_and(|c| c.len() > 16_384) {
                return Err(usage("--cmd is over 16 KiB"));
            }
            Prepared::Simple {
                t: "ui.ssh.open",
                fields: vec![
                    ("target", Some(Value::text(pos(0)))),
                    ("workspace", text(p.flag("workspace"))),
                    ("cwd", text(p.flag("cwd"))), // a server path: never made absolute here
                    ("cmd", text(p.flag("cmd"))),
                    ("hook", Some(Value::Bool(!p.has("no-hook")))),
                    ("focus", flag(p, "focus")),
                ],
                id_key: Some("tab"),
                prefix: "t",
            }
        }
        "tmux attach" => Prepared::Simple {
            t: "ui.tmux.attach",
            fields: vec![
                ("name", Some(Value::text(pos(0)))),
                ("host", text(p.flag("host"))),
                ("create", flag(p, "create")),
                ("focus", flag(p, "focus")),
            ],
            id_key: Some("tab"),
            prefix: "t",
        },
        "tmux ls" => Prepared::TmuxList { host: text(p.flag("host")) },
```

Add the variant `TmuxList { host: Option<Value> }` to `Prepared`; execute it like `Prepared::BrowserList` (one request `ui.tmux.list`); print: with `--json` the result object as JSON; otherwise one line per session `name\t<windows> window(s)[\tattached]`, nothing for an empty list. Map caps: commands under `ssh` need `ui.ssh`, under `tmux` need `ui.tmux` (A7 D4's `needs_cap` table). Exit codes: `ssh_unavailable`, `tmux_unavailable`, `tmux_failed` → 1 (A7 D10 "other error" — add them to the mapping list explicitly so they are not mistaken for incompatibility).

`agent-skills/shellx/reference.md` — a section "SSH and tmux" listing the three commands, their flags, outputs, exit codes, and two recipes: "open a server tab next to the user and run tests: `t=$(shellx ssh devbox --cwd ~/app --cmd 'make test')`; `shellx wait p${t#t} --match 'PASS|FAIL' --timeout 600`" and "attach the team's tmux session: `shellx tmux ls --host devbox --json` then `shellx tmux attach main --host devbox`". State that `shellx` does not exist on the server, and that `shellx notify` inside a ShellX SSH pane works (it is a shell function there).

- [ ] **Step 5: Run the tests**

```bash
cd term && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && ~/.cargo/bin/cargo test && cd ..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
```

Expected: PASS; A7's contract suite (both hosts) green.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent/lib/src/mux/cli_wire.dart apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/lib/src/cli/cli_targets.dart apps/desktop/lib/src/cli/cli_event_bus.dart apps/desktop/test/cli/ui_command_handler_ssh_test.dart term/src/api/args.rs term/src/api/run.rs agent-skills/shellx/reference.md
git commit -m "feat(cli): shellx ssh, shellx tmux ls/attach, remote in ls, replaced pane ids keep working (A8 D22, D33)"
```

---

### Task 15: Privacy page, HANDOFF, ⚠ MANUAL verification, full suite (D37, D43, D44)

**Files:**
- Modify: `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `docs/superpowers/HANDOFF.md`, `docs/superpowers/ledgers/a1-desktop-terminal.md`

- [ ] **Step 1: Privacy page (D37)**

Add one bullet to §4 of both pages (vi / en):

- vi: "**SSH (máy tính):** khi bạn kết nối tới máy chủ, ShellX chạy lệnh `ssh` của máy bạn với khoá và cấu hình của bạn; ShellX không hỏi, không lưu mật khẩu. Nếu bật hook, ShellX ghi vài tệp script nhỏ vào `~/.cache/shellx/` trên máy chủ để biết thư mục, nhánh git và cổng đang mở — không gửi gì khác đi đâu. Danh sách máy gần đây chỉ lưu trên máy tính này."
- en: "**SSH (desktop):** when you connect to a server, ShellX runs your computer's `ssh` with your keys and configuration; it never asks for or stores passwords. With the hook on, ShellX writes a few small script files to `~/.cache/shellx/` on the server to know its folder, git branch and listening ports — nothing else is sent anywhere. The recent-servers list stays on this computer."

```bash
git add web/src/pages/privacy.md web/src/pages/en/privacy.md
git commit -m "docs(web): privacy — SSH from the desktop app (A8 D37)"
```

- [ ] **Step 2: HANDOFF section and the ⚠ MANUAL checklist**

Add `## N. SSH và tmux — A8 (2026-10-07)` to `docs/superpowers/HANDOFF.md` (numbered after the last section): spec/plan/UI paths; where things live (control sockets `/tmp/shellx-ssh-<uid>/`, server cache `~/.cache/shellx/remote-<hash>/`, settings keys); the tray "SSH" submenu; how to remove the server side (`rm -rf ~/.cache/shellx`); and this checklist — each line recorded pass/fail with date and machine in the ledger:

1. ⚠ macOS → Linux server (zsh, bash, fish accounts) with a key in the agent: spec criteria 1, 3, 4 (no second password, ≤ 500 ms on LAN), 9, 10, 11 (log grep).
2. ⚠ Password-only account and an OTP (PAM) account: the prompt in the pane, split during the prompt (D9: typed within 3 s → second pane does not ask), `grep -r` of the app support folder and `~/Library/Preferences/pro.shellx.desktop.plist` for the typed password → nothing.
3. ⚠ Host key: first connection (`yes/no` in the pane); a changed key (ssh's warning, pane `failed`, `known_hosts` untouched).
4. ⚠ Wi-Fi off 60 s, then on: line + strip ≤ 50 s, countdown, automatic reconnect into the same slot, `~/work/api` restored, divider; laptop sleep 5 min → retry at wake; wrong password → never retries alone.
5. ⚠ tmux: local `main` (Homebrew tmux), server `main`; close tab → `tmux ls` still lists it; drop Wi-Fi → reconnect re-attaches and a running `top` inside tmux continues; "Create and attach".
6. ⚠ Restore (A5a): spec criterion 7, including an unreachable server (pane `failed`, layout kept). With A5b: criterion 8 (`top` in an SSH pane survives ⌘Q).
7. ⚠ Ports: `python3 -m http.server 8000` on the server → `:8000` in ≤ 6 s; click → page of the server; with local 8000 busy → another port, tooltip shows it; ⌥-click → browser pane; close the last pane → `ssh -O check` fine and the forward gone (`lsof -iTCP:8000` empty).
8. ⚠ Control directory: `ls -ld /tmp/shellx-ssh-$(id -u)` is `drwx------` and yours; pre-create it as another user (or `chmod 777` it) → ShellX logs `ssh: control dir unsafe` once and SSH still works without multiplexing.
9. ⚠ Windows 11 (`ssh.exe` 8.x+, ssh-agent service): criteria 1–7 and 10 (each pane authenticates; ports every 15 s; forward via a `-N` process), Ctrl+C, `~.`, vim resize, ConPTY with the password prompt; no OpenSSH Client → toast with the Settings hint.
10. ⚠ Accessibility: VoiceOver/Narrator read the row ("…, on devbox, Lost connection to devbox"), the strip once (no per-second reading), the dialog's suggestions; keyboard only: ⌘⇧K, ↓ Enter, Tab order of UI-A8 §6, Ctrl+F6 into the strip.
11. ⚠ Performance (D44): `ssh -G` + spawn ≤ 80 ms (Instruments/`time` around `open`), dialog opens ≤ 50 ms with a 200-host config, probe parse ≤ 5 ms for 2000 processes (debug timing, removed after).

Ledger section `## A8 (SSH/tmux) — execution`: the merge state found at the start (A5a/A5b/A7/A9), every deviation from this plan with "cost if wrong", the D44 numbers, the checklist results.

```bash
git add docs/superpowers/HANDOFF.md docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "docs: A8 HANDOFF checklist and ledger"
```

- [ ] **Step 3: Full verification**

```bash
cd term && ~/.cargo/bin/cargo fmt --check && ~/.cargo/bin/cargo clippy --all-targets -- -D warnings && ~/.cargo/bin/cargo test && ~/.cargo/bin/cargo test --features test-hooks && cd ..
cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test && cd ../shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test && cd ../shellx_e2e && ~/fvm/versions/3.41.4/bin/dart test && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && cd ../..
```

Expected: everything green; counts ≥ baseline + new tests. These must print nothing:

```bash
git diff main --stat -- packages/shellx_core/lib/src/protocol apps/mobile relay term/src/proto term/shell
git diff main -- packages/shellx_agent/lib/src/pty/shell_hook_scripts.dart
git diff main -- '**/pubspec.yaml' term/Cargo.toml
```

The branch merges only after every ⚠ line above is recorded as passed.

---

## Self-Review

**Spec coverage** (spec decision → task):
- D1 (prerequisites) → "Prerequisite" section; D40 (quit) → Task 4 `exitMasters` + Task 8 Step 3.
- S1/D2–D7 (system ssh, targets, keys, agent, no passwords) → Tasks 1, 3, 5, 8, 12; D8/D9 (multiplexing, master wait) → Tasks 4, 5; D10/D11/D15/D16 (bootstrap, hook toggle, branch, OSC 6973) → Tasks 3, 5, 8, 11, 12; D12/D13 (ssh options, keepalive) → Tasks 3, 4, 5; D14 (remote cwd) → Task 5, displayed Task 11; D17 (states) → Tasks 5, 7, 11; D18 (ports) → Tasks 2, 6; D19 (forwards) → Tasks 4, 10, 11; D20/D21/D22 (reconnect, same terminal, id forwarding) → Tasks 7, 9, 11, 13, 14; D23 (SSH workspaces) → Tasks 8, 11; D24 (splits) → Tasks 1, 7, 11; D25–D28 (tmux) → Tasks 1, 2, 3, 5, 8, 12, 14; D29/D30 (restore) → Task 13; D31 (daemon) → Tasks 5, 13; D32/D33/D34 (CLI) → Task 14; D35 (notifications) → unchanged code path (Task 3 keeps the hook's `shellx notify`, Task 15 checklist 1); D36 (phone) → Task 5; D37 (privacy) → every task's `toString`/log rules, tests in Tasks 5, 6, Task 15 page; D38 (security) → Tasks 1, 3, 4, 13, 14; D39 (limits) → Tasks 1–6; D41/D42 (entry points, dialog) → Task 12; D43 (Windows) → Tasks 3, 4, Task 15 ⚠; D44 → Task 15 ⚠.
- UI addendum §1 → Task 11 sizes; §2–§3 → Task 11; §4–§6 → Task 12; §7 → Task 7 Step 1; §8 → Tasks 11, 12.

**Placeholder scan:** Task 14's two Rust `run.rs` tests are given as exact expectations in comments because they must use A7 Task 10's private `FakeSession` test helper, whose shape A7 defines; every other step carries full code. No "TBD"/"similar to Task N".

**Type consistency:** `SshTarget.key`/`destinationArgs` (Task 1) are the only way targets reach ssh (Tasks 3, 4, 8, 14). `SessionLaunch` = `SshLaunch | TmuxLaunch` everywhere; `SessionRemote{launch, connected, home}` flows agent → `SessionSummary.remote` → `PaneSession.remote` → `remoteStateOf` (Task 7) → UI (Task 11) and CLI (Task 14). `RemoteTools{sshPath, tmuxPath, control}` is built by `resolveRemoteTools` (Task 4) and consumed by `SessionManager` (Task 5) and `remoteToolsProvider` (Tasks 8, 10, 12). `CommandRunner`'s signature `(String, List<String>, {Duration timeout})` is the same in every fake. `TerminalTabs.reconnect(id, {withoutHook})` (Task 7) ← `SshReconnector.reconnectNow(id, {withoutHook})` (Task 9) ← `RemoteStrip` (Task 11). `PaneReplacement{tabId, from, to}` (Task 7) → reconnector (Task 9), restore keys (Task 13), CLI events (Task 14). Spawn failure messages `ssh_unavailable` / `tmux_unavailable` / `bad_launch` (Task 5) → `spawnNoticeFor` (Task 7) and `CliError` (Task 14).

**Fixes applied during review:** D40's master exit had no step — added to Task 8 Step 3 ("Quit completely"). Task 13's restore test was a comment — now real code against A5a's `RestoreSnapshot`/`RestorePlan`, and the spec's D29 was aligned with A5a D11 (a bad `launch` breaks the file, it does not silently drop a leaf). The dialog's private widgets were prose — now code. The ⌘⇧K dialog test pressed ↓ once but expected the second suggestion — fixed to ↓ ↓. Widget tests that leave timers (reconnector 3 s, "Loading…" 300 ms) now tear down / settle explicitly.
