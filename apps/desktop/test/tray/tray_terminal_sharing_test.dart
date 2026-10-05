import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';
import 'package:shellx_desktop/src/terminal_sharing/confirm_text.dart';
import 'package:shellx_desktop/src/terminal_sharing/powershell.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/ui/window_host.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';

final vi = lookupAppLocalizations(const Locale('vi'));
final en = lookupAppLocalizations(const Locale('en'));

DesktopSessionSummary terminal(
  int id, {
  String? mobile,
  String title = 'npm run dev',
}) => DesktopSessionSummary(
  id: id,
  index: 1,
  app: 'Terminal',
  title: title,
  shell: 'zsh',
  createdAt: DateTime(2026, 10, 5),
  attachedMobileId: mobile,
  connected: true,
);

AgentViewState signedIn(TerminalSharingView sharing) => AgentViewState(
  phase: AuthPhase.signedIn,
  email: 'user@email.com',
  relay: RelayConnectionState.connected,
  terminalSharing: sharing,
);

List<String?> labels(Menu menu) => [
  for (final item in menu.items!) item.type == 'separator' ? '---' : item.label,
];

PlannedFile planned(String path, {bool exists = true}) => PlannedFile(
  ConfigTarget(path: path, block: 'b', create: true, newFileEol: '\n'),
  exists: exists,
);

