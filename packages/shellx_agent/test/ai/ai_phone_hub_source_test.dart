import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// V2-2b B24: what a phone sends is the phone's on the computer, and the
/// phone's mirror says which prompts were written on a phone.
void main() {
  test('a phone\'s prompt reaches the window as the phone\'s and starts a '
      'turn the timeline says is the phone\'s', () {
    fakeAsync((async) {
      final rig = HubRig();
      final s = rig.source.add(-1);
      rig.hub.handle(
        _phone,
        const AiPrompt(sid: 'ep.-1', rid: 1, text: 'Sửa lỗi'),
      );
      async.flushMicrotasks();
      expect(rig.last<AiResult>(_phone).ok, isTrue);
      expect(rig.source.controls[-1]!.prompts.single.text, 'Sửa lỗi');
      expect(
        s.timeline.items.whereType<UserItem>().single.source,
        PromptSource.phone,
      );
    });
  });

  test('the mirror marks the phone\'s prompt and only it', () {
    fakeAsync((async) {
      final rig = HubRig();
      final s = rig.source.add(-1)
        ..beginTurn(const [TextBlock('ở máy tính')], aiT0)
        ..endTurn(outcome: TurnOutcome.finished, at: aiT0);
      rig.hub.handle(_phone, const AiAttach(sid: 'ep.-1'));
      rig.hub.handle(
        _phone,
        const AiPrompt(sid: 'ep.-1', rid: 1, text: 'từ điện thoại'),
      );
      async.elapse(const Duration(seconds: 1));
      expect(s.turn, isNotNull);
      final users = [
        for (final t in rig.mirror(_phone, 'ep.-1').items)
          if (t is MirrorText && t.kind == MirrorTextKind.user)
            (t.text, t.fromPhone),
      ];
      expect(users, [('ở máy tính', false), ('từ điện thoại', true)]);
    });
  });

  test('AiPhonePrompt never shows its text', () {
    expect(const AiPhonePrompt('Sửa lỗi').toString(), '…');
  });
}
