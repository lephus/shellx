import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/desktop_notifications.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../../support/fake_local_sessions.dart';
import '../../support/fakes.dart';

final _systemNotifiers = Expando<RecordingNotifier>();

/// The window's tab list and sidebar over [local] (A7 Tasks 6–9), English
/// strings, in-memory settings, and A4's system notifications wired as
/// `main.dart` does into a [RecordingNotifier] ([systemNotificationsSent]);
/// [overrides] come last and win. Disposed at the end of the test.
ProviderContainer cliContainer(
  FakeLocalSessions local, {
  List<Override> overrides = const [],
}) {
  final settings = InMemorySettingsStore();
  final l10n = lookupAppLocalizations(const Locale('en'));
  final c = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(l10n),
      settingsStoreProvider.overrideWithValue(settings),
      ...overrides,
    ],
  );
  c.read(terminalTabsProvider);
  c.read(sidebarWorkspacesProvider);
  final notifier = RecordingNotifier();
  final notifications = DesktopNotifications(
    notifier: notifier,
    settings: settings,
    l10n: l10n,
    onOpen: (_) {},
    viewOf: (id) => attentionView(c, id),
    log: (_) {},
  );
  listenForDesktopNotifications(
    container: c,
    notifications: notifications,
    l10n: l10n,
  );
  addTearDown(notifications.dispose);
  _systemNotifiers[c] = notifier;
  return c;
}

/// The system notifications [c] posted (A4 D14–D15), oldest first.
List<ShownNotification> systemNotificationsSent(ProviderContainer c) =>
    _systemNotifiers[c]!.shown;

/// Pane area where no pane can be split either way (A3 D4): a 20×5 pane
/// needs 176×100 px.
PaneMetrics tinyPaneMetrics() => const PaneMetrics(
  area: Size(300, 150),
  minPane: Size(176, 100),
  divider: 1,
);

/// Lets a pane's output reach its terminal ([TerminalFeed] writes on a
/// later turn).
Future<void> pumpFeed() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
