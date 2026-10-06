import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

late TestHarness h;
late FakeLocalSessions local;
late ProviderContainer container;

const testHome = '/Users/test';

Future<void> pumpSidebar(
  WidgetTester tester, {
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  h = TestHarness(settings: {'onboarding_done': true});
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      localSessionsProvider.overrideWithValue(local),
      homeDirectoryProvider.overrideWithValue(testHome),
    ],
  );
  await h.seedSignedIn();
  await container
      .read(agentControllerProvider.notifier)
      .bootstrap(watchForWake: false);
  tester.view.physicalSize = const Size(1100, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          theme: buildDesktopTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: TerminalWorkspacePage()),
        ),
      ),
    ),
  );
  await tester.pump();
}

TerminalTabsState tabs() => container.read(terminalTabsProvider);
SidebarState sidebar() => container.read(sidebarWorkspacesProvider);
SidebarWorkspaces workspaces() =>
    container.read(sidebarWorkspacesProvider.notifier);
Finder row(int id) => find.byKey(ValueKey('tab.$id'));

/// macOS only (⌘ labels); the body tears the container down itself
/// (bootstrap leaves a periodic timer, as in terminal_workspace_test).
void testSidebar(
  String description,
  Future<void> Function(WidgetTester) body,
) => testWidgets(
  description,
  variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }
  },
);

void setUpSidebar() => setUp(() => local = FakeLocalSessions());

bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;
