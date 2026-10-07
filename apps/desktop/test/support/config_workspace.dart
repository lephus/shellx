import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import 'config_harness.dart';
import 'fake_local_sessions.dart';
import 'fakes.dart';
import 'memory_config_fs.dart';

/// The workspace with one open tab and [config] loaded (A9 tests).
Future<
  ({ProviderContainer container, FakeLocalSessions local, MemoryConfigFs fs})
>
pumpConfiguredWorkspace(
  WidgetTester tester, {
  String config = '',
  TargetPlatform? platform,
  List<Override> extra = const [],
  Locale locale = const Locale('en'),
}) async {
  final fs = MemoryConfigFs();
  if (config.isNotEmpty) fs.write(testConfigPaths().shellx, config);
  final local = FakeLocalSessions();
  final h = TestHarness(settings: {'onboarding_done': true});
  final container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      // A10 D20: these tests check layout, not settling: sizes go at once.
      resizeSettleProvider.overrideWithValue(Duration.zero),
      ...configOverrides(fs, platform: platform ?? defaultTargetPlatform),
      ...extra,
    ],
  );
  await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  await loadConfig(container);
  container.read(windowRouterProvider.notifier).showTerminal();
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(workspaceApp(container, locale: locale));
  await container.read(terminalTabsProvider.notifier).openTab();
  await tester.pumpAndSettle();
  return (container: container, local: local, fs: fs);
}

/// Bootstrap starts timers: tear the tree down before the test ends.
Future<void> disposeWorkspace(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

/// The window around the workspace page (a test may pump it again to model
/// the window being closed and reopened).
Widget workspaceApp(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildDesktopTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: const Scaffold(body: TerminalWorkspacePage()),
  ),
);
