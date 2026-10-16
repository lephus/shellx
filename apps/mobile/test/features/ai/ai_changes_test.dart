import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_revert_outcome.dart';
import 'package:shellx_mobile/features/ai/domain/ai_text.dart' show kShownLineChars;
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart' show AiDiffLineRow;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

/// Turn 1 changed `src/a.ts` and added `b.txt`.
const _turnOne = AiChangesView(
  scope: 'turn',
  turn: 1,
  files: [
    AiChangedFile(path: 'src/a.ts', kind: 'm', plus: 3, minus: 1),
    AiChangedFile(path: 'b.txt', kind: 'a', plus: 2, minus: 0),
  ],
  first: 1,
  last: 1,
  done: 1,
);

/// V2-2b B20: the Changes sheet, a file's diff page and the revert, on the phone.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late FakePopupHandler popups;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    popups = FakePopupHandler();
    final drafts = AiDrafts();
    final registry = WorkspaceRegistry(session.backend);
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session, drafts, registry),
      );
    // The computer can show and revert changes (V2-2b B1).
    machine.ai
      ..protocolValue = 2
      ..emitListing(const AiListing(features: {AiFeature.changes, AiFeature.revert}))
      ..changesValue = _turnOne;
  });

  tearDown(() async => getIt.reset());

  /// The session page of [sid], whose first turn changed two files (and which runs a second turn when [running]).
  Future<FakeAiSession> open(WidgetTester tester, {bool running = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ai = machine.ai.session(sid);
    final now = DateTime.now();
    ai.desktop
      ..beginTurn(const [TextBlock('go')], now)
      ..endTurn(
        outcome: TurnOutcome.finished,
        at: now,
        changes: const [
          FileChange(path: 'src/a.ts', kind: ChangeKind.modified, added: 3, removed: 1),
          FileChange(path: 'b.txt', kind: ChangeKind.added, added: 2, removed: 0),
        ],
      );
    if (running) ai.desktop.beginTurn(const [TextBlock('more')], now);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [
          AutoRoute(page: AiSessionRoute.page),
          AutoRoute(page: AiFileDiffRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ai.sync();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    return ai;
  }

  /// Taps the turn's summary: the sheet of turn 1.
  Future<void> openTurnOne(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ai.turnEnd.1')));
    await tester.pumpAndSettle();
  }

  /// Taps [key] once the question's buttons have settled (400 ms).
  Future<void> answer(WidgetTester tester, Key key) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('the summary of a turn opens its changes; a file opens its diff', (tester) async {
    await open(tester);
    expect(find.textContaining('2 tệp đổi +5 −1'), findsOneWidget);
    await openTurnOne(tester);
    expect(machine.ai.changesAsked, [(sid, 1)]);
    expect(find.byKey(const Key('ai.changes.sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai.change.src/a.ts')), findsOneWidget);
    expect(find.text('+3 −1'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Hoàn tác lượt này'), findsOneWidget);

    machine.ai.diffValue = const {'path': 'src/a.ts', 'old': 'a\nb', 'new': 'a\nc', 'plus': 1, 'minus': 1};
    await tester.tap(find.byKey(const ValueKey('ai.change.src/a.ts')));
    await tester.pumpAndSettle();
    expect(machine.ai.diffsAsked, [(sid, 'src/a.ts', 1)]);
    expect(find.byKey(const Key('ai.fileDiff')), findsOneWidget);
    expect(find.text('- b'), findsOneWidget);
    expect(find.text('+ c'), findsOneWidget);
    expect(find.textContaining('So với đầu lượt 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.fileDiff.back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.changes.sheet')), findsOneWidget, reason: 'back on the sheet');
  });

  testWidgets('a binary file and a file there neither before nor now say so', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    machine.ai.diffValue = const {'path': 'b.txt', 'binary': true};
    await tester.tap(find.byKey(const ValueKey('ai.change.b.txt')));
    await tester.pumpAndSettle();
    expect(find.text('Tệp nhị phân — xem trên máy tính.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.fileDiff.back')));
    await tester.pumpAndSettle();
    machine.ai.diffValue = const {'path': 'b.txt', 'missing': true};
    await tester.tap(find.byKey(const ValueKey('ai.change.b.txt')));
    await tester.pumpAndSettle();
    expect(find.text('Tệp này không có, cả trước lẫn bây giờ.'), findsOneWidget);
  });

  testWidgets('a line longer than the phone shows is cut, in the diff rows of the conversation (F52)', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    final long = 'x' * (kShownLineChars + 1000);
    machine.ai.diffValue = {'path': 'src/a.ts', 'old': 'a', 'new': long, 'plus': 1, 'minus': 1};
    await tester.tap(find.byKey(const ValueKey('ai.change.src/a.ts')));
    await tester.pumpAndSettle();
    expect(find.byType(AiDiffLineRow), findsNWidgets(2));
    expect(find.text('- a'), findsOneWidget);
    expect(find.text('+ ${'x' * kShownLineChars}…'), findsOneWidget);
    expect(find.text('+ $long'), findsNothing);
  });

  testWidgets('the menu opens the whole session; "Lượt này" is the last turn', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.menu.changes')));
    await tester.pumpAndSettle();
    expect(machine.ai.changesAsked, [(sid, null)]);
    expect(find.text('Hoàn tác cả phiên'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.changes.turn')));
    await tester.pumpAndSettle();
    expect(machine.ai.changesAsked, [(sid, null), (sid, 1)]);
    expect(find.text('Hoàn tác lượt này'), findsOneWidget);
  });

  testWidgets('a revert asks first with the files; a tap in its first 400 ms '
      'does nothing (Review Focus 4)', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    machine.ai.revertAnswers.add(2);
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    expect(find.text('Đưa 2 tệp về như trước lượt 1?'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('ai.revert.dialog')), matching: find.text('src/a.ts')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('ai.revert.confirm')));
    await tester.pump();
    expect(machine.ai.reverts, isEmpty, reason: 'the tap that opened it must not answer it');
    await answer(tester, const Key('ai.revert.confirm'));
    expect(machine.ai.reverts, [(sid, 1, null)]);
    expect(popups.successes, ['Đã hoàn tác 2 tệp.']);
  });

  testWidgets('files changed after the turn: the computer asks, the phone '
      'offers only-unchanged or all (Review Focus 4)', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    machine.ai.revertAnswers.addAll([
      const AiRequestException(
        'confirm',
        body: {
          'touched': ['b.txt'],
          'some_clean': true,
          'files': 2,
        },
      ),
      1,
    ]);
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    await answer(tester, const Key('ai.revert.confirm'));
    expect(find.text('1 tệp đã đổi sau lượt này.'), findsOneWidget);
    expect(find.byKey(const Key('ai.revert.clean')), findsOneWidget);
    expect(find.byKey(const Key('ai.revert.all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.revert.clean')));
    await tester.pump();
    expect(machine.ai.reverts, hasLength(1), reason: 'its buttons wait too');
    await answer(tester, const Key('ai.revert.clean'));
    expect(machine.ai.reverts, [(sid, 1, null), (sid, 1, 'clean')]);
    expect(popups.successes, ['Đã hoàn tác 1 tệp.']);
  });

  testWidgets('cancel sends nothing; "only unchanged" is not offered when every '
      'file changed', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    await answer(tester, const Key('ai.revert.cancel'));
    expect(machine.ai.reverts, isEmpty);
    machine.ai.revertAnswers.add(
      const AiRequestException(
        'confirm',
        body: {
          'touched': ['src/a.ts', 'b.txt'],
          'some_clean': false,
          'files': 2,
        },
      ),
    );
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    await answer(tester, const Key('ai.revert.confirm'));
    expect(find.byKey(const Key('ai.revert.clean')), findsNothing);
    await answer(tester, const Key('ai.revert.cancel'));
    expect(machine.ai.reverts, [(sid, 1, null)]);
  });

  testWidgets('while a turn runs the revert is dim and says to wait; busy_turn '
      'from the computer says the same (Review Focus 4)', (tester) async {
    await open(tester, running: true);
    await openTurnOne(tester);
    expect(tester.widget<FilledButton>(find.byKey(const Key('ai.changes.revert'))).onPressed, isNull);
    expect(find.byKey(const Key('ai.changes.busy')), findsOneWidget);
    expect(find.text('Chờ lượt này xong.'), findsOneWidget);

    // The turn ends; the computer still has one running when the revert lands.
    final ai = machine.ai.session(sid);
    ai.desktop.endTurn(outcome: TurnOutcome.finished, at: DateTime.now());
    ai.sync();
    await tester.pumpAndSettle();
    machine.ai.revertAnswers.add(const AiRequestException('busy_turn'));
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    await answer(tester, const Key('ai.revert.confirm'));
    expect(popups.errors, ['Chờ lượt này xong.']);
  });

  testWidgets('the question names what the revert puts back at the tap: files the running turn changed after '
      'the sheet opened are in it (F51)', (tester) async {
    await open(tester, running: true);
    await tester.tap(find.byKey(const Key('ai.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.menu.changes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai.change.c.ts')), findsNothing);

    // The running turn writes c.ts, then ends: the button wakes, and the sheet still shows what it read at first.
    machine.ai.changesValue = const AiChangesView(
      scope: 'session',
      files: [
        AiChangedFile(path: 'src/a.ts', kind: 'm', plus: 3, minus: 1),
        AiChangedFile(path: 'b.txt', kind: 'a', plus: 2, minus: 0),
        AiChangedFile(path: 'c.ts', kind: 'a', plus: 7, minus: 0),
      ],
      first: 1,
      last: 2,
      done: 2,
    );
    final ai = machine.ai.session(sid);
    ai.desktop.endTurn(outcome: TurnOutcome.finished, at: DateTime.now());
    ai.sync();
    await tester.pumpAndSettle();
    machine.ai.revertAnswers.add(3);
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    expect(find.text('Đưa 3 tệp về như trước phiên này?'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('ai.revert.dialog')), matching: find.text('c.ts')),
      findsOneWidget,
    );
    expect(machine.ai.changesAsked, [(sid, null), (sid, null)], reason: 'read again at the tap');
    expect(find.byKey(const ValueKey('ai.change.c.ts')), findsOneWidget, reason: 'the sheet shows what it read');
    await answer(tester, const Key('ai.revert.confirm'));
    expect(machine.ai.reverts, [(sid, null, null)]);
    expect(popups.successes, ['Đã hoàn tác 3 tệp.']);
  });

  testWidgets('a read that fails at the tap asks nothing and sends nothing; the sheet says why (F51)', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    machine.ai.connectFailure = MachineConnectionFailure.agentOffline;
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.revert.dialog')), findsNothing);
    expect(machine.ai.changesAsked, [(sid, 1), (sid, 1)]);
    expect(machine.ai.reverts, isEmpty);
    expect(find.byKey(const Key('ai.changes.error')), findsOneWidget);
    expect(find.textContaining('Có thể chưa gửi được'), findsOneWidget);
    expect(popups.errors, isEmpty, reason: 'the sheet says it, as it says any read that failed');
  });

  testWidgets('a revert lost with the channel may not have gone, and is never '
      'sent again', (tester) async {
    await open(tester);
    await openTurnOne(tester);
    await tester.tap(find.byKey(const Key('ai.changes.revert')));
    await tester.pump();
    // The channel drops once the question is up (the changes are read again at the tap, F51): the revert itself is
    // what it takes with it.
    machine.ai.connectFailure = MachineConnectionFailure.agentOffline;
    await answer(tester, const Key('ai.revert.confirm'));
    expect(machine.ai.reverts, hasLength(1));
    expect(popups.errors.single, startsWith('Có thể chưa gửi được'));
    await tester.pump(const Duration(seconds: 5));
    expect(machine.ai.reverts, hasLength(1));
  });

  testWidgets('undo off: the sheet says why and offers no revert', (tester) async {
    machine.ai.changesValue = const AiChangesView(scope: 'session', off: 'noGit');
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.menu.changes')));
    await tester.pumpAndSettle();
    expect(find.text('Hoàn tác đang tắt cho dự án này (không tìm thấy git).'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('ai.changes.revert'))).onPressed, isNull);
  });

  testWidgets('a computer that cannot: no menu entry, the summary is no button', (tester) async {
    machine.ai.emitListing(const AiListing());
    await open(tester);
    expect(find.byKey(const ValueKey('ai.turnEnd.1')), findsNothing);
    expect(find.byKey(const Key('ai.menu')), findsNothing);
    expect(machine.ai.changesAsked, isEmpty);
  });

  test('nothing of an outcome is printed', () {
    expect(const AiRevertDone(2).toString(), 'AiRevertDone(…)');
    expect(const AiRevertFailed('busy_turn').toString(), 'AiRevertFailed(…)');
    expect(const AiRevertAsk(AiRevertConfirm(touched: ['secret.ts'])).toString(), 'AiRevertAsk(…)');
  });
}
