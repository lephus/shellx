# Terminal Sharing P3 — Agent + Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ShellX agent its side of terminal sharing: accept authenticated `shellx-term` connections on `127.0.0.1`, turn each into a `desktop` session the phone can list, attach, watch and type into, and extend the phone ↔ agent protocol (spec §8) compatibly. Ends with a simulated phone ↔ agent ↔ real `shellx-term` run.

**Architecture:** The phone-facing half of a session (ring buffer, send window, attach/replay, `taken_over`) moves out of `SessionManager` into `SessionStream`. Shell sessions keep `SessionManager` (behaviour unchanged, proven by the untouched existing tests); desktop terminals get `DesktopSessionManager`, which has **no way to kill a terminal**. `SessionRouter` sits where `SessionManager` sat in `AgentService` (through a new `AgentSessions` interface), routes by session id and merges `session.list`. `TermServer` owns the loopback port, the `endpoint` file and the HMAC handshake; its links feed `DesktopSessionManager`. `TerminalSharing` pairs the two for P4's switch.

**Tech Stack:** Dart 3.11 (workspace, Flutter 3.41.7 for the apps), `cbor ^6.5.1` and `cryptography ^2.9.0` (already used by `shellx_core`), `fake_async`, `test`; Rust 1.95 / `portable-pty 0.9.0` for one test-only example in `term/`; Node relay (`npm run dev`) for the relay e2e.

**Spec:** `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` — §6 (local link; byte-exact vectors in `term/protocol/vectors.txt`), §7.1–§7.5, **§7.7–§7.9 (P3 structure, data flow, errors)**, §8, §11.2, §11.4, §12, §14; decisions T13, T14. Term-side behaviour this plan talks to: `term/src/link.rs`, `term/src/size.rs`, ledger `docs/superpowers/ledgers/terminal-sharing.md` (P2a, P2b).

## Global Constraints

- Branch `feat/terminal-sharing-p3` (already holds the spec commits; cut from `origin/windows-check/p2b` = `main` + `d6f778f`). Work in worktree `.claude/worktrees/terminal-sharing-p3`: before Task 1, from the repo root (whose checkout is on `main`), `git worktree add .claude/worktrees/terminal-sharing-p3 feat/terminal-sharing-p3 && cd .claude/worktrees/terminal-sharing-p3 && flutter pub get`. Merge locally after the final review. **Never push. Never deploy. Never connect to `relay.shellx.pro`** (T14: the user runs that step).
- Relay, web, `term/src/**` and the mobile/desktop UI do not change. The only `term/` change is a new test-only example (`term/examples/fake_window.rs`).
- Local-link constants (spec §6, must match `term/src/proto/*`):
  - `v = 1`; frame = 4-byte big-endian length + CBOR map, payload ≤ `65536` bytes.
  - Map keys written in **bytewise ascending order** (all keys are ASCII, so `String.compareTo` order); decoders accept any order.
  - HMAC-SHA256; agent proof = HMAC(secret, `"shellx-term/agent"` ‖ nonce_term ‖ nonce_agent); term proof = HMAC(secret, `"shellx-term/term"` ‖ nonce_agent ‖ nonce_term). Nonces 32 bytes, `term_id` 16 bytes, `mac` 32 bytes.
  - Handshake deadline 5 s for the whole handshake. `reject` reasons: `limit`, `version`.
  - Agent → term write queue: over **1 MiB** (`1048576`) unsent bytes closes the link.
- `endpoint` file: macOS `$HOME/Library/Application Support/ShellX/term/endpoint` (dir 0700, file 0600 set **before** the secret is written); Windows `%LOCALAPPDATA%\ShellX\term\endpoint`. Exactly `v=1\nport=<decimal>\nsecret=<64 lowercase hex>\n`.
- Desktop sessions: at most **32** (waiting ones count), separate from the 10 shell sessions; reconnect grace **30 s**; buffer **256 KiB** (`262144`); snapshot over 256 KiB is a protocol error; title ≤ **200** characters.
- Session ids for both kinds come from **one** allocator (`sessionIdAllocator`): random start in [1, 2^31), then +1.
- Phone protocol (spec §8): every new field is optional; `session.list` without `desktop: true` and its answer are **byte-identical to today**. A phone may attach a desktop session only after it sent `session.list {desktop: true}` at least once since the agent started (flag kept per phone across channel losses, dropped on revoke).
- **No path may kill or close a desktop terminal** (spec §7.2). `DesktopSessionManager` and `TermLink` have no kill; closing a link only ends sharing.
- Logs and `toString`s never contain the secret, a `mac`, a nonce or terminal bytes.
- Never touch the real `~/Library/Application Support/ShellX` or real shell rc files; tests use temp HOMEs.
- Gates (run before every commit; full suite 3× in a row when a task adds timing-sensitive tests — flakiness is a bug):
  - `packages/shellx_core`: `dart analyze && dart test`
  - `packages/shellx_agent`: `dart analyze && dart test`
  - `packages/shellx_client`: `dart analyze && dart test`
  - `packages/shellx_e2e`: `dart analyze` (+ `dart test` where the task says)
  - `apps/desktop`, `apps/mobile`: `flutter analyze && flutter test` when the task touches them or a package they import changes its public API
  - `term/`: `cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks` (Task 11 only)
- Commit messages: `feat(core): …`, `feat(agent): …`, `feat(client): …`, `test(e2e): …`, `test(term): …`, `ci: …`, `docs: …`.

## Review Focus

1. **A phone whose channel drops while attached to a desktop terminal** must re-attach the tab without listing again and keep seeing output (the spec §7.9 fix of 2026-10-05). Pinned in Task 9 (router keeps the flag across `mobileDisconnected`) and Task 10 (client harness disconnect → reconnect re-attaches the desktop tab).
2. **The window's own keystroke racing a phone keystroke** must leave the driver on whoever acted last and never lose either side's bytes. Pinned in Task 8 (`local` then phone `input` → `resize` before `in`, and `session.driver` order) and Task 11 (real binary: window keystroke → `session.driver {desktop}`).
3. **An old phone (no `desktop: true`) on a new agent** must see exactly today's wire: no desktop entries, no `desktop_sharing`, no `session.driver`, no `terminal_gone`, and `session.attach` to a desktop id answered `session_not_found`. Pinned in Task 1 (wire bytes of `SessionList()`/`SessionListResult` unchanged) and Task 9.
4. **`shellx-term` reconnecting with the same `term_id` while the agent still holds a half-open old connection** must replace the old link, keep the session id and resync from the snapshot with `session.reset`. Pinned in Task 8 and Task 11 (agent restart).
5. **The agent being stopped/started (switch off/on, app quit)** must never close a terminal window and must not delete an `endpoint` file written by a newer start. Pinned in Task 6 (`deleteIfOwned`), Task 9 (every §7.2 path) and Task 11 (window keeps running across stop/start).

---

### Task 1: Phone ↔ agent protocol additions (`shellx_core`, spec §8)

**Files:**
- Modify: `packages/shellx_core/lib/src/protocol/messages.dart`
- Test: `packages/shellx_core/test/protocol/messages_test.dart`

**Interfaces:**
- Produces (all exported by `package:shellx_core/shellx_core.dart`):
  - `SessionList({bool desktop = false})`, field `desktop`
  - `SessionListResult(List<SessionInfo> sessions, {bool? desktopSharing})`, field `desktopSharing`
  - `enum SessionKind { shellx, desktop }`
  - `SessionInfo({…existing…, SessionKind kind = SessionKind.shellx, String app = '', String title = ''})`
  - `SessionDetach({required int id})` (`t` = `session.detach`)
  - `enum DriverSide { desktop('desktop'), phone('phone') }` with `wire` and `static DriverSide fromWire(String)`
  - `SessionDriver({required int id, required DriverSide by})` (`t` = `session.driver`)
  - `DetachReason.terminalGone` (`terminal_gone`)

- [ ] **Step 1: Write the failing tests**

In `messages_test.dart`, add to the `samples` map (keep the existing entries; the map drives the "toMap uses the wire keys" and "round trip" groups):

```dart
    const SessionList(desktop: true): {'t': 'session.list', 'desktop': true},
    const SessionListResult([
      SessionInfo(
        id: 9,
        index: 1,
        shell: 'zsh',
        createdAt: 1790000000002,
        attached: false,
        kind: SessionKind.desktop,
        app: 'Terminal',
        title: 'npm run dev',
      ),
    ], desktopSharing: true): {
      't': 'session.list.result',
      'sessions': [
        {
          'id': 9,
          'index': 1,
          'shell': 'zsh',
          'created_at': 1790000000002,
          'attached': false,
          'kind': 'desktop',
          'app': 'Terminal',
          'title': 'npm run dev',
        },
      ],
      'desktop_sharing': true,
    },
    const SessionDetach(id: 9): {'t': 'session.detach', 'id': 9},
    const SessionDriver(id: 9, by: DriverSide.desktop): {
      't': 'session.driver',
      'id': 9,
      'by': 'desktop',
    },
    const SessionDetached(id: 9, reason: DetachReason.terminalGone): {
      't': 'session.detached',
      'id': 9,
      'reason': 'terminal_gone',
    },
```

Then add these tests inside `main()`:

```dart
  group('terminal sharing compatibility (spec §8)', () {
    test('session.list without desktop is byte-identical to before', () {
      expect(
        encodeBatch([const SessionList()]),
        encodeCbor([
          {'t': 'session.list'},
        ]),
      );
    });

    test('a shell SessionInfo and a result without desktop_sharing keep '
        'the old keys only', () {
      const result = SessionListResult([
        SessionInfo(
          id: 1,
          index: 1,
          shell: 'zsh',
          createdAt: 1,
          attached: false,
        ),
      ]);
      expect(result.toMap(), {
        't': 'session.list.result',
        'sessions': [
          {
            'id': 1,
            'index': 1,
            'shell': 'zsh',
            'created_at': 1,
            'attached': false,
          },
        ],
      });
    });

    test('missing desktop and desktop_sharing decode as false / null', () {
      final decoded = decodeBatch(
        encodeCbor([
          {'t': 'session.list'},
          {'t': 'session.list.result', 'sessions': <Object?>[]},
        ]),
      );
      expect((decoded[0] as SessionList).desktop, isFalse);
      expect((decoded[1] as SessionListResult).desktopSharing, isNull);
    });

    test('a session entry with an unknown kind is skipped, not an error', () {
      final decoded = decodeBatch(
        encodeCbor([
          {
            't': 'session.list.result',
            'sessions': [
              {
                'id': 1,
                'index': 1,
                'shell': 'zsh',
                'created_at': 1,
                'attached': false,
                'kind': 'hologram',
              },
              {
                'id': 2,
                'index': 1,
                'shell': 'zsh',
                'created_at': 1,
                'attached': false,
                'kind': 'desktop',
              },
            ],
          },
        ]),
      );
      final sessions = (decoded.single as SessionListResult).sessions;
      expect(sessions.map((s) => s.id), [2]);
      expect(sessions.single.kind, SessionKind.desktop);
      expect(sessions.single.app, '');
      expect(sessions.single.title, '');
    });

    test('DriverSide.fromWire rejects an unknown side', () {
      expect(DriverSide.fromWire('phone'), DriverSide.phone);
      expect(() => DriverSide.fromWire('tablet'), throwsFormatException);
    });
  });
```

And add to the existing `malformed input throws FormatException` cases (follow the shape already used there — a name and a map):

```dart
      'session.driver with an unknown side': {
        't': 'session.driver',
        'id': 1,
        'by': 'tablet',
      },
      'session.detach without id': {'t': 'session.detach'},
      'session.list with a non-bool desktop': {
        't': 'session.list',
        'desktop': 1,
      },
      'session entry with a non-string kind': {
        't': 'session.list.result',
        'sessions': [
          {
            'id': 1,
            'index': 1,
            'shell': 'zsh',
            'created_at': 1,
            'attached': false,
            'kind': 7,
          },
        ],
      },
```

(If that group is a list of records instead of a map, add the same four cases in its format.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_core && dart test test/protocol/messages_test.dart`
Expected: compile errors (`SessionKind`, `SessionDetach`, `SessionDriver`, `DriverSide`, `terminalGone`, named `desktop` undefined).

- [ ] **Step 3: Implement**

In `messages.dart`:

1. `fromMap` cases:

```dart
      'session.list' => SessionList(
        desktop: f.optionalBoolean('desktop') ?? false,
      ),
      'session.list.result' => SessionListResult(
        [
          for (final item in f.list('sessions'))
            if (SessionInfo._fromMap(item, t) case final info?) info,
        ],
        desktopSharing: f.optionalBoolean('desktop_sharing'),
      ),
```

and, next to `'session.close'`:

```dart
      'session.detach' => SessionDetach(id: f.integer('id')),
      'session.driver' => SessionDriver(
        id: f.integer('id'),
        by: DriverSide.fromWire(f.string('by')),
      ),
```

2. Replace `SessionList`:

```dart
final class SessionList extends AppMessage {
  const SessionList({this.desktop = false});

  /// Also list desktop terminals and report `desktop_sharing` (spec §8).
  /// Only written when true, so the old wire form is unchanged.
  final bool desktop;
  @override
  String get type => 'session.list';
  @override
  Map<String, Object?> toMap() => {'t': type, if (desktop) 'desktop': true};
}
```

3. Before `SessionInfo`:

```dart
/// Where a session's terminal lives (spec §7.1). Absent on the wire means
/// [shellx].
enum SessionKind { shellx, desktop }
```

4. Replace `SessionInfo`:

```dart
final class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attached,
    this.kind = SessionKind.shellx,
    this.app = '',
    this.title = '',
  });

  final int id;
  final int index;
  final String shell;

  /// Unix milliseconds.
  final int createdAt;
  final bool attached;
  final SessionKind kind;

  /// Terminal application (desktop sessions only; may be empty).
  final String app;

  /// Latest window title (desktop sessions only; may be empty).
  final String title;

  Map<String, Object?> toMap() => {
    'id': id,
    'index': index,
    'shell': shell,
    'created_at': createdAt,
    'attached': attached,
    if (kind == SessionKind.desktop) ...{
      'kind': 'desktop',
      'app': app,
      'title': title,
    },
  };

  /// Null for a `kind` this version does not know: the entry is skipped so
  /// a newer agent's new session kinds never break the list (spec §7.9).
  static SessionInfo? _fromMap(Object? value, String type) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$type: session entry must be a map');
    }
    final f = _Fields(value, type);
    final kind = switch (f.optionalString('kind')) {
      null => SessionKind.shellx,
      'desktop' => SessionKind.desktop,
      _ => null,
    };
    if (kind == null) return null;
    return SessionInfo(
      id: f.integer('id'),
      index: f.integer('index'),
      shell: f.string('shell'),
      createdAt: f.integer('created_at'),
      attached: f.boolean('attached'),
      kind: kind,
      app: f.optionalString('app') ?? '',
      title: f.optionalString('title') ?? '',
    );
  }
```

(keep its `==`, `hashCode`, `toString`).

5. Replace `SessionListResult`:

```dart
final class SessionListResult extends AppMessage {
  const SessionListResult(this.sessions, {this.desktopSharing});
  final List<SessionInfo> sessions;

  /// Whether terminal sharing is on (spec §8); only in answers to
  /// `session.list {desktop: true}`. Null means an agent without terminal
  /// sharing, or a list that did not ask.
  final bool? desktopSharing;
  @override
  String get type => 'session.list.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sessions': [for (final session in sessions) session.toMap()],
    if (desktopSharing != null) 'desktop_sharing': desktopSharing,
  };
}
```

6. After `SessionClose`:

```dart
/// The phone leaves a desktop session; the terminal keeps running (spec §8).
/// Never answered.
final class SessionDetach extends AppMessage {
  const SessionDetach({required this.id});
  final int id;
  @override
  String get type => 'session.detach';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id};
}

/// Who sets a desktop terminal's size now (spec §5.5, §7.3).
enum DriverSide {
  desktop('desktop'),
  phone('phone');

  const DriverSide(this.wire);
  final String wire;

  /// Throws [FormatException] for an unknown value.
  static DriverSide fromWire(String wire) {
    for (final side in values) {
      if (side.wire == wire) return side;
    }
    throw FormatException('Unknown driver side', wire);
  }
}

final class SessionDriver extends AppMessage {
  const SessionDriver({required this.id, required this.by});
  final int id;
  final DriverSide by;
  @override
  String get type => 'session.driver';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id, 'by': by.wire};
}
```

7. `DetachReason`: add `terminalGone('terminal_gone')` after `closedByHost`.

8. `_Fields`: add

```dart
  bool? optionalBoolean(String key) {
    final value = _map[key];
    if (value == null || value is bool) return value as bool?;
    throw FormatException('$_type: "$key" must be a boolean');
  }

  String? optionalString(String key) {
    final value = _map[key];
    if (value == null || value is String) return value as String?;
    throw FormatException('$_type: "$key" must be a string');
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_core && dart analyze && dart test`
Expected: all pass. Then `cd ../shellx_client && dart analyze && dart test` and `cd ../shellx_agent && dart analyze && dart test` still pass (no API was removed).

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_core
git commit -m "feat(core): terminal sharing messages — session.list desktop, desktop_sharing, desktop SessionInfo, session.detach, session.driver, terminal_gone (spec §8)"
```

---

### Task 2: `RingBuffer.restartWith`, `SessionStream`, shared id allocator

**Files:**
- Modify: `packages/shellx_agent/lib/src/session/ring_buffer.dart`
- Create: `packages/shellx_agent/lib/src/session/session_stream.dart`, `packages/shellx_agent/lib/src/session/session_ids.dart`, `packages/shellx_agent/lib/src/session/agent_sessions.dart`
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart` (only: move `OutboundMessage` and `SessionOpenedEvent` out to `agent_sessions.dart` and import it), `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/session/ring_buffer_test.dart`, `packages/shellx_agent/test/session/session_stream_test.dart`

**Interfaces:**
- Produces:
  - `RingBuffer.restartWith(Uint8List data)`
  - `int Function() sessionIdAllocator([Random? random])`
  - `final class SessionStream({required int id, required int capacity, required int sendWindow, required void Function(String mobileId, AppMessage message) send})` with `id`, `String? attachedMobileId` (settable), `int get start`, `int get end`, `bool get drained`, `void append(Uint8List)`, `void restartWith(Uint8List)`, `String? attach(String mobileId, int lastSeq)`, `void ack(int seq)`, `void pump()`
  - `abstract interface class AgentSessions` with `Stream<OutboundMessage> get outbound`, `Stream<SessionOpenedEvent> get opened`, `Future<void> handle(String, AppMessage)`, `void mobileDisconnected(String)`, `void closeSessionsAttachedTo(String)`; `OutboundMessage` and `SessionOpenedEvent` now live in `agent_sessions.dart` (same names, same fields)

- [ ] **Step 1: Write the failing tests**

Append to `ring_buffer_test.dart`:

```dart
  test('restartWith drops what was held and keeps positions increasing', () {
    final ring = RingBuffer(8)..append(_bytes('abcdef'));
    ring.restartWith(_bytes('XYZ'));
    expect(ring.start, 6);
    expect(ring.end, 9);
    expect(String.fromCharCodes(ring.read(6, 10)), 'XYZ');
    expect(() => ring.read(5, 1), throwsRangeError);
  });

  test('restartWith larger than the capacity keeps the newest bytes', () {
    final ring = RingBuffer(4)..append(_bytes('ab'));
    ring.restartWith(_bytes('0123456789'));
    expect(ring.start, 8);
    expect(ring.end, 12);
    expect(String.fromCharCodes(ring.read(8, 4)), '6789');
  });

  test('restartWith on an empty buffer is an append', () {
    final ring = RingBuffer(8)..restartWith(_bytes('hi'));
    expect(ring.start, 0);
    expect(ring.end, 2);
  });

  test('after restartWith, appends wrap around as usual', () {
    final ring = RingBuffer(4)
      ..append(_bytes('abc'))
      ..restartWith(_bytes('de'))
      ..append(_bytes('fgh'));
    expect(ring.start, 4);
    expect(ring.end, 8);
    expect(String.fromCharCodes(ring.read(4, 4)), 'efgh');
  });
```

(If the file has no `_bytes` helper, add `Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);` at the top level.)

Create `test/session/session_stream_test.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

