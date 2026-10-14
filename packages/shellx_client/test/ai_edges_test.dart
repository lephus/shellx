import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

// The edges of the phone's AI client (V2-2 Task 6): what test/ai_test.dart
// (the end to end and compatibility tests) leaves open. A scripted desktop
// says exactly what a test needs and records what the phone sends; the real
// hub is used where its own behaviour is the point.

const _sid = 'x.1';

// ------------------------------------------------- a scripted desktop --

final class _Desktop implements AiEndpoint {
  _Desktop(this._clock);

  final Duration Function() _clock;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final received = <AiMessage>[];
  final receivedAt = <Duration>[];
  void Function(AiMessage message)? onMessage;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    received.add(message);
    receivedAt.add(_clock());
    onMessage?.call(message);
  }

  @override
  void phoneGone(String mobileId) {}

  @override
  void allPhonesGone() {}

  void say(AiMessage message) => _out.add(OutboundMessage(phoneId, message));

  List<T> got<T extends AiMessage>() => received.whereType<T>().toList();

  /// The [T]s received from the [n]th (1-based) [A] on.
  List<T> sinceNth<A extends AiMessage, T extends AiMessage>(int n) {
    final at = [
      for (var i = 0; i < received.length; i++)
        if (received[i] is A) i,
    ];
    return received.skip(at[n - 1]).whereType<T>().toList();
  }
}

/// The real hub, with a record of what passes between it and the phone.
final class _Tap implements AiEndpoint {
  _Tap(this.inner) {
    inner.outbound.listen((o) {
      toPhone.add(o.message);
      _out.add(o);
    });
  }

  final AiEndpoint inner;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final fromPhone = <AiMessage>[];
  final toPhone = <AppMessage>[];

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    fromPhone.add(message);
    inner.handle(mobileId, message);
  }

  @override
  void phoneGone(String mobileId) => inner.phoneGone(mobileId);

  @override
  void allPhonesGone() => inner.allPhonesGone();

  /// The `seq` of every mirror message the hub sent, in order.
  List<int> get seqsSent => [
    for (final m in toPhone)
      if (m is AiSnapshot) m.seq else if (m is AiUpdate) m.seq,
  ];
}

Map<String, Object?> _head([Map<String, Object?> extra = const {}]) => {
  'phase': 'ready',
  'agent': 'claude',
  'name': 'Claude',
  ...extra,
};

AiSnapshot _snapshot(
  int seq, {
  String sid = _sid,
  int n = 0,
  int g = 1,
  int from = 0,
  bool reset = true,
  Map<String, Object?>? head,
  List<Map<String, Object?>> items = const [],
}) => AiSnapshot(
  sid: sid,
  seq: seq,
  body: encodeBody({
    'v': 1,
    'n': n,
    'g': g,
    'from': from,
    'reset': reset,
    'more': from > 0,
    'head': head ?? _head(),
    'items': items,
  }),
);

AiUpdate _update(
  int seq, {
  int n = 0,
  List<Map<String, Object?>> items = const [],
}) => AiUpdate(
  sid: _sid,
  seq: seq,
  body: encodeBody({'v': 1, 'n': n, 'items': items}),
);

Map<String, Object?> _item(int i, {int rev = 1}) => {
  'i': i,
  'r': rev,
  'k': 'end',
  'turn': 1,
  'outcome': 'finished',
  'ms': 1000,
};

/// A card whose start is a time no clock can show: the mirror throws when it
/// builds it.
Map<String, Object?> _noClockItem(int i) => {
  'i': i,
  'r': 1,
  'k': 'tool',
  'turn': 1,
  'id': 'c$i',
  't0': 9007199254740991,
};

/// How a request ended, for the tests that must not wait for it.
final class _Outcome {
  _Outcome(Future<Object?> future) {
    future.then(values.add, onError: errors.add);
  }

  final values = <Object?>[];
  final errors = <Object>[];

  Object get error => errors.single;
}

Matcher _aiError(String code) =>
    isA<AiRequestException>().having((e) => e.code, 'code', code);

Matcher _connectionError(MachineConnectionFailure failure) =>
    isA<MachineConnectionException>().having(
      (e) => e.failure,
      'failure',
      failure,
    );

// ------------------------------------------------------ the real hub --

final class _Control implements AiControl {
  _Control(this.state);

  @override
  final AiSessionState state;
  final answers = <(int, String)>[];

  @override
  Future<bool> send(List<ContentBlock> prompt) async => true;
  @override
  void cancel() {}
  @override
  Future<void> forceStop() async {}

  @override
  void answerPermission(int id, String optionId) {
    answers.add((id, optionId));
    state.resolvePermission(id, PermissionSelected(optionId));
  }

  @override
  void answerAsk(int id, ElicitationResponse response) {}
}

/// A window with one AI session (`ep.-1`) whose runtime can be replaced.
final class _Window implements AiSessionSource {
  AiSessionState state = _fresh();
  late _Control runtime = _Control(state);
  final _changes = StreamController<void>.broadcast(sync: true);

  static AiSessionState _fresh() =>
      AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p')
        ..setPhase(AgentPhase.ready);

  /// Another runtime in the same tab (a folder was changed).
  void replace() {
    state = _fresh();
    runtime = _Control(state);
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
  @override
  List<AiSessionEntry> get sessions => [
    AiSessionEntry(
      paneId: -1,
      agentId: 'claude',
      agentName: 'Claude',
      title: 'Phiên AI mới',
      cwd: '/p',
      state: state,
    ),
  ];
  @override
  List<AiAgentChoice> get agents => const [
    AiAgentChoice(id: 'claude', name: 'Claude'),
  ];
  @override
  List<AiFolderChoice> get folders => const [];
  @override
  String? get defaultAgent => 'claude';
  @override
  AiControl? control(int paneId, {bool start = false}) => runtime;
  @override
  Future<int?> open(String agentId, String folderKey) async => null;
  @override
  bool seenOnDesktop(int paneId) => false;
  @override
  Duration? get doneThreshold => null;
}

final _t0 = DateTime.utc(2026, 10, 14, 9);

void _say(AiSessionState s, String text) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  _t0,
);

