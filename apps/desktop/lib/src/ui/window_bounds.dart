import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;

import '../platform/settings_store.dart';
import 'theme/shellx_desktop_theme.dart';

/// Remembers where the terminal window was (A1 D9).
final class WindowBoundsStore {
  WindowBoundsStore(this._settings);

  final SettingsStore _settings;

  /// Null when nothing usable is stored.
  Rect? read() {
    final x = _settings.getInt(SettingKeys.windowX);
    final y = _settings.getInt(SettingKeys.windowY);
    final w = _settings.getInt(SettingKeys.windowWidth);
    final h = _settings.getInt(SettingKeys.windowHeight);
    if (x == null || y == null || w == null || h == null) return null;
    if (w < ShellxSizes.minWindow.width || h < ShellxSizes.minWindow.height) {
      return null;
    }
    return Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      w.toDouble(),
      h.toDouble(),
    );
  }

  /// Best effort: a failed write keeps the previous bounds.
  Future<void> write(Rect bounds) async {
    try {
      await _settings.setInt(SettingKeys.windowX, bounds.left.round());
      await _settings.setInt(SettingKeys.windowY, bounds.top.round());
      await _settings.setInt(SettingKeys.windowWidth, bounds.width.round());
      await _settings.setInt(SettingKeys.windowHeight, bounds.height.round());
    } catch (error) {
      // The window opens where it was last saved (or centred) next time.
      debugPrint(
        'ShellX: saving the window bounds failed: '
        '${error.runtimeType}',
      );
    }
  }

  bool readMaximized() =>
      _settings.getBool(SettingKeys.windowMaximized, defaultValue: false);

  /// Best effort, like [write].
  Future<void> writeMaximized(bool maximized) async {
    try {
      await _settings.setBool(SettingKeys.windowMaximized, maximized);
    } catch (error) {
      debugPrint(
        'ShellX: saving the window state failed: '
        '${error.runtimeType}',
      );
    }
  }
}

/// [saved] if the window would still be on one of [displays] (its centre is
/// on a display's visible area), else null so the host centres the default
/// size: a window saved on a monitor that is gone must not open off screen.
/// An empty [displays] (the query failed) keeps [saved].
Rect? restorableBounds(Rect? saved, List<Rect> displays) {
  if (saved == null) return null;
  if (displays.isEmpty) return saved;
  return displays.any((d) => d.contains(saved.center)) ? saved : null;
}
