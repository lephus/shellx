import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/tab_attention.dart';
import '../terminal/terminal_tabs.dart';
import '../ui/window_focus.dart';
import '../ui/window_router.dart';
import 'notifier.dart';
import 'settings_store.dart';

/// One tab's D15 coalescing window: what arrived after the first post.
final class _Burst {
  _Burst(this.title);
  String title;
  int extra = 0;
  String latest = '';
  Timer? timer;
}

/// Native notifications for tabs (A4 N6, D14–D17). Never throws; never
/// logs a title or text (N9).
final class DesktopNotifications {
  DesktopNotifications({
    required SystemNotifier notifier,
    required SettingsStore settings,
    required AppLocalizations l10n,
    required void Function(int tabId) onOpen,
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
  final DateTime Function() _now;
  final void Function(String message) _log;
  final Duration coalesce;
  final int perTab;
  final int perApp;
  final Duration window;
  final _bursts = <int, _Burst>{};
  final _postsByTab = <int, List<DateTime>>{};
  final _posts = <DateTime>[];

  /// D14: whether [a] becomes a system notification, then D15. Both
  /// settings are read here, on every notice, so a tray change applies at
  /// once; a missing value means on.
  void arrived(
    AttentionArrival a, {
    required String title,
    required bool windowFocused,
    required bool tabSelected,
  }) {
    final enabled = _settings.getBool(
      SettingKeys.desktopNotifications,
      defaultValue: true,
    );
    if (!enabled) return;
    final onlyUnfocused = _settings.getBool(
      SettingKeys.desktopNotificationsOnlyUnfocused,
      defaultValue: true,
    );
    // A bell only when the window is not in front, whatever the switch.
    final post = a.kind == AttentionKind.bell
        ? !windowFocused
        : !windowFocused || (!onlyUnfocused && !tabSelected);
    if (!post) return;
    final body = a.kind == AttentionKind.bell
        ? _l10n.attentionBellBody
        : a.text;
    final burst = _bursts[a.tabId];
    if (burst != null) {
      burst
        ..title = title
        ..extra += 1
        ..latest = body;
      return;
    }
    final fresh = _Burst(title);
    fresh.timer = Timer(coalesce, () => _flush(a.tabId));
    _bursts[a.tabId] = fresh;
    _post(a.tabId, title, body);
  }

  /// The tab was read (or closed): no pending burst, and its delivered
  /// notification leaves Notification/Action Center (D15).
  void tabRead(int tabId) {
    _bursts.remove(tabId)?.timer?.cancel();
    unawaited(_guard(() => _notifier.close(idFor(tabId))));
  }

  void dispose() {
    for (final b in _bursts.values) {
      b.timer?.cancel();
    }
    _bursts.clear();
  }

  void _flush(int tabId) {
    final burst = _bursts.remove(tabId);
    if (burst == null || burst.extra == 0) return;
    _post(
      tabId,
      burst.title,
      _l10n.systemNotifyCoalesced(burst.extra, burst.latest),
    );
  }

  void _post(int tabId, String title, String body) {
    final now = _now();
    bool full(List<DateTime> times, int max) {
      times.removeWhere((t) => now.difference(t) >= window);
      return times.length >= max;
    }

    final tabPosts = _postsByTab.putIfAbsent(tabId, () => []);
    if (full(tabPosts, perTab) || full(_posts, perApp)) {
      _log('ShellX: system notification skipped (rate limit)');
      return;
    }
    tabPosts.add(now);
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
  }

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

/// UI-A4 §6: the tab label, or "label · workspace" when headers show.
String systemNotificationTitle(
  TerminalTab tab,
  SidebarState sidebar,
  AppLocalizations l10n,
) {
  if (!sidebar.showHeaders) return tab.label;
  final ws = sidebar.workspaceOf(tab.id);
  final name = ws == null ? null : sidebar.workspace(ws)?.displayName(l10n);
  return name == null ? tab.label : '${tab.label} · $name';
}

/// `main.dart`: arrivals → [DesktopNotifications.arrived], reads →
/// [DesktopNotifications.tabRead]. Reading [tabAttentionProvider] here
/// also builds it at startup, so no notice is missed.
void listenForDesktopNotifications({
  required ProviderContainer container,
  required DesktopNotifications notifications,
  required AppLocalizations l10n,
}) {
  final attention = container.read(tabAttentionProvider.notifier);
  attention.arrivals.listen((a) {
    final tabs = container.read(terminalTabsProvider);
    TerminalTab? tab;
    for (final t in tabs.tabs) {
      if (t.id == a.tabId) tab = t;
    }
    if (tab == null) return;
    notifications.arrived(
      a,
      title: systemNotificationTitle(
        tab,
        container.read(sidebarWorkspacesProvider),
        l10n,
      ),
      // windowActiveProvider's rule, read from its sources at decision
      // time: the derived provider can lag (see TabAttention.build).
      windowFocused:
          container.read(windowFocusProvider) &&
          container.read(windowRouterProvider).visible,
      tabSelected: tabs.selectedId == a.tabId,
    );
  });
  attention.reads.listen(notifications.tabRead);
}
