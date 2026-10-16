import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

const _view = AiConfigView(
  options: [
    AiConfigOptionView(
      id: 'mode',
      name: 'Mode',
      category: 'mode',
      kind: 'select',
      current: 'default',
      choices: [
        AiConfigChoiceView(value: 'default', name: 'Manual'),
        AiConfigChoiceView(value: 'plan', name: 'Plan'),
      ],
    ),
    AiConfigOptionView(
      id: 'model',
      name: 'Model',
      category: 'model',
      kind: 'select',
      current: 'opus',
      choices: [
        AiConfigChoiceView(value: 'opus', name: 'Opus 5.5'),
        AiConfigChoiceView(value: 'sonnet', name: 'Sonnet 5.5'),
      ],
      more: true,
    ),
    AiConfigOptionView(
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      kind: 'select',
      current: 'high',
      choices: [AiConfigChoiceView(value: 'high', name: 'High')],
    ),
    AiConfigOptionView(id: 'fast', name: 'Fast', category: 'model_config', kind: 'boolean', current: false),
  ],
);

/// V2-2b B11: "Chế độ và model" on the phone.
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
  });

  tearDown(() async => getIt.reset());

  /// The page of [sid] on a computer that offers [features] (and speaks ai 2), its session holding
  /// Claude's model "Opus 5.5".
  Future<FakeAiSession> open(WidgetTester tester, {Set<String> features = const {AiFeature.config}}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(features: features))
      ..configValue = _view;
    final ai = machine.ai.session(sid);
    ai.desktop.configOptions = [
      ?ConfigOption.fromJson({
        'id': 'model',
        'name': 'Model',
        'category': 'model',
        'type': 'select',
        'currentValue': 'opus',
        'options': [
          {'value': 'opus', 'name': 'Opus 5.5'},
        ],
      }),
    ];
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ai.sync();
    await tester.pumpAndSettle();
    return ai;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai.status.tap')));
    await tester.pumpAndSettle();
  }

  testWidgets('the status line names the model; a tap opens the groups, Claude\'s modes in the app\'s words', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('Opus 5.5'), findsOneWidget);
    await openSheet(tester);
    expect(find.text('Chế độ và model'), findsOneWidget);
    for (final group in ['CHẾ ĐỘ', 'MODEL', 'MỨC SUY NGHĨ']) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    expect(find.text('Hỏi trước'), findsOneWidget); // `default`, as the status line says it
    expect(find.text('Lập kế hoạch'), findsOneWidget);
    expect(find.text('Sonnet 5.5'), findsOneWidget);
    expect(find.text('Còn lựa chọn khác trên máy tính.'), findsOneWidget);
    expect(find.byKey(const Key('ai.config.fast')), findsOneWidget);
    expect(machine.ai.configCalls, 1);
  });

  testWidgets('a choice is sent once and the sheet closes; a switch is a switch', (tester) async {
    await open(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('ai.config.model.sonnet')));
    await tester.pumpAndSettle();
    expect(machine.ai.configSets, [(sid, 'model', 'sonnet')]);
    expect(find.text('Chế độ và model'), findsNothing);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('ai.config.fast')));
    await tester.pumpAndSettle();
    expect(machine.ai.configSets.last, (sid, 'fast', true));
  });

  testWidgets('the current choice sends nothing; a refused one says why and the sheet stays', (tester) async {
    await open(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('ai.config.model.opus')));
    await tester.pumpAndSettle();
    expect(machine.ai.configSets, isEmpty);
    machine.ai.failWith = 'on_computer';
    await tester.tap(find.byKey(const Key('ai.config.mode.plan')));
    await tester.pumpAndSettle();
    expect(popups.errors, ['Chọn mục này trên máy tính.']);
    expect(find.text('Chế độ và model'), findsOneWidget);
  });

  testWidgets('an agent with only modes: its modes, set as a mode', (tester) async {
    await open(tester);
    machine.ai.configValue = const AiConfigView(
      modes: AiModesView(
        current: 'default',
        choices: [
          AiConfigChoiceView(value: 'default', name: 'Default'),
          AiConfigChoiceView(value: 'autoEdit', name: 'Auto edit'),
        ],
      ),
    );
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('ai.config.mode.autoEdit')));
    await tester.pumpAndSettle();
    expect(machine.ai.modeSets, [(sid, 'autoEdit')]);
  });

  testWidgets('without the feature (an older computer) the status line is plain text', (tester) async {
    await open(tester, features: const {});
    expect(find.byKey(const Key('ai.status.tap')), findsNothing);
    expect(machine.ai.configCalls, 0);
  });
}
