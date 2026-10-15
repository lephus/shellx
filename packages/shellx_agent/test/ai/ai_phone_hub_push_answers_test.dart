import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// A permission request with [options], as `(optionId, kind)`.
PermissionRequest _perm(List<(String, String)> options) =>
    PermissionRequest.fromJson({
      'sessionId': 's',
      'toolCall': {'toolCallId': 'c1', 'title': 'Sửa src/main.ts'},
      'options': [
        for (final (id, kind) in options)
          {'optionId': id, 'name': id, 'kind': kind},
      ],
    });

/// The one push of a permission with [options], in a session nobody shows.
AiPush _pushFor(List<(String, String)> options) {
  late AiPush push;
  fakeAsync((async) {
    final pushes = <AiPush>[];
    final rig = HubRig(pushes: pushes, clock: () => aiT0.add(async.elapsed));
    rig.source.add(-1)
      ..beginTurn(const [TextBlock('go')], aiT0)
      ..addPermission(_perm(options), aiT0);
    push = pushes.single;
  });
  return push;
}

/// V2-2b B7: the push of a permission request carries the two answers its
/// buttons give — never one that turns on a mode acting without asking, never
/// an "always" one — and a question's push has none.
void main() {
  test('a permission\'s push carries its id, the first "allow once" and the '
      'first "reject once", and the tag of the request', () {
    fakeAsync((async) {
      final pushes = <AiPush>[];
      final rig = HubRig(pushes: pushes, clock: () => aiT0.add(async.elapsed));
      final s = rig.source.add(-1)..beginTurn(const [TextBlock('go')], aiT0);
      final p = s.addPermission(
        _perm([
          ('always', 'allow_always'),
          ('allow', 'allow_once'),
          ('reject', 'reject_once'),
          ('never', 'reject_always'),
        ]),
        aiT0,
      );
      final push = pushes.single;
      expect(
        (push.permission, push.allow, push.reject),
        (p.id, 'allow', 'reject'),
      );
      expect(push.tag, 'ai-ep--1-${p.id}');
      expect(push.answerable, isTrue);
      expect('$push', '…');
    });
  });

  test('the allow button is never an answer that turns on a mode acting '
      'without asking (Review Focus 5)', () {
    expect(
      _pushFor([
        ('bypassPermissions', 'allow_once'),
        ('allow', 'allow_once'),
        ('reject', 'reject_once'),
      ]).allow,
      'allow',
    );
    for (final options in [
      [('bypassPermissions', 'allow_once'), ('reject', 'reject_once')],
      [('yolo-mode', 'allow_once'), ('reject', 'reject_once')],
      [
        ('Allow, and skip:permissions', 'allow_once'),
        ('reject', 'reject_once'),
      ],
    ]) {
      final push = _pushFor(options);
      expect(
        (push.permission, push.allow, push.reject, push.answerable),
        (null, null, null, false),
        reason: '$options',
      );
      expect(push.detail, 'Sửa src/main.ts', reason: 'still the plain push');
    }
  });

  test('without an "allow once" and a "reject once" that fit the push data, '
      'the push has no buttons: never an "always" answer', () {
    for (final options in [
      [('always', 'allow_always'), ('reject', 'reject_once')],
      [('allow', 'allow_once'), ('never', 'reject_always')],
      [('allow', 'allow_once')],
      [('allow', 'allow_once'), ('r' * 257, 'reject_once')],
      [('', 'allow_once'), ('reject', 'reject_once')],
    ]) {
      final push = _pushFor(options);
      expect(push.answerable, isFalse, reason: '$options');
      expect(push.permission, isNull, reason: '$options');
    }
    // 256 characters, not bytes, still fit.
    expect(
      _pushFor([
        ('é' * 256, 'allow_once'),
        ('reject', 'reject_once'),
      ]).answerable,
      isTrue,
    );
  });

  test('a question\'s push never has buttons', () {
    fakeAsync((async) {
      final pushes = <AiPush>[];
      final rig = HubRig(pushes: pushes, clock: () => aiT0.add(async.elapsed));
      rig.source.add(-1)
        ..beginTurn(const [TextBlock('go')], aiT0)
        ..addAsk(
          ElicitationRequest.fromJson({
            'mode': 'form',
            'message': 'Which?',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'pick': {'type': 'string'},
              },
            },
          }),
        );
      final push = pushes.single;
      expect(
        (push.question, push.permission, push.tag, push.answerable),
        (true, null, null, false),
      );
    });
  });

  test('the background service gets the answers in ai.push; an older one, '
      'which does not read them, sends the push without buttons', () {
    const push = AiPush(
      kind: AiPushKind.needsInput,
      agentName: 'Claude',
      sid: 'ep.-1',
      detail: 'Sửa a.ts',
      permission: 7,
      allow: 'allow',
      reject: 'reject',
    );
    final fields = push.toFields();
    expect(
      (fields['perm'], fields['allow'], fields['reject']),
      (7, 'allow', 'reject'),
    );
    final back = AiPush.fromFields(fields)!;
    expect(
      (back.permission, back.allow, back.reject, back.tag),
      (7, 'allow', 'reject', 'ai-ep--1-7'),
    );
    // What a V2-2a service makes of the same fields: it reads none of them.
    final older = AiPush.fromFields(
      {...fields}
        ..remove('perm')
        ..remove('allow')
        ..remove('reject'),
    )!;
    expect((older.permission, older.answerable), (null, false));
    // Half of them is none of them.
    expect(
      AiPush.fromFields({...fields}..remove('reject'))!.answerable,
      isFalse,
    );
    expect(AiPush.fromFields({...fields, 'perm': '7'})!.permission, isNull);
    // A push without answers writes none of the keys.
    expect(
      const AiPush(
        kind: AiPushKind.done,
        agentName: 'Claude',
        sid: 'ep.-1',
      ).toFields().keys,
      isNot(contains('perm')),
    );
  });

  test('through the background service the push keeps its answers', () {
    final pushes = <AiPush>[];
    final forwarder = MuxAiForwarder(onPush: pushes.add);
    final window = Object();
    forwarder.serve(window, (_) {});
    const push = AiPush(
      kind: AiPushKind.needsInput,
      agentName: 'Claude',
      sid: 'ep.-1',
      permission: 7,
      allow: 'allow',
      reject: 'reject',
    );
    forwarder.fromUi(
      window,
      MuxMessage(MuxType.aiPush, fields: push.toFields()),
    );
    expect(
      (pushes.single.permission, pushes.single.allow, pushes.single.reject),
      (7, 'allow', 'reject'),
    );
  });

  test(
    'the tag is in the relay\'s shape, or there is none (and no button)',
    () {
      AiPush withSid(String sid) => AiPush(
        kind: AiPushKind.needsInput,
        agentName: 'Claude',
        sid: sid,
        permission: 41,
        allow: 'a',
        reject: 'r',
      );
      expect(withSid('k3f9za.-12').tag, 'ai-k3f9za--12-41');
      expect(withSid('bad sid').tag, isNull);
      expect(withSid('bad sid').answerable, isFalse);
      expect(withSid('${'k' * 60}.-1').tag, isNull); // over 64 characters
    },
  );

  test('the listing says the window\'s pushes carry their answers', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, const AiList());
    final r = rig.last<AiListResult>(_phone);
    expect(
      AiListing.fromJson(decodeBody(r.body)!, available: r.available).features,
      contains(AiFeature.pushAnswer),
    );
  });
}
