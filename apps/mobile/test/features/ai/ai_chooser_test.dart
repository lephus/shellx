import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_chooser.dart';

import '../../support/app_harness.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const _listing = AiListing(
  sessions: [
    AiSessionInfo(
      sid: 'e.-1',
      agentId: 'claude',
      agentName: 'Claude',
      title: 'Nút đăng xuất',
      state: AiRemoteState.needsInput,
      waiting: 'Sửa src/main.ts',
    ),
  ],
  agents: [AiAgentChoice(id: 'claude', name: 'Claude')],
  folders: [AiFolderChoice(key: 'ws:a', name: 'shop-web', path: '/Users/me/shop-web')],
  defaultAgent: 'claude',
);

/// V2-2b B21, B22: the AI chooser — the session picker's AI group alone, and "Phiên AI mới".
void main() {
  late FakeAiMachine ai;
  late FakePopupHandler popups;
  late List<Object?> pushed;

  setUp(() {
    ai = FakeAiMachine();
    popups = FakePopupHandler();
    pushed = [];
    getIt.registerSingleton<PopupHandler>(popups);
  });

  tearDown(() async => getIt.reset());

  Future<void> choose(WidgetTester tester) async {
    await tester.pumpWidget(
      routedApp(
        open: () => const PageRouteInfo('ChooserHost'),
        routes: [
          AutoRoute(
            page: PageInfo(
              'ChooserHost',
              builder: (_) => Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () =>
                          openAiChooser(context, agentId: agentA, machineName: 'MacBook', ai: ai, listing: _listing),
                      child: const Text('choose'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          stubRoute(AiSessionRoute.name, pushed: pushed),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();
  }

  testWidgets('the computer\'s AI sessions only; the one picked opens', (tester) async {
    await choose(tester);
    expect(find.text('Nút đăng xuất'), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-desktop-hint')), findsNothing);
    expect(find.text('Phiên mới'), findsNothing, reason: 'no new terminal session here');
    await tester.tap(find.byKey(const ValueKey('picker-ai-e.-1')));
    await tester.pumpAndSettle();
    expect([for (final a in pushed) (a! as AiSessionRouteArgs).sid], ['e.-1']);
  });

  testWidgets('"Phiên AI mới" opens the session the computer made', (tester) async {
    ai.openedSid = 'e.-7';
    await choose(tester);
    await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();
    expect(ai.opened, [('claude', 'ws:a')]);
    expect([for (final a in pushed) (a! as AiSessionRouteArgs).sid], ['e.-7']);
  });

  testWidgets('a new session the computer refused opens nothing and says why', (tester) async {
    ai.failWith = 'refused';
    await choose(tester);
    await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();
    expect(pushed, isEmpty);
    expect(popups.errors, isNotEmpty);
  });
}
