import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

/// The fake's notices arrive asynchronously (a broadcast stream, as from
/// the agent): the first pump delivers them, the second draws the result.
Future<void> deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, title: 'claude'));
    local.add(local.summary(2, title: 'api'));
  });

  Finder ring() => find.byKey(const Key('pane.ring'));
  AnimatedOpacity fade(WidgetTester t) => t.widget<AnimatedOpacity>(
    find.ancestor(of: ring(), matching: find.byType(AnimatedOpacity)).first,
  );

  testSidebar('the selected tab with unread gets the ring; reading removes '
      'it; the terminal is never resized (D21)', (tester) async {
    await pumpSidebar(tester);
    final resizes = List.of(local.views[1]!.resizes);
    expect(fade(tester).opacity, 0);
    local.notice(1, SessionNoticeKind.message, body: 'need you');
    await deliver(tester);
    await tester.pumpAndSettle();
    expect(fade(tester).opacity, 1);
    // UI-A4 §4: base 150 ms easeOutCubic in.
    expect(fade(tester).duration, const Duration(milliseconds: 150));
    expect(fade(tester).curve, Curves.easeOutCubic);
    expect(local.views[1]!.resizes, resizes);
    container.read(tabAttentionProvider.notifier).markRead(1);
    await tester.pump();
    // exit 120 ms easeIn out.
    expect(fade(tester).opacity, 0);
    expect(fade(tester).duration, const Duration(milliseconds: 120));
    expect(fade(tester).curve, Curves.easeIn);
    await tester.pumpAndSettle();
    expect(local.views[1]!.resizes, resizes);
  });

  testSidebar('another tab with unread does not ring the selected one', (
    tester,
  ) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'elsewhere');
    await deliver(tester);
    await tester.pumpAndSettle();
    expect(fade(tester).opacity, 0);
  });

  testSidebar('the ring is paint only: 2 px accent outside, 1 px accent '
      '40 % inside, square, over the terminal area (UI-A4 §4)', (tester) async {
    await pumpSidebar(tester);
    local.notice(1, SessionNoticeKind.bell);
    await deliver(tester);
    await tester.pumpAndSettle();
    final outer = tester.widget<DecoratedBox>(ring());
    final border = (outer.decoration as BoxDecoration).border! as Border;
    expect(border.top.width, 2);
    expect(border.top.color, const Color(0xFF5FD4E2));
    expect((outer.decoration as BoxDecoration).borderRadius, isNull);
    final inner = tester.widget<DecoratedBox>(
      find.descendant(of: ring(), matching: find.byType(DecoratedBox)).first,
    );
    final glow = (inner.decoration as BoxDecoration).border! as Border;
    expect(glow.top.width, 1);
    expect(glow.top.color, const Color(0x665FD4E2));
    expect(
      find.ancestor(of: ring(), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    // Covers the terminal area exactly (no padding of its own).
    final terminal = tester.getRect(find.byKey(const ValueKey('terminal.1')));
    expect(tester.getRect(ring()), terminal);
  });

  testSidebar('the pane label says it has unread (UI-A4 §8)', (tester) async {
    await pumpSidebar(tester);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Terminal claude'), findsOneWidget);
    local.notice(1, SessionNoticeKind.message, body: 'x');
    await deliver(tester);
    expect(
      find.bySemanticsLabel('Terminal claude, has unread notifications'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testSidebar('reduced motion: the ring appears at once', (tester) async {
    await pumpSidebar(tester, disableAnimations: true);
    local.notice(1, SessionNoticeKind.message, body: 'x');
    await deliver(tester);
    expect(fade(tester).duration, Duration.zero);
    expect(fade(tester).opacity, 1);
  });
}