final class _Rig {
  _Rig({int capacity = 64, int window = 1024}) {
    stream = SessionStream(
      id: 5,
      capacity: capacity,
      sendWindow: window,
      send: (mobileId, message) => sent.add((mobileId, message)),
    );
  }
  late final SessionStream stream;
  final sent = <(String, AppMessage)>[];
  List<AppMessage> to(String m) => [
    for (final (id, msg) in sent)
      if (id == m) msg,
  ];
  String text(String m) => utf8.decode([
    for (final msg in to(m).whereType<OutputMessage>()) ...msg.data,
  ]);
}

void main() {
  test('append does not send; pump sends to the attached phone', () {
    final rig = _Rig();
    rig.stream.attach('p', 0);
    rig.stream.append(_b('hello'));
    expect(rig.to('p'), isEmpty);
    rig.stream.pump();
    expect(rig.text('p'), 'hello');
    expect(rig.stream.drained, isTrue);
  });

  test('attach replays from last_seq inside the buffer', () {
    final rig = _Rig()..stream.append(_b('0123456789'));
    rig.stream.attach('p', 4);
    expect(rig.text('p'), '456789');
    expect(rig.to('p').whereType<SessionReset>(), isEmpty);
    expect((rig.to('p').first as OutputMessage).seq, 4);
  });

  test('attach outside the buffer resets and replays from start', () {
    final rig = _Rig(capacity: 4)..stream.append(_b('0123456789'));
    rig.stream.attach('p', 1);
    expect(rig.to('p').first, const SessionReset(id: 5));
    expect(rig.text('p'), '6789');
  });

  test('a second phone takes over and the first gets taken_over', () {
    final rig = _Rig();
    rig.stream.attach('a', 0);
    expect(rig.stream.attach('b', 0), 'a');
    expect(
      rig.to('a').single,
      const SessionDetached(id: 5, reason: DetachReason.takenOver),
    );
    expect(rig.stream.attachedMobileId, 'b');
  });

  test('the send window holds output until acked', () {
    final rig = _Rig(window: 4);
    rig.stream.attach('p', 0);
    rig.stream
      ..append(_b('abcdefgh'))
      ..pump();
    expect(rig.text('p'), 'abcd');
    rig.stream
      ..ack(4)
      ..pump();
    expect(rig.text('p'), 'abcdefgh');
  });

  test('restartWith resets the attached phone and replays the new bytes', () {
    final rig = _Rig()..stream.append(_b('old screen'));
    rig.stream.attach('p', 0);
    rig.sent.clear();
    rig.stream.restartWith(_b('snapshot'));
    rig.stream.pump();
    expect(rig.to('p').first, const SessionReset(id: 5));
    expect(rig.text('p'), 'snapshot');
    expect((rig.to('p')[1] as OutputMessage).seq, 10);
  });

  test('restartWith with nobody attached sends nothing', () {
    final rig = _Rig()..stream.append(_b('x'));
    rig.stream.restartWith(_b('y'));
    expect(rig.sent, isEmpty);
    expect(rig.stream.start, 1);
    expect(rig.stream.end, 2);
  });

  test('sessionIdAllocator starts in [1, 2^31) and counts up', () {
    final next = sessionIdAllocator(Random(1));
    final first = next();
    expect(first, inInclusiveRange(1, (1 << 31) - 1));
    expect(next(), first + 1);
    expect(next(), first + 2);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/shellx_agent && dart test test/session/ring_buffer_test.dart test/session/session_stream_test.dart`
Expected: compile errors (`restartWith`, `SessionStream`, `sessionIdAllocator` undefined).

- [ ] **Step 3: Implement**

`ring_buffer.dart` — add a floor:

```dart
  int _end = 0;

  /// Positions below this were dropped by [restartWith].
  int _floor = 0;

  int get start => max(_floor, _end - _capacity);
  int get end => _end;
```

and the method (after `append`):

```dart
  /// Drops every byte held and continues the stream with [data]: positions
  /// keep increasing, and [start] becomes the old [end] (spec §7.8: a desktop
  /// terminal's snapshot after a reconnect replaces the buffer).
  void restartWith(Uint8List data) {
    _floor = _end;
    append(data);
  }
```

`session_ids.dart`:

```dart
import 'dart:math';

/// Session ids start at a random value in [1, 2^31) and then increase by
/// one (spec v1 §6.4), so a phone re-attaching after an agent restart cannot
/// land on a new session that reuses its old id. One allocator is shared by
/// the shell and desktop session managers, so their ids never collide.
int Function() sessionIdAllocator([Random? random]) {
  var next = (random ?? Random.secure()).nextInt((1 << 31) - 1) + 1;
  return () => next++;
}
```

`agent_sessions.dart` (move the two classes here verbatim from `session_manager.dart`, then delete them there and add `import 'agent_sessions.dart';` to `session_manager.dart`):

```dart
import 'package:shellx_core/shellx_core.dart';

/// An application message the agent must deliver to one phone.
final class OutboundMessage {
  const OutboundMessage(this.mobileId, this.message);
  final String mobileId;
  final AppMessage message;
}

/// Emitted when a phone opens a new session (desktop notification).
final class SessionOpenedEvent {
  const SessionOpenedEvent(this.mobileId, this.sessionId);
  final String mobileId;
  final int sessionId;
}

/// What [AgentService] needs from the sessions: phone messages in,
/// messages to phones out, and the channel lifecycle. Implemented by
/// `SessionManager` (shell sessions only) and `SessionRouter` (shell and
/// desktop sessions).
abstract interface class AgentSessions {
  /// Messages to deliver, in order (a synchronous broadcast stream).
  Stream<OutboundMessage> get outbound;

  Stream<SessionOpenedEvent> get opened;

  Future<void> handle(String mobileId, AppMessage message);

  /// The channel to [mobileId] is gone.
  void mobileDisconnected(String mobileId);

  /// [mobileId] was revoked: its shell sessions are killed; desktop
  /// terminals only lose the phone (spec §7.2).
  void closeSessionsAttachedTo(String mobileId);
}
```

`session_stream.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'ring_buffer.dart';

/// The phone-facing half of a session (spec v1 §6.5): buffered output
/// addressed by `seq`, the attached phone, replay on attach and the send
/// window. Shared by shell sessions (`SessionManager`) and desktop
/// terminals (`DesktopSessionManager`); it does not know where bytes come
/// from and never decides when a session ends.
///
/// [append], [ack] and [restartWith] only change state; the owner calls
/// [pump] (so it can check, right after, whether a closing session has
/// drained). [attach] pumps itself, before the owner resizes and answers
/// `session.attached`.
final class SessionStream {
  SessionStream({
    required this.id,
    required int capacity,
    required int sendWindow,
    required void Function(String mobileId, AppMessage message) send,
  }) : _buffer = RingBuffer(capacity),
       _sendWindow = sendWindow,
       _send = send;

  final int id;
  final RingBuffer _buffer;
  final int _sendWindow;
  final void Function(String mobileId, AppMessage message) _send;

  /// The phone output goes to; null when nobody is attached.
  String? attachedMobileId;

  /// Next stream position to send to the attached phone.
  int _sent = 0;

  /// Highest position acknowledged by the attached phone.
  int _acked = 0;

  int get start => _buffer.start;
  int get end => _buffer.end;

  /// Every buffered byte has been handed to the attached phone.
  bool get drained => _sent >= _buffer.end;

  void append(Uint8List data) => _buffer.append(data);

  /// Replaces the buffer with [data], positions continuing (spec §7.8). An
  /// attached phone gets `session.reset` and, on the next [pump], [data]
  /// from its first byte.
  void restartWith(Uint8List data) {
    _buffer.restartWith(data);
    final mobileId = attachedMobileId;
    if (mobileId == null) return;
    _send(mobileId, SessionReset(id: id));
    _sent = _buffer.start;
    _acked = _buffer.start;
  }

  /// Attaches [mobileId] from [lastSeq] and replays: `taken_over` to the
  /// previous phone, `session.reset` when [lastSeq] is outside the buffer.
  /// Returns the phone that was attached before. Does not send
  /// `session.attached`.
  String? attach(String mobileId, int lastSeq) {
    final previous = attachedMobileId;
    if (previous != null && previous != mobileId) {
      _send(previous, SessionDetached(id: id, reason: DetachReason.takenOver));
    }
    attachedMobileId = mobileId;
    if (lastSeq < _buffer.start || lastSeq > _buffer.end) {
      _send(mobileId, SessionReset(id: id));
      _sent = _buffer.start;
    } else {
      _sent = lastSeq;
    }
    _acked = _sent;
    pump();
    return previous;
  }

  void ack(int seq) => _acked = max(_acked, min(seq, _sent));

  /// Sends buffered output to the attached phone while the send window
  /// allows. Data overwritten before it could be sent triggers a reset.
  void pump() {
    final mobileId = attachedMobileId;
    if (mobileId == null) return;
    while (_sent < _buffer.end && _sent - _acked < _sendWindow) {
      if (_sent < _buffer.start) {
        _send(mobileId, SessionReset(id: id));
        _sent = _buffer.start;
        _acked = _buffer.start;
        continue;
      }
      final room = _sendWindow - (_sent - _acked);
      final count = min(min(kMaxOutputChunk, _buffer.end - _sent), room);
      final data = _buffer.read(_sent, count);
      final seq = _sent;
      // Advance before sending: the owner's outbound stream is synchronous,
      // so a listener may call back (e.g. to ack) before `_send` returns.
      _sent += count;
      _send(mobileId, OutputMessage(id: id, seq: seq, data: data));
    }
  }
}
```

`lib/shellx_agent.dart` — add (keep alphabetical order):

```dart
export 'src/session/agent_sessions.dart';
export 'src/session/session_ids.dart';
export 'src/session/session_stream.dart';
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && dart analyze && dart test`
Expected: all pass (existing tests untouched).

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent
git commit -m "feat(agent): SessionStream (phone-facing half of a session), RingBuffer.restartWith, shared session id allocator, AgentSessions interface"
```

---

### Task 3: `SessionManager` on `SessionStream`; `AgentService` takes `AgentSessions`

Behaviour of shell sessions must not change. **Proof: every existing test in `packages/shellx_agent`, `packages/shellx_client`, `apps/desktop` passes with no edit to any existing test file.**

**Files:**
- Modify: `packages/shellx_agent/lib/src/session/session_manager.dart`
- Modify: `packages/shellx_agent/lib/src/service/agent_service.dart`
- Test: `packages/shellx_agent/test/session/session_manager_test.dart` (append two tests only)

**Interfaces:**
- Consumes: `SessionStream`, `sessionIdAllocator`, `AgentSessions` (Task 2)
- Produces:
  - `SessionManager({…existing…, int Function()? nextId})` — when `nextId` is null, behaves exactly as today (`sessionIdAllocator(random ?? Random.secure())`)
  - `SessionManager implements AgentSessions`
  - `List<SessionInfo> get sessionInfos` (listable shell sessions, as in `session.list.result`)
  - `AgentService({…, required AgentSessions sessions, …})`

- [ ] **Step 1: Write the failing tests**

Append to `session_manager_test.dart` (inside `main`):

```dart
  test('nextId: ids come from the given allocator', () async {
    var next = 500;
    final rig = SessionRig();
    final manager = SessionManager(
      ptyFactory: rig.factory,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      nextId: () => next++,
    );
    final sent = <OutboundMessage>[];
    manager.outbound.listen(sent.add);
    await manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
    await manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
    expect(
      sent.map((o) => o.message).whereType<SessionOpened>().map((m) => m.id),
      [500, 501],
    );
  });

  test('sessionInfos lists what session.list.result lists', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    expect(rig.manager.sessionInfos.single.id, id);
    expect(rig.manager.sessionInfos.single.kind, SessionKind.shellx);
    rig.clear();
    await rig.manager.handle(phone, const SessionList());
    expect(
      rig.to(phone).single,
      SessionListResult(rig.manager.sessionInfos),
    );
  });
```

(`FixedShellResolver` is in `test/support/fake_pty.dart`; add the import if the file lacks it.)

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/session/session_manager_test.dart`
Expected: compile error (`nextId`, `sessionInfos`).

- [ ] **Step 3: Implement**

In `session_manager.dart`:

1. Imports: add `import 'agent_sessions.dart';`, `import 'session_ids.dart';`, `import 'session_stream.dart';`. Remove the `ring_buffer.dart` import if no longer used. Delete the `_idUpperBound` constant.

2. `_Session`: replace the fields `buffer`, `attachedMobileId`, `sent`, `acked` with a stream, keeping `attachedMobileId` as a forwarding property so the rest of the file reads the same:

```dart
final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.pty,
    required this.stream,
    required this.cols,
    required this.rows,
  });

  final int id;
  final int index;
  final String shell;
  final DateTime createdAt;
  final Pty pty;
  final SessionStream stream;
  int cols;
  int rows;

  String? get attachedMobileId => stream.attachedMobileId;
  set attachedMobileId(String? value) => stream.attachedMobileId = value;

  // … exitRecipient, closing, finishedExitCode, drainTimer, exited, output,
  // write/resize/kill: unchanged …
}
```

3. Class header and constructor:

```dart
final class SessionManager implements AgentSessions {
  SessionManager({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Random? random,
    int Function()? nextId,
  }) : _ptyFactory = ptyFactory,
       _shellResolver = shellResolver,
       _homeDirectory = homeDirectory,
       _baseEnvironment = baseEnvironment,
       _maxSessions = maxSessions,
       _bufferCapacity = bufferCapacity,
       _sendWindow = sendWindow,
       _nextId = nextId ?? sessionIdAllocator(random ?? Random.secure());
```

with the field `final int Function() _nextId;` (replacing `int _nextId;`). Update the class doc: ids come from `nextId` (default: a private `sessionIdAllocator`).

4. Add `@override` to `outbound`, `opened`, `handle`, `mobileDisconnected`, `closeSessionsAttachedTo`.

5. `sessionInfos` and the `SessionList` case:

```dart
  /// Listable sessions, as `session.list.result` entries.
  List<SessionInfo> get sessionInfos => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionInfo(
          id: s.id,
          index: s.index,
          shell: s.shell,
          createdAt: s.createdAt.millisecondsSinceEpoch,
          attached: s.attachedMobileId != null,
        ),
  ];
```

```dart
      case SessionList():
        _send(mobileId, SessionListResult(sessionInfos));
```

6. `AckMessage` case:

```dart
      case AckMessage(:final id, :final seq):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.stream.ack(seq);
        _pump(session);
```

7. In `_open`, build the session with a stream:

```dart
    final id = _nextId();
    final session = _Session(
      id: id,
      index: _lowestFreeIndex(),
      shell: command.name,
      createdAt: DateTime.now(),
      pty: pty,
      stream: SessionStream(
        id: id,
        capacity: _bufferCapacity,
        sendWindow: _sendWindow,
        send: _send,
      ),
      cols: c,
      rows: r,
    );
    session.attachedMobileId = mobileId;
```

8. `_attach` — replace from `final previous = …` through `_pump(session);` with:

```dart
    final previous = session.stream.attach(mobileId, lastSeq);
    session.exitRecipient = null;
```

(the resize block, `SessionAttached` and `if (previous != mobileId) _changes.add(null);` stay as they are).

9. `_watch` output listener:

```dart
      (data) {
        session.stream.append(data);
        _pump(session);
      },
```

10. `_pump`:

```dart
  /// Sends what the send window allows; once a closing session (its shell
  /// has exited) has handed every buffered byte out, hands off to [_finish].
  void _pump(_Session session) {
    if (session.attachedMobileId == null) return;
    session.stream.pump();
    if (session.closing && session.stream.drained) _finish(session);
  }
```

In `agent_service.dart`: change the import to `import '../session/agent_sessions.dart';` (keep `session_manager.dart` only if still referenced in doc comments), the constructor parameter to `required AgentSessions sessions`, the field to `final AgentSessions _sessions;`, and the class doc's first paragraph to "routes app messages to [AgentSessions]".

- [ ] **Step 4: Run every gate; existing tests must be untouched**

```bash
cd packages/shellx_agent && dart analyze && dart test
cd ../shellx_client && dart analyze && dart test
cd ../../apps/desktop && flutter analyze && flutter test
cd ../.. && git diff --stat HEAD -- packages/shellx_agent/test packages/shellx_client/test apps/desktop/test
```

Expected: all green; the diff lists only `session_manager_test.dart` (2 new tests appended, no other line changed).

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent
git commit -m "refactor(agent): SessionManager uses SessionStream and an injectable id allocator; AgentService takes AgentSessions (existing tests unchanged)"
```

---

### Task 4: Local-link codec — messages, frames, HMAC (byte-exact with `vectors.txt`)

**Files:**
- Modify: `packages/shellx_core/lib/shellx_core.dart` (export `src/util/cbor_values.dart`)
- Modify: `packages/shellx_agent/pubspec.yaml` (add `cryptography: ^2.9.0`)
- Create: `packages/shellx_agent/lib/src/term/term_messages.dart`, `term_frames.dart`, `term_auth.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/term/term_codec_test.dart`

**Interfaces:**
- Produces:
  - `const int kTermProtocolVersion = 1;`
  - `sealed class TermToAgent` with `Uint8List encode()` and `static TermToAgent? decode(Uint8List payload)` (null for an unknown `t`; `FormatException` for malformed). Subclasses: `TermHello({required int v, required Uint8List nonce})`, `TermAuth({required Uint8List mac, required TermInfo info})`, `TermSnapshot({required Uint8List data, required bool last})`, `TermOut({required Uint8List data})`, `TermSize({required int cols, required int rows})`, `TermLocal()`, `TermExit({required int code})`
  - `final class TermInfo({required Uint8List termId, required String app, required String shell, required int pid, required int cols, required int rows, required int startedAt})` with `String get key` (hex of `termId`)
  - `sealed class AgentToTerm` with `encode()`/`decode()` likewise. Subclasses: `AgentChallenge({required Uint8List nonce, required Uint8List mac})`, `AgentReady()`, `AgentReject({required String reason})` (+ `static const limit = 'limit'`, `version = 'version'`), `AgentIn({required Uint8List data})`, `AgentResize({required int cols, required int rows})`, `AgentLocalSize()`
  - `const int kTermMaxFrame = 65536; const int kTermMaxChunk = 61440;`, `Uint8List termFrame(Uint8List payload)`, `final class TermFrameReader { List<Uint8List> add(List<int> chunk); }`
  - `Uint8List hmacSha256(List<int> key, List<int> data)`, `Uint8List agentProof(Uint8List secret, Uint8List nonceTerm, Uint8List nonceAgent)`, `Uint8List termProof(Uint8List secret, Uint8List nonceAgent, Uint8List nonceTerm)`

- [ ] **Step 1: Write the failing tests**

