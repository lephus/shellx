import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/agent_state_codec.dart';
import 'package:shellx_desktop/src/agent/remote_agent_controller.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';

import '../support/config_workspace.dart';

/// A recorder in place of the tray's executor: what Settings asks for is
/// what the tray would ask for (A11 D4).
final class RecordingTrayActions implements TrayActions {
  final handled = <TrayAction>[];

  @override
  Future<void> handle(TrayAction action) async => handled.add(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The tray's local state, changeable from a test.
final localStateProvider = NotifierProvider<LocalStateNotifier, TrayLocalState>(
  LocalStateNotifier.new,
);

class LocalStateNotifier extends Notifier<TrayLocalState> {
  @override
  TrayLocalState build() => const TrayLocalState();
  void set(TrayLocalState next) => state = next;
}

const cmd = LogicalKeyboardKey.metaLeft;

Future<void> open(WidgetTester t, ProviderContainer c, String page) async {
  await t.sendKeyDownEvent(cmd);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(cmd);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(Key('settings.page.$page')));
  await t.pumpAndSettle();
}

Future<void> tapSwitch(WidgetTester t, String id) async {
  await t.tap(find.byKey(Key('setting.$id.switch')));
  await t.pumpAndSettle();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  late RecordingTrayActions tray;
  List<Override> overrides() => [
    trayActionsProvider.overrideWith((ref) => tray),
    trayLocalStateProvider.overrideWith((ref) => ref.watch(localStateProvider)),
  ];

  setUp(() => tray = RecordingTrayActions());

  testWidgets('the Desktop notifications switch asks for the tray\'s own '
      'action, once', (t) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'agents');
    await tapSwitch(t, 'desktop-notifications');
    expect(tray.handled, hasLength(1));
    expect(tray.handled.single, isA<ToggleDesktopNotifications>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a switch follows the tray\'s state', (t) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'general');
    Switch sw() => t.widget<Switch>(
      find.byKey(const Key('setting.background-service.switch')),
    );
    expect(sw().value, isFalse);
    w.container
        .read(localStateProvider.notifier)
        .set(const TrayLocalState(backgroundService: true));
    await t.pumpAndSettle();
    expect(sw().value, isTrue);
    await tapSwitch(t, 'background-service');
    expect(tray.handled.single, isA<ToggleBackgroundService>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('"Notify after" picks a threshold through SetNotifyThreshold', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'agents');
    await t.tap(find.byKey(const Key('setting.notify-threshold.opt.60')));
    await t.pumpAndSettle();
    expect(tray.handled.single, isA<SetNotifyThreshold>());
    expect((tray.handled.single as SetNotifyThreshold).seconds, 60);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('"only when in the background" is off until notifications are '
      'on', (t) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'agents');
    const only = Key('setting.desktop-notifications-only-unfocused.switch');
    expect(t.widget<Switch>(find.byKey(only)).onChanged, isNotNull);
    // Notifications off (the agent's own state): the second switch is locked.
    await w.container
        .read(agentControllerProvider.notifier)
        .setDesktopNotifications(false);
    await t.pumpAndSettle();
    expect(t.widget<Switch>(find.byKey(only)).onChanged, isNull);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the real tray executor and the Settings switch change the same '
      'state', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    await open(t, w.container, 'agents');
    bool on() => w.container.read(agentControllerProvider).desktopNotifications;
    final before = on();
    await tapSwitch(t, 'desktop-notifications');
    expect(on(), !before);
    await w.container
        .read(trayActionsProvider)
        .handle(const ToggleDesktopNotifications());
    await t.pumpAndSettle();
    expect(on(), before);
    expect(
      t
          .widget<Switch>(
            find.byKey(const Key('setting.desktop-notifications.switch')),
          )
          .value,
      before,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('every app switch of the catalogue has a row that calls its '
      'TrayAction', (t) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'general');
    for (final def in kSettings.where(
      (d) => d.owner == SettingOwner.app && d.control == SettingControl.toggle,
    )) {
      // Find the page that shows it, by walking them.
      for (final page in SettingPage.values) {
        await t.tap(find.byKey(Key('settings.page.${page.name}')));
        await t.pumpAndSettle();
        final sw = find.byKey(Key('setting.${def.id}.switch'));
        if (sw.evaluate().isEmpty) continue;
        tray.handled.clear();
        await t.tap(sw);
        await t.pumpAndSettle();
        expect(tray.handled, hasLength(1), reason: def.id);
        expect(
          tray.handled.single.runtimeType,
          def.toggle.runtimeType,
          reason: def.id,
        );
        break;
      }
    }
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Phone, signed out: "Sign in" and locked rows', (t) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await w.container.read(agentControllerProvider.notifier).signOut();
    await open(t, w.container, 'phone');
    expect(find.byKey(const Key('settings.phone.sign-in')), findsOneWidget);
    expect(
      t
          .widget<Switch>(find.byKey(const Key('setting.remote-access.switch')))
          .onChanged,
      isNull,
    );
    final signIn = find.descendant(
      of: find.byKey(const Key('settings.phone.sign-in')),
      matching: find.byType(OutlinedButton),
    );
    await t.tap(signIn);
    await t.pumpAndSettle();
    expect(tray.handled.single, isA<SignIn>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Phone, signed in: the switch works, Pair is offered', (t) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'phone');
    expect(find.byKey(const Key('settings.phone.sign-in')), findsNothing);
    await tapSwitch(t, 'remote-access');
    expect(tray.handled.single, isA<ToggleRemoteAccess>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the command-line install row follows the tray\'s state', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t, extra: overrides());
    await open(t, w.container, 'agents');
    expect(
      find.text('Install the shellx command for all terminals…'),
      findsOneWidget,
    );
    w.container
        .read(localStateProvider.notifier)
        .set(const TrayLocalState(cliPathInstalled: true));
    await t.pumpAndSettle();
    expect(
      find.text('Remove the shellx command from other terminals'),
      findsOneWidget,
    );
    await t.tap(find.text('Remove the shellx command from other terminals'));
    await t.pumpAndSettle();
    expect(tray.handled.single, isA<ToggleCliPath>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('service mode: a daemon-owned switch is a call to the service '
      'and writes nothing in this process', (t) async {
    final (ui, daemonEnd) = MemoryMuxTransport.pair();
    final calls = <String>[];
    daemonEnd.messages.listen((m) {
      if (m.type == MuxType.agentGet) {
        daemonEnd.send(
          MuxMessage(
            MuxType.result,
            q: m.q,
            fields: {'state': agentStateToWire(const AgentViewState())},
          ),
        );
      } else if (m.type == MuxType.agentCall) {
        calls.add('${m.get<String>('m')}:${m.get<Map<Object?, Object?>>('a')}');
        daemonEnd.send(MuxMessage(MuxType.result, q: m.q));
      }
    });
    final store = InMemorySettingsStore({SettingKeys.tourDone: true});
    final w = await pumpConfiguredWorkspace(
      t,
      extra: [
        agentControllerProvider.overrideWith(
          () => RemoteAgentController(MuxClient(ui)),
        ),
        settingsStoreProvider.overrideWithValue(store),
      ],
    );
    await open(t, w.container, 'general');
    final before = {...store.values};
    await tapSwitch(t, 'keep-awake');
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(calls, ['setKeepAwake:{enabled: false}']);
    expect(store.values, before);
    expect(store.ints, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}