void main() {
  group('menu', () {
    test('not offered: no switch, no terminals', () {
      final menu = buildTrayMenu(
        signedIn(const TerminalSharingView()),
        vi,
        TrayMenuIds(),
      );
      expect(menu.getMenuItem(TrayKeys.terminalSharing), isNull);
      expect(menu.getMenuItem(TrayKeys.desktopTerminals), isNull);
    });

    test(
      'offered and off: the switch, unchecked, after the startup switch',
      () {
        final menu = buildTrayMenu(
          signedIn(const TerminalSharingView(available: true)),
          vi,
          TrayMenuIds(),
        );
        final item = menu.getMenuItem(TrayKeys.terminalSharing)!;
        expect(item.label, 'Chia sẻ terminal với điện thoại (thử nghiệm)');
        expect(item.type, 'checkbox');
        expect(item.checked, isFalse);
        final l = labels(menu);
        expect(l.indexOf(item.label), l.indexOf('Khởi động cùng hệ thống') + 1);
        expect(menu.getMenuItem(TrayKeys.desktopTerminals), isNull);
      },
    );

    test(
      'on: "Terminal trên máy tính (N)" lists app — title, 📱 when a phone is attached',
      () {
        final menu = buildTrayMenu(
          signedIn(
            TerminalSharingView(
              available: true,
              enabled: true,
              sessions: [
                terminal(7, mobile: 'm1'),
                terminal(8, title: ''),
              ],
            ),
          ),
          vi,
          TrayMenuIds(),
        );
        expect(menu.getMenuItem(TrayKeys.terminalSharing)!.checked, isTrue);
        final group = menu.getMenuItem(TrayKeys.desktopTerminals)!;
        expect(group.label, 'Terminal trên máy tính (2)');
        expect(
          labels(menu).indexOf(group.label),
          labels(menu).indexOf('Phiên đang hoạt động (0)') + 1,
        );
        final attached = menu.getMenuItem(TrayKeys.desktopTerminal(7))!;
        expect(attached.label, 'Terminal — npm run dev 📱');
        final disconnect = attached.submenu!.items!.single;
        expect(disconnect.key, TrayKeys.disconnectPhone(7));
        expect(disconnect.label, 'Ngắt điện thoại');
        expect(disconnect.disabled, isFalse);
        final idle = menu.getMenuItem(TrayKeys.desktopTerminal(8))!;
        expect(idle.label, 'Terminal — zsh');
        expect(idle.submenu!.items!.single.disabled, isTrue);
        // Never an item that ends the terminal.
        expect(attached.submenu!.items, hasLength(1));
      },
    );

    test('on with no terminal: the group is shown, disabled', () {
      final menu = buildTrayMenu(
        signedIn(const TerminalSharingView(available: true, enabled: true)),
        vi,
        TrayMenuIds(),
      );
      final group = menu.getMenuItem(TrayKeys.desktopTerminals)!;
      expect(group.label, 'Terminal trên máy tính (0)');
      expect(group.disabled, isTrue);
    });

    test('needs setup: the warning item; busy disables the switch', () {
      final menu = buildTrayMenu(
        signedIn(
          const TerminalSharingView(
            available: true,
            enabled: true,
            needsSetup: true,
            busy: true,
          ),
        ),
        vi,
        TrayMenuIds(),
      );
      final warning = menu.getMenuItem(TrayKeys.terminalSharingSetup)!;
      expect(warning.label, '⚠ Chia sẻ terminal cần thiết lập lại…');
      expect(menu.getMenuItem(TrayKeys.terminalSharing)!.disabled, isTrue);
    });

    test('keys map to actions', () {
      expect(
        trayActionForKey(TrayKeys.terminalSharing),
        isA<ToggleTerminalSharing>(),
      );
      expect(
        trayActionForKey(TrayKeys.terminalSharingSetup),
        isA<SetUpTerminalSharing>(),
      );
      expect(
        (trayActionForKey(TrayKeys.disconnectPhone(9))!
                as DisconnectDesktopPhone)
            .id,
        9,
      );
      expect(trayActionForKey('desktop_disconnect:x'), isNull);
      expect(trayActionForKey(TrayKeys.desktopTerminal(9)), isNull);
    });
  });

  group('confirmation text', () {
    test('macOS: exact files, new files marked, binary path, R2 note', () {
      final body = sharingConfirmBody(
        SharingPlan(
          files: [
            planned('/Users/phu/.zshrc', exists: false),
            planned('/Users/phu/.bashrc'),
          ],
          bashSkipped: false,
          powerShells: const [],
        ),
        vi,
        windows: false,
        binaryPath:
            '/Users/phu/Library/Application Support/ShellX/bin/shellx-term',
      );
      expect(body, contains('Các cửa sổ đang mở không được chia sẻ.'));
      expect(body, contains('• /Users/phu/.zshrc (file mới)'));
      expect(body, contains('• /Users/phu/.bashrc\n'));
      expect(
        body,
        contains(
          '/Users/phu/Library/Application Support/ShellX/bin/shellx-term',
        ),
      );
      expect(body, contains('Terminal.app'));
      expect(body, isNot(contains('bash không được chia sẻ')));
    });

    test('macOS without bash files says bash is skipped', () {
      final body = sharingConfirmBody(
        SharingPlan(
          files: [planned('/Users/phu/.zshrc')],
          bashSkipped: true,
          powerShells: const [],
        ),
        en,
        windows: false,
        binaryPath: '/b',
      );
      expect(body, contains('bash windows are not shared'));
    });

    test('Windows: script policy per PowerShell, no Terminal.app note', () {
      const blocked = PowerShellInstall(
        name: 'Windows PowerShell',
        executable: 'powershell.exe',
        profilePath: r'C:\Users\a\Documents\WindowsPowerShell\profile.ps1',
        policy: ScriptPolicy.blocked,
      );
      const gp = PowerShellInstall(
        name: 'PowerShell 7',
        executable: 'pwsh.exe',
        profilePath: r'C:\Users\a\Documents\PowerShell\profile.ps1',
        policy: ScriptPolicy.blockedByGroupPolicy,
      );
      final plan = SharingPlan(
        files: [planned(blocked.profilePath)],
        bashSkipped: false,
        powerShells: const [blocked, gp],
      );
      final body = sharingConfirmBody(
        plan,
        en,
        windows: true,
        binaryPath: r'C:\L\ShellX\bin\shellx-term.exe',
      );
      expect(
        body,
        contains('Windows PowerShell: running scripts is not allowed'),
      );
      expect(
        body,
        contains('PowerShell 7: the script policy is set by your organization'),
      );
      expect(body, contains('PowerShell window will open a little slower'));
      expect(body, isNot(contains('Terminal.app')));
      expect(fixablePowerShells(plan), [blocked]);
    });
  });

  group('actions', () {
    late TestHarness h;
    late FakeSharingSetup setup;
    late ProviderContainer container;

    WindowState window() => container.read(windowRouterProvider);
    TrayActions tray() => container.read(trayActionsProvider);
    TerminalSharingView sharing() =>
        container.read(agentControllerProvider).terminalSharing;

    Future<void> boot({
      Map<String, bool>? settings,
      bool windows = false,
    }) async {
      setup = FakeSharingSetup(windows: windows);
      h = TestHarness(
        settings: {'onboarding_done': true, ...?settings},
        sharingSetup: setup,
      );
      container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      await h.seedSignedIn();
      await container
          .read(agentControllerProvider.notifier)
          .bootstrap(watchForWake: false);
    }

    Future<void> answer(bool yes) async {
      await pumpEventQueue();
      window().confirm!.complete(yes);
      await pumpEventQueue();
    }

    test(
      'turning on asks first (long, not destructive); cancel changes nothing',
      () async {
        await boot();
        final done = tray().handle(const ToggleTerminalSharing());
        await pumpEventQueue();
        final request = window().confirm!;
        expect(request.title, h.l10n.confirmSharingTitle);
        expect(request.body, contains('/Users/phu/.zshrc'));
        expect(request.long, isTrue);
        expect(request.destructive, isFalse);
        expect(windowSizeFor(window()), const Size(560, 560));
        await answer(false);
        await done;
        expect(setup.calls, isNot(contains('enable')));
        expect(sharing().enabled, isFalse);
      },
    );

    test('confirming installs and starts sharing', () async {
      await boot();
      final done = tray().handle(const ToggleTerminalSharing());
      await answer(true);
      await done;
      expect(setup.calls, contains('enable'));
      expect(sharing().enabled, isTrue);
      expect(h.runtime.sharingCalls, [true]);
    });

    test('turning off needs no confirmation', () async {
      await boot(settings: {SettingKeys.terminalSharing: true});
      await tray().handle(const ToggleTerminalSharing());
      expect(window().confirm, isNull);
      expect(setup.calls, contains('disable'));
      expect(sharing().enabled, isFalse);
    });

    test('"set up again" runs the enable flow', () async {
      await boot(settings: {SettingKeys.terminalSharing: true});
      final done = tray().handle(const SetUpTerminalSharing());
      await answer(true);
      await done;
      expect(setup.calls, contains('enable'));
    });

    test('"Disconnect phone" goes to the runtime', () async {
      await boot(settings: {SettingKeys.terminalSharing: true});
      await tray().handle(const DisconnectDesktopPhone(5));
      expect(h.runtime.disconnectedPhones, [5]);
    });

    group('Windows script policy', () {
      const blocked = PowerShellInstall(
        name: 'Windows PowerShell',
        executable: 'powershell.exe',
        profilePath: r'C:\p.ps1',
        policy: ScriptPolicy.blocked,
      );

      Future<void> run({required bool allow}) async {
        await boot(windows: true);
        setup.plan = SharingPlan(
          files: [planned(blocked.profilePath)],
          bashSkipped: false,
          powerShells: const [blocked],
        );
        final done = tray().handle(const ToggleTerminalSharing());
        await answer(true);
        expect(
          window().confirm!.confirmLabel,
          h.l10n.confirmAllowScriptsAction,
        );
        expect(
          window().confirm!.body,
          contains('Set-ExecutionPolicy -Scope CurrentUser RemoteSigned'),
        );
        await answer(allow);
        await done;
      }

      test('the policy changes only when the button is pressed', () async {
        await run(allow: true);
        expect(setup.allowedScripts, [blocked]);
        expect(setup.calls, contains('enable'));
      });

      test('declining keeps the policy and still turns sharing on', () async {
        await run(allow: false);
        expect(setup.allowedScripts, isEmpty);
        expect(setup.calls, contains('enable'));
      });
    });
  });
}
