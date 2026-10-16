import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

/// UI-A5 §7.5 (the strips of a lost background service) and §7.4 (the empty
/// state while there is none).
final class _FakeDaemonState extends DaemonStateNotifier {
  _FakeDaemonState(this.initial);
  final DaemonUiState initial;
  int retries = 0;
  int dismissals = 0;

  @override
  DaemonUiState build() => initial;

  @override
  Future<void> retry() async {
    retries++;
    state = state.copyWith(retrying: true);
  }

  @override
  void dismissStrip() {
    dismissals++;
    super.dismissStrip();
  }
}

final restartedStrip = find.byKey(const Key('pane.daemonStrip'));

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  late _FakeDaemonState fake;

  Future<void> pumpWith(
    WidgetTester t,
    DaemonUiState state, {
    bool mode = true,
  }) async {
    fake = _FakeDaemonState(state);
    await pumpSidebar(
      t,
      overrides: [
        daemonModeProvider.overrideWithValue(mode),
        daemonStateProvider.overrideWith(() => fake),
      ],
    );
  }

  testSidebar('the restarted strip: history icon, the text, Close hides it', (
    t,
  ) async {
    await pumpWith(t, const DaemonUiState(strip: DaemonStrip.restarted));
    await t.pump();
    expect(restartedStrip, findsOneWidget);
    expect(
      find.text(
        'The background service stopped unexpectedly and was restarted. '
        'Shells were reopened in their folders.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.byKey(const Key('daemonStrip.retry')), findsNothing);
    await t.tap(find.byKey(const Key('infoStrip.close')));
    await t.pumpAndSettle();
    expect(fake.dismissals, 1);
    expect(restartedStrip, findsNothing);
  });

  testSidebar('the lost strip: error icon, text, "Try Again" retries and '
      'shows a spinner while it works', (t) async {
    await pumpWith(t, const DaemonUiState(strip: DaemonStrip.lost));
    await t.pump();
    expect(
      find.text(
        'The background service stopped. Shells are no longer running.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await t.tap(find.byKey(const Key('daemonStrip.retry')));
    await t.pump();
    expect(fake.retries, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testSidebar('the retry button reads for a screen reader', (t) async {
    await pumpWith(t, const DaemonUiState(strip: DaemonStrip.lost));
    await t.pump();
    expect(
      find.bySemanticsLabel('Try restarting the background service'),
      findsOneWidget,
    );
  });

  testSidebar(
    'both strips: the restore strip first, the service strip below it',
    (t) async {
      await pumpWith(t, const DaemonUiState(strip: DaemonStrip.lost));
      container
          .read(restoreStripProvider.notifier)
          .show(const RestoreStripState(tabs: 2, contentsAt: null));
      await t.pump();
      await t.pump();
      final restore = t.getRect(find.byKey(const Key('pane.restoreStrip')));
      final daemon = t.getRect(restartedStrip);
      expect(daemon.top, greaterThanOrEqualTo(restore.bottom));
    },
  );

  testSidebar('waiting for the service: the empty state says so and offers no '
      'new tab (UI-A5 §7.4)', (t) async {
    local.summaries.clear();
    await pumpWith(t, const DaemonUiState(waiting: true));
    await t.pump();
    expect(find.text('Waiting for the background service…'), findsOneWidget);
    expect(find.byKey(const Key('pane.empty.open')), findsNothing);
  });

  testSidebar('not waiting: the empty state is unchanged', (t) async {
    local.summaries.clear();
    await pumpWith(t, const DaemonUiState(), mode: false);
    await t.pump();
    expect(find.byKey(const Key('pane.empty.open')), findsOneWidget);
  });
}
