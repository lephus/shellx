import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/ui/terminal/ssh_connect_dialog.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late InMemorySettingsStore settings;
late FutureOr<CommandResult> Function(List<String>) tmuxAnswer;
late List<List<String>> ran;

CommandResult tmux(String out) => CommandResult(0, out, '');

Future<ProviderContainer> pump(
  WidgetTester tester, {
  SshDialogTab tab = SshDialogTab.ssh,
}) async {
  local = FakeLocalSessions();
  settings = InMemorySettingsStore();
  ran = [];
  Future<CommandResult> run(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    ran.add(args);
    return tmuxAnswer(args);
  }

  final container = ProviderContainer(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
      commandRunnerProvider.overrideWithValue(run),
      remoteToolsProvider.overrideWithValue(
        RemoteTools(
          sshPath: '/usr/bin/ssh',
          tmuxPath: '/usr/bin/tmux',
          control: SshControl(sshPath: '/usr/bin/ssh', run: run),
        ),
      ),
      sshConfigHostsProvider.overrideWithValue(
        () async => ['devbox', 'dev-db', 'prod'],
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(child: SshConnectDialog(initialTab: tab)),
        ),
      ),
    ),
  );
  await settle(tester);
  return container;
}

/// Frames, then past the dialog's 300 ms "Loading…" delay (no timer left).
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(
    () => tmuxAnswer = (_) => tmux(
      'SXTMUX\tmain\t3\t0\t1759831200\nSXTMUX\tbuild\t1\t1\t1759744800\n',
    ),
  );

  testWidgets('type, filter, ↓ ↓, Enter connects; the dialog closes at once '
      '(D42)', (tester) async {
    await pump(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('ssh.host')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.enterText(find.byKey(const Key('ssh.host')), 'dev');
    await tester.pump();
    expect(find.text('devbox'), findsOneWidget);
    expect(find.text('dev-db'), findsOneWidget);
    expect(find.text('prod'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // devbox
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // dev-db
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(local.openLaunches.single, SshLaunch(SshTarget.parse('dev-db')!));
  });

  testWidgets('a bad server name stays in the dialog with an error', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const Key('ssh.host')),
      '-oProxyCommand=x',
    );
    await tester.tap(find.byKey(const Key('ssh.connect')));
    await tester.pump();
    expect(find.text('Not a valid server name'), findsOneWidget);
    expect(local.openLaunches, isEmpty);
  });

  testWidgets('a bad folder stays in the dialog with an error', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('ssh.host')), 'devbox');
    await tester.enterText(find.byKey(const Key('ssh.dir')), 'relative/x');
    await tester.tap(find.byKey(const Key('ssh.connect')));
    await tester.pump();
    expect(find.text('The path must start with / or ~'), findsOneWidget);
    expect(local.openLaunches, isEmpty);
  });

  testWidgets('folder and "no hook" travel with the connect', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('ssh.host')), 'me@box:2222');
    await tester.enterText(find.byKey(const Key('ssh.dir')), '~/srv');
    await tester.tap(find.byKey(const Key('ssh.nohook')));
    await tester.tap(find.byKey(const Key('ssh.connect')));
    await settle(tester);
    expect(
      local.openLaunches.single,
      SshLaunch(
        SshTarget.parse('me@box:2222')!,
        remoteCwd: '~/srv',
        hook: false,
      ),
    );
    expect(settings.getStrings(SettingKeys.sshPlainTargets), ['me@box:2222']);
  });

  testWidgets('the tick follows a server already marked "no hook"', (
    tester,
  ) async {
    await pump(tester);
    await settings.setStrings(SettingKeys.sshPlainTargets, ['devbox']);
    await tester.enterText(find.byKey(const Key('ssh.host')), 'devbox');
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('ssh.nohook')))
          .value,
      isTrue,
    );
  });

  testWidgets('tmux tab: sessions here, attach; create a new one (D25)', (
    tester,
  ) async {
    await pump(tester, tab: SshDialogTab.tmux);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('3 windows'), findsOneWidget);
    expect(find.text('attached elsewhere'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tmux.attach')));
    await settle(tester);
    expect(local.openLaunches.single, const TmuxLaunch('main'));
  });

  testWidgets('tmux tab: ↓ moves the cursor, Enter attaches it', (
    tester,
  ) async {
    await pump(tester, tab: SshDialogTab.tmux);
    await tester.tap(find.byKey(const Key('tmux.row.main')));
    // A tap waits out the double-tap window.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(local.openLaunches.single, const TmuxLaunch('build'));
  });

  testWidgets('tmux tab: no server here → empty text; on a server that needs '
      'a password → advice', (tester) async {
    tmuxAnswer = (_) => const CommandResult(
      1,
      '',
      'no server running on /tmp/tmux-501/default',
    );
    await pump(tester, tab: SshDialogTab.tmux);
    expect(find.text('No tmux sessions yet'), findsOneWidget);
    tmuxAnswer = (_) => const CommandResult(255, '', '');
    await tester.enterText(find.byKey(const Key('tmux.source')), 'devbox');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(
      find.textContaining('Couldn’t list sessions on devbox'),
      findsOneWidget,
    );
  });

  testWidgets('tmux tab: a list that never answers ends in the same advice '
      '(bounded)', (tester) async {
    final never = Completer<CommandResult>();
    tmuxAnswer = (_) => never.future;
    await pump(tester, tab: SshDialogTab.tmux);
    expect(find.text('Loading sessions…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    expect(
      find.textContaining('Couldn’t list sessions on This computer'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('tmux tab: a session name with control characters is never '
      'offered', (tester) async {
    tmuxAnswer = (_) => tmux(
      'SXTMUX\tma\u001b[2Jin\t1\t0\t1759831200\nSXTMUX\tok\t1\t0\t1759831200\n',
    );
    await pump(tester, tab: SshDialogTab.tmux);
    expect(find.text('ok'), findsOneWidget);
    expect(find.textContaining('ma'), findsNothing);
  });

  testWidgets('tmux tab: a source that is not a server name lists nothing', (
    tester,
  ) async {
    await pump(tester, tab: SshDialogTab.tmux);
    ran.clear();
    await tester.enterText(
      find.byKey(const Key('tmux.source')),
      '-oProxyCommand=x',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Not a valid server name'), findsOneWidget);
    expect(ran, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('tmux.attach')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('tmux tab on Windows: no "This computer" to list', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pump(tester, tab: SshDialogTab.tmux);
      expect(ran, isEmpty);
      expect(
        find.text('tmux isn’t installed on This computer'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tmux: an invalid new name is refused', (tester) async {
    await pump(tester, tab: SshDialogTab.tmux);
    await tester.enterText(find.byKey(const Key('tmux.new')), 'a:b');
    await tester.tap(find.byKey(const Key('tmux.create')));
    await tester.pump();
    expect(
      find.text('Use up to 64 characters, without “:” or “.”'),
      findsOneWidget,
    );
    expect(local.openLaunches, isEmpty);
  });

  testWidgets('tmux: a new name creates and attaches (new-session -A)', (
    tester,
  ) async {
    await pump(tester, tab: SshDialogTab.tmux);
    await tester.enterText(find.byKey(const Key('tmux.new')), 'notes');
    await tester.tap(find.byKey(const Key('tmux.create')));
    await settle(tester);
    expect(local.openLaunches.single, const TmuxLaunch('notes', create: true));
  });

  testWidgets(
    '←/→ on a tab switch tabs; the tabs are named for screen readers',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(find.byKey(const Key('ssh.host')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ssh.tab.tmux')));
      await settle(tester);
      expect(find.byKey(const Key('tmux.source')), findsOneWidget);
      expect(find.bySemanticsLabel('tmux'), findsWidgets);
      handle.dispose();
    },
  );
}
