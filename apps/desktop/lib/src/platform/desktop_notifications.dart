import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/tab_attention.dart';
import '../terminal/terminal_tabs.dart';
import '../ui/window_focus.dart';
import 'notifier.dart';
import 'settings_store.dart';

/// Whether the user can see a tab now (D14): read at each decision.
typedef AttentionView = ({bool windowFocused, bool tabSelected});

/// One tab's D15 coalescing window: what arrived after the first post.
final class _Burst {
  _Burst(this.title, {required this.bellsOnly});
  String title;
  int extra = 0;
  String latest = '';
  Timer? timer;

  /// The first notice was refused by the rate limit: the coalesced post
  /// counts it too.
  bool firstSkipped = false;

  /// Only bells so far: D14's bell rule applies at the flush.
  bool bellsOnly;
}

/// Native notifications for tabs (A4 N6, D14–D17). Never throws; never
/// logs a title or text (N9).
final class DesktopNotifications {
  DesktopNotifications({
    required SystemNotifier notifier,
    required SettingsStore settings,
    required AppLocalizations l10n,
    required void Function(int tabId) onOpen,
    AttentionView Function(int tabId)? viewOf,
    DateTime Function()? now,
    this.coalesce = const Duration(seconds: 3),
    this.perTab = 6,
    this.perApp = 20,
    this.window = const Duration(seconds: 60),
    void Function(String message)? log,
  }) : _notifier = notifier,
       _settings = settings,
       _l10n = l10n,
       _onOpen = onOpen,
       _viewOf = viewOf ?? _unseen,
       _now = now ?? DateTime.now,
       _log = log ?? debugPrint;

  /// UI-A4 §6: cut lengths, in characters (runes), `…` included.
  static const int maxTitle = 80;
  static const int maxBody = 200;

  /// D15: one id per tab, so a coalesced post replaces the first.
  static String idFor(int tabId) => 'shellx.tab.$tabId';

  final SystemNotifier _notifier;
  final SettingsStore _settings;
  final AppLocalizations _l10n;
  final void Function(int tabId) _onOpen;
  final AttentionView Function(int tabId) _viewOf;
  final DateTime Function() _now;
  final void Function(String message) _log;
  final Duration coalesce;
  final int perTab;
  final int perApp;
  final Duration window;
  final _bursts = <int, _Burst>{};
  final _postsByTab = <int, List<DateTime>>{};
  final _posts = <DateTime>[];

  /// When the rate limit was last logged: once per [window].
  DateTime? _limitLogged;
  AttentionListener? _listener;

  static AttentionView _unseen(int _) =>
      (windowFocused: false, tabSelected: false);

  /// D14: whether [a] becomes a system notification, then D15.
  void arrived(
    AttentionArrival a, {
    required String title,
    required bool windowFocused,
    required bool tabSelected,
  }) {
    final bell = a.kind == AttentionKind.bell;
    if (!_wanted(
      bell: bell,
      windowFocused: windowFocused,
      tabSelected: tabSelected,
    )) {
      return;
    }
    final body = bell ? _l10n.attentionBellBody : a.text;
    final burst = _bursts[a.tabId];
    if (burst != null) {
      burst
        ..title = title
        ..extra += 1
        ..latest = body
        ..bellsOnly = burst.bellsOnly && bell;
      return;
    }
    final fresh = _Burst(title, bellsOnly: bell);
    fresh.timer = Timer(coalesce, () => _flush(a.tabId));
    _bursts[a.tabId] = fresh;
    fresh.firstSkipped = !_post(a.tabId, title, body);
  }

  /// D14. Both settings are read at each decision, so a tray change
  /// applies at once (also to a pending coalesced post); a missing value
  /// means on. A bell only when the window is not in front, whatever the
  /// switch.
  bool _wanted({
    required bool bell,
    required bool windowFocused,
    required bool tabSelected,
  }) {
    final enabled = _settings.getBool(
      SettingKeys.desktopNotifications,
      defaultValue: true,
    );
    if (!enabled) return false;
    final onlyUnfocused = _settings.getBool(
      SettingKeys.desktopNotificationsOnlyUnfocused,
      defaultValue: true,
    );
    return bell
        ? !windowFocused
        : !windowFocused || (!onlyUnfocused && !tabSelected);
  }

  /// The tab was read (or closed): no pending burst, and its delivered
  /// notification leaves Notification/Action Center (D15).
  void tabRead(int tabId) {
    _bursts.remove(tabId)?.timer?.cancel();
    unawaited(_guard(() => _notifier.close(idFor(tabId))));
  }

  /// Stops listening (see [listenForDesktopNotifications]) and cancels
  /// pending bursts.
  void dispose() {
    _listener?.close();
    _listener = null;
    for (final b in _bursts.values) {
      b.timer?.cancel();
    }
    _bursts.clear();
  }

