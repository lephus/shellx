import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../../support/fake_local_sessions.dart';

/// The window's tab list and sidebar over [local] (A7 Tasks 6–9), English
/// strings, in-memory settings; [overrides] come last and win. Disposed
/// at the end of the test.
ProviderContainer cliContainer(
  FakeLocalSessions local, {
  List<Override> overrides = const [],
}) {
  final c = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ...overrides,
    ],
  );
  c.read(terminalTabsProvider);
  c.read(sidebarWorkspacesProvider);
  return c;
}

/// Pane area where no pane can be split either way (A3 D4): a 20×5 pane
/// needs 176×100 px.
PaneMetrics tinyPaneMetrics() => const PaneMetrics(
  area: Size(300, 150),
  minPane: Size(176, 100),
  divider: 1,
);
