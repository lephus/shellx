import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

PermissionRequest _perm(String toolCallId) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': toolCallId, 'title': 'Sửa src/main.ts'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

/// V2-2b B3, Review Focus 1: a pane keeps its session id when its runtime is
/// replaced (a folder chosen again, its agent switched off and on), so an
/// answer the phone meant for the old runtime's request can never land on
/// the request of the new one.
void main() {
  test('an answer to the old runtime\'s request is stale; the new request '
      'stays asked', () {
    final rig = HubRig();
    final before = rig.source.add(-1);
    final old = before.addPermission(_perm('c1'), aiT0);
    final now = rig.source.replace(-1); // another runtime, the same pane
    final current = now.addPermission(_perm('c1'), aiT0);
    expect(current.id, isNot(old.id));
    rig.hub.handle(
      _phone,
      AiAnswer(sid: 'ep.-1', rid: 1, permission: old.id, option: 'allow'),
    );
    final result = rig.last<AiResult>(_phone);
    expect((result.rid, result.ok, result.code), (1, false, 'stale'));
    expect(rig.source.controls[-1]!.permissions, isEmpty);
    expect(now.currentPermission?.id, current.id, reason: 'still asked');
  });

  test('a queued prompt of the old runtime is not the new one\'s either', () {
    final rig = HubRig();
    final before = rig.source.add(-1);
    before.beginTurn(const [TextBlock('go')], aiT0);
    final old = before.enqueue(const [TextBlock('later')])!;
    final now = rig.source.replace(-1);
    now.beginTurn(const [TextBlock('go')], aiT0);
    final current = now.enqueue(const [TextBlock('later')])!;
    expect(current.id, isNot(old.id));
    rig.hub.handle(_phone, AiUnqueue(sid: 'ep.-1', rid: 2, queued: old.id));
    expect(rig.last<AiResult>(_phone).code, 'stale');
    expect(now.queue.single.id, current.id);
  });
}
