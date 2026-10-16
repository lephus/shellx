import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:local_notifier/local_notifier.dart';

abstract interface class SystemNotifier {
  /// [id]: a later notification with the same id replaces this one
  /// (A4 D15); [close] removes it.
  Future<void> show({
    required String title,
    String? body,
    String? id,
    void Function()? onClick,
  });

  /// Removes the notification shown with [id], if it is still delivered.
  Future<void> close(String id);
}

/// Package local_notifier (NSUserNotification on macOS, WinToast on Windows).
/// Its `identifier` and `close` already give A4 D17 its id and removal.
final class LocalSystemNotifier implements SystemNotifier {
  LocalSystemNotifier._();

  /// Without [setup]: tests answer the plugin's channel themselves.
  @visibleForTesting
  LocalSystemNotifier.forTest();

  static Future<LocalSystemNotifier> setup() async {
    await localNotifier.setup(
      appName: 'ShellX',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    return LocalSystemNotifier._();
  }

  final _shown = <String, LocalNotification>{};

  @override
  Future<void> show({
    required String title,
    String? body,
    String? id,
    void Function()? onClick,
  }) async {
    final notification = LocalNotification(
      identifier: id,
      title: title,
      body: body,
    );
    notification.onClick = onClick;
    if (id != null) {
      // Registered before the first await, so a close(id) that comes
      // while the previous one is going away removes this one too.
      final previous = _shown[id];
      _shown[id] = notification;
      if (previous != null) await previous.destroy();
      if (!identical(_shown[id], notification)) return; // closed meanwhile
    }
    await notification.show();
  }

  @override
  Future<void> close(String id) async {
    final previous = _shown.remove(id);
    // destroy = close + drop the plugin's listener and map entry; a plain
    // close would keep every replaced notification alive for the session.
    if (previous != null) await previous.destroy();
  }
}
