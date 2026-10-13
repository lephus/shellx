import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/agent_reply_bar.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/features/voice/presentation/widgets/mic_button.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

/// Agent quick reply D2, §3: the reply bar replaces the extra keys while the tab's agent waits.
void main() {
  const needsInput = TabAgent(agent: 'claude', state: AgentWireState.needsInput);
  const running = TabAgent(agent: 'claude', state: AgentWireState.running);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late WorkspaceRegistry registry;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    final settings = AppSettings(InMemoryKeyValueStore());
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(FakeSpeechInput(), settings))
      ..registerSingleton<ExternalLinks>(FakeExternalLinks());
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> open(WidgetTester tester, {Locale locale = vi}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [AutoRoute(page: TerminalRoute.page)],
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Finder labelled(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

  /// The reply bar scrolls sideways: brings [finder] into view.
  Future<void> reveal(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
    finder.hitTestable(),
    100,
    scrollable: find.descendant(of: find.byType(AgentReplyBar), matching: find.byType(Scrollable)),
  );

  Future<void> tell(WidgetTester tester, TabAgent agent) async {
    machine.handles.single.emit(agent);
    await tester.pump();
  }

  testWidgets('the bar replaces the extra keys while the agent waits, and goes when it stops waiting', (tester) async {
    await open(tester);
    expect(find.byType(AgentReplyBar), findsNothing);
    expect(find.byType(ExtraKeysBar), findsOneWidget);

    await tell(tester, needsInput);
    expect(find.byType(AgentReplyBar), findsOneWidget);
    expect(find.byType(ExtraKeysBar), findsNothing);
    expect(
      find.descendant(of: find.byType(AgentReplyBar), matching: find.byType(MicButton)),
      findsOneWidget,
      reason: 'the composer / voice button stays',
    );

    await tell(tester, running);
    expect(find.byType(AgentReplyBar), findsNothing);
    expect(find.byType(ExtraKeysBar), findsOneWidget);
  });

  testWidgets('each key sends exactly one key', (tester) async {
    await open(tester);
    // Application cursor mode on: the reply keys still send the plain sequences.
    machine.handles.single.emit(const TabOutput('\x1b[?1h'));
    await tell(tester, needsInput);
    const expected = {
      ReplyKey.one: '1',
      ReplyKey.two: '2',
      ReplyKey.three: '3',
      ReplyKey.yes: 'y',
      ReplyKey.no: 'n',
      ReplyKey.enter: '\r',
      ReplyKey.esc: '\x1b',
      ReplyKey.up: '\x1b[A',
      ReplyKey.down: '\x1b[B',
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      final finder = find.byKey(ValueKey('reply-key-${key.name}'));
      await reveal(tester, finder);
      await tester.tap(finder);
      expect(utf8.decode(machine.inputs.last.data), value, reason: key.name);
    }
    expect(machine.inputs, hasLength(expected.length));
  });

  testWidgets('⌨ brings the extra keys back until the next needs_input', (tester) async {
    await open(tester);
    await tell(tester, needsInput);
    final keyboard = find.byKey(const ValueKey('reply-keyboard'));
    await reveal(tester, keyboard);
    await tester.tap(keyboard);
    await tester.pump();
    expect(find.byType(AgentReplyBar), findsNothing);
    expect(find.byType(ExtraKeysBar), findsOneWidget);

    await tell(tester, running);
    await tell(tester, needsInput);
    expect(find.byType(AgentReplyBar), findsOneWidget);
  });

  testWidgets('the keys are labelled for screen readers (EN; the VI dot labels are read below)', (tester) async {
    await open(tester, locale: en);
    await tell(tester, needsInput);
    expect(labelled('Quick replies to the agent'), findsOneWidget);
    expect(labelled('Option 1'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('reply-keyboard')));
    expect(labelled('Escape'), findsOneWidget);
    expect(labelled('Show the extra keys'), findsOneWidget);
    expect(labelled('An agent needs your answer'), findsOneWidget);
  });

  testWidgets('the tab strip dot: amber while the agent waits, neutral while it runs, none otherwise', (tester) async {
    await open(tester);
    final id = machine.handles.single.id;
    final dot = find.byKey(ValueKey('tab-agent-$id'));
    expect(dot, findsNothing);

    await tell(tester, needsInput);
    expect(labelled('Agent cần bạn trả lời'), findsOneWidget);
    expect(
      tester.widget<Container>(dot).decoration,
      isA<BoxDecoration>().having((d) => d.color, 'color', TerminalColors.yellow),
    );

    await tell(tester, running);
    expect(labelled('Agent đang chạy'), findsOneWidget);
    expect(
      tester.widget<Container>(dot).decoration,
      isA<BoxDecoration>().having((d) => d.color, 'color', TerminalColors.muted),
    );

    await tell(tester, const TabAgent(agent: 'claude', state: AgentWireState.idle));
    expect(dot, findsNothing);
  });
}
