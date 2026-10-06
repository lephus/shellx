import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';

void main() {
  test('10 s mark per tab and pane; one announcement per 60 s (D27)', () {
    fakeAsync((async) {
      var now = DateTime(2026, 10, 7, 9);
      final c = ProviderContainer(
        overrides: [agentMarksClockProvider.overrideWithValue(() => now)],
      );
      final announced = <int>[];
      c.read(agentMarksProvider.notifier).onAnnounce = announced.add;
      c.read(agentMarksProvider.notifier).touch(tab: 5, pane: 6);
      expect(c.read(agentMarksProvider).tabActive(5, now), isTrue);
      expect(c.read(agentMarksProvider).paneActive(6, now), isTrue);
      expect(c.read(agentMarksProvider).paneActive(5, now), isFalse);
      expect(announced, [5]);
      now = now.add(const Duration(seconds: 9));
      c.read(agentMarksProvider.notifier).touch(tab: 5);
      expect(announced, [5]); // within 60 s
      expect(c.read(agentMarksProvider).paneActive(6, now), isTrue);
      now = now.add(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 20));
      expect(c.read(agentMarksProvider).tabActive(5, now), isFalse);
      expect(c.read(agentMarksProvider).tabs, isEmpty); // expired: pruned
      expect(c.read(agentMarksProvider).panes, isEmpty);
      now = now.add(const Duration(seconds: 60));
      c.read(agentMarksProvider.notifier).touch(tab: 5);
      expect(announced, [5, 5]);
      c.dispose();
    });
  });
}
