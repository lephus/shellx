import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/attention_badge.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

final class _Host implements BadgeHost {
  final unread = <(int, String)>[];
  int flashes = 0;
  @override
  Future<void> setUnread(int count, String description) async =>
      unread.add((count, description));
  @override
  Future<void> flash() async => flashes++;
}

void main() {
  test('total unread drives the badge, re-applied when the window shows; '
      'flash only while inactive (D18, D19)', () async {
    final local = FakeLocalSessions();
    local.add(local.summary(1, title: 'a'));
    local.add(local.summary(2, title: 'b'));
    final c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    c.read(terminalTabsProvider);
    final host = _Host();
    listenForAttentionBadge(
      container: c,
      host: host,
      l10n: lookupAppLocalizations(const Locale('en')),
      run: (f) {},
    );
    expect(host.unread, [(0, '0 unread notifications')]);
    local.notice(2, SessionNoticeKind.message, body: 'x');
    local.notice(2, SessionNoticeKind.message, body: 'y');
    await pumpEventQueue(); // fake notices arrive asynchronously
    expect(host.unread.last, (2, '2 unread notifications'));
    expect(host.flashes, 2); // window inactive
    final calls = host.unread.length;
    c.read(windowRouterProvider.notifier).showTerminal();
    expect(host.unread.length, calls + 1); // re-applied on show
    expect(host.unread.last.$1, 2);
    c.read(windowFocusProvider.notifier).set(true);
    local.notice(2, SessionNoticeKind.message, body: 'z');
    await pumpEventQueue();
    expect(host.flashes, 2);
    c.read(tabAttentionProvider.notifier).markAllRead();
    expect(host.unread.last.$1, 0);
  });

  test('dock label', () {
    expect(dockBadgeLabel(0), '');
    expect(dockBadgeLabel(5), '5');
    expect(dockBadgeLabel(120), '99+');
  });

  test('macOS: a badge call waits for the window calls already queued, so '
      'the show sets the Dock policy first (A1 D10, D18)', () async {
    final host = _Host();
    var window = Completer<void>();
    final badge = AfterWindowBadge(host, windowSettled: () => window.future);
    unawaited(badge.setUnread(3, '3 unread notifications'));
    unawaited(badge.flash());
    await pumpEventQueue();
    expect(host.unread, isEmpty);
    expect(host.flashes, 0);
    window.complete();
    await pumpEventQueue();
    expect(host.unread, [(3, '3 unread notifications')]);
    expect(host.flashes, 1);
    // A failed window call does not hold the badge back.
    window = Completer<void>()..completeError(StateError('no window'));
    await badge.setUnread(0, '0 unread notifications');
    expect(host.unread.last, (0, '0 unread notifications'));
  });
}
