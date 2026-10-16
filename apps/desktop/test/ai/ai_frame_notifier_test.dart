import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';

void main() {
  testWidgets('a burst of 2 000 updates is one notification per frame', (
    t,
  ) async {
    final state = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: '/w',
    );
    final frames = AiFrameNotifier(state);
    var heard = 0;
    frames.addListener(() => heard++);
    final at = DateTime(2026, 10, 14);
    for (var i = 0; i < 2000; i++) {
      state.applyUpdate(AgentMessageChunk(TextBlock('x')), at);
    }
    expect(heard, 0, reason: 'nothing before the frame');
    await t.pump();
    expect(heard, 1);
    await t.pump();
    expect(heard, 1, reason: 'no news, no notification');
    state.applyUpdate(AgentMessageChunk(TextBlock('y')), at);
    await t.pump();
    expect(heard, 2);
    frames.dispose();
    state.applyUpdate(AgentMessageChunk(TextBlock('z')), at);
    await t.pump();
    expect(heard, 2, reason: 'disposed: unhooked');
  });
}