`test/term/term_codec_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// `term/protocol/vectors.txt`, written by the Rust side (plan P2a).
Map<String, String> _vectors() {
  final file = File('../../term/protocol/vectors.txt');
  return {
    for (final line in file.readAsLinesSync())
      if (line.isNotEmpty && !line.startsWith('#'))
        line.substring(0, line.indexOf('=')): line.substring(
          line.indexOf('=') + 1,
        ),
  };
}

Uint8List _fill(int byte, int length) =>
    Uint8List.fromList(List.filled(length, byte));

Uint8List _seq(int from, int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) from + i]);

void main() {
  final vectors = _vectors();

  group('byte-exact with vectors.txt', () {
    for (final name in vectors.keys.where((k) => k.startsWith('term.'))) {
      test('$name decodes and re-encodes to the same bytes', () {
        final bytes = hexToBytes(vectors[name]!);
        final message = TermToAgent.decode(bytes);
        expect(message, isNotNull);
        expect(bytesToHex(message!.encode()), vectors[name]);
      });
    }
    for (final name in vectors.keys.where((k) => k.startsWith('agent.'))) {
      test('$name decodes and re-encodes to the same bytes', () {
        final bytes = hexToBytes(vectors[name]!);
        final message = AgentToTerm.decode(bytes);
        expect(message, isNotNull);
        expect(bytesToHex(message!.encode()), vectors[name]);
      });
    }

    test('messages built from values encode to the vectors', () {
      expect(
        bytesToHex(TermHello(v: 1, nonce: _seq(1, 32)).encode()),
        vectors['term.hello'],
      );
      expect(
        bytesToHex(
          TermAuth(
            mac: _fill(0x55, 32),
            info: TermInfo(
              termId: _fill(0x11, 16),
              app: 'Terminal',
              shell: 'zsh',
              pid: 4242,
              cols: 80,
              rows: 24,
              startedAt: 1759276800000,
            ),
          ).encode(),
        ),
        vectors['term.auth'],
      );
      expect(
        bytesToHex(
          AgentChallenge(nonce: _seq(0x80, 32), mac: _fill(0x66, 32)).encode(),
        ),
        vectors['agent.challenge'],
      );
      expect(
        bytesToHex(const AgentReject(reason: AgentReject.limit).encode()),
        vectors['agent.reject_limit'],
      );
      expect(
        bytesToHex(
          AgentIn(data: Uint8List.fromList(utf8.encode('echo hi\r'))).encode(),
        ),
        vectors['agent.in'],
      );
      expect(
        bytesToHex(const AgentResize(cols: 50, rows: 20).encode()),
        vectors['agent.resize'],
      );
      expect(
        bytesToHex(const AgentLocalSize().encode()),
        vectors['agent.local_size'],
      );
      expect(bytesToHex(const AgentReady().encode()), vectors['agent.ready']);
    });

    test('decoded fields carry the values', () {
      final auth =
          TermToAgent.decode(hexToBytes(vectors['term.auth']!)) as TermAuth;
      expect(auth.info.app, 'Terminal');
      expect(auth.info.pid, 4242);
      expect(auth.info.startedAt, 1759276800000);
      expect(auth.info.key, '11' * 16);
      final out =
          TermToAgent.decode(hexToBytes(vectors['term.out']!)) as TermOut;
      expect(utf8.decode(out.data), 'tiếng Việt\r\n');
      final exit =
          TermToAgent.decode(hexToBytes(vectors['term.exit']!)) as TermExit;
      expect(exit.code, 130);
    });

    test('both proofs match auth.*_proof', () {
      final secret = hexToBytes(vectors['auth.secret']!);
      final nonceTerm = hexToBytes(vectors['auth.nonce_term']!);
      final nonceAgent = hexToBytes(vectors['auth.nonce_agent']!);
      expect(
        bytesToHex(agentProof(secret, nonceTerm, nonceAgent)),
        vectors['auth.agent_proof'],
      );
      expect(
        bytesToHex(termProof(secret, nonceAgent, nonceTerm)),
        vectors['auth.term_proof'],
      );
    });
  });

  test('hmacSha256 matches RFC 4231 test case 2', () {
    expect(
      bytesToHex(
        hmacSha256(
          utf8.encode('Jefe'),
          utf8.encode('what do ya want for nothing?'),
        ),
      ),
      '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    );
  });

  group('decode', () {
    Uint8List cbor(Map<String, Object?> map) => encodeCbor(map);

    test('an unknown t is null, not an error', () {
      expect(TermToAgent.decode(cbor({'t': 'future'})), isNull);
      expect(AgentToTerm.decode(cbor({'t': 'future'})), isNull);
    });

    test('keys in any order are accepted', () {
      final message = TermToAgent.decode(
        cbor({'v': 1, 't': 'hello', 'nonce': _seq(1, 32)}),
      );
      expect(message, isA<TermHello>());
    });

    final malformed = <String, Map<String, Object?>>{
      'no t': {'v': 1},
      'short nonce': {'t': 'hello', 'v': 1, 'nonce': _seq(1, 31)},
      'negative v': {'t': 'hello', 'v': -1, 'nonce': _seq(1, 32)},
      'zero cols': {'t': 'size', 'cols': 0, 'rows': 24},
      'cols over 65535': {'t': 'size', 'cols': 65536, 'rows': 24},
      'exit code over u32': {'t': 'exit', 'code': 1 << 32},
      'data not bytes': {'t': 'out', 'data': 'text'},
      'last not bool': {'t': 'snapshot', 'data': Uint8List(0), 'last': 1},
    };
    for (final MapEntry(:key, :value) in malformed.entries) {
      test('malformed: $key', () {
        expect(() => TermToAgent.decode(cbor(value)), throwsFormatException);
      });
    }

    test('not a map', () {
      expect(
        () => TermToAgent.decode(encodeCbor([1, 2])),
        throwsFormatException,
      );
      expect(
        () => TermToAgent.decode(Uint8List.fromList([0xff])),
        throwsFormatException,
      );
    });
  });

  group('frames', () {
    test('a frame is a 4-byte big-endian length and the payload', () {
      expect(termFrame(Uint8List.fromList([7, 8, 9])), [0, 0, 0, 3, 7, 8, 9]);
    });

    test('the reader splits a stream at any boundary', () {
      final payloads = [
        Uint8List.fromList([1]),
        Uint8List.fromList(List.filled(300, 2)),
        Uint8List(0),
      ];
      final stream = [for (final p in payloads) ...termFrame(p)];
      for (var cut = 0; cut <= stream.length; cut++) {
        final reader = TermFrameReader();
        final got = [
          ...reader.add(stream.sublist(0, cut)),
          ...reader.add(stream.sublist(cut)),
        ];
        expect(got, payloads, reason: 'cut at $cut');
      }
    });

    test('a length over 64 KiB is rejected before the payload arrives', () {
      final reader = TermFrameReader();
      expect(
        () => reader.add([0, 1, 0, 1]), // 65537
        throwsFormatException,
      );
    });

    test('termFrame refuses an oversized payload', () {
      expect(
        () => termFrame(Uint8List(kTermMaxFrame + 1)),
        throwsArgumentError,
      );
    });
  });

  test('toString never prints bytes', () {
    final secretish = _fill(0x42, 32);
    expect(
      '${TermHello(v: 1, nonce: secretish)}'
      '${AgentChallenge(nonce: secretish, mac: secretish)}'
      '${AgentIn(data: Uint8List.fromList(utf8.encode('password')))}',
      allOf(isNot(contains('42')), isNot(contains('password'))),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/term/term_codec_test.dart`
Expected: compile errors (`TermToAgent`, `encodeCbor`, … undefined).

- [ ] **Step 3: Implement**

`packages/shellx_core/lib/shellx_core.dart`: add `export 'src/util/cbor_values.dart';` (after `src/util/bytes.dart`).

`packages/shellx_agent/pubspec.yaml` `dependencies:` add `cryptography: ^2.9.0`, then run `dart pub get` at the repo root.

`term_frames.dart`:

```dart
import 'dart:typed_data';

/// Largest local-link frame payload (spec §6.2).
const int kTermMaxFrame = 65536;

/// Largest `data` piece of `snapshot`/`out` (spec §6.2).
const int kTermMaxChunk = 61440;

/// 4-byte big-endian length + [payload].
Uint8List termFrame(Uint8List payload) {
  if (payload.length > kTermMaxFrame) {
    throw ArgumentError.value(payload.length, 'payload', 'over 64 KiB');
  }
  final frame = Uint8List(4 + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length);
  frame.setRange(4, frame.length, payload);
  return frame;
}

/// Splits the bytes read from a local-link socket into frame payloads.
final class TermFrameReader {
  Uint8List _pending = Uint8List(0);

  /// Adds [chunk] and returns every payload now complete, in order. Throws
  /// [FormatException] as soon as a length over [kTermMaxFrame] is seen.
  List<Uint8List> add(List<int> chunk) {
    final joined = Uint8List(_pending.length + chunk.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, chunk);
    final payloads = <Uint8List>[];
    var offset = 0;
    while (joined.length - offset >= 4) {
      final length = ByteData.sublistView(
        joined,
        offset,
        offset + 4,
      ).getUint32(0);
      if (length > kTermMaxFrame) {
        throw const FormatException('local-link frame over 64 KiB');
      }
      if (joined.length - offset - 4 < length) break;
      payloads.add(
        Uint8List.fromList(
          Uint8List.sublistView(joined, offset + 4, offset + 4 + length),
        ),
      );
      offset += 4 + length;
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(joined, offset));
    return payloads;
  }
}
```

`term_auth.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:shellx_core/shellx_core.dart';

const int _blockLength = 64;
final DartSha256 _sha256 = DartSha256();

Uint8List _hash(List<int> data) =>
    Uint8List.fromList(_sha256.hashSync(data).bytes);

/// RFC 2104 HMAC-SHA256.
Uint8List hmacSha256(List<int> key, List<int> data) {
  final normalized = key.length > _blockLength ? _hash(key) : key;
  final inner = Uint8List(_blockLength);
  final outer = Uint8List(_blockLength);
  for (var i = 0; i < _blockLength; i++) {
    final k = i < normalized.length ? normalized[i] : 0;
    inner[i] = k ^ 0x36;
    outer[i] = k ^ 0x5c;
  }
  return _hash(concatBytes([outer, _hash(concatBytes([inner, data]))]));
}

final _agentLabel = utf8.encode('shellx-term/agent');
final _termLabel = utf8.encode('shellx-term/term');

/// The agent proves it knows the secret (spec §6.3 step 2).
Uint8List agentProof(
  Uint8List secret,
  Uint8List nonceTerm,
  Uint8List nonceAgent,
) => hmacSha256(secret, concatBytes([_agentLabel, nonceTerm, nonceAgent]));

/// What `shellx-term` must send in `auth` (spec §6.3 step 4).
Uint8List termProof(
  Uint8List secret,
  Uint8List nonceAgent,
  Uint8List nonceTerm,
) => hmacSha256(secret, concatBytes([_termLabel, nonceAgent, nonceTerm]));
```

`term_messages.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Local-link protocol version (spec §6.3).
const int kTermProtocolVersion = 1;

/// Encodes with keys in bytewise ascending order (spec §6.2): every key is
/// ASCII, so `String.compareTo` order is byte order.
Uint8List _encode(Map<String, Object?> fields) {
  final keys = fields.keys.toList()..sort();
  return encodeCbor({for (final key in keys) key: fields[key]});
}

(Map<Object?, Object?>, String) _parse(Uint8List payload) {
  final value = decodeCbor(payload);
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('local-link message must be a CBOR map');
  }
  final t = value['t'];
  if (t is! String) throw const FormatException('local-link message without "t"');
  return (value, t);
}

final class _Fields {
  _Fields(this._map, this._t);
  final Map<Object?, Object?> _map;
  final String _t;

  FormatException _bad(String key) =>
      FormatException('$_t: "$key" missing or wrong type');

  int uint(String key) {
    final value = _map[key];
    if (value is int && value >= 0) return value;
    throw _bad(key);
  }

  int u32(String key) {
    final value = uint(key);
    if (value > 0xffffffff) throw _bad(key);
    return value;
  }

  int dim(String key) {
    final value = uint(key);
    if (value < 1 || value > 0xffff) throw _bad(key);
    return value;
  }

  Uint8List bytes(String key, [int? length]) {
    final value = _map[key];
    if (value is Uint8List && (length == null || value.length == length)) {
      return value;
    }
    throw _bad(key);
  }

  String text(String key) {
    final value = _map[key];
    if (value is String) return value;
    throw _bad(key);
  }

  bool boolean(String key) {
    final value = _map[key];
    if (value is bool) return value;
    throw _bad(key);
  }
}

/// What `shellx-term` reported about its window in `auth` (spec §6.3).
final class TermInfo {
  const TermInfo({
    required this.termId,
    required this.app,
    required this.shell,
    required this.pid,
    required this.cols,
    required this.rows,
    required this.startedAt,
  });

  /// 16 random bytes per window, kept across reconnects.
  final Uint8List termId;
  final String app;
  final String shell;

  /// The inner shell's pid.
  final int pid;
  final int cols;
  final int rows;

  /// Unix milliseconds when `shellx-term` started.
  final int startedAt;

  /// [termId] as hex: the key a reconnecting window is found by.
  String get key => bytesToHex(termId);

  @override
  String toString() => 'TermInfo(app: $app, shell: $shell, pid: $pid, '
      '${cols}x$rows)';
}

/// `shellx-term` → agent (spec §6.3, §6.4).
sealed class TermToAgent {
  const TermToAgent();
  Map<String, Object?> _fields();
  Uint8List encode() => _encode(_fields());

  /// Null for an unknown `t`. Throws [FormatException] when malformed.
  static TermToAgent? decode(Uint8List payload) {
    final (map, t) = _parse(payload);
    final f = _Fields(map, t);
    return switch (t) {
      'hello' => TermHello(v: f.uint('v'), nonce: f.bytes('nonce', 32)),
      'auth' => TermAuth(
        mac: f.bytes('mac', 32),
        info: TermInfo(
          termId: f.bytes('term_id', 16),
          app: f.text('app'),
          shell: f.text('shell'),
          pid: f.u32('pid'),
          cols: f.dim('cols'),
          rows: f.dim('rows'),
          startedAt: f.uint('started_at'),
        ),
      ),
      'snapshot' => TermSnapshot(
        data: f.bytes('data'),
        last: f.boolean('last'),
      ),
      'out' => TermOut(data: f.bytes('data')),
      'size' => TermSize(cols: f.dim('cols'), rows: f.dim('rows')),
      'local' => const TermLocal(),
      'exit' => TermExit(code: f.u32('code')),
      _ => null,
    };
  }

  @override
  String toString() => '$runtimeType';
}

final class TermHello extends TermToAgent {
  const TermHello({required this.v, required this.nonce});
  final int v;
  final Uint8List nonce;
  @override
  Map<String, Object?> _fields() => {'t': 'hello', 'v': v, 'nonce': nonce};
}

final class TermAuth extends TermToAgent {
  const TermAuth({required this.mac, required this.info});
  final Uint8List mac;
  final TermInfo info;
  @override
  Map<String, Object?> _fields() => {
    't': 'auth',
    'mac': mac,
    'term_id': info.termId,
    'app': info.app,
    'shell': info.shell,
    'pid': info.pid,
    'cols': info.cols,
    'rows': info.rows,
    'started_at': info.startedAt,
  };
}

final class TermSnapshot extends TermToAgent {
  const TermSnapshot({required this.data, required this.last});
  final Uint8List data;
  final bool last;
  @override
  Map<String, Object?> _fields() => {
    't': 'snapshot',
    'data': data,
    'last': last,
  };
}

final class TermOut extends TermToAgent {
  const TermOut({required this.data});
  final Uint8List data;
  @override
  Map<String, Object?> _fields() => {'t': 'out', 'data': data};
}

final class TermSize extends TermToAgent {
  const TermSize({required this.cols, required this.rows});
  final int cols, rows;
  @override
  Map<String, Object?> _fields() => {'t': 'size', 'cols': cols, 'rows': rows};
}

final class TermLocal extends TermToAgent {
  const TermLocal();
  @override
  Map<String, Object?> _fields() => {'t': 'local'};
}

final class TermExit extends TermToAgent {
  const TermExit({required this.code});
  final int code;
  @override
  Map<String, Object?> _fields() => {'t': 'exit', 'code': code};
}

/// Agent → `shellx-term` (spec §6.3, §6.4).
sealed class AgentToTerm {
  const AgentToTerm();
  Map<String, Object?> _fields();
  Uint8List encode() => _encode(_fields());

  /// Null for an unknown `t`. Throws [FormatException] when malformed.
  static AgentToTerm? decode(Uint8List payload) {
    final (map, t) = _parse(payload);
    final f = _Fields(map, t);
    return switch (t) {
      'challenge' => AgentChallenge(
        nonce: f.bytes('nonce', 32),
        mac: f.bytes('mac', 32),
      ),
      'ready' => const AgentReady(),
      'reject' => AgentReject(reason: f.text('reason')),
      'in' => AgentIn(data: f.bytes('data')),
      'resize' => AgentResize(cols: f.dim('cols'), rows: f.dim('rows')),
      'local_size' => const AgentLocalSize(),
      _ => null,
    };
  }

  @override
  String toString() => '$runtimeType';
}

final class AgentChallenge extends AgentToTerm {
  const AgentChallenge({required this.nonce, required this.mac});
  final Uint8List nonce;
  final Uint8List mac;
  @override
  Map<String, Object?> _fields() => {
    't': 'challenge',
    'nonce': nonce,
    'mac': mac,
  };
}

final class AgentReady extends AgentToTerm {
  const AgentReady();
  @override
  Map<String, Object?> _fields() => {'t': 'ready'};
}

final class AgentReject extends AgentToTerm {
  const AgentReject({required this.reason});
  static const limit = 'limit';
  static const version = 'version';
  final String reason;
  @override
  Map<String, Object?> _fields() => {'t': 'reject', 'reason': reason};
  @override
  String toString() => 'AgentReject($reason)';
}

final class AgentIn extends AgentToTerm {
  const AgentIn({required this.data});
  final Uint8List data;
  @override
  Map<String, Object?> _fields() => {'t': 'in', 'data': data};
}

final class AgentResize extends AgentToTerm {
  const AgentResize({required this.cols, required this.rows});
  final int cols, rows;
  @override
  Map<String, Object?> _fields() => {
    't': 'resize',
    'cols': cols,
    'rows': rows,
  };
  @override
  String toString() => 'AgentResize(${cols}x$rows)';
}

final class AgentLocalSize extends AgentToTerm {
  const AgentLocalSize();
  @override
  Map<String, Object?> _fields() => {'t': 'local_size'};
}
```

`lib/shellx_agent.dart` — add `export 'src/term/term_auth.dart';`, `export 'src/term/term_frames.dart';`, `export 'src/term/term_messages.dart';`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd packages/shellx_agent && dart analyze && dart test` and `cd ../shellx_core && dart analyze && dart test`
Expected: all pass. If a vector fails only on key order, check that `encodeCbor` keeps map insertion order (package `cbor`'s `CborMap` is insertion-ordered); do not change `vectors.txt`.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_core/lib/shellx_core.dart packages/shellx_agent pubspec.lock
git commit -m "feat(agent): local-link codec — messages, frames and HMAC proofs, byte-exact with term/protocol/vectors.txt"
```

---

### Task 5: `endpoint` file (spec §6.1)

**Files:**
- Create: `packages/shellx_agent/lib/src/term/term_endpoint.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/term/term_endpoint_test.dart`

**Interfaces:**
- Produces:
  - `String termEndpointPath({required Map<String, String> environment, required bool windows})` — throws `StateError` when `HOME` / `LOCALAPPDATA` is unset or empty
  - `String formatEndpoint(int port, Uint8List secret)`
  - `final class EndpointFile(String path, {bool? posix})` with `Future<String> write(int port, Uint8List secret)` (returns the exact contents written) and `Future<void> deleteIfOwned(String contents)`

- [ ] **Step 1: Write the failing tests**

