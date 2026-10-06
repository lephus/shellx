import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/cli/cli_install.dart';
import 'package:shellx_desktop/src/cli/cli_service.dart';
import 'package:shellx_desktop/src/cli/cli_settings.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';

final vi = lookupAppLocalizations(const Locale('vi'));
final en = lookupAppLocalizations(const Locale('en'));

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final sub = i.submenu?.items;
    if (sub != null) {
      final hit = find(sub, key);
      if (hit != null) return hit;
    }
  }
  return null;
}

final class FakePathInstaller implements PathInstaller {
  bool isInstalled = false;
  PathInstallResult next = PathInstallResult.installed;
  final calls = <String>[];

  @override
  Future<bool> get installed async => isInstalled;

  @override
  Future<PathInstallResult> install() async {
    calls.add('install');
    if (next == PathInstallResult.installed) isInstalled = true;
    return next;
  }

  @override
  Future<PathInstallResult> uninstall() async {
    calls.add('uninstall');
    if (next == PathInstallResult.installed) isInstalled = false;
    return next;
  }
}

void main() {
  for (final signedIn in [false, true]) {
    test('"Dòng lệnh" right after "Thông báo" (signedIn: $signedIn; A6 '
        'absent: no "Trình duyệt")', () {
      final state = signedIn
          ? const AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c')
          : const AgentViewState(phase: AuthPhase.signedOut);
      final items = buildTrayMenu(
        state,
        vi,
        TrayMenuIds(),
        local: const TrayLocalState(),
      ).items!;
      final notifications = items.indexWhere(
        (i) => i.key == TrayKeys.notifications,
      );
      final commandLine = items.indexWhere(
        (i) => i.key == TrayKeys.commandLine,
      );
      expect(notifications, greaterThanOrEqualTo(0));
      expect(commandLine, notifications + 1);
      final sub = items[commandLine];
      expect(sub.label, 'Dòng lệnh');
      expect(sub.submenu!.items!.map((i) => i.key), [
        TrayKeys.cliControl,
        TrayKeys.cliAllowExternal,
        TrayKeys.cliPath,
        TrayKeys.cliSkills,
      ]);
      // Defaults: control on, other terminals off, not installed.
      final control = find(items, TrayKeys.cliControl)!;
      expect(control.type, 'checkbox');
      expect(control.label, 'Cho phép điều khiển ShellX bằng dòng lệnh');
      expect(control.checked, isTrue);
      final external = find(items, TrayKeys.cliAllowExternal)!;
      expect(external.type, 'checkbox');
      expect(external.label, 'Cho phép terminal khác');
      expect(external.checked, isFalse);
      expect(
        find(items, TrayKeys.cliPath)!.label,
        'Cài lệnh shellx cho mọi terminal…',
      );
      expect(
        find(items, TrayKeys.cliSkills)!.label,
        'Sao chép lệnh cài skill cho agent',
      );
    });
  }

  test('the menu follows the CLI settings', () {
    final items = buildTrayMenu(
      const AgentViewState(phase: AuthPhase.signedOut),
      en,
      TrayMenuIds(),
      local: const TrayLocalState(
        cliControlEnabled: false,
        cliAllowExternal: true,
        cliPathInstalled: true,
      ),
    ).items!;
    expect(find(items, TrayKeys.commandLine)!.label, 'Command line');
    expect(find(items, TrayKeys.cliControl)!.checked, isFalse);
    expect(find(items, TrayKeys.cliAllowExternal)!.checked, isTrue);
    expect(
      find(items, TrayKeys.cliAllowExternal)!.label,
      'Allow other terminals',
    );
    expect(
      find(items, TrayKeys.cliPath)!.label,
      'Remove the shellx command from other terminals',
    );
  });

  test('keys map to actions', () {
    expect(trayActionForKey(TrayKeys.cliControl), isA<ToggleCliControl>());
    expect(
      trayActionForKey(TrayKeys.cliAllowExternal),
      isA<ToggleCliAllowExternal>(),
    );
    expect(trayActionForKey(TrayKeys.cliPath), isA<ToggleCliPath>());
    expect(trayActionForKey(TrayKeys.cliSkills), isA<CopySkillsCommand>());
  });

  group('actions', () {
    late TestHarness h;
    late ProviderContainer c;
    late FakePathInstaller installer;
    late List<String> copied;
    late int rechecks;
    final paths = CliPaths.forTest(
      dir: '/Users/me/Library/Application Support/ShellX/cli',
      binary: '/Users/me/Library/Application Support/ShellX/cli/shellx',
      bundled: '/b',
    );

    setUp(() {
      h = TestHarness();
      installer = FakePathInstaller();
      copied = [];
      rechecks = 0;
      c = ProviderContainer.test(
        overrides: [
          desktopServicesProvider.overrideWithValue(h.services()),
          cliPathsProvider.overrideWithValue(paths),
          cliPathInstallerProvider.overrideWithValue(installer),
          cliClipboardProvider.overrideWithValue((text) async {
            copied.add(text);
          }),
        ],
      );
      c.read(cliSettingsProvider.notifier).onChanged = () => rechecks++;
      c.listen(trayLocalStateProvider, (_, _) {});
    });

    TrayLocalState local() => c.read(trayLocalStateProvider);
    TabNotice? notice() => c.read(terminalTabsProvider).notice;
    Future<void> tap(TrayAction a) => c.read(trayActionsProvider).handle(a);

    test('the switch: stored, the menu re-renders, the host rechecks at '
        'once (D26)', () async {
      expect(local().cliControlEnabled, isTrue);
      await tap(const ToggleCliControl());
      expect(h.settings.values[SettingKeys.cliControlEnabled], isFalse);
      expect(local().cliControlEnabled, isFalse);
      expect(rechecks, 1);
      await tap(const ToggleCliControl());
      expect(h.settings.values[SettingKeys.cliControlEnabled], isTrue);
      expect(local().cliControlEnabled, isTrue);
      expect(rechecks, 2);
      expect(c.read(windowRouterProvider).confirm, isNull); // never asks
    });

    test('"Allow other terminals": stored, re-rendered, rechecked at once '
        '(amendment)', () async {
      expect(local().cliAllowExternal, isFalse);
      await tap(const ToggleCliAllowExternal());
      expect(h.settings.values[SettingKeys.cliAllowExternal], isTrue);
      expect(local().cliAllowExternal, isTrue);
      expect(rechecks, 1);
      await tap(const ToggleCliAllowExternal());
      expect(h.settings.values[SettingKeys.cliAllowExternal], isFalse);
      expect(local().cliAllowExternal, isFalse);
      expect(rechecks, 2);
    });

    test('the two settings stay independent of the PATH install', () async {
      await tap(const ToggleCliPath());
      expect(h.settings.values[SettingKeys.cliAllowExternal], isNull);
      expect(local().cliAllowExternal, isFalse);
      expect(rechecks, 0);
    });

    test(
      'copy skills: the command on the clipboard and a neutral toast',
      () async {
        await tap(const CopySkillsCommand());
        expect(copied, ['shellx skills install']);
        expect(notice(), isA<CliSkillsCopiedNotice>());
      },
    );

    test('install: stored only on installed; the toast says other '
        'terminals also need "Allow other terminals"', () async {
      await tap(const ToggleCliPath());
      expect(installer.calls, ['install']);
      expect(h.settings.values[SettingKeys.cliPathInstalled], isTrue);
      expect(local().cliPathInstalled, isTrue);
      expect(notice(), isA<CliPathInstalledNotice>());
      expect(c.read(windowRouterProvider).visible, isTrue);

      // Installed: the item removes it.
      await tap(const ToggleCliPath());
      expect(installer.calls, ['install', 'uninstall']);
      expect(h.settings.values[SettingKeys.cliPathInstalled], isFalse);
      expect(local().cliPathInstalled, isFalse);
    });

    test(
      'a cancelled password prompt changes nothing and says nothing',
      () async {
        installer.next = PathInstallResult.cancelled;
        await tap(const ToggleCliPath());
        expect(h.settings.values[SettingKeys.cliPathInstalled], isNull);
        expect(notice(), isNull);
        expect(c.read(windowRouterProvider).visible, isFalse);
      },
    );

    test('a failed install shows the toast with the folder to add', () async {
      installer.next = PathInstallResult.failed;
      await tap(const ToggleCliPath());
      expect(h.settings.values[SettingKeys.cliPathInstalled], isNull);
      final n = notice();
      expect(n, isA<CliPathFailedNotice>());
      expect((n! as CliPathFailedNotice).path, paths.dir);
      expect(c.read(windowRouterProvider).visible, isTrue);
    });

    test('a link removed behind the menu\'s back: the item heals', () async {
      h.settings.values[SettingKeys.cliPathInstalled] = true;
      c.invalidate(cliSettingsProvider);
      expect(local().cliPathInstalled, isTrue);
      // Not really there: "remove" finds nothing to remove and clears it.
      await tap(const ToggleCliPath());
      expect(installer.calls, ['uninstall']);
      expect(h.settings.values[SettingKeys.cliPathInstalled], isFalse);
    });
  });

  test('strings (en/vi)', () {
    expect(en.trayCliControl, 'Allow controlling ShellX from the command line');
    expect(vi.trayCliAllowExternal, 'Cho phép terminal khác');
    expect(
      en.trayCliInstallPath,
      'Install the shellx command for all terminals…',
    );
    expect(vi.trayCliRemovePath, 'Gỡ lệnh shellx khỏi terminal khác');
    expect(en.trayCliCopySkills, 'Copy the agent skill install command');
    expect(
      vi.cliSkillsCopied,
      'Đã sao chép “shellx skills install” — dán vào terminal',
    );
    expect(
      en.cliPathFailed('/x/cli'),
      'Couldn’t install the shellx command. Add /x/cli to your PATH.',
    );
    expect(
      vi.cliPathFailed('/x/cli'),
      'Không cài được lệnh shellx. Hãy thêm /x/cli vào PATH.',
    );
    expect(en.cliPathInstalled, contains('Allow other terminals'));
    expect(vi.cliPathInstalled, contains('Cho phép terminal khác'));
    expect(en.agentChip, 'Agent');
    expect(
      vi.agentChipTooltip,
      'Một chương trình đang điều khiển tab này qua dòng lệnh ShellX',
    );
    expect(en.cliAnnounceAgent('zsh'), 'An agent is controlling zsh');
    expect(vi.cliAnnounceAgent('zsh'), 'Agent đang điều khiển zsh');
  });
}
