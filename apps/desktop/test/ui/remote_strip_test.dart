import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/ssh_reconnector.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/remote_strip.dart';

import '../support/fake_local_sessions.dart';

final _clock = DateTime(2026, 10, 7, 9);

/// A reconnector whose retry table the test writes (the strip only reads it).
class _FixedRetries extends SshReconnector {
  _FixedRetries(this.table);
  final Map<int, RetryInfo> table;
  @override
  Map<int, RetryInfo> build() => table;
}

void main() {
  final devbox = SshTarget.parse('devbox')!;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required bool connected,
    int code = 255,
    Map<int, RetryInfo>? retries,
    SessionLaunch? launch,
  }) async {
    final local = FakeLocalSessions();
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(
          launch: launch ?? SshLaunch(devbox),
          connected: connected,
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        reconnectClockProvider.overrideWithValue(() => _clock),
        if (retries != null)
          sshReconnectorProvider.overrideWith(() => _FixedRetries(retries)),
      ],
    );
    container.read(sshReconnectorProvider);
    container.read(terminalTabsProvider);
    local.summaries.clear();
    local.views[1]!.end(code);
    await tester.pump();
    final pane = container
        .read(terminalTabsProvider)
        .tabOfSession(1)!
        .panes[1]!;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: RemoteStrip(pane: pane),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return container;
  }

  /// The reconnector's 3 s timer and the strip's ticker must be gone
  /// before the test ends.
  Future<void> done(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets('disconnected: countdown, Reconnect, Close pane (UI-A8 §3.2)', (
    tester,
  ) async {
    final c = await pump(tester, connected: true);
    expect(find.text('Lost connection to devbox'), findsOneWidget);
    expect(find.textContaining('Retrying in 3 seconds'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reconnect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Close pane'), findsOneWidget);
    expect(
      find.byTooltip(
        'Run inside tmux to keep programs running when the connection drops',
      ),
      findsOneWidget,
    );
    await done(tester, c);
  });

  testWidgets('failed after the hook: Try again, Try without the hook', (
    tester,
  ) async {
    final c = await pump(tester, connected: false, code: 127);
    expect(find.text('Couldn’t connect to devbox'), findsOneWidget);
    expect(
      find.textContaining('The server may not support the ShellX hook'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'Try without the hook'),
      findsOneWidget,
    );
    await done(tester, c);
  });

  testWidgets('failed without the hook: no hook hint, no plain retry', (
    tester,
  ) async {
    final c = await pump(
      tester,
      connected: false,
      code: 127,
      launch: SshLaunch(devbox, hook: false),
    );
    expect(find.textContaining('ShellX hook'), findsNothing);
    expect(
      find.widgetWithText(TextButton, 'Try without the hook'),
      findsNothing,
    );
    await done(tester, c);
  });

  testWidgets('needs sign-in: Reconnect, no countdown (D20)', (tester) async {
    final c = await pump(
      tester,
      connected: true,
      retries: {
        1: RetryInfo(
          attempt: 2,
          firstLost: _clock,
          stopped: true,
          needsSignIn: true,
        ),
      },
    );
    expect(find.textContaining('Sign in'), findsOneWidget);
    expect(find.textContaining('Retrying in'), findsNothing);
    expect(find.textContaining('Stopped retrying'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reconnect'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('gave up after 30 minutes: Stopped retrying, Reconnect', (
    tester,
  ) async {
    final c = await pump(
      tester,
      connected: true,
      retries: {1: RetryInfo(attempt: 9, firstLost: _clock, stopped: true)},
    );
    expect(find.textContaining('Stopped retrying'), findsOneWidget);
    expect(find.textContaining('Retrying in'), findsNothing);
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reconnect'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('one attempt running: Reconnecting…, only Close pane', (
    tester,
  ) async {
    final c = await pump(
      tester,
      connected: true,
      retries: {1: RetryInfo(attempt: 1, firstLost: _clock, retrying: true)},
    );
    expect(find.textContaining('Reconnecting'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reconnect'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Close pane'), findsOneWidget);
    await done(tester, c);
  });

  testWidgets('one live region, buttons are buttons', (tester) async {
    final c = await pump(tester, connected: true);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('remote.strip.1'))),
      matchesSemantics(
        isLiveRegion: true,
        label: 'Lost connection to devbox · Retrying in 3 seconds',
      ),
    );
    handle.dispose();
    await done(tester, c);
  });
}