```dart
@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  setUp(() async => home = await Directory.systemTemp.createTemp('endpoint-'));
  tearDown(() => home.delete(recursive: true));

  final secret = Uint8List.fromList(List.generate(32, (i) => i));

  test('paths per platform', () {
    expect(
      termEndpointPath(environment: {'HOME': '/Users/u'}, windows: false),
      '/Users/u/Library/Application Support/ShellX/term/endpoint',
    );
    expect(
      termEndpointPath(
        environment: {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
        windows: true,
      ),
      r'C:\Users\u\AppData\Local\ShellX\term\endpoint',
    );
    expect(
      () => termEndpointPath(environment: {'HOME': ''}, windows: false),
      throwsStateError,
    );
    expect(
      () => termEndpointPath(environment: const {}, windows: true),
      throwsStateError,
    );
  });

  test('format is exactly three lines (spec §6.1)', () {
    expect(
      formatEndpoint(54321, secret),
      'v=1\nport=54321\nsecret='
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n',
    );
  });

  test('write creates the directory 0700 and the file 0600', () async {
    final path = termEndpointPath(
      environment: {'HOME': home.path},
      windows: false,
    );
    final contents = await EndpointFile(path).write(4000, secret);
    expect(File(path).readAsStringSync(), contents);
    expect(File(path).statSync().modeString(), 'rw-------');
    expect(File(path).parent.statSync().modeString(), 'rwx------');
    final leftovers = File(path).parent.listSync().map((e) => e.path);
    expect(leftovers, [path], reason: 'no temp file left behind');
  });

  test('a second write replaces the file', () async {
    final path = '${home.path}/term/endpoint';
    final file = EndpointFile(path);
    await file.write(1, secret);
    final second = await file.write(2, secret);
    expect(File(path).readAsStringSync(), second);
    expect(second, contains('port=2'));
  });

  test('deleteIfOwned deletes only our own contents', () async {
    final path = '${home.path}/term/endpoint';
    final file = EndpointFile(path);
    final ours = await file.write(1, secret);
    File(path).writeAsStringSync('v=1\nport=9\nsecret=${'0' * 64}\n');
    await file.deleteIfOwned(ours);
    expect(File(path).existsSync(), isTrue, reason: 'a newer agent wrote it');
    final again = await file.write(3, secret);
    await file.deleteIfOwned(again);
    expect(File(path).existsSync(), isFalse);
    await file.deleteIfOwned(again); // already gone: no error
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/term/term_endpoint_test.dart`
Expected: compile errors.

- [ ] **Step 3: Implement**

```dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Where the agent tells `shellx-term` how to reach it (spec §6.1): macOS
/// `$HOME/Library/Application Support/ShellX/term/endpoint`, Windows
/// `%LOCALAPPDATA%\ShellX\term\endpoint` — the same paths
/// `term/src/proto/endpoint.rs` reads.
String termEndpointPath({
  required Map<String, String> environment,
  required bool windows,
}) {
  final variable = windows ? 'LOCALAPPDATA' : 'HOME';
  final base = environment[variable];
  if (base == null || base.isEmpty) throw StateError('$variable is not set');
  return windows
      ? '$base\\ShellX\\term\\endpoint'
      : '$base/Library/Application Support/ShellX/term/endpoint';
}

/// The file's exact contents: three lines, trailing newline (spec §6.1).
String formatEndpoint(int port, Uint8List secret) =>
    'v=1\nport=$port\nsecret=${bytesToHex(secret).toLowerCase()}\n';

/// Writes and removes the `endpoint` file.
final class EndpointFile {
  EndpointFile(this.path, {bool? posix}) : _posix = posix ?? !Platform.isWindows;

  final String path;
  final bool _posix;

  /// Writes atomically (temp file, then rename). On POSIX the directory is
  /// made 0700 and the temp file 0600 **before** the secret goes in, so the
  /// secret is never readable by another account, even briefly. Windows
  /// files inherit `%LOCALAPPDATA%`'s owner-only access. Returns the
  /// contents written, for [deleteIfOwned].
  Future<String> write(int port, Uint8List secret) async {
    final contents = formatEndpoint(port, secret);
    final directory = File(path).parent;
    await directory.create(recursive: true);
    if (_posix) await _chmod('700', directory.path);
    final temp = File(
      '$path.tmp-$pid-${Random.secure().nextInt(1 << 32).toRadixString(16)}',
    );
    try {
      await temp.writeAsBytes(const [], flush: true);
      if (_posix) await _chmod('600', temp.path);
      await temp.writeAsString(contents, flush: true);
      await temp.rename(path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    return contents;
  }

  /// Deletes the file only while it still holds [contents]: a newer start
  /// (or another agent instance) may have replaced it. Never throws for a
  /// missing file.
  Future<void> deleteIfOwned(String contents) async {
    final file = File(path);
    try {
      if (await file.readAsString() == contents) await file.delete();
    } on FileSystemException {
      // Already gone, or unreadable: nothing of ours to remove.
    }
  }

  static Future<void> _chmod(String mode, String target) async {
    final result = await Process.run('/bin/chmod', [mode, target]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed', target);
    }
  }
}
```

Export `src/term/term_endpoint.dart` from `lib/shellx_agent.dart`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd packages/shellx_agent && dart analyze && dart test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent
git commit -m "feat(agent): endpoint file — per-platform path, 0700/0600 before the secret, atomic write, delete only our own (spec §6.1)"
```

---

### Task 6: `TermServer` — loopback port, handshake, links

**Files:**
- Create: `packages/shellx_agent/lib/src/term/term_link.dart`, `packages/shellx_agent/lib/src/term/term_server.dart`
- Create: `packages/shellx_agent/test/support/fake_term.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/term/term_server_test.dart`

**Interfaces:**
- Consumes: Task 4 codec, Task 5 `EndpointFile`, `constantTimeEquals` (`shellx_core`)
- Produces:
  - `abstract interface class TermLink { TermInfo get info; Stream<TermToAgent> get messages; void send(AgentToTerm message); void close(); }` — `messages` is single-subscription, buffered until listened to, and done when the connection ends for any reason; `send` never blocks
  - `const int kTermMaxQueuedBytes = 1048576;`
  - `final class TermServer({required String endpointPath, required bool Function(TermInfo info) admit, required void Function(TermLink link) onLink, Duration handshakeTimeout = const Duration(seconds: 5), Random? random, bool? posix})` with `bool get running`, `int? get port`, `Future<void> start()`, `Future<void> stop()`

- [ ] **Step 1: Write the fake term and the failing tests**

`test/support/fake_term.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// Reads the agent's `endpoint` file: (port, secret).
(int, Uint8List) readEndpoint(String path) {
  final lines = File(path).readAsLinesSync();
  return (
    int.parse(lines[1].substring('port='.length)),
    Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(lines[2].substring(7 + i, 9 + i), radix: 16),
    ]),
  );
}

TermInfo termInfo({int id = 1, String app = 'Terminal'}) => TermInfo(
  termId: Uint8List.fromList(List.filled(16, id)),
  app: app,
  shell: 'zsh',
  pid: 4242,
  cols: 80,
  rows: 24,
  startedAt: 1759276800000,
);

/// Plays `shellx-term` over a real socket with the real codec.
final class FakeTerm {
  FakeTerm._(this._socket) {
    _socket.listen(
      (chunk) {
        for (final payload in _reader.add(chunk)) {
          _received.add(AgentToTerm.decode(payload));
        }
      },
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
        _received.close();
      },
      onError: (Object _) {},
    );
  }

  static Future<FakeTerm> connect(int port) async =>
      FakeTerm._(await Socket.connect(InternetAddress.loopbackIPv4, port));

  final Socket _socket;
  final _reader = TermFrameReader();
  final _received = StreamController<AgentToTerm?>();
  late final _next = StreamIterator(_received.stream);
  final _closed = Completer<void>();

  /// Completes when the agent closes the connection.
  Future<void> get closed => _closed.future;

  void send(TermToAgent message) => sendRaw(termFrame(message.encode()));

  void sendRaw(List<int> bytes) => _socket.add(bytes);

  /// The next message from the agent, or null when the connection ended.
  Future<AgentToTerm?> next({
    Duration timeout = const Duration(seconds: 5),
  }) async => await _next.moveNext().timeout(timeout) ? _next.current : null;

  /// Runs the full handshake; returns the agent's answer to `auth`.
  Future<AgentToTerm?> handshake(
    Uint8List secret, {
    TermInfo? info,
    bool wrongProof = false,
  }) async {
    final nonce = Uint8List.fromList(List.generate(32, (i) => i + 1));
    send(TermHello(v: 1, nonce: nonce));
    final challenge = await next();
    if (challenge is! AgentChallenge) return challenge;
    final proof = termProof(
      wrongProof ? Uint8List(32) : secret,
      challenge.nonce,
      nonce,
    );
    send(TermAuth(mac: proof, info: info ?? termInfo()));
    return next();
  }

  void destroy() => _socket.destroy();
}
```

`test/term/term_server_test.dart`:

```dart
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_term.dart';

