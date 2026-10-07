import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/agent_bridge_impl.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_controller_base.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/agent/remote_agent_controller.dart';
import 'package:shellx_desktop/src/cli/cli_service.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

/// Every key, and who owns it (A5b D13). Written out by hand: a new
/// [SettingKeys] entry fails this test until someone decides.
const _expectedDaemon = {
  // The spec's nine.
  'remote_access_enabled',
  'keep_awake_enabled',
  'launch_at_startup_enabled',
  'onboarding_done',
  'terminal_sharing_enabled',
  'terminal_sharing_files',
  'command_notify_threshold_seconds',
  'desktop_notifications_enabled',
  'desktop_notifications_only_unfocused',
  // Task 6 ruling: the CLI host (daemon) reads them, the tray toggles them.
  'cli_control_enabled',
  'cli_allow_external',
  // Read where the ssh hook is installed (daemon), toggled from the tray.
  'ssh_remote_hook',
};

const _expectedUi = {
  'terminal_font_size',
  'window_x',
  'window_y',
  'window_width',
  'window_height',
  'window_maximized',
  'terminal_workspaces',
  'terminal_restore_scrollback',
  'cli_path_installed',
  'config_ghostty_notice_shown',
  'ssh_recent_targets',
  'ssh_plain_targets',
  'quit_keeps_sessions_explained',
  'background_service_enabled',
};

final class _Listener implements MuxListener {
  final _c = StreamController<MuxConnection>.broadcast();
  @override
  Stream<MuxConnection> get connections => _c.stream;
  @override
  String get address => 'test';
  @override
  Future<void> close() async {}
  void push(MuxConnection c) => _c.add(c);
}

final _secret = Uint8List.fromList(List.generate(32, (i) => i + 1));

