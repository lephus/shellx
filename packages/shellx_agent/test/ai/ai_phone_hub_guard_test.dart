import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

PermissionRequest perm(String toolCallId) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': toolCallId, 'title': 'Sửa src/main.ts'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

AiListing listing(AiListResult r) =>
    AiListing.fromJson(decodeBody(r.body)!, available: r.available);

/// V2-2 §6: the window's code (the adapter over its tabs and runtimes, the
/// push sender) may fail; the hub runs inside the runtime's own loops, so a
/// failure must never travel back into them, nor leave a phone unanswered,
/// nor become an uncaught error in the window's zone.
void main() {
  group('the window\'s code fails, the hub does not', () {
    test('a push that cannot be sent does not cut the state\'s other '
        'listeners short, nor repeat itself', () {
      var attempts = 0;
      final rig = HubRig(
        sink: (_) {
          attempts++;
          throw StateError('push failed');
        },
      );
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      var others = 0;
      s.addListener(() => others++); // after the hub's own
      final p = s.addPermission(perm('c1'), aiT0);
      expect((others, attempts), (1, 1));
      s.resolvePermission(p.id, const PermissionSelected('allow'));
      s.addPermission(perm('c2'), aiT0); // within 30 s: the limit still counts
      expect((others, attempts), (3, 1));
      s.endTurn(
        outcome: TurnOutcome.finished,
        at: aiT0.add(const Duration(minutes: 4)),
      );
      s.touch(); // the long turn is not pushed twice
      expect((others, attempts), (5, 2));
    });

    test('a window that cannot say whether the pane is seen still pushes', () {
      final pushes = <AiPush>[];
      final rig = HubRig(pushes: pushes);
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      rig.source.failing.add('seen');
      s.addPermission(perm('c1'), aiT0);
      expect(pushes, hasLength(1));
    });

    test(
      'a window that cannot give the long-turn threshold pushes no done',
      () {
        final pushes = <AiPush>[];
        final rig = HubRig(pushes: pushes);
        final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
        var others = 0;
        s.addListener(() => others++);
        rig.source.failing.add('threshold');
        s.endTurn(
          outcome: TurnOutcome.finished,
          at: aiT0.add(const Duration(minutes: 4)),
        );
        expect(pushes, isEmpty);
        expect(others, 1);
      },
    );

    test('a window that fails while the hub looks at its tabs is looked at '
        'again at the next change', () async {
      final rig = HubRig()..source.add(-1);
      rig.source.failing.add('sessions');
      rig.source.add(-2); // the change: the hub looks, the window fails
      await Future<void>.delayed(Duration.zero); // nothing uncaught
      rig.source.failing.clear();
      rig.source.add(-3);
      rig.hub.handle(phone, const AiList());
      expect(
        listing(rig.last<AiListResult>(phone)).sessions.map((s) => s.sid),
        ['ep.-1', 'ep.-2', 'ep.-3'],
      );
    });

    test('a request to a window that fails is refused, once, and nothing '
        'escapes', () async {
      final rig = HubRig();
      rig.source.add(-1).beginTurn(const [TextBlock('go')], aiT0);
      rig.source.failing.add('control');
      rig.hub.handle(phone, const AiPrompt(sid: 'ep.-1', rid: 1, text: 'hi'));
      rig.hub.handle(phone, const AiCancel(sid: 'ep.-1', rid: 2));
      rig.hub.handle(
        phone,
        const AiAnswer(sid: 'ep.-1', rid: 3, permission: 0, option: 'allow'),
      );
      await Future<void>.delayed(Duration.zero);
      final codes = {
        for (final r in rig.to(phone).whereType<AiResult>()) r.rid: r.code,
      };
      expect(codes, {1: 'refused', 2: 'refused', 3: 'refused'});
    });

    test('an attach to a window that fails is closed, not left unanswered', () {
      final rig = HubRig()..source.add(-1);
      rig.source.failing.add('control');
      rig.hub.handle(phone, const AiAttach(sid: 'ep.-1'));
      expect(rig.to(phone).map((m) => m.type), ['ai.closed']);
    });

    test('a listing the window fails keeps the last one; the next change '
        'makes a new one', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        rig.hub.handle(phone, const AiList());
        rig.source.failing.add('folders');
        rig.source.add(-2); // the list is made again, and the window fails
        async.elapse(const Duration(seconds: 1)); // nothing uncaught
        expect(rig.to(phone).whereType<AiListResult>(), hasLength(1));
        rig.source.failing.clear();
        rig.source.add(-3);
        async.elapse(const Duration(seconds: 1));
        expect(listing(rig.last<AiListResult>(phone)).sessions, hasLength(3));
      });
    });
  });

  group('a result belongs to the request that made it', () {
    test('a phone back on a new channel does not get the answer of a '
        'prompt it never made', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        final control = rig.source.controls[-1]!..hold = Completer<void>();
        rig.hub.handle(phone, const AiPrompt(sid: 'ep.-1', rid: 7, text: 'hi'));
        rig.hub.phoneGone(phone); // the channel drops …
        rig.hub.handle(phone, const AiList()); // … and the new one lists
        control.hold!.complete();
        async.flushMicrotasks();
        expect(rig.to(phone).whereType<AiResult>(), isEmpty);
        expect(rig.to(phone).whereType<AiListResult>(), hasLength(1));
      });
    });

    test('nor the answer of an open', () {
      fakeAsync((async) {
        final rig = HubRig();
        rig.source
          ..opened = -5
          ..holdOpen = Completer<void>();
        rig.hub.handle(
          phone,
          const AiOpen(rid: 7, agent: 'claude', folder: 'ws:a'),
        );
        rig.hub.phoneGone(phone);
        rig.hub.handle(phone, const AiList());
        rig.source.holdOpen!.complete();
        async.flushMicrotasks();
        expect(rig.to(phone).whereType<AiResult>(), isEmpty);
      });
    });

    test('the channel that asked still gets it', () {
      fakeAsync((async) {
        final rig = HubRig()..source.add(-1);
        final control = rig.source.controls[-1]!..hold = Completer<void>();
        rig.hub.handle(phone, const AiPrompt(sid: 'ep.-1', rid: 7, text: 'hi'));
        control.hold!.complete();
        async.flushMicrotasks();
        expect(rig.last<AiResult>(phone).rid, 7);
      });
    });
  });

  group('a phone opens only what the computer offers (V2-2 D9)', () {
    test('a listed, ready agent in an offered folder; nothing else reaches '
        'the window', () async {
      final rig = HubRig();
      rig.source
        ..opened = -5
        ..agents = const [
          AiAgentChoice(id: 'claude', name: 'Claude'),
          AiAgentChoice(id: 'codex', name: 'Codex', ready: false),
        ];
      const asks = [
        AiOpen(rid: 1, agent: 'claude', folder: 'ws:a'),
        AiOpen(rid: 2, agent: 'codex', folder: 'ws:a'), // not ready
        AiOpen(rid: 3, agent: 'gemini', folder: 'ws:a'), // not listed
        AiOpen(rid: 4, agent: 'claude', folder: 'path:/etc'), // not offered
      ];
      for (final ask in asks) {
        rig.hub.handle(phone, ask);
      }
      await Future<void>.delayed(Duration.zero);
      final results = {
        for (final r in rig.to(phone).whereType<AiResult>()) r.rid: r,
      };
      expect((results[1]!.ok, results[1]!.sid), (true, 'ep.-5'));
      expect(
        [
          for (final i in [2, 3, 4]) results[i]!.code,
        ],
        ['refused', 'refused', 'refused'],
      );
      expect(rig.source.openedWith, [('claude', 'ws:a')]);
    });

    test('an open the window fails, or one that needs a list it cannot give, '
        'is refused', () async {
      final rig = HubRig()..source.opened = -5;
      rig.source.failing.add('open');
      rig.hub.handle(
        phone,
        const AiOpen(rid: 1, agent: 'claude', folder: 'ws:a'),
      );
      rig.source.failing
        ..clear()
        ..add('agents');
      rig.hub.handle(
        phone,
        const AiOpen(rid: 2, agent: 'claude', folder: 'ws:a'),
      );
      await Future<void>.delayed(Duration.zero);
      final codes = {
        for (final r in rig.to(phone).whereType<AiResult>()) r.rid: r.code,
      };
      expect(codes, {1: 'refused', 2: 'refused'});
    });
  });
}
