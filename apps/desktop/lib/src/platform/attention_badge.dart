import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../terminal/tab_attention.dart';
import '../ui/window_focus.dart';
import '../ui/window_router.dart';

/// The app icon's unread mark (A4 N7).
abstract interface class BadgeHost {
  /// [description] is for assistive technology (Windows overlay).
  Future<void> setUnread(int count, String description);

  /// A new notice while the window is not active (Windows: taskbar flash).
  Future<void> flash();
}

/// D18 / UI-A4 §1.1: '' clears; '99+' over 99.
String dockBadgeLabel(int count) => count <= 0 ? '' : unreadBadgeLabel(count);

/// macOS: `NSApp.dockTile.badgeLabel` through window_manager (D18).
final class MacDockBadge implements BadgeHost {
  const MacDockBadge();
  @override
  Future<void> setUnread(int count, String description) =>
      windowManager.setBadgeLabel(dockBadgeLabel(count));

  /// The Dock badge is the mark; macOS has no taskbar flash.
  @override
  Future<void> flash() async {}
}

/// Windows: overlay dot + flash in the runner (D19). `win32` has neither
/// API, so `windows/runner/flutter_window.cpp` answers this channel.
final class WindowsTaskbarBadge implements BadgeHost {
  const WindowsTaskbarBadge({
    MethodChannel channel = const MethodChannel('pro.shellx.desktop/taskbar'),
  }) : _channel = channel;
  final MethodChannel _channel;

  @override
  Future<void> setUnread(int count, String description) =>
      _channel.invokeMethod<void>('setUnread', {
        'count': count,
        'description': description,
      });

  @override
  Future<void> flash() => _channel.invokeMethod<void>('flash');
}

/// Linux and tests: no app icon mark.
final class NoBadge implements BadgeHost {
  const NoBadge();
  @override
  Future<void> setUnread(int count, String description) async {}
  @override
  Future<void> flash() async {}
}

/// macOS: the Dock tile comes back with the `.regular` activation policy
/// (A1 D10), which the window's show sets. Each call waits for the window
/// calls already queued ([windowSettled], `WindowPresenter.settled`), so the
/// re-apply on show lands after the policy, never before it.
final class AfterWindowBadge implements BadgeHost {
  const AfterWindowBadge(this._inner, {required this.windowSettled});
  final BadgeHost _inner;
  final Future<void> Function() windowSettled;

  @override
  Future<void> setUnread(int count, String description) =>
      _after(() => _inner.setUnread(count, description));

  @override
  Future<void> flash() => _after(_inner.flash);

  /// A failed window call is the presenter's to report; the badge still
  /// goes on.
  Future<void> _after(Future<void> Function() call) =>
      windowSettled().then((_) {}, onError: (Object _) {}).then((_) => call());
}

/// `main.dart`. [run] logs a failed call by type (never the count's text).
/// A host without its platform channel (an old Windows runner) fails every
/// call the same way: [log] says so once, and nothing goes to [run] again.
AttentionListener listenForAttentionBadge({
  required ProviderContainer container,
  required BadgeHost host,
  required AppLocalizations l10n,
  required void Function(Future<void> call) run,
  void Function(String message)? log,
}) {
  final say = log ?? debugPrint;
  var missing = false;
  void call(Future<void> Function() f) {
    if (missing) return;
    run(
      f().catchError((Object _) {
        if (missing) return;
        missing = true;
        say('ShellX: badge unavailable (no platform channel)');
      }, test: (e) => e is MissingPluginException),
    );
  }

  void apply(int count) =>
      call(() => host.setUnread(count, l10n.attentionUnreadCount(count)));
  container.listen<int>(
    tabAttentionProvider.select((s) => s.totalUnread),
    (_, count) => apply(count),
    fireImmediately: true,
  );
  // The Dock icon comes back with the window (A1 D10): set it again.
  container.listen<bool>(windowRouterProvider.select((s) => s.visible), (
    _,
    shown,
  ) {
    if (shown) apply(container.read(tabAttentionProvider).totalUnread);
  });
  // Arrivals come only while the user is not looking at that tab; flash
  // only when the whole window is not active (D19).
  return listenAttention(
    container,
    onArrival: (_) {
      if (!readWindowActive(container.read)) call(host.flash);
    },
  );
}
