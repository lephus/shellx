import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

void say(AiSessionState s, String text) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  aiT0,
);

/// The `seq` of the last mirror message [who] was sent for [sid].
int lastSeq(HubRig rig, String who, String sid) => [
  for (final m in rig.to(who))
    if (m is AiSnapshot && m.sid == sid)
      m.seq
    else if (m is AiUpdate && m.sid == sid)
      m.seq,
].last;

/// About 600 KB of text at 6 updates a second and not one ack: the window to
/// the phone is full when this returns.
void fillWindow(FakeAsync async, AiSessionState s) {
  for (var i = 0; i < 40; i++) {
    say(s, '${'Dòng dài có dấu. ' * 800}\n');
    async.elapse(const Duration(milliseconds: 150));
  }
}

/// V2-2 D5, §7: a tab whose runtime changes (a folder chosen, an agent
/// switched off and on) keeps its phones, and `seq` never goes back.
void main() {
  group('a runtime that is forgotten and made again', () {
    test('the phone gets the new state, not a frozen copy of the old', () {
      fakeAsync((async) {
        final rig = HubRig();
        final a = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        say(a, 'from A');
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        async.elapse(const Duration(milliseconds: 150));
        rig.source.forget(-1); // the folder changed: the runtime is forgotten
        final b =
            rig.source.replace(-1) // … and another is made
              ..beginTurn(const [TextBlock('go')], aiT0);
        say(b, 'from B');
        async.elapse(const Duration(seconds: 1));
        final snapshots = rig.to(phone).whereType<AiSnapshot>().toList();
        expect(snapshots, hasLength(2)); // A's, then B's: nothing between
        expect(decodeBody(snapshots.last.body)!['reset'], isTrue);
        final mirror = rig.mirror(phone, 'ep.-1');
        expect((mirror.items.last as MirrorText).text, 'from B');
      });
    });

    test('a gap with no reason is not announced: another runtime comes', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final sent = rig.sent.length;
        rig.source.forget(-1);
        async.elapse(const Duration(seconds: 1));
        expect(rig.sent.length, sent);
      });
    });

    test('a tab that cannot run now says so at once; the old runtime is not '
        'mirrored; it comes back live', () {
      fakeAsync((async) {
        final rig = HubRig();
        final a = rig.source.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
        expect(
          rig.mirror(phone, 'ep.-1').head!.unavailable,
          AiRemoteState.agentOff,
        ); // told at once, not left frozen
        final sent = rig.sent.length;
        a.beginTurn(const [TextBlock('late')], aiT0); // the old one still moves
        async.elapse(const Duration(seconds: 1));
        expect(rig.sent.length, sent);

        final b = rig.source.replace(-1)
          ..beginTurn(const [TextBlock('back')], aiT0);
        say(b, 'welcome back');
        async.elapse(const Duration(seconds: 1));
        final mirror = rig.mirror(phone, 'ep.-1');
        expect(mirror.head!.unavailable, isNull);
        expect((mirror.items.last as MirrorText).text, 'welcome back');
      });
    });

    test('a session that could not run when it was opened goes live when '
        'it can', () {
      final rig = HubRig()
        ..source.add(-2, runs: false, unavailable: AiRemoteState.noFolder);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-2'));
      expect(
        rig.mirror(phone, 'ep.-2').head!.unavailable,
        AiRemoteState.noFolder,
      );
      rig.source.replace(-2); // a folder was chosen on the computer
      final mirror = rig.mirror(phone, 'ep.-2');
      expect(mirror.head!.unavailable, isNull);
      expect(rig.to(phone).whereType<AiSnapshot>(), hasLength(2));
    });

    test('a phone that left is not brought back by it', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
      rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
      final sent = rig.sent.length;
      rig.source.replace(-1);
      expect(rig.sent.length, sent);
    });

    test('a tab that cannot run and is then closed closes on the phone', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
      rig.source.remove(-1);
      expect(rig.last<AiClosed>(phone).reason, 'gone');
      final sent = rig.sent.length;
      rig.source.add(-1); // the same id again: nobody waits for it
      expect(rig.sent.length, sent);
    });
  });

  group('a phone told why a session cannot run, once the reason is gone and '
      'no runtime came (M3)', () {
    test('its agent switched on again: the attach runs again, the session '
        'goes live', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
        expect(
          rig.mirror(phone, 'ep.-1').head!.unavailable,
          AiRemoteState.agentOff,
        );
        rig.source.started.clear();
        rig.source
          ..lazy.add(-1) // made when asked for, as a pane does
          ..forget(-1); // switched on: no reason, and no runtime yet
        expect(rig.source.started, [-1]); // as the phone's attach does (D15)
        final mirror = rig.mirror(phone, 'ep.-1');
        expect(mirror.head!.unavailable, isNull);
        expect(mirror.head!.phase, 'ready');
        final s = rig.source.controls[-1]!.state
          ..beginTurn(const [TextBlock('go')], aiT0);
        say(s, 'live');
        async.elapse(const Duration(milliseconds: 150));
        final live = rig.mirror(phone, 'ep.-1');
        expect((live.items.last as MirrorText).text, 'live');
      });
    });

    test('a folder chosen for a tab it opened without one: the same', () {
      final rig = HubRig()
        ..source.add(-2, runs: false, unavailable: AiRemoteState.noFolder);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-2'));
      expect(
        rig.mirror(phone, 'ep.-2').head!.unavailable,
        AiRemoteState.noFolder,
      );
      rig.source
        ..lazy.add(-2)
        ..forget(-2);
      expect(rig.mirror(phone, 'ep.-2').head!.unavailable, isNull);
      expect(rig.source.started, [-2, -2]);
    });

    test('a window that cannot make the runtime: the attach runs again '
        'once, and its answer is what a plain attach gets', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
      final before = rig.to(phone).whereType<AiSnapshot>().length;
      rig.source.forget(-1); // no reason now, and no runtime will come
      final snapshots = rig.to(phone).whereType<AiSnapshot>().toList();
      expect(snapshots, hasLength(before + 1));
      // Still no composer: the session cannot run (as an attach to such a
      // tab is told).
      expect(rig.mirror(phone, 'ep.-1').head!.unavailable, isNotNull);
      final sent = rig.to(phone).length;
      rig.source.add(-5); // another change: the attach is not run again
      expect(rig.to(phone).length, sent);
    });

    test('a phone that left the session is not brought back', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
      rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
      rig.source.started.clear();
      final sent = rig.sent.length;
      rig.source
        ..lazy.add(-1)
        ..forget(-1);
      expect(rig.sent.length, sent);
      expect(rig.source.started, isEmpty);
    });

    test('a reason that changes is told', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.source.forget(-1, unavailable: AiRemoteState.agentOff);
      rig.source.forget(-1, unavailable: AiRemoteState.noFolder);
      expect(
        rig.mirror(phone, 'ep.-1').head!.unavailable,
        AiRemoteState.noFolder,
      );
    });
  });

  group('seq only goes up for a phone and a session', () {
    test('a new runtime goes on from the old one, and the late ack of the '
        'old one clears nothing of the new one', () {
      fakeAsync((async) {
        final rig = HubRig();
        final a = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        for (var i = 0; i < 60; i++) {
          say(a, 'tick $i ');
          async.elapse(const Duration(milliseconds: 150));
        }
        final old = lastSeq(rig, phone, 'ep.-1');
        expect(old, greaterThan(40));

        final b = rig.source.replace(-1)
          ..beginTurn(const [TextBlock('go')], aiT0);
        expect(rig.last<AiSnapshot>(phone).seq, old + 1);

        fillWindow(async, b); // the phone has acked nothing of the new one
        final stuck = rig.to(phone).length;
        rig.hub.handle(phone, AiAck(sid: 'ep.-1', seq: old)); // late
        say(b, 'more');
        async.elapse(const Duration(seconds: 1));
        expect(rig.to(phone).length, stuck); // the window is still full
      });
    });

    test('leaving and coming back goes on too', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        say(s, 'one');
        async.elapse(const Duration(milliseconds: 150));
        final before = lastSeq(rig, phone, 'ep.-1');
        rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        expect(rig.last<AiSnapshot>(phone).seq, before + 1);
      });
    });

    test('the snapshot of a session that cannot run goes on too', () {
      final rig = HubRig()
        ..source.add(-2, runs: false, unavailable: AiRemoteState.agentOff);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-2'));
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-2'));
      expect(rig.to(phone).whereType<AiSnapshot>().map((m) => m.seq), [1, 2]);
      rig.source.replace(-2); // it can run now: its live snapshot goes on
      expect(rig.last<AiSnapshot>(phone).seq, 3);
    });

    test('a session is its own count: another one starts at 1', () {
      final rig = HubRig()
        ..source.add(-1)
        ..source.add(-2);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-2'));
      expect(rig.to(phone).whereType<AiSnapshot>().map((m) => m.seq), [1, 1]);
    });
  });

  group('a tab that closes leaves nothing behind', () {
    test('its flush timer goes with it', () {
      fakeAsync((async) {
        final rig = HubRig();
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        say(s, 'x'); // a flush is waiting
        expect(async.nonPeriodicTimerCount, 1);
        rig.source.remove(-1);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('nor does its flush clock: an id used again is flushed at once', () {
      fakeAsync((async) {
        final rig = HubRig();
        final first = rig.source.add(-1)
          ..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        say(first, 'x');
        async.elapse(Duration.zero); // flushed now: the clock starts
        rig.source.remove(-1);
        final second = rig.source.add(-1)
          ..beginTurn(const [TextBlock('go')], aiT0);
        rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
        final sent = rig.to(phone).length;
        say(second, 'y');
        async.elapse(Duration.zero); // not 100 ms later
        expect(rig.to(phone).length, greaterThan(sent));
      });
    });

    test('nor its count of seq, even for a phone that had left it', () {
      final rig = HubRig()..source.add(-1);
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      rig.hub.handle(phone, const AiDetach(sid: 'ep.-1'));
      rig.source.remove(-1);
      rig.source.add(-1); // another session under the same id
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      expect(rig.to(phone).whereType<AiSnapshot>().map((m) => m.seq), [1, 1]);
    });
  });
}
