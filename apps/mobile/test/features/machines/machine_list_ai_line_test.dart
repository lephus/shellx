import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_ai_lines.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/machines/presentation/pages/machine_list_page.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

AiListing listing({required int waiting, int sessions = 2}) => AiListing(
  sessions: [
    for (var i = 0; i < sessions; i++)
      AiSessionInfo(
        sid: 'e.-${i + 1}',
        agentId: 'claude',
        agentName: 'Claude',
        title: 'Phiên ${i + 1}',
        state: i < waiting ? AiRemoteState.needsInput : AiRemoteState.idle,
      ),
  ],
);

/// The lines of the page, counting what is done to them: the app's lifecycle and the end of the page.
class _SpyLines extends MachineAiLines {
  _SpyLines(super.session, super.registry);

  int disposeCalls = 0;
  final List<bool> foreground = [];

  @override
  void setForeground(bool foreground) {
    this.foreground.add(foreground);
    super.setForeground(foreground);
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

/// V2-2b B21: "✦ 2 phiên AI · 1 cần bạn" on the card of a computer, and where it leads.
void main() {
  late FakeBackend backend;
  late FakeMachineSession mac;
  late WorkspaceRegistry registry;
  late List<Object?> aiPages;
  late List<Object?> terminals;
  late _SpyLines lines;

  setUp(() {
    backend = FakeBackend(devices: [agentDevice(agentA, 'MacBook Pro')], pinnedList: [pinned(agentA)])
      ..onlineIds.add(agentA);
    mac = backend.addMachine(agentA)..ai.supportedValue = true;
    final session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    aiPages = [];
    terminals = [];
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactory<MachineListController>(() => MachineListController(backend: backend, registry: registry))
      ..registerFactory<MachineAiLines>(() => lines = _SpyLines(session, registry));
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> openList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const MachineListRoute(),
        routes: [
          AutoRoute(page: MachineListRoute.page),
          stubRoute(AiSessionRoute.name, pushed: aiPages),
          stubRoute(TerminalRoute.name, pushed: terminals),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Finder line() => find.byKey(ValueKey('machine-ai-$agentA'));

  testWidgets('the line counts the sessions and the ones that wait (warning colour), or only the sessions', (
    tester,
  ) async {
    await openList(tester);
    expect(mac.ai.watching, isTrue);
    expect(line(), findsNothing);
    mac.ai.emitListing(listing(waiting: 1));
    await tester.pump();
    expect(find.descendant(of: line(), matching: find.text('✦ 2 phiên AI · 1 cần bạn')), findsOneWidget);
    final colors = Brightness.light.appColors;
    expect(tester.widget<Text>(find.text('✦ 2 phiên AI · 1 cần bạn')).style!.color, colors.warn);
    mac.ai.emitListing(listing(waiting: 0));
    await tester.pump();
    expect(find.text('✦ 2 phiên AI'), findsOneWidget);
    expect(tester.widget<Text>(find.text('✦ 2 phiên AI')).style!.color, colors.secondaryText);
  });

  testWidgets('one session waits: the line opens it', (tester) async {
    await openList(tester);
    mac.ai.emitListing(listing(waiting: 1));
    await tester.pump();
    await tester.tap(line());
    await tester.pumpAndSettle();
    final args = aiPages.single as AiSessionRouteArgs;
    expect((args.agentId, args.machineName, args.sid), (agentA, 'MacBook Pro', 'e.-1'));
    expect(terminals, isEmpty);
  });

  testWidgets('the page of the waiting session is keyed by it, like every way into an AI session (F44)', (
    tester,
  ) async {
    await openList(tester);
    mac.ai.emitListing(listing(waiting: 1));
    await tester.pump();
    await tester.tap(line());
    await tester.pumpAndSettle();
    expect((aiPages.single as AiSessionRouteArgs).key, const ValueKey('ai:$agentA/e.-1'));
  });

  /// A card on its own, without the list.
  Widget cardOf({
    bool online = true,
    bool waiting = false,
    MachineAiLine? ai = const (sessions: 2, waiting: 1),
    Locale locale = vi,
  }) => localized(
    Scaffold(
      body: MachineCard(
        machine: MachineEntry(
          id: agentA,
          name: 'MacBook Pro',
          platform: DevicePlatform.macos,
          online: online,
          lastSeenAt: null,
          paired: true,
        ),
        waiting: waiting,
        tabs: 0,
        now: DateTime(2026, 10, 16),
        onTap: null,
        ai: ai,
      ),
    ),
    locale: locale,
  );

  testWidgets('the card shows the line only while its machine is online and the relay is up', (tester) async {
    await tester.pumpWidget(cardOf());
    expect(line(), findsOneWidget);
    await tester.pumpWidget(cardOf(online: false));
    expect(line(), findsNothing);
    await tester.pumpWidget(cardOf(waiting: true));
    expect(line(), findsNothing);
  });

  testWidgets('English: the sessions in the singular or the plural, and no "need you" when nobody waits (R11)', (
    tester,
  ) async {
    await tester.pumpWidget(cardOf(locale: en));
    expect(find.text('✦ 2 AI sessions · 1 need you'), findsOneWidget);
    await tester.pumpWidget(cardOf(locale: en, ai: (sessions: 1, waiting: 1)));
    expect(find.text('✦ 1 AI session · 1 need you'), findsOneWidget);
    await tester.pumpWidget(cardOf(locale: en, ai: (sessions: 1, waiting: 0)));
    expect(find.text('✦ 1 AI session'), findsOneWidget);
    await tester.pumpWidget(cardOf(locale: en, ai: (sessions: 3, waiting: 0)));
    expect(find.text('✦ 3 AI sessions'), findsOneWidget);
  });

  testWidgets('none or several wait: the computer\'s AI sessions to pick from, over the list', (tester) async {
    await openList(tester);
    mac.ai.emitListing(listing(waiting: 2));
    await tester.pump();
    await tester.tap(line());
    await tester.pumpAndSettle();
    expect(aiPages, isEmpty);
    // Task 6's chooser lists the sessions by title (the picker's AI rows).
    expect(find.text('Phiên 2'), findsOneWidget);
  });

  testWidgets(
    'the app in the background lets the machine go, the notification shade does not; back, it is held again',
    (
      tester,
    ) async {
      await openList(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(mac.ai.watching, isTrue);
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(mac.ai.watching, isFalse);
      for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(mac.ai.watching, isTrue);
    },
  );

  testWidgets('pulling the list down tries a computer that could not be reached again', (tester) async {
    mac.connectFailure = MachineConnectionFailure.agentOffline;
    await openList(tester);
    expect((mac.connectCalls, mac.ai.watching), (1, false));
    expect(line(), findsNothing);
    mac.connectFailure = null;
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect((mac.connectCalls, mac.ai.watching), (2, true));
  });

  testWidgets('leaving the list lets every machine go, and the app lifecycle no longer reaches its lines', (
    tester,
  ) async {
    await openList(tester);
    expect(mac.ai.watching, isTrue);
    await tester.element(find.byType(MachineListPage)).router.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(MachineListPage), findsNothing);
    expect((mac.ai.watching, mac.ai.hasListingListener, lines.disposeCalls), (false, false, 1));
    final heard = lines.foreground.length;
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(lines.foreground.length, heard);
  });

  testWidgets('the session picked in the chooser opens over the list: the machine stays let go under it', (
    tester,
  ) async {
    await openList(tester);
    mac.ai.emitListing(listing(waiting: 2));
    await tester.pump();
    await tester.tap(line());
    await tester.pumpAndSettle();
    expect(mac.ai.watching, isFalse, reason: 'the chooser is over the list');
    final handshakes = mac.connectCalls;
    await tester.tap(find.byKey(const ValueKey('picker-ai-e.-2')));
    await tester.pumpAndSettle();
    expect((aiPages.single as AiSessionRouteArgs).sid, 'e.-2');
    expect((mac.ai.watching, mac.connectCalls), (false, handshakes), reason: 'the session page is over the list');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(mac.ai.watching, isTrue);
  });

  testWidgets('a page pushed over the list by something else lets the machine go too', (tester) async {
    await openList(tester);
    // What a tapped notification does: it pushes over the list without the list's own code being involved.
    final list = tester.element(find.byType(MachineListPage));
    unawaited(list.router.push(TerminalRoute(agentId: agentA, machineName: 'MacBook Pro')));
    await tester.pumpAndSettle();
    expect(terminals, hasLength(1));
    expect(mac.ai.watching, isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(mac.ai.watching, isTrue);
  });

  testWidgets('a page over the list lets the machine go; back on the list it is held again', (tester) async {
    await openList(tester);
    await tester.tap(find.byKey(ValueKey('machine-$agentA')));
    await tester.pumpAndSettle();
    expect(terminals, hasLength(1));
    expect(mac.ai.watching, isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(mac.ai.watching, isTrue);
  });
}