void main() {
  late Directory home;
  late String path;
  late TermServer server;
  late List<TermLink> links;
  late bool admitAll;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('term-server-');
    path = '${home.path}/term/endpoint';
    links = [];
    admitAll = true;
    server = TermServer(
      endpointPath: path,
      admit: (_) => admitAll,
      onLink: links.add,
      handshakeTimeout: const Duration(milliseconds: 300),
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await home.delete(recursive: true);
  });

  test('start writes the endpoint; stop removes it and closes the port', () async {
    expect(server.running, isTrue);
    final (port, _) = readEndpoint(path);
    expect(port, server.port);
    await server.stop();
    expect(server.running, isFalse);
    expect(File(path).existsSync(), isFalse);
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
  });

  test('a correct handshake gets ready and hands over a link', () async {
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    final nonce = Uint8List.fromList(List.generate(32, (i) => i + 1));
    term.send(TermHello(v: 1, nonce: nonce));
    final challenge = await term.next() as AgentChallenge;
    expect(
      challenge.mac,
      agentProof(secret, nonce, challenge.nonce),
      reason: 'the agent proves it knows the secret',
    );
    term.send(
      TermAuth(
        mac: termProof(secret, challenge.nonce, nonce),
        info: termInfo(app: 'iTerm2'),
      ),
    );
    expect(await term.next(), isA<AgentReady>());
    await pumpEventQueue();
    expect(links.single.info.app, 'iTerm2');

    final got = <TermToAgent>[];
    links.single.messages.listen(got.add);
    term.send(TermSnapshot(data: Uint8List.fromList([65]), last: true));
    links.single.send(AgentIn(data: Uint8List.fromList([66])));
    expect(await term.next(), isA<AgentIn>());
    await pumpEventQueue();
    expect(got.single, isA<TermSnapshot>());
    term.destroy();
  });

  test('a wrong term proof is closed without ready or reject', () async {
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    expect(await term.handshake(secret, wrongProof: true), isNull);
    expect(links, isEmpty);
  });

  test('a peer without the key that stops after hello is cut off', () async {
    final (port, _) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    term.send(TermHello(v: 1, nonce: Uint8List(32)));
    expect(await term.next(), isA<AgentChallenge>());
    await term.closed.timeout(const Duration(seconds: 2));
    expect(links, isEmpty);
  });

  test('a byte-by-byte trickle cannot outlast the deadline', () async {
    final (port, _) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    final bytes = termFrame(TermHello(v: 1, nonce: Uint8List(32)).encode());
    final sw = Stopwatch()..start();
    unawaited(() async {
      for (final byte in bytes) {
        term.sendRaw([byte]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }());
    await term.closed.timeout(const Duration(seconds: 2));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('an unknown version is rejected with version', () async {
    final (port, _) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    term.send(TermHello(v: 2, nonce: Uint8List(32)));
    expect(
      (await term.next() as AgentReject).reason,
      AgentReject.version,
    );
    await term.closed.timeout(const Duration(seconds: 2));
  });

  test('admit false is rejected with limit after a correct auth', () async {
    admitAll = false;
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    final answer = await term.handshake(secret);
    expect((answer as AgentReject).reason, AgentReject.limit);
    await term.closed.timeout(const Duration(seconds: 2));
    expect(links, isEmpty);
  });

  test('an oversized frame or an unknown message before ready closes', () async {
    final (port, _) = readEndpoint(path);
    final big = await FakeTerm.connect(port);
    big.sendRaw([0, 1, 0, 1]);
    await big.closed.timeout(const Duration(seconds: 2));
    final odd = await FakeTerm.connect(port);
    odd.sendRaw(termFrame(encodeCbor({'t': 'future'})));
    await odd.closed.timeout(const Duration(seconds: 2));
  });

  test('a link whose peer stops reading closes itself past 1 MiB queued', () async {
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    expect(await term.handshake(secret), isA<AgentReady>());
    await pumpEventQueue();
    final link = links.single;
    var done = false;
    link.messages.listen(null, onDone: () => done = true);
    final chunk = AgentIn(data: Uint8List(kTermMaxChunk));
    for (var i = 0; i < 40; i++) {
      link.send(chunk); // synchronous: nothing is flushed in between
    }
    await pumpEventQueue();
    expect(done, isTrue);
  });

  test('stop closes links and pending handshakes; restart has a new secret',
      () async {
    final (port, secret) = readEndpoint(path);
    final linked = await FakeTerm.connect(port);
    expect(await linked.handshake(secret), isA<AgentReady>());
    final pending = await FakeTerm.connect(port);
    pending.send(TermHello(v: 1, nonce: Uint8List(32)));
    expect(await pending.next(), isA<AgentChallenge>());
    await server.stop();
    await linked.closed.timeout(const Duration(seconds: 2));
    await pending.closed.timeout(const Duration(seconds: 2));
    await server.start();
    final (_, newSecret) = readEndpoint(path);
    expect(newSecret, isNot(secret));
  });

  test('stop leaves an endpoint file rewritten by someone else', () async {
    File(path).writeAsStringSync('v=1\nport=9\nsecret=${'0' * 64}\n');
    await server.stop();
    expect(File(path).existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/term/term_server_test.dart`
Expected: compile errors (`TermServer`, `TermLink`).

- [ ] **Step 3: Implement**

`term_link.dart`:

```dart
import 'term_messages.dart';

/// Unsent bytes an agent → `shellx-term` link may hold before it closes
/// itself (spec §7.8): a terminal that stops reading reconnects and resyncs
/// from its snapshot instead of growing the agent's memory.
const int kTermMaxQueuedBytes = 1024 * 1024;

/// One authenticated `shellx-term` connection (spec §6.4).
abstract interface class TermLink {
  TermInfo get info;

  /// `snapshot`, `out`, `size`, `local` and `exit`, in arrival order;
  /// unknown types are dropped. Single-subscription, buffered until
  /// listened to, done when the connection ends for any reason.
  Stream<TermToAgent> get messages;

  /// Never blocks. Ignored once closed.
  void send(AgentToTerm message);

  /// Ends sharing for this window. The terminal itself keeps running and
  /// reconnects on its own schedule (spec §6.5).
  void close();
}
```

`term_server.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'term_auth.dart';
import 'term_endpoint.dart';
import 'term_frames.dart';
import 'term_link.dart';
import 'term_messages.dart';

/// The agent's loopback port for `shellx-term` (spec §6.1, §6.3). [start]
/// binds `127.0.0.1` on a port the OS picks, makes a fresh 32-byte secret
/// and writes the `endpoint` file; [stop] closes the port, every pending
/// handshake and every link, and deletes the file if it is still ours.
///
/// Each connection must finish the handshake within [handshakeTimeout]
/// (counted over the whole handshake, so a byte-by-byte trickle cannot hold
/// it open). `admit` decides `reject limit` once `auth` is verified (spec
/// §7.8 step 3: a reconnecting window must never be turned away).
final class TermServer {
  TermServer({
    required String endpointPath,
    required bool Function(TermInfo info) admit,
    required void Function(TermLink link) onLink,
    Duration handshakeTimeout = const Duration(seconds: 5),
    Random? random,
    bool? posix,
  }) : _endpoint = EndpointFile(endpointPath, posix: posix),
       _admit = admit,
       _onLink = onLink,
       _handshakeTimeout = handshakeTimeout,
       _random = random ?? Random.secure();

  final EndpointFile _endpoint;
  final bool Function(TermInfo info) _admit;
  final void Function(TermLink link) _onLink;
  final Duration _handshakeTimeout;
  final Random _random;

  ServerSocket? _server;
  String? _contents;
  final _connections = <_Connection>{};

  bool get running => _server != null;
  int? get port => _server?.port;

  /// Throws when the port cannot be opened or the file cannot be written;
  /// nothing stays open then.
  Future<void> start() async {
    if (_server != null) return;
    final secret = Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => _accept(socket, secret), onError: (Object _) {});
    try {
      _contents = await _endpoint.write(server.port, secret);
    } catch (_) {
      await server.close();
      rethrow;
    }
    _server = server;
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    final contents = _contents!;
    _contents = null;
    for (final connection in _connections.toList()) {
      connection.close();
    }
    await server.close();
    await _endpoint.deleteIfOwned(contents);
  }

  void _accept(Socket socket, Uint8List secret) {
    final connection = _Connection(
      socket: socket,
      secret: secret,
      admit: _admit,
      random: _random,
      timeout: _handshakeTimeout,
      onReady: (link) {
        if (_server == null) {
          link.close();
          return;
        }
        _onLink(link);
      },
    );
    _connections.add(connection);
    connection.done.then((_) => _connections.remove(connection));
  }
}

enum _Stage { hello, auth, ready }

/// One accepted socket: the handshake, then the [TermLink].
final class _Connection implements TermLink {
  _Connection({
    required Socket socket,
    required Uint8List secret,
    required bool Function(TermInfo info) admit,
    required Random random,
    required Duration timeout,
    required void Function(TermLink link) onReady,
  }) : _socket = socket,
       _secret = secret,
       _admit = admit,
       _random = random,
       _onReady = onReady {
    _deadline = Timer(timeout, close);
    _subscription = socket.listen(
      _onBytes,
      onDone: close,
      onError: (Object _) => close(),
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final Uint8List _secret;
  final bool Function(TermInfo info) _admit;
  final Random _random;
  final void Function(TermLink link) _onReady;
  final _reader = TermFrameReader();
  final _messages = StreamController<TermToAgent>();
  final _done = Completer<void>();
  late final Timer _deadline;
  late final StreamSubscription<Uint8List> _subscription;

  _Stage _stage = _Stage.hello;
  Uint8List? _nonceTerm;
  Uint8List? _nonceAgent;
  TermInfo? _info;
  bool _closed = false;

  final _queue = <Uint8List>[];
  int _queued = 0;
  bool _flushing = false;
  bool _closeWhenFlushed = false;

  Future<void> get done => _done.future;

  @override
  TermInfo get info => _info!;

  @override
  Stream<TermToAgent> get messages => _messages.stream;

  @override
  void send(AgentToTerm message) {
    if (_stage == _Stage.ready) _write(message);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _deadline.cancel();
    _queue.clear();
    unawaited(_subscription.cancel());
    _socket.destroy();
    unawaited(_messages.close());
    _done.complete();
  }

  void _onBytes(Uint8List chunk) {
    final List<Uint8List> payloads;
    try {
      payloads = _reader.add(chunk);
    } on FormatException {
      close();
      return;
    }
    for (final payload in payloads) {
      if (_closed || _closeWhenFlushed) return;
      _onPayload(payload);
    }
  }

  void _onPayload(Uint8List payload) {
    final TermToAgent? message;
    try {
      message = TermToAgent.decode(payload);
    } on FormatException {
      close();
      return;
    }
    switch (_stage) {
      case _Stage.hello:
        if (message is! TermHello) return close();
        if (message.v != kTermProtocolVersion) {
          return _rejectAndClose(AgentReject.version);
        }
        final nonceAgent = Uint8List.fromList(
          List.generate(32, (_) => _random.nextInt(256)),
        );
        _nonceTerm = message.nonce;
        _nonceAgent = nonceAgent;
        _stage = _Stage.auth;
        _write(
          AgentChallenge(
            nonce: nonceAgent,
            mac: agentProof(_secret, message.nonce, nonceAgent),
          ),
        );
      case _Stage.auth:
        if (message is! TermAuth) return close();
        final expected = termProof(_secret, _nonceAgent!, _nonceTerm!);
        if (!constantTimeEquals(message.mac, expected)) return close();
        if (!_admit(message.info)) return _rejectAndClose(AgentReject.limit);
        _info = message.info;
        _deadline.cancel();
        _stage = _Stage.ready;
        _write(const AgentReady());
        _onReady(this);
      case _Stage.ready:
        if (message != null) _messages.add(message);
    }
  }

  void _rejectAndClose(String reason) {
    _write(AgentReject(reason: reason));
    _closeWhenFlushed = true;
    if (!_flushing) close();
  }

  void _write(AgentToTerm message) {
    if (_closed) return;
    final frame = termFrame(message.encode());
    _queued += frame.length;
    if (_queued > kTermMaxQueuedBytes) return close();
    _queue.add(frame);
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty && !_closed) {
        final frame = _queue.removeAt(0);
        _socket.add(frame);
        await _socket.flush();
        _queued -= frame.length;
      }
    } catch (_) {
      close();
    } finally {
      _flushing = false;
      if (_closeWhenFlushed) close();
    }
  }
}
```

Export `src/term/term_link.dart` and `src/term/term_server.dart` from `lib/shellx_agent.dart`.

- [ ] **Step 4: Run to verify they pass (3× in a row)**

Run: `cd packages/shellx_agent && dart analyze && for i in 1 2 3; do dart test test/term/term_server_test.dart || break; done && dart test`
Expected: all pass, three times.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent
git commit -m "feat(agent): TermServer — loopback port, endpoint, HMAC handshake with 5 s deadline, reject limit/version, links that close past 1 MiB queued"
```

---

### Task 7: Window-title parser (spec §7.4)

**Files:**
- Create: `packages/shellx_agent/lib/src/term/osc_title.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/term/osc_title_test.dart`

**Interfaces:**
- Produces: `final class OscTitleParser { static const int maxTitleLength = 200; String? feed(Uint8List data); void reset(); }` — `feed` returns the last title completed inside `data` (a sequence may start in an earlier call), or null

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('OSC 0 and OSC 2, ended by BEL or ST', () {
    expect(OscTitleParser().feed(_b('\x1b]0;one\x07')), 'one');
    expect(OscTitleParser().feed(_b('\x1b]2;two\x1b\\')), 'two');
  });

  test('other OSCs and CSIs are not titles', () {
    final parser = OscTitleParser();
    expect(parser.feed(_b('\x1b]1;icon\x07\x1b[2J\x1b]7;file:///\x07')), isNull);
  });

  test('the last of several titles wins', () {
    expect(OscTitleParser().feed(_b('\x1b]0;a\x07x\x1b]2;b\x07')), 'b');
  });

  test('a title split at every byte position is still found', () {
    final bytes = _b('ab\x1b]0;tiếng Việt\x07cd');
    for (var cut = 0; cut <= bytes.length; cut++) {
      final parser = OscTitleParser();
      final first = parser.feed(Uint8List.sublistView(bytes, 0, cut));
      final second = parser.feed(Uint8List.sublistView(bytes, cut));
      expect(second ?? first, 'tiếng Việt', reason: 'cut at $cut');
    }
  });

  test('titles are cut to 200 characters', () {
    final title = OscTitleParser().feed(_b('\x1b]0;${'é' * 300}\x07'));
    expect(title!.runes.length, OscTitleParser.maxTitleLength);
  });

  test('a sequence over 4 KiB is ignored, and parsing recovers', () {
    final parser = OscTitleParser();
    expect(parser.feed(_b('\x1b]0;${'x' * 5000}\x07')), isNull);
    expect(parser.feed(_b('\x1b]0;ok\x07')), 'ok');
  });

  test('reset forgets a half-read sequence', () {
    final parser = OscTitleParser()..feed(_b('\x1b]0;half'));
    parser.reset();
    expect(parser.feed(_b('\x07')), isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/term/osc_title_test.dart`
Expected: compile error.

- [ ] **Step 3: Implement**

```dart
import 'dart:convert';
import 'dart:typed_data';

enum _State { ground, escape, param, payload, payloadEscape, ignore, ignoreEscape }

/// Finds window titles (OSC 0 and OSC 2, ended by BEL or ST) in terminal
/// output, across chunk boundaries (spec §7.4). Longer than 4 KiB is not a
/// title anyone wants to see: such a sequence is skipped.
final class OscTitleParser {
  static const int maxTitleLength = 200;
  static const int _maxPayload = 4096;

  _State _state = _State.ground;
  final _param = StringBuffer();
  final _payload = BytesBuilder(copy: false);

  void reset() {
    _state = _State.ground;
    _param.clear();
    _payload.clear();
  }

  String? feed(Uint8List data) {
    String? title;
    for (final byte in data) {
      title = _step(byte) ?? title;
    }
    return title;
  }

  String? _step(int byte) {
    switch (_state) {
      case _State.ground:
        if (byte == 0x1b) _state = _State.escape;
      case _State.escape:
        if (byte == 0x5d) {
          _param.clear();
          _state = _State.param;
        } else if (byte != 0x1b) {
          _state = _State.ground;
        }
      case _State.param:
        if (byte >= 0x30 && byte <= 0x39 && _param.length < 3) {
          _param.writeCharCode(byte);
        } else if (byte == 0x3b) {
          final p = _param.toString();
          _payload.clear();
          _state = p == '0' || p == '2' ? _State.payload : _State.ignore;
        } else if (byte == 0x07) {
          _state = _State.ground;
        } else if (byte == 0x1b) {
          _state = _State.escape;
        } else {
          _state = _State.ignore;
        }
      case _State.payload:
        if (byte == 0x07) return _finish();
        if (byte == 0x1b) {
          _state = _State.payloadEscape;
        } else if (_payload.length >= _maxPayload) {
          _payload.clear();
          _state = _State.ignore;
        } else {
          _payload.addByte(byte);
        }
      case _State.payloadEscape:
        if (byte == 0x5c) return _finish();
        _payload.clear();
        _state = _State.escape;
        return _step(byte);
      case _State.ignore:
        if (byte == 0x07) {
          _state = _State.ground;
        } else if (byte == 0x1b) {
          _state = _State.ignoreEscape;
        }
      case _State.ignoreEscape:
        if (byte == 0x5c) {
          _state = _State.ground;
        } else {
          _state = _State.escape;
          return _step(byte);
        }
    }
    return null;
  }

  String _finish() {
    _state = _State.ground;
    final text = utf8.decode(_payload.takeBytes(), allowMalformed: true);
    return String.fromCharCodes(text.runes.take(maxTitleLength));
  }
}
```

Export `src/term/osc_title.dart`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd packages/shellx_agent && dart analyze && dart test test/term/osc_title_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent
git commit -m "feat(agent): OSC 0/2 window-title parser that survives chunk splits (spec §7.4)"
```

---

### Task 8: `DesktopSessionManager` (spec §7.1–§7.5, §7.8, §7.9)

**Files:**
- Create: `packages/shellx_agent/lib/src/term/desktop_session_manager.dart`
- Create: `packages/shellx_agent/test/support/fake_term_link.dart`, `packages/shellx_agent/test/support/desktop_rig.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/term/desktop_session_manager_test.dart`

**Interfaces:**
- Consumes: `SessionStream`, `OutboundMessage` (Task 2), codec + `TermLink` (Tasks 4, 6), `OscTitleParser` (Task 7)
- Produces:
  - `final class DesktopSessionSummary({required int id, required int index, required String app, required String title, required String shell, required DateTime createdAt, required String? attachedMobileId, required bool connected})`
  - `final class DesktopPhoneAttached(String mobileId, int sessionId)`
  - `final class DesktopSessionManager({required int Function() nextId, int maxSessions = 32, int bufferCapacity = 256 * 1024, int sendWindow = 256 * 1024, Duration reconnectGrace = const Duration(seconds: 30), Duration drainTimeout = const Duration(seconds: 30)})` with:
    - `Stream<OutboundMessage> get outbound` (sync broadcast), `Stream<void> get changes`, `Stream<DesktopPhoneAttached> get phoneAttached`
    - `List<DesktopSessionSummary> get sessions`, `List<SessionInfo> get sessionInfos`, `bool owns(int id)`
    - `bool canAdmit(TermInfo info)`, `void addLink(TermLink link)`
    - phone side: `void attach(String mobileId, int id, int cols, int rows, int lastSeq)`, `void input(String mobileId, int id, Uint8List data)`, `void resize(String mobileId, int id, int cols, int rows)`, `void ack(String mobileId, int id, int seq)`, `void detach(String mobileId, int id)`, `void mobileDisconnected(String mobileId)`
    - host side: `void disconnectPhone(int id)`, `void disconnectPhonesAttachedTo(String mobileId)`, `void disconnectAllPhones()`, `void clear()`
    - **no method that kills or closes a terminal**

- [ ] **Step 1: Test support**

`test/support/fake_term_link.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// A [TermLink] the test drives: [emit] plays `shellx-term`, [sent] records
/// what the agent sent, [drop] is the connection dying.
final class FakeTermLink implements TermLink {
  FakeTermLink(this.info);

  @override
  final TermInfo info;
  final _messages = StreamController<TermToAgent>();
  final sent = <AgentToTerm>[];
  bool closed = false;

  @override
  Stream<TermToAgent> get messages => _messages.stream;

  @override
  void send(AgentToTerm message) {
    if (!closed) sent.add(message);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(_messages.close());
  }

  void emit(TermToAgent message) {
    if (!closed) _messages.add(message);
  }

  void snapshot(String text) => emit(
    TermSnapshot(data: Uint8List.fromList(utf8.encode(text)), last: true),
  );

  void out(String text) =>
      emit(TermOut(data: Uint8List.fromList(utf8.encode(text))));

  void drop() => close();

  /// What the phone typed, decoded.
  String get typed => utf8.decode([
    for (final m in sent.whereType<AgentIn>()) ...m.data,
  ]);
}
```

`test/support/desktop_rig.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'fake_term_link.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';
const tablet = 'b0000000-0000-4000-8000-000000000003';

TermInfo windowInfo(int n, {String app = 'Terminal'}) => TermInfo(
  termId: Uint8List.fromList(List.filled(16, n)),
  app: app,
  shell: 'zsh',
  pid: 1000 + n,
  cols: 80,
  rows: 24,
  startedAt: 1759276800000 + n,
);

final class DesktopRig {
  DesktopRig({int maxSessions = 32, int bufferCapacity = 256 * 1024}) {
    var next = 100;
    manager = DesktopSessionManager(
      nextId: () => next++,
      maxSessions: maxSessions,
      bufferCapacity: bufferCapacity,
    );
    manager.outbound.listen(sent.add);
  }

  late final DesktopSessionManager manager;
  final sent = <OutboundMessage>[];

  List<AppMessage> to(String mobileId) => [
    for (final o in sent)
      if (o.mobileId == mobileId) o.message,
  ];

  String text(String mobileId, int id) => utf8.decode([
    for (final m in to(mobileId).whereType<OutputMessage>())
      if (m.id == id) ...m.data,
  ]);

  /// Connects window [n] and returns its link (snapshot not yet sent).
  /// Session ids are handed out from 100 in connection order.
  FakeTermLink connect(int n, {String app = 'Terminal'}) {
    final link = FakeTermLink(windowInfo(n, app: app));
    manager.addLink(link);
    return link;
  }

  void clear() => sent.clear();
}
```

- [ ] **Step 2: Write the failing tests**

`test/term/desktop_session_manager_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/desktop_rig.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('listing', () {
    test('a connected window is a desktop session with its own index', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        rig.connect(1, app: 'iTerm2');
        rig.connect(2);
        async.flushMicrotasks();
        final infos = rig.manager.sessionInfos;
        expect(infos.map((s) => s.id), [100, 101]);
        expect(infos.map((s) => s.index), [1, 2]);
        expect(infos.first.kind, SessionKind.desktop);
        expect(infos.first.app, 'iTerm2');
        expect(infos.first.shell, 'zsh');
        expect(infos.first.createdAt, 1759276800001);
        expect(rig.manager.owns(100), isTrue);
        expect(rig.manager.owns(7), isFalse);
      });
    });

    test('the limit admits reconnecting windows, not new ones', () {
      fakeAsync((async) {
        final rig = DesktopRig(maxSessions: 2);
        rig.connect(1);
        rig.connect(2);
        expect(rig.manager.canAdmit(windowInfo(3)), isFalse);
        expect(rig.manager.canAdmit(windowInfo(1)), isTrue);
        final over = rig.connect(3);
        expect(over.closed, isTrue);
        expect(rig.manager.sessions, hasLength(2));
      });
    });
  });

  group('snapshot and output', () {
    test('a snapshot in parts reaches the phone only once complete', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1);
        rig.manager.attach(phone, 100, 50, 20, 0);
        link.emit(TermSnapshot(data: _b('before '), last: false));
        async.flushMicrotasks();
        expect(rig.text(phone, 100), isEmpty);
        link.emit(TermSnapshot(data: _b('agent'), last: true));
        link.out(' live');
        async.flushMicrotasks();
        expect(rig.text(phone, 100), 'before agent live');
      });
    });

    test('a snapshot over the buffer size is a protocol error', () {
      fakeAsync((async) {
        final rig = DesktopRig(bufferCapacity: 8);
        final link = rig.connect(1);
        link.emit(TermSnapshot(data: _b('0123456789'), last: true));
        async.flushMicrotasks();
        expect(link.closed, isTrue);
        expect(rig.manager.owns(100), isTrue, reason: 'waits for reconnect');
      });
    });

    test('out before the snapshot is a protocol error', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..out('early');
        async.flushMicrotasks();
        expect(link.closed, isTrue);
      });
    });

    test('titles come from OSC in the snapshot and in output', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('\x1b]0;vim notes\x07');
        async.flushMicrotasks();
        expect(rig.manager.sessionInfos.single.title, 'vim notes');
        link.out('\x1b]2;npm run dev\x07');
        async.flushMicrotasks();
        expect(rig.manager.sessions.single.title, 'npm run dev');
      });
    });
  });

  group('driver and size (spec §5.5, §7.3)', () {
    test('attach makes the phone the driver: resize, driver, attached', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        expect(link.sent.single, isA<AgentResize>());
        expect((link.sent.single as AgentResize).cols, 50);
        final messages = rig.to(phone);
        expect(
          messages,
          containsAllInOrder([
            const SessionDriver(id: 100, by: DriverSide.phone),
            const SessionAttached(id: 100),
          ]),
        );
      });
    });

    test('local hands the size back to the desktop; the next phone key '
        'takes it again, resize before input', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        link.sent.clear();
        rig.clear();
        link.emit(const TermLocal());
        async.flushMicrotasks();
        expect(
          rig.to(phone).single,
          const SessionDriver(id: 100, by: DriverSide.desktop),
        );
        rig.manager.input(phone, 100, _b('ls\r'));
        expect(link.sent[0], isA<AgentResize>());
        expect(link.sent[1], isA<AgentIn>());
        expect(link.typed, 'ls\r');
        expect(
          rig.to(phone).last,
          const SessionDriver(id: 100, by: DriverSide.phone),
        );
      });
    });

    test('same-size input while the phone drives sends no resize', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        link.sent.clear();
        rig.manager.input(phone, 100, _b('a'));
        rig.manager.resize(phone, 100, 50, 20);
        expect(link.sent.whereType<AgentResize>(), isEmpty);
        rig.manager.resize(phone, 100, 60, 20);
        expect((link.sent.last as AgentResize).cols, 60);
      });
    });

    test('detach and a lost channel send local_size, nothing to the phone', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final a = rig.connect(1)..snapshot('');
        final b = rig.connect(2)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        rig.manager.attach(phone, 101, 50, 20, 0);
        rig.clear();
        rig.manager.detach(phone, 100);
        rig.manager.mobileDisconnected(phone);
        expect(a.sent.last, isA<AgentLocalSize>());
        expect(b.sent.last, isA<AgentLocalSize>());
        expect(rig.to(phone), isEmpty);
        expect(rig.manager.sessions.every((s) => s.attachedMobileId == null),
            isTrue);
        expect(a.closed || b.closed, isFalse);
      });
    });
  });

  group('reconnect (spec §6.5, §7.8)', () {
    test('within 30 s: same id, reset then the new snapshot, resize resent; '
        'input while away is dropped', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final first = rig.connect(1)..snapshot('old');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        first.drop();
        async.flushMicrotasks();
        rig.manager.input(phone, 100, _b('lost'));
        async.elapse(const Duration(seconds: 29));
        expect(rig.manager.owns(100), isTrue);
        rig.clear();

        final second = rig.connect(1)..snapshot('new screen');
        async.flushMicrotasks();
        expect(rig.manager.sessionInfos.single.id, 100);
        expect(rig.to(phone).first, const SessionReset(id: 100));
        expect(rig.text(phone, 100), 'new screen');
        expect(second.sent.whereType<AgentResize>().single.cols, 50);
        expect(second.typed, isEmpty);
        async.elapse(const Duration(seconds: 5));
        expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
      });
    });

    test('a second connection with the same term_id replaces a half-open one',
        () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final old = rig.connect(1)..snapshot('a');
        async.flushMicrotasks();
        final fresh = rig.connect(1)..snapshot('b');
        async.flushMicrotasks();
        expect(old.closed, isTrue);
        expect(fresh.closed, isFalse);
        expect(rig.manager.sessions, hasLength(1));
        old.out('ignored');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        expect(rig.text(phone, 100), 'b');
      });
    });

    test('after 30 s the session goes: terminal_gone to the attached phone',
        () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        link.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(rig.manager.owns(100), isFalse);
        expect(
          rig.to(phone).last,
          const SessionDetached(id: 100, reason: DetachReason.terminalGone),
        );
      });
    });
  });

  group('exit', () {
    test('exit drains to the phone, then session.exited; hidden at once', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        link
          ..out('bye')
          ..emit(const TermExit(code: 3));
        async.flushMicrotasks();
        expect(rig.text(phone, 100), 'bye');
        expect(rig.to(phone).last, const SessionExited(id: 100, exitCode: 3));
        expect(rig.manager.sessions, isEmpty);
      });
    });

    test('attach to an unknown or exited session is session_not_found', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        rig.manager.attach(phone, 999, 80, 24, 0);
        expect(
          (rig.to(phone).single as ErrorMessage).code,
          AppErrorCode.sessionNotFound,
        );
      });
    });
  });

  group('host side never closes the terminal (spec §7.2)', () {
    test('disconnectPhone: closed_by_host, local_size, terminal stays', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        rig.clear();
        rig.manager.disconnectPhone(100);
        expect(
          rig.to(phone).single,
          const SessionDetached(id: 100, reason: DetachReason.closedByHost),
        );
        expect(link.sent.last, isA<AgentLocalSize>());
        expect(link.closed, isFalse);
        expect(rig.manager.owns(100), isTrue);
      });
    });

    test('disconnectAllPhones and disconnectPhonesAttachedTo keep terminals',
        () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final a = rig.connect(1)..snapshot('');
        final b = rig.connect(2)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        rig.manager.attach(tablet, 101, 80, 24, 0);
        rig.manager.disconnectPhonesAttachedTo(phone);
        expect(rig.manager.sessions.firstWhere((s) => s.id == 101)
            .attachedMobileId, tablet);
        rig.manager.disconnectAllPhones();
        expect(rig.manager.sessions, hasLength(2));
        expect(a.closed || b.closed, isFalse);
      });
    });

    test('clear (sharing switched off) drops sessions and links only', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        rig.manager.clear();
        expect(rig.manager.sessions, isEmpty);
        expect(link.closed, isTrue, reason: 'ends sharing; window keeps running');
        expect(
          rig.to(phone).last,
          const SessionDetached(id: 100, reason: DetachReason.closedByHost),
        );
        async.elapse(const Duration(minutes: 1));
        expect(rig.to(phone).whereType<SessionDetached>(), hasLength(1));
      });
    });
  });

  test('phoneAttached fires once per new attach', () {
    fakeAsync((async) {
      final rig = DesktopRig();
      final events = <DesktopPhoneAttached>[];
      rig.manager.phoneAttached.listen(events.add);
      rig.connect(1).snapshot('');
      async.flushMicrotasks();
      rig.manager.attach(phone, 100, 80, 24, 0);
      rig.manager.attach(phone, 100, 80, 24, 0);
      async.flushMicrotasks();
      expect(events.map((e) => (e.mobileId, e.sessionId)), [(phone, 100)]);
    });
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/term/desktop_session_manager_test.dart`
Expected: compile error (`DesktopSessionManager` undefined).

- [ ] **Step 4: Implement**

`desktop_session_manager.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';
import '../session/session_stream.dart';
import 'osc_title.dart';
import 'term_link.dart';
import 'term_messages.dart';

/// Read-only view of a desktop terminal for the tray (P4).
final class DesktopSessionSummary {
  const DesktopSessionSummary({
    required this.id,
    required this.index,
    required this.app,
    required this.title,
    required this.shell,
    required this.createdAt,
    required this.attachedMobileId,
    required this.connected,
  });
  final int id, index;
  final String app, title, shell;
  final DateTime createdAt;
  final String? attachedMobileId;

  /// False while waiting (≤ 30 s) for `shellx-term` to reconnect.
  final bool connected;
}

/// A phone attached to a desktop terminal (for P4's desktop notification).
final class DesktopPhoneAttached {
  const DesktopPhoneAttached(this.mobileId, this.sessionId);
  final String mobileId;
  final int sessionId;
}

enum _Driver { desktop, phone }

const int _minDimension = 1;
const int _maxDimension = 1000;
int _clamp(int value) => value.clamp(_minDimension, _maxDimension);

final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.info,
    required this.stream,
  });

  final int id;
  final int index;
  TermInfo info;
  final SessionStream stream;

  TermLink? link;
  StreamSubscription<TermToAgent>? subscription;

  /// Collects a snapshot until `last: true`; null when none is arriving.
  BytesBuilder? snapshot;

  /// The current link's snapshot is complete: `out`, `local`, `exit` and
  /// phone input are accepted.
  bool live = false;

  Timer? graceTimer;
  Timer? drainTimer;
  final titles = OscTitleParser();
  String title = '';
  _Driver driver = _Driver.desktop;

  /// The attached phone's size; 0 before any phone attached.
  int cols = 0, rows = 0;

  /// `exit` received: hidden, not attachable, draining to the phone.
  bool closing = false;
  int exitCode = -1;

  String? get attachedMobileId => stream.attachedMobileId;
}

/// Every desktop terminal shared through `shellx-term` (spec §7.1). Each
/// authenticated [TermLink] becomes a `desktop` session; a window that
/// reconnects (same `term_id`) within [reconnectGrace] keeps its session.
///
/// This class can detach phones and drop links, but it has **no way to end
/// a terminal** (spec §7.2, T13): the window belongs to the user.
final class DesktopSessionManager {
  DesktopSessionManager({
    required int Function() nextId,
    int maxSessions = 32,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Duration reconnectGrace = const Duration(seconds: 30),
    Duration drainTimeout = const Duration(seconds: 30),
  }) : _nextId = nextId,
       _maxSessions = maxSessions,
       _bufferCapacity = bufferCapacity,
       _sendWindow = sendWindow,
       _grace = reconnectGrace,
       _drainTimeout = drainTimeout;

  final int Function() _nextId;
  final int _maxSessions;
  final int _bufferCapacity;
  final int _sendWindow;
  final Duration _grace;
  final Duration _drainTimeout;

  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _attached = StreamController<DesktopPhoneAttached>.broadcast();
  final _sessions = <int, _Session>{};
  final _byTerm = <String, _Session>{};

  /// Messages to deliver, in order. Synchronous, like `SessionManager`'s.
  Stream<OutboundMessage> get outbound => _outbound.stream;
  Stream<void> get changes => _changes.stream;
  Stream<DesktopPhoneAttached> get phoneAttached => _attached.stream;

  List<DesktopSessionSummary> get sessions => [
    for (final s in _sessions.values)
      if (!s.closing)
        DesktopSessionSummary(
          id: s.id,
          index: s.index,
          app: s.info.app,
          title: s.title,
          shell: s.info.shell,
          createdAt: DateTime.fromMillisecondsSinceEpoch(s.info.startedAt),
          attachedMobileId: s.attachedMobileId,
          connected: s.link != null,
        ),
  ];

  List<SessionInfo> get sessionInfos => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionInfo(
          id: s.id,
          index: s.index,
          shell: s.info.shell,
          createdAt: s.info.startedAt,
          attached: s.attachedMobileId != null,
          kind: SessionKind.desktop,
          app: s.info.app,
          title: s.title,
        ),
  ];

  bool owns(int id) => _sessions.containsKey(id);

  /// `TermServer`'s check at `auth` (spec §7.8 step 3): a window that
  /// already has a session (it is reconnecting) is always admitted.
  bool canAdmit(TermInfo info) =>
      _byTerm.containsKey(info.key) || _sessions.length < _maxSessions;

  void addLink(TermLink link) {
    var session = _byTerm[link.info.key];
    if (session == null) {
      if (_sessions.length >= _maxSessions) {
        link.close();
        return;
      }
      final id = _nextId();
      session = _Session(
        id: id,
        index: _lowestFreeIndex(),
        info: link.info,
        stream: SessionStream(
          id: id,
          capacity: _bufferCapacity,
          sendWindow: _sendWindow,
          send: _send,
        ),
      );
      _sessions[id] = session;
      _byTerm[link.info.key] = session;
    } else {
      _dropLink(session); // A half-open old connection loses (spec §7.8).
      session.graceTimer?.cancel();
      session.graceTimer = null;
      session.info = link.info;
    }
    final s = session;
    s.link = link;
    s.live = false;
    s.snapshot = BytesBuilder(copy: false);
    s.subscription = link.messages.listen(
      (message) => _onMessage(s, link, message),
      onDone: () => _linkLost(s, link),
    );
    _changes.add(null);
  }

  // ---- phone side -------------------------------------------------------

  void attach(String mobileId, int id, int cols, int rows, int lastSeq) {
    final s = _sessions[id];
    if (s == null || s.closing) {
      _notFound(mobileId, id);
      return;
    }
    final previous = s.stream.attach(mobileId, lastSeq);
    _drive(s, _clamp(cols), _clamp(rows));
    _send(mobileId, SessionAttached(id: id));
    if (previous != mobileId) {
      _changes.add(null);
      _attached.add(DesktopPhoneAttached(mobileId, id));
    }
  }

  /// Dropped while the terminal is reconnecting (spec §7.8: not queued).
  void input(String mobileId, int id, Uint8List data) {
    final s = _attachedTo(mobileId, id);
    if (s == null || !s.live) return;
    if (s.driver == _Driver.desktop) _drive(s, s.cols, s.rows);
    s.link!.send(AgentIn(data: data));
  }

  void resize(String mobileId, int id, int cols, int rows) {
    final s = _attachedTo(mobileId, id);
    if (s != null) _drive(s, _clamp(cols), _clamp(rows));
  }

  void ack(String mobileId, int id, int seq) {
    final s = _attachedTo(mobileId, id);
    if (s == null) return;
    s.stream.ack(seq);
    _pump(s);
  }

  /// `session.detach` (or `session.close`) from the phone: it leaves, the
  /// terminal stays. Never answered.
  void detach(String mobileId, int id) {
    final s = _attachedTo(mobileId, id);
    if (s == null) return;
    _phoneLeft(s);
    _changes.add(null);
  }

  void mobileDisconnected(String mobileId) {
    var changed = false;
    for (final s in _sessions.values.toList()) {
      if (s.attachedMobileId != mobileId) continue;
      _phoneLeft(s);
      changed = true;
    }
    if (changed) _changes.add(null);
  }

  // ---- host side --------------------------------------------------------

  /// Tray "Disconnect phone", or the phone's access going away: the phone
  /// gets `session.detached {closed_by_host}`; the terminal keeps running.
  void disconnectPhone(int id) {
    final s = _sessions[id];
    final mobileId = s?.attachedMobileId;
    if (s == null || mobileId == null) return;
    _send(
      mobileId,
      SessionDetached(id: id, reason: DetachReason.closedByHost),
    );
    _phoneLeft(s);
    _changes.add(null);
  }

  void disconnectPhonesAttachedTo(String mobileId) {
    for (final s in _sessions.values.toList()) {
      if (s.attachedMobileId == mobileId) disconnectPhone(s.id);
    }
  }

  void disconnectAllPhones() {
    for (final id in _sessions.keys.toList()) {
      disconnectPhone(id);
    }
  }

  /// Sharing switched off (`TerminalSharing.stop`): every session goes now,
  /// without the 30 s wait; attached phones get `closed_by_host`; links
  /// close. Windows keep running and keep retrying (spec §7.9).
  void clear() {
    for (final s in _sessions.values.toList()) {
      final mobileId = s.attachedMobileId;
      if (mobileId != null) {
        _send(
          mobileId,
          SessionDetached(id: s.id, reason: DetachReason.closedByHost),
        );
      }
      s.stream.attachedMobileId = null;
      _remove(s);
    }
  }

  // ---- link side --------------------------------------------------------

  void _onMessage(_Session s, TermLink link, TermToAgent message) {
    if (!identical(s.link, link)) return;
    switch (message) {
      case TermSnapshot(:final data, :final last):
        final builder = s.snapshot;
        if (builder == null ||
            builder.length + data.length > _bufferCapacity) {
          return _protocolError(s);
        }
        builder.add(data);
        if (!last) return;
        final bytes = builder.takeBytes();
        s.snapshot = null;
        s.live = true;
        s.stream.restartWith(bytes);
        s.titles.reset();
        final title = s.titles.feed(bytes);
        if (title != null) s.title = title;
        _pump(s);
        if (s.attachedMobileId != null && s.driver == _Driver.phone) {
          // shellx-term went back to its window size when the link dropped.
          link.send(AgentResize(cols: s.cols, rows: s.rows));
        }
        _changes.add(null);
      case TermOut(:final data):
        if (!s.live) return _protocolError(s);
        s.stream.append(data);
        final title = s.titles.feed(data);
        if (title != null && title != s.title) {
          s.title = title;
          _changes.add(null);
        }
        _pump(s);
      case TermLocal():
        if (!s.live) return _protocolError(s);
        s.driver = _Driver.desktop;
        final mobileId = s.attachedMobileId;
        if (mobileId != null) {
          _send(mobileId, SessionDriver(id: s.id, by: DriverSide.desktop));
        }
      case TermExit(:final code):
        if (!s.live) return _protocolError(s);
        _exited(s, code);
      case TermSize():
        break; // The PTY follows the driver; nothing to do (spec §5.5).
      case TermHello() || TermAuth():
        _protocolError(s);
    }
  }

  void _linkLost(_Session s, TermLink link) {
    if (!identical(s.link, link)) return;
    s.subscription = null;
    s.link = null;
    if (s.closing) return;
    _startGrace(s);
    _changes.add(null);
  }

  void _protocolError(_Session s) {
    _dropLink(s);
    _startGrace(s);
    _changes.add(null);
  }

  void _startGrace(_Session s) {
    s.live = false;
    s.snapshot = null;
    s.graceTimer?.cancel();
    s.graceTimer = Timer(_grace, () {
      if (!identical(_sessions[s.id], s)) return;
      final mobileId = s.attachedMobileId;
      _remove(s);
      if (mobileId != null) {
        _send(
          mobileId,
          SessionDetached(id: s.id, reason: DetachReason.terminalGone),
        );
      }
    });
  }

  void _exited(_Session s, int code) {
    s.closing = true;
    s.exitCode = code;
    if (identical(_byTerm[s.info.key], s)) _byTerm.remove(s.info.key);
    _dropLink(s);
    _pump(s); // may already finish (and remove) the session.
    if (!identical(_sessions[s.id], s)) return;
    if (s.attachedMobileId == null) {
      _finish(s);
      return;
    }
    s.drainTimer = Timer(_drainTimeout, () => _finish(s));
    _changes.add(null);
  }

  void _finish(_Session s) {
    if (!identical(_sessions[s.id], s)) return;
    final mobileId = s.attachedMobileId;
    _remove(s);
    if (mobileId != null) {
      _send(mobileId, SessionExited(id: s.id, exitCode: s.exitCode));
    }
  }

  void _remove(_Session s) {
    s.graceTimer?.cancel();
    s.drainTimer?.cancel();
    _dropLink(s);
    _sessions.remove(s.id);
    if (identical(_byTerm[s.info.key], s)) _byTerm.remove(s.info.key);
    _changes.add(null);
  }

  void _dropLink(_Session s) {
    unawaited(s.subscription?.cancel());
    s.subscription = null;
    s.link?.close();
    s.link = null;
  }

  // ---- helpers ----------------------------------------------------------

  /// The phone drives: tell `shellx-term` its size when it was not driving
  /// or the size changed (spec §7.3). While reconnecting, the size is kept
  /// and sent after the next snapshot.
  void _drive(_Session s, int cols, int rows) {
    final mobileId = s.attachedMobileId;
    if (mobileId == null) return;
    final changed = cols != s.cols || rows != s.rows;
    if (!changed && s.driver == _Driver.phone) return;
    s.cols = cols;
    s.rows = rows;
    s.driver = _Driver.phone;
    if (s.live) s.link!.send(AgentResize(cols: cols, rows: rows));
    _send(mobileId, SessionDriver(id: s.id, by: DriverSide.phone));
  }

  void _phoneLeft(_Session s) {
    s.stream.attachedMobileId = null;
    if (s.driver == _Driver.phone) {
      s.driver = _Driver.desktop;
      if (s.live) s.link!.send(const AgentLocalSize());
    }
    if (s.closing) _finish(s);
  }

  void _pump(_Session s) {
    if (s.attachedMobileId == null) return;
    s.stream.pump();
    if (s.closing && s.stream.drained) _finish(s);
  }

  _Session? _attachedTo(String mobileId, int id) {
    final s = _sessions[id];
    return s != null && s.attachedMobileId == mobileId ? s : null;
  }

  int _lowestFreeIndex() {
    final used = {for (final s in _sessions.values) s.index};
    var index = 1;
    while (used.contains(index)) {
      index++;
    }
    return index;
  }

  void _notFound(String mobileId, int id) => _send(
    mobileId,
    ErrorMessage(
      code: AppErrorCode.sessionNotFound,
      message: 'Session $id not found',
      id: id,
    ),
  );

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
```

Export `src/term/desktop_session_manager.dart`.

- [ ] **Step 5: Run to verify they pass (3×)**

Run: `cd packages/shellx_agent && dart analyze && for i in 1 2 3; do dart test test/term/desktop_session_manager_test.dart || break; done && dart test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent
git commit -m "feat(agent): DesktopSessionManager — desktop sessions over TermLink: snapshot, 30 s reconnect, driver/size, titles, exit; no way to end a terminal (spec §7, T13)"
```

---

### Task 9: `SessionRouter`; wire it into `AgentService` users

**Files:**
- Create: `packages/shellx_agent/lib/src/session/session_router.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Modify: `apps/desktop/lib/src/agent/agent_runtime.dart`
- Test: `packages/shellx_agent/test/session/session_router_test.dart`

**Interfaces:**
- Consumes: `SessionManager` (Task 3), `DesktopSessionManager` (Task 8), `AgentSessions` (Task 2)
- Produces: `final class SessionRouter({required SessionManager shells, required DesktopSessionManager desktop, required bool Function() desktopSharing}) implements AgentSessions` with `Stream<void> get changes`, `void closeSession(int id)`, `void closeAll()`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/desktop_rig.dart' show windowInfo;
import '../support/fake_pty.dart';
import '../support/fake_term_link.dart';
import '../support/session_rig.dart' show phone, tablet;

final class _Rig {
  _Rig() {
    var next = 10;
    int ids() => next++;
    shells = SessionManager(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      nextId: ids,
    );
    desktop = DesktopSessionManager(nextId: ids);
    router = SessionRouter(
      shells: shells,
      desktop: desktop,
      desktopSharing: () => sharing,
    );
    router.outbound.listen(sent.add);
  }

  final ptys = FakePtyFactory();
  late final SessionManager shells;
  late final DesktopSessionManager desktop;
  late final SessionRouter router;
  bool sharing = true;
  final sent = <OutboundMessage>[];

  List<AppMessage> to(String m) => [
    for (final o in sent)
      if (o.mobileId == m) o.message,
  ];

  FakeTermLink window(int n) {
    final link = FakeTermLink(windowInfo(n));
    desktop.addLink(link);
    link.snapshot('');
    return link;
  }
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('ids never collide between shell and desktop sessions', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      rig.window(1);
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      rig.window(2);
      async.flushMicrotasks();
      final ids = [
        ...rig.shells.sessionInfos.map((s) => s.id),
        ...rig.desktop.sessionInfos.map((s) => s.id),
      ];
      expect(ids.toSet(), hasLength(4));
    });
  });

  test('an old phone sees today\'s list; desktop: true adds desktop '
      'sessions and desktop_sharing', () {
    fakeAsync((async) {
      final rig = _Rig()..window(1);
      async.flushMicrotasks();
      rig.router.handle(phone, const SessionList());
      final old = rig.to(phone).single as SessionListResult;
      expect(old.sessions, isEmpty);
      expect(old.desktopSharing, isNull);
      expect(old.toMap().containsKey('desktop_sharing'), isFalse);

      rig.sent.clear();
      rig.sharing = false;
      rig.router.handle(phone, const SessionList(desktop: true));
      final fresh = rig.to(phone).single as SessionListResult;
      expect(fresh.sessions.single.kind, SessionKind.desktop);
      expect(fresh.desktopSharing, isFalse);
    });
  });

  test('a phone that never listed with desktop: true cannot attach a '
      'desktop session; once listed it can, also after its channel drops', () {
    fakeAsync((async) {
      final rig = _Rig();
      final link = rig.window(1);
      async.flushMicrotasks();
      final id = rig.desktop.sessionInfos.single.id;
      final attach = SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0);

      rig.router.handle(phone, attach);
      expect(
        (rig.to(phone).single as ErrorMessage).code,
        AppErrorCode.sessionNotFound,
      );
      expect(link.sent, isEmpty);

      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(phone, attach);
      expect(rig.to(phone).last, SessionAttached(id: id));

      rig.router.mobileDisconnected(phone);
      rig.sent.clear();
      rig.router.handle(phone, attach);
      expect(rig.to(phone).last, SessionAttached(id: id));
    });
  });

  test('revoking a phone drops its desktop flag', () {
    fakeAsync((async) {
      final rig = _Rig()..window(1);
      async.flushMicrotasks();
      final id = rig.desktop.sessionInfos.single.id;
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.closeSessionsAttachedTo(phone);
      rig.sent.clear();
      rig.router.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
      );
      expect(rig.to(phone).single, isA<ErrorMessage>());
    });
  });

  test('input, resize and ack reach the desktop session', () {
    fakeAsync((async) {
      final rig = _Rig();
      final link = rig.window(1);
      async.flushMicrotasks();
      final id = rig.desktop.sessionInfos.single.id;
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
      );
      rig.router.handle(phone, InputMessage(id: id, data: _b('ls\r')));
      rig.router.handle(phone, ResizeMessage(id: id, cols: 90, rows: 30));
      rig.router.handle(phone, AckMessage(id: id, seq: 0));
      expect(link.typed, 'ls\r');
      expect((link.sent.last as AgentResize).cols, 90);
    });
  });

  group('no path closes a desktop terminal (spec §7.2)', () {
    late _Rig rig;
    late FakeTermLink link;
    late int desktopId;
    late int shellId;

    void setUpWorld(FakeAsync async) {
      rig = _Rig();
      link = rig.window(1);
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      shellId = rig.shells.sessionInfos.single.id;
      desktopId = rig.desktop.sessionInfos.single.id;
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(
        phone,
        SessionAttach(id: desktopId, cols: 80, rows: 24, lastSeq: 0),
      );
      rig.sent.clear();
    }

    void expectTerminalAlive() {
      expect(link.closed, isFalse);
      expect(rig.desktop.owns(desktopId), isTrue);
    }

    test('session.close from the phone only detaches', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.handle(phone, SessionClose(id: desktopId));
        async.flushMicrotasks();
        expectTerminalAlive();
        expect(rig.desktop.sessions.single.attachedMobileId, isNull);
        expect(rig.to(phone), isEmpty);
      });
    });

    test('session.detach on a shell session is ignored', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.handle(phone, SessionDetach(id: shellId));
        expect(rig.ptys.ptys.single.killed, isFalse);
        expect(rig.to(phone), isEmpty);
      });
    });

    test('revoke kills shells, only disconnects desktop terminals', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.closeSessionsAttachedTo(phone);
        async.flushMicrotasks();
        expect(rig.ptys.ptys.single.killed, isTrue);
        expectTerminalAlive();
        expect(
          rig.to(phone),
          contains(
            SessionDetached(id: desktopId, reason: DetachReason.closedByHost),
          ),
        );
      });
    });

    test('closeSession on a desktop id disconnects the phone only', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.closeSession(desktopId);
        expectTerminalAlive();
        expect(rig.ptys.ptys.single.killed, isFalse);
      });
    });

    test('closeAll (quit, remote access off, logout) kills shells only', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.closeAll();
        async.flushMicrotasks();
        expect(rig.ptys.ptys.single.killed, isTrue);
        expectTerminalAlive();
      });
    });

    test('mobileDisconnected keeps the terminal', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.mobileDisconnected(phone);
        expectTerminalAlive();
        expect(rig.ptys.ptys.single.killed, isFalse);
      });
    });
  });

  test('changes fire for both kinds of session', () {
    fakeAsync((async) {
      final rig = _Rig();
      var count = 0;
      rig.router.changes.listen((_) => count++);
      rig.window(1);
      rig.router.handle(tablet, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      expect(count, greaterThanOrEqualTo(2));
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/shellx_agent && dart test test/session/session_router_test.dart`
Expected: compile error (`SessionRouter`).

- [ ] **Step 3: Implement**

`session_router.dart`:

```dart
import 'dart:async';

import 'package:shellx_core/shellx_core.dart';

import '../term/desktop_session_manager.dart';
import 'agent_sessions.dart';
import 'session_manager.dart';

/// Shell sessions and desktop terminals behind one [AgentSessions] (spec
/// §7.7). Messages go to the manager that owns their session id (both draw
/// ids from one allocator); `session.list` is answered here.
///
/// A phone may attach a desktop terminal only after it sent
/// `session.list {desktop: true}` at least once since the agent started:
/// an old app never gets messages its decoder rejects (spec §7.9). The flag
/// survives channel losses (tabs re-attach without listing) and is dropped
/// on revoke.
///
/// Every "close" from the host or the phone ends shell sessions as before,
/// but only disconnects phones from desktop terminals (spec §7.2).
final class SessionRouter implements AgentSessions {
  SessionRouter({
    required SessionManager shells,
    required DesktopSessionManager desktop,
    required bool Function() desktopSharing,
  }) : _shells = shells,
       _desktop = desktop,
       _desktopSharing = desktopSharing {
    shells.outbound.listen(_outbound.add);
    desktop.outbound.listen(_outbound.add);
    shells.changes.listen(_changes.add);
    desktop.changes.listen(_changes.add);
  }

  final SessionManager _shells;
  final DesktopSessionManager _desktop;
  final bool Function() _desktopSharing;
  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _desktopPhones = <String>{};

  @override
  Stream<OutboundMessage> get outbound => _outbound.stream;

  @override
  Stream<SessionOpenedEvent> get opened => _shells.opened;

  Stream<void> get changes => _changes.stream;

  @override
  Future<void> handle(String mobileId, AppMessage message) async {
    switch (message) {
      case SessionList(:final desktop):
        if (desktop) _desktopPhones.add(mobileId);
        _send(
          mobileId,
          SessionListResult(
            [..._shells.sessionInfos, if (desktop) ..._desktop.sessionInfos],
            desktopSharing: desktop ? _desktopSharing() : null,
          ),
        );
      case SessionAttach(:final id, :final cols, :final rows, :final lastSeq)
          when _desktop.owns(id):
        if (_desktopPhones.contains(mobileId)) {
          _desktop.attach(mobileId, id, cols, rows, lastSeq);
        } else {
          _send(
            mobileId,
            ErrorMessage(
              code: AppErrorCode.sessionNotFound,
              message: 'Session $id not found',
              id: id,
            ),
          );
        }
      case InputMessage(:final id, :final data) when _desktop.owns(id):
        _desktop.input(mobileId, id, data);
      case ResizeMessage(:final id, :final cols, :final rows)
          when _desktop.owns(id):
        _desktop.resize(mobileId, id, cols, rows);
      case AckMessage(:final id, :final seq) when _desktop.owns(id):
        _desktop.ack(mobileId, id, seq);
      case SessionClose(:final id) when _desktop.owns(id):
        _desktop.detach(mobileId, id);
      case SessionDetach(:final id):
        _desktop.detach(mobileId, id); // Unknown or shell id: ignored.
      default:
        await _shells.handle(mobileId, message);
    }
  }

  @override
  void mobileDisconnected(String mobileId) {
    _shells.mobileDisconnected(mobileId);
    _desktop.mobileDisconnected(mobileId);
  }

  @override
  void closeSessionsAttachedTo(String mobileId) {
    _desktopPhones.remove(mobileId);
    _shells.closeSessionsAttachedTo(mobileId);
    _desktop.disconnectPhonesAttachedTo(mobileId);
  }

  /// Tray: a shell session is closed; a desktop terminal only loses its
  /// phone.
  void closeSession(int id) {
    if (_desktop.owns(id)) {
      _desktop.disconnectPhone(id);
    } else {
      _shells.closeSession(id);
    }
  }

  /// Quit, "Allow remote access" off, logout: shells end, desktop terminals
  /// only lose their phones.
  void closeAll() {
    _shells.closeAll();
    _desktop.disconnectAllPhones();
  }

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
```

Export `src/session/session_router.dart`.

In `apps/desktop/lib/src/agent/agent_runtime.dart`:

```dart
    final ids = sessionIdAllocator();
    _sessions = SessionManager(
      ptyFactory: ptyFactory,
      shellResolver: shellResolver,
      homeDirectory: homeDirectory,
      baseEnvironment: baseEnvironment,
      nextId: ids,
    );
    _desktopSessions = DesktopSessionManager(nextId: ids);
    // P4 replaces `() => false` with the TerminalSharing switch.
    _router = SessionRouter(
      shells: _sessions,
      desktop: _desktopSessions,
      desktopSharing: () => false,
    );
```

pass `sessions: _router` to `AgentService`, add the fields `late final DesktopSessionManager _desktopSessions;` and `late final SessionRouter _router;`, and change `stop()` to `_router.closeAll();`, `closeSession(id)` to `_router.closeSession(id)`, `closeAllSessions()` to `_router.closeAll()`. `sessions` and `sessionChanges` keep returning the shell manager's (the tray shows desktop terminals in P4).

- [ ] **Step 4: Run every gate**

```bash
cd packages/shellx_agent && dart analyze && dart test
cd ../shellx_client && dart analyze && dart test
cd ../../apps/desktop && flutter analyze && flutter test
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent apps/desktop/lib/src/agent/agent_runtime.dart
git commit -m "feat(agent): SessionRouter — shared ids, merged session.list, desktop attach only for phones that listed with desktop: true, every close path spares desktop terminals (spec §7.2, §7.9)"
```

---

### Task 10: `shellx_client` — desktop sessions on the phone side (protocol only)

**Files:**
- Modify: `packages/shellx_client/lib/src/machine_client.dart`, `packages/shellx_client/lib/src/client_tab.dart`
- Modify: `apps/mobile/lib/features/terminal/presentation/controllers/terminal_tab_controller.dart` (one `case` so the exhaustive switch compiles)
- Create: `packages/shellx_client/test/support/fake_term_link.dart` (same content as the agent's, Task 8 Step 1 — the packages cannot share test files)
- Modify: `packages/shellx_client/test/support/harness.dart`
- Test: `packages/shellx_client/test/desktop_sessions_test.dart`

**Interfaces:**
- Consumes: Task 1 messages; `SessionRouter`, `DesktopSessionManager`, `sessionIdAllocator` (agent)
- Produces:
  - `MachineClient.listSessions({bool includeDesktop = false})`; `bool? get desktopSharing` (last `desktop_sharing` received)
  - `ClientTab({…, SessionKind kind = SessionKind.shellx, String app = '', String title = ''})` with getters `kind`, `app`, `title`
  - `final class TabDriver extends TabEvent { const TabDriver(this.by); final DriverSide by; }`
  - `MachineClient.closeTab(id)` on a desktop tab sends `session.detach` (never `session.close`, never queued)
  - Harness: `late DesktopSessionManager desktop;`, `late SessionRouter router;`, `bool desktopSharing = true;`, `FakeTermLink shareWindow(int n)`

- [ ] **Step 1: Harness support**

In `test/support/harness.dart`, inside `startAgent()` replace the `SessionManager` construction and the `sessions:` argument:

```dart
    ptys = FakePtyFactory();
    final ids = sessionIdAllocator(Random(1000 + _agentStarts++));
    sessions = SessionManager(
      ptyFactory: ptys,
      shellResolver: shellResolver,
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      nextId: ids,
    );
    desktop = DesktopSessionManager(nextId: ids);
    router = SessionRouter(
      shells: sessions,
      desktop: desktop,
      desktopSharing: () => desktopSharing,
    );
```

and `sessions: router,` in the `AgentService(...)` call. Add the fields and helper:

```dart
  late DesktopSessionManager desktop;
  late SessionRouter router;
  bool desktopSharing = true;

  /// A desktop terminal window [n] connecting to the agent, snapshot sent.
  FakeTermLink shareWindow(int n, {String snapshot = ''}) {
    final link = FakeTermLink(
      TermInfo(
        termId: Uint8List.fromList(List.filled(16, n)),
        app: 'Terminal',
        shell: 'zsh',
        pid: 1000 + n,
        cols: 80,
        rows: 24,
        startedAt: 1759276800000,
      ),
    );
    desktop.addLink(link);
    link.snapshot(snapshot);
    settle(async);
    return link;
  }
```

`restartAgent()` keeps calling `sessions.closeAll()` (shell sessions die with the agent); add `desktop.clear();` after it.

`sessionIdAllocator(Random(1000 + n))` yields the same first id as before (`SessionManager` used the same formula), so existing tests keep their ids. Run `dart test` now: everything existing must still pass.

- [ ] **Step 2: Write the failing tests**

`test/desktop_sessions_test.dart` (copy the `keys` setup and `settle`/`failsWith` imports from the top of `machine_client_test.dart`):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('listSessions() is unchanged; includeDesktop adds desktop sessions '
      'and desktopSharing', () {
    fakeAsync((async) {
      final h = Harness(async, keys)..shareWindow(1);
      final machine = h.phoneMachine;
      expect(h.run(machine.listSessions()), isEmpty);
      expect(machine.desktopSharing, isNull);
      final all = h.run(machine.listSessions(includeDesktop: true));
      expect(all.single.kind, SessionKind.desktop);
      expect(all.single.app, 'Terminal');
      expect(machine.desktopSharing, isTrue);
    });
  });

  test('attach a desktop terminal: earlier output, typing, driver events', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1, snapshot: 'before\r\n');
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      final tab = h.run(machine.attach(id, cols: 50, rows: 20));
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      settle(async);
      expect(tab.kind, SessionKind.desktop);
      expect(tab.app, 'Terminal');

      machine.input(id, _b('ls\r'));
      settle(async);
      expect(link.typed, 'ls\r');

      link.emit(const TermLocal());
      settle(async);
      expect(
        events.whereType<TabDriver>().map((e) => e.by),
        contains(DriverSide.desktop),
      );
    });
  });

  test('closeTab on a desktop tab detaches; the terminal stays', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1);
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      h.run(machine.attach(id, cols: 50, rows: 20));
      h.run(machine.closeTab(id));
      settle(async);
      expect(link.closed, isFalse);
      expect(link.sent.last, isA<AgentLocalSize>());
      expect(h.desktop.sessions.single.attachedMobileId, isNull);
    });
  });

  test('a desktop tab re-attaches after the phone reconnects, without '
      'listing again (Review Focus 1)', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1);
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      final tab = h.run(machine.attach(id, cols: 50, rows: 20));
      final text = StringBuffer();
      tab.events.listen((e) {
        if (e is TabOutput) text.write(e.text);
      });
      h.disconnectPhone();
      link.out('while away');
      settle(async);
      h.reconnectPhone();
      expect(tab.isAttached, isTrue);
      expect(text.toString(), contains('while away'));
      expect(h.desktop.sessions.single.attachedMobileId, phoneId);
    });
  });

  test('terminal_gone ends the tab; it is not re-attached', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final link = h.shareWindow(1);
      final machine = h.phoneMachine;
      final id = h.run(machine.listSessions(includeDesktop: true)).single.id;
      final tab = h.run(machine.attach(id, cols: 50, rows: 20));
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      link.drop();
      async.elapse(const Duration(seconds: 31));
      expect(
        events.whereType<TabDetached>().single.reason,
        DetachReason.terminalGone,
      );
      expect(tab.isAttached, isFalse);
    });
  });
}
```

(`phoneId`, `TestKeys`, `settle` come from the existing support files; use the same imports `machine_client_test.dart` uses. `harness.dart` needs `import 'dart:typed_data';` and `import 'fake_term_link.dart';` for `shareWindow`.)

- [ ] **Step 3: Run to verify failure**

Run: `cd packages/shellx_client && dart test test/desktop_sessions_test.dart`
Expected: compile errors (`includeDesktop`, `desktopSharing`, `kind`, `TabDriver`).

- [ ] **Step 4: Implement**

`client_tab.dart`:

```dart
/// Who sets the desktop terminal's size now (spec §9.2 banner).
final class TabDriver extends TabEvent {
  const TabDriver(this.by);
  final DriverSide by;
}
```

`ClientTab` constructor gains `this.kind = SessionKind.shellx, this.app = '', this.title = ''` with fields `final SessionKind kind; final String app; final String title;`, and:

```dart
  void handleDriver(DriverSide by) => _emit(TabDriver(by));
