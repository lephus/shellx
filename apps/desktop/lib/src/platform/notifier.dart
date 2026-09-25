import 'package:local_notifier/local_notifier.dart';

abstract interface class SystemNotifier {
  Future<void> show({
    required String title,
    String? body,
    void Function()? onClick,
  });
}

/// Package local_notifier (NSUserNotification on macOS, WinToast on Windows).
final class LocalSystemNotifier implements SystemNotifier {
  LocalSystemNotifier._();

  static Future<LocalSystemNotifier> setup() async {
    await localNotifier.setup(
      appName: 'ShellX',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    return LocalSystemNotifier._();
  }

  @override
  Future<void> show({
    required String title,
    String? body,
    void Function()? onClick,
  }) async {
    final notification = LocalNotification(title: title, body: body);
    notification.onClick = onClick;
    await notification.show();
  }
}