void main() {
  test('every key has exactly one owner (D13)', () {
    expect(DaemonSettingKeys.all.intersection(UiSettingKeys.all), isEmpty);
    expect(DaemonSettingKeys.all.union(UiSettingKeys.all), SettingKeys.all);
  });

  test('the decision for every current key is the recorded one', () {
    expect(DaemonSettingKeys.all, _expectedDaemon);
    expect(UiSettingKeys.all, _expectedUi);
    expect(SettingKeys.all, hasLength(26));
    expect(
      SettingKeys.quitKeepsSessionsExplained,
      'quit_keeps_sessions_explained',
    );
    expect(SettingKeys.backgroundService, 'background_service_enabled');
  });

  test('the UI never writes or reads a daemon key', () {
    final names = [
      for (final k in SettingKeys.all)
        if (DaemonSettingKeys.all.contains(k)) k,
    ];
    expect(names, isNotEmpty);
    const idents = [
      'remoteAccess',
      'keepAwake',
      'launchAtStartup',
      'onboardingDone',
      'terminalSharing',
      'notifyThreshold',
      'desktopNotifications',
      'cliControlEnabled',
      'cliAllowExternal',
      'sshRemoteHook',
    ];
    // UI-only code: nothing under these may name a daemon key.
    for (final path in [
      'lib/src/tray/tray_actions.dart',
      'lib/src/tray/tray_menu.dart',
      'lib/src/ui',
      'lib/src/terminal',
      'lib/src/restore',
      'lib/src/remote',
      'lib/src/config',
      'lib/src/cli/cli_settings.dart',
    ]) {
      final files = FileSystemEntity.isDirectorySync(path)
          ? Directory(path).listSync(recursive: true).whereType<File>()
          : [File(path)];
      for (final file in files) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        for (final key in idents) {
          expect(
            text.contains('SettingKeys.$key'),
            isFalse,
            reason: '${file.path} uses $key',
          );
        }
        for (final key in names) {
          expect(
            text.contains("'$key'"),
            isFalse,
            reason: '${file.path} spells a daemon key',
          );
        }
      }
    }
  });

  group('two processes, one writer per key', () {
    late TestHarness h; // the daemon's settings, services and agent
    late ProviderContainer daemon;
    late InMemorySettingsStore uiSettings; // the UI's own store
    late ProviderContainer ui;
    late MuxServer server;
    late MuxClient client;
    late ControllerAgentBridge bridge;
    var rechecks = 0;

    setUp(() async {
      rechecks = 0;
      h = TestHarness();
      daemon = ProviderContainer.test(
        overrides: [
          desktopServicesProvider.overrideWithValue(h.services()),
          settingsStoreProvider.overrideWithValue(h.settings),
        ],
      );
      daemon.read(cliHostControlProvider).recheck = () => rechecks++;
      await daemon
          .read(agentControllerProvider.notifier)
          .bootstrap(watchForWake: false);
      bridge = ControllerAgentBridge(daemon);
      final listener = _Listener();
      server = MuxServer(
        sessions: FakeLocalSessions(),
        secret: _secret,
        self: const MuxPeerInfo(
          protocol: kMuxProtocol,
          app: 't',
          instance: 'i',
        ),
        agent: bridge,
        onQuit: () async {},
      )..serve(listener);
      final (a, b) = MemoryMuxTransport.pair();
      listener.push(b);
      final peer = await clientHandshake(
        a,
        secret: _secret,
        app: 't',
        role: 'ui',
      );
      client = MuxClient(a, early: peer.early);
      uiSettings = InMemorySettingsStore();
      ui = ProviderContainer.test(
        overrides: [
          agentControllerProvider.overrideWith(
            () => RemoteAgentController(client),
          ),
          settingsStoreProvider.overrideWithValue(uiSettings),
        ],
      );
      await ui.read(agentControllerProvider.notifier).bootstrap();
    });

    tearDown(() async {
      await server.close();
      bridge.close();
    });

    AgentControllerBase uiAgent() => ui.read(agentControllerProvider.notifier);

    test(
      'the UI toggles a daemon key: it goes through agent.call, the daemon '
      'writes it, agent.state brings it back; the UI store stays empty',
      () async {
        expect(ui.read(agentControllerProvider).keepAwake, isTrue);
        await uiAgent().setKeepAwake(false);
        await uiAgent().setNotifyThreshold(60);
        await uiAgent().setCliControlEnabled(false);
        await uiAgent().setCliAllowExternal(true);
        await uiAgent().setSshRemoteHook(false);
        await pumpEventQueue(times: 50);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        // The daemon's store has every value.
        expect(h.settings.values[SettingKeys.keepAwake], isFalse);
        expect(h.settings.ints[SettingKeys.notifyThreshold], 60);
        expect(h.settings.values[SettingKeys.cliControlEnabled], isFalse);
        expect(h.settings.values[SettingKeys.cliAllowExternal], isTrue);
        expect(h.settings.values[SettingKeys.sshRemoteHook], isFalse);
        // The UI process wrote nothing to its own.
        expect(uiSettings.values, isEmpty);
        expect(uiSettings.ints, isEmpty);
        expect(uiSettings.strings, isEmpty);
        // And its view is the daemon's, not a cached copy.
        final s = ui.read(agentControllerProvider);
        expect(s.keepAwake, isFalse);
        expect(s.notifyThresholdSeconds, 60);
        expect(s.cliControlEnabled, isFalse);
        expect(s.cliAllowExternal, isTrue);
        expect(s.sshRemoteHook, isFalse);
        // The CLI host in the daemon was told (twice: the two CLI switches).
        expect(rechecks, 2);
      },
    );

    test('the daemon changes a key on its own (its tray): the UI sees it '
        'without asking', () async {
      await daemon.read(agentControllerProvider.notifier).setNotifyThreshold(0);
      await daemon
          .read(agentControllerProvider.notifier)
          .setDesktopNotifications(false);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue(times: 50);
      final s = ui.read(agentControllerProvider);
      expect(s.notifyThresholdSeconds, 0);
      expect(s.desktopNotifications, isFalse);
      expect(uiSettings.ints, isEmpty);
    });

    test('a daemon-side setting error is an error for the caller, not a '
        'silent success', () async {
      h.settings.fail = true;
      await expectLater(
        uiAgent().setCliControlEnabled(false),
        throwsA(isA<MuxRemoteException>()),
      );
    });
  });
}
