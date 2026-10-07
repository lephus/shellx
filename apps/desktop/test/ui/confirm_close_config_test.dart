import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/close_tab.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    local = FakeLocalSessions();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(TestHarness().services()),
        localSessionsProvider.overrideWithValue(local),
      ],
    );
    c.listen(terminalTabsProvider, (_, _) {});
    await c.read(terminalTabsProvider.notifier).openTab();
  });
  tearDown(() => c.dispose());

  TerminalTab tab() => c.read(terminalTabsProvider).selected!;
  Future<void> close(ConfirmClose mode) => closeTabWithConfirm(
    tabs: c.read(terminalTabsProvider.notifier),
    router: c.read(windowRouterProvider.notifier),
    l10n: l10n,
    tab: tab(),
    confirm: mode,
  );

  test('never: a running command closes without asking (D20)', () async {
    final id = tab().id;
    local.setRunning(id, true); // A4 OSC 133;C in the fake
    await close(ConfirmClose.never);
    expect(local.closed, contains(id));
    expect(c.read(windowRouterProvider).confirm, isNull);
  });

  test('always: an idle tab asks with the new body', () async {
    final id = tab().id;
    final pending = close(ConfirmClose.always);
    await Future<void>.delayed(Duration.zero);
    final request = c.read(windowRouterProvider).confirm!;
    expect(request.body, l10n.confirmCloseAlwaysBody);
    request.complete(true);
    await pending;
    expect(local.closed, contains(id));
  });

  test('whenRunning (default) keeps A1: idle closes, running asks', () async {
    final id = tab().id;
    await close(ConfirmClose.whenRunning);
    expect(local.closed, contains(id));
  });

  test('whenRunning: a running command asks with the A1 body', () async {
    final id = tab().id;
    local.setRunning(id, true);
    await Future<void>.delayed(Duration.zero);
    final pending = close(ConfirmClose.whenRunning);
    await Future<void>.delayed(Duration.zero);
    final request = c.read(windowRouterProvider).confirm!;
    expect(request.body, l10n.confirmCloseRunningBody);
    request.complete(false);
    await pending;
    expect(local.closed, isNot(contains(id)));
  });
}
