import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

const _waiting = AiSessionInfo(
  sid: 'e.-1',
  agentId: 'claude',
  agentName: 'Claude',
  title: 'Nút đăng xuất',
  state: AiRemoteState.needsInput,
  waiting: 'Sửa src/main.ts',
);

const _claude = AiAgentChoice(id: 'claude', name: 'Claude');
const _codex = AiAgentChoice(id: 'codex', name: 'Codex');
const _shop = AiFolderChoice(key: 'ws:a', name: 'shop-web', path: '/Users/me/shop-web');
const _blog = AiFolderChoice(key: 'ws:b', name: 'blog', path: '/Users/me/blog');

/// A computer with one session waiting, and everything to start another.
const _listing = AiListing(
  sessions: [_waiting],
  agents: [_claude],
  folders: [_shop],
  defaultAgent: 'claude',
);

const _terminal = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1, attached: false);

bool isAiSessionRow(Widget widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('picker-ai-e.');
}

/// V2-2 §5.1 and the additions of Task 10: how the AI entries of the machine page behave when the
/// computer has no AI sessions now, cannot be reached, or goes away; the watch of the list.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late FakePopupHandler popups;
  late List<Object?> pushed;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    final settings = AppSettings(InMemoryKeyValueStore());
    popups = FakePopupHandler();
    pushed = [];
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(FakeSpeechInput(), settings));
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// The machine page of [agentA], entered from the start page, not settled: while the first listing of
  /// the AI sessions is awaited (up to [TerminalWorkspace.aiListingWait]) the progress bar never rests.
  Future<void> enter(WidgetTester tester, {List<Object?>? results, bool landscape = false}) async {
    tester.view.physicalSize = landscape ? const Size(2532, 1170) : const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [
          AutoRoute(page: TerminalRoute.page),
          stubRoute(AiSessionRoute.name, pushed: pushed),
        ],
        results: results,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// [enter] and settle: for a computer whose AI listing is in hand (or that has none).
  Future<void> open(WidgetTester tester, {List<Object?>? results, bool landscape = false}) async {
    await enter(tester, results: results, landscape: landscape);
    await tester.pumpAndSettle();
  }

  /// What the app says, in the words of the strings (a reworded string is not a failing test).
  S words(WidgetTester tester) => S.of(tester.element(find.byType(Scaffold).first));

  /// The picker opened on entry is closed by a tap beside it.
  Future<void> dismissPicker(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
  }

  Future<void> leavePage(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
  }

  group('the watch of the list follows the page', () {
    testWidgets('the page watches the list while it is open and stops when it is left', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      await open(tester);
      expect(find.byKey(const ValueKey('picker-ai-e.-1')), findsOneWidget);
      expect((machine.ai.watchCalls, machine.ai.watching), (1, true));
      await dismissPicker(tester);
      expect(machine.ai.unwatchCalls, 0);

      await leavePage(tester);
      expect(find.text('open'), findsOneWidget);
      expect((machine.ai.watchCalls, machine.ai.unwatchCalls, machine.ai.watching), (1, 1, false));
    });

    testWidgets('an AI session over the page does not stop it; leaving the page does', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('picker-ai-e.-1')));
      await tester.pumpAndSettle();
      expect((pushed.single! as AiSessionRouteArgs).sid, 'e.-1');
      expect(machine.ai.unwatchCalls, 0, reason: 'the page is still there, under the session');

      await tester.tap(find.byType(BackButton)); // the stand-in page's
      await tester.pumpAndSettle();
      expect(machine.ai.unwatchCalls, 0);
      await leavePage(tester);
      expect((machine.ai.watchCalls, machine.ai.unwatchCalls), (1, 1));
    });

    testWidgets('a computer without AI for phones is not watched at all', (tester) async {
      machine.ai.supportedValue = false;
      machine.sessions = [_terminal];
      await open(tester);
      await dismissPicker(tester);
      await leavePage(tester);
      expect((machine.ai.watchCalls, machine.ai.unwatchCalls), (0, 0));
    });

    testWidgets('a second visit: the count of the first one is gone until the computer answers again', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      machine.sessions = [_terminal];
      await open(tester);
      await dismissPicker(tester);
      machine.ai.emitListing(_listing);
      await tester.pump();
      expect(find.byKey(const ValueKey('terminal-ai')), findsOneWidget);
      await leavePage(tester);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(machine.ai.watchCalls, 2, reason: 'a visit watches again');
      expect(find.byKey(const ValueKey('terminal-ai')), findsNothing, reason: 'the old listing may be stale');

      machine.ai.emitListing(const AiListing(agents: [_claude], folders: [_shop]));
      await tester.pump();
      final button = find.byKey(const ValueKey('terminal-ai'));
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.text('0')),
        findsNothing,
        reason: 'no one waits: no badge',
      );
      expect(find.descendant(of: button, matching: find.text('1')), findsNothing);
    });
  });

  group('no AI sessions now is a calm state, never an error', () {
    testWidgets('the computer has AI but no window serves it: a hint, not an error', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = AiListing.unavailable;
      await open(tester);
      expect(find.text('PHIÊN AI'), findsOneWidget);
      expect(find.text(words(tester).aiUnavailable), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-ai-hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-ai-new')), findsNothing);
      expect(popups.errors, isEmpty);
      expect(find.byKey(const ValueKey('terminal-ai')), findsNothing, reason: 'no AI button without a listing');
    });

    testWidgets('the computer does not answer the list in time: the same hint, once the wait is over', (tester) async {
      machine.ai.supportedValue = true;
      await enter(tester);
      expect(find.text('PHIÊN AI'), findsNothing, reason: 'the picker waits for the computer for a moment');
      await tester.pump(TerminalWorkspace.aiListingWait);
      await tester.pumpAndSettle();
      expect(find.text('PHIÊN AI'), findsOneWidget);
      expect(find.text(words(tester).aiUnavailable), findsOneWidget);
      expect(popups.errors, isEmpty);
    });

    testWidgets('a listing without sessions offers the new session and nothing else', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = const AiListing(agents: [_claude], folders: [_shop]);
      await open(tester);
      expect(find.text('PHIÊN AI'), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-ai-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-ai-hint')), findsNothing);
      expect(find.byWidgetPredicate(isAiSessionRow), findsNothing, reason: 'no session row');
      expect(find.text('Máy này đang có 0 phiên'), findsOneWidget);
    });

    testWidgets('a session that waits for the user is in the warning colour; one that runs is not', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = const AiListing(
          sessions: [
            _waiting,
            AiSessionInfo(
              sid: 'e.-2',
              agentId: 'claude',
              agentName: 'Claude',
              title: 'Chạy test',
              state: AiRemoteState.running,
              waiting: 'chỉ khi chờ mới hiện',
            ),
          ],
          agents: [_claude],
          folders: [_shop],
        );
      await open(tester);
      final s = words(tester);
      final colors = Brightness.light.appColors;
      Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;
      expect(colorOf(s.aiRowSubtitle('Claude', AiWords.state(s, AiRemoteState.needsInput))), colors.warn);
      expect(colorOf(s.aiRowSubtitle('Claude', AiWords.state(s, AiRemoteState.running))), colors.secondaryText);
      expect(find.text('Sửa src/main.ts'), findsOneWidget, reason: 'what the first one waits for');
      expect(find.text('chỉ khi chờ mới hiện'), findsNothing, reason: 'a running session waits for nothing');
    });

    testWidgets('the title counts the AI sessions with the terminal ones', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      machine.sessions = [_terminal];
      await open(tester);
      expect(find.text('Máy này đang có 2 phiên'), findsOneWidget, reason: 'one terminal, one AI session');
    });

    testWidgets('no agent ready, or no folder: the setup hint instead of the new session', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = const AiListing(
          agents: [AiAgentChoice(id: 'codex', name: 'Codex', ready: false)],
          folders: [_shop],
        );
      await open(tester);
      expect(find.text(words(tester).aiNewNoAgents), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-ai-new')), findsNothing);
    });

    testWidgets('an agent but no folder: says to set a folder', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = const AiListing(agents: [_claude]);
      await open(tester);
      expect(find.text(words(tester).aiNewNoFolders), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-ai-new')), findsNothing);
    });

    testWidgets('an old computer with no session to pick: no picker, a new terminal at once, as before AI', (
      tester,
    ) async {
      machine.ai.supportedValue = false;
      await enter(tester); // half a second: nothing waits for a listing that cannot come
      expect(machine.opened, hasLength(1));
      await tester.pumpAndSettle();
      expect(find.text('PHIÊN AI'), findsNothing);
      expect(find.byKey(const ValueKey('terminal-ai')), findsNothing);
    });

    testWidgets('a computer that has not said whether it has AI shows no AI group', (tester) async {
      machine.sessions = [_terminal];
      await open(tester);
      expect(find.text('PHIÊN AI'), findsNothing);
      expect(find.byKey(const ValueKey('picker-ai-hint')), findsNothing);
      expect(find.byKey(const ValueKey('picker-session-7')), findsOneWidget);
    });

    testWidgets('a computer with AI offers the picker even with no terminal session at all', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = AiListing.unavailable;
      await open(tester);
      expect(find.text('Phiên mới'), findsOneWidget, reason: 'the new terminal session is in the picker');
      expect(machine.opened, isEmpty);
    });
  });

  group('the machine is not reachable', () {
    testWidgets('+ says why, with the words of the machine, and opens no picker', (tester) async {
      machine.sessions = [_terminal];
      machine.ai.supportedValue = false;
      await open(tester);
      await dismissPicker(tester);
      machine
        ..connectFailure = MachineConnectionFailure.agentOffline
        ..emitState(const MachineIdle());
      await tester.tap(find.byTooltip(words(tester).terminalOpenNew));
      await tester.pumpAndSettle();
      expect(find.text(ErrorText(words(tester)).machine(MachineConnectionFailure.agentOffline)), findsWidgets);
      expect(find.text('PHIÊN AI'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'nothing is loading');
      await tester.pump(TerminalPageController.noticeDuration);
    });

    testWidgets('the AI button says it the same way', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      machine.sessions = [_terminal];
      await open(tester);
      await dismissPicker(tester);
      machine.ai.emitListing(_listing);
      await tester.pump();
      machine
        ..connectFailure = MachineConnectionFailure.agentOffline
        ..emitState(const MachineIdle());
      await tester.tap(find.byKey(const ValueKey('terminal-ai')));
      await tester.pumpAndSettle();
      expect(find.text(ErrorText(words(tester)).machine(MachineConnectionFailure.agentOffline)), findsWidgets);
      expect(find.text('PHIÊN AI'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pump(TerminalPageController.noticeDuration);
    });

    // The request may have left the phone and reached the computer, which may have opened the session
    // (V2-2 D13): the words say so, and nothing sends the request again by itself.
    for (final failure in [MachineConnectionFailure.agentOffline, MachineConnectionFailure.timeout]) {
      testWidgets(
        'a new AI session whose request ends as ${failure.name}: it may not have been created, never retried',
        (
          tester,
        ) async {
          final results = <Object?>[];
          machine.ai
            ..supportedValue = true
            ..listingValue = _listing;
          await open(tester, results: results);
          machine.ai.connectFailure = failure;
          await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('ai-new-start')));
          await tester.pumpAndSettle();
          expect(machine.ai.opened, [('claude', 'ws:a')]);
          expect(pushed, isEmpty);
          expect(popups.errors, [words(tester).aiOpenOutcomeUnknown], reason: 'the words of an unknown outcome');
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(results, isEmpty, reason: 'the page stays: it is not a reason to leave');
          // Nothing asks again: not when the computer is back, not later on.
          machine.ai.connectFailure = null;
          await tester.pump(const Duration(minutes: 2));
          await tester.pumpAndSettle();
          expect(machine.ai.opened, hasLength(1), reason: 'the user asks again, nothing else does');
          expect(pushed, isEmpty);
          await tester.pump(TerminalPageController.noticeDuration);
        },
      );
    }

    testWidgets('a new AI session the computer cannot serve (no window): its words, a toast, no page', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing
        ..failWith = 'unavailable';
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);
      expect(popups.errors, [AiWords.failure(words(tester), 'unavailable')]);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a computer that no longer trusts the phone while it opens a session: the page leaves as untrusted', (
      tester,
    ) async {
      final results = <Object?>[];
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing
        ..connectFailure = MachineConnectionFailure.untrusted;
      await open(tester, results: results);
      await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pumpAndSettle();
      expect(results, [TerminalExit.untrusted]);
      expect(pushed, isEmpty);
      expect(machine.ai.watching, isFalse, reason: 'the page left with its machine');
      expect(tester.takeException(), isNull);
    });
  });

  group('opening an AI session over the machine page', () {
    testWidgets('the terminal under it is not looked at meanwhile: its output counts as unseen until back', (
      tester,
    ) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      machine.sessions = [_terminal];
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('picker-session-7'))); // a tab
      await tester.pumpAndSettle();
      final workspace = registry.forMachine(agentA);
      machine.handle(7).emit(const TabOutput('seen'));
      await tester.pump();
      expect(workspace.unseenCount, 0, reason: 'the terminal is on screen');

      machine.ai.emitListing(_listing);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('terminal-ai')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-ai-e.-1')));
      await tester.pumpAndSettle();
      expect(pushed, hasLength(1));
      machine.handle(7).emit(const TabOutput('while the AI session is on top'));
      await tester.pump();
      expect(workspace.unseenCount, 1);

      await tester.tap(find.byType(BackButton)); // the stand-in page's
      await tester.pumpAndSettle();
      expect(workspace.unseenCount, 0, reason: 'looked at again');
      machine.handle(7).emit(const TabOutput('seen again'));
      await tester.pump();
      expect(workspace.unseenCount, 0);
    });

    testWidgets('a session opened from a tap of a row, and a new one, both go to AiSessionRoute of this machine', (
      tester,
    ) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing
        ..openedSid = 'e.-7';
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('picker-ai-e.-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      machine.ai.emitListing(_listing);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('terminal-ai')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pumpAndSettle();
      expect([for (final args in pushed) (args! as AiSessionRouteArgs).sid], ['e.-1', 'e.-7']);
      expect([for (final args in pushed) (args! as AiSessionRouteArgs).agentId], [agentA, agentA]);
      expect([for (final args in pushed) (args! as AiSessionRouteArgs).machineName], ['MacBook-Pro', 'MacBook-Pro']);
      expect(machine.ai.prompts, isEmpty, reason: 'a new session is opened, nothing is said in it');
    });
  });

  group('the AI button in the chrome', () {
    testWidgets('in landscape too: it counts the sessions that wait and opens the picker', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing;
      machine.sessions = [_terminal];
      await open(tester, landscape: true);
      await dismissPicker(tester);
      machine.ai.emitListing(_listing);
      await tester.pump();
      final button = find.byKey(const ValueKey('terminal-ai'));
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.text('1')), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('PHIÊN AI'), findsOneWidget);
    });

    testWidgets('it waits while a request of the page is on its way, like +', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = _listing
        ..gate = Completer<void>();
      await open(tester);
      await dismissPicker(tester);
      machine.ai.emitListing(_listing);
      await tester.pump();
      IconButton button() => tester.widget<IconButton>(find.byKey(const ValueKey('terminal-ai')));
      expect(button().onPressed, isNotNull);

      await tester.tap(find.byTooltip(words(tester).terminalOpenNew));
      await tester.pump(); // `+` lists the sessions; the picker comes
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pump();
      expect(machine.ai.opened, [('claude', 'ws:a')]);
      expect(button().onPressed, isNull, reason: 'the session is being opened');

      machine.ai.gate!.complete();
      await tester.pumpAndSettle();
      expect((pushed.single! as AiSessionRouteArgs).sid, machine.ai.openedSid);
    });

    testWidgets('no listing, or a computer where no window serves AI: no button', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = AiListing.unavailable;
      await open(tester);
      await dismissPicker(tester);
      machine.ai.emitListing(AiListing.unavailable);
      await tester.pump();
      expect(find.byKey(const ValueKey('terminal-ai')), findsNothing);
      machine.ai.emitListing(_listing); // a window comes up
      await tester.pump();
      expect(find.byKey(const ValueKey('terminal-ai')), findsOneWidget);
    });
  });

  group('the new AI session sheet', () {
    const both = AiListing(
      agents: [_claude, _codex],
      folders: [_shop, _blog],
      defaultAgent: 'claude',
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
      await tester.pumpAndSettle();
    }

    testWidgets('what the user chose is what is started: the second agent, the second folder', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = both;
      await open(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('ai-new-agent-codex')));
      await tester.tap(find.byKey(const ValueKey('ai-new-folder-ws:b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pumpAndSettle();
      expect(machine.ai.opened, [('codex', 'ws:b')]);
    });

    testWidgets('the choice survives the phone being turned', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = both;
      await open(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('ai-new-agent-codex')));
      await tester.tap(find.byKey(const ValueKey('ai-new-folder-ws:b')));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(2532, 1170);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('ai-new-start')));
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pumpAndSettle();
      expect(machine.ai.opened, [('codex', 'ws:b')]);
    });

    testWidgets('at first: the computer\'s default agent, and the first folder', (tester) async {
      machine.ai
        ..supportedValue = true
        ..listingValue = const AiListing(
          agents: [_claude, _codex],
          folders: [_shop, _blog],
          defaultAgent: 'codex',
        );
      await open(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('ai-new-start')));
      await tester.pumpAndSettle();
      expect(machine.ai.opened, [('codex', 'ws:a')]);
    });

    testWidgets(
      'the computer\'s default agent is chosen at first, else the first ready one; an agent not ready is not',
      (
        tester,
      ) async {
        machine.ai
          ..supportedValue = true
          ..listingValue = const AiListing(
            agents: [
              AiAgentChoice(id: 'codex', name: 'Codex', ready: false),
              _claude,
            ],
            folders: [_shop],
            defaultAgent: 'codex', // not ready
          );
        await open(tester);
        await openSheet(tester);
        await tester.tap(find.byKey(const ValueKey('ai-new-agent-codex')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-new-start')));
        await tester.pumpAndSettle();
        expect(machine.ai.opened, [('claude', 'ws:a')]);
      },
    );
  });
}
