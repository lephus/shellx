import 'package:shellx_agent/shellx_agent.dart';

/// Spec §7.6: at most one "phone is watching" notification per (phone,
/// terminal) in [window], so re-attaching after a network drop stays quiet.
final class AttachNotificationThrottle {
  AttachNotificationThrottle({
    required DateTime Function() now,
    this.window = const Duration(minutes: 10),
  }) : _now = now;

  final DateTime Function() _now;
  final Duration window;
  final Map<(String, int), DateTime> _last = {};

  /// Forgets every pair (a new runtime numbers its sessions afresh).
  void clear() => _last.clear();

  /// True (and remembered) when a notification may be shown now.
  bool allow(String mobileId, int sessionId) {
    final now = _now();
    _last.removeWhere((_, at) => now.difference(at) >= window);
    final key = (mobileId, sessionId);
    if (_last.containsKey(key)) return false;
    _last[key] = now;
    return true;
  }
}

/// "app — title" for the tray and the notification (spec §7.6); the shell
/// stands in for a terminal that set no title yet.
String desktopTerminalLabel(DesktopSessionSummary session) {
  final app = session.app.isEmpty ? 'Terminal' : session.app;
  final title = session.title.isEmpty ? session.shell : session.title;
  return title.isEmpty ? app : '$app — $title';
}

/// Spec §7.6, §12: the switch always shows on macOS; on Windows only when
/// ShellX starts with `SHELLX_EXPERIMENTAL=terminal-sharing` (a
/// comma-separated list is accepted) until Windows is checked by hand — or
/// when sharing is already on ([storedEnabled]): a start without the flag
/// (launch at login) must still let the user turn it off and keep `bin`
/// current.
bool terminalSharingAvailable({
  required bool macos,
  required bool windows,
  required Map<String, String> environment,
  bool storedEnabled = false,
}) {
  if (macos) return true;
  if (!windows) return false;
  if (storedEnabled) return true;
  final flags = (environment['SHELLX_EXPERIMENTAL'] ?? '')
      .split(',')
      .map((f) => f.trim().toLowerCase());
  return flags.contains('terminal-sharing');
}