  /// D15: the coalesced post, if the user still wants one now: the
  /// settings and the window may have changed during the 3 s.
  void _flush(int tabId) {
    final burst = _bursts.remove(tabId);
    if (burst == null || burst.extra == 0) return;
    // A7 D23: command-line entries are treated as "window not in front".
    final view = tabId == kCommandLineTabId ? _unseen(tabId) : _viewOf(tabId);
    if (!_wanted(
      bell: burst.bellsOnly,
      windowFocused: view.windowFocused,
      tabSelected: view.tabSelected,
    )) {
      return;
    }
    final count = burst.extra + (burst.firstSkipped ? 1 : 0);
    _post(tabId, burst.title, _l10n.systemNotifyCoalesced(count, burst.latest));
  }

  /// False when the rate limit refused it.
  bool _post(int tabId, String title, String body) {
    final now = _now();
    bool old(DateTime t) => now.difference(t) >= window;
    _posts.removeWhere(old);
    // Tabs without a post in the window are forgotten.
    _postsByTab.removeWhere((_, times) {
      times.removeWhere(old);
      return times.isEmpty;
    });
    final tabPosts = _postsByTab[tabId] ?? const <DateTime>[];
    if (tabPosts.length >= perTab || _posts.length >= perApp) {
      final logged = _limitLogged;
      if (logged == null || now.difference(logged) >= window) {
        _limitLogged = now;
        _log('ShellX: system notifications skipped (rate limit)');
      }
      return false;
    }
    _postsByTab.putIfAbsent(tabId, () => []).add(now);
    _posts.add(now);
    unawaited(
      _guard(
        () => _notifier.show(
          id: idFor(tabId),
          title: _clip(title, maxTitle),
          body: _clip(body, maxBody),
          onClick: () => _onOpen(tabId),
        ),
      ),
    );
    return true;
  }

  /// Tabs with a post in the current rate-limit window.
  @visibleForTesting
  int get trackedTabs => _postsByTab.length;

  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } catch (error) {
      _log('ShellX: system notification failed: ${error.runtimeType}');
    }
  }

  static String _clip(String text, int max) {
    final runes = text.runes;
    return runes.length <= max
        ? text
        : '${String.fromCharCodes(runes.take(max - 1))}…';
  }
}

/// UI-A4 §6: the tab label, or "label · workspace" when headers show. In a
/// split tab the label is that of [paneId], the pane that sent it (final
/// ruling m-6).
String systemNotificationTitle(
  TerminalTab tab,
  SidebarState sidebar,
  AppLocalizations l10n, {
  required int paneId,
}) {
  final label = tab.noticeLabel(paneId);
  if (!sidebar.showHeaders) return label;
  final ws = sidebar.workspaceOf(tab.id);
  final name = ws == null ? null : sidebar.workspace(ws)?.displayName(l10n);
  return name == null ? label : '$label · $name';
}

/// [DesktopNotifications.arrived]'s window state for [tabId], read from
/// [windowActiveProvider]'s sources at decision time: the derived provider
/// can lag (see TabAttention.build).
AttentionView attentionView(ProviderContainer container, int tabId) => (
  windowFocused: readWindowActive(container.read),
  tabSelected: container.read(terminalTabsProvider).selectedId == tabId,
);

/// `main.dart`: arrivals → [DesktopNotifications.arrived], reads →
/// [DesktopNotifications.tabRead], until [DesktopNotifications.dispose].
void listenForDesktopNotifications({
  required ProviderContainer container,
  required DesktopNotifications notifications,
  required AppLocalizations l10n,
}) {
  notifications._listener?.close();
  notifications._listener = listenAttention(
    container,
    onArrival: (a) {
      if (a.tabId == kCommandLineTabId) {
        // A7 D23: no tab; same switches (D14) and limits (D15), as if the
        // window were not in front. A click (onOpen(0)) raises the window.
        notifications.arrived(
          a,
          title: a.title ?? l10n.cliNoticeSource,
          windowFocused: false,
          tabSelected: false,
        );
        return;
      }
      final tabs = container.read(terminalTabsProvider);
      final tab = tabs.tabs.where((t) => t.id == a.tabId).firstOrNull;
      if (tab == null) return;
      final view = attentionView(container, a.tabId);
      notifications.arrived(
        a,
        title: systemNotificationTitle(
          tab,
          container.read(sidebarWorkspacesProvider),
          l10n,
          paneId: a.paneId,
        ),
        windowFocused: view.windowFocused,
        tabSelected: view.tabSelected,
      );
    },
    onRead: notifications.tabRead,
  );
}
