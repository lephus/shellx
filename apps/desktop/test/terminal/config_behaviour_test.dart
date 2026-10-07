import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/terminal/user_commands.dart';
import 'package:xterm/core.dart' show TerminalKey;

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryConfigFs fs;
  late FakeLocalSessions local;
  late ProviderContainer c;

  setUp(() {
    fs = MemoryConfigFs();
    local = FakeLocalSessions();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(TestHarness().services()),
        localSessionsProvider.overrideWithValue(local),
        ...configOverrides(fs),
      ],
    );
    c.listen(terminalTabsProvider, (_, _) {});
  });
  tearDown(() => c.dispose());

  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);
  TerminalTabsState state() => c.read(terminalTabsProvider);
  Future<void> config(String text) async {
    fs.write(testConfigPaths().shellx, text);
    await loadConfig(c);
  }

  test(
    'scrollback-limit applies to panes opened after the load (D17)',
    () async {
      await tabs().openTab();
      expect(state().selected!.focused.terminal.maxLines, 10000);
      await config('scrollback-limit = 2000\n');
      await tabs().openTab();
      expect(state().selected!.focused.terminal.maxLines, 2000);
      expect(state().tabs.first.focused.terminal.maxLines, 10000);
    },
  );

  test('working-directory: home, a path, inherit (D21)', () async {
    await tabs().openTab();
    expect(local.openCwds.last, isNull);
    await config('working-directory = /tmp/w\n');
    await tabs().openTab();
    expect(local.openCwds.last, '/tmp/w');
    await config('working-directory = inherit\n');
    local.setCwd(state().selected!.focused.id, '/repo'); // A2 OSC 7 in the fake
    await tabs().openTab();
    expect(local.openCwds.last, '/repo');
  });

  test('inherit never takes an SSH pane\'s folder (A8 D5)', () async {
    await config('working-directory = inherit\n');
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        cwd: '/tmp',
        remote: SessionRemote(
          launch: SshLaunch(SshTarget.parse('devbox')!),
          connected: true,
        ),
      ),
    );
    local.add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpEventQueue();
    tabs().focusPane(1);
    expect(tabs().newTabCwd(), isNull);
    tabs().focusPane(2);
    local.setCwd(2, '/repo');
    expect(tabs().newTabCwd(), '/repo');
    await tabs().openTab(launch: SshLaunch(SshTarget.parse('devbox')!));
    expect(local.openCwds.last, isNull);
  });

  test(
    'user commands paste and press Enter; snippets only paste (D35)',
    () async {
      await tabs().openTab();
      final id = state().selected!.focused.id;
      final entry = ConfigEntry(file: '/c', line: 1, key: 'command', value: '');
      expect(
        runUserCommand(
          state(),
          UserCommand(
            name: 'Lint',
            text: 'npm run lint',
            enter: true,
            origin: entry,
          ),
        ),
        CommandRun.ran,
      );
      expect(local.views[id]!.writes.join(), 'npm run lint\r');
      local.views[id]!.writes.clear();
      runUserCommand(
        state(),
        UserCommand(
          name: 'S',
          text: 'git status\n',
          enter: false,
          origin: entry,
        ),
      );
      expect(local.views[id]!.writes.join(), 'git status\r');
    },
  );

  test('no live terminal: noTerminal', () async {
    final entry = ConfigEntry(file: '/c', line: 1, key: 'command', value: '');
    expect(
      runUserCommand(
        state(),
        UserCommand(name: 'L', text: 'x', enter: true, origin: entry),
      ),
      CommandRun.noTerminal,
    );
    expect(sendTextToFocused(state(), 'x'), CommandRun.noTerminal);
  });

  test('text: bytes go out raw, as typed input (D31)', () async {
    await tabs().openTab();
    final id = state().selected!.focused.id;
    expect(sendTextToFocused(state(), '\x1b[A'), CommandRun.ran);
    expect(local.views[id]!.writes.join(), '\x1b[A');
  });

  test(
    'a created terminal sends Option+F as ESC f only after a reload',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tabs().openTab();
      final tab = state().selected!;
      final writes = local.views[tab.focused.id]!.writes;
      tab.terminal.keyInput(TerminalKey.keyF, alt: true);
      expect(writes, isEmpty);
      await config('macos-option-as-alt = true\n');
      tab.terminal.keyInput(TerminalKey.keyF, alt: true);
      expect(writes.join(), '\x1bf');
    },
  );

  test('Option as Alt is read at key time (live)', () async {
    await tabs().openTab();
    expect(c.read(shellxConfigProvider).config.optionAsAlt, OptionAsAlt.off);
    await config('macos-option-as-alt = true\n');
    expect(c.read(shellxConfigProvider).config.optionAsAlt, OptionAsAlt.both);
  });
}