```

`machine_client.dart`:

1. Fields: `bool? _desktopSharing;`, `bool _listedDesktop = false;` and `bool? get desktopSharing => _desktopSharing;`.

2. `listSessions`:

```dart
  /// [includeDesktop] also asks for desktop terminals (spec §8); until the
  /// app shows them (P5) it stays false by default, so today's screens see
  /// today's list.
  Future<List<SessionInfo>> listSessions({bool includeDesktop = false}) async {
    await connect();
    if (includeDesktop) _listedDesktop = true;
    final pending = _PendingList();
    _pendingLists.add(pending);
    return _request(
      pending.completer,
      SessionList(desktop: includeDesktop),
      () => _pendingLists.remove(pending),
      abandon: () => pending.abandoned = true,
    );
  }
```

3. In `attach`, the fallback list: `(await listSessions(includeDesktop: _listedDesktop))`, and create the tab with `kind: info.kind, app: info.app, title: info.title`.

4. `_dispatch`:

```dart
      case SessionListResult(:final sessions, :final desktopSharing):
        _known = {for (final s in sessions) s.id: s};
        if (desktopSharing != null) _desktopSharing = desktopSharing;
        // … rest unchanged …
      case SessionDriver(:final id, :final by):
        _tabs[id]?.handleDriver(by);
