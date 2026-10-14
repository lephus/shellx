# ShellX V2-1a — AI foundation (ACP client, session model, agent host) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart foundation of the desktop AI tab. It talks ACP v1 to a real agent process, turns everything the agent says into a timeline the UI can draw, answers permissions and questions, checkpoints the project before every turn so a turn can be undone, and never leaves an agent process behind. There is no Flutter UI in this plan; plan V2-1b builds the tab on top of it.

**Architecture:** Two new workspace packages, both pure Dart:
- `packages/shellx_acp`:
  - JSON-RPC 2.0 over newline-delimited stdio (`JsonRpcConnection`);
  - the ACP v1 types ShellX uses, with tolerant parsers and schema-checked request builders;
  - `AcpClient`;
  - a scripted `FakeAgent` that runs in process or as a real process (`bin/fake_agent.dart`).
- `packages/shellx_ai`:
  - `package:shellx_ai/shellx_ai.dart`: the transport-free session model (`Timeline`, `AiSessionState`). The phone reuses it in V2-2, so it has no `dart:io`.
  - `package:shellx_ai/host.dart` (`dart:io`): the login-shell environment, the agent catalog and resolver, `AgentProcess`, the crash registry `RunningAgents`, the shadow-git `CheckpointStore`, and `AiRuntime`, which ties one AI tab together.

The desktop app only wires `host.dart` into widgets in V2-1b.

**Tech Stack:** Dart ^3.11 (`~/fvm/versions/3.41.4/bin/dart`; the workspace resolves with `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the repo root because it includes the Flutter apps), `package:test`, `package:async` (StreamQueue in tests), `package:json_schema` (dev, schema conformance), `package:crypto` + `package:path` (host). Real `git` and real child processes in host tests; no network in any test.

**Spec:** `docs/superpowers/specs/2026-10-14-ai-pane-design.md`, which is binding. It covers D1, D6, D8–D12, D16, D20, D22 and D23, plus §5 (privacy), §6 (errors and edges), §7 (tests) and §12 (Task-1 checks). The demo in `docs/superpowers/design/2026-10-14-ai-pane-demo/` shows the intended behaviour; `demo.js` plays the client side of the same ACP messages.

## Prerequisite and how this plan was made

Work on branch `shellx-v2` (V2 lives there; `main` keeps V1). The plan was written after reading:
- the ACP schema v1 1.25.0 (`schema.json`, `meta.json`, CHANGELOG, 2026-10-09);
- the `@agentclientprotocol/claude-agent-acp` 0.90.0 sources;
- the ACP registry;
- the ShellX code named in spec §2.

One behaviour was probed on this Mac (git 2.56): with `GIT_DIR` set elsewhere, `git add -A` **aborts the whole add** when the work tree contains a nested repository without commits (`error: 'sub/' does not have a commit checked out`). Without `--directory`, `git ls-files --others` lists such a repository as one entry ending in `/`. Task 8 is built on that.

Run first and record the baseline in the new ledger `docs/superpowers/ledgers/v2-ai.md`:

```bash
git switch shellx-v2 && git log --oneline -1
~/fvm/versions/3.41.4/bin/dart --version
git --version; node --version; which npm claude codex gemini opencode
cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart test 2>&1 | tail -1; cd ../..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test 2>&1 | tail -1; cd ../..
```

The ledger starts with this header and the rulings below. The controller appends one line per task as it lands.

```markdown
# V2 AI — execution ledger (branch shellx-v2)

## V2-1a (foundation) — planning rulings
```

## Rulings (deviations from the spec, recorded in the ledger)

- **R1 — host code lives in `package:shellx_ai/host.dart`, not `apps/desktop/lib/src/ai/`** (spec D6, D12). It is pure Dart, so `dart test` runs it with real processes and real git, on macOS and on the Windows CI. The desktop app only wires it. *Cost if wrong:* one move.
- **R2 — Gemini CLI runs from the pinned npm package** (`@google/gemini-cli@0.64.0`, entry from its `bin`, args `--acp`), installed like the Claude and Codex adapters. This follows the ACP registry instead of `gemini` from PATH (spec D6). OpenCode stays a PATH command (`opencode acp`). *Cost if wrong:* one catalog entry.
- **R3 — checkpoints use plumbing** (`git add -A`, `write-tree`, `commit-tree`, `update-ref`) instead of `git commit` (spec D12).
  - Why: no hooks, no GPG prompt, no `commit.*` user config.
  - Every git call also passes `-c core.autocrlf=false -c core.fsmonitor=false -c commit.gpgSign=false -c gc.auto=0 -c maintenance.auto=false -c core.logAllRefUpdates=false -c core.hooksPath=<shadow repo>/hooks`. A global `reference-transaction` hook could otherwise veto `update-ref`.
  - `$GIT_DIR/info/attributes` holds `* -text -filter -ident -working-tree-encoding`, so a project's `.gitattributes` (`text=auto`, `filter=lfs`) cannot change bytes or start filters. Restore is byte-exact.
  - Every inherited `GIT_*` variable is removed.
  - *Cost if wrong:* none to the user's repo; at worst undo is off.
- **R4 — nested repositories and big files are excluded before every snapshot** (spec D12, plus the probe above).
  - Untracked entries ending in `/` are nested repositories. They go into the managed `$GIT_DIR/info/exclude` and out of the shadow index.
  - New untracked files over 50 MiB (`kMaxCheckpointFileBytes`) are excluded too, so a dataset or video does not double its size in `<support>`.
  - *Cost if wrong:* such a file cannot be undone; the panel says so (V2-1b copy).
- **R5 — restore deletes, in Dart, files that are absent from the checkpoint** and the directories the turn created that are now empty. Files present in the checkpoint come back with `git restore --source=<commit> --worktree --pathspec-from-file=- --pathspec-file-nul` (spec D12). *Cost if wrong:* an empty directory may stay.
- **R6 — remembered config never re-applies "Bypass permissions"** (spec D11 with Review Focus 6). A remembered `bypassPermissions` mode is skipped on new sessions; the user confirms it each time. *Cost if wrong:* one extra click.
- **R7 — V2-1 is split into two plans:** V2-1a (this plan, foundation) and V2-1b (the desktop tab).

## Global Constraints

- Branch `shellx-v2` only. Do **not** touch:
  - the relay;
  - `packages/shellx_core/lib/src/protocol/`;
  - the daemon (`daemon_main.dart`, `src/mux/*`);
  - `apps/mobile`;
  - V1 behaviour.

  This plan does not touch `apps/desktop` at all.
- Packages:
  - `packages/shellx_acp` and `packages/shellx_ai`: `resolution: workspace`, `environment: sdk: ^3.11.0`, listed in the root `pubspec.yaml` workspace.
  - No Flutter imports.
  - `package:shellx_ai/shellx_ai.dart` and `package:shellx_acp/shellx_acp.dart` must not import `dart:io`. Only `host.dart`, `testing.dart` and `bin/` may.
- ACP v1 only (spec D1).
  - `initialize` params are exactly `{protocolVersion: 1, clientCapabilities: {fs: {readTextFile: false, writeTextFile: false}, terminal: false, auth: {terminal: true}, elicitation: {form: {}, url: {}}}, clientInfo: {name: "shellx", title: "ShellX", version}}`.
  - Unknown update kinds and unknown `_meta` keys are ignored. No ACP v2.
- Framing (spec §6):
  - one JSON-RPC message per UTF-8 line;
  - lines up to 64 MiB are accepted;
  - non-JSON lines are ignored, and **more than 20 in a row** stop the agent;
  - a longer line stops the agent.
- Privacy (spec D20, §5):
  - Never log prompts, agent text, tool output, paths or file names. Only agent names, event kinds, counts and exit codes.
  - Agent stderr is kept in memory, last 256 KiB per session.
  - `toString()` of every ACP type, timeline item, session state, runtime and checkpoint type returns `'…'`, pinned by tests.
  - `JsonRpcError.toString()` shows only the code.
- Never auto-allow (spec §8.6, D10).
  - With no handler, a permission request answers `{outcome: cancelled}` and an elicitation answers `decline`.
  - Nothing picks an `allow_*` option for the user.
- Credentials (spec §5, D8, D21):
  - ShellX never reads, stores or relays credentials.
  - Terminal login runs the agent's own command plus the method's `args`/`env`; its output is never parsed.
  - Never pass `--hide-claude-auth`.
  - Never put `SHELLX_CLI_TOKEN`, `SHELLX_SOCKET` or any `SHELLX_*` variable into an agent's environment.
- Launching (spec D6):
  - Never through a shell. The environment comes from the login shell between `\x1e` markers (10 s, then fallback). `includeParentEnvironment: false`.
  - Pins:
    - `@agentclientprotocol/claude-agent-acp@0.90.0`, Node ≥ 22;
    - `@agentclientprotocol/codex-acp@2.2.2`, Node ≥ 20;
    - `@google/gemini-cli@0.64.0`, args `--acp`, Node ≥ 20;
    - `opencode` from PATH, args `acp`.
  - npm adapters install with `npm install --prefix <support>/ai/agents/<id> <pkg>@<pin>` and run with `node <bin>`.
  - Stop = close stdin, wait 2 s, then kill the process tree.
- Checkpoints (spec D12):
  - Repo layout: `GIT_DIR=<support>/ai/checkpoints/<first 12 hex of sha1(realpath)>` (path lower-cased on Windows), `GIT_WORK_TREE=<project>`.
  - Never run git against the project's own `.git`.
  - Thresholds: 200 000 files or 30 s for the first snapshot.
  - Retention: default 14 days.
  - macOS: run `xcode-select -p` before using `/usr/bin/git`.
  - Git ≥ 2.26 (for `restore --pathspec-from-file`).
  - Operations on one project run in series.
- Turns:
  - **Cancel:** sends `session/cancel` and answers pending permissions `cancelled` and pending questions `cancel`. "Force stop" becomes available after 10 s (spec §1.4).
  - **Queue:** at most 5 queued prompts (spec D16).
- Crash cleanup (spec §6): `<support>/ai/running.json` holds `{pid, command, startedAt}`. The next launch kills only processes whose command and start time match.
- Tests:
  - `package:test` only.
  - Host tests may spawn real processes (the fake agent via `Platform.resolvedExecutable`) and real git in temp dirs.
  - Nothing may touch the real `~/Library/Application Support` or any repo outside a temp dir.
  - No network.
- Code style:
  - English identifiers, comments and commit messages.
  - `final class`, doc comments on public API, matching `packages/shellx_core`.
  - Lints from the root `analysis_options.yaml`; `dart analyze` must be clean.
  - Commits: `feat(v2-ai): …` / `test(v2-ai): …`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

These are the inputs most likely to hurt a real user that the spec implies but does not test. Each has a pinning test in the owning task.

1. **A UTF-8 character split across two stdout chunks, or a chunk carrying a notification *and* the response that ends the turn.** The text must arrive whole. Every update must be applied before `prompt()` resolves, or the turn summary misses the last tool card. [`json_rpc_test` "split multibyte", "notification before response in one chunk" — Task 1; `acp_client_test` "updates before stopReason" — Task 3]
2. **Project files with spaces, Vietnamese names, or `* ? [ :` in the name.** Snapshot, diff, `fileAt` and restore must be exact. Pathspecs are literal, never globs. [`checkpoint_store_test` "odd names" — Task 8]
3. **A project `.gitattributes` (`* text=auto eol=crlf`, `filter=lfs`) or a hostile global git config** (`core.autocrlf=true`, `commit.gpgSign=true`, a failing `core.hooksPath`). Restore must give back the exact bytes; no GPG and no hook may run. [`checkpoint_store_test` "attributes" and "hostile global config" — Task 8]
4. **A login shell whose profile prints banners, exits non-zero, or hangs.** The environment still resolves (markers, then `-lc`, then the app's own env) within the timeout, and no agent is ever started through a shell. [`login_shell_env_test` "noisy profile" and "hanging shell" — Task 6]
5. **The user sends while the first snapshot of a big project is still running, or presses Stop while it runs.** The prompt waits for the checkpoint and is never sent unprotected. Stop ends the turn as cancelled without sending the prompt. [`ai_runtime_test` "send waits for the first snapshot" and "cancel while snapshotting" — Task 9]

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `pubspec.yaml` (root) | add `packages/shellx_acp`, `packages/shellx_ai` to the workspace |
| Modify `pubspec.lock` (root) | new dev deps (`json_schema`, `async`), host deps (`crypto`, `path`) |
| Modify `.github/workflows/windows-check.yml` | `dart test` steps for both packages (macOS + Windows) |
| Create `packages/shellx_acp/pubspec.yaml`, `lib/shellx_acp.dart` | package, public exports |
| Create `packages/shellx_acp/lib/src/json_rpc.dart` | `JsonRpcConnection`, `JsonRpcError`, `ConnectionClosed`, `ConnectionCloseReason`, `JsonMap` |
| Create `packages/shellx_acp/lib/src/acp_json.dart` | tolerant readers (`readString`, `readInt`, …), not exported |
| Create `packages/shellx_acp/lib/src/acp_content.dart` | `ContentBlock` family, `blockText` |
| Create `packages/shellx_acp/lib/src/acp_types.dart` | initialize/session/config/mode/permission/stop-reason/MCP types |
| Create `packages/shellx_acp/lib/src/acp_updates.dart` | tool-call types, `ToolCallFields.merge`, plan, commands, usage, `SessionUpdate` family |
| Create `packages/shellx_acp/lib/src/acp_elicitation.dart` | elicitation request/field/response types |
| Create `packages/shellx_acp/lib/src/acp_requests.dart` | request param builders (`initializeParams`, …) — schema-checked |
| Create `packages/shellx_acp/lib/src/acp_client.dart` | `AcpClient` |
| Create `packages/shellx_acp/lib/testing.dart`, `lib/src/testing/fake_agent.dart`, `lib/src/testing/fake_steps.dart` | `FakeAgent`, `FakeScenario`, `FakeSteps`, fake-agent process helpers |
| Create `packages/shellx_acp/bin/fake_agent.dart` | the fake agent as a process |
| Create `packages/shellx_acp/test/…` | `json_rpc_test`, `acp_types_test`, `conformance_test`, `acp_client_test`, `fake_agent_process_test`, `recorded_session_test`, `fixtures/acp-schema-1.25.0.json`, `fixtures/sessions/*.jsonl` |
| Create `packages/shellx_ai/pubspec.yaml`, `lib/shellx_ai.dart`, `lib/host.dart`, `lib/testing.dart` | package, model exports, host exports, test helpers |
| Create `packages/shellx_ai/lib/src/model/{timeline,session_state,notices,changes}.dart` | timeline reducer, session state, notices, `FileChange`/`Checkpoint`/`UndoOff` |
| Create `packages/shellx_ai/lib/src/host/{login_shell_env,probe,agent_catalog,agent_resolver}.dart` | environment, probes, catalog, readiness |
| Create `packages/shellx_ai/lib/src/host/{agent_process,byte_ring,running_agents}.dart` | process, stderr ring, crash registry |
| Create `packages/shellx_ai/lib/src/host/{git_runner,git_locator,checkpoint_store}.dart` | shadow-git checkpoints |
| Create `packages/shellx_ai/lib/src/host/{ai_runtime,ai_host}.dart` | one AI tab's orchestration; app-wide wiring |
| Create `packages/shellx_ai/lib/src/testing/fake_agent_channel.dart` | in-process `AgentChannel` over `FakeAgent` |
| Create `packages/shellx_ai/test/…` | one test file per unit above |
| Create `docs/superpowers/ledgers/v2-ai.md` | rulings, baseline, per-task results, Task-4 findings |

---

### Task 1: `shellx_acp` package and `JsonRpcConnection`

**Files:**
- Modify: `pubspec.yaml` (root workspace list)
- Modify: `.github/workflows/windows-check.yml` (job `dart`)
- Create: `packages/shellx_acp/pubspec.yaml`
- Create: `packages/shellx_acp/lib/shellx_acp.dart`
- Create: `packages/shellx_acp/lib/src/json_rpc.dart`
- Test: `packages/shellx_acp/test/json_rpc_test.dart`
- Create: `docs/superpowers/ledgers/v2-ai.md` (header + rulings R1–R7 + baseline, see "Prerequisite")

**Interfaces:**
- Consumes: nothing.
- Produces (exported from `package:shellx_acp/shellx_acp.dart`):
  - `typedef JsonMap = Map<String, Object?>`
  - `enum ConnectionCloseReason { ended, closed, lineTooLong, tooManyBadLines }`
  - `final class JsonRpcError implements Exception { const JsonRpcError(int code, String message, [Object? data]); static const parseError, invalidRequest, methodNotFound, invalidParams, internalError, authRequired (-32000), resourceNotFound (-32002); JsonMap toJson(); toString() => 'JsonRpcError(<code>)' }`
  - `final class ConnectionClosed implements Exception { const ConnectionClosed(ConnectionCloseReason reason); }`
  - `typedef RequestHandler = FutureOr<Object?> Function(JsonMap params)`, `typedef NotificationHandler = void Function(JsonMap params)`
  - `final class JsonRpcConnection { JsonRpcConnection({required Stream<List<int>> input, required StreamSink<List<int>> output, int maxLineChars = 64 * 1024 * 1024, int maxBadLines = 20}); Future<Object?> request(String method, [JsonMap? params]); void notify(String method, [JsonMap? params]); void onRequest(String method, RequestHandler h); void onNotification(String method, NotificationHandler h); Future<void> close(); Future<ConnectionCloseReason> get done; bool get isClosed; ConnectionCloseReason? get closeReason; }`

- [ ] **Step 1: Scaffold the package and add it to the workspace**

`packages/shellx_acp/pubspec.yaml`:

```yaml
name: shellx_acp
description: >-
  Agent Client Protocol (ACP v1) client for ShellX in pure Dart: JSON-RPC 2.0
  over newline-delimited stdio, the ACP types ShellX uses, and a scripted fake
  agent for tests.
version: 1.0.0
publish_to: none
resolution: workspace
environment:
  sdk: ^3.11.0
dev_dependencies:
  async: ^2.13.0
  test: ^1.30.0
```

Root `pubspec.yaml`: add `  - packages/shellx_acp` to `workspace:` after `packages/shellx_e2e`.

`packages/shellx_acp/lib/shellx_acp.dart`:

```dart
/// Agent Client Protocol (ACP v1) for ShellX: JSON-RPC over stdio, the
/// protocol types ShellX uses and the client (spec D1).
library;

export 'src/json_rpc.dart';
```

In `.github/workflows/windows-check.yml`, job `dart`, after the `shellx_agent` step, add:

```yaml
      - name: shellx_acp
        working-directory: packages/shellx_acp
        run: dart test
```

Resolve the workspace: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` (repo root). Expected: `Got dependencies!`.

- [ ] **Step 2: Write the failing tests**

`packages/shellx_acp/test/json_rpc_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

/// Two connected ends: what one writes, the other reads.
(JsonRpcConnection, JsonRpcConnection) pair() {
  final aToB = StreamController<List<int>>();
  final bToA = StreamController<List<int>>();
  return (
    JsonRpcConnection(input: bToA.stream, output: aToB.sink),
    JsonRpcConnection(input: aToB.stream, output: bToA.sink),
  );
}

/// One connection driven by raw bytes; its output decoded as JSON lines.
final class Raw {
  Raw({int maxLineChars = 1 << 20, int maxBadLines = 20}) {
    conn = JsonRpcConnection(
      input: toConn.stream,
      output: fromConn.sink,
      maxLineChars: maxLineChars,
      maxBadLines: maxBadLines,
    );
    out = StreamQueue(
      fromConn.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((l) => jsonDecode(l) as JsonMap),
    );
  }
  final toConn = StreamController<List<int>>();
  final fromConn = StreamController<List<int>>();
  late final JsonRpcConnection conn;
  late final StreamQueue<JsonMap> out;

  void send(String text) => toConn.add(utf8.encode(text));
  void line(Object json) => send('${jsonEncode(json)}\n');
}

void main() {
  group('request and response', () {
    test('round trip between two ends', () async {
      final (a, b) = pair();
      b.onRequest('echo', (p) => {'got': p['x']});
      expect(await a.request('echo', {'x': 1}), {'got': 1});
    });

    test('a notification reaches its handler with its params', () async {
      final (a, b) = pair();
      final got = Completer<JsonMap>();
      b.onNotification('n', got.complete);
      a.notify('n', {'k': 'v'});
      expect(await got.future, {'k': 'v'});
    });

    test('an unknown method answers -32601', () async {
      final (a, _) = pair();
      await expectLater(
        a.request('nope'),
        throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', -32601)),
      );
    });

    test('a handler error keeps its code; toString hides the message', () async {
      final (a, b) = pair();
      b.onRequest(
        'session/new',
        (_) => throw const JsonRpcError(-32000, 'Authentication required: secret'),
      );
      final e = await a.request('session/new').then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<JsonRpcError>().having((e) => e.code, 'code', JsonRpcError.authRequired));
      expect((e! as JsonRpcError).message, contains('Authentication required'));
      expect(e.toString(), 'JsonRpcError(-32000)');
    });

    test('a handler bug answers -32603 and is reported to the zone', () async {
      final reported = <Object>[];
      await runZonedGuarded(() async {
        final (a, b) = pair();
        b.onRequest('boom', (_) => throw StateError('bug'));
        await expectLater(
          a.request('boom'),
          throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', -32603)),
        );
      }, (e, _) => reported.add(e));
      expect(reported.single, isA<StateError>());
    });

    test('responses out of order reach the right callers', () async {
      final r = Raw();
      final first = r.conn.request('a');
      final second = r.conn.request('b');
      final m1 = await r.out.next;
      final m2 = await r.out.next;
      r.line({'jsonrpc': '2.0', 'id': m2['id'], 'result': 'B'});
      r.line({'jsonrpc': '2.0', 'id': m1['id'], 'result': 'A'});
      expect(await first, 'A');
      expect(await second, 'B');
    });

    test('a response with an unknown id is ignored', () async {
      final r = Raw();
      r.line({'jsonrpc': '2.0', 'id': 999, 'result': 1});
      final f = r.conn.request('x');
      final m = await r.out.next;
      r.line({'jsonrpc': '2.0', 'id': m['id'], 'result': 2});
      expect(await f, 2);
    });

    test('an error object without an int code becomes -32603', () async {
      final r = Raw();
      final f = r.conn.request('x');
      final m = await r.out.next;
      r.line({'jsonrpc': '2.0', 'id': m['id'], 'error': {'message': 'odd'}});
      await expectLater(f, throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', -32603)));
    });

    test('incoming requests echo string ids', () async {
      final r = Raw();
      r.conn.onRequest('ping', (_) => 'pong');
      r.line({'jsonrpc': '2.0', 'id': 'abc', 'method': 'ping'});
      expect(await r.out.next, {'jsonrpc': '2.0', 'id': 'abc', 'result': 'pong'});
    });
  });

  group('framing', () {
    test('a multibyte character split across chunks arrives whole', () async {
      final r = Raw();
      final got = Completer<JsonMap>();
      r.conn.onNotification('n', got.complete);
      final bytes = utf8.encode('${jsonEncode({'jsonrpc': '2.0', 'method': 'n', 'params': {'t': 'Tiếng Việt ✓'}})}\n');
      final cut = utf8.encode('{"jsonrpc":"2.0","method":"n","params":{"t":"Ti').length + 1;
      r.toConn.add(bytes.sublist(0, cut)); // ends inside "ế"
      r.toConn.add(bytes.sublist(cut));
      expect((await got.future)['t'], 'Tiếng Việt ✓');
    });

    test('CRLF endings and blank lines are accepted', () async {
      final r = Raw();
      final got = <String>[];
      r.conn.onNotification('n', (p) => got.add(p['v']! as String));
      r.send('\r\n\n{"jsonrpc":"2.0","method":"n","params":{"v":"1"}}\r\n');
      r.send('{"jsonrpc":"2.0","method":"n","params":{"v":"2"}}\n');
      await pumpEventQueue();
      expect(got, ['1', '2']);
    });

    test('a notification and a response in one chunk: notification first', () async {
      final r = Raw();
      final order = <String>[];
      r.conn.onNotification('session/update', (_) => order.add('update'));
      final f = r.conn.request('session/prompt').then((_) => order.add('response'));
      final m = await r.out.next;
      r.send(
        '${jsonEncode({'jsonrpc': '2.0', 'method': 'session/update', 'params': {}})}\n'
        '${jsonEncode({'jsonrpc': '2.0', 'id': m['id'], 'result': {'stopReason': 'end_turn'}})}\n',
      );
      await f;
      expect(order, ['update', 'response']);
    });

    test('every outgoing message is exactly one line', () async {
      final r = Raw();
      final lines = <String>[];
      final sub = r.fromConn.stream.listen((b) => lines.add(utf8.decode(b)));
      r.conn.notify('n', {'text': 'a\nb\r\nc'});
      await pumpEventQueue();
      await sub.cancel();
      expect(lines.single.indexOf('\n'), lines.single.length - 1);
    });

    test('a line of 10 MiB is accepted with the default limit', () async {
      final toConn = StreamController<List<int>>();
      final conn = JsonRpcConnection(input: toConn.stream, output: StreamController<List<int>>().sink);
      final got = Completer<int>();
      conn.onNotification('n', (p) => got.complete((p['t']! as String).length));
      final big = utf8.encode('${jsonEncode({'jsonrpc': '2.0', 'method': 'n', 'params': {'t': 'x' * (10 << 20)}})}\n');
      for (var i = 0; i < big.length; i += 65536) {
        toConn.add(big.sublist(i, i + 65536 > big.length ? big.length : i + 65536));
      }
      expect(await got.future, 10 << 20);
      expect(conn.isClosed, isFalse);
    });

    test('a line at the limit is fine; one char more stops the connection', () async {
      final ok = Raw(maxLineChars: 64);
      final line = jsonEncode({'jsonrpc': '2.0', 'method': 'n', 'params': {'t': ''}});
      final pad = 'x' * (64 - line.length);
      ok.send('${jsonEncode({'jsonrpc': '2.0', 'method': 'n', 'params': {'t': pad}})}\n');
      await pumpEventQueue();
      expect(ok.conn.isClosed, isFalse);

      final tooLong = Raw(maxLineChars: 64);
      final pending = tooLong.conn.request('x');
      tooLong.send('${'y' * 65}');
      expect(await tooLong.conn.done, ConnectionCloseReason.lineTooLong);
      await expectLater(pending, throwsA(isA<ConnectionClosed>()));
    });

    test('bad lines are skipped; more than maxBadLines in a row stop it', () async {
      final r = Raw(maxBadLines: 3);
      final got = <String>[];
      r.conn.onNotification('n', (p) => got.add(p['v']! as String));
      r.send('garbage\n[1,2]\n"str"\n'); // three bad lines: still open
      r.line({'jsonrpc': '2.0', 'method': 'n', 'params': {'v': 'ok'}}); // resets the count
      r.send('bad\nbad\nbad\n');
      await pumpEventQueue();
      expect(r.conn.isClosed, isFalse);
      expect(got, ['ok']);
      final pending = r.conn.request('x');
      r.send('bad\n'); // the fourth in a row
      expect(await r.conn.done, ConnectionCloseReason.tooManyBadLines);
      await expectLater(
        pending,
        throwsA(isA<ConnectionClosed>().having((e) => e.reason, 'reason', ConnectionCloseReason.tooManyBadLines)),
      );
    });

    test('a throwing notification handler does not drop later lines', () async {
      final got = <String>[];
      final reported = <Object>[];
      await runZonedGuarded(() async {
        final r = Raw();
        r.conn.onNotification('bad', (_) => throw StateError('bug'));
        r.conn.onNotification('good', (p) => got.add('good'));
        r.send(
          '${jsonEncode({'jsonrpc': '2.0', 'method': 'bad'})}\n'
          '${jsonEncode({'jsonrpc': '2.0', 'method': 'good'})}\n',
        );
        await pumpEventQueue();
      }, (e, _) => reported.add(e));
      expect(got, ['good']);
      expect(reported.single, isA<StateError>());
    });
  });

  group('lifecycle', () {
    test('input end: done is ended, pending and later requests fail', () async {
      final r = Raw();
      final pending = r.conn.request('x');
      await r.toConn.close();
      expect(await r.conn.done, ConnectionCloseReason.ended);
      await expectLater(pending, throwsA(isA<ConnectionClosed>()));
      await expectLater(r.conn.request('y'), throwsA(isA<ConnectionClosed>()));
      expect(r.conn.closeReason, ConnectionCloseReason.ended);
    });

    test('close() closes the output so the peer sees the end', () async {
      final (a, b) = pair();
      await a.close();
      expect(await a.done, ConnectionCloseReason.closed);
      expect(await b.done, ConnectionCloseReason.ended);
      a.notify('ignored'); // no throw after close
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test test/json_rpc_test.dart`
Expected: compile errors (`JsonRpcConnection` not defined).

- [ ] **Step 4: Implement `lib/src/json_rpc.dart`**

```dart
import 'dart:async';
import 'dart:convert';

/// A decoded JSON object.
typedef JsonMap = Map<String, Object?>;

/// Why a [JsonRpcConnection] stopped.
enum ConnectionCloseReason {
  /// The peer's output ended (the process exited or closed stdout).
  ended,

  /// [JsonRpcConnection.close] was called.
  closed,

  /// A line grew past `maxLineChars` (spec §6: 64 MiB).
  lineTooLong,

  /// More than `maxBadLines` lines in a row were not JSON-RPC (spec §6: 20).
  tooManyBadLines,
}

/// A JSON-RPC error: received in a response, or thrown by a handler to
/// answer a request with it.
///
/// [toString] shows only [code]: [message] and [data] come from the agent
/// and may quote the user's files or prompt (spec D20).
final class JsonRpcError implements Exception {
  const JsonRpcError(this.code, this.message, [this.data]);

  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  /// ACP: the agent needs the user to sign in first (spec D8).
  static const authRequired = -32000;

  /// ACP: for example `session/load` of a session the agent no longer has.
  static const resourceNotFound = -32002;

  final int code;
  final String message;
  final Object? data;

  JsonMap toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'JsonRpcError($code)';
}

/// A request could not complete: the connection is closed.
final class ConnectionClosed implements Exception {
  const ConnectionClosed(this.reason);

  final ConnectionCloseReason reason;

  @override
  String toString() => 'ConnectionClosed(${reason.name})';
}

/// Answers one incoming request; throw [JsonRpcError] to answer an error.
typedef RequestHandler = FutureOr<Object?> Function(JsonMap params);

/// Receives one incoming notification.
typedef NotificationHandler = void Function(JsonMap params);

/// JSON-RPC 2.0 over newline-delimited UTF-8 (ACP's stdio transport).
///
/// Symmetric: either end may send requests and notifications. Lines that
/// are not JSON-RPC are skipped; more than [maxBadLines] in a row, or one
/// line longer than [maxLineChars], close the connection (spec §6).
/// Incoming messages are handled in order, synchronously as their line
/// completes, so a notification always reaches its handler before a later
/// response completes its request.
final class JsonRpcConnection {
  JsonRpcConnection({
    required Stream<List<int>> input,
    required StreamSink<List<int>> output,
    this.maxLineChars = 64 * 1024 * 1024,
    this.maxBadLines = 20,
  }) : _output = output {
    _sub = input
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          _onChunk,
          onError: (Object _) => _shutdown(ConnectionCloseReason.ended),
          onDone: () => _shutdown(ConnectionCloseReason.ended),
        );
    // A write to a process that exited fails on `done`; the input side
    // reports the end, so the error itself is dropped.
    output.done.then<void>((_) {}, onError: (Object _) {});
  }

  /// Longest accepted line, in UTF-16 code units (≈ bytes for JSON).
  final int maxLineChars;

  /// Bad lines tolerated in a row; one more closes the connection.
  final int maxBadLines;

  final StreamSink<List<int>> _output;
  late final StreamSubscription<String> _sub;
  final _requestHandlers = <String, RequestHandler>{};
  final _notificationHandlers = <String, NotificationHandler>{};
  final _pending = <int, Completer<Object?>>{};
  final _done = Completer<ConnectionCloseReason>();
  final _line = StringBuffer();
  var _lineLength = 0;
  var _badLines = 0;
  var _nextId = 0;
  ConnectionCloseReason? _reason;

  /// Completes once, with the reason, when the connection stops.
  Future<ConnectionCloseReason> get done => _done.future;

  bool get isClosed => _reason != null;

  ConnectionCloseReason? get closeReason => _reason;

  void onRequest(String method, RequestHandler handler) =>
      _requestHandlers[method] = handler;

  void onNotification(String method, NotificationHandler handler) =>
      _notificationHandlers[method] = handler;

  /// Sends a request; completes with its `result`, or fails with
  /// [JsonRpcError] or [ConnectionClosed].
  Future<Object?> request(String method, [JsonMap? params]) {
    final reason = _reason;
    if (reason != null) return Future.error(ConnectionClosed(reason));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    return completer.future;
  }

  /// Sends a notification; does nothing once closed.
  void notify(String method, [JsonMap? params]) {
    if (_reason != null) return;
    _send({
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    });
  }

  /// Stops reading, fails pending requests and closes the output (for an
  /// agent process: closes its stdin).
  Future<void> close() async {
    _shutdown(ConnectionCloseReason.closed);
    await _done.future;
  }

  void _onChunk(String chunk) {
    var start = 0;
    while (_reason == null) {
      final nl = chunk.indexOf('\n', start);
      final end = nl < 0 ? chunk.length : nl;
      _lineLength += end - start;
      if (_lineLength > maxLineChars) {
        _shutdown(ConnectionCloseReason.lineTooLong);
        return;
      }
      if (start == 0 && end == chunk.length) {
        _line.write(chunk);
      } else {
        _line.write(chunk.substring(start, end));
      }
      if (nl < 0) return;
      final line = _line.toString();
      _line.clear();
      _lineLength = 0;
      _handleLine(line);
      start = nl + 1;
    }
  }

  void _handleLine(String raw) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.trim().isEmpty) return;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      _badLine();
      return;
    }
    if (message is! JsonMap) {
      _badLine();
      return;
    }
    final method = message['method'];
    if (method is String) {
      _badLines = 0;
      final params = message['params'];
      final p = params is JsonMap ? params : <String, Object?>{};
      if (message.containsKey('id')) {
        unawaited(_answer(message['id'], method, p));
      } else {
        final handler = _notificationHandlers[method];
        if (handler != null) {
          try {
            handler(p);
          } catch (e, s) {
            Zone.current.handleUncaughtError(e, s);
          }
        }
      }
      return;
    }
    if (message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'))) {
      _badLines = 0;
      _complete(message);
      return;
    }
    _badLine();
  }

  void _badLine() {
    if (++_badLines > maxBadLines) {
      _shutdown(ConnectionCloseReason.tooManyBadLines);
    }
  }

  Future<void> _answer(Object? id, String method, JsonMap params) async {
    final handler = _requestHandlers[method];
    if (handler == null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': const JsonRpcError(
          JsonRpcError.methodNotFound,
          'Method not found',
        ).toJson(),
      });
      return;
    }
    try {
      final result = await handler(params);
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on JsonRpcError catch (e) {
      _send({'jsonrpc': '2.0', 'id': id, 'error': e.toJson()});
    } catch (e, s) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': const JsonRpcError(
          JsonRpcError.internalError,
          'Internal error',
        ).toJson(),
      });
      Zone.current.handleUncaughtError(e, s);
    }
  }

  void _complete(JsonMap message) {
    final id = message['id'];
    final completer = id is int ? _pending.remove(id) : null;
    if (completer == null) return;
    if (message.containsKey('error')) {
      final error = message['error'];
      final code = error is JsonMap ? error['code'] : null;
      final text = error is JsonMap ? error['message'] : null;
      completer.completeError(
        JsonRpcError(
          code is int ? code : JsonRpcError.internalError,
          text is String ? text : '',
          error is JsonMap ? error['data'] : null,
        ),
      );
    } else {
      completer.complete(message['result']);
    }
  }

  void _send(JsonMap message) {
    if (_reason != null) return;
    final bytes = utf8.encode('${jsonEncode(message)}\n');
    try {
      _output.add(bytes);
    } on Object {
      // The pipe is gone; the input side reports the end.
    }
  }

  void _shutdown(ConnectionCloseReason reason) {
    if (_reason != null) return;
    _reason = reason;
    unawaited(_sub.cancel());
    final pending = [..._pending.values];
    _pending.clear();
    for (final c in pending) {
      c.completeError(ConnectionClosed(reason));
    }
    try {
      unawaited(_output.close().then<void>((_) {}, onError: (Object _) {}));
    } on Object {
      // Already closed.
    }
    _done.complete(reason);
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test test/json_rpc_test.dart && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: all tests pass; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock .github/workflows/windows-check.yml packages/shellx_acp docs/superpowers/ledgers/v2-ai.md
git commit -m "feat(v2-ai): shellx_acp package with line-framed JSON-RPC connection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 2: ACP types, request builders and schema conformance

**Files:**
- Create: `packages/shellx_acp/lib/src/acp_json.dart` (not exported, except `Redacted`)
- Create: `packages/shellx_acp/lib/src/acp_content.dart`
- Create: `packages/shellx_acp/lib/src/acp_types.dart`
- Create: `packages/shellx_acp/lib/src/acp_updates.dart`
- Create: `packages/shellx_acp/lib/src/acp_elicitation.dart`
- Create: `packages/shellx_acp/lib/src/acp_requests.dart`
- Modify: `packages/shellx_acp/lib/shellx_acp.dart` (exports)
- Modify: `packages/shellx_acp/pubspec.yaml` (dev dep `json_schema: ^5.2.2`)
- Create: `packages/shellx_acp/test/fixtures/acp-schema-1.25.0.json` (the controller copies it from the spec research download, `<scratchpad>/acp-schema/schema.json`, 255 170 bytes) and `test/fixtures/README.md`
- Test: `packages/shellx_acp/test/acp_types_test.dart`, `packages/shellx_acp/test/conformance_test.dart`

**Interfaces:**
- Consumes: `JsonMap` (Task 1).
- Produces (all exported from `package:shellx_acp/shellx_acp.dart`; every class mixes in `Redacted`, so `toString()` is `'…'`):
  - `mixin Redacted`
  - content:
    - `sealed class ContentBlock { static ContentBlock fromJson(JsonMap); JsonMap toJson(); }`
    - `TextBlock(text)`
    - `ImageBlock({data, mimeType, uri})`
    - `ResourceLinkBlock({uri, name, title, mimeType, size, description})`
    - `ResourceBlock({uri, text, mimeType})`
    - `OtherBlock(type)`
    - `String blockText(Iterable<ContentBlock>)`
  - agent and session:
    - `Implementation({name, version, title})`
    - `PromptCapabilities({image, audio, embeddedContext})`
    - `AgentCapabilities({loadSession, prompt, listSessions, resumeSession, closeSession})`
    - `sealed AuthMethod {id, name, description}` with `AuthMethodAgent`, `AuthMethodTerminal {args, env}` and `AuthMethodOther {type}`
    - `InitializeResult({protocolVersion, capabilities, authMethods, agentInfo})`
    - `NewSessionResult({sessionId, configOptions, modes})`
    - `LoadSessionResult({configOptions, modes})`
    - `SessionSummary({sessionId, cwd, title, updatedAt})`
    - `ListSessionsResult({sessions, nextCursor})`
    - `StopReason { endTurn, maxTokens, maxTurnRequests, refusal, cancelled, other; String wire; static parse }`
    - `McpServerStdio({name, command, args, env})`
  - config and modes:
    - `enum ConfigKind { select, boolean, other }`
    - `ConfigChoice({value, name, description, group})`
    - `ConfigOption({id, name, kind, description, category, currentValue, choices}) + withValue(Object?)`
    - `List<ConfigOption> readConfigOptions(JsonMap, String key)`
    - `SessionMode({id, name, description})`
    - `SessionModes({currentModeId, available}) + withCurrent(String)`
  - permissions:
    - `PermissionKind { allowOnce, allowAlways, rejectOnce, rejectAlways, other; wire; isReject; parse }`
    - `PermissionOption({optionId, name, kind})`
    - `PermissionRequest({sessionId, toolCallId, toolCall, options})`
    - `sealed PermissionOutcome { JsonMap toJson(); }` with `PermissionSelected(optionId)` and `PermissionCancelled()`
  - tool calls:
    - `ToolKind { read, edit, delete, move, search, execute, think, fetch, switchMode, other; wire; parse }`
    - `ToolCallStatus { pending, inProgress, completed, failed; wire; parse }`
    - `sealed ToolContent` with `ToolContentBlock(block)`, `ToolDiff({path, oldText, newText})`, `ToolTerminal(terminalId)` and `ToolContentOther(type)`
    - `ToolLocation(path, [line])`
    - `ToolCallFields({title, name, kind, status, content, locations, rawInput, rawOutput}) + merge(ToolCallFields)`
  - session updates:
    - `PlanStatus { pending, inProgress, completed }`
    - `PlanEntry({content, status, priority})`
    - `AvailableCommand({name, description, hint})`
    - `Usage({used, size, costAmount, costCurrency}) + percent`
    - `sealed SessionUpdate { static SessionUpdate fromJson(JsonMap) }` with:
      - `UserMessageChunk(content, {messageId})`, `AgentMessageChunk(…)`, `AgentThoughtChunk(…)`
      - `ToolCallStarted(toolCallId, fields)`, `ToolCallUpdated(toolCallId, fields)`
      - `PlanUpdated(entries)`, `CommandsUpdated(commands)`, `ModeUpdated(currentModeId)`, `ConfigUpdated(options)`
      - `SessionInfoUpdated({hasTitle, title, updatedAt})`, `UsageUpdated(usage)`
      - `UnknownUpdate(kind)`
  - elicitation:
    - `sealed ElicitationRequest {message, sessionId, toolCallId, requestId; static fromJson}` with:
      - `ElicitationForm({title, description, fields}) + supported + accepts(Map)`
      - `ElicitationUrl({elicitationId, url}) + isWebUrl`
      - `ElicitationOther({mode})`
    - `ElicitOption(value, title)`
    - `sealed ElicitField {key, required, title, description; bool accepts(Object)}` with `ElicitTextField`, `ElicitNumberField({integer})`, `ElicitBoolField`, `ElicitChoiceField`, `ElicitMultiChoiceField` and `ElicitUnsupportedField`
    - `sealed ElicitationResponse { JsonMap toJson(); }` with `ElicitAccept([Map<String,Object>? content])`, `ElicitDecline()` and `ElicitCancel()`
  - request builders (all return `JsonMap`):
    - `initializeParams({clientVersion})`
    - `authenticateParams(methodId)`
    - `newSessionParams({cwd, mcpServers})`
    - `loadSessionParams({sessionId, cwd, mcpServers})`
    - `listSessionsParams({cwd, cursor})`
    - `promptParams(sessionId, prompt)`
    - `cancelParams(sessionId)`
    - `setConfigOptionParams(sessionId, configId, Object value)`
    - `setModeParams(sessionId, modeId)`

- [ ] **Step 1: Place the schema fixture and add the dev dependency**

Copy the schema to `packages/shellx_acp/test/fixtures/acp-schema-1.25.0.json` unchanged. Then write `test/fixtures/README.md`:

```markdown
# ACP schema fixture

`acp-schema-1.25.0.json` is `schema/v1/schema.json` of
https://github.com/agentclientprotocol/agent-client-protocol at release
schema-v1.25.0 (2026-10-09), unchanged. The conformance test checks what
ShellX sends, and the samples it parses, against it (spec D1, §7). Bump it
only together with the adapter pins (spec D6).
```

Add `json_schema: ^5.2.2` to `dev_dependencies` in `packages/shellx_acp/pubspec.yaml` and run `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the repo root. Expected: `Got dependencies!`.

If the workspace cannot resolve `json_schema` 5.x, take the newest 5.x that resolves and note it in the ledger. If no 5.x resolves, use 4.x; `draft2020_12` is supported from 4.0. Keep the test unchanged.

- [ ] **Step 2: Write the failing tests**

`packages/shellx_acp/test/acp_types_test.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

void main() {
  group('tolerant parsing', () {
    test('wrong types read as absent, never throw', () {
      final r = InitializeResult.fromJson({
        'protocolVersion': '1',
        'agentCapabilities': 'yes',
        'authMethods': [1, null, {'id': 'x'}, {'id': 'a', 'name': 'A'}],
      });
      expect(r.protocolVersion, 0);
      expect(r.capabilities.loadSession, isFalse);
      expect(r.authMethods.single, isA<AuthMethodAgent>().having((m) => m.id, 'id', 'a'));
    });

    test('an update without its id or content is UnknownUpdate', () {
      expect(SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'title': 'x'}), isA<UnknownUpdate>());
      expect(SessionUpdate.fromJson({'sessionUpdate': 'agent_message_chunk'}), isA<UnknownUpdate>());
      expect(SessionUpdate.fromJson({'sessionUpdate': 'usage_update', 'used': 1}), isA<UnknownUpdate>());
      expect(SessionUpdate.fromJson({}), isA<UnknownUpdate>().having((u) => u.kind, 'kind', isNull));
      expect(
        SessionUpdate.fromJson({'sessionUpdate': 'notice', 'severity': 'info', 'title': 't'}),
        isA<UnknownUpdate>().having((u) => u.kind, 'kind', 'notice'),
      );
    });

    test('unknown enum values', () {
      expect(StopReason.parse('end_turn'), StopReason.endTurn);
      expect(StopReason.parse('paused_for_lunch'), StopReason.other);
      expect(StopReason.parse(null), StopReason.other);
      expect(ToolKind.parse('switch_mode'), ToolKind.switchMode);
      expect(ToolKind.parse('teleport'), ToolKind.other);
      expect(ToolKind.parse(null), isNull);
      expect(ToolCallStatus.parse('in_progress'), ToolCallStatus.inProgress);
      expect(ToolCallStatus.parse('weird'), isNull);
      expect(PermissionKind.parse('reject_always'), PermissionKind.rejectAlways);
      expect(PermissionKind.parse('maybe'), PermissionKind.other);
      expect(PermissionKind.rejectOnce.isReject, isTrue);
      expect(PermissionKind.allowAlways.isReject, isFalse);
    });

    test('an auth method of an unknown type is kept as AuthMethodOther', () {
      final m = AuthMethod.fromJson({'id': 'e', 'name': 'Env', 'type': 'env_var'});
      expect(m, isA<AuthMethodOther>().having((m) => m.type, 'type', 'env_var'));
    });

    test('terminal auth keeps args and string env values only', () {
      final m = AuthMethod.fromJson({
        'id': 'claude-ai-login',
        'name': 'Claude Subscription',
        'type': 'terminal',
        'args': ['--cli', 'auth', 'login', '--claudeai', 7],
        'env': {'A': '1', 'B': 2},
      })! as AuthMethodTerminal;
      expect(m.args, ['--cli', 'auth', 'login', '--claudeai']);
      expect(m.env, {'A': '1'});
    });
  });

  group('tool calls', () {
    test('merge: sent fields replace, absent fields stay', () {
      final start = ToolCallFields.fromJson({
        'title': 'Edit a.txt',
        'kind': 'edit',
        'status': 'pending',
        'content': [
          {'type': 'diff', 'path': '/p/a.txt', 'oldText': 'a', 'newText': 'b'},
        ],
        'locations': [{'path': '/p/a.txt', 'line': 3}],
      });
      final merged = start.merge(ToolCallFields.fromJson({'status': 'completed', 'content': []}));
      expect(merged.title, 'Edit a.txt');
      expect(merged.kind, ToolKind.edit);
      expect(merged.status, ToolCallStatus.completed);
      expect(merged.content, isEmpty);
      expect(merged.locations!.single.line, 3);
    });

    test('diff without oldText is a new file', () {
      final d = ToolContent.fromJson({'type': 'diff', 'path': 'n.txt', 'newText': 'x'}) as ToolDiff;
      expect(d.oldText, isNull);
      expect(ToolContent.fromJson({'type': 'terminal', 'terminalId': 't'}), isA<ToolTerminal>());
      expect(ToolContent.fromJson({'type': 'hologram'}), isA<ToolContentOther>());
    });
  });

  group('config options', () {
    test('groups are flattened and keep their group name', () {
      final o = ConfigOption.fromJson({
        'id': 'model',
        'name': 'Model',
        'category': 'model',
        'type': 'select',
        'currentValue': 'opus',
        'options': [
          {'group': 'g1', 'name': 'Anthropic', 'options': [
            {'value': 'opus', 'name': 'Opus'},
            {'value': 'sonnet', 'name': 'Sonnet'},
          ]},
          {'group': 'g2', 'name': 'Other', 'options': [{'value': 'x', 'name': 'X'}]},
        ],
      })!;
      expect(o.kind, ConfigKind.select);
      expect(o.choices.map((c) => '${c.group}/${c.value}'), ['Anthropic/opus', 'Anthropic/sonnet', 'Other/x']);
      expect(o.currentValue, 'opus');
      expect(o.withValue('sonnet').currentValue, 'sonnet');
    });

    test('boolean options read a bool value', () {
      final o = ConfigOption.fromJson({'id': 'fast', 'name': 'Fast', 'type': 'boolean', 'currentValue': true})!;
      expect(o.kind, ConfigKind.boolean);
      expect(o.currentValue, true);
    });

    test('an option without id or name is dropped', () {
      expect(readConfigOptions({'c': [{'name': 'x'}, {'id': 'y', 'name': 'Y', 'type': 'select', 'currentValue': 'a', 'options': []}]}, 'c').single.id, 'y');
    });
  });

  group('elicitation', () {
    final form = ElicitationRequest.fromJson({
      'sessionId': 's',
      'mode': 'form',
      'message': 'Pick',
      'requestedSchema': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'minLength': 1, 'maxLength': 5},
          'color': {'type': 'string', 'oneOf': [{'const': 'r', 'title': 'Red'}, {'const': 'g', 'title': 'Green'}]},
          'size': {'type': 'string', 'enum': ['s', 'm']},
          'count': {'type': 'integer', 'minimum': 1, 'maximum': 3},
          'ratio': {'type': 'number'},
          'ok': {'type': 'boolean', 'default': true},
          'tags': {'type': 'array', 'minItems': 1, 'items': {'type': 'string', 'enum': ['a', 'b']}},
          'labels': {'type': 'array', 'items': {'anyOf': [{'const': 'x', 'title': 'X'}]}},
        },
        'required': ['name', 'tags'],
      },
    }) as ElicitationForm;

    test('fields by type', () {
      expect(form.fields.map((f) => f.runtimeType.toString()), [
        'ElicitTextField',
        'ElicitChoiceField',
        'ElicitChoiceField',
        'ElicitNumberField',
        'ElicitNumberField',
        'ElicitBoolField',
        'ElicitMultiChoiceField',
        'ElicitMultiChoiceField',
      ]);
      expect((form.fields[1] as ElicitChoiceField).options.map((o) => o.title), ['Red', 'Green']);
      expect((form.fields[3] as ElicitNumberField).integer, isTrue);
      expect(form.supported, isTrue);
    });

    test('accepts checks required fields, bounds and unknown keys', () {
      expect(form.accepts({'name': 'abc', 'tags': ['a']}), isTrue);
      expect(form.accepts({'name': 'abc'}), isFalse, reason: 'tags is required');
      expect(form.accepts({'name': '', 'tags': ['a']}), isFalse, reason: 'minLength');
      expect(form.accepts({'name': 'abcdef', 'tags': ['a']}), isFalse, reason: 'maxLength');
      expect(form.accepts({'name': 'a', 'tags': ['c']}), isFalse, reason: 'not an option');
      expect(form.accepts({'name': 'a', 'tags': ['a', 'a']}), isFalse, reason: 'duplicates');
      expect(form.accepts({'name': 'a', 'tags': ['a'], 'count': 4}), isFalse, reason: 'maximum');
      expect(form.accepts({'name': 'a', 'tags': ['a'], 'count': 2.5}), isFalse, reason: 'integer');
      expect(form.accepts({'name': 'a', 'tags': ['a'], 'ratio': 2.5, 'color': 'g'}), isTrue);
      expect(form.accepts({'name': 'a', 'tags': ['a'], 'extra': 1}), isFalse, reason: 'unknown key');
    });

    test('an unknown field type makes the form unsupported (spec D22)', () {
      final f = ElicitationRequest.fromJson({
        'mode': 'form',
        'message': 'm',
        'requestedSchema': {'type': 'object', 'properties': {'file': {'type': 'blob'}}},
      }) as ElicitationForm;
      expect(f.supported, isFalse);
    });

    test('url mode: only http(s) with a host may be opened', () {
      ElicitationUrl url(String u) => ElicitationRequest.fromJson({'mode': 'url', 'message': 'm', 'elicitationId': 'e', 'url': u}) as ElicitationUrl;
      expect(url('https://example.com/a').isWebUrl, isTrue);
      expect(url('http://localhost:8080').isWebUrl, isTrue);
      expect(url('javascript:alert(1)').isWebUrl, isFalse);
      expect(url('file:///etc/passwd').isWebUrl, isFalse);
      expect(url('https://').isWebUrl, isFalse);
      expect(ElicitationRequest.fromJson({'mode': 'url', 'message': 'm'}), isA<ElicitationOther>());
      expect(ElicitationRequest.fromJson({'mode': 'telepathy', 'message': 'm'}), isA<ElicitationOther>());
    });

    test('responses', () {
      expect(const ElicitAccept({'a': 1}).toJson(), {'action': 'accept', 'content': {'a': 1}});
      expect(const ElicitAccept().toJson(), {'action': 'accept'});
      expect(const ElicitDecline().toJson(), {'action': 'decline'});
      expect(const ElicitCancel().toJson(), {'action': 'cancel'});
    });
  });

  test('blockText joins text and names resource links', () {
    expect(
      blockText(const [TextBlock('Fix '), ResourceLinkBlock(uri: 'file:///p/a.dart', name: 'a.dart'), ImageBlock(data: '', mimeType: 'image/png')]),
      'Fix @a.dart',
    );
  });

  test('permission outcomes', () {
    expect(const PermissionSelected('allow-once').toJson(), {'outcome': {'outcome': 'selected', 'optionId': 'allow-once'}});
    expect(const PermissionCancelled().toJson(), {'outcome': {'outcome': 'cancelled'}});
  });

  test('setConfigOptionParams rejects values that are neither String nor bool', () {
    expect(() => setConfigOptionParams('s', 'c', 3), throwsArgumentError);
  });

  test('toString never shows content (spec D20)', () {
    final values = <Object>[
      const TextBlock('secret'),
      const ToolCallFields(title: 'cat secret.txt'),
      SessionUpdate.fromJson({'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'secret'}}),
      PermissionRequest.fromJson({'sessionId': 's', 'toolCall': {'toolCallId': 't', 'title': 'secret'}, 'options': []}),
      ElicitationRequest.fromJson({'mode': 'form', 'message': 'secret', 'requestedSchema': {}}),
      const ElicitAccept({'k': 'secret'}),
      const Implementation(name: 'n', version: '1'),
      const McpServerStdio(name: 'n', command: '/secret'),
    ];
    for (final v in values) {
      expect(v.toString(), '…', reason: v.runtimeType.toString());
    }
  });
}
```

`packages/shellx_acp/test/conformance_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

final _root =
    jsonDecode(File('test/fixtures/acp-schema-1.25.0.json').readAsStringSync())
        as Map<String, Object?>;
final _schemas = <String, JsonSchema>{};

/// One `$defs` entry of the ACP schema as a schema of its own.
JsonSchema def(String name) => _schemas.putIfAbsent(
  name,
  () => JsonSchema.create({
    for (final e in _root.entries)
      if (e.key != 'anyOf' && e.key != 'title') e.key: e.value,
    r'$ref': '#/\$defs/$name',
  }),
);

void valid(String name, Object? json) {
  final r = def(name).validate(json);
  expect(r.isValid, isTrue, reason: '$name: ${r.errors.take(3).join(' | ')}');
}

/// A sample an agent could send: valid against [name], then parsed.
T sample<T>(String name, JsonMap json, T Function(JsonMap) parse) {
  valid(name, json);
  return parse(json);
}

void main() {
  test('the fixture is ACP schema v1 (draft 2020-12)', () {
    expect(_root[r'$schema'], contains('2020-12'));
    expect((_root[r'$defs']! as Map).containsKey('InitializeRequest'), isTrue);
  });

  group('what ShellX sends is valid ACP', () {
    test('initialize (spec D1)', () {
      final p = initializeParams(clientVersion: '2.0.0');
      valid('InitializeRequest', p);
      expect(p, {
        'protocolVersion': 1,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
          'auth': {'terminal': true},
          'elicitation': {'form': {}, 'url': {}},
        },
        'clientInfo': {'name': 'shellx', 'title': 'ShellX', 'version': '2.0.0'},
      });
    });

    test('session requests', () {
      valid('AuthenticateRequest', authenticateParams('console-login'));
      valid('NewSessionRequest', newSessionParams(cwd: '/p'));
      valid(
        'NewSessionRequest',
        newSessionParams(cwd: '/p', mcpServers: const [McpServerStdio(name: 'fs', command: '/bin/fs', args: ['-v'], env: {'K': 'V'})]),
      );
      valid('LoadSessionRequest', loadSessionParams(sessionId: 's', cwd: '/p'));
      valid('ListSessionsRequest', listSessionsParams());
      valid('ListSessionsRequest', listSessionsParams(cwd: '/p', cursor: 'c'));
      valid('CancelNotification', cancelParams('s'));
      valid('SetSessionModeRequest', setModeParams('s', 'plan'));
      valid('SetSessionConfigOptionRequest', setConfigOptionParams('s', 'model', 'opus'));
      valid('SetSessionConfigOptionRequest', setConfigOptionParams('s', 'fast', true));
      expect(setConfigOptionParams('s', 'fast', true)['type'], 'boolean');
    });

    test('prompt with text, image and a resource link', () {
      valid(
        'PromptRequest',
        promptParams('s', const [
          TextBlock('Fix the bug in '),
          ResourceLinkBlock(uri: 'file:///p/lib/a.dart', name: 'a.dart', mimeType: 'text/x-dart'),
          ImageBlock(data: 'iVBORw0KGgo=', mimeType: 'image/png'),
        ]),
      );
    });

    test('answers to the agent', () {
      valid('RequestPermissionResponse', const PermissionSelected('allow-once').toJson());
      valid('RequestPermissionResponse', const PermissionCancelled().toJson());
      valid('CreateElicitationResponse', const ElicitAccept({'name': 'a', 'n': 2, 'ok': true, 'tags': ['x']}).toJson());
      valid('CreateElicitationResponse', const ElicitAccept().toJson());
      valid('CreateElicitationResponse', const ElicitDecline().toJson());
      valid('CreateElicitationResponse', const ElicitCancel().toJson());
    });
  });

  group('what agents send parses', () {
    test('initialize result (Claude adapter 0.90.0 shape)', () {
      final r = sample('InitializeResponse', {
        'protocolVersion': 1,
        'agentCapabilities': {
          'loadSession': true,
          'promptCapabilities': {'image': true, 'embeddedContext': true},
          'mcpCapabilities': {'http': true, 'sse': true},
          'sessionCapabilities': {'list': {}, 'close': {}, 'resume': {}},
        },
        'authMethods': [
          {'id': 'claude-ai-login', 'name': 'Claude Subscription', 'type': 'terminal', 'args': ['--cli', 'auth', 'login', '--claudeai']},
          {'id': 'console-login', 'name': 'Anthropic Console', 'type': 'terminal', 'args': ['--cli', 'auth', 'login', '--console']},
        ],
        'agentInfo': {'name': '@agentclientprotocol/claude-agent-acp', 'title': 'Claude Agent', 'version': '0.90.0'},
      }, InitializeResult.fromJson);
      expect(r.protocolVersion, 1);
      expect(r.capabilities.loadSession, isTrue);
      expect(r.capabilities.prompt.image, isTrue);
      expect(r.capabilities.listSessions, isTrue);
      expect(r.authMethods.map((m) => m.id), ['claude-ai-login', 'console-login']);
      expect((r.authMethods.first as AuthMethodTerminal).args.last, '--claudeai');
      expect(r.agentInfo!.title, 'Claude Agent');
    });

    test('new session with config options and modes', () {
      final r = sample('NewSessionResponse', {
        'sessionId': 'sess-1',
        'modes': {
          'currentModeId': 'default',
          'availableModes': [
            {'id': 'default', 'name': 'Manual'},
            {'id': 'plan', 'name': 'Plan'},
          ],
        },
        'configOptions': [
          {'id': 'mode', 'name': 'Mode', 'category': 'mode', 'type': 'select', 'currentValue': 'default', 'options': [
            {'value': 'default', 'name': 'Manual'},
            {'value': 'acceptEdits', 'name': 'Accept edits'},
          ]},
          {'id': 'model', 'name': 'Model', 'category': 'model', 'type': 'select', 'currentValue': 'opus', 'options': [
            {'group': 'a', 'name': 'Anthropic', 'options': [{'value': 'opus', 'name': 'Opus'}]},
          ]},
          {'id': 'fast', 'name': 'Fast', 'type': 'boolean', 'currentValue': false},
        ],
      }, NewSessionResult.fromJson);
      expect(r.sessionId, 'sess-1');
      expect(r.modes!.available.map((m) => m.id), ['default', 'plan']);
      expect(r.configOptions!.map((o) => o.kind), [ConfigKind.select, ConfigKind.select, ConfigKind.boolean]);
    });

    JsonMap note(JsonMap update) => {'sessionId': 's', 'update': update};
    SessionUpdate update(JsonMap u) =>
        sample('SessionNotification', note(u), (n) => SessionUpdate.fromJson(n['update']! as JsonMap));

    test('every update kind ShellX draws', () {
      expect(
        update({'sessionUpdate': 'user_message_chunk', 'content': {'type': 'text', 'text': 'hi'}}),
        isA<UserMessageChunk>().having((u) => (u.content as TextBlock).text, 'text', 'hi'),
      );
      expect(
        update({'sessionUpdate': 'agent_message_chunk', 'messageId': 'm1', 'content': {'type': 'text', 'text': 'Hello'}}),
        isA<AgentMessageChunk>().having((u) => u.messageId, 'messageId', 'm1'),
      );
      expect(update({'sessionUpdate': 'agent_thought_chunk', 'content': {'type': 'text', 'text': '…'}}), isA<AgentThoughtChunk>());
      final call = update({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'toolu_1',
        'title': 'Edit src/cart.js',
        'kind': 'edit',
        'status': 'pending',
        'content': [{'type': 'diff', 'path': '/p/src/cart.js', 'oldText': 'a', 'newText': 'b'}],
        'locations': [{'path': '/p/src/cart.js', 'line': 12}],
        'rawInput': {'file_path': '/p/src/cart.js'},
      }) as ToolCallStarted;
      expect(call.toolCallId, 'toolu_1');
      expect(call.fields.kind, ToolKind.edit);
      expect((call.fields.content!.single as ToolDiff).newText, 'b');
      final done = update({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'toolu_1',
        'status': 'completed',
        'content': [{'type': 'content', 'content': {'type': 'text', 'text': 'ok'}}],
      }) as ToolCallUpdated;
      expect(done.fields.status, ToolCallStatus.completed);
      expect(done.fields.title, isNull);
      expect(
        update({'sessionUpdate': 'plan', 'entries': [{'content': 'Read', 'priority': 'high', 'status': 'in_progress'}]}),
        isA<PlanUpdated>().having((u) => u.entries.single.status, 'status', PlanStatus.inProgress),
      );
      expect(
        update({'sessionUpdate': 'available_commands_update', 'availableCommands': [
          {'name': 'review', 'description': 'Review code', 'input': {'hint': 'files'}},
        ]}),
        isA<CommandsUpdated>().having((u) => u.commands.single.hint, 'hint', 'files'),
      );
      expect(update({'sessionUpdate': 'current_mode_update', 'currentModeId': 'plan'}), isA<ModeUpdated>());
      expect(
        update({'sessionUpdate': 'config_option_update', 'configOptions': [
          {'id': 'mode', 'name': 'Mode', 'type': 'select', 'currentValue': 'plan', 'options': [{'value': 'plan', 'name': 'Plan'}]},
        ]}),
        isA<ConfigUpdated>().having((u) => u.options.single.currentValue, 'value', 'plan'),
      );
      expect(
        update({'sessionUpdate': 'session_info_update', 'title': 'Fix cart'}),
        isA<SessionInfoUpdated>().having((u) => u.title, 'title', 'Fix cart').having((u) => u.hasTitle, 'has', isTrue),
      );
      expect(
        update({'sessionUpdate': 'usage_update', 'used': 32000, 'size': 200000, 'cost': {'amount': 0.12, 'currency': 'USD'}}),
        isA<UsageUpdated>().having((u) => u.usage.percent, 'percent', 16),
      );
    });

    test('permission request with the Claude options', () {
      final r = sample('RequestPermissionRequest', {
        'sessionId': 's',
        'toolCall': {'toolCallId': 'toolu_1', 'title': 'Edit src/cart.js', 'kind': 'edit'},
        'options': [
          {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
          {'optionId': 'allow-with-updates', 'name': 'Yes, allow all edits during this session', 'kind': 'allow_always'},
          {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
        ],
      }, PermissionRequest.fromJson);
      expect(r.toolCallId, 'toolu_1');
      expect(r.toolCall.title, 'Edit src/cart.js');
      expect(r.options.map((o) => o.kind), [PermissionKind.allowOnce, PermissionKind.allowAlways, PermissionKind.rejectOnce]);
    });

    test('elicitation requests', () {
      final f = sample('CreateElicitationRequest', {
        'sessionId': 's',
        'toolCallId': 't',
        'mode': 'form',
        'message': 'Which approach?',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'approach': {'type': 'string', 'title': 'Approach', 'oneOf': [{'const': 'a', 'title': 'Patch'}, {'const': 'b', 'title': 'Rewrite'}]},
          },
          'required': ['approach'],
        },
      }, ElicitationRequest.fromJson) as ElicitationForm;
      expect(f.toolCallId, 't');
      expect(f.fields.single, isA<ElicitChoiceField>());
      final u = sample('CreateElicitationRequest', {
        'sessionId': 's',
        'mode': 'url',
        'message': 'Sign in to the MCP server',
        'elicitationId': 'e1',
        'url': 'https://example.com/oauth',
      }, ElicitationRequest.fromJson) as ElicitationUrl;
      expect(u.elicitationId, 'e1');
    });

    test('session list and prompt response', () {
      final l = sample('ListSessionsResponse', {
        'sessions': [{'sessionId': 'a', 'cwd': '/p', 'title': 'Fix cart', 'updatedAt': '2026-10-14T09:00:00Z'}],
        'nextCursor': 'n',
      }, ListSessionsResult.fromJson);
      expect(l.sessions.single.title, 'Fix cart');
      expect(l.nextCursor, 'n');
      for (final r in StopReason.values.where((r) => r != StopReason.other)) {
        valid('PromptResponse', {'stopReason': r.wire});
      }
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test test/acp_types_test.dart test/conformance_test.dart`
Expected: compile errors (types not defined).

- [ ] **Step 4: Implement the types**

`lib/src/acp_json.dart`:

```dart
import 'json_rpc.dart';

/// `toString()` is `'…'`: ACP values may carry the user's prompt, files or
/// paths and must never reach a log (spec D20).
mixin Redacted {
  @override
  String toString() => '…';
}

// Tolerant readers for agent JSON: a field of the wrong type reads as
// absent and nothing throws (spec §6).

String? readString(JsonMap m, String key) {
  final v = m[key];
  return v is String ? v : null;
}

int? readInt(JsonMap m, String key) {
  final v = m[key];
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

num? readNum(JsonMap m, String key) {
  final v = m[key];
  return v is num ? v : null;
}

bool? readBool(JsonMap m, String key) {
  final v = m[key];
  return v is bool ? v : null;
}

JsonMap? readMap(JsonMap m, String key) {
  final v = m[key];
  return v is JsonMap ? v : null;
}

List<Object?>? readList(JsonMap m, String key) {
  final v = m[key];
  return v is List ? v.cast<Object?>() : null;
}

/// The objects in list [key]; other entries are skipped.
Iterable<JsonMap> readMaps(JsonMap m, String key) =>
    (readList(m, key) ?? const []).whereType<JsonMap>();

/// The strings in list [key]; other entries are skipped.
List<String> readStrings(JsonMap m, String key) =>
    (readList(m, key) ?? const []).whereType<String>().toList();
```

`lib/src/acp_content.dart`:

```dart
import 'acp_json.dart';
import 'json_rpc.dart';

/// A piece of a prompt or message (ACP `ContentBlock`). ShellX sends text,
/// images and resource links (spec D16); embedded resources are read for
/// display; any other type is kept as [OtherBlock] and not drawn.
sealed class ContentBlock with Redacted {
  const ContentBlock();

  static ContentBlock fromJson(JsonMap j) => switch (readString(j, 'type')) {
    'text' => TextBlock(readString(j, 'text') ?? ''),
    'image' => ImageBlock(
      data: readString(j, 'data') ?? '',
      mimeType: readString(j, 'mimeType') ?? '',
      uri: readString(j, 'uri'),
    ),
    'resource_link' => ResourceLinkBlock(
      uri: readString(j, 'uri') ?? '',
      name: readString(j, 'name') ?? '',
      title: readString(j, 'title'),
      mimeType: readString(j, 'mimeType'),
      size: readInt(j, 'size'),
      description: readString(j, 'description'),
    ),
    'resource' => ResourceBlock.fromJson(readMap(j, 'resource') ?? const {}),
    final type => OtherBlock(type),
  };

  JsonMap toJson();
}

final class TextBlock extends ContentBlock {
  const TextBlock(this.text);

  final String text;

  @override
  JsonMap toJson() => {'type': 'text', 'text': text};
}

final class ImageBlock extends ContentBlock {
  const ImageBlock({required this.data, required this.mimeType, this.uri});

  /// Base64 bytes.
  final String data;
  final String mimeType;
  final String? uri;

  @override
  JsonMap toJson() => {
    'type': 'image',
    'data': data,
    'mimeType': mimeType,
    if (uri != null) 'uri': uri,
  };
}

final class ResourceLinkBlock extends ContentBlock {
  const ResourceLinkBlock({
    required this.uri,
    required this.name,
    this.title,
    this.mimeType,
    this.size,
    this.description,
  });

  final String uri;
  final String name;
  final String? title;
  final String? mimeType;
  final int? size;
  final String? description;

  @override
  JsonMap toJson() => {
    'type': 'resource_link',
    'uri': uri,
    'name': name,
    if (title != null) 'title': title,
    if (mimeType != null) 'mimeType': mimeType,
    if (size != null) 'size': size,
    if (description != null) 'description': description,
  };
}

/// An embedded resource; [text] is null for a binary (`blob`) resource.
final class ResourceBlock extends ContentBlock {
  const ResourceBlock({required this.uri, this.text, this.mimeType});

  static ResourceBlock fromJson(JsonMap r) => ResourceBlock(
    uri: readString(r, 'uri') ?? '',
    text: readString(r, 'text'),
    mimeType: readString(r, 'mimeType'),
  );

  final String uri;
  final String? text;
  final String? mimeType;

  @override
  JsonMap toJson() => {
    'type': 'resource',
    'resource': {
      'uri': uri,
      'text': text ?? '',
      if (mimeType != null) 'mimeType': mimeType,
    },
  };
}

/// A block type ShellX does not draw.
final class OtherBlock extends ContentBlock {
  const OtherBlock(this.type);

  final String? type;

  @override
  JsonMap toJson() => {'type': type ?? 'unknown'};
}

/// The text of [blocks]: text as it is, resource links as `@name`, other
/// blocks as nothing. Used for labels, never for logs.
String blockText(Iterable<ContentBlock> blocks) => blocks
    .map(
      (b) => switch (b) {
        TextBlock(:final text) => text,
        ResourceLinkBlock(:final name) => '@$name',
        _ => '',
      },
    )
    .join();
```

`lib/src/acp_types.dart`:

```dart
import 'acp_json.dart';
import 'acp_updates.dart';
import 'json_rpc.dart';

/// `clientInfo` / `agentInfo`.
final class Implementation with Redacted {
  const Implementation({required this.name, required this.version, this.title});

  static Implementation? fromJson(JsonMap? j) {
    final name = j == null ? null : readString(j, 'name');
    if (name == null) return null;
    return Implementation(
      name: name,
      version: readString(j!, 'version') ?? '',
      title: readString(j, 'title'),
    );
  }

  final String name;
  final String version;
  final String? title;
}

final class PromptCapabilities with Redacted {
  const PromptCapabilities({
    this.image = false,
    this.audio = false,
    this.embeddedContext = false,
  });

  static PromptCapabilities fromJson(JsonMap j) => PromptCapabilities(
    image: readBool(j, 'image') ?? false,
    audio: readBool(j, 'audio') ?? false,
    embeddedContext: readBool(j, 'embeddedContext') ?? false,
  );

  final bool image;
  final bool audio;
  final bool embeddedContext;
}

/// What the agent supports, from `initialize`.
final class AgentCapabilities with Redacted {
  const AgentCapabilities({
    this.loadSession = false,
    this.prompt = const PromptCapabilities(),
    this.listSessions = false,
    this.resumeSession = false,
    this.closeSession = false,
  });

  static AgentCapabilities fromJson(JsonMap j) {
    final s = readMap(j, 'sessionCapabilities') ?? const <String, Object?>{};
    return AgentCapabilities(
      loadSession: readBool(j, 'loadSession') ?? false,
      prompt: PromptCapabilities.fromJson(
        readMap(j, 'promptCapabilities') ?? const {},
      ),
      listSessions: s['list'] is JsonMap,
      resumeSession: s['resume'] is JsonMap,
      closeSession: s['close'] is JsonMap,
    );
  }

  /// `session/load` replays a past session (spec D14).
  final bool loadSession;
  final PromptCapabilities prompt;

  /// `session/list` is offered (spec D15).
  final bool listSessions;
  final bool resumeSession;
  final bool closeSession;
}

/// One way to sign in, from `initialize` (spec D8). Names are the agent's
/// and shown as they are.
sealed class AuthMethod with Redacted {
  const AuthMethod({required this.id, required this.name, this.description});

  static AuthMethod? fromJson(JsonMap j) {
    final id = readString(j, 'id');
    final name = readString(j, 'name');
    if (id == null || name == null) return null;
    final description = readString(j, 'description');
    return switch (readString(j, 'type')) {
      null || 'agent' => AuthMethodAgent(id: id, name: name, description: description),
      'terminal' => AuthMethodTerminal(
        id: id,
        name: name,
        description: description,
        args: readStrings(j, 'args'),
        env: {
          for (final e in (readMap(j, 'env') ?? const <String, Object?>{}).entries)
            if (e.value case final String v) e.key: v,
        },
      ),
      final type => AuthMethodOther(id: id, name: name, description: description, type: type),
    };
  }

  final String id;
  final String name;
  final String? description;
}

/// The agent signs in by itself after `authenticate {methodId}`.
final class AuthMethodAgent extends AuthMethod {
  const AuthMethodAgent({required super.id, required super.name, super.description});
}

/// ShellX runs the agent's own command plus [args] and [env] in a run sheet;
/// exit 0 means signed in. ShellX never calls `authenticate` for it and
/// never reads what the run sheet shows (spec D8, §5).
final class AuthMethodTerminal extends AuthMethod {
  const AuthMethodTerminal({
    required super.id,
    required super.name,
    super.description,
    this.args = const [],
    this.env = const {},
  });

  final List<String> args;
  final Map<String, String> env;
}

/// A sign-in kind this version does not know: listed, not offered.
final class AuthMethodOther extends AuthMethod {
  const AuthMethodOther({required super.id, required super.name, super.description, required this.type});

  final String type;
}

final class InitializeResult with Redacted {
  const InitializeResult({
    required this.protocolVersion,
    this.capabilities = const AgentCapabilities(),
    this.authMethods = const [],
    this.agentInfo,
  });

  static InitializeResult fromJson(JsonMap j) => InitializeResult(
    protocolVersion: readInt(j, 'protocolVersion') ?? 0,
    capabilities: AgentCapabilities.fromJson(readMap(j, 'agentCapabilities') ?? const {}),
    authMethods: readMaps(j, 'authMethods').map(AuthMethod.fromJson).nonNulls.toList(),
    agentInfo: Implementation.fromJson(readMap(j, 'agentInfo')),
  );

  final int protocolVersion;
  final AgentCapabilities capabilities;
  final List<AuthMethod> authMethods;
  final Implementation? agentInfo;
}

enum ConfigKind { select, boolean, other }

/// One value of a select option; [group] is its group's display name.
final class ConfigChoice with Redacted {
  const ConfigChoice({required this.value, required this.name, this.description, this.group});

  final String value;
  final String name;
  final String? description;
  final String? group;
}

/// A session setting the agent offers (`configOptions`, spec D11): mode,
/// model, thought level… Grouped values are flattened into [choices].
final class ConfigOption with Redacted {
  const ConfigOption({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.category,
    this.currentValue,
    this.choices = const [],
  });

  static ConfigOption? fromJson(JsonMap j) {
    final id = readString(j, 'id');
    final name = readString(j, 'name');
    if (id == null || name == null) return null;
    final kind = switch (readString(j, 'type')) {
      'select' => ConfigKind.select,
      'boolean' => ConfigKind.boolean,
      _ => ConfigKind.other,
    };
    final choices = <ConfigChoice>[];
    void add(JsonMap c, String? group) {
      final value = readString(c, 'value');
      final label = readString(c, 'name');
      if (value == null || label == null) return;
      choices.add(ConfigChoice(value: value, name: label, description: readString(c, 'description'), group: group));
    }

    for (final o in readMaps(j, 'options')) {
      if (readList(o, 'options') != null) {
        for (final c in readMaps(o, 'options')) {
          add(c, readString(o, 'name'));
        }
      } else {
        add(o, null);
      }
    }
    return ConfigOption(
      id: id,
      name: name,
      kind: kind,
      description: readString(j, 'description'),
      category: readString(j, 'category'),
      currentValue: switch (kind) {
        ConfigKind.select => readString(j, 'currentValue'),
        ConfigKind.boolean => readBool(j, 'currentValue'),
        ConfigKind.other => j['currentValue'],
      },
      choices: choices,
    );
  }

  final String id;
  final String name;
  final ConfigKind kind;
  final String? description;

  /// `mode`, `model`, `model_config`, `thought_level` or an agent's own.
  final String? category;

  /// A [String] for [ConfigKind.select], a [bool] for [ConfigKind.boolean].
  final Object? currentValue;
  final List<ConfigChoice> choices;

  ConfigOption withValue(Object? value) => ConfigOption(
    id: id,
    name: name,
    kind: kind,
    description: description,
    category: category,
    currentValue: value,
    choices: choices,
  );
}

/// The valid options in list [key] of [j].
List<ConfigOption> readConfigOptions(JsonMap j, String key) =>
    readMaps(j, key).map(ConfigOption.fromJson).nonNulls.toList();

final class SessionMode with Redacted {
  const SessionMode({required this.id, required this.name, this.description});

  final String id;
  final String name;
  final String? description;
}

/// Legacy modes (`modes`); agents with `configOptions` use those (spec D11).
final class SessionModes with Redacted {
  const SessionModes({required this.currentModeId, required this.available});

  static SessionModes? fromJson(JsonMap? j) {
    final current = j == null ? null : readString(j, 'currentModeId');
    if (current == null) return null;
    return SessionModes(
      currentModeId: current,
      available: [
        for (final m in readMaps(j!, 'availableModes'))
          if ((readString(m, 'id'), readString(m, 'name')) case (final String id, final String name))
            SessionMode(id: id, name: name, description: readString(m, 'description')),
      ],
    );
  }

  final String currentModeId;
  final List<SessionMode> available;

  SessionModes withCurrent(String id) => SessionModes(currentModeId: id, available: available);
}

final class NewSessionResult with Redacted {
  const NewSessionResult({required this.sessionId, this.configOptions, this.modes});

  static NewSessionResult fromJson(JsonMap j) => NewSessionResult(
    sessionId: readString(j, 'sessionId') ?? '',
    configOptions: j['configOptions'] is List ? readConfigOptions(j, 'configOptions') : null,
    modes: SessionModes.fromJson(readMap(j, 'modes')),
  );

  /// Empty when the agent sent none (a protocol error for the caller).
  final String sessionId;
  final List<ConfigOption>? configOptions;
  final SessionModes? modes;
}

final class LoadSessionResult with Redacted {
  const LoadSessionResult({this.configOptions, this.modes});

  static LoadSessionResult fromJson(JsonMap j) => LoadSessionResult(
    configOptions: j['configOptions'] is List ? readConfigOptions(j, 'configOptions') : null,
    modes: SessionModes.fromJson(readMap(j, 'modes')),
  );

  final List<ConfigOption>? configOptions;
  final SessionModes? modes;
}

/// One entry of `session/list` (spec D15).
final class SessionSummary with Redacted {
  const SessionSummary({required this.sessionId, required this.cwd, this.title, this.updatedAt});

  final String sessionId;
  final String cwd;
  final String? title;

  /// ISO 8601, as the agent sent it.
  final String? updatedAt;
}

final class ListSessionsResult with Redacted {
  const ListSessionsResult({this.sessions = const [], this.nextCursor});

  static ListSessionsResult fromJson(JsonMap j) => ListSessionsResult(
    sessions: [
      for (final s in readMaps(j, 'sessions'))
        if (readString(s, 'sessionId') case final String id)
          SessionSummary(
            sessionId: id,
            cwd: readString(s, 'cwd') ?? '',
            title: readString(s, 'title'),
            updatedAt: readString(s, 'updatedAt'),
          ),
    ],
    nextCursor: readString(j, 'nextCursor'),
  );

  final List<SessionSummary> sessions;
  final String? nextCursor;
}

/// Why a turn ended (`session/prompt` result).
enum StopReason {
  endTurn('end_turn'),
  maxTokens('max_tokens'),
  maxTurnRequests('max_turn_requests'),
  refusal('refusal'),
  cancelled('cancelled'),

  /// A reason this version does not know.
  other('');

  const StopReason(this.wire);

  final String wire;

  static StopReason parse(String? wire) {
    for (final r in values) {
      if (r != other && r.wire == wire) return r;
    }
    return other;
  }
}

/// The kind of a permission option; the label comes from it (spec D10).
enum PermissionKind {
  allowOnce('allow_once'),
  allowAlways('allow_always'),
  rejectOnce('reject_once'),
  rejectAlways('reject_always'),
  other('');

  const PermissionKind(this.wire);

  final String wire;

  bool get isReject => this == rejectOnce || this == rejectAlways;

  static PermissionKind parse(String? wire) {
    for (final k in values) {
      if (k != other && k.wire == wire) return k;
    }
    return other;
  }
}

final class PermissionOption with Redacted {
  const PermissionOption({required this.optionId, required this.name, required this.kind});

  static PermissionOption? fromJson(JsonMap j) {
    final id = readString(j, 'optionId');
    final name = readString(j, 'name');
    if (id == null || name == null) return null;
    return PermissionOption(optionId: id, name: name, kind: PermissionKind.parse(readString(j, 'kind')));
  }

  final String optionId;

  /// The agent's own words (shown under the kind label, spec D10).
  final String name;
  final PermissionKind kind;
}

/// `session/request_permission`: options in the agent's order (keys 1–9).
final class PermissionRequest with Redacted {
  const PermissionRequest({
    required this.sessionId,
    required this.toolCallId,
    required this.toolCall,
    required this.options,
  });

  static PermissionRequest fromJson(JsonMap j) {
    final call = readMap(j, 'toolCall') ?? const <String, Object?>{};
    return PermissionRequest(
      sessionId: readString(j, 'sessionId') ?? '',
      toolCallId: readString(call, 'toolCallId') ?? '',
      toolCall: ToolCallFields.fromJson(call),
      options: readMaps(j, 'options').map(PermissionOption.fromJson).nonNulls.toList(),
    );
  }

  final String sessionId;
  final String toolCallId;
  final ToolCallFields toolCall;
  final List<PermissionOption> options;
}

/// The answer to a permission request.
sealed class PermissionOutcome with Redacted {
  const PermissionOutcome();

  JsonMap toJson();
}

final class PermissionSelected extends PermissionOutcome {
  const PermissionSelected(this.optionId);

  final String optionId;

  @override
  JsonMap toJson() => {
    'outcome': {'outcome': 'selected', 'optionId': optionId},
  };
}

/// The turn was cancelled while the question was open (ACP requires this
/// answer for every open request after `session/cancel`).
final class PermissionCancelled extends PermissionOutcome {
  const PermissionCancelled();

  @override
  JsonMap toJson() => {
    'outcome': {'outcome': 'cancelled'},
  };
}

/// An MCP server ShellX could hand to a session (none in V2-1).
final class McpServerStdio with Redacted {
  const McpServerStdio({required this.name, required this.command, this.args = const [], this.env = const {}});

  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;

  JsonMap toJson() => {
    'name': name,
    'command': command,
    'args': args,
    'env': [
      for (final e in env.entries) {'name': e.key, 'value': e.value},
    ],
  };
}
```

`lib/src/acp_updates.dart`:

```dart
import 'acp_content.dart';
import 'acp_json.dart';
import 'acp_types.dart';
import 'json_rpc.dart';

/// What a tool call does; picks its card (spec §4.2).
enum ToolKind {
  read('read'),
  edit('edit'),
  delete('delete'),
  move('move'),
  search('search'),
  execute('execute'),
  think('think'),
  fetch('fetch'),
  switchMode('switch_mode'),
  other('other');

  const ToolKind(this.wire);

  final String wire;

  /// Null when not sent; an unknown kind is [other].
  static ToolKind? parse(String? wire) {
    if (wire == null) return null;
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return other;
  }
}

enum ToolCallStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  failed('failed');

  const ToolCallStatus(this.wire);

  final String wire;

  /// Null when not sent or unknown.
  static ToolCallStatus? parse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// Something a tool call shows: output, a diff, or an agent terminal.
sealed class ToolContent with Redacted {
  const ToolContent();

  static ToolContent fromJson(JsonMap j) => switch (readString(j, 'type')) {
    'content' => ToolContentBlock(ContentBlock.fromJson(readMap(j, 'content') ?? const {})),
    'diff' => ToolDiff(
      path: readString(j, 'path') ?? '',
      oldText: readString(j, 'oldText'),
      newText: readString(j, 'newText') ?? '',
    ),
    'terminal' => ToolTerminal(readString(j, 'terminalId') ?? ''),
    final type => ToolContentOther(type),
  };
}

final class ToolContentBlock extends ToolContent {
  const ToolContentBlock(this.block);

  final ContentBlock block;
}

/// A file edit; a null [oldText] means the file is new (card "Tạo").
final class ToolDiff extends ToolContent {
  const ToolDiff({required this.path, this.oldText, required this.newText});

  final String path;
  final String? oldText;
  final String newText;
}

/// An agent-side terminal. ShellX offers none (D1), so it is not drawn.
final class ToolTerminal extends ToolContent {
  const ToolTerminal(this.terminalId);

  final String terminalId;
}

final class ToolContentOther extends ToolContent {
  const ToolContentOther(this.type);

  final String? type;
}

final class ToolLocation with Redacted {
  const ToolLocation(this.path, [this.line]);

  final String path;
  final int? line;
}

/// What a `tool_call` or `tool_call_update` says about one call; null means
/// "not sent". In an update, [content] and [locations] replace whole lists.
final class ToolCallFields with Redacted {
  const ToolCallFields({
    this.title,
    this.name,
    this.kind,
    this.status,
    this.content,
    this.locations,
    this.rawInput,
    this.rawOutput,
  });

  static ToolCallFields fromJson(JsonMap j) => ToolCallFields(
    title: readString(j, 'title'),
    name: readString(j, 'name'),
    kind: ToolKind.parse(readString(j, 'kind')),
    status: ToolCallStatus.parse(readString(j, 'status')),
    content: readList(j, 'content')?.whereType<JsonMap>().map(ToolContent.fromJson).toList(),
    locations: readList(j, 'locations')
        ?.whereType<JsonMap>()
        .map((l) => ToolLocation(readString(l, 'path') ?? '', readInt(l, 'line')))
        .toList(),
    rawInput: j['rawInput'],
    rawOutput: j['rawOutput'],
  );

  final String? title;
  final String? name;
  final ToolKind? kind;
  final ToolCallStatus? status;
  final List<ToolContent>? content;
  final List<ToolLocation>? locations;
  final Object? rawInput;
  final Object? rawOutput;

  /// These fields, with every field [update] sent replacing its own.
  ToolCallFields merge(ToolCallFields update) => ToolCallFields(
    title: update.title ?? title,
    name: update.name ?? name,
    kind: update.kind ?? kind,
    status: update.status ?? status,
    content: update.content ?? content,
    locations: update.locations ?? locations,
    rawInput: update.rawInput ?? rawInput,
    rawOutput: update.rawOutput ?? rawOutput,
  );
}

enum PlanStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed');

  const PlanStatus(this.wire);

  final String wire;

  static PlanStatus parse(String? wire) => values.firstWhere((s) => s.wire == wire, orElse: () => pending);
}

final class PlanEntry with Redacted {
  const PlanEntry({required this.content, required this.status, this.priority = 'medium'});

  static PlanEntry? fromJson(JsonMap j) {
    final content = readString(j, 'content');
    if (content == null) return null;
    return PlanEntry(
      content: content,
      status: PlanStatus.parse(readString(j, 'status')),
      priority: readString(j, 'priority') ?? 'medium',
    );
  }

  final String content;
  final PlanStatus status;

  /// `high`, `medium` or `low`.
  final String priority;
}

/// A `/command` the agent offers (spec D16).
final class AvailableCommand with Redacted {
  const AvailableCommand({required this.name, this.description = '', this.hint});

  static AvailableCommand? fromJson(JsonMap j) {
    final name = readString(j, 'name');
    if (name == null) return null;
    final input = readMap(j, 'input');
    return AvailableCommand(
      name: name,
      description: readString(j, 'description') ?? '',
      hint: input == null ? null : readString(input, 'hint'),
    );
  }

  final String name;
  final String description;
  final String? hint;
}

/// Context use (`usage_update`, the composer's "Ngữ cảnh 16%").
final class Usage with Redacted {
  const Usage({required this.used, required this.size, this.costAmount, this.costCurrency});

  final int used;
  final int size;
  final double? costAmount;
  final String? costCurrency;

  int get percent => size <= 0 ? 0 : (used * 100 / size).round().clamp(0, 100);
}

/// One `session/update`. Unknown kinds (including `notice` and
/// `compaction_*`, which ShellX does not advertise) are [UnknownUpdate].
sealed class SessionUpdate with Redacted {
  const SessionUpdate();

  static SessionUpdate fromJson(JsonMap j) {
    final kind = readString(j, 'sessionUpdate');
    switch (kind) {
      case 'user_message_chunk':
      case 'agent_message_chunk':
      case 'agent_thought_chunk':
        final content = readMap(j, 'content');
        if (content == null) return UnknownUpdate(kind);
        final block = ContentBlock.fromJson(content);
        final messageId = readString(j, 'messageId');
        return switch (kind) {
          'user_message_chunk' => UserMessageChunk(block, messageId: messageId),
          'agent_message_chunk' => AgentMessageChunk(block, messageId: messageId),
          _ => AgentThoughtChunk(block, messageId: messageId),
        };
      case 'tool_call':
      case 'tool_call_update':
        final id = readString(j, 'toolCallId');
        if (id == null) return UnknownUpdate(kind);
        final fields = ToolCallFields.fromJson(j);
        return kind == 'tool_call' ? ToolCallStarted(id, fields) : ToolCallUpdated(id, fields);
      case 'plan':
        return PlanUpdated(readMaps(j, 'entries').map(PlanEntry.fromJson).nonNulls.toList());
      case 'available_commands_update':
        return CommandsUpdated(readMaps(j, 'availableCommands').map(AvailableCommand.fromJson).nonNulls.toList());
      case 'current_mode_update':
        final id = readString(j, 'currentModeId');
        return id == null ? UnknownUpdate(kind) : ModeUpdated(id);
      case 'config_option_update':
        return ConfigUpdated(readConfigOptions(j, 'configOptions'));
      case 'session_info_update':
        return SessionInfoUpdated(
          hasTitle: j.containsKey('title'),
          title: readString(j, 'title'),
          updatedAt: readString(j, 'updatedAt'),
        );
      case 'usage_update':
        final used = readInt(j, 'used');
        final size = readInt(j, 'size');
        if (used == null || size == null) return UnknownUpdate(kind);
        final cost = readMap(j, 'cost');
        return UsageUpdated(
          Usage(
            used: used,
            size: size,
            costAmount: cost == null ? null : readNum(cost, 'amount')?.toDouble(),
            costCurrency: cost == null ? null : readString(cost, 'currency'),
          ),
        );
      default:
        return UnknownUpdate(kind);
    }
  }
}

final class UserMessageChunk extends SessionUpdate {
  const UserMessageChunk(this.content, {this.messageId});

  final ContentBlock content;
  final String? messageId;
}

final class AgentMessageChunk extends SessionUpdate {
  const AgentMessageChunk(this.content, {this.messageId});

  final ContentBlock content;
  final String? messageId;
}

final class AgentThoughtChunk extends SessionUpdate {
  const AgentThoughtChunk(this.content, {this.messageId});

  final ContentBlock content;
  final String? messageId;
}

final class ToolCallStarted extends SessionUpdate {
  const ToolCallStarted(this.toolCallId, this.fields);

  final String toolCallId;
  final ToolCallFields fields;
}

final class ToolCallUpdated extends SessionUpdate {
  const ToolCallUpdated(this.toolCallId, this.fields);

  final String toolCallId;
  final ToolCallFields fields;
}

final class PlanUpdated extends SessionUpdate {
  const PlanUpdated(this.entries);

  final List<PlanEntry> entries;
}

final class CommandsUpdated extends SessionUpdate {
  const CommandsUpdated(this.commands);

  final List<AvailableCommand> commands;
}

final class ModeUpdated extends SessionUpdate {
  const ModeUpdated(this.currentModeId);

  final String currentModeId;
}

final class ConfigUpdated extends SessionUpdate {
  const ConfigUpdated(this.options);

  final List<ConfigOption> options;
}

final class SessionInfoUpdated extends SessionUpdate {
  const SessionInfoUpdated({required this.hasTitle, this.title, this.updatedAt});

  /// `title` was sent; a null [title] then clears the title.
  final bool hasTitle;
  final String? title;
  final String? updatedAt;
}

final class UsageUpdated extends SessionUpdate {
  const UsageUpdated(this.usage);

  final Usage usage;
}

final class UnknownUpdate extends SessionUpdate {
  const UnknownUpdate(this.kind);

  final String? kind;
}
```

`lib/src/acp_elicitation.dart`:

```dart
import 'acp_json.dart';
import 'json_rpc.dart';

/// The agent asks the user something (`elicitation/create`, spec D22).
sealed class ElicitationRequest with Redacted {
  const ElicitationRequest({required this.message, this.sessionId, this.toolCallId, this.requestId});

  static ElicitationRequest fromJson(JsonMap j) {
    final message = readString(j, 'message') ?? '';
    final sessionId = readString(j, 'sessionId');
    final toolCallId = readString(j, 'toolCallId');
    final requestId = j['requestId'];
    switch (readString(j, 'mode')) {
      case 'form':
        final schema = readMap(j, 'requestedSchema') ?? const <String, Object?>{};
        final required = readStrings(schema, 'required').toSet();
        final props = readMap(schema, 'properties') ?? const <String, Object?>{};
        return ElicitationForm(
          message: message,
          sessionId: sessionId,
          toolCallId: toolCallId,
          requestId: requestId,
          title: readString(schema, 'title'),
          description: readString(schema, 'description'),
          fields: [
            for (final e in props.entries)
              if (e.value case final JsonMap p) ElicitField.fromJson(e.key, p, required: required.contains(e.key)),
          ],
        );
      case 'url':
        final id = readString(j, 'elicitationId');
        final url = readString(j, 'url');
        if (id != null && url != null) {
          return ElicitationUrl(
            message: message,
            sessionId: sessionId,
            toolCallId: toolCallId,
            requestId: requestId,
            elicitationId: id,
            url: url,
          );
        }
        return ElicitationOther(message: message, sessionId: sessionId, toolCallId: toolCallId, requestId: requestId, mode: 'url');
      case final mode:
        return ElicitationOther(message: message, sessionId: sessionId, toolCallId: toolCallId, requestId: requestId, mode: mode);
    }
  }

  final String message;
  final String? sessionId;
  final String? toolCallId;

  /// Set when the question belongs to a request (e.g. `session/new` asking
  /// to sign in to an MCP server) instead of a session.
  final Object? requestId;
}

final class ElicitationForm extends ElicitationRequest {
  const ElicitationForm({
    required super.message,
    super.sessionId,
    super.toolCallId,
    super.requestId,
    this.title,
    this.description,
    this.fields = const [],
  });

  final String? title;
  final String? description;
  final List<ElicitField> fields;

  /// False when a field uses a type ShellX cannot show; then the card says
  /// so and the answer is `decline` (spec D22).
  bool get supported => fields.every((f) => f is! ElicitUnsupportedField);

  /// [content] answers every required field with an accepted value and has
  /// no key the form did not ask for.
  bool accepts(Map<String, Object?> content) {
    final keys = {for (final f in fields) f.key};
    if (content.keys.any((k) => !keys.contains(k))) return false;
    for (final f in fields) {
      final v = content[f.key];
      if (v == null) {
        if (f.required) return false;
      } else if (!f.accepts(v)) {
        return false;
      }
    }
    return true;
  }
}

final class ElicitationUrl extends ElicitationRequest {
  const ElicitationUrl({
    required super.message,
    super.sessionId,
    super.toolCallId,
    super.requestId,
    required this.elicitationId,
    required this.url,
  });

  final String elicitationId;
  final String url;

  /// Only http and https URLs with a host may be opened, after a click
  /// (spec D22, §5).
  bool get isWebUrl {
    final u = Uri.tryParse(url);
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
  }
}

/// A mode this version does not know; answered `decline`.
final class ElicitationOther extends ElicitationRequest {
  const ElicitationOther({required super.message, super.sessionId, super.toolCallId, super.requestId, this.mode});

  final String? mode;
}

final class ElicitOption with Redacted {
  const ElicitOption(this.value, this.title);

  final String value;
  final String title;
}

/// One form field (string, number, boolean, single or multiple choice).
sealed class ElicitField with Redacted {
  const ElicitField({required this.key, required this.required, this.title, this.description});

  static ElicitField fromJson(String key, JsonMap j, {required bool required}) {
    final title = readString(j, 'title');
    final description = readString(j, 'description');
    List<ElicitOption> titled(Iterable<JsonMap> items) => [
      for (final o in items)
        if (readString(o, 'const') case final String v) ElicitOption(v, readString(o, 'title') ?? v),
    ];
    switch (readString(j, 'type')) {
      case 'string':
        if (readList(j, 'oneOf') != null || readList(j, 'enum') != null) {
          final oneOf = titled(readMaps(j, 'oneOf'));
          return ElicitChoiceField(
            key: key,
            required: required,
            title: title,
            description: description,
            options: oneOf.isNotEmpty ? oneOf : [for (final v in readStrings(j, 'enum')) ElicitOption(v, v)],
            defaultValue: readString(j, 'default'),
          );
        }
        return ElicitTextField(
          key: key,
          required: required,
          title: title,
          description: description,
          minLength: readInt(j, 'minLength'),
          maxLength: readInt(j, 'maxLength'),
          format: readString(j, 'format'),
          defaultValue: readString(j, 'default'),
        );
      case final t && ('number' || 'integer'):
        return ElicitNumberField(
          key: key,
          required: required,
          title: title,
          description: description,
          integer: t == 'integer',
          minimum: readNum(j, 'minimum'),
          maximum: readNum(j, 'maximum'),
          defaultValue: readNum(j, 'default'),
        );
      case 'boolean':
        return ElicitBoolField(key: key, required: required, title: title, description: description, defaultValue: readBool(j, 'default'));
      case 'array':
        final items = readMap(j, 'items') ?? const <String, Object?>{};
        final anyOf = titled(readMaps(items, 'anyOf'));
        final options = anyOf.isNotEmpty ? anyOf : [for (final v in readStrings(items, 'enum')) ElicitOption(v, v)];
        if (options.isEmpty) {
          return ElicitUnsupportedField(key: key, required: required, title: title, description: description, type: 'array');
        }
        return ElicitMultiChoiceField(
          key: key,
          required: required,
          title: title,
          description: description,
          options: options,
          minItems: readInt(j, 'minItems'),
          maxItems: readInt(j, 'maxItems'),
          defaultValue: readList(j, 'default') == null ? null : readStrings(j, 'default'),
        );
      case final type:
        return ElicitUnsupportedField(key: key, required: required, title: title, description: description, type: type);
    }
  }

  final String key;
  final bool required;
  final String? title;
  final String? description;

  /// [value] is a valid answer for this field.
  bool accepts(Object value);
}

final class ElicitTextField extends ElicitField {
  const ElicitTextField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    this.minLength,
    this.maxLength,
    this.format,
    this.defaultValue,
  });

  final int? minLength;
  final int? maxLength;

  /// `email`, `uri`, `date` or `date-time`: a keyboard hint only.
  final String? format;
  final String? defaultValue;

  @override
  bool accepts(Object value) =>
      value is String &&
      (minLength == null || value.length >= minLength!) &&
      (maxLength == null || value.length <= maxLength!);
}

final class ElicitNumberField extends ElicitField {
  const ElicitNumberField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    required this.integer,
    this.minimum,
    this.maximum,
    this.defaultValue,
  });

  final bool integer;
  final num? minimum;
  final num? maximum;
  final num? defaultValue;

  @override
  bool accepts(Object value) =>
      value is num &&
      value.isFinite &&
      (!integer || value is int) &&
      (minimum == null || value >= minimum!) &&
      (maximum == null || value <= maximum!);
}

final class ElicitBoolField extends ElicitField {
  const ElicitBoolField({required super.key, required super.required, super.title, super.description, this.defaultValue});

  final bool? defaultValue;

  @override
  bool accepts(Object value) => value is bool;
}

final class ElicitChoiceField extends ElicitField {
  const ElicitChoiceField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    required this.options,
    this.defaultValue,
  });

  final List<ElicitOption> options;
  final String? defaultValue;

  @override
  bool accepts(Object value) => value is String && options.any((o) => o.value == value);
}

final class ElicitMultiChoiceField extends ElicitField {
  const ElicitMultiChoiceField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    required this.options,
    this.minItems,
    this.maxItems,
    this.defaultValue,
  });

  final List<ElicitOption> options;
  final int? minItems;
  final int? maxItems;
  final List<String>? defaultValue;

  @override
  bool accepts(Object value) =>
      value is List &&
      value.every((v) => v is String && options.any((o) => o.value == v)) &&
      value.toSet().length == value.length &&
      (minItems == null || value.length >= minItems!) &&
      (maxItems == null || value.length <= maxItems!);
}

/// A field type ShellX cannot show (spec D22).
final class ElicitUnsupportedField extends ElicitField {
  const ElicitUnsupportedField({required super.key, required super.required, super.title, super.description, this.type});

  final String? type;

  @override
  bool accepts(Object value) => false;
}

/// The user's answer to an elicitation.
sealed class ElicitationResponse with Redacted {
  const ElicitationResponse();

  JsonMap toJson();
}

final class ElicitAccept extends ElicitationResponse {
  const ElicitAccept([this.content]);

  /// The form values; null for a URL question.
  final Map<String, Object>? content;

  @override
  JsonMap toJson() => {'action': 'accept', if (content != null) 'content': content};
}

final class ElicitDecline extends ElicitationResponse {
  const ElicitDecline();

  @override
  JsonMap toJson() => {'action': 'decline'};
}

final class ElicitCancel extends ElicitationResponse {
  const ElicitCancel();

  @override
  JsonMap toJson() => {'action': 'cancel'};
}
```

`lib/src/acp_requests.dart`:

```dart
import 'acp_content.dart';
import 'acp_types.dart';
import 'json_rpc.dart';

// Params of every request ShellX sends. Kept apart from AcpClient so the
// conformance test checks each one against the ACP schema (spec §7).

/// `initialize` (spec D1): no file system and no terminals offered; ShellX
/// runs terminal logins itself and answers form and URL questions.
JsonMap initializeParams({required String clientVersion}) => {
  'protocolVersion': 1,
  'clientCapabilities': {
    'fs': {'readTextFile': false, 'writeTextFile': false},
    'terminal': false,
    'auth': {'terminal': true},
    'elicitation': {'form': <String, Object?>{}, 'url': <String, Object?>{}},
  },
  'clientInfo': {'name': 'shellx', 'title': 'ShellX', 'version': clientVersion},
};

JsonMap authenticateParams(String methodId) => {'methodId': methodId};

JsonMap newSessionParams({required String cwd, List<McpServerStdio> mcpServers = const []}) => {
  'cwd': cwd,
  'mcpServers': [for (final s in mcpServers) s.toJson()],
};

JsonMap loadSessionParams({
  required String sessionId,
  required String cwd,
  List<McpServerStdio> mcpServers = const [],
}) => {
  'sessionId': sessionId,
  'cwd': cwd,
  'mcpServers': [for (final s in mcpServers) s.toJson()],
};

JsonMap listSessionsParams({String? cwd, String? cursor}) => {
  if (cwd != null) 'cwd': cwd,
  if (cursor != null) 'cursor': cursor,
};

JsonMap promptParams(String sessionId, List<ContentBlock> prompt) => {
  'sessionId': sessionId,
  'prompt': [for (final b in prompt) b.toJson()],
};

JsonMap cancelParams(String sessionId) => {'sessionId': sessionId};

/// A [String] is a select value; a [bool] is sent with `type: "boolean"`.
JsonMap setConfigOptionParams(String sessionId, String configId, Object value) {
  if (value is! String && value is! bool) {
    throw ArgumentError.value(value, 'value', 'must be a String or a bool');
  }
  return {
    'sessionId': sessionId,
    'configId': configId,
    if (value is bool) 'type': 'boolean',
    'value': value,
  };
}

JsonMap setModeParams(String sessionId, String modeId) => {'sessionId': sessionId, 'modeId': modeId};
```

Update `lib/shellx_acp.dart`:

```dart
/// Agent Client Protocol (ACP v1) for ShellX: JSON-RPC over stdio, the
/// protocol types ShellX uses and the client (spec D1).
library;

export 'src/acp_content.dart';
export 'src/acp_elicitation.dart';
export 'src/acp_json.dart' show Redacted;
export 'src/acp_requests.dart';
export 'src/acp_types.dart';
export 'src/acp_updates.dart';
export 'src/json_rpc.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: all tests pass; `No issues found!`

If the schema validator throws on an unknown `format` (`uint16`, `uint32`, `uint64`, `int64`, `double`), call `validate(json, validateFormats: false)`. Formats are annotations in draft 2020-12. Record that in the ledger.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_acp pubspec.lock
git commit -m "feat(v2-ai): ACP v1 types, request builders and schema conformance tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `AcpClient` and the scripted fake agent

**Files:**
- Create: `packages/shellx_acp/lib/src/acp_client.dart`
- Create: `packages/shellx_acp/lib/src/testing/fake_agent.dart`, `lib/src/testing/fake_steps.dart`, `lib/src/testing/fake_agent_process.dart`
- Create: `packages/shellx_acp/lib/testing.dart`
- Create: `packages/shellx_acp/bin/fake_agent.dart`
- Modify: `packages/shellx_acp/lib/shellx_acp.dart` (export `src/acp_client.dart`)
- Test: `packages/shellx_acp/test/acp_client_test.dart`, `packages/shellx_acp/test/fake_agent_process_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces:
  - `typedef PermissionHandler = Future<PermissionOutcome> Function(PermissionRequest)`; `typedef ElicitationHandler = Future<ElicitationResponse> Function(ElicitationRequest)`.
  - `final class AcpClient`:
    - constructor and fields: `AcpClient(JsonRpcConnection connection)`; `final JsonRpcConnection connection`.
    - callbacks: `void Function(String sessionId, SessionUpdate update)? onUpdate`; `void Function(String elicitationId)? onElicitationComplete`; `PermissionHandler? onPermission`; `ElicitationHandler? onElicitation`.
    - session methods:
      - `Future<InitializeResult> initialize({required String clientVersion})`
      - `Future<void> authenticate(String methodId)`
      - `Future<NewSessionResult> newSession({required String cwd, List<McpServerStdio> mcpServers = const []})`
      - `Future<LoadSessionResult> loadSession({required String sessionId, required String cwd, List<McpServerStdio> mcpServers = const []})`
      - `Future<ListSessionsResult> listSessions({String? cwd, String? cursor})`
    - turn methods:
      - `Future<StopReason> prompt(String sessionId, List<ContentBlock> prompt)`
      - `void cancel(String sessionId)`
    - config methods:
      - `Future<List<ConfigOption>?> setConfigOption(String sessionId, String configId, Object value)`
      - `Future<void> setMode(String sessionId, String modeId)`
    - lifecycle: `Future<void> close()`.

    Without handlers, a permission answers `PermissionCancelled` and an elicitation answers `ElicitDecline` (never auto-allow).
  - `package:shellx_acp/testing.dart`:
    - `final class FakeScenario`, with `fromJson`/`toJson`. Fields: `protocolVersion`, `loadSession`, `listSessions`, `image`, `authMethods`, `requireAuth`, `authFile`, `sessionId`, `configOptions`, `modes`, `turns`, `history`, `sessions`, `newSessionError`, `loadSessionError`.
    - `abstract final class FakeSteps`, with one-key step maps:
      - updates: `update`, `text`, `thought`, `tool`, `toolUpdate`, `diff`, `output`, `plan`;
      - questions: `permission`, `ask`, `completeAsk`;
      - flow: `sleep`, `waitCancel`, `hang`, `exit`, `stop`, `error`;
      - output and files: `raw`, `bigText`, `stderr`, `write`, `delete`;
      - `claudeOptions`.
    - `final class FakeAgent`:
      - constructor: `FakeAgent(FakeScenario, {required Stream<List<int>> input, required StreamSink<List<int>> output, String? cwd, void Function(String line)? stderr, void Function(int code)? onExit})`;
      - fields: `connection`, `List<String> received`, `Map<String, JsonMap> params`.
    - `List<String> fakeAgentArgs(String scenarioFile)`, `String writeScenario(FakeScenario, Directory dir, [String name])`.

`received` uses these entries, in arrival order:
- `initialize`;
- `authenticate:<methodId>`;
- `session/new`, `session/load:<id>`, `session/list`;
- `session/prompt:<blockText>`, `session/cancel`;
- `session/set_config_option:<id>=<value>`, `session/set_mode:<id>`;
- `permission:<optionId|cancelled>`;
- `ask:<action>[=<json content>]`.

The process form also prints each entry to stderr as `RECV <entry>`.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_acp/test/acp_client_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:test/test.dart';

/// A client wired to an in-process fake agent.
(AcpClient, FakeAgent) connect(FakeScenario scenario, {String? cwd}) {
  final toAgent = StreamController<List<int>>();
  final toClient = StreamController<List<int>>();
  final agent = FakeAgent(
    scenario,
    input: toAgent.stream,
    output: toClient.sink,
    cwd: cwd,
    onExit: (_) => toClient.close(),
  );
  final client = AcpClient(JsonRpcConnection(input: toClient.stream, output: toAgent.sink));
  return (client, agent);
}

Future<String> start(AcpClient client) async {
  await client.initialize(clientVersion: '2.0.0');
  return (await client.newSession(cwd: '/p')).sessionId;
}

void main() {
  test('initialize sends the D1 capabilities and reads the agent', () async {
    final (client, agent) = connect(const FakeScenario(authMethods: [
      {'id': 'login', 'name': 'Log in', 'type': 'terminal', 'args': ['--login']},
    ]));
    final r = await client.initialize(clientVersion: '2.0.0');
    expect(agent.params['initialize'], initializeParams(clientVersion: '2.0.0'));
    expect(r.protocolVersion, 1);
    expect(r.capabilities.loadSession, isTrue);
    expect(r.authMethods.single, isA<AuthMethodTerminal>());
    expect(r.agentInfo!.name, 'fake-agent');
  });

  test('every update of a turn arrives before stopReason', () async {
    final (client, _) = connect(FakeScenario(turns: [
      [
        FakeSteps.text('Hel'),
        FakeSteps.text('lo'),
        FakeSteps.tool('t1', 'Read a.txt', kind: 'read', status: 'in_progress'),
        FakeSteps.toolUpdate('t1', status: 'completed'),
      ],
    ]));
    final got = <SessionUpdate>[];
    client.onUpdate = (_, u) => got.add(u);
    final sid = await start(client);
    expect(await client.prompt(sid, const [TextBlock('hi')]), StopReason.endTurn);
    expect(got.map((u) => u.runtimeType.toString()), [
      'AgentMessageChunk',
      'AgentMessageChunk',
      'ToolCallStarted',
      'ToolCallUpdated',
    ]);
  });

  test('the permission handler answers the agent', () async {
    final (client, agent) = connect(FakeScenario(turns: [
      [FakeSteps.permission('t1', 'Edit a.txt')],
    ]));
    PermissionRequest? asked;
    client.onPermission = (r) async {
      asked = r;
      return PermissionSelected(r.options.first.optionId);
    };
    final sid = await start(client);
    expect(await client.prompt(sid, const [TextBlock('go')]), StopReason.endTurn);
    expect(asked!.toolCall.title, 'Edit a.txt');
    expect(asked!.options.map((o) => o.optionId), ['allow-once', 'allow-with-updates', 'reject']);
    expect(agent.received, contains('permission:allow-once'));
  });

  test('without handlers: permission is cancelled, a question declined', () async {
    final (client, agent) = connect(FakeScenario(turns: [
      [
        FakeSteps.ask({'mode': 'form', 'message': 'Pick', 'requestedSchema': {'type': 'object', 'properties': {}}}),
        FakeSteps.permission('t1', 'Run rm -rf build', kind: 'execute'),
      ],
    ]));
    final sid = await start(client);
    expect(await client.prompt(sid, const [TextBlock('go')]), StopReason.cancelled);
    expect(agent.received, containsAllInOrder(['ask:decline', 'permission:cancelled']));
  });

  test('a form answer reaches the agent; elicitation/complete is reported', () async {
    final (client, agent) = connect(FakeScenario(turns: [
      [
        FakeSteps.ask({
          'mode': 'form',
          'message': 'Approach?',
          'requestedSchema': {'type': 'object', 'properties': {'a': {'type': 'string', 'enum': ['x', 'y']}}},
        }),
        FakeSteps.completeAsk('e1'),
      ],
    ]));
    final completed = <String>[];
    client
      ..onElicitation = (r) async => const ElicitAccept({'a': 'y'})
      ..onElicitationComplete = completed.add;
    final sid = await start(client);
    await client.prompt(sid, const [TextBlock('go')]);
    expect(agent.received, contains('ask:accept={"a":"y"}'));
    expect(completed, ['e1']);
  });

  test('cancel: the turn ends with cancelled', () async {
    final (client, agent) = connect(FakeScenario(turns: [
      [FakeSteps.text('working'), FakeSteps.waitCancel()],
    ]));
    final sid = await start(client);
    final turn = client.prompt(sid, const [TextBlock('go')]);
    await pumpEventQueue();
    client.cancel(sid);
    expect(await turn, StopReason.cancelled);
    expect(agent.received, contains('session/cancel'));
  });

  test('auth required: -32000 until authenticate', () async {
    final (client, agent) = connect(const FakeScenario(
      requireAuth: true,
      authMethods: [{'id': 'agent-login', 'name': 'Log in'}],
    ));
    await client.initialize(clientVersion: '2.0.0');
    await expectLater(
      client.newSession(cwd: '/p'),
      throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', JsonRpcError.authRequired)),
    );
    await client.authenticate('agent-login');
    expect((await client.newSession(cwd: '/p')).sessionId, 'sess-1');
    expect(agent.received, containsAllInOrder(['session/new', 'authenticate:agent-login', 'session/new']));
  });

  test('a terminal login is seen through the auth file', () async {
    final dir = Directory.systemTemp.createTempSync('acp_auth');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = '${dir.path}/signed-in';
    final (client, _) = connect(FakeScenario(requireAuth: true, authFile: marker));
    await client.initialize(clientVersion: '2.0.0');
    await expectLater(client.newSession(cwd: '/p'), throwsA(isA<JsonRpcError>()));
    File(marker).writeAsStringSync('');
    expect((await client.newSession(cwd: '/p')).sessionId, 'sess-1');
  });

  test('loadSession replays history before it returns', () async {
    final (client, agent) = connect(FakeScenario(history: [
      {'sessionUpdate': 'user_message_chunk', 'content': {'type': 'text', 'text': 'old question'}},
      {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'old answer'}},
    ]));
    final got = <SessionUpdate>[];
    client.onUpdate = (sid, u) {
      expect(sid, 'old-1');
      got.add(u);
    };
    await client.initialize(clientVersion: '2.0.0');
    await client.loadSession(sessionId: 'old-1', cwd: '/p');
    expect(got, hasLength(2));
    expect(agent.received.last, 'session/load:old-1');
  });

  test('config options and modes', () async {
    final (client, agent) = connect(const FakeScenario(
      configOptions: [
        {'id': 'model', 'name': 'Model', 'type': 'select', 'currentValue': 'a', 'options': [
          {'value': 'a', 'name': 'A'},
          {'value': 'b', 'name': 'B'},
        ]},
        {'id': 'fast', 'name': 'Fast', 'type': 'boolean', 'currentValue': false},
      ],
      modes: {'currentModeId': 'default', 'availableModes': [{'id': 'default', 'name': 'Manual'}, {'id': 'plan', 'name': 'Plan'}]},
    ));
    final modes = <String>[];
    client.onUpdate = (_, u) {
      if (u is ModeUpdated) modes.add(u.currentModeId);
    };
    await client.initialize(clientVersion: '2.0.0');
    final s = await client.newSession(cwd: '/p');
    expect(s.configOptions!.first.currentValue, 'a');
    final after = await client.setConfigOption(s.sessionId, 'model', 'b');
    expect(after!.first.currentValue, 'b');
    expect((await client.setConfigOption(s.sessionId, 'fast', true))![1].currentValue, true);
    expect(agent.params['session/set_config_option']!['type'], 'boolean');
    await client.setMode(s.sessionId, 'plan');
    await pumpEventQueue();
    expect(modes, ['plan']);
  });

  test('listSessions', () async {
    final (client, _) = connect(const FakeScenario(sessions: [
      {'sessionId': 'a', 'cwd': '/p', 'title': 'Fix cart'},
    ]));
    await client.initialize(clientVersion: '2.0.0');
    expect((await client.listSessions(cwd: '/p')).sessions.single.title, 'Fix cart');
  });

  test('the agent exits mid-turn: prompt fails with ConnectionClosed', () async {
    final (client, _) = connect(FakeScenario(turns: [
      [FakeSteps.text('bye'), FakeSteps.exit(3)],
    ]));
    final sid = await start(client);
    await expectLater(client.prompt(sid, const [TextBlock('go')]), throwsA(isA<ConnectionClosed>()));
  });

  test('a prompt error keeps its code', () async {
    final (client, _) = connect(FakeScenario(turns: [
      [FakeSteps.error(-32603, 'model overloaded')],
    ]));
    final sid = await start(client);
    await expectLater(
      client.prompt(sid, const [TextBlock('go')]),
      throwsA(isA<JsonRpcError>().having((e) => e.message, 'message', 'model overloaded')),
    );
  });

  test('toString is redacted', () {
    final (client, _) = connect(const FakeScenario());
    expect(client.toString(), '…');
  });
}
```

`packages/shellx_acp/test/fake_agent_process_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:test/test.dart';

late Directory tmp;

Future<(Process, AcpClient, StringBuffer)> spawn(FakeScenario scenario) async {
  final file = writeScenario(scenario, tmp);
  final p = await Process.start(Platform.resolvedExecutable, fakeAgentArgs(file), workingDirectory: tmp.path);
  final err = StringBuffer();
  p.stderr.transform(utf8.decoder).listen(err.write);
  return (p, AcpClient(JsonRpcConnection(input: p.stdout, output: p.stdin)), err);
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('fake_agent'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('speaks ACP over real pipes and logs what it got to stderr', () async {
    final (p, client, err) = await spawn(FakeScenario(turns: [
      [FakeSteps.text('hello'), FakeSteps.write('out.txt', 'made by agent')],
    ]));
    final got = <SessionUpdate>[];
    client.onUpdate = (_, u) => got.add(u);
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    expect(await client.prompt(sid, const [TextBlock('hi')]), StopReason.endTurn);
    expect((got.single as AgentMessageChunk).content, isA<TextBlock>());
    expect(File('${tmp.path}/out.txt').readAsStringSync(), 'made by agent');
    await client.close(); // closes stdin
    expect(await p.exitCode.timeout(const Duration(seconds: 10)), 0);
    expect(err.toString(), contains('RECV session/prompt:hi'));
  });

  test('a garbage line is skipped; a 10 MiB line arrives whole', () async {
    final (p, client, _) = await spawn(FakeScenario(turns: [
      [FakeSteps.raw('Welcome to my shell profile!'), FakeSteps.bigText(10 << 20)],
    ]));
    final sizes = <int>[];
    client.onUpdate = (_, u) {
      if (u is AgentMessageChunk) sizes.add((u.content as TextBlock).text.length);
    };
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    await client.prompt(sid, const [TextBlock('go')]);
    expect(sizes, [10 << 20]);
    await client.close();
    await p.exitCode.timeout(const Duration(seconds: 10));
  });

  test('exit mid-turn: exit code 3 and the prompt fails', () async {
    final (p, client, _) = await spawn(FakeScenario(turns: [
      [FakeSteps.stderr('fatal: out of tokens'), FakeSteps.exit(3)],
    ]));
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    await expectLater(client.prompt(sid, const [TextBlock('go')]), throwsA(isA<ConnectionClosed>()));
    expect(await p.exitCode.timeout(const Duration(seconds: 10)), 3);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test test/acp_client_test.dart test/fake_agent_process_test.dart`
Expected: compile errors (`AcpClient`, `FakeAgent` not defined).

- [ ] **Step 3: Implement `lib/src/acp_client.dart`**

```dart
import 'acp_content.dart';
import 'acp_elicitation.dart';
import 'acp_json.dart';
import 'acp_requests.dart';
import 'acp_types.dart';
import 'acp_updates.dart';
import 'json_rpc.dart';

/// Answers a `session/request_permission`.
typedef PermissionHandler = Future<PermissionOutcome> Function(PermissionRequest request);

/// Answers an `elicitation/create`.
typedef ElicitationHandler = Future<ElicitationResponse> Function(ElicitationRequest request);

/// The client side of ACP v1 over one connection (spec D1).
///
/// Updates go to [onUpdate] synchronously, in the order they arrive, so all
/// of a turn's updates are delivered before [prompt] completes. With no
/// handler set, a permission request is answered `cancelled` and a question
/// `decline`: nothing is ever allowed on the user's behalf (spec §8.6).
final class AcpClient with Redacted {
  AcpClient(this.connection) {
    connection
      ..onNotification('session/update', (p) {
        final sessionId = readString(p, 'sessionId');
        final update = readMap(p, 'update');
        if (sessionId == null || update == null) return;
        onUpdate?.call(sessionId, SessionUpdate.fromJson(update));
      })
      ..onNotification('elicitation/complete', (p) {
        final id = readString(p, 'elicitationId');
        if (id != null) onElicitationComplete?.call(id);
      })
      ..onRequest('session/request_permission', (p) async {
        final handler = onPermission;
        final outcome = handler == null
            ? const PermissionCancelled()
            : await handler(PermissionRequest.fromJson(p));
        return outcome.toJson();
      })
      ..onRequest('elicitation/create', (p) async {
        final handler = onElicitation;
        final response = handler == null
            ? const ElicitDecline()
            : await handler(ElicitationRequest.fromJson(p));
        return response.toJson();
      });
  }

  final JsonRpcConnection connection;

  void Function(String sessionId, SessionUpdate update)? onUpdate;
  void Function(String elicitationId)? onElicitationComplete;
  PermissionHandler? onPermission;
  ElicitationHandler? onElicitation;

  Future<InitializeResult> initialize({required String clientVersion}) async =>
      InitializeResult.fromJson(
        _map(await connection.request('initialize', initializeParams(clientVersion: clientVersion))),
      );

  /// For [AuthMethodAgent] only; terminal logins run in a run sheet (D8).
  Future<void> authenticate(String methodId) =>
      connection.request('authenticate', authenticateParams(methodId));

  Future<NewSessionResult> newSession({
    required String cwd,
    List<McpServerStdio> mcpServers = const [],
  }) async => NewSessionResult.fromJson(
    _map(await connection.request('session/new', newSessionParams(cwd: cwd, mcpServers: mcpServers))),
  );

  /// The agent replays the session through [onUpdate] before this returns.
  Future<LoadSessionResult> loadSession({
    required String sessionId,
    required String cwd,
    List<McpServerStdio> mcpServers = const [],
  }) async => LoadSessionResult.fromJson(
    _map(
      await connection.request(
        'session/load',
        loadSessionParams(sessionId: sessionId, cwd: cwd, mcpServers: mcpServers),
      ),
    ),
  );

  Future<ListSessionsResult> listSessions({String? cwd, String? cursor}) async =>
      ListSessionsResult.fromJson(
        _map(await connection.request('session/list', listSessionsParams(cwd: cwd, cursor: cursor))),
      );

  Future<StopReason> prompt(String sessionId, List<ContentBlock> prompt) async => StopReason.parse(
    readString(_map(await connection.request('session/prompt', promptParams(sessionId, prompt))), 'stopReason'),
  );

  void cancel(String sessionId) => connection.notify('session/cancel', cancelParams(sessionId));

  /// The options as the agent now has them, or null if it sent none.
  Future<List<ConfigOption>?> setConfigOption(String sessionId, String configId, Object value) async {
    final r = _map(
      await connection.request('session/set_config_option', setConfigOptionParams(sessionId, configId, value)),
    );
    return r['configOptions'] is List ? readConfigOptions(r, 'configOptions') : null;
  }

  /// For agents that only offer legacy `modes` (spec D11).
  Future<void> setMode(String sessionId, String modeId) =>
      connection.request('session/set_mode', setModeParams(sessionId, modeId));

  Future<void> close() => connection.close();

  static JsonMap _map(Object? v) => v is JsonMap ? v : const {};
}
```

Export it from `lib/shellx_acp.dart` (`export 'src/acp_client.dart';`).

- [ ] **Step 4: Implement the fake agent**

`lib/src/testing/fake_steps.dart`:

```dart
import '../json_rpc.dart';

/// Steps for `FakeScenario.turns`: each is a one-key JSON map, so the same
/// script drives the in-process agent and `bin/fake_agent.dart`.
abstract final class FakeSteps {
  /// The Claude adapter's permission options (0.90.0).
  static const claudeOptions = <JsonMap>[
    {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
    {
      'optionId': 'allow-with-updates',
      'name': 'Yes, allow all edits during this session',
      'kind': 'allow_always',
    },
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ];

  /// Sends `session/update` with [update].
  static JsonMap update(JsonMap update) => {'update': update};

  static JsonMap text(String text, {String? messageId}) => update({
    'sessionUpdate': 'agent_message_chunk',
    if (messageId != null) 'messageId': messageId,
    'content': {'type': 'text', 'text': text},
  });

  static JsonMap thought(String text) => update({
    'sessionUpdate': 'agent_thought_chunk',
    'content': {'type': 'text', 'text': text},
  });

  static JsonMap tool(
    String id,
    String title, {
    String kind = 'other',
    String status = 'pending',
    List<JsonMap>? content,
    List<JsonMap>? locations,
    Object? rawInput,
  }) => update({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': title,
    'kind': kind,
    'status': status,
    if (content != null) 'content': content,
    if (locations != null) 'locations': locations,
    if (rawInput != null) 'rawInput': rawInput,
  });

  static JsonMap toolUpdate(String id, {String? status, List<JsonMap>? content, String? title}) => update({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': id,
    if (status != null) 'status': status,
    if (content != null) 'content': content,
    if (title != null) 'title': title,
  });

  /// Tool content: a diff (`oldText` null = new file).
  static JsonMap diff(String path, String? oldText, String newText) =>
      {'type': 'diff', 'path': path, 'oldText': oldText, 'newText': newText};

  /// Tool content: text output.
  static JsonMap output(String text) => {
    'type': 'content',
    'content': {'type': 'text', 'text': text},
  };

  /// [entries]: (content, status) pairs.
  static JsonMap plan(List<(String, String)> entries) => update({
    'sessionUpdate': 'plan',
    'entries': [
      for (final (content, status) in entries) {'content': content, 'priority': 'medium', 'status': status},
    ],
  });

  /// Asks permission and waits; `cancelled` ends the turn as cancelled.
  static JsonMap permission(
    String toolCallId,
    String title, {
    String kind = 'edit',
    List<JsonMap> options = claudeOptions,
  }) => {
    'permission': {
      'toolCall': {'toolCallId': toolCallId, 'title': title, 'kind': kind},
      'options': options,
    },
  };

  /// Sends `elicitation/create` with [request] (+ sessionId) and waits.
  static JsonMap ask(JsonMap request) => {'ask': request};

  static JsonMap completeAsk(String elicitationId) => {'completeAsk': elicitationId};

  /// Waits [ms], or less if the turn is cancelled.
  static JsonMap sleep(int ms) => {'sleep': ms};

  /// Waits for `session/cancel`, then ends the turn as cancelled.
  static JsonMap waitCancel() => {'waitCancel': true};

  /// Never answers the prompt, even after `session/cancel`.
  static JsonMap hang() => {'hang': true};

  /// The agent exits with [code] in the middle of the turn.
  static JsonMap exit(int code) => {'exit': code};

  /// Writes [line] to stdout as it is (not JSON-RPC).
  static JsonMap raw(String line) => {'raw': line};

  /// An agent message of [chars] characters on one line.
  static JsonMap bigText(int chars) => {'bigText': chars};

  static JsonMap stderr(String text) => {'stderr': text};

  /// Writes a file under the agent's cwd, like an agent editing with a tool.
  static JsonMap write(String path, String text) => {
    'write': {'path': path, 'text': text},
  };

  static JsonMap delete(String path) => {'delete': path};

  /// Ends the turn with [reason] (`end_turn`, `refusal`, …).
  static JsonMap stop(String reason) => {'stop': reason};

  /// Answers the prompt with a JSON-RPC error.
  static JsonMap error(int code, String message) => {
    'error': {'code': code, 'message': message},
  };
}
```

`lib/src/testing/fake_agent.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../acp_content.dart';
import '../acp_json.dart';
import '../json_rpc.dart';

/// What a [FakeAgent] does. Plain JSON, so one scenario drives the agent in
/// process and as a process (`bin/fake_agent.dart`).
final class FakeScenario {
  const FakeScenario({
    this.protocolVersion = 1,
    this.loadSession = true,
    this.listSessions = true,
    this.image = true,
    this.authMethods = const [],
    this.requireAuth = false,
    this.authFile,
    this.sessionId = 'sess-1',
    this.configOptions,
    this.modes,
    this.turns = const [],
    this.history = const [],
    this.sessions = const [],
    this.newSessionError,
    this.loadSessionError,
  });

  factory FakeScenario.fromJson(JsonMap j) => FakeScenario(
    protocolVersion: readInt(j, 'protocolVersion') ?? 1,
    loadSession: readBool(j, 'loadSession') ?? true,
    listSessions: readBool(j, 'listSessions') ?? true,
    image: readBool(j, 'image') ?? true,
    authMethods: readMaps(j, 'authMethods').toList(),
    requireAuth: readBool(j, 'requireAuth') ?? false,
    authFile: readString(j, 'authFile'),
    sessionId: readString(j, 'sessionId') ?? 'sess-1',
    configOptions: readList(j, 'configOptions')?.whereType<JsonMap>().toList(),
    modes: readMap(j, 'modes'),
    turns: [
      for (final t in readList(j, 'turns') ?? const <Object?>[])
        if (t is List) t.whereType<JsonMap>().toList(),
    ],
    history: readMaps(j, 'history').toList(),
    sessions: readMaps(j, 'sessions').toList(),
    newSessionError: readMap(j, 'newSessionError'),
    loadSessionError: readMap(j, 'loadSessionError'),
  );

  final int protocolVersion;
  final bool loadSession;
  final bool listSessions;
  final bool image;

  /// Raw ACP `authMethods`.
  final List<JsonMap> authMethods;

  /// `session/new` and `session/load` answer -32000 until signed in.
  final bool requireAuth;

  /// Signed in once this file exists (what a terminal login leaves).
  final String? authFile;
  final String sessionId;
  final List<JsonMap>? configOptions;
  final JsonMap? modes;

  /// Steps per `session/prompt` ([FakeSteps]); the last list repeats.
  final List<List<JsonMap>> turns;

  /// Updates `session/load` replays.
  final List<JsonMap> history;

  /// `session/list` entries.
  final List<JsonMap> sessions;

  /// `{code, message}`: `session/new` fails with it.
  final JsonMap? newSessionError;

  /// `{code, message}`: `session/load` fails with it (e.g. -32002).
  final JsonMap? loadSessionError;

  JsonMap toJson() => {
    'protocolVersion': protocolVersion,
    'loadSession': loadSession,
    'listSessions': listSessions,
    'image': image,
    'authMethods': authMethods,
    'requireAuth': requireAuth,
    if (authFile != null) 'authFile': authFile,
    'sessionId': sessionId,
    if (configOptions != null) 'configOptions': configOptions,
    if (modes != null) 'modes': modes,
    'turns': turns,
    'history': history,
    'sessions': sessions,
    if (newSessionError != null) 'newSessionError': newSessionError,
    if (loadSessionError != null) 'loadSessionError': loadSessionError,
  };
}

/// A scripted ACP agent for tests (spec §7).
final class FakeAgent {
  FakeAgent(
    this.scenario, {
    required Stream<List<int>> input,
    required StreamSink<List<int>> output,
    String? cwd,
    void Function(String line)? stderr,
    void Function(int code)? onExit,
  }) : _output = output,
       _cwd = cwd ?? Directory.current.path,
       _stderr = stderr ?? _ignore,
       _onExit = onExit {
    connection = JsonRpcConnection(input: input, output: output, maxLineChars: 1 << 30);
    _config = [for (final o in scenario.configOptions ?? const <JsonMap>[]) {...o}];
    _modes = scenario.modes == null ? null : {...scenario.modes!};
    connection
      ..onRequest('initialize', _initialize)
      ..onRequest('authenticate', _authenticate)
      ..onRequest('session/new', _newSession)
      ..onRequest('session/load', _loadSession)
      ..onRequest('session/list', _list)
      ..onRequest('session/prompt', _prompt)
      ..onRequest('session/set_config_option', _setConfig)
      ..onRequest('session/set_mode', _setMode)
      ..onNotification('session/cancel', _onCancel);
  }

  static void _ignore(String _) {}

  final FakeScenario scenario;
  late final JsonRpcConnection connection;

  /// What arrived, in order (see the task's list of entries).
  final List<String> received = [];

  /// The last params of each method.
  final Map<String, JsonMap> params = {};

  final StreamSink<List<int>> _output;
  final String _cwd;
  final void Function(String) _stderr;
  final void Function(int code)? _onExit;
  late List<JsonMap> _config;
  JsonMap? _modes;
  var _turn = 0;
  var _authenticated = false;
  var _cancelled = false;
  var _cancel = Completer<void>();

  bool get _signedIn {
    final file = scenario.authFile;
    return _authenticated || (file != null && File(file).existsSync());
  }

  void _record(String entry, [String? method, JsonMap? p]) {
    received.add(entry);
    if (method != null && p != null) params[method] = p;
    _stderr('RECV $entry');
  }

  JsonMap _initialize(JsonMap p) {
    _record('initialize', 'initialize', p);
    return {
      'protocolVersion': scenario.protocolVersion,
      'agentCapabilities': {
        'loadSession': scenario.loadSession,
        'promptCapabilities': {'image': scenario.image, 'embeddedContext': true},
        'sessionCapabilities': {if (scenario.listSessions) 'list': <String, Object?>{}},
      },
      'authMethods': scenario.authMethods,
      'agentInfo': {'name': 'fake-agent', 'title': 'Fake Agent', 'version': '1.0.0'},
    };
  }

  JsonMap _authenticate(JsonMap p) {
    _record('authenticate:${readString(p, 'methodId')}', 'authenticate', p);
    _authenticated = true;
    return {};
  }

  JsonMap _sessionConfig() => {
    if (scenario.configOptions != null) 'configOptions': _config,
    if (_modes != null) 'modes': _modes,
  };

  JsonMap _newSession(JsonMap p) {
    _record('session/new', 'session/new', p);
    final error = scenario.newSessionError;
    if (error != null) {
      throw JsonRpcError(readInt(error, 'code') ?? JsonRpcError.internalError, readString(error, 'message') ?? '');
    }
    if (scenario.requireAuth && !_signedIn) {
      throw const JsonRpcError(JsonRpcError.authRequired, 'Authentication required');
    }
    return {'sessionId': scenario.sessionId, ..._sessionConfig()};
  }

  JsonMap _loadSession(JsonMap p) {
    final id = readString(p, 'sessionId') ?? '';
    _record('session/load:$id', 'session/load', p);
    if (scenario.requireAuth && !_signedIn) {
      throw const JsonRpcError(JsonRpcError.authRequired, 'Authentication required');
    }
    if (!scenario.loadSession) {
      throw const JsonRpcError(JsonRpcError.methodNotFound, 'Method not found');
    }
    final error = scenario.loadSessionError;
    if (error != null) {
      throw JsonRpcError(readInt(error, 'code') ?? JsonRpcError.internalError, readString(error, 'message') ?? '');
    }
    for (final u in scenario.history) {
      connection.notify('session/update', {'sessionId': id, 'update': u});
    }
    return _sessionConfig();
  }

  JsonMap _list(JsonMap p) {
    _record('session/list', 'session/list', p);
    return {'sessions': scenario.sessions};
  }

  Future<JsonMap> _prompt(JsonMap p) async {
    final sessionId = readString(p, 'sessionId') ?? '';
    final text = blockText(readMaps(p, 'prompt').map(ContentBlock.fromJson));
    _record('session/prompt:$text', 'session/prompt', p);
    final steps = scenario.turns.isEmpty
        ? const <JsonMap>[]
        : scenario.turns[math.min(_turn, scenario.turns.length - 1)];
    _turn++;
    _cancelled = false;
    _cancel = Completer<void>();
    for (final step in steps) {
      if (_cancelled) return {'stopReason': 'cancelled'};
      final reason = await _run(step, sessionId);
      if (reason != null) return {'stopReason': reason};
    }
    return {'stopReason': _cancelled ? 'cancelled' : 'end_turn'};
  }

  void _onCancel(JsonMap p) {
    _record('session/cancel', 'session/cancel', p);
    _cancelled = true;
    if (!_cancel.isCompleted) _cancel.complete();
  }

  JsonMap _setConfig(JsonMap p) {
    final id = readString(p, 'configId');
    final value = p['value'];
    _record('session/set_config_option:$id=$value', 'session/set_config_option', p);
    _config = [
      for (final o in _config) o['id'] == id ? {...o, 'currentValue': value} : o,
    ];
    return {'configOptions': _config};
  }

  JsonMap _setMode(JsonMap p) {
    final id = readString(p, 'modeId') ?? '';
    _record('session/set_mode:$id', 'session/set_mode', p);
    final modes = _modes;
    if (modes != null) {
      modes['currentModeId'] = id;
      connection.notify('session/update', {
        'sessionId': readString(p, 'sessionId'),
        'update': {'sessionUpdate': 'current_mode_update', 'currentModeId': id},
      });
    }
    return {};
  }

  /// Runs one step; a non-null result ends the turn with that stop reason.
  Future<String?> _run(JsonMap step, String sessionId) async {
    final value = step.values.first;
    switch (step.keys.first) {
      case 'update':
        connection.notify('session/update', {'sessionId': sessionId, 'update': value});
      case 'permission':
        final s = value! as JsonMap;
        final r = await connection.request('session/request_permission', {
          'sessionId': sessionId,
          'toolCall': s['toolCall'],
          'options': s['options'],
        });
        final outcome = readMap(r is JsonMap ? r : const {}, 'outcome') ?? const <String, Object?>{};
        final kind = readString(outcome, 'outcome');
        _record('permission:${kind == 'selected' ? readString(outcome, 'optionId') : kind}');
        if (kind == 'cancelled') return 'cancelled';
      case 'ask':
        final r = await connection.request('elicitation/create', {'sessionId': sessionId, ...value! as JsonMap});
        final answer = r is JsonMap ? r : const <String, Object?>{};
        final content = readMap(answer, 'content');
        _record('ask:${readString(answer, 'action')}${content == null ? '' : '=${jsonEncode(content)}'}');
        if (_cancelled) return 'cancelled';
      case 'completeAsk':
        connection.notify('elicitation/complete', {'elicitationId': value});
      case 'sleep':
        await Future.any([Future<void>.delayed(Duration(milliseconds: value! as int)), _cancel.future]);
        if (_cancelled) return 'cancelled';
      case 'waitCancel':
        await _cancel.future;
        return 'cancelled';
      case 'hang':
        await Completer<void>().future;
      case 'exit':
        final onExit = _onExit;
        if (onExit != null) {
          onExit(value! as int);
        } else {
          await connection.close();
        }
        await Completer<void>().future;
      case 'raw':
        try {
          _output.add(utf8.encode('$value\n'));
        } on Object {
          // Closed.
        }
      case 'bigText':
        connection.notify('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'x' * (value! as int)},
          },
        });
      case 'stderr':
        _stderr(value! as String);
      case 'write':
        final w = value! as JsonMap;
        File('$_cwd/${w['path']}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(w['text']! as String);
      case 'delete':
        final f = File('$_cwd/$value');
        if (f.existsSync()) f.deleteSync();
      case 'stop':
        return value! as String;
      case 'error':
        final e = value! as JsonMap;
        throw JsonRpcError(readInt(e, 'code') ?? JsonRpcError.internalError, readString(e, 'message') ?? '');
    }
    return null;
  }
}
```

`lib/src/testing/fake_agent_process.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'fake_agent.dart';

/// Arguments for `Platform.resolvedExecutable` (the Dart VM running the
/// test) that start `bin/fake_agent.dart` with [scenarioFile].
List<String> fakeAgentArgs(String scenarioFile) {
  final lib = Isolate.resolvePackageUriSync(Uri.parse('package:shellx_acp/testing.dart'));
  if (lib == null) throw StateError('package:shellx_acp cannot be resolved');
  final config = Isolate.packageConfigSync;
  return [
    if (config != null) '--packages=${config.toFilePath()}',
    lib.resolve('../bin/fake_agent.dart').toFilePath(),
    scenarioFile,
  ];
}

/// Writes [scenario] as JSON into [dir]; returns the file's path.
String writeScenario(FakeScenario scenario, Directory dir, [String name = 'scenario.json']) =>
    (File('${dir.path}${Platform.pathSeparator}$name')..writeAsStringSync(jsonEncode(scenario.toJson()))).path;
```

`lib/testing.dart`:

```dart
/// Test helpers: a scripted ACP agent, in process or as a process (spec §7).
library;

export 'src/testing/fake_agent.dart';
export 'src/testing/fake_agent_process.dart';
export 'src/testing/fake_steps.dart';
```

`bin/fake_agent.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/testing.dart';

/// A scripted ACP agent process for tests:
/// `dart [--packages=…] bin/fake_agent.dart <scenario.json>`.
/// Logs what it receives to stderr (`RECV …`); exits 0 when stdin closes.
Future<void> main(List<String> args) async {
  final scenario = FakeScenario.fromJson(
    jsonDecode(File(args.single).readAsStringSync()) as Map<String, Object?>,
  );
  final agent = FakeAgent(
    scenario,
    input: stdin,
    output: stdout,
    stderr: stderr.writeln,
    onExit: (code) {
      stdout.flush().whenComplete(() => exit(code));
    },
  );
  await agent.connection.done;
  await stdout.done.timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((Object _) {});
  exit(0);
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: all tests pass; `No issues found!`

The process test needs the workspace package config. If `Isolate.packageConfigSync` is null under `dart test`, run the script with `dart run shellx_acp:fake_agent <file>` from `packages/shellx_acp`. Record the change in the ledger.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_acp
git commit -m "feat(v2-ai): ACP client and a scripted fake agent (in process and as a process)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Record a real Claude session (spec §12, Task-1 checks)

The controller runs this task, not a subagent. It uses the user's own Claude login on this Mac through the adapter's own flow; ShellX code never touches credentials. It is a spike: the only code kept is the recorder script and the scrubbed fixture with its test.

**Files:**
- Create: `packages/shellx_acp/tool/record_session.dart` (recorder; run by hand, not by tests)
- Create: `packages/shellx_acp/test/fixtures/sessions/claude-agent-acp-0.90.0.jsonl`
- Test: `packages/shellx_acp/test/recorded_session_test.dart`
- Modify: `docs/superpowers/ledgers/v2-ai.md` (findings for spec §12 items 1–5)

**Interfaces:**
- Consumes: `AcpClient`, `JsonRpcConnection`, the types, `initializeParams`.
- Produces: the fixture. Each line is `{"dir":"out"|"in","msg":{…}}`, where `out` = ShellX → agent. Task 5's replay test reads it.

- [ ] **Step 1: Install the pinned adapter in a scratch prefix**

```bash
SCRATCH=<scratchpad>/rec && mkdir -p "$SCRATCH/agent" "$SCRATCH/project"
npm install --prefix "$SCRATCH/agent" --no-audit --no-fund @agentclientprotocol/claude-agent-acp@0.90.0
node -e "console.log(require('$SCRATCH/agent/node_modules/@agentclientprotocol/claude-agent-acp/package.json').bin)"
```

Expected: install succeeds, and `bin` points at `dist/index.js`. Record the `engines.node` value in the ledger.

- [ ] **Step 2: Write the recorder**

`tool/record_session.dart`: `dart tool/record_session.dart <node> <entry.js> <projectDir> <out.jsonl>`. It:
- starts `node entry.js` with `cwd = projectDir`, the current environment and no shell;
- wraps stdout/stdin in tee streams that append `{"dir", "msg"}` lines (raw JSON as received or sent) to the output;
- runs `AcpClient` through `initialize` → `session/new` (cwd = project) → one prompt:

  > Read hello.txt, then change the word world to ShellX in it, then run the command ls.

- answers every permission with the first `allow_once` option. That is the user's own one-off allowance for this recording; ShellX never does this.
- then runs `session/list`;
- then restarts the adapter and runs `session/load` of the same session (records the replay);
- then closes stdin and waits up to 10 s, then kills.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';

/// Records one real ACP session as JSON lines (spec §12). Run by hand.
Future<void> main(List<String> args) async {
  final [node, entry, project, outPath] = args;
  final out = File(outPath).openWrite();
  void log(String dir, List<int> bytes) {
    for (final line in const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true))) {
      if (line.trim().isEmpty) continue;
      out.writeln(jsonEncode({'dir': dir, 'msg': jsonDecode(line)}));
    }
  }

  Future<(Process, AcpClient)> start() async {
    final p = await Process.start(node, [entry], workingDirectory: project);
    p.stderr.drain<void>();
    final toAgent = StreamController<List<int>>();
    toAgent.stream.listen((b) {
      log('out', b);
      p.stdin.add(b);
    }, onDone: p.stdin.close);
    final fromAgent = p.stdout.map((b) {
      log('in', b);
      return b;
    });
    final client = AcpClient(JsonRpcConnection(input: fromAgent, output: toAgent.sink));
    client.onPermission = (r) async =>
        PermissionSelected(r.options.firstWhere((o) => o.kind == PermissionKind.allowOnce).optionId);
    client.onElicitation = (r) async => const ElicitDecline();
    return (p, client);
  }

  var (p, client) = await start();
  await client.initialize(clientVersion: '0.0.0-record');
  final sid = (await client.newSession(cwd: project)).sessionId;
  final reason = await client.prompt(sid, const [
    TextBlock('Read hello.txt, then change the word world to ShellX in it, then run the command ls.'),
  ]);
  stdout.writeln('stopReason: ${reason.wire}');
  await client.listSessions(cwd: project);
  await client.close();
  await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
    p.kill(ProcessSignal.sigkill);
    return -9;
  });

  (p, client) = await start();
  await client.initialize(clientVersion: '0.0.0-record');
  await client.loadSession(sessionId: sid, cwd: project);
  await client.close();
  await p.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
    p.kill(ProcessSignal.sigkill);
    return -9;
  });
  await out.close();
}
```

- [ ] **Step 3: Record**

```bash
printf 'hello world\n' > "$SCRATCH/project/hello.txt"
cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart tool/record_session.dart \
  "$(which node)" "$SCRATCH/agent/node_modules/@agentclientprotocol/claude-agent-acp/dist/index.js" \
  "$SCRATCH/project" "$SCRATCH/raw.jsonl"
cat "$SCRATCH/project/hello.txt"   # expected: hello ShellX
```

If the adapter answers `session/new` with `-32000` (not signed in on this Mac), **stop**. Do not sign in on the user's behalf. Record "pending manual: needs a signed-in Claude" in the ledger, and do Step 5 with hand-made samples from Task 2's conformance test instead.

- [ ] **Step 4: Scrub and commit the fixture**

With a small script (`python3 -I` or Dart):
- remove every `_meta` key at any depth;
- drop extension messages (any `method` starting with `_`);
- replace the project path with `/project` and `$HOME` with `/home/user`;
- truncate `agentInfo.version` to `0.90.0`;
- replace long text blocks over 2 000 chars with their first 2 000 chars;
- keep everything else.

Then check:

```bash
grep -c . fixtures/sessions/claude-agent-acp-0.90.0.jsonl
grep -n -i -E "$(whoami)|@[a-z0-9.-]+\.[a-z]{2,}|sk-ant|Bearer" fixtures/sessions/claude-agent-acp-0.90.0.jsonl || echo clean
```

Expected: `clean`. Read the whole file before committing (spec §5).

- [ ] **Step 5: Write the replay test**

`test/recorded_session_test.dart` (skips with a reason when the fixture is absent):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

void main() {
  final file = File('test/fixtures/sessions/claude-agent-acp-0.90.0.jsonl');
  final lines = file.existsSync()
      ? [for (final l in file.readAsLinesSync()) jsonDecode(l) as JsonMap]
      : <JsonMap>[];

  test('every update of the real Claude session parses', () {
    final kinds = <String>{};
    for (final l in lines.where((l) => l['dir'] == 'in')) {
      final msg = l['msg']! as JsonMap;
      if (msg['method'] == 'session/update') {
        final update = (msg['params']! as JsonMap)['update']! as JsonMap;
        final parsed = SessionUpdate.fromJson(update);
        kinds.add(update['sessionUpdate']! as String);
        expect(parsed, isNot(isA<UnknownUpdate>()), reason: '${update['sessionUpdate']}');
      }
      if (msg['method'] == 'session/request_permission') {
        final r = PermissionRequest.fromJson(msg['params']! as JsonMap);
        expect(r.options.map((o) => o.kind), contains(PermissionKind.allowOnce));
      }
    }
    expect(kinds, containsAll(['agent_message_chunk', 'tool_call', 'tool_call_update']));
  }, skip: lines.isEmpty ? 'no recorded session (ledger: pending manual)' : false);

  test('the tool kinds of the real session map to cards', () {
    final toolKinds = <ToolKind?>{
      for (final l in lines.where((l) => l['dir'] == 'in'))
        if ((l['msg']! as JsonMap)['method'] == 'session/update')
          if (SessionUpdate.fromJson(((l['msg']! as JsonMap)['params']! as JsonMap)['update']! as JsonMap)
              case ToolCallStarted(:final fields))
            fields.kind,
    };
    expect(toolKinds, containsAll([ToolKind.read, ToolKind.edit, ToolKind.execute]));
  }, skip: lines.isEmpty ? 'no recorded session (ledger: pending manual)' : false);
}
```

Run: `cd packages/shellx_acp && ~/fvm/versions/3.41.4/bin/dart test test/recorded_session_test.dart`
Expected: pass (or skip with the ledger note).

If a real update fails to parse, fix the type in Task 2's file and add the shape to `conformance_test.dart`. Never loosen the test.

- [ ] **Step 6: Ledger findings (spec §12)**

Record:
1. the recording result, with stop reason and update kinds seen;
2. Codex: not installed here, so pending manual (spec §9);
3. D17 Flutter packages: moved to plan V2-1b;
4. Gemini without `fs/*`: pending manual (not installed);
5. elicitation form for multiple choice: seen or not seen in the recording.

If the recording contradicts the spec, fix the spec first (spec §12) and note it.

- [ ] **Step 7: Commit**

```bash
git add packages/shellx_acp/tool packages/shellx_acp/test docs/superpowers/ledgers/v2-ai.md
git commit -m "test(v2-ai): replay a recorded Claude adapter 0.90.0 session through the ACP types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `shellx_ai` session model (timeline reducer and session state)

**Files:**
- Modify: `pubspec.yaml` (root: add `packages/shellx_ai` to the workspace)
- Modify: `.github/workflows/windows-check.yml` (job `dart`: add a `shellx_ai` step like the `shellx_acp` one)
- Create: `packages/shellx_ai/pubspec.yaml`
- Create: `packages/shellx_ai/lib/shellx_ai.dart`
- Create: `packages/shellx_ai/lib/src/model/changes.dart`
- Create: `packages/shellx_ai/lib/src/model/notices.dart`
- Create: `packages/shellx_ai/lib/src/model/timeline.dart`
- Create: `packages/shellx_ai/lib/src/model/session_state.dart`
- Test: `packages/shellx_ai/test/model/timeline_test.dart`, `test/model/session_state_test.dart`, `test/model/recorded_replay_test.dart`

**Interfaces:**
- Consumes: `package:shellx_acp/shellx_acp.dart` (Tasks 1–3); the fixture from Task 4 (optional).
- Produces (`package:shellx_ai/shellx_ai.dart`, no `dart:io`; every type `toString()` → `'…'`):
  - changes and notices:
    - `enum ChangeKind { added, modified, deleted }`
    - `FileChange({path, kind, added, removed}) + binary`
    - `Checkpoint({commit, tree})`
    - `enum UndoOff { noGit, noCommandLineTools, gitTooOld, tooManyFiles, tooSlow, failed }`
    - `enum StartFailure { spawn, timeout, protocol, session }`
    - `sealed AiNotice`, with variants:
      - `LoginNeeded(methods)`
      - `NodeMissing({required, found})`
      - `AgentNotInstalled({canInstall})`
      - `AgentMissing(command, {shimOnly})`
      - `AgentExited(exitCode)`
      - `AgentOutputInvalid(ConnectionCloseReason reason)`
      - `StartFailed(reason)`
      - `CannotResume()`
      - `FolderMissing()`
      - `UndoUnavailable(reason, {turnOnly})`
  - timeline items:
    - `sealed TimelineItem {turn; rev}`
    - `UserItem(turn, blocks, {messageId}) + text`
    - `sealed StreamedTextItem(turn, {messageId}) + text/append`, with `AgentTextItem` and `ThoughtItem`
    - `enum ToolEnd { completed, failed, stopped }`
    - `ToolItem(turn, toolCallId, fields, {startedAt})`, with `{fields, endedAt, end, awaitingPermission, permissionAnswer, permissionCancelled}`
    - `AskItem(turn, id, request, {autoDeclined})`, with `{response, completed}`
    - `enum TurnOutcome { finished, cancelled, interrupted, failed }`
    - `TurnEndItem(turn, {outcome, elapsed, stopReason, error, checkpoint, afterTree, changes})`
    - `NoticeItem(turn, notice) + resolved`
  - `final class Timeline`:
    - fields: `items`, `turn`
    - lookup and add: `ToolItem? tool(String id)`, `void add(TimelineItem)`
    - updates: `UserItem startTurn(List<ContentBlock>, {String? messageId})`, `bool apply(SessionUpdate, DateTime at)`, `ToolItem toolFor(String id, ToolCallFields, DateTime at)`
    - `void stopOpenTools(DateTime at)`
  - session types:
    - `enum AgentPhase { stopped, starting, needsAuth, ready, running, failed }`
    - `ActiveTurn(index, startedAt)`, with `{cancelRequested, canForceStop, checkpoint}`
    - `PendingPermission(id, request, item) + title`
    - `PendingAsk(id, item) + request`
    - `QueuedPrompt(id, blocks) + text`
  - `final class AiSessionState`:
    - constructor: `AiSessionState({required String agentId, required String agentName, required String cwd})`.
    - state fields:
      - session: `phase`, `sessionId`, `title`, `agent`, `cwd`;
      - content: `timeline`, `plan`, `commands`, `configOptions`, `modes`, `usage`;
      - turn and questions: `turn`, `permissions`, `asks`, `queue`;
      - listeners: `version`.
    - `static const maxQueue = 5`.
    - getters: `capabilities`, `authMethods`, `needsInput`, `currentPermission`, `currentAsk`, `label`.
    - listeners and agent: `addListener`, `removeListener`, `touch()`, `setPhase(AgentPhase)`, `setAgent(InitializeResult)`, `setSession(String id, {configOptions, modes})`.
    - updates: `applyUpdate(SessionUpdate, DateTime at, {bool history = false, bool timelineToo = true})`.
    - turns: `ActiveTurn beginTurn(List<ContentBlock>, DateTime at)`, `TurnEndItem? endTurn({required TurnOutcome outcome, required DateTime at, StopReason? stopReason, String? error, String? afterTree, List<FileChange>? changes})`.
    - permissions: `PendingPermission addPermission(PermissionRequest, DateTime at)`, `void resolvePermission(int id, PermissionOutcome)`.
    - questions: `PendingAsk? addAsk(ElicitationRequest, {bool autoDeclined = false})`, `void resolveAsk(int id, ElicitationResponse)`, `void completeUrlAsk(String elicitationId)`.
    - notices: `NoticeItem addNotice(AiNotice)`, `void resolveNotices(bool Function(AiNotice) test)`.
    - queue: `QueuedPrompt? enqueue(List<ContentBlock>)`, `void removeQueued(int id)`, `QueuedPrompt? takeQueued()`.

- [ ] **Step 1: Scaffold the package**

`packages/shellx_ai/pubspec.yaml`:

```yaml
name: shellx_ai
description: >-
  ShellX AI sessions in pure Dart: the session model shared by the desktop
  and the phone, and the desktop host (agent processes, checkpoints, runtime).
version: 1.0.0
publish_to: none
resolution: workspace
environment:
  sdk: ^3.11.0
dependencies:
  shellx_acp: any
dev_dependencies:
  test: ^1.30.0
```

Root `pubspec.yaml`: add `  - packages/shellx_ai` after `packages/shellx_acp`. CI: add the step

```yaml
      - name: shellx_ai
        working-directory: packages/shellx_ai
        run: dart test
```

Run `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the root.

`lib/shellx_ai.dart`:

```dart
/// The AI session model shared by the desktop and the phone (spec D9): the
/// timeline reducer and the session state. No `dart:io`.
library;

export 'src/model/changes.dart';
export 'src/model/notices.dart';
export 'src/model/session_state.dart';
export 'src/model/timeline.dart';
```

- [ ] **Step 2: Write the failing tests**

`test/model/timeline_test.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 14, 9);
SessionUpdate u(JsonMap j) => SessionUpdate.fromJson(j);
JsonMap text(String s, {String kind = 'agent_message_chunk', String? id}) => {
  'sessionUpdate': kind,
  if (id != null) 'messageId': id,
  'content': {'type': 'text', 'text': s},
};

void main() {
  late Timeline tl;
  setUp(() => tl = Timeline()..startTurn(const [TextBlock('fix it')]));

  test('message chunks merge; a tool call or a new messageId splits them', () {
    for (final s in ['Hel', 'lo']) {
      tl.apply(u(text(s)), t0);
    }
    tl.apply(u({'sessionUpdate': 'tool_call', 'toolCallId': 't1', 'title': 'Read a', 'kind': 'read'}), t0);
    tl.apply(u(text('Done')), t0);
    tl.apply(u(text(' twice', id: 'm2')), t0);
    final texts = tl.items.whereType<AgentTextItem>().map((i) => i.text).toList();
    expect(texts, ['Hello', 'Done', ' twice']);
  });

  test('thoughts merge apart from text', () {
    tl.apply(u(text('think ', kind: 'agent_thought_chunk')), t0);
    tl.apply(u(text('more', kind: 'agent_thought_chunk')), t0);
    tl.apply(u(text('answer')), t0);
    expect(tl.items.whereType<ThoughtItem>().single.text, 'think more');
    expect(tl.items.last, isA<AgentTextItem>());
  });

  test('a tool update merges into its card; content is replaced; completed ends it', () {
    tl.apply(u({
      'sessionUpdate': 'tool_call',
      'toolCallId': 't1',
      'title': 'Edit a.txt',
      'kind': 'edit',
      'status': 'in_progress',
      'content': [{'type': 'diff', 'path': '/p/a.txt', 'oldText': 'a', 'newText': 'b'}],
    }), t0);
    final later = t0.add(const Duration(seconds: 2));
    tl.apply(u({'sessionUpdate': 'tool_call_update', 'toolCallId': 't1', 'status': 'completed', 'content': []}), later);
    final card = tl.tool('t1')!;
    expect(tl.items.whereType<ToolItem>(), hasLength(1));
    expect(card.fields.title, 'Edit a.txt');
    expect(card.fields.content, isEmpty);
    expect(card.end, ToolEnd.completed);
    expect(card.endedAt, later);
    expect(card.rev, greaterThan(1));
  });

  test('an update for an unknown id creates the card; a resent tool_call does not duplicate', () {
    tl.apply(u({'sessionUpdate': 'tool_call_update', 'toolCallId': 'x', 'status': 'failed'}), t0);
    tl.apply(u({'sessionUpdate': 'tool_call', 'toolCallId': 'x', 'title': 'Run make', 'kind': 'execute'}), t0);
    expect(tl.items.whereType<ToolItem>().single.fields.title, 'Run make');
    expect(tl.tool('x')!.end, ToolEnd.failed);
  });

  test('replayed user messages start turns', () {
    final replay = Timeline();
    replay.apply(u(text('q1', kind: 'user_message_chunk')), t0);
    replay.apply(u(text('a1')), t0);
    replay.apply(u(text('q2', kind: 'user_message_chunk')), t0);
    replay.apply(u(text('a2')), t0);
    expect(replay.items.map((i) => '${i.runtimeType}:${i.turn}'), [
      'UserItem:1',
      'AgentTextItem:1',
      'UserItem:2',
      'AgentTextItem:2',
    ]);
    expect(replay.turn, 2);
  });

  test('stopOpenTools stops only open calls', () {
    tl.apply(u({'sessionUpdate': 'tool_call', 'toolCallId': 'a', 'title': 'A', 'status': 'completed'}), t0);
    tl.apply(u({'sessionUpdate': 'tool_call', 'toolCallId': 'b', 'title': 'B', 'status': 'in_progress'}), t0);
    tl.stopOpenTools(t0);
    expect(tl.tool('a')!.end, ToolEnd.completed);
    expect(tl.tool('b')!.end, ToolEnd.stopped);
  });

  test('images in agent text are skipped; resource links become markdown links', () {
    tl.apply(u({'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'image', 'data': '', 'mimeType': 'image/png'}}), t0);
    expect(tl.items.whereType<AgentTextItem>(), isEmpty);
    tl.apply(u({'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'resource_link', 'uri': 'file:///p/a.dart', 'name': 'a.dart'}}), t0);
    expect(tl.items.whereType<AgentTextItem>().single.text, '[a.dart](file:///p/a.dart)');
  });

  test('plan and usage are not timeline updates', () {
    expect(tl.apply(u({'sessionUpdate': 'plan', 'entries': []}), t0), isFalse);
    expect(tl.apply(u({'sessionUpdate': 'usage_update', 'used': 1, 'size': 2}), t0), isFalse);
  });

  test('toString is redacted', () {
    tl.apply(u(text('secret')), t0);
    for (final i in tl.items) {
      expect(i.toString(), '…');
    }
    expect(tl.toString(), '…');
  });
}
```

`test/model/session_state_test.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 14, 9);
AiSessionState fresh() => AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');
PermissionRequest perm(String toolCallId, {String? title}) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': toolCallId, if (title != null) 'title': title},
  'options': [
    {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

void main() {
  group('label (spec D2)', () {
    test('the session title wins', () {
      final s = fresh()..beginTurn(const [TextBlock('first prompt')], t0);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'session_info_update', 'title': 'Fix cart'}), t0);
      expect(s.label, 'Fix cart');
    });

    test('else the first prompt, spaces collapsed, cut at 40 characters', () {
      final s = fresh()..beginTurn(const [TextBlock('  Fix   the cart total when a second item is added  ')], t0);
      expect(s.label, 'Fix the cart total when a second item is…');
    });

    test('the cut never splits a character', () {
      final s = fresh()..beginTurn([TextBlock('😀' * 50)], t0);
      expect(s.label!.runes.length, 41);
      expect(s.label!.endsWith('😀…'), isTrue);
    });

    test('else null ("Phiên AI mới" in the UI); a null title clears', () {
      final s = fresh();
      expect(s.label, isNull);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'session_info_update', 'title': 'T'}), t0);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'session_info_update', 'title': null}), t0);
      expect(s.label, isNull);
    });
  });

  test('session-wide updates; each change bumps the version and calls listeners', () {
    final s = fresh()
      ..setSession('s1', modes: const SessionModes(currentModeId: 'default', available: []));
    var calls = 0;
    s.addListener(() => calls++);
    final v = s.version;
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'plan', 'entries': [{'content': 'Read', 'priority': 'high', 'status': 'pending'}]}), t0);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'available_commands_update', 'availableCommands': [{'name': 'review', 'description': 'r'}]}), t0);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'current_mode_update', 'currentModeId': 'plan'}), t0);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'usage_update', 'used': 50, 'size': 100}), t0);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'config_option_update', 'configOptions': []}), t0);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'something_new'}), t0);
    expect(s.plan.single.content, 'Read');
    expect(s.commands.single.name, 'review');
    expect(s.modes!.currentModeId, 'plan');
    expect(s.usage!.percent, 50);
    expect(s.configOptions, isEmpty);
    expect(s.version, v + 5, reason: 'the unknown update changes nothing');
    expect(calls, 5);
  });

  test('our own prompt is not doubled by a user_message_chunk during the turn', () {
    final s = fresh()..beginTurn(const [TextBlock('hi')], t0);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'user_message_chunk', 'content': {'type': 'text', 'text': 'hi'}}), t0);
    expect(s.timeline.items.whereType<UserItem>(), hasLength(1));
  });

  test('timelineToo: false keeps session-wide updates only', () {
    final s = fresh();
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'x'}}), t0, timelineToo: false);
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'usage_update', 'used': 1, 'size': 4}), t0, timelineToo: false);
    expect(s.timeline.items, isEmpty);
    expect(s.usage!.used, 1);
  });

  group('turns', () {
    test('begin and end: phase, elapsed, checkpoint, outcome', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      final turn = s.beginTurn(const [TextBlock('go')], t0);
      turn.checkpoint = const Checkpoint(commit: 'c1', tree: 'tr1');
      expect(s.phase, AgentPhase.running);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': 'a', 'title': 'A', 'status': 'in_progress'}), t0);
      final end = s.endTurn(outcome: TurnOutcome.cancelled, at: t0.add(const Duration(seconds: 41)), stopReason: StopReason.cancelled)!;
      expect(end.turn, 1);
      expect(end.elapsed, const Duration(seconds: 41));
      expect(end.checkpoint!.commit, 'c1');
      expect(s.timeline.tool('a')!.end, ToolEnd.stopped);
      expect(s.turn, isNull);
      expect(s.phase, AgentPhase.ready);
      expect(s.endTurn(outcome: TurnOutcome.finished, at: t0), isNull);
    });

    test('a finished turn leaves open tools open (background work may update them)', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': 'bg', 'title': 'npm run dev', 'status': 'in_progress'}), t0);
      s.endTurn(outcome: TurnOutcome.finished, at: t0, stopReason: StopReason.endTurn);
      expect(s.timeline.tool('bg')!.end, isNull);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'tool_call_update', 'toolCallId': 'bg', 'status': 'completed'}), t0);
      expect(s.timeline.tool('bg')!.end, ToolEnd.completed);
    });
  });

  group('permissions (spec D10)', () {
    test('one at a time, in order; answers land on the card', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': 'e1', 'title': 'Edit a.txt', 'kind': 'edit'}), t0);
      final p1 = s.addPermission(perm('e1'), t0);
      final p2 = s.addPermission(perm('x9', title: 'Run rm -rf build'), t0);
      expect(s.needsInput, isTrue);
      expect(s.currentPermission, same(p1));
      expect(p1.title, 'Edit a.txt');
      expect(p2.title, 'Run rm -rf build', reason: 'no card yet: the request title (spec §6)');
      expect(s.timeline.tool('x9'), isNotNull);
      expect(p1.item.awaitingPermission, isTrue);
      s.resolvePermission(p1.id, const PermissionSelected('allow-once'));
      expect(p1.item.permissionAnswer!.name, 'Yes');
      expect(p1.item.awaitingPermission, isFalse);
      expect(s.currentPermission, same(p2));
      s.resolvePermission(p2.id, const PermissionCancelled());
      expect(p2.item.permissionCancelled, isTrue);
      expect(s.needsInput, isFalse);
      s.resolvePermission(p2.id, const PermissionCancelled()); // twice: no-op
    });
  });

  group('questions (spec D22)', () {
    test('pending, answered, url completed, auto-declined', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      final form = ElicitationRequest.fromJson({'mode': 'form', 'message': 'Pick', 'requestedSchema': {'type': 'object', 'properties': {}}});
      final a = s.addAsk(form)!;
      expect(s.currentAsk, same(a));
      expect(s.needsInput, isTrue);
      s.resolveAsk(a.id, const ElicitAccept({}));
      expect(a.item.response, isA<ElicitAccept>());
      expect(s.needsInput, isFalse);

      final url = s.addAsk(ElicitationRequest.fromJson({'mode': 'url', 'message': 'Sign in', 'elicitationId': 'e1', 'url': 'https://x.test'}))!;
      s.resolveAsk(url.id, const ElicitAccept());
      s.completeUrlAsk('e1');
      expect(url.item.completed, isTrue);

      final odd = ElicitationRequest.fromJson({'mode': 'form', 'message': 'File?', 'requestedSchema': {'type': 'object', 'properties': {'f': {'type': 'blob'}}}});
      expect(s.addAsk(odd, autoDeclined: true), isNull);
      final card = s.timeline.items.whereType<AskItem>().last;
      expect(card.autoDeclined, isTrue);
      expect(card.response, isA<ElicitDecline>());
    });
  });

  test('queue holds at most 5, in order (spec D16)', () {
    final s = fresh();
    final ids = [for (var i = 0; i < 5; i++) s.enqueue([TextBlock('q$i')])!.id];
    expect(s.enqueue(const [TextBlock('q5')]), isNull);
    s.removeQueued(ids[1]);
    expect(s.takeQueued()!.text, 'q0');
    expect(s.takeQueued()!.text, 'q2');
    expect(s.queue.map((q) => q.text), ['q3', 'q4']);
  });

  test('notices are added and folded', () {
    final s = fresh();
    s.addNotice(const LoginNeeded([]));
    s.addNotice(const AgentExited(3));
    s.resolveNotices((n) => n is LoginNeeded);
    final cards = s.timeline.items.whereType<NoticeItem>().toList();
    expect(cards.map((c) => c.resolved), [true, false]);
  });

  test('toString is redacted', () {
    final s = fresh()..beginTurn(const [TextBlock('secret')], t0);
    final p = s.addPermission(perm('a', title: 'secret'), t0);
    expect([s, s.turn, p, s.enqueue(const [TextBlock('secret')]), const FileChange(path: 'secret', kind: ChangeKind.added)].map((o) => o.toString()).toSet(), {'…'});
  });
}
```

`test/model/recorded_replay_test.dart` (uses Task 4's fixture; skips without it):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

void main() {
  final file = File('../shellx_acp/test/fixtures/sessions/claude-agent-acp-0.90.0.jsonl');
  final lines = file.existsSync() ? [for (final l in file.readAsLinesSync()) jsonDecode(l) as JsonMap] : <JsonMap>[];
  final skip = lines.isEmpty ? 'no recorded session (ledger)' : false;

  // The recording holds two runs: the live turn, then a restart with session/load.
  final secondInit = lines.indexWhere((l) => l['dir'] == 'out' && (l['msg']! as JsonMap)['method'] == 'initialize', 1);
  Iterable<SessionUpdate> updates(Iterable<JsonMap> part) sync* {
    for (final l in part) {
      final msg = l['msg']! as JsonMap;
      if (l['dir'] == 'in' && msg['method'] == 'session/update') {
        yield SessionUpdate.fromJson((msg['params']! as JsonMap)['update']! as JsonMap);
      }
    }
  }

  test('the live turn draws text and finished read, edit and execute cards', () {
    final s = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/project')
      ..beginTurn(const [TextBlock('Read hello.txt…')], DateTime.utc(2026));
    for (final u in updates(lines.take(secondInit < 0 ? lines.length : secondInit))) {
      s.applyUpdate(u, DateTime.utc(2026));
    }
    final tools = s.timeline.items.whereType<ToolItem>().toList();
    expect(tools.map((t) => t.fields.kind), containsAll([ToolKind.read, ToolKind.edit, ToolKind.execute]));
    expect(tools.every((t) => t.end == ToolEnd.completed), isTrue);
    expect(s.timeline.items.whereType<AgentTextItem>().map((t) => t.text).join(), isNotEmpty);
  }, skip: skip);

  test('session/load replays the prompt as the first turn', () {
    final s = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/project');
    for (final u in updates(lines.skip(secondInit < 0 ? lines.length : secondInit))) {
      s.applyUpdate(u, DateTime.utc(2026), history: true);
    }
    expect(s.timeline.items.whereType<UserItem>().first.text, contains('hello.txt'));
  }, skip: skip);
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/model`
Expected: compile errors.

- [ ] **Step 4: Implement the model**

`lib/src/model/changes.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';

enum ChangeKind { added, modified, deleted }

/// One file changed since a checkpoint (spec §4.4).
final class FileChange with Redacted {
  const FileChange({required this.path, required this.kind, this.added, this.removed});

  /// Relative to the project, with `/` separators.
  final String path;
  final ChangeKind kind;

  /// Lines added and removed; null for a binary file.
  final int? added;
  final int? removed;

  bool get binary => added == null;
}

/// The project as it was before a turn (spec D12).
final class Checkpoint with Redacted {
  const Checkpoint({required this.commit, required this.tree});

  final String commit;
  final String tree;
}

/// Why undo is off for a project (spec §6, `aiNoUndo`).
enum UndoOff { noGit, noCommandLineTools, gitTooOld, tooManyFiles, tooSlow, failed }
```

`lib/src/model/notices.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';

import 'changes.dart';

/// Why an agent could not start (spec §6).
enum StartFailure { spawn, timeout, protocol, session }

/// A card in the conversation (spec §4.5).
sealed class AiNotice with Redacted {
  const AiNotice();
}

/// `-32000`: sign in with one of [methods] (spec D8).
final class LoginNeeded extends AiNotice {
  const LoginNeeded(this.methods);

  final List<AuthMethod> methods;
}

/// The agent needs Node [required] or newer; [found] is what is installed.
final class NodeMissing extends AiNotice {
  const NodeMissing({required this.required, this.found});

  final int required;
  final String? found;
}

/// The adapter is not installed (or not at the pinned version).
final class AgentNotInstalled extends AiNotice {
  const AgentNotInstalled({this.canInstall = true});

  /// False when npm was not found next to node.
  final bool canInstall;
}

/// A PATH or custom agent command was not found.
final class AgentMissing extends AiNotice {
  const AgentMissing(this.command, {this.shimOnly = false});

  final String command;

  /// Found only as a `.cmd`/`.bat` shim on Windows, which ShellX does not run.
  final bool shimOnly;
}

final class AgentExited extends AiNotice {
  const AgentExited(this.exitCode);

  final int exitCode;
}

/// The agent wrote output ShellX cannot read: more than 20 bad lines in a
/// row, or one line over 64 MiB (spec §6). ShellX stopped it.
final class AgentOutputInvalid extends AiNotice {
  const AgentOutputInvalid(this.reason);

  final ConnectionCloseReason reason;
}

final class StartFailed extends AiNotice {
  const StartFailed(this.reason);

  final StartFailure reason;
}

/// The agent cannot load the old session; a new one was started (D14).
final class CannotResume extends AiNotice {
  const CannotResume();
}

final class FolderMissing extends AiNotice {
  const FolderMissing();
}

/// Undo is off for the project, or only for this turn when [turnOnly].
final class UndoUnavailable extends AiNotice {
  const UndoUnavailable(this.reason, {this.turnOnly = false});

  final UndoOff reason;
  final bool turnOnly;
}
```

`lib/src/model/timeline.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';

import 'changes.dart';
import 'notices.dart';

/// One entry of the conversation. Items are mutable; [rev] goes up on each
/// change so a view redraws only what changed.
sealed class TimelineItem with Redacted {
  TimelineItem(this.turn);

  /// The turn the item belongs to (0 = before the first prompt).
  final int turn;
  int rev = 0;
}

final class UserItem extends TimelineItem {
  UserItem(super.turn, List<ContentBlock> blocks, {this.messageId}) : blocks = [...blocks];

  final List<ContentBlock> blocks;
  final String? messageId;

  String get text => blockText(blocks);
}

/// Text that arrives in chunks and is merged (spec D9).
sealed class StreamedTextItem extends TimelineItem {
  StreamedTextItem(super.turn, {this.messageId});

  final String? messageId;
  final _text = StringBuffer();

  String get text => _text.toString();

  void append(String s) {
    _text.write(s);
    rev++;
  }
}

/// Agent text (`agent_message_chunk`).
final class AgentTextItem extends StreamedTextItem {
  AgentTextItem(super.turn, {super.messageId});
}

/// A thought (`agent_thought_chunk`), folded by default (spec §4.2).
final class ThoughtItem extends StreamedTextItem {
  ThoughtItem(super.turn, {super.messageId});
}

/// How a tool call ended.
enum ToolEnd {
  completed,
  failed,

  /// The turn was cancelled or the agent stopped while it ran.
  stopped,
}

/// One tool call card, updated in place by `toolCallId` (spec D9, §4.2).
final class ToolItem extends TimelineItem {
  ToolItem(super.turn, this.toolCallId, this.fields, {required this.startedAt});

  final String toolCallId;
  ToolCallFields fields;
  final DateTime startedAt;
  DateTime? endedAt;
  ToolEnd? end;

  /// A permission request for this call is waiting.
  bool awaitingPermission = false;

  /// What the user picked ("Bạn chọn: Cho phép (Yes)").
  PermissionOption? permissionAnswer;

  /// The turn was cancelled while the request was open.
  bool permissionCancelled = false;
}

/// A question from the agent (spec D22).
final class AskItem extends TimelineItem {
  AskItem(super.turn, this.id, this.request, {this.autoDeclined = false});

  final int id;
  final ElicitationRequest request;

  /// Declined without asking: the form uses a type ShellX cannot show.
  final bool autoDeclined;
  ElicitationResponse? response;

  /// A URL question the agent reported done (`elicitation/complete`).
  bool completed = false;
}

enum TurnOutcome {
  /// The agent ended the turn (any stop reason but `cancelled`).
  finished,
  cancelled,

  /// The agent process ended during the turn.
  interrupted,

  /// `session/prompt` answered an error.
  failed,
}

/// The summary card at the end of a turn (spec §4.2).
final class TurnEndItem extends TimelineItem {
  TurnEndItem(
    super.turn, {
    required this.outcome,
    required this.elapsed,
    this.stopReason,
    this.error,
    this.checkpoint,
    this.afterTree,
    this.changes,
  });

  final TurnOutcome outcome;
  final Duration elapsed;
  final StopReason? stopReason;

  /// The agent's error message: shown, never logged.
  final String? error;

  /// The project before the turn; null when undo was off.
  final Checkpoint? checkpoint;

  /// The project right after the turn ("đã sửa sau lượt" compares to it).
  final String? afterTree;

  /// What the turn changed (checkpoint → after); null without checkpoint.
  final List<FileChange>? changes;
}

final class NoticeItem extends TimelineItem {
  NoticeItem(super.turn, this.notice);

  final AiNotice notice;

  /// The problem went away; the card may fold.
  bool resolved = false;
}

/// The conversation of one session (spec D9).
final class Timeline with Redacted {
  final List<TimelineItem> items = [];
  final Map<String, ToolItem> _tools = {};

  /// The current turn; a prompt or a replayed user message starts the next.
  int turn = 0;

  ToolItem? tool(String toolCallId) => _tools[toolCallId];

  void add(TimelineItem item) => items.add(item);

  UserItem startTurn(List<ContentBlock> prompt, {String? messageId}) {
    turn++;
    final item = UserItem(turn, prompt, messageId: messageId);
    items.add(item);
    return item;
  }

  /// Applies a message, thought or tool update; false for other kinds.
  bool apply(SessionUpdate update, DateTime at) {
    switch (update) {
      case UserMessageChunk(:final content, :final messageId):
        final last = items.isEmpty ? null : items.last;
        if (last is UserItem && last.turn == turn && last.messageId == messageId) {
          last.blocks.add(content);
          last.rev++;
        } else {
          startTurn([content], messageId: messageId);
        }
        return true;
      case AgentMessageChunk(:final content, :final messageId):
        _appendText(content, messageId, thought: false);
        return true;
      case AgentThoughtChunk(:final content, :final messageId):
        _appendText(content, messageId, thought: true);
        return true;
      case ToolCallStarted(:final toolCallId, :final fields):
      case ToolCallUpdated(:final toolCallId, :final fields):
        toolFor(toolCallId, fields, at);
        return true;
      default:
        return false;
    }
  }

  /// The card of [toolCallId] with [fields] merged in; a new card goes at
  /// the end of the timeline.
  ToolItem toolFor(String toolCallId, ToolCallFields fields, DateTime at) {
    var item = _tools[toolCallId];
    if (item == null) {
      item = ToolItem(turn, toolCallId, fields, startedAt: at);
      _tools[toolCallId] = item;
      items.add(item);
    } else {
      item.fields = item.fields.merge(fields);
    }
    switch (fields.status) {
      case ToolCallStatus.completed:
        item.end = ToolEnd.completed;
        item.endedAt ??= at;
      case ToolCallStatus.failed:
        item.end = ToolEnd.failed;
        item.endedAt ??= at;
      default:
        break;
    }
    item.rev++;
    return item;
  }

  /// Marks every call that has not ended as stopped.
  void stopOpenTools(DateTime at) {
    for (final t in _tools.values) {
      if (t.end != null) continue;
      t
        ..end = ToolEnd.stopped
        ..endedAt = at
        ..awaitingPermission = false
        ..rev += 1;
    }
  }

  void _appendText(ContentBlock content, String? messageId, {required bool thought}) {
    final text = switch (content) {
      TextBlock(:final text) => text,
      ResourceLinkBlock(:final name, :final uri) => '[$name]($uri)',
      _ => '',
    };
    if (text.isEmpty) return;
    final last = items.isEmpty ? null : items.last;
    if (thought) {
      if (last is ThoughtItem && last.turn == turn && last.messageId == messageId) {
        last.append(text);
      } else {
        items.add(ThoughtItem(turn, messageId: messageId)..append(text));
      }
    } else if (last is AgentTextItem && last.turn == turn && last.messageId == messageId) {
      last.append(text);
    } else {
      items.add(AgentTextItem(turn, messageId: messageId)..append(text));
    }
  }
}
```

`lib/src/model/session_state.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';

import 'changes.dart';
import 'notices.dart';
import 'timeline.dart';

enum AgentPhase { stopped, starting, needsAuth, ready, running, failed }

/// The turn in progress.
final class ActiveTurn with Redacted {
  ActiveTurn(this.index, this.startedAt);

  final int index;
  final DateTime startedAt;
  bool cancelRequested = false;

  /// Stop did not end the turn in time: offer "Dừng hẳn" (spec §1.4).
  bool canForceStop = false;

  /// Taken before the prompt went out; null when undo is off.
  Checkpoint? checkpoint;
}

/// A permission request, shown one at a time in order (spec D10).
final class PendingPermission with Redacted {
  PendingPermission(this.id, this.request, this.item);

  final int id;
  final PermissionRequest request;
  final ToolItem item;

  /// The card's title, else the request's (spec §6).
  String get title => item.fields.title ?? request.toolCall.title ?? '';
}

final class PendingAsk with Redacted {
  PendingAsk(this.id, this.item);

  final int id;
  final AskItem item;

  ElicitationRequest get request => item.request;
}

/// A prompt sent while a turn runs; it goes out when the turn ends (D16).
final class QueuedPrompt with Redacted {
  QueuedPrompt(this.id, this.blocks);

  final int id;
  final List<ContentBlock> blocks;

  String get text => blockText(blocks);
}

/// Everything one AI tab shows. The desktop runtime (and the phone, V2-2)
/// changes it; views listen and redraw.
final class AiSessionState with Redacted {
  AiSessionState({required this.agentId, required this.agentName, required this.cwd});

  static const maxQueue = 5;

  final String agentId;
  final String agentName;
  String cwd;

  AgentPhase phase = AgentPhase.stopped;
  String? sessionId;
  String? title;

  /// What `initialize` returned.
  InitializeResult? agent;
  final timeline = Timeline();
  List<PlanEntry> plan = const [];
  List<AvailableCommand> commands = const [];
  List<ConfigOption>? configOptions;
  SessionModes? modes;
  Usage? usage;
  ActiveTurn? turn;
  final List<PendingPermission> permissions = [];
  final List<PendingAsk> asks = [];
  final List<QueuedPrompt> queue = [];

  /// Goes up on every change.
  int version = 0;
  final _listeners = <void Function()>[];
  var _nextId = 0;

  AgentCapabilities get capabilities => agent?.capabilities ?? const AgentCapabilities();

  List<AuthMethod> get authMethods => agent?.authMethods ?? const [];

  /// A permission or a question waits for the user (A12 "Cần bạn").
  bool get needsInput => permissions.isNotEmpty || asks.isNotEmpty;

  PendingPermission? get currentPermission => permissions.isEmpty ? null : permissions.first;

  PendingAsk? get currentAsk => asks.isEmpty ? null : asks.first;

  /// The tab title (spec D2): the session title, else the first prompt
  /// (spaces collapsed, 40 characters), else null ("Phiên AI mới").
  String? get label {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    for (final item in timeline.items) {
      if (item is! UserItem) continue;
      final text = item.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final runes = text.runes.toList();
      return runes.length <= 40 ? text : '${String.fromCharCodes(runes.take(40))}…';
    }
    return null;
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Something changed: bump [version] and tell the listeners.
  void touch() {
    version++;
    for (final l in [..._listeners]) {
      l();
    }
  }

  void setPhase(AgentPhase value) {
    if (phase == value) return;
    phase = value;
    touch();
  }

  void setAgent(InitializeResult result) {
    agent = result;
    touch();
  }

  void setSession(String id, {List<ConfigOption>? configOptions, SessionModes? modes}) {
    sessionId = id;
    if (configOptions != null) this.configOptions = configOptions;
    if (modes != null) this.modes = modes;
    touch();
  }

  /// Applies one `session/update`.
  ///
  /// [history]: replayed by `session/load`, so user messages start turns.
  /// [timelineToo]: false drops message and tool updates, for a restart
  /// whose replay repeats what the timeline already shows.
  void applyUpdate(SessionUpdate update, DateTime at, {bool history = false, bool timelineToo = true}) {
    switch (update) {
      case PlanUpdated(:final entries):
        plan = entries;
      case CommandsUpdated(:final commands):
        this.commands = commands;
      case ModeUpdated(:final currentModeId):
        modes = modes?.withCurrent(currentModeId);
      case ConfigUpdated(:final options):
        configOptions = options;
      case SessionInfoUpdated(:final hasTitle, title: final newTitle):
        if (hasTitle) title = newTitle;
      case UsageUpdated(:final usage):
        this.usage = usage;
      case UnknownUpdate():
        return;
      case UserMessageChunk() when !history && turn != null:
        return;
      default:
        if (!timelineToo) return;
        timeline.apply(update, at);
    }
    touch();
  }

  /// Starts a turn: the prompt joins the timeline.
  ActiveTurn beginTurn(List<ContentBlock> prompt, DateTime at) {
    timeline.startTurn(prompt);
    final t = ActiveTurn(timeline.turn, at);
    turn = t;
    phase = AgentPhase.running;
    touch();
    return t;
  }

  /// Ends the turn in progress with its summary card. Calls still open are
  /// stopped unless the agent finished the turn itself.
  TurnEndItem? endTurn({
    required TurnOutcome outcome,
    required DateTime at,
    StopReason? stopReason,
    String? error,
    String? afterTree,
    List<FileChange>? changes,
  }) {
    final t = turn;
    if (t == null) return null;
    if (outcome != TurnOutcome.finished) timeline.stopOpenTools(at);
    final item = TurnEndItem(
      t.index,
      outcome: outcome,
      elapsed: at.difference(t.startedAt),
      stopReason: stopReason,
      error: error,
      checkpoint: t.checkpoint,
      afterTree: afterTree,
      changes: changes,
    );
    timeline.add(item);
    turn = null;
    if (phase == AgentPhase.running) phase = AgentPhase.ready;
    touch();
    return item;
  }

  /// Queues a permission request; its card is created from the request
  /// when the agent sent none (spec §6).
  PendingPermission addPermission(PermissionRequest request, DateTime at) {
    final item = timeline.toolFor(request.toolCallId, request.toolCall, at)..awaitingPermission = true;
    final p = PendingPermission(_nextId++, request, item);
    permissions.add(p);
    touch();
    return p;
  }

  void resolvePermission(int id, PermissionOutcome outcome) {
    final i = permissions.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final p = permissions.removeAt(i);
    final item = p.item..awaitingPermission = permissions.any((q) => identical(q.item, p.item));
    switch (outcome) {
      case PermissionSelected(:final optionId):
        item.permissionAnswer = p.request.options.where((o) => o.optionId == optionId).firstOrNull;
      case PermissionCancelled():
        item.permissionCancelled = true;
    }
    item.rev++;
    touch();
  }

  /// Adds a question card; null (and already answered `decline`) when
  /// [autoDeclined].
  PendingAsk? addAsk(ElicitationRequest request, {bool autoDeclined = false}) {
    final item = AskItem(timeline.turn, _nextId++, request, autoDeclined: autoDeclined);
    timeline.add(item);
    if (autoDeclined) {
      item.response = const ElicitDecline();
      touch();
      return null;
    }
    final a = PendingAsk(item.id, item);
    asks.add(a);
    touch();
    return a;
  }

  void resolveAsk(int id, ElicitationResponse response) {
    final i = asks.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = asks.removeAt(i);
    a.item
      ..response = response
      ..rev += 1;
    touch();
  }

  void completeUrlAsk(String elicitationId) {
    var changed = false;
    for (final item in timeline.items) {
      if (item is AskItem && item.request is ElicitationUrl &&
          (item.request as ElicitationUrl).elicitationId == elicitationId) {
        item
          ..completed = true
          ..rev += 1;
        changed = true;
      }
    }
    if (changed) touch();
  }

  NoticeItem addNotice(AiNotice notice) {
    final item = NoticeItem(timeline.turn, notice);
    timeline.add(item);
    touch();
    return item;
  }

  /// Folds the open notices [test] matches (the problem is solved).
  void resolveNotices(bool Function(AiNotice notice) test) {
    var changed = false;
    for (final item in timeline.items) {
      if (item is NoticeItem && !item.resolved && test(item.notice)) {
        item
          ..resolved = true
          ..rev += 1;
        changed = true;
      }
    }
    if (changed) touch();
  }

  /// Null when [maxQueue] prompts already wait.
  QueuedPrompt? enqueue(List<ContentBlock> blocks) {
    if (queue.length >= maxQueue) return null;
    final q = QueuedPrompt(_nextId++, [...blocks]);
    queue.add(q);
    touch();
    return q;
  }

  void removeQueued(int id) {
    final before = queue.length;
    queue.removeWhere((q) => q.id == id);
    if (queue.length != before) touch();
  }

  QueuedPrompt? takeQueued() {
    if (queue.isEmpty) return null;
    final q = queue.removeAt(0);
    touch();
    return q;
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: all pass (the replay tests skip without the fixture); `No issues found!`. Also run `grep -rn "dart:io" lib/src/model lib/shellx_ai.dart`. Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock .github/workflows/windows-check.yml packages/shellx_ai
git commit -m "feat(v2-ai): shared AI session model — timeline reducer, permissions, questions, queue

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Login-shell environment, probes, agent catalog and resolver

**Files:**
- Modify: `packages/shellx_ai/pubspec.yaml` (add `path: ^1.9.1` to `dependencies`)
- Create: `packages/shellx_ai/lib/host.dart`
- Create: `packages/shellx_ai/lib/src/host/probe.dart`
- Create: `packages/shellx_ai/lib/src/host/login_shell_env.dart`
- Create: `packages/shellx_ai/lib/src/host/agent_catalog.dart`
- Create: `packages/shellx_ai/lib/src/host/agent_resolver.dart`
- Test: `packages/shellx_ai/test/host/login_shell_env_test.dart`, `test/host/agent_resolver_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks except `Redacted` (shellx_acp).
- Produces (`package:shellx_ai/host.dart`):
  - probes and the file system:
    - `final class ProbeResult(int exitCode, String stdout)`
    - `typedef ProbeRunner = Future<ProbeResult?> Function(String executable, List<String> args, {Map<String, String>? environment})`
    - `Future<ProbeResult?> runProbe(String executable, List<String> args, {Map<String, String>? environment, Duration timeout = const Duration(seconds: 5)})`
    - `abstract interface class FileProbe { bool isFile(String); bool isExecutable(String); String? read(String); }`, `final class RealFileProbe implements FileProbe`
    - `String? envValue(Map<String, String> vars, String name)` (case-insensitive name)
    - `String? findExecutable(String command, Map<String, String> vars, {required bool isWindows, FileProbe files = const RealFileProbe(), bool shims = false})`
  - the login-shell environment:
    - `enum LoginEnvSource { interactiveLogin, login, process }`
    - `final class LoginEnv(Map<String, String> vars, {required LoginEnvSource source})`
    - `typedef ShellRunner = Future<(int, List<int>)> Function(String shell, List<String> args, Map<String, String> environment, Duration timeout)`
    - `Map<String, String>? parseMarkedEnv(List<int> stdout)`, `Map<String, String> cleanAgentEnv(Map<String, String> env)`
    - `final class LoginShellEnv { LoginShellEnv({String? shell, Map<String, String>? processEnv, bool? isWindows, bool? isMacOS, ShellRunner? run, Duration timeout = const Duration(seconds: 10)}); Future<LoginEnv> resolve(); void invalidate(); }`
  - the catalog:
    - `sealed AgentLaunch`, with `NpmLaunch({package, version, bin, args, minNode})`, `PathLaunch(command, [args])` and `CustomLaunch({command, args, env})`
    - `AgentSpec({id, name, launch})`, `const kKnownAgents`
    - `final class AgentCommand({executable, args, environment, workingDirectory}) + withArgs(extraArgs, [extraEnv])`
  - readiness:
    - `sealed AgentReadiness`, with `AgentReady(command)`, `AgentNeedsNode({required, found})`, `AgentNeedsInstall(AgentCommand? install)` and `AgentNotFound(command, {shimOnly})`
    - `final class AgentResolver { AgentResolver({required String agentsDir, bool? isWindows, ProbeRunner? probe, FileProbe files = const RealFileProbe()}); String prefixFor(AgentSpec); Future<AgentReadiness> resolve(AgentSpec, LoginEnv); }`

- [ ] **Step 1: Write the failing tests**

`test/host/login_shell_env_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

List<int> marked(Map<String, String> vars, {String before = '', String after = ''}) => utf8.encode(
  '$before\x1e${vars.entries.map((e) => '${e.key}=${e.value}').join('\x00')}\x00\x1e$after',
);

void main() {
  group('parseMarkedEnv', () {
    test('only what is between the markers; values may hold = and newlines', () {
      final env = parseMarkedEnv(marked(
        {'PATH': '/usr/bin:/bin', 'MULTI': 'a\nb=c', 'EMPTY': ''},
        before: 'Welcome back!\nLast login: today\n',
        after: '\nbye',
      ));
      expect(env, {'PATH': '/usr/bin:/bin', 'MULTI': 'a\nb=c', 'EMPTY': ''});
    });

    test('no markers: null', () {
      expect(parseMarkedEnv(utf8.encode('PATH=/bin\x00')), isNull);
      expect(parseMarkedEnv(utf8.encode('one \x1e only')), isNull);
    });
  });

  test('cleanAgentEnv drops every SHELLX_* and per-shell noise (spec D6)', () {
    expect(
      cleanAgentEnv({
        'PATH': '/bin',
        'SHELLX_CLI_TOKEN': 't',
        'SHELLX_SOCKET': 's',
        'shellx_other': 'x',
        'PWD': '/x',
        'OLDPWD': '/y',
        'SHLVL': '2',
        '_': '/usr/bin/env',
        'HOME': '/Users/a',
      }),
      {'PATH': '/bin', 'HOME': '/Users/a'},
    );
  });

  group('resolve', () {
    final process = {'PATH': '/usr/bin', 'SHELL': '/bin/zsh', 'SHELLX_CLI_TOKEN': 'secret'};

    test('interactive login first; markers make profile noise harmless', () async {
      final calls = <List<String>>[];
      final env = LoginShellEnv(
        processEnv: process,
        isWindows: false,
        isMacOS: true,
        run: (shell, args, environment, timeout) async {
          calls.add([shell, ...args]);
          expect(environment['SHELLX_RESOLVING_ENVIRONMENT'], '1');
          return (0, marked({'PATH': '/opt/homebrew/bin:/usr/bin', 'SHELLX_CLI_TOKEN': 'x'}, before: 'banner'));
        },
      );
      final r = await env.resolve();
      expect(r.source, LoginEnvSource.interactiveLogin);
      expect(r.vars, {'PATH': '/opt/homebrew/bin:/usr/bin'});
      expect(calls.single.take(4), ['/bin/zsh', '-i', '-l', '-c']);
    });

    test('then -l -c, then the app environment', () async {
      var n = 0;
      final viaLogin = await LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async =>
            n++ == 0 ? (1, utf8.encode('no markers here')) : (0, marked({'PATH': '/login/bin'})),
      ).resolve();
      expect(viaLogin.source, LoginEnvSource.login);
      expect(viaLogin.vars['PATH'], '/login/bin');

      final fallback = await LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async => throw TimeoutException('slow'),
      ).resolve();
      expect(fallback.source, LoginEnvSource.process);
      expect(fallback.vars, {'PATH': '/usr/bin', 'SHELL': '/bin/zsh'});
    });

    test('a non-zero exit with markers still counts', () async {
      final r = await LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async => (3, marked({'PATH': '/x'})),
      ).resolve();
      expect(r.vars['PATH'], '/x');
    });

    test('cached until invalidate', () async {
      var n = 0;
      final env = LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async {
          n++;
          return (0, marked({'PATH': '/p$n'}));
        },
      );
      expect((await env.resolve()).vars['PATH'], '/p1');
      expect((await env.resolve()).vars['PATH'], '/p1');
      env.invalidate();
      expect((await env.resolve()).vars['PATH'], '/p2');
    });

    test('an unknown or relative SHELL falls back to /bin/zsh on macOS', () async {
      final shells = <String>[];
      await LoginShellEnv(
        processEnv: {'SHELL': 'nu'},
        isWindows: false,
        isMacOS: true,
        run: (shell, args, environment, timeout) async {
          shells.add(shell);
          return (0, marked({'PATH': '/x'}));
        },
      ).resolve();
      expect(shells, ['/bin/zsh']);
    });

    test('Windows: the app environment, no shell', () async {
      final r = await LoginShellEnv(
        processEnv: {'Path': r'C:\Windows', 'SHELLX_CLI_TOKEN': 't'},
        isWindows: true,
        run: (shell, args, environment, timeout) async => fail('no shell on Windows'),
      ).resolve();
      expect(r.source, LoginEnvSource.process);
      expect(r.vars, {'Path': r'C:\Windows'});
    });
  });

  group('real shells', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('login_env'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String script(String name, String body) {
      final f = File('${tmp.path}/$name')..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    test('a noisy profile that exits non-zero', () async {
      final shell = script('noisy', r'''
echo "Welcome to the noisy profile"
for last; do :; done
/bin/sh -c "$last"
echo "bye"
exit 3''');
      final r = await LoginShellEnv(shell: shell, processEnv: {'PATH': '/usr/bin:/bin', 'SHELL': shell}, isWindows: false).resolve();
      expect(r.source, LoginEnvSource.interactiveLogin);
      expect(r.vars['PATH'], '/usr/bin:/bin');
    });

    test('a hanging shell gives up within the timeout', () async {
      final shell = script('hang', 'sleep 30');
      final sw = Stopwatch()..start();
      final r = await LoginShellEnv(
        shell: shell,
        processEnv: {'PATH': '/usr/bin:/bin'},
        isWindows: false,
        timeout: const Duration(milliseconds: 300),
      ).resolve();
      expect(r.source, LoginEnvSource.process);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('the user shell of this machine resolves a PATH', () async {
      final r = await LoginShellEnv().resolve();
      expect(envValue(r.vars, 'PATH'), isNotEmpty);
    });
  }, testOn: '!windows');
}
```

The noisy and hanging "shells" are `/bin/sh` scripts. Because the paths are absolute but the basenames are not known shells, `shell:` must take them as given. That is why `LoginShellEnv` only applies the known-shell check to `$SHELL`, not to an explicit `shell:` argument.

`test/host/agent_resolver_test.dart`:

```dart
import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

/// An in-memory file system for both platforms.
final class FakeFiles implements FileProbe {
  final files = <String, String>{};
  final executables = <String>{};

  @override
  bool isFile(String path) => files.containsKey(path) || executables.contains(path);

  @override
  bool isExecutable(String path) => executables.contains(path);

  @override
  String? read(String path) => files[path];
}

LoginEnv env(Map<String, String> vars) => LoginEnv(vars, source: LoginEnvSource.interactiveLogin);
AgentSpec known(String id) => kKnownAgents.firstWhere((a) => a.id == id);
ProbeRunner nodeVersion(String v) => (exe, args, {environment}) async => ProbeResult(0, '$v\n');

void main() {
  test('the pins (spec D6): bump only on purpose', () {
    final npm = {for (final a in kKnownAgents) if (a.launch is NpmLaunch) a.id: a.launch as NpmLaunch};
    expect(kKnownAgents.map((a) => a.id), ['claude', 'codex', 'gemini', 'opencode']);
    expect(npm['claude']!.package, '@agentclientprotocol/claude-agent-acp');
    expect(npm['claude']!.version, '0.90.0');
    expect(npm['claude']!.minNode, 22);
    expect(npm['codex']!.version, '2.2.2');
    expect(npm['gemini']!.version, '0.64.0');
    expect(npm['gemini']!.args, ['--acp']);
    expect((known('opencode').launch as PathLaunch).args, ['acp']);
    expect(known('claude').name, 'Claude', reason: 'never "Claude Code" (spec D21)');
  });

  group('POSIX', () {
    late FakeFiles fs;
    final vars = {'PATH': '/usr/local/bin:/usr/bin', 'HOME': '/Users/a'};
    const pkg = '/support/ai/agents/claude/node_modules/@agentclientprotocol/claude-agent-acp';
    AgentResolver resolver({String node = 'v22.12.0'}) =>
        AgentResolver(agentsDir: '/support/ai/agents', isWindows: false, probe: nodeVersion(node), files: fs);

    setUp(() => fs = FakeFiles()..executables.addAll({'/usr/local/bin/node', '/usr/local/bin/npm'}));

    test('no node: needs Node 22, none found', () async {
      fs.executables.clear();
      final r = await resolver().resolve(known('claude'), env(vars));
      expect(r, isA<AgentNeedsNode>().having((r) => r.found, 'found', isNull).having((r) => r.required, 'required', 22));
    });

    test('node 20 is too old for Claude but fine for Codex', () async {
      expect(
        await resolver(node: 'v20.11.1').resolve(known('claude'), env(vars)),
        isA<AgentNeedsNode>().having((r) => r.found, 'found', 'v20.11.1'),
      );
      expect(await resolver(node: 'v20.11.1').resolve(known('codex'), env(vars)), isA<AgentNeedsInstall>());
    });

    test('not installed: the npm install command, in the agent prefix', () async {
      final r = await resolver().resolve(known('claude'), env(vars)) as AgentNeedsInstall;
      final c = r.install!;
      expect(c.executable, '/usr/local/bin/npm');
      expect(c.args, [
        'install',
        '--prefix',
        '/support/ai/agents/claude',
        '--no-audit',
        '--no-fund',
        '--save-exact',
        '@agentclientprotocol/claude-agent-acp@0.90.0',
      ]);
      expect(c.workingDirectory, '/support/ai/agents/claude');
      expect(c.environment, vars);
    });

    test('installed at the pin: node runs the package bin, no shell, no npx', () async {
      fs.files['$pkg/package.json'] = '{"version":"0.90.0","bin":{"claude-agent-acp":"dist/index.js"}}';
      fs.files['$pkg/dist/index.js'] = '';
      final r = await resolver().resolve(known('claude'), env(vars)) as AgentReady;
      expect(r.command.executable, '/usr/local/bin/node');
      expect(r.command.args, ['$pkg/dist/index.js']);
      expect(r.command.environment, vars);
    });

    test('installed at another version: install again', () async {
      fs.files['$pkg/package.json'] = '{"version":"0.89.0","bin":"dist/index.js"}';
      fs.files['$pkg/dist/index.js'] = '';
      expect(await resolver().resolve(known('claude'), env(vars)), isA<AgentNeedsInstall>());
    });

    test('Gemini: the bin from package.json, then --acp', () async {
      const g = '/support/ai/agents/gemini/node_modules/@google/gemini-cli';
      fs.files['$g/package.json'] = '{"version":"0.64.0","bin":{"gemini":"bundle/gemini.js"}}';
      fs.files['$g/bundle/gemini.js'] = '';
      final r = await resolver().resolve(known('gemini'), env(vars)) as AgentReady;
      expect(r.command.args, ['$g/bundle/gemini.js', '--acp']);
    });

    test('npm missing: install is null', () async {
      fs.executables.remove('/usr/local/bin/npm');
      final r = await resolver().resolve(known('claude'), env(vars)) as AgentNeedsInstall;
      expect(r.install, isNull);
    });

    test('a PATH agent', () async {
      expect(await resolver().resolve(known('opencode'), env(vars)), isA<AgentNotFound>().having((r) => r.shimOnly, 'shim', isFalse));
      fs.executables.add('/usr/bin/opencode');
      final r = await resolver().resolve(known('opencode'), env(vars)) as AgentReady;
      expect([r.command.executable, ...r.command.args], ['/usr/bin/opencode', 'acp']);
    });

    test('a custom agent: absolute command, its env over the login env', () async {
      fs.executables.add('/opt/my/agent');
      const spec = AgentSpec(
        id: 'custom:mine',
        name: 'Mine',
        launch: CustomLaunch(command: '/opt/my/agent', args: ['--acp'], env: {'HOME': '/elsewhere', 'TOKEN_FILE': '/x'}),
      );
      final r = await resolver().resolve(spec, env(vars)) as AgentReady;
      expect(r.command.args, ['--acp']);
      expect(r.command.environment, {'PATH': '/usr/local/bin:/usr/bin', 'HOME': '/elsewhere', 'TOKEN_FILE': '/x'});
    });
  });

  group('Windows', () {
    late FakeFiles fs;
    final vars = {'Path': r'C:\node;C:\tools', 'SystemRoot': r'C:\Windows'};
    AgentResolver resolver() =>
        AgentResolver(agentsDir: r'C:\support\ai\agents', isWindows: true, probe: nodeVersion('v22.1.0'), files: fs);

    setUp(() => fs = FakeFiles()..executables.add(r'C:\node\node.exe'));

    test('install runs npm-cli.js with node, never npm.cmd', () async {
      fs.files[r'C:\node\node_modules\npm\bin\npm-cli.js'] = '';
      final r = await resolver().resolve(known('claude'), env(vars)) as AgentNeedsInstall;
      expect(r.install!.executable, r'C:\node\node.exe');
      expect(r.install!.args.take(4), [r'C:\node\node_modules\npm\bin\npm-cli.js', 'install', '--prefix', r'C:\support\ai\agents\claude']);
    });

    test('a .cmd shim alone is not run', () async {
      fs.executables.add(r'C:\tools\opencode.cmd');
      expect(await resolver().resolve(known('opencode'), env(vars)), isA<AgentNotFound>().having((r) => r.shimOnly, 'shim', isTrue));
      fs.executables.add(r'C:\tools\opencode.exe');
      final r = await resolver().resolve(known('opencode'), env(vars)) as AgentReady;
      expect(r.command.executable, r'C:\tools\opencode.exe');
    });
  });

  test('AgentCommand.withArgs adds a login method args and env (spec D8)', () {
    const c = AgentCommand(executable: 'node', args: ['index.js'], environment: {'A': '1'});
    final login = c.withArgs(['--cli', 'auth', 'login'], {'B': '2'});
    expect(login.args, ['index.js', '--cli', 'auth', 'login']);
    expect(login.environment, {'A': '1', 'B': '2'});
    expect(c.toString(), '…');
  });

  test('findExecutable on the real file system', () {
    final dir = Directory.systemTemp.createTempSync('which');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/tool').writeAsStringSync('#!/bin/sh\n');
    File('${dir.path}/plain').writeAsStringSync('');
    Process.runSync('chmod', ['+x', '${dir.path}/tool']);
    final vars = {'PATH': '/nonexistent:${dir.path}'};
    expect(findExecutable('tool', vars, isWindows: false), '${dir.path}/tool');
    expect(findExecutable('plain', vars, isWindows: false), isNull, reason: 'not executable');
    expect(findExecutable('${dir.path}/tool', const {}, isWindows: false), '${dir.path}/tool');
  }, testOn: '!windows');
}
```

Add `import 'dart:io';` at the top of the resolver test for `Directory`, `File` and `Process`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/host`
Expected: compile errors.

- [ ] **Step 3: Implement**

`lib/src/host/probe.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The exit code and output of a short helper command.
final class ProbeResult {
  const ProbeResult(this.exitCode, this.stdout);

  final int exitCode;
  final String stdout;
}

/// Runs a short helper (`node --version`, `git --version`, `xcode-select
/// -p`, `ps`); null when it cannot start or runs over its time.
typedef ProbeRunner =
    Future<ProbeResult?> Function(String executable, List<String> args, {Map<String, String>? environment});

Future<ProbeResult?> runProbe(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      args,
      environment: environment,
      includeParentEnvironment: environment == null,
    );
  } on Object {
    return null;
  }
  unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
  unawaited(process.stderr.drain<void>());
  final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProbeResult(code, await out.timeout(const Duration(seconds: 1), onTimeout: () => ''));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return null;
  }
}

/// What the host asks the file system; faked in tests for both platforms.
abstract interface class FileProbe {
  bool isFile(String path);
  bool isExecutable(String path);
  String? read(String path);
}

final class RealFileProbe implements FileProbe {
  const RealFileProbe();

  @override
  bool isFile(String path) => FileSystemEntity.typeSync(path) == FileSystemEntityType.file;

  @override
  bool isExecutable(String path) {
    if (Platform.isWindows) return isFile(path);
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
  }

  @override
  String? read(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return null;
    }
  }
}

/// [name]'s value in [vars], ignoring case (Windows writes `Path`).
String? envValue(Map<String, String> vars, String name) {
  final exact = vars[name];
  if (exact != null) return exact;
  final upper = name.toUpperCase();
  for (final e in vars.entries) {
    if (e.key.toUpperCase() == upper) return e.value;
  }
  return null;
}

/// [command] as given when it holds a separator, else the first match on
/// the `PATH` of [vars]. On Windows the extensions are `.exe` and `.com`;
/// `.cmd`/`.bat` only with [shims] (ShellX never runs them: cmd.exe would
/// have to parse the arguments).
String? findExecutable(
  String command,
  Map<String, String> vars, {
  required bool isWindows,
  FileProbe files = const RealFileProbe(),
  bool shims = false,
}) {
  final ctx = p.Context(style: isWindows ? p.Style.windows : p.Style.posix);
  final exts = !isWindows
      ? const ['']
      : ctx.extension(command).isNotEmpty
      ? const ['']
      : shims
      ? const ['.cmd', '.bat']
      : const ['.exe', '.com'];
  bool ok(String path) => isWindows ? files.isFile(path) : files.isExecutable(path);
  if (command.contains('/') || (isWindows && command.contains(r'\'))) {
    for (final e in exts) {
      if (ok('$command$e')) return '$command$e';
    }
    return null;
  }
  final path = envValue(vars, 'PATH') ?? '';
  for (final dir in path.split(isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final e in exts) {
      final candidate = ctx.join(dir, '$command$e');
      if (ok(candidate)) return candidate;
    }
  }
  return null;
}
```

`lib/src/host/login_shell_env.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Where an environment came from.
enum LoginEnvSource { interactiveLogin, login, process }

/// The environment agents and git run with (spec D6).
final class LoginEnv {
  const LoginEnv(this.vars, {required this.source});

  final Map<String, String> vars;
  final LoginEnvSource source;

  @override
  String toString() => 'LoginEnv(${source.name}, ${vars.length} vars)';
}

/// Runs [shell] with [args]; returns its exit code and stdout, or throws
/// [TimeoutException] after [timeout].
typedef ShellRunner =
    Future<(int, List<int>)> Function(String shell, List<String> args, Map<String, String> environment, Duration timeout);

/// The `KEY=value` pairs (`env -0`: NUL-separated) between the first and
/// the last `\x1e` of [stdout]; null without both markers.
Map<String, String>? parseMarkedEnv(List<int> stdout) {
  final text = utf8.decode(stdout, allowMalformed: true);
  final start = text.indexOf('\x1e');
  final end = text.lastIndexOf('\x1e');
  if (start < 0 || end <= start) return null;
  final vars = <String, String>{};
  for (final entry in text.substring(start + 1, end).split('\x00')) {
    final eq = entry.indexOf('=');
    if (eq <= 0) continue;
    vars[entry.substring(0, eq)] = entry.substring(eq + 1);
  }
  return vars;
}

const _dropped = {'PWD', 'OLDPWD', 'SHLVL', '_'};

/// [env] without ShellX's own variables (no `SHELLX_CLI_TOKEN`, spec D6)
/// and per-shell noise. The agent's cwd is set apart.
Map<String, String> cleanAgentEnv(Map<String, String> env) => {
  for (final e in env.entries)
    if (!e.key.toUpperCase().startsWith('SHELLX_') && !_dropped.contains(e.key)) e.key: e.value,
};

/// The user's login-shell environment, resolved once per app session
/// (spec D6): `$SHELL -i -l -c`, then `-l -c`, then the app's own
/// environment. The script prints `env -0` between `\x1e` markers, so
/// whatever a profile prints around it is ignored. Windows has no login
/// shell: the app's environment is used. Agents never run through a shell.
final class LoginShellEnv {
  LoginShellEnv({
    String? shell,
    Map<String, String>? processEnv,
    bool? isWindows,
    bool? isMacOS,
    ShellRunner? run,
    this.timeout = const Duration(seconds: 10),
  }) : _processEnv = processEnv ?? Platform.environment,
       _isWindows = isWindows ?? Platform.isWindows,
       _shell = shell ?? _pickShell((processEnv ?? Platform.environment)['SHELL'], isMacOS ?? Platform.isMacOS),
       _run = run ?? _runShell;

  static const script = r"printf '\036'; /usr/bin/env -0; printf '\036'";
  static const _known = {'zsh', 'bash', 'sh', 'fish', 'dash', 'ksh'};

  final Duration timeout;
  final Map<String, String> _processEnv;
  final bool _isWindows;
  final String _shell;
  final ShellRunner _run;
  Future<LoginEnv>? _cached;

  Future<LoginEnv> resolve() => _cached ??= _resolve();

  /// Forgets the environment (the user installed Node, edited a profile…).
  void invalidate() => _cached = null;

  static String _pickShell(String? shell, bool isMacOS) {
    if (shell != null && shell.startsWith('/') && _known.contains(shell.split('/').last)) return shell;
    return isMacOS ? '/bin/zsh' : '/bin/sh';
  }

  Future<LoginEnv> _resolve() async {
    if (_isWindows) return LoginEnv(cleanAgentEnv(_processEnv), source: LoginEnvSource.process);
    // A profile can skip slow setup when it sees this (like VS Code's flag);
    // cleanAgentEnv drops it again.
    final env = {..._processEnv, 'SHELLX_RESOLVING_ENVIRONMENT': '1', 'TERM': 'dumb'};
    for (final (args, source) in [
      (['-i', '-l', '-c', script], LoginEnvSource.interactiveLogin),
      (['-l', '-c', script], LoginEnvSource.login),
    ]) {
      try {
        final (_, out) = await _run(_shell, args, env, timeout);
        final vars = parseMarkedEnv(out);
        if (vars != null && vars['PATH'] != null) return LoginEnv(cleanAgentEnv(vars), source: source);
      } on Object {
        // Try the next way.
      }
    }
    return LoginEnv(cleanAgentEnv(_processEnv), source: LoginEnvSource.process);
  }

  static Future<(int, List<int>)> _runShell(
    String shell,
    List<String> args,
    Map<String, String> environment,
    Duration timeout,
  ) async {
    final process = await Process.start(shell, args, environment: environment, includeParentEnvironment: false);
    unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
    unawaited(process.stderr.drain<void>());
    final out = <int>[];
    final outDone = process.stdout.listen(out.addAll).asFuture<void>();
    try {
      final code = await process.exitCode.timeout(timeout);
      // A background child may keep stdout open; the markers are in by now.
      await outDone.timeout(const Duration(seconds: 1), onTimeout: () {});
      return (code, out);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }
}
```

`lib/src/host/agent_catalog.dart`:

```dart
/// How ShellX starts an agent (spec D6, D23).
sealed class AgentLaunch {
  const AgentLaunch();
}

/// An npm adapter installed once under `<support>/ai/agents/<id>` at a
/// pinned version and run with node (no npx, no shell).
final class NpmLaunch extends AgentLaunch {
  const NpmLaunch({
    required this.package,
    required this.version,
    required this.bin,
    this.args = const [],
    required this.minNode,
  });

  final String package;
  final String version;

  /// The package's bin script; the installed `package.json` wins.
  final String bin;
  final List<String> args;
  final int minNode;
}

/// A command found on the login PATH.
final class PathLaunch extends AgentLaunch {
  const PathLaunch(this.command, [this.args = const []]);

  final String command;
  final List<String> args;
}

/// An agent the user added (Settings › Agents, spec D7).
final class CustomLaunch extends AgentLaunch {
  const CustomLaunch({required this.command, this.args = const [], this.env = const {}});

  final String command;
  final List<String> args;
  final Map<String, String> env;
}

final class AgentSpec {
  const AgentSpec({required this.id, required this.name, required this.launch});

  final String id;

  /// Shown in menus; "Claude", never "Claude Code" (spec D21).
  final String name;
  final AgentLaunch launch;
}

/// The agents ShellX knows, in default order (spec D23). Bump a pin only
/// after testing it (spec D6).
const kKnownAgents = <AgentSpec>[
  AgentSpec(
    id: 'claude',
    name: 'Claude',
    launch: NpmLaunch(
      package: '@agentclientprotocol/claude-agent-acp',
      version: '0.90.0',
      bin: 'dist/index.js',
      minNode: 22,
    ),
  ),
  AgentSpec(
    id: 'codex',
    name: 'Codex',
    launch: NpmLaunch(package: '@agentclientprotocol/codex-acp', version: '2.2.2', bin: 'dist/index.js', minNode: 20),
  ),
  AgentSpec(
    id: 'gemini',
    name: 'Gemini CLI',
    launch: NpmLaunch(
      package: '@google/gemini-cli',
      version: '0.64.0',
      bin: 'bundle/gemini.js',
      args: ['--acp'],
      minNode: 20,
    ),
  ),
  AgentSpec(id: 'opencode', name: 'OpenCode', launch: PathLaunch('opencode', ['acp'])),
];

/// A command line to start without a shell: an agent, its terminal login
/// (spec D8) or an adapter install (spec D7).
final class AgentCommand {
  const AgentCommand({
    required this.executable,
    this.args = const [],
    this.environment = const {},
    this.workingDirectory,
  });

  final String executable;
  final List<String> args;

  /// The whole environment: the child gets nothing else.
  final Map<String, String> environment;

  /// Installs run in their prefix (create it first); agents run in the
  /// session folder instead.
  final String? workingDirectory;

  /// This command plus a login method's args and env (spec D8).
  AgentCommand withArgs(List<String> extraArgs, [Map<String, String> extraEnv = const {}]) => AgentCommand(
    executable: executable,
    args: [...args, ...extraArgs],
    environment: {...environment, ...extraEnv},
    workingDirectory: workingDirectory,
  );

  @override
  String toString() => '…';
}

/// Can the agent start (spec D7 statuses)?
sealed class AgentReadiness {
  const AgentReadiness();
}

final class AgentReady extends AgentReadiness {
  const AgentReady(this.command);

  final AgentCommand command;
}

/// "Thiếu Node 22": [found] is `node --version` (null: no node at all).
final class AgentNeedsNode extends AgentReadiness {
  const AgentNeedsNode({required this.required, this.found});

  final int required;
  final String? found;
}

/// "Chưa cài": [install] runs in the run sheet; null when npm is missing.
final class AgentNeedsInstall extends AgentReadiness {
  const AgentNeedsInstall(this.install);

  final AgentCommand? install;
}

/// A PATH or custom command that is not there ([shimOnly]: only a
/// `.cmd`/`.bat` on Windows).
final class AgentNotFound extends AgentReadiness {
  const AgentNotFound(this.command, {this.shimOnly = false});

  final String command;
  final bool shimOnly;
}
```

`lib/src/host/agent_resolver.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent_catalog.dart';
import 'login_shell_env.dart';
import 'probe.dart';

/// Finds out whether an agent can start, and with which command (spec D6).
final class AgentResolver {
  AgentResolver({
    required this.agentsDir,
    bool? isWindows,
    ProbeRunner? probe,
    this.files = const RealFileProbe(),
  }) : isWindows = isWindows ?? Platform.isWindows,
       _probe = probe ?? runProbe;

  /// `<app support>/ai/agents`.
  final String agentsDir;
  final bool isWindows;
  final FileProbe files;
  final ProbeRunner _probe;

  p.Context get _p => p.Context(style: isWindows ? p.Style.windows : p.Style.posix);

  /// Where [spec]'s npm package is installed (one prefix per agent).
  String prefixFor(AgentSpec spec) => _p.join(agentsDir, spec.id);

  Future<AgentReadiness> resolve(AgentSpec spec, LoginEnv env) async => switch (spec.launch) {
    final NpmLaunch l => await _npm(spec, l, env.vars),
    PathLaunch(:final command, :final args) => _path(command, args, env.vars),
    CustomLaunch(:final command, :final args, env: final extra) => _path(command, args, {...env.vars, ...extra}),
  };

  Future<AgentReadiness> _npm(AgentSpec spec, NpmLaunch l, Map<String, String> vars) async {
    final node = findExecutable('node', vars, isWindows: isWindows, files: files);
    if (node == null) return AgentNeedsNode(required: l.minNode);
    final found = (await _probe(node, const ['--version'], environment: vars))?.stdout.trim();
    final major = int.tryParse(RegExp(r'^v?(\d+)\.').firstMatch(found ?? '')?.group(1) ?? '');
    if (major == null || major < l.minNode) return AgentNeedsNode(required: l.minNode, found: found);
    final prefix = prefixFor(spec);
    final pkgDir = _p.joinAll([prefix, 'node_modules', ...l.package.split('/')]);
    final pkg = _json(files.read(_p.join(pkgDir, 'package.json')));
    if (pkg?['version'] == l.version) {
      final entry = _p.normalize(_p.join(pkgDir, _bin(pkg!, l)));
      if (files.isFile(entry)) {
        return AgentReady(AgentCommand(executable: node, args: [entry, ...l.args], environment: vars));
      }
    }
    return AgentNeedsInstall(_install(node, prefix, l, vars));
  }

  AgentReadiness _path(String command, List<String> args, Map<String, String> vars) {
    final exe = findExecutable(command, vars, isWindows: isWindows, files: files);
    if (exe != null) return AgentReady(AgentCommand(executable: exe, args: args, environment: vars));
    final shim = isWindows && findExecutable(command, vars, isWindows: true, files: files, shims: true) != null;
    return AgentNotFound(command, shimOnly: shim);
  }

  AgentCommand? _install(String node, String prefix, NpmLaunch l, Map<String, String> vars) {
    final args = [
      'install',
      '--prefix',
      prefix,
      '--no-audit',
      '--no-fund',
      '--save-exact',
      '${l.package}@${l.version}',
    ];
    if (isWindows) {
      // npm.cmd would need cmd.exe; npm-cli.js ships next to node.
      final cli = _p.join(_p.dirname(node), 'node_modules', 'npm', 'bin', 'npm-cli.js');
      if (!files.isFile(cli)) return null;
      return AgentCommand(executable: node, args: [cli, ...args], environment: vars, workingDirectory: prefix);
    }
    final npm = findExecutable('npm', vars, isWindows: false, files: files);
    if (npm == null) return null;
    return AgentCommand(executable: npm, args: args, environment: vars, workingDirectory: prefix);
  }

  static Map<String, Object?>? _json(String? text) {
    if (text == null) return null;
    try {
      final j = jsonDecode(text);
      return j is Map<String, Object?> ? j : null;
    } on FormatException {
      return null;
    }
  }

  static String _bin(Map<String, Object?> pkg, NpmLaunch l) {
    final bin = pkg['bin'];
    if (bin is String) return bin;
    if (bin is Map) {
      final named = bin[l.package.split('/').last];
      if (named is String) return named;
      if (bin.length == 1 && bin.values.first is String) return bin.values.first as String;
    }
    return l.bin;
  }
}
```

`lib/host.dart`:

```dart
/// The desktop host for AI sessions (`dart:io`): environment, agents,
/// processes, checkpoints and the runtime (spec D6, D12). The phone does not
/// import this library.
library;

export 'src/host/agent_catalog.dart';
export 'src/host/agent_resolver.dart';
export 'src/host/login_shell_env.dart';
export 'src/host/probe.dart';
```

Later tasks add their exports here.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/host && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: pass (the `real shells` group is skipped on Windows); `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_ai pubspec.lock
git commit -m "feat(v2-ai): login-shell environment, agent catalog with pins, and readiness resolver

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Agent process, stderr ring, crash registry, in-process channel

**Files:**
- Create: `packages/shellx_ai/lib/src/host/byte_ring.dart`
- Create: `packages/shellx_ai/lib/src/host/agent_process.dart`
- Create: `packages/shellx_ai/lib/src/host/running_agents.dart`
- Create: `packages/shellx_ai/lib/src/host/serial_queue.dart` (also used by Task 8)
- Create: `packages/shellx_ai/lib/testing.dart`, `lib/src/testing/fake_agent_channel.dart`
- Modify: `packages/shellx_ai/lib/host.dart` (exports)
- Modify: `packages/shellx_ai/pubspec.yaml` (dev dependency none new; `shellx_acp` already a dependency, `package:shellx_acp/testing.dart` is used by `lib/testing.dart`)
- Test: `test/host/byte_ring_test.dart`, `test/host/agent_process_test.dart`, `test/host/running_agents_test.dart`, `test/support/scripts.dart`

**Interfaces:**
- Consumes: `AgentCommand` (Task 6), `FakeAgent`, `FakeScenario`, `fakeAgentArgs`, `writeScenario` (Task 3).
- Produces:
  - process types:
    - `final class ByteRing(int capacity)`, with `add(List<int>)`, `bytes`, `text` and `length`
    - `abstract interface class AgentChannel { Stream<List<int>> get stdout; StreamSink<List<int>> get stdin; Future<int> get exitCode; String get stderrTail; Future<void> stop(); Future<void> kill(); }`
    - `typedef AgentLauncher = Future<AgentChannel> Function(AgentCommand command, {required String cwd})`
    - `typedef KillTree = Future<void> Function(Process process)`, `Future<void> killOnly(Process)`
    - `final class AgentProcess implements AgentChannel { static Future<AgentProcess> start(AgentCommand, {required String cwd, KillTree killTree = killOnly, Duration grace = const Duration(seconds: 2)}); int get pid; }`
  - the crash registry:
    - `final class SerialQueue { Future<T> run<T>(Future<T> Function() op); }` (one at a time, in order; a failure does not block the next)
    - `final class RunningRecord({pid, command, startedAt})`
    - `typedef ProcessLookup = Future<({String command, DateTime startedAt})?> Function(int pid)`, `typedef KillPid = Future<void> Function(int pid)` (not `ProcessInfo`, which `dart:io` already exports)
    - `Future<({String command, DateTime startedAt})?> lookupProcess(int pid)`, `Future<void> killProcessByPid(int pid)`, `Duration? parseEtime(String)`
    - `final class RunningAgents { RunningAgents(File file, {ProcessLookup? info, KillPid? killPid, Duration tolerance = const Duration(seconds: 5)}); Future<void> add(RunningRecord); Future<void> remove(int pid); Future<int> sweep(); List<RunningRecord> read(); }`
  - `package:shellx_ai/testing.dart`:
    - `final class FakeAgentChannel implements AgentChannel { FakeAgentChannel(FakeScenario, {String? cwd}); FakeAgent agent; int stopCalls; int killCalls; }`
    - `final class FakeLauncher { FakeLauncher(FakeScenario first, [List<FakeScenario> later = const []]); List<FakeAgentChannel> channels; List<AgentCommand> commands; Future<AgentChannel> call(AgentCommand, {required String cwd}); }`

- [ ] **Step 1: Write the failing tests**

`test/support/scripts.dart` (helpers that write tiny Dart programs for process tests):

```dart
import 'dart:io';

/// Writes a Dart program into [dir] and returns the args to run it with
/// the current VM.
List<String> dartScript(Directory dir, String name, String source) {
  final f = File('${dir.path}${Platform.pathSeparator}$name.dart')..writeAsStringSync(source);
  return [f.path];
}

/// A program that ignores stdin closing and lives for five minutes.
const ignoreStdin = '''
import 'dart:async';
void main() { Timer(const Duration(minutes: 5), () {}); }
''';

/// Prints which of HOME / USERPROFILE / ONLY_THIS it can see, then exits.
const printEnv = '''
import 'dart:io';
void main() {
  final e = Platform.environment;
  stdout.write(['HOME', 'USERPROFILE', 'ONLY_THIS'].where(e.containsKey).join(','));
}
''';

/// The variables a Windows process needs to start at all.
Map<String, String> minimalEnv() => {
  if (Platform.isWindows)
    for (final k in ['SystemRoot', 'PATH', 'TEMP', 'TMP'])
      if (Platform.environment[k] != null) k: Platform.environment[k]!,
};
```

`test/host/byte_ring_test.dart`:

```dart
import 'dart:convert';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  test('keeps the last bytes only', () {
    final r = ByteRing(10)
      ..add([1, 2, 3, 4])
      ..add([5, 6, 7, 8])
      ..add([9, 10, 11, 12]);
    expect(r.bytes, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    r.add(List.generate(15, (i) => 100 + i));
    expect(r.bytes, List.generate(10, (i) => 105 + i));
    expect(r.length, 10);
  });

  test('text decodes leniently when the cut splits a character', () {
    final r = ByteRing(4)..add(utf8.encode('aé✓'));
    expect(r.text, endsWith('✓'));
  });
}
```

`test/host/agent_process_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

import '../support/scripts.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('agent_process'));
  tearDown(() => tmp.deleteSync(recursive: true));

  AgentCommand fake(FakeScenario s) => AgentCommand(
    executable: Platform.resolvedExecutable,
    args: fakeAgentArgs(writeScenario(s, tmp)),
    environment: Platform.environment,
  );

  test('speaks ACP over the process pipes; stop() closes stdin and it exits', () async {
    final killed = <int>[];
    final p = await AgentProcess.start(
      fake(FakeScenario(turns: [[FakeSteps.stderr('note: warming up'), FakeSteps.text('ok')]])),
      cwd: tmp.path,
      killTree: (proc) async => killed.add(proc.pid),
    );
    final client = AcpClient(JsonRpcConnection(input: p.stdout, output: p.stdin));
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    expect(await client.prompt(sid, const [TextBlock('hi')]), StopReason.endTurn);
    expect(p.stderrTail, contains('note: warming up'));
    await p.stop();
    expect(await p.exitCode, 0);
    expect(killed, isEmpty, reason: 'it left within the grace period');
  });

  test('stop() kills the tree when stdin closing is ignored', () async {
    final killed = <int>[];
    final p = await AgentProcess.start(
      AgentCommand(executable: Platform.resolvedExecutable, args: dartScript(tmp, 'ignore', ignoreStdin), environment: Platform.environment),
      cwd: tmp.path,
      grace: const Duration(milliseconds: 300),
      killTree: (proc) async {
        killed.add(proc.pid);
        proc.kill(ProcessSignal.sigkill);
      },
    );
    await p.stop();
    await p.exitCode.timeout(const Duration(seconds: 10));
    expect(killed, [p.pid]);
    await p.stop(); // once is enough; a second call does not kill again
    expect(killed, hasLength(1));
  });

  test('the child gets exactly the given environment', () async {
    final p = await AgentProcess.start(
      AgentCommand(
        executable: Platform.resolvedExecutable,
        args: dartScript(tmp, 'env', printEnv),
        environment: {...minimalEnv(), 'ONLY_THIS': '1'},
      ),
      cwd: tmp.path,
    );
    final out = await p.stdout.transform(utf8.decoder).join();
    await p.exitCode;
    expect(out, 'ONLY_THIS');
  });

  test('a missing executable fails to start', () async {
    await expectLater(
      AgentProcess.start(const AgentCommand(executable: '/nonexistent/agent'), cwd: tmp.path),
      throwsA(isA<ProcessException>()),
    );
  });
}
```

`test/host/running_agents_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

import '../support/scripts.dart';

void main() {
  late Directory tmp;
  late File file;
  final t0 = DateTime.utc(2026, 10, 14, 9);
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('running');
    file = File('${tmp.path}/ai/running.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('add and remove persist; concurrent adds keep every record', () async {
    final r = RunningAgents(file);
    await Future.wait([for (var i = 1; i <= 10; i++) r.add(RunningRecord(pid: i, command: '/usr/bin/node', startedAt: t0))]);
    await r.remove(3);
    expect(RunningAgents(file).read().map((e) => e.pid), unorderedEquals([1, 2, 4, 5, 6, 7, 8, 9, 10]));
  });

  test('sweep kills only matching leftovers, then clears the file', () async {
    final killed = <int>[];
    final now = {
      1: (command: '/opt/homebrew/bin/node', startedAt: t0.add(const Duration(seconds: 1))),
      2: (command: '/usr/bin/python3', startedAt: t0),
      3: (command: 'node', startedAt: t0.add(const Duration(hours: 1))),
      5: (command: r'C:\Program Files\nodejs\NODE.EXE', startedAt: t0),
    };
    final r = RunningAgents(file, info: (pid) async => now[pid], killPid: (pid) async => killed.add(pid));
    for (final (pid, cmd) in [(1, '/usr/local/bin/node'), (2, '/usr/local/bin/node'), (3, 'node'), (4, 'node'), (5, r'C:\nodejs\node.exe')]) {
      await r.add(RunningRecord(pid: pid, command: cmd, startedAt: t0));
    }
    expect(await r.sweep(), 2);
    expect(killed, [1, 5], reason: '2: other program; 3: pid reused; 4: gone');
    expect(r.read(), isEmpty);
  });

  test('a corrupt file is treated as empty', () async {
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{not json');
    final r = RunningAgents(file, info: (_) async => fail('nothing to look up'));
    expect(await r.sweep(), 0);
    expect(r.read(), isEmpty);
  });

  test('parseEtime', () {
    expect(parseEtime('05:03'), const Duration(minutes: 5, seconds: 3));
    expect(parseEtime(' 1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(parseEtime('2-01:00:00'), const Duration(days: 2, hours: 1));
    expect(parseEtime('soon'), isNull);
  });

  test('lookupProcess and killProcessByPid on a real process', () async {
    final proc = await Process.start(Platform.resolvedExecutable, dartScript(tmp, 'ignore', ignoreStdin));
    final started = DateTime.now();
    final info = await lookupProcess(proc.pid);
    expect(info, isNotNull);
    final name = info!.command.replaceAll(r'\', '/').split('/').last.toLowerCase();
    expect(name, anyOf('dart', 'dart.exe', 'dartvm', 'dartvm.exe'));
    expect(info.startedAt.difference(started).abs(), lessThan(const Duration(seconds: 30)));

    final r = RunningAgents(file);
    await r.add(RunningRecord(pid: proc.pid, command: info.command, startedAt: started));
    expect(await r.sweep(), 1);
    await proc.exitCode.timeout(const Duration(seconds: 10));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/host/byte_ring_test.dart test/host/agent_process_test.dart test/host/running_agents_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement**

`lib/src/host/byte_ring.dart`:

```dart
import 'dart:collection';
import 'dart:convert';

/// The last [capacity] bytes of a stream (agent stderr, spec D20: 256 KiB
/// per session, memory only).
final class ByteRing {
  ByteRing(this.capacity);

  final int capacity;
  final _chunks = Queue<List<int>>();
  var _length = 0;

  int get length => _length;

  void add(List<int> data) {
    if (data.isEmpty) return;
    if (data.length >= capacity) {
      _chunks
        ..clear()
        ..add(data.sublist(data.length - capacity));
      _length = capacity;
      return;
    }
    _chunks.add(data);
    _length += data.length;
    while (_length > capacity) {
      final first = _chunks.removeFirst();
      final excess = _length - capacity;
      if (first.length <= excess) {
        _length -= first.length;
      } else {
        _chunks.addFirst(first.sublist(excess));
        _length -= excess;
      }
    }
  }

  List<int> get bytes => [for (final c in _chunks) ...c];

  String get text => utf8.decode(bytes, allowMalformed: true);
}
```

`lib/src/host/agent_process.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'agent_catalog.dart';
import 'byte_ring.dart';

/// A running agent: its stdio and lifetime. [AgentProcess] in the app; an
/// in-process fake in tests.
abstract interface class AgentChannel {
  Stream<List<int>> get stdout;
  StreamSink<List<int>> get stdin;
  Future<int> get exitCode;

  /// The last 256 KiB of stderr ("Xem log", spec D20).
  String get stderrTail;

  /// Close stdin, wait, then kill the tree (spec D6).
  Future<void> stop();

  /// Kill the tree now ("Dừng hẳn").
  Future<void> kill();
}

/// Starts [command] in [cwd].
typedef AgentLauncher = Future<AgentChannel> Function(AgentCommand command, {required String cwd});

/// Kills a process and everything it started; the desktop passes its
/// `killProcessTree` (taskkill /T, or the A10 POSIX tree killer).
typedef KillTree = Future<void> Function(Process process);

/// The fallback [KillTree]: the process only.
Future<void> killOnly(Process process) async {
  process.kill(ProcessSignal.sigkill);
}

/// An agent process: no shell, exactly the command's environment, stderr
/// kept in a ring (spec D6, D20).
final class AgentProcess implements AgentChannel {
  AgentProcess._(this._process, this._killTree, this._grace) {
    _process.stderr.listen(_stderr.add, onError: (Object _) {});
  }

  static Future<AgentProcess> start(
    AgentCommand command, {
    required String cwd,
    KillTree killTree = killOnly,
    Duration grace = const Duration(seconds: 2),
  }) async {
    final process = await Process.start(
      command.executable,
      command.args,
      workingDirectory: cwd,
      environment: command.environment,
      includeParentEnvironment: false,
    );
    return AgentProcess._(process, killTree, grace);
  }

  final Process _process;
  final KillTree _killTree;
  final Duration _grace;
  final _stderr = ByteRing(256 * 1024);
  Future<void>? _stopping;

  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  StreamSink<List<int>> get stdin => _process.stdin;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  String get stderrTail => _stderr.text;

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    unawaited(_process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
    try {
      await _process.exitCode.timeout(_grace);
    } on TimeoutException {
      await _killTree(_process);
    }
  }

  @override
  Future<void> kill() => _killTree(_process);

  @override
  String toString() => '…';
}
```

`lib/src/host/serial_queue.dart`:

```dart
/// Runs async operations one at a time, in the order they were queued; a
/// failed operation does not stop the ones after it.
final class SerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
```

`lib/src/host/running_agents.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'probe.dart';
import 'serial_queue.dart';

/// One agent process this app started.
final class RunningRecord {
  const RunningRecord({required this.pid, required this.command, required this.startedAt});

  final int pid;

  /// The executable that was started.
  final String command;
  final DateTime startedAt;

  Map<String, Object?> toJson() => {'pid': pid, 'command': command, 'startedAt': startedAt.millisecondsSinceEpoch};

  static RunningRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final pid = j['pid'];
    final command = j['command'];
    final at = j['startedAt'];
    if (pid is! int || command is! String || at is! int) return null;
    return RunningRecord(pid: pid, command: command, startedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true));
  }

  @override
  String toString() => '…';
}

/// The executable and start time of a live process; null when gone.
/// (Not `ProcessInfo`: `dart:io` exports a class of that name.)
typedef ProcessLookup = Future<({String command, DateTime startedAt})?> Function(int pid);

typedef KillPid = Future<void> Function(int pid);

/// `ps -o etime` → age: `mm:ss`, `hh:mm:ss` or `d-hh:mm:ss`.
Duration? parseEtime(String text) {
  final m = RegExp(r'^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$').firstMatch(text.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  return Duration(days: g(1), hours: g(2), minutes: g(3), seconds: g(4));
}

/// The OS view of [pid]: `ps` on macOS/Linux, CIM through PowerShell on
/// Windows.
Future<({String command, DateTime startedAt})?> lookupProcess(int pid) async {
  if (Platform.isWindows) {
    final r = await runProbe('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$p = Get-CimInstance Win32_Process -Filter 'ProcessId=$pid'; "
          "if (\$p) { \$p.ExecutablePath; \$p.CreationDate.ToUniversalTime().ToString('o') }",
    ], timeout: const Duration(seconds: 15));
    final lines = const LineSplitter().convert(r?.stdout ?? '').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return null;
    final at = DateTime.tryParse(lines[1].trim());
    return at == null ? null : (command: lines[0].trim(), startedAt: at);
  }
  final r = await runProbe('/bin/ps', ['-o', 'etime=', '-o', 'comm=', '-p', '$pid']);
  final line = (r?.stdout ?? '').trim();
  if (r == null || r.exitCode != 0 || line.isEmpty) return null;
  final space = line.indexOf(RegExp(r'\s'));
  if (space < 0) return null;
  final age = parseEtime(line.substring(0, space));
  if (age == null) return null;
  return (command: line.substring(space).trim(), startedAt: DateTime.now().toUtc().subtract(age));
}

/// The fallback [KillPid]: the process itself (`taskkill /T` on Windows).
Future<void> killProcessByPid(int pid) async {
  if (Platform.isWindows) {
    await runProbe('taskkill', ['/F', '/T', '/PID', '$pid']);
  } else {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

/// `<support>/ai/running.json`: the agents this app runs. After a crash
/// the next launch stops the ones left behind, but only when both the
/// command and the start time still match: a reused pid is left alone
/// (spec §6). Writes run one at a time.
final class RunningAgents {
  RunningAgents(
    this.file, {
    ProcessLookup? info,
    KillPid? killPid,
    this.tolerance = const Duration(seconds: 5),
  }) : _info = info ?? lookupProcess,
       _killPid = killPid ?? killProcessByPid;

  final File file;
  final Duration tolerance;
  final ProcessLookup _info;
  final KillPid _killPid;
  final _queue = SerialQueue();

  Future<void> add(RunningRecord record) => _queue.run(() async {
    _write([..._readNow().where((r) => r.pid != record.pid), record]);
  });

  Future<void> remove(int pid) => _queue.run(() async {
    _write(_readNow().where((r) => r.pid != pid).toList());
  });

  /// At app start: stops matching leftovers and clears the file; returns
  /// how many were stopped.
  Future<int> sweep() => _queue.run(() async {
    var stopped = 0;
    for (final r in _readNow()) {
      final now = await _info(r.pid);
      if (now == null || !_sameCommand(now.command, r.command)) continue;
      if (now.startedAt.difference(r.startedAt).abs() > tolerance) continue;
      await _killPid(r.pid);
      stopped++;
    }
    _write(const []);
    return stopped;
  });

  /// The records as they are on disk.
  List<RunningRecord> read() => _readNow();

  static bool _sameCommand(String a, String b) {
    String base(String s) {
      final name = s.replaceAll(r'\', '/').split('/').last.toLowerCase();
      return name.endsWith('.exe') ? name.substring(0, name.length - 4) : name;
    }

    return base(a) == base(b);
  }

  List<RunningRecord> _readNow() {
    try {
      final j = jsonDecode(file.readAsStringSync());
      final agents = j is Map ? j['agents'] : null;
      if (agents is! List) return [];
      return agents.map(RunningRecord.fromJson).nonNulls.toList();
    } on Object {
      return [];
    }
  }

  void _write(List<RunningRecord> records) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')
      ..writeAsStringSync(jsonEncode({'v': 1, 'agents': [for (final r in records) r.toJson()]}));
    tmp.renameSync(file.path);
  }
}
```

`lib/src/testing/fake_agent_channel.dart`:

```dart
import 'dart:async';

import 'package:shellx_acp/testing.dart';

import '../host/agent_catalog.dart';
import '../host/agent_process.dart';

/// An in-process [AgentChannel] around a [FakeAgent]: no process, same
/// lifecycle. Closing stdin makes it exit 0; [kill] exits -9.
final class FakeAgentChannel implements AgentChannel {
  FakeAgentChannel(FakeScenario scenario, {String? cwd}) {
    agent = FakeAgent(
      scenario,
      input: _toAgent.stream,
      output: _toClient.sink,
      cwd: cwd,
      stderr: _stderr.writeln,
      onExit: _exit,
    );
    agent.connection.done.then((_) => _exit(0));
  }

  late final FakeAgent agent;
  final _toAgent = StreamController<List<int>>();
  final _toClient = StreamController<List<int>>();
  final _exitCode = Completer<int>();
  final _stderr = StringBuffer();
  var stopCalls = 0;
  var killCalls = 0;

  bool get exited => _exitCode.isCompleted;

  void _exit(int code) {
    if (_exitCode.isCompleted) return;
    _exitCode.complete(code);
    unawaited(_toClient.close());
  }

  @override
  Stream<List<int>> get stdout => _toClient.stream;

  @override
  StreamSink<List<int>> get stdin => _toAgent.sink;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  String get stderrTail => _stderr.toString();

  @override
  Future<void> stop() async {
    stopCalls++;
    unawaited(_toAgent.close());
    await exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
      _exit(-9);
      return -9;
    });
  }

  @override
  Future<void> kill() async {
    killCalls++;
    _exit(-9);
  }
}

/// An [AgentLauncher] that hands out [FakeAgentChannel]s and remembers
/// them. Launch 0 uses [first], launch n uses `later[n - 1]` (the last one
/// repeats), so a restarted agent can behave differently.
final class FakeLauncher {
  FakeLauncher(this.first, [this.later = const []]);

  final FakeScenario first;
  final List<FakeScenario> later;
  final channels = <FakeAgentChannel>[];
  final commands = <AgentCommand>[];

  Future<AgentChannel> call(AgentCommand command, {required String cwd}) async {
    commands.add(command);
    final n = channels.length;
    final scenario = n == 0 || later.isEmpty ? first : later[(n - 1).clamp(0, later.length - 1)];
    final channel = FakeAgentChannel(scenario, cwd: cwd);
    channels.add(channel);
    return channel;
  }
}
```

`lib/testing.dart`:

```dart
/// Test helpers for AI sessions: an in-process agent channel and launcher.
library;

export 'package:shellx_acp/testing.dart';

export 'src/testing/fake_agent_channel.dart';
```

Add to `lib/host.dart`: `export 'src/host/agent_process.dart';`, `export 'src/host/byte_ring.dart';`, `export 'src/host/running_agents.dart';`, `export 'src/host/serial_queue.dart';`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: pass; `No issues found!`

On macOS, `ps -o comm=` may show the Dart VM under a different basename (for example `dartvm`). The expectation lists the known names. If another appears, add it and say so in the ledger.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_ai
git commit -m "feat(v2-ai): agent process with stderr ring and graceful stop; crash registry; in-process agent channel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Checkpoints in a shadow git repository

**Files:**
- Modify: `packages/shellx_ai/pubspec.yaml` (add `crypto: ^3.0.6` to `dependencies`)
- Create: `packages/shellx_ai/lib/src/host/git_locator.dart`
- Create: `packages/shellx_ai/lib/src/host/git_runner.dart`
- Create: `packages/shellx_ai/lib/src/host/checkpoint_store.dart`
- Modify: `packages/shellx_ai/lib/host.dart` (exports)
- Test: `test/host/git_locator_test.dart`, `test/host/checkpoint_store_test.dart`, `test/support/git_project.dart`

**Interfaces:**
- Consumes: `LoginEnv`, `ProbeRunner`, `runProbe`, `FileProbe`, `findExecutable` (Task 6); `SerialQueue` (Task 7); `Checkpoint`, `FileChange`, `ChangeKind`, `UndoOff` (Task 5).
- Produces:
  - git:
    - `final class GitTool(String executable, int major, int minor)`
    - `final class GitLocator { GitLocator({ProbeRunner? probe, bool? isMacOS, bool? isWindows, FileProbe files = const RealFileProbe()}); Future<(GitTool?, UndoOff?)> locate(LoginEnv env); }`
    - `final class GitFailed implements Exception { const GitFailed(int exitCode, {bool timedOut = false}); }`
    - `final class GitRunner { GitRunner({required GitTool git, required String gitDir, required String workTree, required Map<String, String> env, DateTime Function()? now}); List<String> get flags; Future<List<int>> run(List<String> args, {List<int>? input, Duration timeout}); Future<String> text(…); }`
  - the store:
    - `const kMaxCheckpointFileBytes = 50 * 1024 * 1024`
    - `String excludePattern(String relPath)`
    - `abstract interface class Checkpoints`, with `off`, `snapshot`, `currentTree`, `changes`, `changedSince`, `fileAt` and `restore` (the runtime depends on this; tests fake it).
    - `final class CheckpointStore implements Checkpoints`:
      - constructor: `CheckpointStore({required String project, required String gitDir, required GitTool git, required Map<String, String> env, int maxFiles = 200000, Duration firstSnapshotLimit = const Duration(seconds: 30), int maxFileBytes = kMaxCheckpointFileBytes, DateTime Function()? now})`;
      - `UndoOff? get off`;
      - methods: `Future<Checkpoint?> snapshot(String ref)`; `Future<String?> currentTree()`; `Future<List<FileChange>> changes(String fromTree, [String? toTree])`; `Future<Set<String>> changedSince(String tree)`; `Future<List<int>?> fileAt(String treeish, String path)`; `Future<void> restore(String treeish, Iterable<String> paths)`; `Future<int> prune(Duration olderThan)`.
    - `final class CheckpointStores { CheckpointStores({required String root, GitLocator? locator, bool? isWindows, CheckpointStore Function(String project, String gitDir, GitTool git, Map<String, String> env)? create}); Future<(CheckpointStore?, UndoOff?)> forProject(String project, LoginEnv env); Future<void> pruneAll(Duration olderThan, LoginEnv env); Future<void> deleteAll(); static String projectId(String realPath, {required bool isWindows}); }`

- [ ] **Step 1: Write the failing tests**

`test/support/git_project.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';

/// A temp project and a shadow repo path, cleaned up by the caller.
final class GitProject {
  GitProject() : tmp = Directory.systemTemp.createTempSync('ckpt') {
    Directory(project).createSync();
  }

  final Directory tmp;

  String get project => p.join(tmp.path, 'project');
  String get gitDir => p.join(tmp.path, 'support', 'ai', 'checkpoints', 'abc');

  void put(String rel, Object content) {
    final f = File(p.join(project, rel))..parent.createSync(recursive: true);
    content is String ? f.writeAsStringSync(content) : f.writeAsBytesSync(content as List<int>);
  }

  List<int> bytes(String rel) => File(p.join(project, rel)).readAsBytesSync();
  bool exists(String rel) => FileSystemEntity.typeSync(p.join(project, rel)) != FileSystemEntityType.notFound;

  /// git in the project itself, as the user would run it.
  ProcessResult userGit(List<String> args, {String? dir}) => Process.runSync(
    'git',
    ['-c', 'user.name=t', '-c', 'user.email=t@t.invalid', '-c', 'commit.gpgSign=false', ...args],
    workingDirectory: dir ?? project,
  );

  static Future<GitTool> git() async {
    final (tool, off) = await GitLocator().locate(LoginEnv(Platform.environment, source: LoginEnvSource.process));
    if (tool == null) throw StateError('git is needed for these tests ($off)');
    return tool;
  }

  void dispose() => tmp.deleteSync(recursive: true);
}
```

`test/host/git_locator_test.dart`:

```dart
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final class Files implements FileProbe {
  Files(this.exe);

  final Set<String> exe;

  @override
  bool isExecutable(String path) => exe.contains(path);

  @override
  bool isFile(String path) => exe.contains(path);

  @override
  String? read(String path) => null;
}

LoginEnv env(String path) => LoginEnv({'PATH': path}, source: LoginEnvSource.interactiveLogin);

ProbeRunner probe(Map<String, ProbeResult?> answers) =>
    (exe, args, {environment}) async => answers['$exe ${args.join(' ')}'];

void main() {
  test('no git on PATH', () async {
    final (git, off) = await GitLocator(isMacOS: true, isWindows: false, files: Files({}), probe: probe({})).locate(env('/usr/bin'));
    expect(git, isNull);
    expect(off, UndoOff.noGit);
  });

  test('macOS /usr/bin/git without Command Line Tools: never run it', () async {
    final asked = <String>[];
    final (git, off) = await GitLocator(
      isMacOS: true,
      isWindows: false,
      files: Files({'/usr/bin/git'}),
      probe: (exe, args, {environment}) async {
        asked.add(exe);
        return exe == '/usr/bin/xcode-select' ? const ProbeResult(2, '') : fail('git must not run');
      },
    ).locate(env('/usr/bin'));
    expect(off, UndoOff.noCommandLineTools);
    expect(git, isNull);
    expect(asked, ['/usr/bin/xcode-select']);
  });

  test('version: 2.26 or newer', () async {
    Future<(GitTool?, UndoOff?)> with_(String version) => GitLocator(
      isMacOS: false,
      isWindows: false,
      files: Files({'/opt/git/bin/git'}),
      probe: probe({'/opt/git/bin/git --version': ProbeResult(0, version)}),
    ).locate(env('/opt/git/bin'));
    expect((await with_('git version 2.20.1')).$2, UndoOff.gitTooOld);
    final (ok, _) = await with_('git version 2.39.5 (Apple Git-154)');
    expect([ok!.executable, ok.major, ok.minor], ['/opt/git/bin/git', 2, 39]);
  });
}
```

`test/host/checkpoint_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

import '../support/git_project.dart';

void main() {
  late GitTool git;
  late GitProject gp;
  setUpAll(() async => git = await GitProject.git());
  setUp(() => gp = GitProject());
  tearDown(() => gp.dispose());

  CheckpointStore store({
    Map<String, String>? env,
    int maxFiles = 200000,
    Duration first = const Duration(seconds: 30),
    int maxFileBytes = kMaxCheckpointFileBytes,
    DateTime Function()? now,
  }) => CheckpointStore(
    project: gp.project,
    gitDir: gp.gitDir,
    git: git,
    env: env ?? Platform.environment,
    maxFiles: maxFiles,
    firstSnapshotLimit: first,
    maxFileBytes: maxFileBytes,
    now: now,
  );

  test('snapshot, diff and restore give back the exact bytes', () async {
    gp
      ..put('a.txt', 'one\r\ntwo\r\n')
      ..put('bin.dat', [0, 1, 2, 255, 254])
      ..put('keep.txt', 'keep');
    final s = store();
    final ck = (await s.snapshot('sess/1'))!;
    gp
      ..put('a.txt', 'one\nTWO\n')
      ..put('new/dir/n.txt', 'new\n');
    File(p.join(gp.project, 'bin.dat')).deleteSync();

    final changes = {for (final c in await s.changes(ck.tree)) c.path: c};
    expect(changes.keys, unorderedEquals(['a.txt', 'bin.dat', 'new/dir/n.txt']));
    expect(changes['a.txt']!.kind, ChangeKind.modified);
    expect(changes['bin.dat']!.kind, ChangeKind.deleted);
    expect(changes['bin.dat']!.binary, isTrue);
    expect(changes['new/dir/n.txt']!.kind, ChangeKind.added);
    expect([changes['new/dir/n.txt']!.added, changes['new/dir/n.txt']!.removed], [1, 0]);
    expect(await s.fileAt(ck.tree, 'a.txt'), utf8.encode('one\r\ntwo\r\n'));
    expect(await s.fileAt(ck.tree, 'new/dir/n.txt'), isNull);

    await s.restore(ck.commit, changes.keys);
    expect(gp.bytes('a.txt'), utf8.encode('one\r\ntwo\r\n'));
    expect(gp.bytes('bin.dat'), [0, 1, 2, 255, 254]);
    expect(gp.exists('new/dir/n.txt'), isFalse);
    expect(gp.exists('new'), isFalse, reason: 'the folders the turn made are gone (R5)');
    expect(gp.bytes('keep.txt'), utf8.encode('keep'));
  });

  test('the project own .git is never touched', () async {
    gp.put('a.txt', 'v1');
    gp.userGit(['init', '-q']);
    gp.userGit(['add', '-A']);
    gp.userGit(['commit', '-q', '-m', 'init']);
    gp.put('a.txt', 'v2');
    final index = File(p.join(gp.project, '.git', 'index'));
    // --no-optional-locks: the test's own `git status` must not rewrite the index.
    String state() => [
      gp.userGit(['--no-optional-locks', 'status', '--porcelain']).stdout,
      gp.userGit(['rev-parse', 'HEAD']).stdout,
      gp.userGit(['for-each-ref']).stdout,
      gp.userGit(['stash', 'list']).stdout,
    ].join('|');
    final before = state();
    final indexBytes = index.readAsBytesSync();
    final mtime = index.lastModifiedSync();

    final s = store();
    final ck = (await s.snapshot('sess/1'))!;
    gp.put('a.txt', 'v3');
    await s.changes(ck.tree);
    await s.restore(ck.commit, ['a.txt']);

    expect(index.readAsBytesSync(), indexBytes);
    expect(index.lastModifiedSync(), mtime);
    expect(state(), before);
    expect(gp.userGit(['for-each-ref', 'refs/shellx']).stdout, '');
    expect(File(p.join(gp.project, 'a.txt')).readAsStringSync(), 'v2');
  });

  test('.gitignore is honoured', () async {
    gp
      ..put('.gitignore', 'secret.env\nbuild/\n')
      ..put('secret.env', 'A=1')
      ..put('build/out.js', 'x');
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    gp
      ..put('secret.env', 'A=2')
      ..put('build/out.js', 'y');
    expect(await s.changes(ck.tree), isEmpty);
  });

  test('a nested repository without commits does not break the snapshot (R4)', () async {
    gp
      ..put('top.txt', 'a')
      ..put('sub/repo/x.txt', 'x');
    gp.userGit(['init', '-q'], dir: p.join(gp.project, 'sub', 'repo'));
    final s = store();
    final ck = await s.snapshot('s/1');
    expect(ck, isNotNull);
    gp.put('sub/repo/x.txt', 'changed');
    expect(await s.changes(ck!.tree), isEmpty);
    expect(File(p.join(gp.gitDir, 'info', 'exclude')).readAsStringSync(), contains('/sub/repo/'));
  });

  test('a nested repository with commits is not added as a gitlink', () async {
    gp.put('lib/x.txt', 'x');
    final lib = p.join(gp.project, 'lib');
    gp.userGit(['init', '-q'], dir: lib);
    gp.userGit(['add', '-A'], dir: lib);
    gp.userGit(['commit', '-q', '-m', 'x'], dir: lib);
    gp.put('top.txt', 'a');
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    final tree = Process.runSync('git', ['--git-dir', gp.gitDir, 'ls-tree', '-r', ck.tree]).stdout as String;
    expect(tree, contains('top.txt'));
    expect(tree, isNot(contains('160000')));
    expect(tree, isNot(contains('lib')));
  });

  test('too many files: undo off, remembered', () async {
    for (var i = 0; i < 5; i++) {
      gp.put('f$i.txt', '$i');
    }
    expect(await store(maxFiles: 3).snapshot('s/1'), isNull);
    expect(store().off, UndoOff.tooManyFiles, reason: 'a new store for the same repo reads it back');
  });

  test('the first snapshot runs over its time: undo off, no lock left', () async {
    gp.put('a.txt', 'a');
    final s = store(first: Duration.zero);
    expect(await s.snapshot('s/1'), isNull);
    expect(s.off, UndoOff.tooSlow);
    expect(File(p.join(gp.gitDir, 'index.lock')).existsSync(), isFalse);
  });

  test('changed after the turn', () async {
    gp
      ..put('a.txt', '1')
      ..put('b.txt', '1');
    final s = store();
    await s.snapshot('s/1');
    gp.put('a.txt', '2'); // the agent
    final after = (await s.currentTree())!;
    gp.put('a.txt', '3'); // the user, later
    expect(await s.changedSince(after), {'a.txt'});
  });

  test('odd names: spaces, Vietnamese, glob characters', () async {
    final names = [
      'with space.txt',
      'Tiếng Việt.md',
      'br[1].txt',
      if (!Platform.isWindows) ...['star*.txt', 'q?.txt', 'colon:x.txt', 'back\\slash.txt'],
    ];
    for (final n in names) {
      gp.put(n, 'old $n');
    }
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    for (final n in names) {
      gp.put(n, 'new $n');
    }
    final changed = (await s.changes(ck.tree)).map((c) => c.path).toSet();
    expect(changed, names.toSet());
    for (final n in names) {
      expect(utf8.decode((await s.fileAt(ck.tree, n))!), 'old $n');
    }
    await s.restore(ck.commit, [names.first, names.last]);
    expect(File(p.join(gp.project, names.first)).readAsStringSync(), 'old ${names.first}');
    expect(File(p.join(gp.project, names.last)).readAsStringSync(), 'old ${names.last}');
    expect(File(p.join(gp.project, names[1])).readAsStringSync(), 'new ${names[1]}', reason: 'not asked for');
  });

  test('project attributes cannot change bytes (R3)', () async {
    gp
      ..put('.gitattributes', '* text=auto eol=crlf\n*.bin filter=lfs diff=lfs merge=lfs -text\n')
      ..put('lf.txt', 'a\nb\n')
      ..put('data.bin', [1, 2, 3]);
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    gp
      ..put('lf.txt', 'changed')
      ..put('data.bin', [9]);
    await s.restore(ck.commit, ['lf.txt', 'data.bin']);
    expect(gp.bytes('lf.txt'), utf8.encode('a\nb\n'));
    expect(gp.bytes('data.bin'), [1, 2, 3]);
  });

  test('a hostile global git config is neutralised (R3)', () async {
    final home = Directory(p.join(gp.tmp.path, 'home'))..createSync();
    final hooks = Directory(p.join(home.path, 'hooks'))..createSync();
    final marker = p.join(home.path, 'hook-ran');
    for (final h in ['pre-commit', 'post-commit', 'post-checkout', 'reference-transaction']) {
      final f = File(p.join(hooks.path, h))..writeAsStringSync('#!/bin/sh\necho ran > "$marker"\nexit 1\n');
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', f.path]);
    }
    File(p.join(home.path, 'ignore')).writeAsStringSync('*.log\n');
    File(p.join(home.path, '.gitconfig')).writeAsStringSync('''
[core]
  autocrlf = true
  hooksPath = ${hooks.path.replaceAll(r'\', '/')}
  excludesFile = ${p.join(home.path, 'ignore').replaceAll(r'\', '/')}
[commit]
  gpgSign = true
[gpg]
  program = /nonexistent/gpg
''');
    final env = {...Platform.environment, 'HOME': home.path, 'USERPROFILE': home.path, 'XDG_CONFIG_HOME': home.path};
    gp
      ..put('lf.txt', 'a\nb\n')
      ..put('debug.log', 'noise');
    final s = store(env: env);
    final ck = await s.snapshot('s/1');
    expect(ck, isNotNull, reason: 'no GPG, no hook');
    gp
      ..put('lf.txt', 'x')
      ..put('debug.log', 'more noise');
    expect((await s.changes(ck!.tree)).map((c) => c.path), ['lf.txt'], reason: 'the global excludesFile still applies');
    await s.restore(ck.commit, ['lf.txt']);
    expect(gp.bytes('lf.txt'), utf8.encode('a\nb\n'));
    expect(File(marker).existsSync(), isFalse);
  });

  test('files over the size cap are not tracked (R4)', () async {
    gp
      ..put('big.bin', List.filled(2048, 7))
      ..put('small.txt', 's');
    final s = store(maxFileBytes: 1024);
    final ck = (await s.snapshot('s/1'))!;
    gp
      ..put('big.bin', List.filled(2048, 8))
      ..put('small.txt', 't');
    expect((await s.changes(ck.tree)).map((c) => c.path), ['small.txt']);
  });

  test('prune drops checkpoints older than the retention', () async {
    gp.put('a.txt', 'a');
    final old = DateTime.now().subtract(const Duration(days: 30));
    await store(now: () => old).snapshot('s/1');
    gp.put('a.txt', 'b');
    await store().snapshot('s/2');
    expect(await store().prune(const Duration(days: 14)), 1);
    final refs = Process.runSync('git', ['--git-dir', gp.gitDir, 'for-each-ref', '--format=%(refname)']).stdout as String;
    expect(refs.trim(), 'refs/shellx/s/2');
  });

  test('operations on one project run one at a time', () async {
    gp.put('a.txt', 'a');
    final s = store();
    final results = await Future.wait([s.snapshot('s/1'), s.currentTree(), s.snapshot('s/2'), s.currentTree()]);
    expect(results.every((r) => r != null), isTrue);
  });

  test('excludePattern anchors and escapes', () {
    expect(excludePattern('sub/repo/'), '/sub/repo/');
    expect(excludePattern(r'a*b?[c]\d'), r'/a\*b\?\[c]\\d');
    expect(excludePattern('#x !y'), r'/\#x \!y');
    expect(excludePattern('trail '), r'/trail\ ');
  });

  test('projectId: 12 hex of sha1(realpath); case-insensitive on Windows', () {
    final a = CheckpointStores.projectId('/Users/a/proj', isWindows: false);
    expect(a, matches(RegExp(r'^[0-9a-f]{12}$')));
    expect(CheckpointStores.projectId('/Users/a/Proj', isWindows: false), isNot(a));
    expect(
      CheckpointStores.projectId(r'C:\Users\A\Proj', isWindows: true),
      CheckpointStores.projectId(r'c:\users\a\proj', isWindows: true),
    );
  });

  test('CheckpointStores: one store per project; pruneAll deletes repos of projects that are gone', () async {
    final stores = CheckpointStores(root: p.join(gp.tmp.path, 'support', 'ai', 'checkpoints'));
    final env = LoginEnv(Platform.environment, source: LoginEnvSource.process);
    gp.put('a.txt', 'a');
    final (s1, _) = await stores.forProject(gp.project, env);
    final (s2, _) = await stores.forProject('${gp.project}${Platform.pathSeparator}', env);
    expect(identical(s1, s2), isTrue);
    await s1!.snapshot('s/1');
    final gone = Directory(p.join(gp.tmp.path, 'gone'))..createSync();
    File(p.join(gone.path, 'x')).writeAsStringSync('x');
    final (s3, _) = await CheckpointStores(root: stores.root).forProject(gone.path, env);
    await s3!.snapshot('s/1');
    gone.deleteSync(recursive: true);
    await CheckpointStores(root: stores.root).pruneAll(const Duration(days: 14), env);
    expect(Directory(s1.gitDir).existsSync(), isTrue);
    expect(Directory(s3.gitDir).existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/host/git_locator_test.dart test/host/checkpoint_store_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement**

`lib/src/host/git_locator.dart`:

```dart
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import '../model/changes.dart';
import 'login_shell_env.dart';
import 'probe.dart';

/// Git as the checkpoints use it.
final class GitTool with Redacted {
  const GitTool(this.executable, this.major, this.minor);

  final String executable;
  final int major;
  final int minor;
}

/// Finds git on the login PATH (spec D12). On macOS `/usr/bin/git` is a
/// stub that opens the Command Line Tools installer when they are missing,
/// so `xcode-select -p` must succeed first. Git older than 2.26 has no
/// `restore --pathspec-from-file`.
final class GitLocator {
  GitLocator({ProbeRunner? probe, bool? isMacOS, bool? isWindows, this.files = const RealFileProbe()})
    : _probe = probe ?? runProbe,
      _isMacOS = isMacOS ?? Platform.isMacOS,
      _isWindows = isWindows ?? Platform.isWindows;

  final FileProbe files;
  final ProbeRunner _probe;
  final bool _isMacOS;
  final bool _isWindows;

  Future<(GitTool?, UndoOff?)> locate(LoginEnv env) async {
    final git = findExecutable('git', env.vars, isWindows: _isWindows, files: files);
    if (git == null) return (null, UndoOff.noGit);
    if (_isMacOS && git == '/usr/bin/git') {
      final r = await _probe('/usr/bin/xcode-select', const ['-p'], environment: env.vars);
      if (r == null || r.exitCode != 0) return (null, UndoOff.noCommandLineTools);
    }
    final v = await _probe(git, const ['--version'], environment: env.vars);
    final m = RegExp(r'git version (\d+)\.(\d+)').firstMatch(v?.stdout ?? '');
    if (v == null || v.exitCode != 0 || m == null) return (null, UndoOff.noGit);
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    if (major < 2 || (major == 2 && minor < 26)) return (null, UndoOff.gitTooOld);
    return (GitTool(git, major, minor), null);
  }
}
```

`lib/src/host/git_runner.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'git_locator.dart';

/// A git command failed or ran over its time. Never carries git's stderr:
/// it may name the user's files (spec D20).
final class GitFailed implements Exception {
  const GitFailed(this.exitCode, {this.timedOut = false});

  final int exitCode;
  final bool timedOut;

  @override
  String toString() => timedOut ? 'GitFailed(timeout)' : 'GitFailed($exitCode)';
}

/// Runs git against the shadow repository only (spec D12, ruling R3).
/// `GIT_DIR` and `GIT_WORK_TREE` are always set; every inherited `GIT_*`
/// variable is dropped; [flags] keep the user's config from changing
/// bytes, starting daemons or signing. Pathspecs are literal.
final class GitRunner {
  GitRunner({
    required this.git,
    required this.gitDir,
    required this.workTree,
    required Map<String, String> env,
    DateTime Function()? now,
  }) : _env = env,
       _now = now ?? DateTime.now;

  /// The user's global config cannot convert bytes, start fsmonitor,
  /// sign, gc, or run hooks: `core.hooksPath` points at the shadow repo's
  /// own `hooks` folder, which holds only inactive samples. A global
  /// `reference-transaction` hook would otherwise veto `update-ref`.
  List<String> get flags => [
    '-c', 'core.autocrlf=false',
    '-c', 'core.safecrlf=false',
    '-c', 'core.fsmonitor=false',
    '-c', 'core.quotePath=false',
    '-c', 'commit.gpgSign=false',
    '-c', 'gc.auto=0',
    '-c', 'maintenance.auto=false',
    '-c', 'core.logAllRefUpdates=false',
    '-c', 'core.longpaths=true',
    '-c', 'core.hooksPath=$gitDir${Platform.pathSeparator}hooks',
  ];

  final GitTool git;
  final String gitDir;
  final String workTree;
  final Map<String, String> _env;
  final DateTime Function() _now;

  Map<String, String> _environment() {
    final when = '${_now().toUtc().millisecondsSinceEpoch ~/ 1000} +0000';
    return {
      for (final e in _env.entries)
        if (!e.key.toUpperCase().startsWith('GIT_')) e.key: e.value,
      'GIT_DIR': gitDir,
      'GIT_WORK_TREE': workTree,
      'GIT_LITERAL_PATHSPECS': '1',
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_AUTHOR_NAME': 'ShellX',
      'GIT_AUTHOR_EMAIL': 'checkpoint@shellx.invalid',
      'GIT_COMMITTER_NAME': 'ShellX',
      'GIT_COMMITTER_EMAIL': 'checkpoint@shellx.invalid',
      'GIT_AUTHOR_DATE': when,
      'GIT_COMMITTER_DATE': when,
    };
  }

  /// Runs `git <flags> <args>`; returns stdout, throws [GitFailed].
  Future<List<int>> run(
    List<String> args, {
    List<int>? input,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final process = await Process.start(
      git.executable,
      [...flags, ...args],
      workingDirectory: workTree,
      environment: _environment(),
      includeParentEnvironment: false,
    );
    if (input != null) process.stdin.add(input);
    unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
    unawaited(process.stderr.drain<void>());
    final out = BytesBuilder(copy: false);
    final outDone = process.stdout.listen(out.add).asFuture<void>();
    final int code;
    try {
      code = await process.exitCode.timeout(timeout);
      await outDone;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
      final lock = File('$gitDir${Platform.pathSeparator}index.lock');
      if (lock.existsSync()) {
        try {
          lock.deleteSync();
        } on FileSystemException {
          // Left for the next run to fail on; undo is off anyway.
        }
      }
      throw const GitFailed(-1, timedOut: true);
    }
    if (code != 0) throw GitFailed(code);
    return out.takeBytes();
  }

  Future<String> text(List<String> args, {List<int>? input, Duration timeout = const Duration(seconds: 60)}) async =>
      utf8.decode(await run(args, input: input, timeout: timeout), allowMalformed: true);
}
```

`lib/src/host/checkpoint_store.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import '../model/changes.dart';
import 'git_locator.dart';
import 'git_runner.dart';
import 'login_shell_env.dart';
import 'serial_queue.dart';

/// Files bigger than this are not checkpointed (ruling R4).
const kMaxCheckpointFileBytes = 50 * 1024 * 1024;

/// A `.gitignore` line for exactly [relPath] (a folder when it ends with
/// `/`): anchored at the root, special characters escaped.
String excludePattern(String relPath) {
  final b = StringBuffer('/');
  for (final ch in relPath.split('')) {
    if (r'\*?[!#'.contains(ch)) b.write(r'\');
    b.write(ch);
  }
  var s = b.toString();
  var spaces = 0;
  while (s.endsWith(' ')) {
    s = s.substring(0, s.length - 1);
    spaces++;
  }
  return s + r'\ ' * spaces;
}

/// What the runtime needs from checkpoints (a fake in runtime tests).
abstract interface class Checkpoints {
  UndoOff? get off;
  Future<Checkpoint?> snapshot(String ref);
  Future<String?> currentTree();
  Future<List<FileChange>> changes(String fromTree, [String? toTree]);
  Future<Set<String>> changedSince(String tree);
  Future<List<int>?> fileAt(String treeish, String path);
  Future<void> restore(String treeish, Iterable<String> paths);
}

/// Snapshots of one project in a hidden git repository, for undo (spec
/// D12). Never touches the project's own `.git`: every command runs with
/// `GIT_DIR=<gitDir>` and `GIT_WORK_TREE=<project>` ([GitRunner]).
/// Operations run one at a time.
final class CheckpointStore with Redacted implements Checkpoints {
  CheckpointStore({
    required this.project,
    required this.gitDir,
    required GitTool git,
    required Map<String, String> env,
    this.maxFiles = 200000,
    this.firstSnapshotLimit = const Duration(seconds: 30),
    this.maxFileBytes = kMaxCheckpointFileBytes,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _git = GitRunner(git: git, gitDir: gitDir, workTree: project, env: env, now: now) {
    _off = _readOff();
  }

  static const _offRetry = Duration(days: 7);
  static const _excludeHeader =
      '# Managed by ShellX: nested repositories and files over 50 MiB are not checkpointed.\n';

  final String project;
  final String gitDir;
  final int maxFiles;
  final Duration firstSnapshotLimit;
  final int maxFileBytes;
  final GitRunner _git;
  final DateTime Function() _now;
  final _queue = SerialQueue();
  UndoOff? _off;

  /// Why undo is off for this project; null when it works.
  @override
  UndoOff? get off => _off;

  File get _meta => File(p.join(gitDir, 'shellx.json'));

  /// Takes a checkpoint as `refs/shellx/<ref>`. Null when undo is off or
  /// the snapshot failed: the turn still runs (spec §6).
  @override
  Future<Checkpoint?> snapshot(String ref) => _serial(() async {
    if (_off != null) return null;
    final first = !File(p.join(gitDir, 'index')).existsSync();
    final limit = first ? firstSnapshotLimit : const Duration(minutes: 2);
    final clock = Stopwatch()..start();
    Duration left() {
      final l = limit - clock.elapsed;
      return l.isNegative ? Duration.zero : l;
    }

    try {
      await _ensureRepo();
      final untracked = _split(await _git.text(['ls-files', '-z', '--others', '--exclude-standard'], timeout: left()));
      if (untracked.length > maxFiles) {
        if (first) _setOff(UndoOff.tooManyFiles);
        return null;
      }
      await _exclude(untracked, left());
      await _git.run(['add', '-A'], timeout: left());
      final tree = (await _git.text(['write-tree'])).trim();
      final commit = (await _git.text(['commit-tree', tree, '-m', 'ShellX checkpoint'])).trim();
      await _git.run(['update-ref', 'refs/shellx/$ref', commit]);
      return Checkpoint(commit: commit, tree: tree);
    } on GitFailed catch (e) {
      if (first) _setOff(e.timedOut ? UndoOff.tooSlow : UndoOff.failed);
      return null;
    } on FileSystemException {
      if (first) _setOff(UndoOff.failed);
      return null;
    }
  });

  /// The project as it is now (a tree); null when undo is off or it fails.
  @override
  Future<String?> currentTree() => _serial(() async {
    if (_off != null) return null;
    try {
      return await _treeNow();
    } on GitFailed {
      return null;
    }
  });

  /// What changed from [fromTree] to [toTree], or to the project now.
  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) => _serial(() async {
    final to = toTree ?? await _treeNow();
    final numstat = _split(await _git.text(['diff-tree', '-r', '--no-renames', '--numstat', '-z', fromTree, to]));
    final status = _split(await _git.text(['diff-tree', '-r', '--no-renames', '--name-status', '-z', fromTree, to]));
    final kinds = <String, ChangeKind>{};
    for (var i = 0; i + 1 < status.length; i += 2) {
      kinds[status[i + 1]] = switch (status[i]) {
        'A' => ChangeKind.added,
        'D' => ChangeKind.deleted,
        _ => ChangeKind.modified,
      };
    }
    return [
      for (final record in numstat)
        if (_numstat(record) case (final added, final removed, final path))
          FileChange(path: path, kind: kinds[path] ?? ChangeKind.modified, added: added, removed: removed),
    ];
  });

  /// Files that differ between [tree] and the project now ("đã sửa sau lượt").
  @override
  Future<Set<String>> changedSince(String tree) => _serial(() async {
    final now = await _treeNow();
    return _split(await _git.text(['diff-tree', '-r', '--no-renames', '--name-only', '-z', tree, now])).toSet();
  });

  /// The bytes of [path] in [treeish]; null when it is not there.
  @override
  Future<List<int>?> fileAt(String treeish, String path) => _serial(() async {
    try {
      return await _git.run(['cat-file', 'blob', '$treeish:$path']);
    } on GitFailed {
      return null;
    }
  });

  /// Writes [paths] back as they were in [treeish], byte for byte. A path
  /// that was not there is deleted, with the folders left empty (R5).
  @override
  Future<void> restore(String treeish, Iterable<String> paths) => _serial(() async {
    final wanted = paths.toSet();
    if (wanted.isEmpty) return;
    final inTree = _split(await _git.text(['ls-tree', '-r', '-z', '--name-only', treeish])).toSet();
    final back = wanted.where(inTree.contains).toList();
    if (back.isNotEmpty) {
      await _git.run(
        ['restore', '--source=$treeish', '--worktree', '--pathspec-from-file=-', '--pathspec-file-nul'],
        input: utf8.encode('${back.join('\x00')}\x00'),
      );
    }
    for (final path in wanted.where((w) => !inTree.contains(w))) {
      final file = File(p.join(project, path));
      if (file.existsSync()) file.deleteSync();
      _removeEmptyFolders(file.parent);
    }
  });

  /// Drops checkpoints older than [olderThan] and the data only they kept;
  /// returns how many were dropped.
  Future<int> prune(Duration olderThan) => _serial(() async {
    if (!File(p.join(gitDir, 'HEAD')).existsSync()) return 0;
    final cutoff = _now().subtract(olderThan).millisecondsSinceEpoch ~/ 1000;
    final out = await _git.text(['for-each-ref', '--format=%(refname) %(committerdate:unix)', 'refs/shellx/']);
    final old = <String>[];
    for (final line in const LineSplitter().convert(out)) {
      final space = line.lastIndexOf(' ');
      if (space > 0 && (int.tryParse(line.substring(space + 1)) ?? 0) < cutoff) old.add(line.substring(0, space));
    }
    if (old.isEmpty) return 0;
    await _git.run(['update-ref', '--stdin'], input: utf8.encode(old.map((r) => 'delete $r\n').join()));
    await _git.run(['gc', '--prune=now', '-q'], timeout: const Duration(minutes: 5));
    return old.length;
  });

  /// Whether any checkpoint is left.
  Future<bool> hasCheckpoints() => _serial(() async {
    if (!File(p.join(gitDir, 'HEAD')).existsSync()) return false;
    return (await _git.text(['for-each-ref', '--count=1', 'refs/shellx/'])).trim().isNotEmpty;
  });

  Future<String> _treeNow() async {
    final untracked = _split(await _git.text(['ls-files', '-z', '--others', '--exclude-standard']));
    await _exclude(untracked, const Duration(minutes: 2));
    await _git.run(['add', '-A'], timeout: const Duration(minutes: 2));
    return (await _git.text(['write-tree'])).trim();
  }

  Future<void> _ensureRepo() async {
    if (File(p.join(gitDir, 'HEAD')).existsSync()) return;
    Directory(gitDir).createSync(recursive: true);
    await _git.run(['init', '-q']);
    File(p.join(gitDir, 'info', 'attributes'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('* -text -filter -ident -working-tree-encoding\n');
    File(p.join(gitDir, 'info', 'exclude')).writeAsStringSync(_excludeHeader);
    _writeMeta();
  }

  /// Keeps nested repositories and big new files out (ruling R4).
  Future<void> _exclude(List<String> untracked, Duration timeout) async {
    final nested = [for (final e in untracked) if (e.endsWith('/')) e];
    final big = <String>[];
    for (final e in untracked) {
      if (e.endsWith('/')) continue;
      try {
        if (File(p.join(project, e)).lengthSync() > maxFileBytes) big.add(e);
      } on FileSystemException {
        // Gone already: `add -A` sees that.
      }
    }
    if (nested.isEmpty && big.isEmpty) return;
    final file = File(p.join(gitDir, 'info', 'exclude'));
    final have = file.existsSync() ? file.readAsLinesSync().toSet() : <String>{};
    final add = [for (final e in [...nested, ...big]) excludePattern(e)].where((l) => !have.contains(l)).toList();
    if (add.isNotEmpty) file.writeAsStringSync('${add.join('\n')}\n', mode: FileMode.append);
    if (nested.isNotEmpty) {
      await _git.run([
        'rm', '-r', '--cached', '-q', '--ignore-unmatch', '--',
        for (final n in nested) n.substring(0, n.length - 1),
      ], timeout: timeout);
    }
  }

  void _removeEmptyFolders(Directory dir) {
    final root = p.canonicalize(project);
    var d = dir;
    while (p.isWithin(root, p.canonicalize(d.path))) {
      try {
        if (d.listSync().isNotEmpty) return;
        d.deleteSync();
      } on FileSystemException {
        return;
      }
      d = d.parent;
    }
  }

  UndoOff? _readOff() {
    try {
      final j = jsonDecode(_meta.readAsStringSync());
      if (j is! Map) return null;
      final reason = UndoOff.values.where((o) => o.name == j['off']).firstOrNull;
      final at = j['offAt'];
      if (reason == null || at is! int) return null;
      final since = _now().difference(DateTime.fromMillisecondsSinceEpoch(at));
      return since > _offRetry ? null : reason;
    } on Object {
      return null;
    }
  }

  void _setOff(UndoOff reason) {
    _off = reason;
    _writeMeta(off: reason);
  }

  void _writeMeta({UndoOff? off}) {
    try {
      Directory(gitDir).createSync(recursive: true);
      _meta.writeAsStringSync(jsonEncode({
        'project': project,
        if (off != null) 'off': off.name,
        if (off != null) 'offAt': _now().millisecondsSinceEpoch,
      }));
    } on FileSystemException {
      // Read-only support folder: undo is off for this run only.
    }
  }

  static List<String> _split(String z) => z.split('\x00').where((s) => s.isNotEmpty).toList();

  /// `added\tremoved\tpath`; `-` counts mean binary.
  static (int?, int?, String)? _numstat(String record) {
    final a = record.indexOf('\t');
    final b = a < 0 ? -1 : record.indexOf('\t', a + 1);
    if (b < 0) return null;
    return (int.tryParse(record.substring(0, a)), int.tryParse(record.substring(a + 1, b)), record.substring(b + 1));
  }

  Future<T> _serial<T>(Future<T> Function() op) => _queue.run(op);
}

/// Every project's [CheckpointStore], one per project so each has one
/// queue (spec D12).
final class CheckpointStores {
  CheckpointStores({
    required this.root,
    GitLocator? locator,
    bool? isWindows,
    CheckpointStore Function(String project, String gitDir, GitTool git, Map<String, String> env)? create,
  }) : _locator = locator ?? GitLocator(),
       _isWindows = isWindows ?? Platform.isWindows,
       _create = create ??
           ((project, gitDir, git, env) => CheckpointStore(project: project, gitDir: gitDir, git: git, env: env));

  /// `<app support>/ai/checkpoints`.
  final String root;
  final GitLocator _locator;
  final bool _isWindows;
  final CheckpointStore Function(String, String, GitTool, Map<String, String>) _create;
  final _stores = <String, CheckpointStore>{};
  Future<(GitTool?, UndoOff?)>? _git;

  static String projectId(String realPath, {required bool isWindows}) =>
      sha1.convert(utf8.encode(isWindows ? realPath.toLowerCase() : realPath)).toString().substring(0, 12);

  /// The store for [project], or why undo is off on this machine.
  Future<(CheckpointStore?, UndoOff?)> forProject(String project, LoginEnv env) async {
    final (git, off) = await (_git ??= _locator.locate(env));
    if (git == null) return (null, off);
    final real = _real(project);
    final id = projectId(real, isWindows: _isWindows);
    return (_stores.putIfAbsent(id, () => _create(real, p.join(root, id), git, env.vars)), null);
  }

  /// At app start: drop old checkpoints; delete the repos of projects that
  /// are gone or have none left (spec D12, `ai-checkpoint-days`).
  Future<void> pruneAll(Duration olderThan, LoginEnv env) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return;
    final (git, _) = await (_git ??= _locator.locate(env));
    for (final repo in dir.listSync().whereType<Directory>()) {
      String? project;
      try {
        final j = jsonDecode(File(p.join(repo.path, 'shellx.json')).readAsStringSync());
        if (j is Map && j['project'] is String) project = j['project'] as String;
      } on Object {
        project = null;
      }
      if (project == null || git == null || !Directory(project).existsSync()) {
        _delete(repo);
        continue;
      }
      final store = CheckpointStore(project: project, gitDir: repo.path, git: git, env: env.vars);
      try {
        await store.prune(olderThan);
        if (!await store.hasCheckpoints()) _delete(repo);
      } on GitFailed {
        // Try again next start.
      }
    }
  }

  /// "Xoá điểm khôi phục" in Settings (no turn may be running).
  Future<void> deleteAll() async {
    _stores.clear();
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  static void _delete(Directory d) {
    try {
      d.deleteSync(recursive: true);
    } on FileSystemException {
      // In use: next start.
    }
  }

  String _real(String path) {
    var real = path;
    try {
      real = Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Keep it as given; the snapshot fails and says so.
    }
    while (real.length > 1 && (real.endsWith('/') || real.endsWith(r'\')) && !real.endsWith(r':\')) {
      real = real.substring(0, real.length - 1);
    }
    return real;
  }
}
```

Add the exports to `lib/host.dart`: `export 'src/host/checkpoint_store.dart';`, `export 'src/host/git_locator.dart';`, `export 'src/host/git_runner.dart';`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/host && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: all pass; `No issues found!`

If `git restore` on this git version deletes a path outside the checkpoint before Dart does, that is fine: the test checks the outcome, not the order.

The hostile-config test includes a failing global `reference-transaction` hook. Without the `core.hooksPath` flag, `update-ref` would abort, and the snapshot would fail.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_ai pubspec.lock
git commit -m "feat(v2-ai): shadow-git checkpoints — snapshot, diff, exact restore, thresholds, nested repos, retention

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `AiRuntime` (one AI tab) and `AiHost` (app-wide wiring)

**Files:**
- Create: `packages/shellx_ai/lib/src/host/ai_runtime.dart`
- Create: `packages/shellx_ai/lib/src/host/ai_host.dart`
- Modify: `packages/shellx_ai/lib/host.dart` (exports)
- Test: `test/host/ai_runtime_test.dart`, `test/host/ai_host_test.dart`

**Interfaces:**
- Consumes:
  - Task 3: `AcpClient`, `JsonRpcConnection`.
  - Task 5: `AiSessionState` and the model.
  - Task 6: `AgentReadiness`, `AgentCommand`, `LoginShellEnv`, `AgentResolver`.
  - Task 7: `AgentChannel`, `AgentLauncher`, `AgentProcess`, `RunningAgents`, `FakeLauncher`.
  - Task 8: `Checkpoints`, `CheckpointStores`.
- Produces:
  - `enum AiStatus { running, needsInput, idle, ended }` (A12 states: spec D13).
  - `final class AiRuntime`:
    - constructor:

      ```dart
      AiRuntime({
        required AiSessionState state,
        required Future<AgentReadiness> Function() resolve,
        required AgentLauncher launch,
        required String clientVersion,
        Future<(Checkpoints?, UndoOff?)> Function()? checkpoints,
        String? resumeSessionId,
        Map<String, Object> preferredConfig = const {},
        Duration initializeTimeout = const Duration(seconds: 30),
        Duration cancelGrace = const Duration(seconds: 10),
        DateTime Function()? now,
        String? sessionKey,
      })
      ```

    - fields: `state`, `onStatus`.
    - lifecycle:
      - `Future<void> start()`, `Future<void> restart()`, `Future<void> retry()`, `Future<void> dispose()`
      - `Future<bool> authenticate(String methodId)`, `AgentCommand? loginCommand(AuthMethodTerminal method)`
    - turns:
      - `Future<bool> send(List<ContentBlock> prompt)`, `void cancel()`, `Future<void> forceStop()`, `Future<void> whenIdle()`
      - `void answerPermission(int id, String? optionId)`, `void answerAsk(int id, ElicitationResponse response)`
    - settings: `Future<void> setConfig(String configId, Object value)`, `Future<void> setMode(String modeId)`, `Future<ListSessionsResult?> listSessions({String? cursor})`.
    - undo:
      - `Checkpoint? checkpointOf(int turn)`
      - `Future<List<FileChange>?> changesSince(int turn)`, `Future<List<FileChange>?> sessionChanges()`, `Future<Set<String>?> changedAfterTurn(int turn)`
      - `Future<bool> revert(int turn, Iterable<String> paths)`, `Future<bool> revertSession(Iterable<String> paths)`
      - `Future<List<int>?> fileBefore(int turn, String path)`
    - `String get stderrTail`.
  - `final class AiHost`:
    - constructor: `AiHost({required String supportDir, required String clientVersion, LoginShellEnv? env, AgentResolver? resolver, CheckpointStores? checkpoints, RunningAgents? running, KillTree killTree = killOnly, DateTime Function()? now})`.
    - members:
      - `Future<AgentChannel> launch(AgentCommand, {required String cwd})`
      - `AiRuntime runtime({required AgentSpec agent, required String cwd, String? resumeSessionId, Map<String, Object> preferredConfig = const {}})`
      - `Future<int> startup({Duration retention = const Duration(days: 14)})`

This task relies on three things from earlier tasks:
- `FakeScenario.loadSessionError` (Task 3);
- `FakeLauncher(first, [later])` (Task 7);
- the `Checkpoints` interface (Task 8).

If one is missing, add it as those tasks show.

- [ ] **Step 1: Write the failing tests**

`test/host/ai_runtime_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:test/test.dart';

/// A runtime on in-process fake agents, in a temp project.
final class Rig {
  Rig(
    FakeScenario first, {
    List<FakeScenario> later = const [],
    Future<AgentReadiness> Function()? resolve,
    Future<(Checkpoints?, UndoOff?)> Function()? checkpoints,
    bool realCheckpoints = false,
    String? resume,
    Map<String, Object> preferred = const {},
    Duration cancelGrace = const Duration(seconds: 10),
  }) : tmp = Directory.systemTemp.createTempSync('runtime') {
    Directory(project).createSync();
    launcher = FakeLauncher(first, later);
    final stores = CheckpointStores(root: p.join(tmp.path, 'support', 'ai', 'checkpoints'));
    runtime = AiRuntime(
      state: AiSessionState(agentId: 'fake', agentName: 'Fake', cwd: project),
      resolve: resolve ?? () async => const AgentReady(AgentCommand(executable: 'fake-agent', args: ['--acp'])),
      launch: launcher.call,
      clientVersion: '2.0.0',
      checkpoints: checkpoints ??
          (realCheckpoints
              ? () async => stores.forProject(project, LoginEnv(Platform.environment, source: LoginEnvSource.process))
              : null),
      resumeSessionId: resume,
      preferredConfig: preferred,
      cancelGrace: cancelGrace,
      sessionKey: 'k1',
    )..onStatus = statuses.add;
  }

  final Directory tmp;
  late final FakeLauncher launcher;
  late final AiRuntime runtime;
  final statuses = <AiStatus>[];

  String get project => p.join(tmp.path, 'project');
  AiSessionState get state => runtime.state;
  FakeAgent agent([int i = -1]) => (i < 0 ? launcher.channels.last : launcher.channels[i]).agent;

  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 400 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  Future<void> dispose() async {
    await runtime.dispose();
    tmp.deleteSync(recursive: true);
  }
}

const hi = [TextBlock('hi')];

void main() {
  test('start: D1 initialize, new session, preferred config — never Bypass (R6)', () async {
    final r = Rig(
      const FakeScenario(configOptions: [
        {'id': 'mode', 'name': 'Mode', 'category': 'mode', 'type': 'select', 'currentValue': 'default', 'options': [
          {'value': 'default', 'name': 'Manual'},
          {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
        ]},
        {'id': 'model', 'name': 'Model', 'type': 'select', 'currentValue': 'a', 'options': [
          {'value': 'a', 'name': 'A'},
          {'value': 'b', 'name': 'B'},
        ]},
      ]),
      preferred: {'model': 'b', 'mode': 'bypassPermissions', 'gone': 'x'},
    );
    addTearDown(r.dispose);
    await r.runtime.start();
    expect(r.state.phase, AgentPhase.ready);
    expect(r.state.sessionId, 'sess-1');
    expect(r.agent().params['initialize'], initializeParams(clientVersion: '2.0.0'));
    expect(r.agent().received, contains('session/set_config_option:model=b'));
    expect(r.agent().received.where((e) => e.contains('bypassPermissions')), isEmpty);
    expect(r.state.configOptions!.firstWhere((o) => o.id == 'model').currentValue, 'b');
    expect(r.launcher.commands.single.args, ['--acp']);
  });

  test('a turn: prompt, merged text, a finished card, the summary; running → idle', () async {
    final r = Rig(FakeScenario(turns: [
      [
        FakeSteps.text('Hel'),
        FakeSteps.text('lo'),
        FakeSteps.tool('t1', 'Read a.txt', kind: 'read', status: 'in_progress'),
        FakeSteps.toolUpdate('t1', status: 'completed'),
      ],
    ]));
    addTearDown(r.dispose);
    await r.runtime.start();
    expect(await r.runtime.send(hi), isTrue);
    await r.runtime.whenIdle();
    final items = r.state.timeline.items;
    expect((items[0] as UserItem).text, 'hi');
    expect((items[1] as AgentTextItem).text, 'Hello');
    expect((items[2] as ToolItem).end, ToolEnd.completed);
    expect((items[3] as TurnEndItem).outcome, TurnOutcome.finished);
    expect((items[3] as TurnEndItem).stopReason, StopReason.endTurn);
    expect(r.statuses, [AiStatus.running, AiStatus.idle]);
    expect(r.state.label, 'hi');
  });

  test('permission: needs input, the answer reaches the agent', () async {
    final r = Rig(FakeScenario(turns: [
      [FakeSteps.permission('e1', 'Edit a.txt'), FakeSteps.text('done')],
    ]));
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.currentPermission != null);
    expect(r.statuses, [AiStatus.running, AiStatus.needsInput]);
    final p = r.state.currentPermission!;
    expect(p.title, 'Edit a.txt');
    r.runtime.answerPermission(p.id, 'allow-once');
    await r.runtime.whenIdle();
    expect(r.agent().received, contains('permission:allow-once'));
    expect(r.statuses, [AiStatus.running, AiStatus.needsInput, AiStatus.running, AiStatus.idle]);
  });

  test('cancel answers open questions cancelled; the turn ends cancelled', () async {
    final r = Rig(FakeScenario(turns: [
      [FakeSteps.permission('x', 'Run rm -rf build', kind: 'execute')],
    ]));
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.currentPermission != null);
    final card = r.state.currentPermission!.item;
    r.runtime.cancel();
    await r.runtime.whenIdle();
    expect(r.agent().received, containsAllInOrder(['session/cancel', 'permission:cancelled']));
    expect(card.permissionCancelled, isTrue);
    expect(r.state.timeline.items.whereType<TurnEndItem>().single.outcome, TurnOutcome.cancelled);
    expect(r.state.needsInput, isFalse);
  });

  test('a hung agent: Force stop after the grace; the next prompt restarts and loads (spec §1.4)', () async {
    final r = Rig(
      FakeScenario(turns: [[FakeSteps.text('working'), FakeSteps.hang()]]),
      later: [
        FakeScenario(
          history: [
            {'sessionUpdate': 'user_message_chunk', 'content': {'type': 'text', 'text': 'hi'}},
          ],
          turns: [[FakeSteps.text('after restart')]],
        ),
      ],
      cancelGrace: const Duration(milliseconds: 50),
    );
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.timeline.items.whereType<AgentTextItem>().isNotEmpty);
    r.runtime.cancel();
    await r.until(() => r.state.turn?.canForceStop ?? false);
    await r.runtime.forceStop();
    await r.runtime.whenIdle();
    expect(r.launcher.channels.first.killCalls, 1);
    expect(r.state.phase, AgentPhase.stopped);
    expect(r.state.timeline.items.whereType<TurnEndItem>().single.outcome, TurnOutcome.cancelled);

    expect(await r.runtime.send(const [TextBlock('again')]), isTrue);
    await r.until(() => r.state.timeline.items.whereType<TurnEndItem>().length == 2);
    expect(r.launcher.channels, hasLength(2));
    expect(r.agent(1).received, containsAllInOrder(['session/load:sess-1', 'session/prompt:again']));
    expect(r.state.timeline.items.whereType<UserItem>().map((u) => u.text), ['hi', 'again'], reason: 'the replay is not drawn twice');
    expect(r.state.timeline.items.whereType<AgentTextItem>().last.text, 'after restart');
  });

  test('the agent dies mid-turn: interrupted, cards stopped, "dừng bất ngờ"; restart loads', () async {
    final r = Rig(
      FakeScenario(turns: [[FakeSteps.tool('t1', 'npm test', kind: 'execute', status: 'in_progress'), FakeSteps.exit(3)]]),
      later: [const FakeScenario()],
    );
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.phase == AgentPhase.failed);
    expect(r.state.timeline.items.whereType<TurnEndItem>().single.outcome, TurnOutcome.interrupted);
    expect(r.state.timeline.tool('t1')!.end, ToolEnd.stopped);
    expect(r.state.timeline.items.whereType<NoticeItem>().map((n) => n.notice), contains(isA<AgentExited>().having((n) => n.exitCode, 'code', 3)));
    expect(r.statuses.last, AiStatus.ended);
    await r.runtime.restart();
    expect(r.state.phase, AgentPhase.ready);
    expect(r.agent(1).received, contains('session/load:sess-1'));
  });

  test('output ShellX cannot read stops the agent and says so (spec §6)', () async {
    final r = Rig(FakeScenario(turns: [
      [FakeSteps.text('ok'), for (var i = 0; i < 21; i++) FakeSteps.raw('Welcome to my noisy profile $i'), FakeSteps.hang()],
    ]));
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.phase == AgentPhase.failed);
    expect(r.state.timeline.items.whereType<TurnEndItem>().single.outcome, TurnOutcome.interrupted);
    expect(
      r.state.timeline.items.whereType<NoticeItem>().single.notice,
      isA<AgentOutputInvalid>().having((n) => n.reason, 'reason', ConnectionCloseReason.tooManyBadLines),
    );
    expect(r.launcher.channels.single.exited, isTrue);
  });

  test('sign in: LoginNeeded, the terminal login command, retry after exit 0 (spec D8)', () async {
    final dir = Directory.systemTemp.createTempSync('auth');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = p.join(dir.path, 'signed-in');
    final r = Rig(FakeScenario(
      requireAuth: true,
      authFile: marker,
      authMethods: const [
        {'id': 'login', 'name': 'Log in', 'type': 'terminal', 'args': ['--login'], 'env': {'MODE': 'x'}},
      ],
    ));
    addTearDown(r.dispose);
    await r.runtime.start();
    expect(r.state.phase, AgentPhase.needsAuth);
    final notice = r.state.timeline.items.whereType<NoticeItem>().single;
    final method = (notice.notice as LoginNeeded).methods.single as AuthMethodTerminal;
    final login = r.runtime.loginCommand(method)!;
    expect([login.executable, ...login.args], ['fake-agent', '--acp', '--login']);
    expect(login.environment['MODE'], 'x');
    File(marker).writeAsStringSync(''); // what the run sheet's login leaves behind
    await r.runtime.retry();
    expect(r.state.phase, AgentPhase.ready);
    expect(notice.resolved, isTrue);
  });

  group('setup problems are cards, and nothing starts (spec §4.5)', () {
    Future<AiNotice> failWith(AgentReadiness readiness) async {
      final r = Rig(const FakeScenario(), resolve: () async => readiness);
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.failed);
      expect(r.launcher.channels, isEmpty);
      return r.state.timeline.items.whereType<NoticeItem>().single.notice;
    }

    test('node', () async {
      expect(await failWith(const AgentNeedsNode(required: 22, found: 'v20.1.0')),
          isA<NodeMissing>().having((n) => n.found, 'found', 'v20.1.0'));
    });
    test('install', () async {
      expect(await failWith(const AgentNeedsInstall(null)), isA<AgentNotInstalled>().having((n) => n.canInstall, 'can', isFalse));
    });
    test('missing command', () async {
      expect(await failWith(const AgentNotFound('opencode', shimOnly: true)),
          isA<AgentMissing>().having((n) => n.shimOnly, 'shim', isTrue));
    });
    test('missing folder', () async {
      final r = Rig(const FakeScenario());
      addTearDown(r.dispose);
      Directory(r.project).deleteSync();
      await r.runtime.start();
      expect(r.state.timeline.items.whereType<NoticeItem>().single.notice, isA<FolderMissing>());
    });
  });

  group('resume (spec D14)', () {
    test('session/load replays the old conversation', () async {
      final r = Rig(
        const FakeScenario(history: [
          {'sessionUpdate': 'user_message_chunk', 'content': {'type': 'text', 'text': 'q1'}},
          {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'a1'}},
        ]),
        resume: 'old-1',
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.sessionId, 'old-1');
      expect(r.state.timeline.items.map((i) => i.runtimeType.toString()), ['UserItem', 'AgentTextItem']);
      expect(r.state.label, 'q1');
    });

    test('an agent without loadSession: a new session and a note', () async {
      final r = Rig(const FakeScenario(loadSession: false), resume: 'old-1');
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.agent().received, contains('session/new'));
      expect(r.state.timeline.items.whereType<NoticeItem>().single.notice, isA<CannotResume>());
    });

    test('the agent forgot the session (-32002): a new session and a note', () async {
      final r = Rig(const FakeScenario(loadSessionError: {'code': -32002, 'message': 'not found'}), resume: 'old-1');
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.ready);
      expect(r.agent().received, containsAllInOrder(['session/load:old-1', 'session/new']));
      expect(r.state.timeline.items.whereType<NoticeItem>().single.notice, isA<CannotResume>());
    });
  });

  test('queue: prompts sent during a turn go out in order; at most 5 (spec D16)', () async {
    final r = Rig(FakeScenario(turns: [[FakeSteps.sleep(30), FakeSteps.text('ok')]]));
    addTearDown(r.dispose);
    await r.runtime.start();
    expect(await r.runtime.send(const [TextBlock('a')]), isTrue);
    for (final t in ['b', 'c', 'd', 'e', 'f']) {
      expect(await r.runtime.send([TextBlock(t)]), isTrue);
    }
    expect(await r.runtime.send(const [TextBlock('g')]), isFalse, reason: 'five already wait');
    await r.until(() => r.state.timeline.items.whereType<TurnEndItem>().length == 6);
    expect(
      r.agent().received.where((e) => e.startsWith('session/prompt:')),
      ['a', 'b', 'c', 'd', 'e', 'f'].map((t) => 'session/prompt:$t'),
    );
  });

  test('questions: a form answer; an unsupported form is declined by itself (spec D22)', () async {
    final r = Rig(FakeScenario(turns: [
      [
        FakeSteps.ask({
          'mode': 'form',
          'message': 'Approach?',
          'requestedSchema': {'type': 'object', 'properties': {'approach': {'type': 'string', 'enum': ['a', 'b']}}},
        }),
        FakeSteps.ask({'mode': 'form', 'message': 'File?', 'requestedSchema': {'type': 'object', 'properties': {'f': {'type': 'blob'}}}}),
      ],
    ]));
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.currentAsk != null);
    r.runtime.answerAsk(r.state.currentAsk!.id, const ElicitAccept({'approach': 'a'}));
    await r.runtime.whenIdle();
    expect(r.agent().received, containsAllInOrder(['ask:accept={"approach":"a"}', 'ask:decline']));
    expect(r.state.timeline.items.whereType<AskItem>().last.autoDeclined, isTrue);
  });

  test('an update after stopReason lands on the finished turn', () async {
    final r = Rig(FakeScenario(turns: [[FakeSteps.tool('bg', 'npm run dev', kind: 'execute', status: 'in_progress')]]));
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.runtime.whenIdle();
    r.agent().connection.notify('session/update', {
      'sessionId': 'sess-1',
      'update': {'sessionUpdate': 'tool_call_update', 'toolCallId': 'bg', 'status': 'completed'},
    });
    await r.until(() => r.state.timeline.tool('bg')!.end == ToolEnd.completed);
    expect(r.state.timeline.tool('bg')!.turn, 1);
  });

  group('checkpoints (spec D12, Review Focus 5)', () {
    test('a turn that writes files is listed and can be undone', () async {
      final r = Rig(
        FakeScenario(turns: [[FakeSteps.write('a.txt', 'after'), FakeSteps.write('new/n.txt', 'n')]]),
        realCheckpoints: true,
      );
      addTearDown(r.dispose);
      File(p.join(r.project, 'a.txt')).writeAsStringSync('before');
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      final end = r.state.timeline.items.whereType<TurnEndItem>().single;
      expect({for (final c in end.changes!) c.path: c.kind}, {'a.txt': ChangeKind.modified, 'new/n.txt': ChangeKind.added});
      expect((await r.runtime.changesSince(1))!.map((c) => c.path), unorderedEquals(['a.txt', 'new/n.txt']));
      File(p.join(r.project, 'a.txt')).writeAsStringSync('edited by the user later');
      expect(await r.runtime.changedAfterTurn(1), {'a.txt'});
      expect(await r.runtime.revert(1, ['a.txt', 'new/n.txt']), isTrue);
      expect(File(p.join(r.project, 'a.txt')).readAsStringSync(), 'before');
      expect(File(p.join(r.project, 'new', 'n.txt')).existsSync(), isFalse);
    });

    test('send waits for the first snapshot; the turn checkpoint is taken before the prompt', () async {
      final first = Completer<void>();
      final fake = FakeCheckpoints(warmupGate: first.future);
      final r = Rig(FakeScenario(turns: [[FakeSteps.text('ok')]]), checkpoints: () async => (fake, null));
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(r.agent().received.where((e) => e.startsWith('session/prompt')), isEmpty, reason: 'still snapshotting');
      first.complete();
      await r.runtime.whenIdle();
      expect(fake.refs, ['k1/0', 'k1/1']);
      expect(r.runtime.checkpointOf(1)!.commit, 'c-k1/1');
    });

    test('Stop while the snapshot runs: the prompt never goes out', () async {
      final gate = Completer<void>();
      final fake = FakeCheckpoints(turnGate: gate.future);
      final r = Rig(FakeScenario(turns: [[FakeSteps.text('ok')]]), checkpoints: () async => (fake, null));
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        return r.dispose();
      });
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => fake.refs.contains('k1/1'));
      r.runtime.cancel();
      await r.runtime.whenIdle().timeout(const Duration(seconds: 2));
      expect(r.state.timeline.items.whereType<TurnEndItem>().single.outcome, TurnOutcome.cancelled);
      expect(r.agent().received.where((e) => e.startsWith('session/prompt')), isEmpty);
    });

    test('undo off: a card says why; turns still run', () async {
      final r = Rig(FakeScenario(turns: [[FakeSteps.text('ok')]]), checkpoints: () async => (null, UndoOff.noCommandLineTools));
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(r.state.timeline.items.whereType<NoticeItem>().single.notice,
          isA<UndoUnavailable>().having((n) => n.reason, 'reason', UndoOff.noCommandLineTools));
      expect(r.state.timeline.items.whereType<TurnEndItem>().single.checkpoint, isNull);
    });
  });

  test('dispose stops the agent', () async {
    final r = Rig(const FakeScenario());
    await r.runtime.start();
    await r.dispose();
    expect(r.launcher.channels.single.stopCalls, 1);
    expect(r.launcher.channels.single.exited, isTrue);
    expect(r.statuses.last, AiStatus.ended);
  });

  test('toString is redacted', () {
    final r = Rig(const FakeScenario());
    addTearDown(r.dispose);
    expect(r.runtime.toString(), '…');
  });
}

/// Checkpoints without git: records refs; gates let a test hold a snapshot.
final class FakeCheckpoints implements Checkpoints {
  FakeCheckpoints({this.warmupGate, this.turnGate});

  final Future<void>? warmupGate;
  final Future<void>? turnGate;
  final refs = <String>[];

  @override
  UndoOff? get off => null;

  @override
  Future<Checkpoint?> snapshot(String ref) async {
    refs.add(ref);
    final gate = ref.endsWith('/0') ? warmupGate : turnGate;
    if (gate != null) await gate;
    return Checkpoint(commit: 'c-$ref', tree: 't-$ref');
  }

  @override
  Future<String?> currentTree() async => 'after';

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) async => const [];

  @override
  Future<Set<String>> changedSince(String tree) async => const {};

  @override
  Future<List<int>?> fileAt(String treeish, String path) async => null;

  @override
  Future<void> restore(String treeish, Iterable<String> paths) async {}
}
```

`test/host/ai_host_test.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ai_host'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('launch keeps running.json in step with the agent process', () async {
    final host = AiHost(supportDir: tmp.path, clientVersion: '2.0.0');
    final command = AgentCommand(
      executable: Platform.resolvedExecutable,
      args: fakeAgentArgs(writeScenario(const FakeScenario(), tmp)),
      environment: Platform.environment,
    );
    final channel = await host.launch(command, cwd: tmp.path) as AgentProcess;
    expect(host.running.read().single.pid, channel.pid);
    final client = AcpClient(JsonRpcConnection(input: channel.stdout, output: channel.stdin));
    await client.initialize(clientVersion: '2.0.0');
    await channel.stop();
    await channel.exitCode;
    for (var i = 0; i < 100 && host.running.read().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(host.running.read(), isEmpty);
    expect(File(p.join(tmp.path, 'ai', 'running.json')).existsSync(), isTrue);
  });

  test('startup sweeps leftovers', () async {
    final killed = <int>[];
    final t = DateTime.now();
    final running = RunningAgents(
      File(p.join(tmp.path, 'ai', 'running.json')),
      info: (pid) async => (command: '/usr/bin/node', startedAt: t),
      killPid: (pid) async => killed.add(pid),
    );
    await running.add(RunningRecord(pid: 4242, command: '/usr/local/bin/node', startedAt: t));
    // A login shell that answers at once, so the background prune stays hermetic.
    final env = LoginShellEnv(processEnv: {'PATH': '/usr/bin'}, run: (s, a, e, t) async => (0, <int>[]));
    final host = AiHost(supportDir: tmp.path, clientVersion: '2.0.0', running: running, env: env);
    expect(await host.startup(), 1);
    expect(killed, [4242]);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test test/host/ai_runtime_test.dart test/host/ai_host_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement `lib/src/host/ai_runtime.dart`**

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/changes.dart';
import '../model/notices.dart';
import '../model/session_state.dart';
import '../model/timeline.dart';
import 'agent_catalog.dart';
import 'agent_process.dart';
import 'checkpoint_store.dart';

/// What an AI tab reports to the A12 status model (spec D13).
enum AiStatus { running, needsInput, idle, ended }

/// One AI tab. Starts the agent and opens (or loads) its session. Takes a
/// checkpoint before every turn, sends prompts, answers permissions and
/// questions through [state], cancels and stops (spec D6–D16).
final class AiRuntime with Redacted {
  AiRuntime({
    required this.state,
    required Future<AgentReadiness> Function() resolve,
    required AgentLauncher launch,
    required this.clientVersion,
    Future<(Checkpoints?, UndoOff?)> Function()? checkpoints,
    String? resumeSessionId,
    this.preferredConfig = const {},
    this.initializeTimeout = const Duration(seconds: 30),
    this.cancelGrace = const Duration(seconds: 10),
    DateTime Function()? now,
    String? sessionKey,
  }) : _resolve = resolve,
       _launch = launch,
       _checkpoints = checkpoints,
       _resumeId = resumeSessionId,
       _now = now ?? DateTime.now,
       _key = sessionKey ?? 's${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  final AiSessionState state;
  final String clientVersion;

  /// Remembered choices per agent (spec D11), applied to new sessions.
  final Map<String, Object> preferredConfig;
  final Duration initializeTimeout;
  final Duration cancelGrace;

  /// A12 status changes, without repeats.
  void Function(AiStatus status)? onStatus;

  final Future<AgentReadiness> Function() _resolve;
  final AgentLauncher _launch;
  final Future<(Checkpoints?, UndoOff?)> Function()? _checkpoints;
  final DateTime Function() _now;
  final String _key;
  String? _resumeId;
  AgentCommand? _command;
  AgentChannel? _channel;
  AcpClient? _client;
  Future<void>? _starting;
  var _expectExit = false;
  var _forced = false;
  ConnectionCloseReason? _garbled;
  var _loading = false;
  var _keepTimeline = false;
  var _disposed = false;
  Checkpoints? _store;
  Future<void>? _warmup;
  Checkpoint? _firstCheckpoint;
  final _turnCheckpoints = <int, Checkpoint>{};
  final _afterTrees = <int, String>{};
  Timer? _cancelTimer;
  Completer<Checkpoint?>? _turnCancel;
  final _permissions = <int, Completer<PermissionOutcome>>{};
  final _asks = <int, Completer<ElicitationResponse>>{};
  final _idle = <Completer<void>>[];
  AiStatus? _lastStatus;

  /// What the agent wrote to stderr ("Xem log").
  String get stderrTail => _channel?.stderrTail ?? '';

  // ---------------------------------------------------------- lifecycle --

  /// Starts the agent and opens (or loads) the session. A restored tab
  /// calls this when it is first shown (spec D14).
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (_disposed) return;
    switch (state.phase) {
      case AgentPhase.starting || AgentPhase.ready || AgentPhase.running || AgentPhase.needsAuth:
        return;
      case AgentPhase.stopped || AgentPhase.failed:
        break;
    }
    state.setPhase(AgentPhase.starting);
    state.resolveNotices((n) => n is! UndoUnavailable && n is! CannotResume);
    if (!Directory(state.cwd).existsSync()) return _fail(const FolderMissing());
    switch (await _resolve()) {
      case AgentReady(:final command):
        _command = command;
      case AgentNeedsNode(:final required, :final found):
        return _fail(NodeMissing(required: required, found: found));
      case AgentNeedsInstall(:final install):
        return _fail(AgentNotInstalled(canInstall: install != null));
      case AgentNotFound(:final command, :final shimOnly):
        return _fail(AgentMissing(command, shimOnly: shimOnly));
    }
    final AgentChannel channel;
    try {
      channel = await _launch(_command!, cwd: state.cwd);
    } on Object {
      return _fail(const StartFailed(StartFailure.spawn));
    }
    _channel = channel;
    final client = AcpClient(JsonRpcConnection(input: channel.stdout, output: channel.stdin))
      ..onUpdate = _onUpdate
      ..onPermission = _onPermission
      ..onElicitation = _onElicitation
      ..onElicitationComplete = state.completeUrlAsk;
    _client = client;
    unawaited(channel.exitCode.then((code) => _onExit(channel, code)));
    // Output ShellX cannot read stops the agent (spec §6).
    unawaited(client.connection.done.then((reason) {
      if (identical(_client, client) &&
          (reason == ConnectionCloseReason.lineTooLong || reason == ConnectionCloseReason.tooManyBadLines)) {
        _garbled = reason;
        unawaited(channel.kill());
      }
    }));
    final InitializeResult init;
    try {
      init = await client.initialize(clientVersion: clientVersion).timeout(initializeTimeout);
    } on TimeoutException {
      await _stopAgent();
      return _fail(const StartFailed(StartFailure.timeout));
    } on JsonRpcError {
      await _stopAgent();
      return _fail(const StartFailed(StartFailure.protocol));
    } on ConnectionClosed {
      return; // _onExit has reported it.
    }
    if (init.protocolVersion != 1) {
      await _stopAgent();
      return _fail(const StartFailed(StartFailure.protocol));
    }
    state.setAgent(init);
    await _openSession();
  }

  Future<void> _openSession() async {
    final client = _client;
    if (client == null) return;
    final resume = _resumeId;
    var fresh = false;
    try {
      if (resume != null && state.capabilities.loadSession) {
        _loading = true;
        _keepTimeline = state.timeline.items.isNotEmpty;
        final r = await client.loadSession(sessionId: resume, cwd: state.cwd);
        state.setSession(resume, configOptions: r.configOptions, modes: r.modes);
      } else {
        if (resume != null) state.addNotice(const CannotResume());
        final r = await client.newSession(cwd: state.cwd);
        if (r.sessionId.isEmpty) {
          await _stopAgent();
          return _fail(const StartFailed(StartFailure.protocol));
        }
        state.setSession(r.sessionId, configOptions: r.configOptions, modes: r.modes);
        await _applyPreferred();
      }
    } on JsonRpcError catch (e) {
      if (e.code == JsonRpcError.authRequired) {
        state.addNotice(LoginNeeded(state.authMethods));
        state.setPhase(AgentPhase.needsAuth);
        _wakeIdle(force: true);
        return;
      }
      if (resume != null && e.code == JsonRpcError.resourceNotFound) {
        fresh = true;
      } else {
        await _stopAgent();
        return _fail(const StartFailed(StartFailure.session));
      }
    } on ConnectionClosed {
      return;
    } finally {
      _loading = false;
      _keepTimeline = false;
    }
    if (fresh) {
      _resumeId = null;
      state.addNotice(const CannotResume());
      return _openSession();
    }
    _resumeId = state.sessionId;
    state.resolveNotices((n) => n is LoginNeeded);
    state.setPhase(AgentPhase.ready);
    _warmCheckpoints();
    if (!_drainQueue()) _wakeIdle();
  }

  /// Applies remembered choices; never "Bypass permissions" (ruling R6).
  Future<void> _applyPreferred() async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    for (final MapEntry(key: id, :value) in preferredConfig.entries) {
      final option = state.configOptions?.where((o) => o.id == id).firstOrNull;
      if (option == null || option.currentValue == value) continue;
      final valid = switch (option.kind) {
        ConfigKind.select => value is String && option.choices.any((c) => c.value == value),
        ConfigKind.boolean => value is bool,
        ConfigKind.other => false,
      };
      final bypass = (option.category == 'mode' || option.id == 'mode') && value == 'bypassPermissions';
      if (!valid || bypass) continue;
      try {
        await _applyConfig(client, sid, id, value);
      } on JsonRpcError {
        // Keep the agent's value.
      }
    }
  }

  Future<void> _applyConfig(AcpClient client, String sid, String id, Object value) async {
    final updated = await client.setConfigOption(sid, id, value);
    state.configOptions = updated ??
        [for (final o in state.configOptions ?? const <ConfigOption>[]) o.id == id ? o.withValue(value) : o];
    state.touch();
  }

  /// The first snapshot of a project runs in the background (spec D12).
  void _warmCheckpoints() {
    final get = _checkpoints;
    if (get == null || _warmup != null) return;
    _warmup = () async {
      final (store, off) = await get();
      if (store == null) {
        if (off != null) state.addNotice(UndoUnavailable(off));
        return;
      }
      _store = store;
      final ck = store.off == null ? await store.snapshot('$_key/0') : null;
      final reason = store.off;
      if (ck == null && reason != null) state.addNotice(UndoUnavailable(reason));
    }().catchError((Object _) {});
  }

  /// "Khởi động lại": a new agent process, then `session/load`.
  Future<void> restart() async {
    await _stopAgent();
    state.setPhase(AgentPhase.stopped);
    await start();
  }

  /// After the run sheet's login exits 0, or after the setup is fixed
  /// (spec D8): a live agent reopens the session; otherwise start again.
  Future<void> retry() async {
    if (state.phase == AgentPhase.needsAuth && _client != null) {
      state.setPhase(AgentPhase.starting);
      await _openSession();
      return;
    }
    if (state.phase == AgentPhase.failed || state.phase == AgentPhase.stopped) await start();
  }

  /// For an agent-type login method: `authenticate`, then the session.
  Future<bool> authenticate(String methodId) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.authenticate(methodId);
    } on JsonRpcError {
      return false;
    } on ConnectionClosed {
      return false;
    }
    state.setPhase(AgentPhase.starting);
    await _openSession();
    return state.phase == AgentPhase.ready;
  }

  /// The run sheet's command for a terminal login: the agent's own command
  /// plus the method's args and env (spec D8). Null before a resolve.
  AgentCommand? loginCommand(AuthMethodTerminal method) => _command?.withArgs(method.args, method.env);

  Future<void> dispose() async {
    _disposed = true;
    _cancelTimer?.cancel();
    await _stopAgent();
    _wakeIdle(force: true);
  }

  // -------------------------------------------------------------- turns --

  /// Sends [prompt], or queues it while a turn runs or the agent starts
  /// (at most 5, spec D16). False when it cannot be taken.
  Future<bool> send(List<ContentBlock> prompt) async {
    switch (state.phase) {
      case AgentPhase.ready:
        unawaited(_runTurn(prompt));
        return true;
      case AgentPhase.running || AgentPhase.starting:
        return state.enqueue(prompt) != null;
      case AgentPhase.stopped:
        if (state.enqueue(prompt) == null) return false;
        unawaited(start());
        return true;
      case AgentPhase.needsAuth || AgentPhase.failed:
        return false;
    }
  }

  Future<void> _runTurn(List<ContentBlock> prompt) async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    final turn = state.beginTurn(prompt, _now());
    final cancelled = _turnCancel = Completer<Checkpoint?>();
    _status(AiStatus.running);
    final warmup = _warmup;
    if (warmup != null) await Future.any<void>([warmup, cancelled.future]);
    final store = _store;
    if (store != null && store.off == null && !turn.cancelRequested) {
      final snap = store.snapshot('$_key/${turn.index}').catchError((Object _) => null);
      final ck = await Future.any<Checkpoint?>([snap, cancelled.future]);
      if (!turn.cancelRequested) {
        if (ck == null) {
          state.addNotice(UndoUnavailable(store.off ?? UndoOff.failed, turnOnly: store.off == null));
        } else {
          turn.checkpoint = ck;
          _turnCheckpoints[turn.index] = ck;
          _firstCheckpoint ??= ck;
        }
      }
    }
    if (turn.cancelRequested) {
      // Stopped before the prompt went out: nothing to tell the agent.
      return _finishTurn(turn, TurnOutcome.cancelled, stopReason: StopReason.cancelled);
    }
    try {
      final reason = await client.prompt(sid, prompt);
      await _finishTurn(
        turn,
        reason == StopReason.cancelled ? TurnOutcome.cancelled : TurnOutcome.finished,
        stopReason: reason,
      );
    } on JsonRpcError catch (e) {
      await _finishTurn(turn, TurnOutcome.failed, error: e.message);
    } on ConnectionClosed {
      // The agent is gone: _onExit ends the turn.
    }
  }

  Future<void> _finishTurn(ActiveTurn turn, TurnOutcome outcome, {StopReason? stopReason, String? error}) async {
    if (!identical(state.turn, turn)) return;
    final endedAt = _now();
    _cancelTimer?.cancel();
    _cancelTimer = null;
    _cancelPending();
    String? after;
    List<FileChange>? changes;
    final store = _store;
    final ck = turn.checkpoint;
    if (store != null && ck != null) {
      after = await store.currentTree();
      if (after != null) {
        _afterTrees[turn.index] = after;
        changes = await store.changes(ck.tree, after).catchError((Object _) => <FileChange>[]);
      }
    }
    if (!identical(state.turn, turn)) return;
    state.endTurn(
      outcome: outcome,
      at: endedAt,
      stopReason: stopReason,
      error: error,
      afterTree: after,
      changes: changes,
    );
    if (!_drainQueue()) {
      _status(AiStatus.idle);
      _wakeIdle();
    }
  }

  bool _drainQueue() {
    if (state.phase != AgentPhase.ready || _client == null) return false;
    final next = state.takeQueued();
    if (next == null) return false;
    unawaited(_runTurn(next.blocks));
    return true;
  }

  /// Stop (Esc): `session/cancel`, and every open question is answered
  /// `cancelled`. After [cancelGrace], "Dừng hẳn" is offered (spec §1.4).
  void cancel() {
    final turn = state.turn;
    if (turn == null || turn.cancelRequested) return;
    turn.cancelRequested = true;
    final sid = state.sessionId;
    if (sid != null) _client?.cancel(sid);
    _cancelPending();
    final c = _turnCancel;
    if (c != null && !c.isCompleted) c.complete(null);
    _cancelTimer = Timer(cancelGrace, () {
      if (identical(state.turn, turn)) {
        turn.canForceStop = true;
        state.touch();
      }
    });
    state.touch();
  }

  /// "Dừng hẳn": kill the agent. The turn ends as stopped, and the next
  /// prompt restarts the agent with `session/load`.
  Future<void> forceStop() async {
    final channel = _channel;
    if (channel == null) return;
    _forced = true;
    await channel.kill();
  }

  /// Completes when no turn runs and nothing is queued (or the agent ended).
  Future<void> whenIdle() {
    if (state.turn == null && state.queue.isEmpty && state.phase != AgentPhase.starting) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  void _wakeIdle({bool force = false}) {
    if (!force && (state.turn != null || state.queue.isNotEmpty)) return;
    for (final c in _idle) {
      if (!c.isCompleted) c.complete();
    }
    _idle.clear();
  }

  // ------------------------------------------------- agent → user asks --

  Future<PermissionOutcome> _onPermission(PermissionRequest request) {
    if (state.turn?.cancelRequested ?? false) return Future.value(const PermissionCancelled());
    final p = state.addPermission(request, _now());
    final c = Completer<PermissionOutcome>();
    _permissions[p.id] = c;
    _status(AiStatus.needsInput);
    return c.future;
  }

  /// The user's pick on the permission bar; null = cancelled.
  void answerPermission(int id, String? optionId) =>
      _answerPermission(id, optionId == null ? const PermissionCancelled() : PermissionSelected(optionId));

  void _answerPermission(int id, PermissionOutcome outcome, {bool quiet = false}) {
    final c = _permissions.remove(id);
    if (c == null) return;
    state.resolvePermission(id, outcome);
    c.complete(outcome);
    if (!quiet && !state.needsInput && state.turn != null) _status(AiStatus.running);
  }

  Future<ElicitationResponse> _onElicitation(ElicitationRequest request) {
    if (state.turn?.cancelRequested ?? false) return Future.value(const ElicitCancel());
    if (request is ElicitationOther || (request is ElicitationForm && !request.supported)) {
      state.addAsk(request, autoDeclined: true);
      return Future.value(const ElicitDecline());
    }
    final a = state.addAsk(request)!;
    final c = Completer<ElicitationResponse>();
    _asks[a.id] = c;
    _status(AiStatus.needsInput);
    return c.future;
  }

  void answerAsk(int id, ElicitationResponse response) => _answerAsk(id, response);

  void _answerAsk(int id, ElicitationResponse response, {bool quiet = false}) {
    final c = _asks.remove(id);
    if (c == null) return;
    state.resolveAsk(id, response);
    c.complete(response);
    if (!quiet && !state.needsInput && state.turn != null) _status(AiStatus.running);
  }

  void _cancelPending() {
    for (final id in [..._permissions.keys]) {
      _answerPermission(id, const PermissionCancelled(), quiet: true);
    }
    for (final id in [..._asks.keys]) {
      _answerAsk(id, const ElicitCancel(), quiet: true);
    }
  }

  void _onUpdate(String sessionId, SessionUpdate update) {
    final current = state.sessionId;
    if (!_loading && current != null && sessionId != current) return;
    state.applyUpdate(update, _now(), history: _loading, timelineToo: !(_loading && _keepTimeline));
  }

  // ------------------------------------------------------------- config --

  Future<void> setConfig(String configId, Object value) async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    await _applyConfig(client, sid, configId, value);
  }

  /// For agents with only legacy `modes` (spec D11).
  Future<void> setMode(String modeId) async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    await client.setMode(sid, modeId);
    state.modes = state.modes?.withCurrent(modeId);
    state.touch();
  }

  /// `session/list` for this folder (spec D15); null when not offered.
  Future<ListSessionsResult?> listSessions({String? cursor}) async {
    final client = _client;
    if (client == null || !state.capabilities.listSessions) return null;
    try {
      return await client.listSessions(cwd: state.cwd, cursor: cursor);
    } on JsonRpcError {
      return null;
    } on ConnectionClosed {
      return null;
    }
  }

  // --------------------------------------------------------------- undo --

  Checkpoint? checkpointOf(int turn) => _turnCheckpoints[turn];

  /// The disk now against the checkpoint before [turn] ("Lượt này").
  Future<List<FileChange>?> changesSince(int turn) async {
    final ck = _turnCheckpoints[turn];
    final store = _store;
    return ck == null || store == null ? null : store.changes(ck.tree);
  }

  /// The disk now against the first checkpoint ("Cả phiên").
  Future<List<FileChange>?> sessionChanges() async {
    final ck = _firstCheckpoint;
    final store = _store;
    return ck == null || store == null ? null : store.changes(ck.tree);
  }

  /// Files changed since [turn] ended ("đã sửa sau lượt").
  Future<Set<String>?> changedAfterTurn(int turn) async {
    final after = _afterTrees[turn];
    final store = _store;
    return after == null || store == null ? null : store.changedSince(after);
  }

  /// Puts [paths] back as they were before [turn]. Refused while a turn runs.
  Future<bool> revert(int turn, Iterable<String> paths) async {
    final ck = _turnCheckpoints[turn];
    final store = _store;
    if (ck == null || store == null || state.turn != null) return false;
    await store.restore(ck.commit, paths);
    return true;
  }

  /// Puts [paths] back as they were before the first turn.
  Future<bool> revertSession(Iterable<String> paths) async {
    final ck = _firstCheckpoint;
    final store = _store;
    if (ck == null || store == null || state.turn != null) return false;
    await store.restore(ck.commit, paths);
    return true;
  }

  Future<List<int>?> fileBefore(int turn, String path) async {
    final ck = _turnCheckpoints[turn];
    final store = _store;
    return ck == null || store == null ? null : store.fileAt(ck.tree, path);
  }

  // ------------------------------------------------------------ process --

  Future<void> _stopAgent() async {
    final channel = _channel;
    if (channel == null) return;
    _expectExit = true;
    await channel.stop();
    await channel.exitCode;
  }

  void _onExit(AgentChannel channel, int code) {
    if (!identical(channel, _channel)) return;
    _channel = null;
    _client = null;
    _cancelTimer?.cancel();
    _cancelPending();
    final garbled = _garbled;
    final stopped = (_expectExit || _forced) && garbled == null;
    if (state.turn != null) {
      state.endTurn(
        outcome: stopped ? TurnOutcome.cancelled : TurnOutcome.interrupted,
        at: _now(),
        stopReason: stopped ? StopReason.cancelled : null,
      );
    }
    if (stopped) {
      state.setPhase(AgentPhase.stopped);
    } else {
      state.addNotice(garbled != null ? AgentOutputInvalid(garbled) : AgentExited(code));
      state.setPhase(AgentPhase.failed);
    }
    _expectExit = false;
    _forced = false;
    _garbled = null;
    _status(AiStatus.ended);
    _wakeIdle(force: true);
  }

  void _fail(AiNotice notice) {
    state.addNotice(notice);
    state.setPhase(AgentPhase.failed);
    _wakeIdle(force: true);
  }

  void _status(AiStatus status) {
    if (_lastStatus == status) return;
    _lastStatus = status;
    onStatus?.call(status);
  }
}
```

`lib/src/host/ai_host.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/session_state.dart';
import 'agent_catalog.dart';
import 'agent_process.dart';
import 'agent_resolver.dart';
import 'ai_runtime.dart';
import 'checkpoint_store.dart';
import 'login_shell_env.dart';
import 'running_agents.dart';

/// The AI services of the app, one per app; the desktop builds it at
/// startup (V2-1b).
final class AiHost {
  AiHost({
    required this.supportDir,
    required this.clientVersion,
    LoginShellEnv? env,
    AgentResolver? resolver,
    CheckpointStores? checkpoints,
    RunningAgents? running,
    KillTree killTree = killOnly,
    DateTime Function()? now,
  }) : env = env ?? LoginShellEnv(),
       resolver = resolver ?? AgentResolver(agentsDir: p.join(supportDir, 'ai', 'agents')),
       checkpoints = checkpoints ?? CheckpointStores(root: p.join(supportDir, 'ai', 'checkpoints')),
       running = running ?? RunningAgents(File(p.join(supportDir, 'ai', 'running.json'))),
       _killTree = killTree,
       _now = now ?? DateTime.now;

  /// `<app support>` (macOS `~/Library/Application Support/pro.shellx.desktop`,
  /// Windows `%LOCALAPPDATA%\ShellX`).
  final String supportDir;
  final String clientVersion;
  final LoginShellEnv env;
  final AgentResolver resolver;
  final CheckpointStores checkpoints;
  final RunningAgents running;
  final KillTree _killTree;
  final DateTime Function() _now;

  /// Starts an agent process and keeps `running.json` in step (spec §6).
  Future<AgentChannel> launch(AgentCommand command, {required String cwd}) async {
    final process = await AgentProcess.start(command, cwd: cwd, killTree: _killTree);
    await running.add(RunningRecord(pid: process.pid, command: command.executable, startedAt: _now()));
    unawaited(process.exitCode.then((_) => running.remove(process.pid)));
    return process;
  }

  /// The runtime of one AI tab.
  AiRuntime runtime({
    required AgentSpec agent,
    required String cwd,
    String? resumeSessionId,
    Map<String, Object> preferredConfig = const {},
  }) => AiRuntime(
    state: AiSessionState(agentId: agent.id, agentName: agent.name, cwd: cwd),
    resolve: () async => resolver.resolve(agent, await env.resolve()),
    launch: launch,
    clientVersion: clientVersion,
    checkpoints: () async => checkpoints.forProject(cwd, await env.resolve()),
    resumeSessionId: resumeSessionId,
    preferredConfig: preferredConfig,
  );

  /// At app start: stop the agents a crash left behind (spec §6), then
  /// prune old checkpoints in the background (spec D12). Returns how many
  /// agents were stopped.
  Future<int> startup({Duration retention = const Duration(days: 14)}) async {
    final stopped = await running.sweep();
    unawaited(() async {
      await checkpoints.pruneAll(retention, await env.resolve());
    }().catchError((Object _) {}));
    return stopped;
  }
}
```

Add to `lib/host.dart`: `export 'src/host/ai_host.dart';`, `export 'src/host/ai_runtime.dart';`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze`
Expected: all pass; `No issues found!`. Run the runtime test three times (`--total-shards`/loop) to catch timing flakes:

```bash
for i in 1 2 3; do ~/fvm/versions/3.41.4/bin/dart test test/host/ai_runtime_test.dart || break; done
```

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_ai packages/shellx_acp
git commit -m "feat(v2-ai): AiRuntime — start, sign-in, turns with checkpoints, cancel and force stop, queue, resume; AiHost wiring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Finish — full verification, privacy sweep, ledger, push

**Files:**
- Modify: `docs/superpowers/ledgers/v2-ai.md`
- No product code unless a check fails.

**Interfaces:**
- Consumes: everything.
- Produces: a green, pushed `shellx-v2` with the V2-1a foundation, ready for plan V2-1b.

- [ ] **Step 1: Full test and analyze run**

```bash
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get
for d in packages/shellx_acp packages/shellx_ai packages/shellx_core packages/shellx_agent; do
  (cd $d && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test) || echo "FAIL $d"
done
(cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test) || echo "FAIL desktop"
```

Expected: no `FAIL` lines. Compare the counts with the ledger baseline: the existing suites keep their counts. The desktop must still resolve after the lockfile change.

- [ ] **Step 2: Privacy and safety sweep (spec §5, §8)**

```bash
grep -rn "print(\|stdout.write\|debugPrint\|log(" packages/shellx_acp/lib packages/shellx_ai/lib | grep -v "bin/\|testing" || echo "no logging"
grep -rn "runInShell: true\|'/bin/sh'\|cmd.exe" packages/shellx_ai/lib || echo "no shell"
grep -rn "hide-claude-auth\|SHELLX_CLI_TOKEN" packages/shellx_ai/lib packages/shellx_acp/lib | grep -v "spec D6\|no CLI token\|SHELLX_\*" || echo "clean"
grep -rn "allow_once\|allowOnce\|PermissionSelected(" packages/shellx_ai/lib | grep -v "^.*///" || echo "nothing picks an option"
grep -rln "dart:io" packages/shellx_ai/lib/shellx_ai.dart packages/shellx_ai/lib/src/model packages/shellx_acp/lib/shellx_acp.dart packages/shellx_acp/lib/src/*.dart || echo "model and protocol are io-free"
```

Expected: each line prints its "clean" message. The only `PermissionSelected(` in `lib` is inside `answerPermission`, which is the user's own pick. Investigate any other hit.

- [ ] **Step 3: Windows CI**

Push a CI branch so `windows-check` runs the new suites on real Windows and macOS. The workflow triggers on `windows-check/**`:

```bash
git push origin shellx-v2
git push origin shellx-v2:windows-check/v2-ai-foundation
gh run list --branch windows-check/v2-ai-foundation --limit 1
```

Watch the `dart` job (`gh run watch <id>`). Fix any Windows-only failure (paths, process info, git on Windows), commit it to `shellx-v2`, and push both refs again. When it is green, delete the CI branch. If auto mode blocks the delete, ask the user to run it with `!`:

```bash
git push origin --delete windows-check/v2-ai-foundation
```

- [ ] **Step 4: Ledger**

Append to `docs/superpowers/ledgers/v2-ai.md` under `## V2-1a (foundation) — execution`:
- per-task commits and test counts;
- Task 4 findings (spec §12 items 1–5), with every ⚠ item that is still open marked "pending manual (spec §9)": Codex, Gemini, OpenCode, Windows Claude, big project timing;
- the CI run URL and its result;
- any ruling the implementers made.

- [ ] **Step 5: Commit and push**

```bash
git add docs/superpowers/ledgers/v2-ai.md
git commit -m "docs(v2-ai): V2-1a foundation ledger — results, Task-1 findings, CI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin shellx-v2
```

---

## Self-review (done while writing)

- **Spec coverage (V2-1a part):**
  - D1: Tasks 1–3.
  - D6 (launch, env, stop, pins): Tasks 6–7, 9.
  - D8 (login: notices, terminal command, retry; no credential handling): Task 9.
  - D9 (model): Task 5.
  - D10 (permission queue, cancelled on stop; the keys are UI, V2-1b): Tasks 5, 9.
  - D11 (config, modes, remembered choices, R6): Tasks 2, 9.
  - D12 (checkpoints): Task 8.
  - D13 (status events; notifier wiring is V2-1b): Task 9.
  - D14 (`session/load`, lazy start, no load capability; `layout.json` is V2-1b): Task 9.
  - D15 (`session/list`): Tasks 3, 9.
  - D16 (queue; composer UI V2-1b): Tasks 5, 9.
  - D20 (redaction, stderr ring): every task.
  - D22 (elicitation): Tasks 2, 5, 9.
  - D23 (catalog order): Task 6.
  - §6 rows:
    - not found / Node / install / -32000 / exit mid-turn / force stop: Task 9;
    - bad lines / long lines: Task 1;
    - update after stopReason: Task 9;
    - unknown updates: Task 2;
    - permission without a card: Task 5;
    - no loadSession: Task 9;
    - folder gone: Task 9;
    - git issues, snapshot failure, two tabs on one project: Task 8;
    - quit while running: Task 7 (`stop`) and Task 9 (`dispose`);
    - crash cleanup: Task 7.
  - §7 tests: Tasks 1–9.
  - §12 checks: Task 4.
- **Left to V2-1b (by design):** everything under `apps/desktop`:
  - tab model and every reader of `focused`/`label`;
  - widgets, run sheet (PTY), keys, settings, onboarding;
  - restore of `aiTabs`, CLI `ui.ls`, ARB strings;
  - A12 notifier wiring and `TabAttention.addAiNotice`;
  - D17 packages.
- **Placeholders:** none. Every step has its code or command.
- **Names across tasks:**
  - `Checkpoints` (Task 8), used by Task 9;
  - `FakeLauncher(first, later)` (Task 7), used by Task 9;
  - `FakeScenario.loadSessionError` (Task 3), used by Task 9;
  - `AiSessionState.applyUpdate(update, at, {history, timelineToo})` (Task 5), used by Task 9;
  - `AgentChannel` / `AgentLauncher` (Task 7), used by Task 9 and `AiHost`.