/// A finished tool call with about 10 KB of output (the phone gets 8 KB).
void _heavyTool(AiSessionState s, int i) {
  final text = [
    for (var l = 0; l < 130; l++) 'line $l of call $i ' * 4,
  ].join('\n');
  s.applyUpdate(
    SessionUpdate.fromJson({
      'sessionUpdate': 'tool_call',
      'toolCallId': 't$i',
      'title': 'Run $i',
      'kind': 'execute',
      'status': 'completed',
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': text},
        },
      ],
    }),
    _t0,
  );
}

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  group('what the machine learns from the list', () {
    test('a plain session.list after a desktop one leaves ai.supported', () {
      fakeAsync((async) {
        final h = Harness(async, keys, ai: AiPhoneHub(source: _Window()));
        final machine = h.phoneMachine;
        h.run(machine.listSessions(includeDesktop: true));
        expect(machine.ai.supported, isTrue);
        // An older screen's list, or the barrier a timed-out open sends: its
        // answer has no `ai` key because it never asked for one.
        h.run(machine.listSessions());
        expect(machine.ai.supported, isTrue);
      });
    });

    test('an ai.list.result is proof enough, and watching connects first', () {
      fakeAsync((async) {
        final hub = AiPhoneHub(source: _Window(), epoch: 'ep');
        final h = Harness(async, keys, ai: hub);
        final ai = h.phoneMachine.ai;
        expect(ai.wantsChannel, isFalse);
        expect(ai.supported, isNull);
        h.run(ai.watch());
        settle(async);
        expect(ai.wantsChannel, isTrue);
        expect(ai.supported, isTrue);
        expect(ai.listing!.sessions.single.sid, 'ep.-1');
      });
    });

    test('the listing follows every ai.list.result; an unreadable one is '
        'an empty list', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        final heard = <AiListing>[];
        ai.listings.listen(heard.add);
        h.run(ai.watch());
        settle(async);
        expect(d.got<AiList>(), hasLength(1));
        AiListResult listed(String title) => AiListResult(
          available: true,
          body: encodeBody(
            AiListing(
              sessions: [
                AiSessionInfo(
                  sid: _sid,
                  agentId: 'claude',
                  agentName: 'Claude',
                  title: title,
                  state: AiRemoteState.idle,
                ),
              ],
            ).toJson(),
          ),
        );
        d.say(listed('one'));
        d.say(listed('two'));
        settle(async);
        expect(heard.map((l) => l.sessions.single.title), ['one', 'two']);
        expect(ai.listing, same(heard.last));
        d.say(
          AiListResult(
            available: true,
            body: Uint8List.fromList('not json'.codeUnits),
          ),
        );
        settle(async);
        expect(heard, hasLength(3));
        expect(ai.listing!.sessions, isEmpty);
        expect(ai.listing!.available, isTrue);
        expect(ai.supported, isTrue);
      });
    });
  });

  group('watching the list', () {
    test('unwatch is the inverse of watch: nobody looks at the machine, so a '
        'lost channel is not brought back for the list', () {
      fakeAsync((async) {
        final tap = _Tap(AiPhoneHub(source: _Window(), epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        final machine = h.phoneMachine;
        final ai = machine.ai;
        ai.unwatch(); // nothing is watched yet: nothing happens
        expect(ai.wantsChannel, isFalse);
        h.run(ai.watch());
        settle(async);
        expect(ai.wantsChannel, isTrue);
        ai.unwatch();
        ai.unwatch(); // again: the same
        expect(ai.wantsChannel, isFalse);
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 5));
        // No relay or presence event makes a handshake for it.
        expect(machine.state, isA<MachineIdle>());
        expect(tap.fromPhone.whereType<AiList>(), hasLength(1));
      });
    });

    test('watch, unwatch, watch again: the list is asked for again and the '
        'channel is wanted again', () {
      fakeAsync((async) {
        final tap = _Tap(AiPhoneHub(source: _Window(), epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        final machine = h.phoneMachine;
        final ai = machine.ai;
        final heard = <AiListing>[];
        ai.listings.listen(heard.add);
        h.run(ai.watch());
        settle(async);
        ai.unwatch();
        h.run(ai.watch()); // the channel is there: asked at once
        settle(async);
        expect(ai.wantsChannel, isTrue);
        expect(tap.fromPhone.whereType<AiList>(), hasLength(2));
        expect(heard, hasLength(2));
        // Wanted for real: a lost channel comes back, and asks again.
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 1));
        expect(machine.state, isA<MachineReady>());
        expect(tap.fromPhone.whereType<AiList>(), hasLength(3));
      });
    });

    test('unwatch while the first channel is still being made: it comes, '
        'and the list is not asked for', () {
      fakeAsync((async) {
        final tap = _Tap(AiPhoneHub(source: _Window(), epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        final machine = h.phoneMachine;
        final watching = _Outcome(machine.ai.watch()); // connects first
        machine.ai.unwatch();
        settle(async);
        expect(watching.errors, isEmpty);
        expect(machine.state, isA<MachineReady>());
        expect(tap.fromPhone.whereType<AiList>(), isEmpty);
        expect(machine.ai.wantsChannel, isFalse);
      });
    });

    test('unwatch drops only the list: an open mirror still wants the '
        'channel', () {
      fakeAsync((async) {
        final tap = _Tap(AiPhoneHub(source: _Window(), epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        final ai = h.phoneMachine.ai;
        final link = ai.attach('ep.-1');
        h.run(ai.watch());
        settle(async);
        ai.unwatch();
        expect(ai.wantsChannel, isTrue);
        link.detach();
        expect(ai.wantsChannel, isFalse);
      });
    });
  });

  group('acks', () {
    test('at most one per 50 ms per session, with the last seq received', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        d.onMessage = (m) {
          if (m is AiAttach) d.say(_snapshot(1));
        };
        final link = h.phoneMachine.ai.attach(_sid);
        settle(async);
        for (var i = 0; i < 40; i++) {
          d.say(_update(2 + i, n: i));
          async.elapse(const Duration(milliseconds: 5));
        }
        settle(async, const Duration(milliseconds: 200));
        final at = [
          for (var i = 0; i < d.received.length; i++)
            if (d.received[i] is AiAck) d.receivedAt[i],
        ];
        final acks = d.got<AiAck>();
        expect(link.state, AiLinkState.live);
        expect(acks.last.seq, 41);
        expect(
          acks.map((a) => a.seq),
          orderedEquals(acks.map((a) => a.seq).toList()..sort()),
        );
        expect(acks.length, lessThanOrEqualTo(6));
        for (var i = 1; i < at.length; i++) {
          expect(
            at[i] - at[i - 1],
            greaterThanOrEqualTo(const Duration(milliseconds: 50)),
          );
        }
      });
    });

    test('a snapshot after a channel loss is applied and acked by the seq '
        'it carries, below the old channel\'s', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          if (attaches == 1) {
            d.say(_snapshot(40, n: 1, items: [_item(0)]));
          } else {
            // The desktop knows this phone again: its numbering starts over,
            // and the snapshot comes a little later.
            Timer(
              const Duration(milliseconds: 300),
              () => d.say(_snapshot(7, n: 2, items: [_item(0), _item(1)])),
            );
          }
        };
        final link = machine.ai.attach(_sid);
        settle(async);
        d.say(_update(41, n: 1));
        // It is there (a batch is 16 ms), and its ack waits for its 50 ms.
        settle(async, const Duration(milliseconds: 30));
        h.run(machine.dropChannel()); // a new channel, at once
        settle(async, const Duration(seconds: 1));
        expect(attaches, 2);
        expect(link.state, AiLinkState.live);
        expect(link.mirror.end, 2);
        // Only the new channel's seq goes out on the new channel: the old
        // channel's 41 would clear the window of a subscription it never saw.
        expect(d.sinceNth<AiAttach, AiAck>(2).map((a) => a.seq), [7]);
      });
    });

    test('a body skipped while the link awaits a snapshot is not acked: a '
        'stale one that crossed onto the new channel must not clear the '
        'window of the new subscription', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          if (attaches == 1) {
            d.say(_snapshot(40, n: 1, items: [_item(0)]));
          } else {
            // Through the background service a body of the old subscription
            // can cross `ai.gone` and reach the new channel first.
            d.say(_update(41, n: 2, items: [_item(1)]));
            Timer(
              const Duration(milliseconds: 300),
              () => d.say(_snapshot(1, n: 1, items: [_item(0)])),
            );
          }
        };
        final link = machine.ai.attach(_sid);
        settle(async);
        h.run(machine.dropChannel());
        settle(async, const Duration(seconds: 1));
        expect(attaches, 2);
        expect(link.state, AiLinkState.live);
        expect(link.mirror.end, 1); // the stale body was not applied
        expect(d.sinceNth<AiAttach, AiAck>(2).map((a) => a.seq), [1]);
      });
    });

    test('bodies skipped while the link awaits a snapshot send no ack at '
        'all, and the one that made the gap is acked once', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          if (attaches == 1) {
            d.say(_snapshot(40, n: 1, items: [_item(0)]));
          } else {
            Timer(
              const Duration(milliseconds: 400),
              () => d.say(_snapshot(57, n: 1, items: [_item(0)])),
            );
          }
        };
        final link = h.phoneMachine.ai.attach(_sid);
        settle(async);
        d.say(_update(41, n: 3, items: [_item(2)])); // a gap: 1 is missing
        // Old bodies keep coming, each after the ack of the one before has
        // gone out: none of them is applied, none is acked.
        for (var seq = 42; seq <= 44; seq++) {
          settle(async, const Duration(milliseconds: 80));
          d.say(_update(seq, n: 3 + seq, items: [_item(seq)]));
        }
        settle(async, const Duration(milliseconds: 100));
        expect(attaches, 2);
        expect(link.mirror.end, 1);
        expect(d.sinceNth<AiAttach, AiAck>(2).map((a) => a.seq), [41]);
        settle(async, const Duration(milliseconds: 400));
        expect(link.state, AiLinkState.live);
        expect(d.sinceNth<AiAttach, AiAck>(2).map((a) => a.seq), [41, 57]);
      });
    });

    test('a gap attaches again with what is held; the new snapshot may '
        'carry any seq, and the old bodies in between are not applied', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          if (attaches == 1) {
            d.say(_snapshot(40, n: 2, items: [_item(0), _item(1)]));
          } else {
            // The desktop made new ones above the old; this one is later.
            Timer(
              const Duration(milliseconds: 100),
              () => d.say(
                _snapshot(
                  57,
                  n: 5,
                  reset: false,
                  items: [_item(2), _item(3), _item(4)],
                ),
              ),
            );
          }
        };
        final link = h.phoneMachine.ai.attach(_sid);
        settle(async);
        expect(link.mirror.end, 2);
        d.say(_update(41, n: 5, items: [_item(4)])); // index 4: 2 and 3 missing
        settle(async, const Duration(milliseconds: 20));
        expect(attaches, 2);
        expect(decodeBody(d.got<AiAttach>()[1].body), {
          'g': 1,
          'from': 0,
          'revs': [1, 1],
        });
        // Made for what the phone held before: not applied, and not acked.
        d.say(_update(42, n: 6, items: [_item(5)]));
        settle(async, const Duration(milliseconds: 20));
        expect(link.mirror.end, 2);
        expect(attaches, 2);
        settle(async, const Duration(milliseconds: 200));
        expect(link.state, AiLinkState.live);
        expect(link.mirror.end, 5);
        expect(d.got<AiAck>().map((a) => a.seq), isNot(contains(42)));
        expect(d.got<AiAck>().last.seq, 57);
      });
    });
  });

  group('a body that cannot be read', () {
    test('is not fatal: the link attaches again, the channel and the '
        'terminals go on', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        final recorder = TabRecorder(
          h.run(machine.openSession(cols: 80, rows: 24)),
        );
        var attaches = 0;
        d.onMessage = (m) {
          if (m is AiAttach) {
            attaches++;
            d.say(_snapshot(attaches * 10, n: 1, items: [_item(0)]));
          }
        };
        final link = machine.ai.attach(_sid);
        settle(async);
        expect(link.state, AiLinkState.live);
        // The mirror throws on this one; terminal output follows it in the
        // same batch, and must still arrive.
        d.say(_update(11, n: 2, items: [_noClockItem(1)]));
        h.pty.emit('after the bad body\r\n');
        settle(async, const Duration(milliseconds: 300));
        expect(attaches, 2);
        expect(link.state, AiLinkState.live);
        expect(link.mirror.end, 1);
        expect(recorder.text, contains('after the bad body'));
        expect(machine.state, isA<MachineReady>());
      });
    });

    test('that is not JSON attaches again too', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          d.say(
            attaches == 1
                ? AiSnapshot(
                    sid: _sid,
                    seq: 1,
                    body: Uint8List.fromList('{"v":1,'.codeUnits),
                  )
                : _snapshot(2, n: 1, items: [_item(0)]),
          );
        };
        final link = h.phoneMachine.ai.attach(_sid);
        settle(async, const Duration(milliseconds: 300));
        expect(attaches, 2);
        expect(link.state, AiLinkState.live);
        expect(link.mirror.end, 1);
      });
    });

    test('that is cured by the new snapshot each time never ends the link', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        d.onMessage = (m) {
          if (m is AiAttach) {
            d.say(
              _snapshot(
                10 * d.got<AiAttach>().length,
                n: 1,
                reset: false,
                items: [_item(0)],
              ),
            );
          }
        };
        final link = h.phoneMachine.ai.attach(_sid);
        settle(async);
        for (var round = 0; round < 8; round++) {
          // A gap (index 99 on a mirror of one item), cured by the snapshot
          // its re-attach brings.
          d.say(_update(5 + round, n: 100, items: [_item(99)]));
          settle(async, const Duration(milliseconds: 200));
          expect(link.state, AiLinkState.live);
        }
        expect(d.got<AiAttach>(), hasLength(9));
        expect(link.closedReason, isNull);
      });
    });

    test('that keeps coming ends the link after a few tries, not a loop', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        d.onMessage = (m) {
          if (m is AiAttach) {
            d.say(
              _snapshot(
                d.got<AiAttach>().length,
                head: _head({
                  'turn': {'n': 1, 't0': 9007199254740991},
                }),
              ),
            );
          }
        };
        final link = machine.ai.attach(_sid);
        final states = <AiLinkState>[];
        link.changes.listen((_) => states.add(link.state));
        settle(async, const Duration(seconds: 5));
        expect(d.got<AiAttach>().length, lessThanOrEqualTo(4));
        expect(link.state, AiLinkState.closed);
        expect(link.closedReason, 'unreadable');
        expect(states.last, AiLinkState.closed);
        // The desktop is told to stop; and nothing more happens.
        expect(d.got<AiDetach>().single.sid, _sid);
        final attaches = d.got<AiAttach>().length;
        settle(async, const Duration(seconds: 60));
        expect(d.got<AiAttach>().length, attaches);
        expect(machine.ai.wantsChannel, isFalse);
        expect(machine.state, isA<MachineReady>());
      });
    });
  });

  group('requests', () {
    test('in flight when the computer closes the session: they fail', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(_snapshot(1));
        };
        final link = ai.attach(_sid);
        settle(async);
        final prompt = _Outcome(ai.prompt(_sid, 'hi'));
        final other = _Outcome(ai.cancel('y.2'));
        settle(async, const Duration(milliseconds: 20));
        expect(d.got<AiPrompt>(), hasLength(1));
        // The window quits: the session is closed, nothing answers the prompt.
        d.say(const AiClosed(sid: _sid, reason: 'desktop_closed'));
        settle(async, const Duration(milliseconds: 20));
        expect(prompt.error, _aiError('unavailable'));
        expect(other.errors, isEmpty); // another session's request goes on
        expect(link.state, AiLinkState.closed);
        expect(link.closedReason, 'desktop_closed');
        // A tab closed on the computer: the session is not there any more.
        final answer = _Outcome(ai.answerPermission('y.2', 3, 'allow'));
        settle(async, const Duration(milliseconds: 20));
        d.say(const AiClosed(sid: 'y.2', reason: 'gone'));
        settle(async, const Duration(milliseconds: 20));
        expect(answer.error, _aiError('not_found'));
        expect(other.error, _aiError('not_found'));
      });
    });

    test('in flight when no window serves AI any more: they all fail', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        h.run(ai.watch());
        final prompt = _Outcome(ai.prompt(_sid, 'hi'));
        final open = _Outcome(ai.open('claude', 'ws:a'));
        settle(async, const Duration(milliseconds: 20));
        expect(d.got<AiOpen>(), hasLength(1));
        d.say(
          AiListResult(
            available: false,
            body: encodeBody(const AiListing().toJson()),
          ),
        );
        settle(async, const Duration(milliseconds: 20));
        expect(prompt.error, _aiError('unavailable'));
        expect(open.error, _aiError('unavailable'));
        expect(ai.listing!.available, isFalse);
      });
    });

    test(
      'a newer reason closes the link and ends its requests all the same',
      () {
        fakeAsync((async) {
          final d = _Desktop(() => async.elapsed);
          final h = Harness(async, keys, ai: d);
          final ai = h.phoneMachine.ai;
          d.onMessage = (m) {
            if (m is AiAttach) d.say(_snapshot(1));
          };
          final link = ai.attach(_sid);
          settle(async);
          final prompt = _Outcome(ai.prompt(_sid, 'hi'));
          settle(async, const Duration(milliseconds: 20));
          d.say(const AiClosed(sid: _sid, reason: 'a_newer_word'));
          settle(async, const Duration(milliseconds: 20));
          expect(link.state, AiLinkState.closed);
          expect(link.closedReason, 'a_newer_word');
          expect(prompt.error, _aiError('unavailable'));
        });
      },
    );

    test('time out after the handshake timeout; a late result is ignored', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        h.run(h.phoneMachine.connect());
        final first = _Outcome(ai.prompt(_sid, 'one'));
        settle(async, const Duration(seconds: 9));
        expect(first.errors, isEmpty);
        settle(async, const Duration(seconds: 2));
        expect(first.error, _connectionError(MachineConnectionFailure.timeout));
        // Its result comes at last: nobody takes it for the next request's.
        final second = _Outcome(ai.prompt(_sid, 'two'));
        settle(async, const Duration(milliseconds: 20));
        final rids = d.got<AiPrompt>().map((p) => p.rid).toList();
        expect(rids.toSet(), hasLength(2));
        d.say(AiResult(rid: rids.first, ok: true));
        settle(async, const Duration(milliseconds: 20));
        expect(second.values, isEmpty);
        expect(second.errors, isEmpty);
        d.say(AiResult(rid: rids.last, ok: true));
        settle(async, const Duration(milliseconds: 20));
        expect(second.values, hasLength(1));
      });
    });

    test('lost with the channel: an answer fails and is never sent again', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(_snapshot(1));
        };
        ai.attach(_sid);
        settle(async);
        final answer = _Outcome(ai.answerPermission(_sid, 4, 'allow'));
        settle(async, const Duration(milliseconds: 20));
        expect(d.got<AiAnswer>(), hasLength(1));
        h.disconnectPhone();
        expect(
          answer.error,
          _connectionError(MachineConnectionFailure.agentOffline),
        );
        h.reconnectPhone();
        settle(async, const Duration(seconds: 2));
        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(d.got<AiAnswer>(), hasLength(1)); // not again
        expect(d.got<AiAttach>(), hasLength(2)); // the mirror came back
      });
    });

    test('the codes of a result are passed on as they are', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        h.run(h.phoneMachine.connect());
        d.onMessage = (m) {
          switch (m) {
            case AiCancel(:final rid):
              d.say(AiResult(rid: rid, ok: false, code: 'a_newer_word'));
            case AiForceStop(:final rid):
              d.say(AiResult(rid: rid, ok: false)); // no code at all
            case AiUnqueue(:final rid):
              d.say(AiResult(rid: rid, ok: true));
            case AiOpen(:final rid, :final agent):
              d.say(
                agent == 'claude'
                    ? AiResult(rid: rid, ok: true, sid: 'ep.9')
                    : AiResult(rid: rid, ok: true), // ok, but no session
              );
            default:
          }
        };
        expect(() => h.run(ai.cancel(_sid)), throwsA(_aiError('a_newer_word')));
        expect(() => h.run(ai.forceStop(_sid)), throwsA(_aiError('refused')));
        h.run(ai.unqueue(_sid, 2));
        expect(h.run(ai.open('claude', 'ws:a')), 'ep.9');
        expect(
          () => h.run(ai.open('codex', 'ws:a')),
          throwsA(_aiError('refused')),
        );
      });
    });

    test('a prompt over 32 KiB is refused on the phone, sending nothing', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        h.run(h.phoneMachine.connect());
        d.onMessage = (m) {
          if (m is AiPrompt) d.say(AiResult(rid: m.rid, ok: true));
        };
        expect(
          () => h.run(ai.prompt(_sid, 'x' * (kAiMaxPromptBytes + 1))),
          throwsA(_aiError('too_large')),
        );
        settle(async);
        expect(d.got<AiPrompt>(), isEmpty);
        h.run(ai.prompt(_sid, 'x' * kAiMaxPromptBytes)); // the limit itself
        expect(d.got<AiPrompt>(), hasLength(1));
      });
    });

    test('an answer over 48 KiB is refused on the phone: it would drop the '
        'channel', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        h.run(machine.connect());
        d.onMessage = (m) {
          if (m is AiAnswer) d.say(AiResult(rid: m.rid, ok: true));
        };
        // `{"t":"…"}` is 8 bytes more than the text.
        h.run(
          machine.ai.answerAsk(
            _sid,
            3,
            ElicitAccept({'t': 'x' * (kAiMaxBodyBytes - 8)}),
          ),
        );
        expect(d.got<AiAnswer>(), hasLength(1));
        for (final size in [kAiMaxBodyBytes - 7, 70000]) {
          expect(
            () => h.run(
              machine.ai.answerAsk(_sid, 3, ElicitAccept({'t': 'x' * size})),
            ),
            throwsA(_aiError('too_large')),
          );
        }
        settle(async, const Duration(seconds: 2));
        expect(d.got<AiAnswer>(), hasLength(1));
        expect(machine.state, isA<MachineReady>());
        // Declining needs no body, and still goes.
        d.onMessage = null;
        final decline = _Outcome(
          machine.ai.answerAsk(_sid, 3, const ElicitDecline()),
        );
        settle(async, const Duration(milliseconds: 20));
        expect(d.got<AiAnswer>().last.action, 'decline');
        expect(decline.errors, isEmpty);
      });
    });
  });

  group('mirrors', () {
    test('attaching with no channel connects first, and detach says so', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(_snapshot(1, n: 1, items: [_item(0)]));
        };
        final link = ai.attach(_sid);
        expect(link.state, AiLinkState.attaching);
        expect(ai.wantsChannel, isTrue);
        settle(async, const Duration(seconds: 1));
        expect(link.state, AiLinkState.live);
        expect(d.got<AiAttach>().single.body, isNull); // it held nothing
        expect(ai.attach(_sid), same(link)); // one link per open session
        final states = <AiLinkState>[];
        var done = false;
        link.changes.listen(
          (_) => states.add(link.state),
          onDone: () => done = true,
        );
        link.detach();
        settle(async);
        expect(d.got<AiDetach>().single.sid, _sid);
        expect(link.state, AiLinkState.closed);
        expect(link.closedReason, 'detached');
        expect(states, [AiLinkState.closed]);
        expect(done, isTrue);
        expect(ai.wantsChannel, isFalse);
        // Bodies for a link nobody holds are dropped, and not acked.
        final acks = d.got<AiAck>().length;
        d.say(_update(2, n: 1));
        settle(async, const Duration(milliseconds: 200));
        expect(d.got<AiAck>(), hasLength(acks));
        // A link that was closed is replaced by a new one.
        final again = ai.attach(_sid);
        expect(again, isNot(same(link)));
        settle(async);
        expect(again.state, AiLinkState.live);
      });
    });

    test(
      'a link the computer closed is not attached again on a new channel',
      () {
        fakeAsync((async) {
          final d = _Desktop(() => async.elapsed);
          final h = Harness(async, keys, ai: d);
          final machine = h.phoneMachine;
          d.onMessage = (m) {
            if (m is AiAttach) d.say(_snapshot(1));
          };
          final link = machine.ai.attach(_sid);
          // The snapshot is there, its ack waits for its 50 ms: and the
          // session is closed before that.
          settle(async, const Duration(milliseconds: 20));
          expect(link.state, AiLinkState.live);
          d.say(const AiClosed(sid: _sid, reason: 'gone'));
          settle(async);
          expect(link.state, AiLinkState.closed);
          expect(machine.ai.wantsChannel, isFalse);
          h.run(machine.dropChannel());
          settle(async, const Duration(seconds: 1));
          expect(d.got<AiAttach>(), hasLength(1));
          // Nothing is acked for a session that is closed.
          expect(d.got<AiAck>(), isEmpty);
        });
      },
    );

    test(
      'a listener that detaches while the channel is lost breaks nothing',
      () {
        fakeAsync((async) {
          final d = _Desktop(() => async.elapsed);
          final h = Harness(async, keys, ai: d);
          final machine = h.phoneMachine;
          d.onMessage = (m) {
            if (m is AiAttach) d.say(_snapshot(1, sid: m.sid));
          };
          final links = [machine.ai.attach('x.1'), machine.ai.attach('x.2')];
          settle(async);
          final seen = [<AiLinkState>[], <AiLinkState>[]];
          final done = [false, false];
          for (var i = 0; i < links.length; i++) {
            final link = links[i];
            link.changes.listen((_) {
              if (link.state == AiLinkState.attaching) link.detach();
            });
            // Another listener, after it: it hears the change the first one
            // made, and the end.
            link.changes.listen(
              (_) => seen[i].add(link.state),
              onDone: () => done[i] = true,
            );
          }
          h.run(machine.dropChannel()); // one loss, one pass over the links
          settle(async);
          expect(machine.state, isA<MachineIdle>());
          expect(links.map((l) => l.state), everyElement(AiLinkState.closed));
          expect(links.map((l) => l.closedReason), everyElement('detached'));
          expect(machine.ai.wantsChannel, isFalse);
          expect(seen.map((s) => s.last), everyElement(AiLinkState.closed));
          expect(done, [true, true]);
        });
      },
    );

    test('"load earlier" waits for the snapshot of a new channel', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          final snapshot = _snapshot(
            attaches,
            n: 7,
            from: 5,
            items: [_item(5), _item(6)],
          );
          if (attaches == 1) {
            d.say(snapshot);
          } else {
            Timer(const Duration(milliseconds: 300), () => d.say(snapshot));
          }
        };
        final link = machine.ai.attach(_sid);
        settle(async);
        expect(link.mirror.hasEarlier, isTrue);
        h.run(machine.dropChannel());
        settle(async, const Duration(milliseconds: 100));
        // The new channel is up, its snapshot is not.
        expect(link.state, AiLinkState.attaching);
        link.loadEarlier();
        settle(async, const Duration(milliseconds: 20));
        expect(d.got<AiEarlier>(), isEmpty);
        settle(async, const Duration(milliseconds: 400));
        expect(link.state, AiLinkState.live);
        link.loadEarlier();
        settle(async, const Duration(milliseconds: 20));
        expect(d.got<AiEarlier>().single.before, 5);
      });
    });

    test('a closed link takes no more bodies', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        d.onMessage = (m) {
          if (m is AiAttach) d.say(_snapshot(1, n: 1, items: [_item(0)]));
        };
        final link = h.phoneMachine.ai.attach(_sid);
        settle(async);
        final states = <AiLinkState>[];
        link.changes.listen((_) => states.add(link.state));
        d.say(const AiClosed(sid: _sid, reason: 'gone'));
        d.say(_update(2, n: 2, items: [_item(1)]));
        settle(async, const Duration(milliseconds: 200));
        expect(link.state, AiLinkState.closed);
        expect(link.mirror.end, 1); // what it held when it closed
        expect(states, [AiLinkState.closed]);
      });
    });

    test(
      'unpairing ends the links and the listing, and fails the requests',
      () {
        fakeAsync((async) {
          final d = _Desktop(() => async.elapsed);
          final h = Harness(async, keys, ai: d);
          final ai = h.phoneMachine.ai;
          d.onMessage = (m) {
            if (m is AiAttach) d.say(_snapshot(1));
          };
          final link = ai.attach(_sid);
          h.run(ai.watch());
          settle(async);
          var linkEnded = false;
          var listingsEnded = false;
          link.changes.listen((_) {}, onDone: () => linkEnded = true);
          ai.listings.listen((_) {}, onDone: () => listingsEnded = true);
          final prompt = _Outcome(ai.prompt(_sid, 'hi'));
          settle(async, const Duration(milliseconds: 20));
          h.run(h.phone.unpair(agentId));
          settle(async);
          expect(
            prompt.error,
            _connectionError(MachineConnectionFailure.agentOffline),
          );
          expect(linkEnded, isTrue);
          expect(listingsEnded, isTrue);
        });
      },
    );

    test('what is held is not sent when it would not fit a message', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final machine = h.phoneMachine;
        const total = 26000; // 2 bytes of `have` each: past 48 KiB
        const perBody = 1500;
        var attaches = 0;
        d.onMessage = (m) {
          if (m is! AiAttach) return;
          attaches++;
          if (attaches > 1) return;
          d.say(
            _snapshot(
              1,
              n: total,
              items: [
                for (var i = 0; i < perBody; i++) {'i': i, 'r': 1, 'k': 'x'},
              ],
            ),
          );
          for (
            var from = perBody, seq = 2;
            from < total;
            from += perBody, seq++
          ) {
            d.say(
              _update(
                seq,
                n: total,
                items: [
                  for (var i = from; i < from + perBody && i < total; i++)
                    {'i': i, 'r': 1, 'k': 'x'},
                ],
              ),
            );
          }
        };
        final link = machine.ai.attach(_sid);
        settle(async, const Duration(seconds: 5));
        expect(link.mirror.end, total);
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 3));
        expect(attaches, 2);
        // No `have` fits: the phone asks for the session from the start, and
        // the channel is still the one it was.
        final body = d.got<AiAttach>()[1].body;
        expect(body == null || body.length <= kAiMaxBodyBytes, isTrue);
        expect(machine.state, isA<MachineReady>());
      });
    });
  });

  group('with the real hub', () {
    test('the listing comes again on every new channel, with no tab open', () {
      fakeAsync((async) {
        final tap = _Tap(AiPhoneHub(source: _Window(), epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        final ai = h.phoneMachine.ai;
        final listings = <AiListing>[];
        ai.listings.listen(listings.add);
        h.run(ai.watch());
        settle(async);
        expect(listings, hasLength(1));
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 1));
        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(listings, hasLength(2));
        expect(tap.fromPhone.whereType<AiList>(), hasLength(2));
        expect(listings.last.sessions.single.sid, 'ep.-1');
      });
    });

    test('a text cut in pieces and a channel lost in between: the rest '
        'comes, whole', () {
      fakeAsync((async) {
        final window = _Window();
        final h = Harness(
          async,
          keys,
          ai: AiPhoneHub(source: window, epoch: 'ep'),
        );
        final ai = h.phoneMachine.ai;
        final text = List.generate(24000, (i) => 'w$i ').join(); // ~160 KB
        window.state.beginTurn(const [TextBlock('go')], _t0);
        _say(window.state, text);
        final link = ai.attach('ep.-1');
        // Until the first piece is there, and not the next one.
        for (var i = 0; i < 100 && link.mirror.items.length < 2; i++) {
          async.elapse(const Duration(milliseconds: 5));
        }
        expect(link.mirror.items, hasLength(2));
        final partial = link.mirror.items.last as MirrorText;
        expect(partial.text.length, lessThan(text.length));
        expect(partial.rev, -1); // claims nothing it does not hold
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 3));
        expect(link.state, AiLinkState.live);
        final whole = link.mirror.items.last as MirrorText;
        expect(whole.text, text);
        expect(whole.rev, isNot(-1));
      });
    });

    test('"load earlier" pages are bounded by the window: ask again until '
        'index 0', () {
      fakeAsync((async) {
        final window = _Window();
        final tap = _Tap(AiPhoneHub(source: window, epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        final link = h.phoneMachine.ai.attach('ep.-1');
        window.state.beginTurn(const [TextBlock('go')], _t0);
        for (var i = 0; i < 200; i++) {
          _heavyTool(window.state, i);
        }
        settle(async, const Duration(seconds: 3));
        final total = window.state.timeline.items.length;
        expect(link.mirror.end, total);
        expect(link.mirror.from, total - 60);
        expect(link.mirror.hasEarlier, isTrue);
        var taps = 0;
        while (link.mirror.hasEarlier && taps < 30) {
          final before = link.mirror.from;
          link.loadEarlier();
          taps++;
          settle(async, const Duration(seconds: 1));
          expect(link.mirror.from, lessThan(before)); // every tap brings some
        }
        expect(link.mirror.from, 0);
        expect(link.mirror.hasEarlier, isFalse);
        expect(taps, greaterThan(2)); // pages were cut, not 60 at a time
        expect(link.mirror.items, hasLength(total));
        expect(
          [for (final i in link.mirror.items) i.index],
          [for (var i = 0; i < total; i++) i],
        );
        expect(tap.fromPhone.whereType<AiEarlier>(), hasLength(taps));
        link.loadEarlier(); // nothing left: nothing asked
        settle(async);
        expect(tap.fromPhone.whereType<AiEarlier>(), hasLength(taps));
      });
    });

    test('a permission without options and a card too big are passed on '
        'untouched; nothing is ever answered by itself', () {
      fakeAsync((async) {
        final window = _Window();
        final h = Harness(
          async,
          keys,
          ai: AiPhoneHub(source: window, epoch: 'ep'),
        );
        final link = h.phoneMachine.ai.attach('ep.-1');
        final long = PermissionRequest.fromJson({
          'sessionId': 's',
          'toolCall': {'toolCallId': 'c9', 'title': 'Chạy một lệnh dài'},
          'options': [
            for (var i = 0; i < 400; i++)
              {
                'optionId': 'option-$i-${'x' * 150}',
                'name': 'Lựa chọn $i ${'y' * 100}',
                'kind': 'allow_once',
              },
          ],
        });
        final p = window.state.addPermission(long, _t0);
        window.state.applyUpdate(
          SessionUpdate.fromJson({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'z' * 100000,
            'title': 'Rất lớn',
            'kind': 'read',
          }),
          _t0,
        );
        settle(async, const Duration(seconds: 1));
        void check() {
          final permission = link.mirror.head!.permission!;
          expect(permission.id, p.id);
          expect(permission.title, 'Chạy một lệnh dài');
          expect(permission.options, isEmpty); // answered on the computer
          final stub = link.mirror.items.last as MirrorUnknown;
          expect(stub.kind, 'big');
          expect(link.state, AiLinkState.live);
        }

        check();
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 3));
        check();
        expect(window.runtime.answers, isEmpty);
        expect(window.state.currentPermission?.id, p.id); // still waiting
      });
    });

    test('a new runtime: its snapshot goes on from the old seq (above 1), '
        'the mirror starts over on it and acks that seq', () {
      fakeAsync((async) {
        final window = _Window();
        final tap = _Tap(AiPhoneHub(source: window, epoch: 'ep'));
        final h = Harness(async, keys, ai: tap);
        window.state.beginTurn(const [TextBlock('go')], _t0);
        _say(window.state, 'first runtime');
        final link = h.phoneMachine.ai.attach('ep.-1');
        settle(async, const Duration(milliseconds: 500));
        final generation = link.mirror.generation;
        expect((link.mirror.items.last as MirrorText).text, 'first runtime');
        window.replace();
        window.state.beginTurn(const [TextBlock('again')], _t0);
        _say(window.state, 'second runtime');
        settle(async, const Duration(seconds: 1));
        final snapshots = tap.toPhone.whereType<AiSnapshot>().toList();
        expect(snapshots, hasLength(2));
        expect(snapshots.last.seq, greaterThan(1));
        expect(snapshots.last.seq, greaterThan(snapshots.first.seq));
        expect(link.mirror.generation, isNot(generation));
        expect(link.mirror.items.map((i) => (i is MirrorText) ? i.text : ''), [
          'again',
          'second runtime',
        ]);
        expect(link.state, AiLinkState.live);
        expect(tap.fromPhone.whereType<AiAck>().last.seq, tap.seqsSent.last);
      });
    });
  });

  group('a page closed "unavailable": no window served AI then (M10)', () {
    const unavailable = AiClosed(sid: _sid, reason: 'unavailable');
    AiListResult listed({required bool available}) => AiListResult(
      available: available,
      body: encodeBody(
        AiListing(
          sessions: [
            if (available)
              const AiSessionInfo(
                sid: _sid,
                agentId: 'claude',
                agentName: 'Claude',
                title: 'T',
                state: AiRemoteState.idle,
              ),
          ],
        ).toJson(),
      ),
    );

    test('attaches once more when the list next says AI is available, and '
        'the page comes back', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        var serving = false;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(serving ? _snapshot(1) : unavailable);
        };
        final link = ai.attach(_sid);
        settle(async);
        expect(link.state, AiLinkState.closed);
        expect(link.closedReason, 'unavailable');
        // It asks for the list, to hear when a window serves AI again; the
        // channel stays wanted meanwhile.
        expect(d.got<AiList>(), hasLength(1));
        expect(ai.wantsChannel, isTrue);
        d.say(listed(available: false));
        settle(async);
        expect(d.got<AiAttach>(), hasLength(1));

        serving = true;
        final states = <AiLinkState>[];
        link.changes.listen((_) => states.add(link.state));
        d.say(listed(available: true));
        settle(async);
        expect(d.got<AiAttach>(), hasLength(2));
        expect(states, [AiLinkState.attaching, AiLinkState.live]);
        expect((link.state, link.closedReason), (AiLinkState.live, null));
        expect(ai.attach(_sid), same(link)); // the page's own link
      });
    });

    test('never a loop: another "unavailable" before the page came back '
        'closes it for good', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(unavailable);
        };
        final link = ai.attach(_sid);
        settle(async);
        d.say(listed(available: true));
        settle(async);
        expect(d.got<AiAttach>(), hasLength(2)); // the one retry
        expect(link.closedReason, 'unavailable');
        for (var i = 0; i < 3; i++) {
          d.say(listed(available: true));
          settle(async);
        }
        expect(d.got<AiAttach>(), hasLength(2));
        expect(d.got<AiList>(), hasLength(1));
        expect(ai.wantsChannel, isFalse);
      });
    });

    test('a page that came back, then lost it again, gets one more try', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        var serving = false;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(serving ? _snapshot(1) : unavailable);
        };
        final link = ai.attach(_sid);
        settle(async);
        serving = true;
        d.say(listed(available: true));
        settle(async);
        expect(link.state, AiLinkState.live);
        serving = false;
        d.say(unavailable); // the service restarted again, say
        settle(async);
        expect(link.closedReason, 'unavailable');
        serving = true;
        d.say(listed(available: true));
        settle(async);
        expect(link.state, AiLinkState.live);
        expect(d.got<AiAttach>(), hasLength(3));
      });
    });

    test('other reasons stay final, and a page that left is not brought '
        'back', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        d.onMessage = (m) {
          if (m is AiAttach) {
            d.say(
              m.sid == _sid
                  ? const AiClosed(sid: _sid, reason: 'gone')
                  : AiClosed(sid: m.sid, reason: 'unavailable'),
            );
          }
        };
        final gone = ai.attach(_sid);
        final left = ai.attach('x.2');
        settle(async);
        left.detach();
        d.say(listed(available: true));
        settle(async);
        expect(d.got<AiAttach>(), hasLength(2));
        expect(gone.closedReason, 'gone');
        expect(left.closedReason, 'unavailable');
        expect(ai.wantsChannel, isFalse);
      });
    });

    test('a channel lost while it waits: the next one asks for the list '
        'again', () {
      fakeAsync((async) {
        final d = _Desktop(() => async.elapsed);
        final h = Harness(async, keys, ai: d);
        final ai = h.phoneMachine.ai;
        var serving = false;
        d.onMessage = (m) {
          if (m is AiAttach) d.say(serving ? _snapshot(1) : unavailable);
        };
        final link = ai.attach(_sid);
        settle(async);
        h.disconnectPhone();
        h.reconnectPhone();
        settle(async, const Duration(seconds: 1));
        expect(d.got<AiList>(), hasLength(2));
        serving = true;
        d.say(listed(available: true));
        settle(async);
        expect(link.state, AiLinkState.live);
      });
    });

    test('the background service back before the window (a restart): the '
        'open page attaches again once the window serves', () {
      fakeAsync((async) {
        final forwarder = MuxAiForwarder();
        final h = Harness(async, keys, ai: forwarder);
        final ai = h.phoneMachine.ai;
        final link = ai.attach('ep.-1');
        settle(async);
        expect(link.closedReason, 'unavailable'); // no window serves yet

        // The window comes back and serves AI through the service.
        final hub = AiPhoneHub(source: _Window(), epoch: 'ep');
        final window = Object();
        hub.outbound.listen(
          (o) => forwarder.fromUi(
            window,
            MuxMessage(
              MuxType.aiOut,
              fields: {'m': o.mobileId, 'b': encodeCbor(o.message.toMap())},
            ),
          ),
        );
        forwarder.serve(window, (m) {
          final mobileId = m.get<String>('m');
          final bytes = m.get<Uint8List>('b');
          if (m.type != MuxType.aiIn || mobileId == null || bytes == null) {
            return;
          }
          final message = AppMessage.fromMap(
            decodeCbor(bytes) as Map<Object?, Object?>,
          );
          if (message is AiMessage) hub.handle(mobileId, message);
        });
        settle(async, const Duration(seconds: 1));
        expect(link.state, AiLinkState.live);
        expect(link.mirror.head!.agentName, 'Claude');
      });
    });
  });
}