```

5. `closeTab`:

```dart
  Future<void> closeTab(int id) async {
    final tab = _tabs.remove(id);
    if (tab == null) return;
    _attachedHere.remove(tab);
    final wasAttached = tab.isAttached;
    tab.dispose();
    if (!wasAttached) return;
    if (tab.kind == SessionKind.desktop) {
      // Leaving a desktop terminal never ends it; with no channel the agent
      // already detached this phone when the channel dropped.
      if (_send([SessionDetach(id: id)])) await _outbox;
      return;
    }
    // … shell path unchanged …
```

`terminal_tab_controller.dart` `_onEvent` switch — add:

```dart
      case TabDriver():
        break; // The "computer is using this terminal" banner comes in P5.
```

- [ ] **Step 5: Run every gate**

```bash
cd packages/shellx_client && dart analyze && dart test
cd ../../apps/mobile && flutter analyze && flutter test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_client apps/mobile/lib/features/terminal/presentation/controllers/terminal_tab_controller.dart
git commit -m "feat(client): desktop sessions — listSessions(includeDesktop), desktopSharing, tab kind/app/title, TabDriver, closeTab detaches desktop tabs"
```

---

### Task 11: `TerminalSharing` and the real `shellx-term` (no relay)

**Files:**
- Create: `packages/shellx_agent/lib/src/term/terminal_sharing.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Create: `term/examples/fake_window.rs`
- Create: `packages/shellx_e2e/test/support/term_window.dart`
- Test: `packages/shellx_agent/test/term/terminal_sharing_test.dart`, `packages/shellx_e2e/test/term_link_test.dart`

**Interfaces:**
- Consumes: `TermServer` (Task 6), `DesktopSessionManager` (Task 8)
- Produces:
  - `final class TerminalSharing({required String endpointPath, required DesktopSessionManager sessions, Duration handshakeTimeout = const Duration(seconds: 5)})` with `bool get enabled`, `Future<void> start()`, `Future<void> stop()` (clears the sessions, then stops the server)
  - `term/examples/fake_window.rs`: `fake_window <program> [args…]` — runs the program in an 80x24 PTY, stdin → PTY, PTY → stdout, exits with the program's code (Unix)
  - e2e support: `Future<TermBinaries> buildTermBinaries()` (`shellxTerm`, `fakeWindow` paths), `final class TermWindow` with `static Future<TermWindow> open(TermBinaries, {required String home})`, `void type(String)`, `String get text`, `Future<void> waitFor(String needle, {Duration timeout})`, `Future<int> get exitCode`, `void kill()`

- [ ] **Step 1: `TerminalSharing` test and code**

`test/term/terminal_sharing_test.dart`:

```dart
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_term.dart';

void main() {
  test('start/stop: enabled, endpoint, sessions cleared, port closed', () async {
    final home = await Directory.systemTemp.createTemp('sharing-');
    addTearDown(() => home.delete(recursive: true));
    final path = '${home.path}/term/endpoint';
    var next = 1;
    final sessions = DesktopSessionManager(nextId: () => next++);
    final sharing = TerminalSharing(endpointPath: path, sessions: sessions);
    expect(sharing.enabled, isFalse);
    await sharing.start();
    expect(sharing.enabled, isTrue);

    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    expect(await term.handshake(secret), isA<AgentReady>());
    await pumpEventQueue();
    expect(sessions.sessions, hasLength(1));

    await sharing.stop();
    expect(sharing.enabled, isFalse);
    expect(sessions.sessions, isEmpty);
    expect(File(path).existsSync(), isFalse);
    await term.closed.timeout(const Duration(seconds: 2));
  });
}
```

`terminal_sharing.dart`:

```dart
import 'desktop_session_manager.dart';
import 'term_server.dart';

/// The agent side of "Share terminals with phone" (spec §6.1, §7.9): the
/// loopback server feeding [DesktopSessionManager]. P4's switch calls
/// [start] and [stop]; [enabled] is `desktop_sharing` (spec §8).
final class TerminalSharing {
  TerminalSharing({
    required String endpointPath,
    required DesktopSessionManager sessions,
    Duration handshakeTimeout = const Duration(seconds: 5),
  }) : _sessions = sessions,
       _server = TermServer(
         endpointPath: endpointPath,
         admit: sessions.canAdmit,
         onLink: sessions.addLink,
         handshakeTimeout: handshakeTimeout,
       );

  final DesktopSessionManager _sessions;
  final TermServer _server;

  bool get enabled => _server.running;

  Future<void> start() => _server.start();

  /// Desktop sessions go at once (phones get `closed_by_host`); windows keep
  /// running and keep retrying until sharing is on again.
  Future<void> stop() async {
    _sessions.clear();
    await _server.stop();
  }
}
```

Export `src/term/terminal_sharing.dart`. Run `cd packages/shellx_agent && dart analyze && dart test`.

- [ ] **Step 2: `fake_window` example**

`term/examples/fake_window.rs`:

```rust
//! A terminal window for tests outside this crate (the Dart suites of plan
//! P3): runs `program args…` in a fresh 80x24 PTY, copies this process's
//! stdin into the PTY and the PTY's output to stdout, and exits with the
//! program's exit code. The environment is inherited.
//!
//!     cargo build --features test-hooks --bin shellx-term --example fake_window
//!     target/debug/examples/fake_window target/debug/shellx-term wrap -- /bin/sh

#[cfg(unix)]
fn main() {
    use portable_pty::{native_pty_system, CommandBuilder, PtySize};
    use std::io::{Read, Write};

    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((program, rest)) = args.split_first() else {
        eprintln!("usage: fake_window <program> [args…]");
        std::process::exit(2);
    };
    let pair = native_pty_system()
        .openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })
        .expect("openpty");
    let mut cmd = CommandBuilder::new(program);
    cmd.args(rest);
    cmd.cwd(std::env::temp_dir());
    let mut child = pair.slave.spawn_command(cmd).expect("spawn");
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().expect("reader");
    let mut writer = pair.master.take_writer().expect("writer");
    std::thread::spawn(move || {
        let mut stdin = std::io::stdin();
        let mut buf = [0u8; 4096];
        while let Ok(n) = stdin.read(&mut buf) {
            if n == 0 || writer.write_all(&buf[..n]).is_err() {
                break;
            }
        }
    });
    let output = std::thread::spawn(move || {
        let mut stdout = std::io::stdout();
        let mut buf = [0u8; 16384];
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 {
                break;
            }
            let _ = stdout.write_all(&buf[..n]);
            let _ = stdout.flush();
        }
    });
    let status = child.wait().expect("wait");
    drop(pair.master);
    let _ = output.join();
    std::process::exit(status.exit_code() as i32);
}

#[cfg(not(unix))]
fn main() {
    eprintln!("fake_window: Unix only");
    std::process::exit(2);
}
```

Run from `term/`: `cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks`. Then smoke it: `cargo build --features test-hooks --bin shellx-term --example fake_window && printf 'echo hi; exit 3\n' | HOME=$(mktemp -d) target/debug/examples/fake_window target/debug/shellx-term wrap -- /bin/sh; echo "code=$?"` → output contains `hi` and `code=3`.

- [ ] **Step 3: e2e support**

`packages/shellx_e2e/test/support/term_window.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// `term/` relative to this package.
final String termDir = Directory('../../term').absolute.path;

final class TermBinaries {
  const TermBinaries(this.shellxTerm, this.fakeWindow);
  final String shellxTerm;
  final String fakeWindow;
}

/// Builds `shellx-term` (with test hooks, so `SHELLX_TERM_TIMING=fast`
/// works) and the `fake_window` example. Fails loudly without cargo: these
/// tests are the proof of spec §11.4 and must not skip silently.
Future<TermBinaries> buildTermBinaries() async {
  final ProcessResult result;
  try {
    result = await Process.run('cargo', [
      'build',
      '--features',
      'test-hooks',
      '--bin',
      'shellx-term',
      '--example',
      'fake_window',
    ], workingDirectory: termDir);
  } on ProcessException {
    throw StateError(
      'cargo not found: install Rust (rustup) to run the shellx-term tests '
      '(spec §11.4)',
    );
  }
  if (result.exitCode != 0) {
    throw StateError('cargo build failed:\n${result.stderr}');
  }
  return TermBinaries(
    '$termDir/target/debug/shellx-term',
    '$termDir/target/debug/examples/fake_window',
  );
}

/// A terminal window running `shellx-term wrap -- /bin/sh` with [home] as
/// HOME (so its `endpoint` is the test agent's, never the real one).
final class TermWindow {
  TermWindow._(this._process) {
    _process.stdout.listen(_output.addAll);
    _process.stderr.drain<void>();
  }

  static Future<TermWindow> open(
    TermBinaries bins, {
    required String home,
  }) async => TermWindow._(
    await Process.start(
      bins.fakeWindow,
      [bins.shellxTerm, 'wrap', '--', '/bin/sh'],
      environment: {
        'HOME': home,
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'PS1': r'$ ',
        'ENV': '',
        'TERM': 'xterm-256color',
        'SHELLX_TERM_TIMING': 'fast',
      },
      includeParentEnvironment: false,
    ),
  );

  final Process _process;
  final _output = <int>[];

  /// Typing on the computer's keyboard.
  void type(String text) => _process.stdin.add(utf8.encode(text));

  String get text => utf8.decode(_output, allowMalformed: true);

  Future<void> waitFor(
    String needle, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!text.contains(needle)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('window never showed "$needle":\n$text');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<int> get exitCode => _process.exitCode;

  void kill() => _process.kill(ProcessSignal.sigkill);
}
```

- [ ] **Step 4: Write the real-binary tests**

`packages/shellx_e2e/test/term_link_test.dart`:

```dart
@TestOn('mac-os')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart' show waitUntil;
import 'support/term_window.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

void main() {
  late TermBinaries bins;
  setUpAll(() async => bins = await buildTermBinaries());

  late Directory home;
  late DesktopSessionManager desktop;
  late TerminalSharing sharing;
  late List<AppMessage> toPhone;
  late List<TermWindow> windows;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('term-link-');
    var next = 1;
    desktop = DesktopSessionManager(nextId: () => next++);
    toPhone = [];
    desktop.outbound.listen((o) => toPhone.add(o.message));
    sharing = TerminalSharing(
      endpointPath: termEndpointPath(
        environment: {'HOME': home.path},
        windows: false,
      ),
      sessions: desktop,
    );
    windows = [];
  });

  tearDown(() async {
    for (final w in windows) {
      w.kill();
    }
    await sharing.stop();
    await home.delete(recursive: true);
  });

  Future<TermWindow> openWindow() async {
    final w = await TermWindow.open(bins, home: home.path);
    windows.add(w);
    return w;
  }

  String phoneText(int id) => utf8.decode([
    for (final m in toPhone.whereType<OutputMessage>())
      if (m.id == id) ...m.data,
  ], allowMalformed: true);

  Future<int> sessionAppears() async {
    await waitUntil(
      () => desktop.sessions.isNotEmpty,
      timeout: const Duration(seconds: 15),
      reason: 'shellx-term never connected',
    );
    return desktop.sessions.single.id;
  }

  test('output from before the agent started, typing from the phone, the '
      'phone\'s size, the window taking the size back, exit code', () async {
    final window = await openWindow();
    window.type('echo before-agent\n');
    await window.waitFor('before-agent');

    await sharing.start();
    final id = await sessionAppears();
    desktop.attach(phone, id, 50, 20, 0);
    await waitUntil(() => phoneText(id).contains('before-agent'));
    expect(
      toPhone,
      contains(SessionDriver(id: id, by: DriverSide.phone)),
    );

    desktop.input(phone, id, Uint8List.fromList(utf8.encode('stty size\r')));
    await waitUntil(
      () => phoneText(id).contains('20 50'),
      reason: 'PTY did not take the phone size: ${phoneText(id)}',
    );

    window.type('echo from-desk\n');
    await waitUntil(
      () => toPhone.contains(SessionDriver(id: id, by: DriverSide.desktop)),
      reason: 'a window keystroke must hand the size back',
    );
    await waitUntil(() => phoneText(id).contains('from-desk'));

    desktop.input(phone, id, Uint8List.fromList(utf8.encode('exit 3\r')));
    await waitUntil(
      () => toPhone.contains(SessionExited(id: id, exitCode: 3)),
    );
    expect(await window.exitCode.timeout(const Duration(seconds: 5)), 3);
  });

  test('stopping and restarting the agent never closes the window; it '
      'comes back with its earlier output', () async {
    await sharing.start();
    final window = await openWindow();
    await sessionAppears();
    window.type('echo first-run\n');
    await window.waitFor('first-run');

    await sharing.stop();
    window.type('echo while-off\n');
    await window.waitFor('while-off');

    await sharing.start();
    final id = await sessionAppears();
    desktop.attach(phone, id, 80, 24, 0);
    await waitUntil(() => phoneText(id).contains('while-off'));
    expect(phoneText(id), contains('first-run'));

    window.type('exit\n');
    expect(await window.exitCode.timeout(const Duration(seconds: 5)), 0);
  });

  test('a phone that only leaves never ends the window', () async {
    await sharing.start();
    final window = await openWindow();
    final id = await sessionAppears();
    desktop.attach(phone, id, 80, 24, 0);
    desktop.detach(phone, id);
    desktop.disconnectAllPhones();
    window.type('echo still-here\n');
    await window.waitFor('still-here');
    expect(desktop.owns(id), isTrue);
  });
}
```

- [ ] **Step 5: Run (3×)**

```bash
cd packages/shellx_e2e && dart analyze && for i in 1 2 3; do dart test test/term_link_test.dart || break; done
```

Expected: 3 tests pass, three runs in a row. If `stty size` shows `24 80`, check that the `AgentResize` reached `shellx-term` (Task 8 `_drive` runs only when `live`); do not loosen the assertion.

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent term/examples/fake_window.rs packages/shellx_e2e/test/support/term_window.dart packages/shellx_e2e/test/term_link_test.dart
git commit -m "feat(agent): TerminalSharing; test(e2e): real shellx-term through the agent — earlier output, phone typing and size, window takes the size back, exit code, agent restart (spec §11.4)"
```

---

### Task 12: End-to-end over the relay: phone ↔ relay ↔ agent ↔ `shellx-term`

**Files:**
- Modify: `packages/shellx_e2e/test/support/e2e_world.dart`
- Test: `packages/shellx_e2e/test/desktop_terminal_e2e_test.dart`

**Interfaces:**
- Consumes: everything above; `TermWindow` (Task 11)
- Produces: `E2eWorld` gains `late final DesktopSessionManager desktop;`, `late final SessionRouter router;`, `late final TerminalSharing sharing;`, `late final Directory home;`

- [ ] **Step 1: Extend `E2eWorld`**

In `_build`, replace the `SessionManager` block:

```dart
    home = await Directory.systemTemp.createTemp('shellx-e2e-home-');
    final ids = sessionIdAllocator();
    sessions = SessionManager(
      ptyFactory: const ProcessPtyFactory(),
      shellResolver: const _PlainShell(),
      homeDirectory: Directory.systemTemp.path,
      baseEnvironment: Platform.environment,
      nextId: ids,
    );
    desktop = DesktopSessionManager(nextId: ids);
    sharing = TerminalSharing(
      endpointPath: termEndpointPath(
        environment: {'HOME': home.path},
        windows: false,
      ),
      sessions: desktop,
    );
    router = SessionRouter(
      shells: sessions,
      desktop: desktop,
      desktopSharing: () => sharing.enabled,
    );
    _sessionsCreated = true;
```

pass `sessions: router` to `AgentService`, and in `dispose()` replace `if (_sessionsCreated) sessions.closeAll();` with:

```dart
    if (_sessionsCreated) {
      router.closeAll();
      await _quietly(sharing.stop);
      await _quietly(() => home.delete(recursive: true));
    }
```

- [ ] **Step 2: Write the test**

`test/desktop_terminal_e2e_test.dart`:

```dart
@TestOn('mac-os')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';
import 'support/term_window.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

Uint8List keys(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late TermBinaries bins;
  setUpAll(() async {
    if (relayUrl != null) bins = await buildTermBinaries();
  });

  group(
    'desktop terminal end-to-end over a real relay (spec §11.4)',
    () {
      test('list → attach → earlier output → type → detach → re-attach → '
          'window exits', () async {
        final world = await E2eWorld.create(Uri.parse(relayUrl!));
        addTearDown(world.dispose);
        await world.pair(world.phone, registered: false);
        await world.sharing.start();

        final window = await TermWindow.open(bins, home: world.home.path);
        addTearDown(window.kill);
        window.type('echo before-phone\n');
        await window.waitFor('before-phone');
        await waitUntil(
          () => world.desktop.sessions.isNotEmpty,
          reason: 'shellx-term never reached the agent',
        );

        final machine = world.phone.service.machine(world.agentId);
        await machine.connect();
        final listed = await machine.listSessions(includeDesktop: true);
        expect(machine.desktopSharing, isTrue);
        final info = listed.singleWhere((s) => s.kind == SessionKind.desktop);

        var tab = await machine.attach(info.id, cols: 60, rows: 20);
        var output = TabText(tab);
        await waitUntil(
          () => output.text.contains('before-phone'),
          reason: 'no earlier output: ${jsonEncode(output.text)}',
        );
        machine.input(tab.id, keys('echo from-phone\r'));
        await window.waitFor('from-phone');

        await machine.closeTab(tab.id);
        await waitUntil(
          () => world.desktop.sessions.single.attachedMobileId == null,
        );
        window.type('echo while-detached\n');
        await window.waitFor('while-detached');

        tab = await machine.attach(info.id, cols: 60, rows: 20);
        output = TabText(tab);
        await waitUntil(() => output.text.contains('while-detached'));

        final ended = tab.events.firstWhere((e) => e is TabExited);
        window.type('exit 4\n');
        expect(((await ended) as TabExited).exitCode, 4);
        expect(await window.exitCode, 4);
      });
    },
    skip: relayUrl == null
        ? 'Set SHELLX_E2E_RELAY=http://127.0.0.1:8787 (npm run dev in relay/) '
              'to run'
        : null,
  );
}
```

- [ ] **Step 3: Run against the local relay**

In one terminal: `cd relay && npm run dev` (listens on `127.0.0.1:8787`, rate limits off). In another:

```bash
cd packages/shellx_e2e && dart analyze && \
  SHELLX_E2E_RELAY=http://127.0.0.1:8787 dart test
```

Expected: the existing 7 e2e tests, `term_link_test.dart` (3) and the new desktop test all pass. Run the new file 3× in a row. Stop the relay afterwards.

- [ ] **Step 4: Commit**

```bash
git add packages/shellx_e2e
git commit -m "test(e2e): desktop terminal over the relay — list, earlier output, typing, detach, re-attach, exit code (spec §11.4)"
```

- [ ] **Step 5: Hand the real-relay run to the user (T14) — do not run it**

Record in the ledger (Task 13) and tell the user this exact command; they run it themselves when they choose (it registers a throwaway `e2e-<random>@example.com` account on production and deletes it at the end; production has rate limits):

```bash
cd packages/shellx_e2e && \
  SHELLX_E2E_RELAY=https://relay.shellx.pro dart test test/desktop_terminal_e2e_test.dart
```

---

### Task 13: Windows workflow, ledger, handoff

**Files:**
- Modify: `.github/workflows/windows-check.yml`
- Modify: `docs/superpowers/ledgers/terminal-sharing.md`, `docs/superpowers/HANDOFF.md`, `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` (status line and §14 P3 row only)

**Interfaces:**
- Consumes: the whole branch

- [ ] **Step 1: Add the Dart job to `windows-check.yml`** (spec §12: P3 adds `dart test` for `shellx_agent` and `shellx_core`)

Append under `jobs:`:

```yaml
  dart:
    name: shellx_core + shellx_agent (${{ matrix.os }})
    strategy:
      fail-fast: false
      matrix:
        os: [windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    timeout-minutes: 30
    steps:
      - name: Keep LF line endings
        run: git config --global core.autocrlf false
      - uses: actions/checkout@v7
      # The workspace includes the Flutter apps, so resolving it needs the
      # Flutter SDK (pinned to the dev machine's version).
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.41.7
          channel: stable
      - name: Resolve the workspace
        run: flutter pub get
      - name: shellx_core
        working-directory: packages/shellx_core
        run: dart test
      - name: shellx_agent
        working-directory: packages/shellx_agent
        run: dart test
```

(The `term_endpoint`/`term_server`/`terminal_sharing` tests are `@TestOn('mac-os || linux')`; the codec, title, stream, router and desktop-manager tests run on Windows too.) Validate the YAML: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/windows-check.yml'))"`.

- [ ] **Step 2: Ledger section**

Add `## P3 — agent + giao thức (2026-10-05)` to `docs/superpowers/ledgers/terminal-sharing.md`, in the file's style (Vietnamese), with:
- branch and commit list (`git log --oneline main..HEAD`);
- test counts per package (from the final gate run) and the e2e result on the local relay;
- every controller ruling in the form `Ruling: <quyết định> — <lý do> — <cái giá nếu sai>`, including at least: T13; flag kept per phone (spec §7.9 fix); `listSessions(includeDesktop: false)` by default until P5; `TermSize` ignored; `driver(phone)` sent on every phone-driven resize; `fake_window` example instead of `script(1)`;
- "Việc chờ người dùng": the real-relay command from Task 12 Step 5; Windows CI run of the new `dart` job (push a `windows-check/p3` branch only when the user says so);
- "Ghi cho P4": `TerminalSharing` start/stop from the switch, `desktopSharing: () => sharing.enabled` in `agent_runtime.dart`, tray lists `DesktopSessionManager.sessions`, notifications from `phoneAttached` (10-minute limit per (phone, terminal)), endpoint path from `termEndpointPath(environment: Platform.environment, windows: Platform.isWindows)`;
- "Ghi cho P5": `listSessions(includeDesktop: true)`, `desktopSharing` null/false/true hints, `TabDriver` banner, `TabDetached(terminalGone)` card (today it shows the closed-by-host banner).

- [ ] **Step 3: HANDOFF and spec**

`HANDOFF.md` §9: replace the "P3" line under "Còn lại" with a "P3 xong" bullet (branch, test counts, what remains for the user), keep P4/P5. Spec header status: "P1, P2a, P3 xong; P2b code xong". §14 P3 row: add "(**xong**, ledger `terminal-sharing.md`)".

- [ ] **Step 4: Final full gate**

```bash
(cd packages/shellx_core && dart analyze && dart test) && \
(cd packages/shellx_agent && dart analyze && dart test) && \
(cd packages/shellx_client && dart analyze && dart test) && \
(cd packages/shellx_e2e && dart analyze && dart test test/term_link_test.dart) && \
(cd apps/desktop && flutter analyze && flutter test) && \
(cd apps/mobile && flutter analyze && flutter test) && \
(cd term && cargo fmt --check && cargo clippy --all-targets --features test-hooks -- -D warnings && cargo test --features test-hooks)
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/windows-check.yml docs/superpowers
git commit -m "ci: windows-check runs shellx_core and shellx_agent tests; docs: terminal sharing P3 ledger, handoff, spec status"
```
