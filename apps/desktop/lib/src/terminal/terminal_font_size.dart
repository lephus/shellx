import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/desktop_services.dart';
import '../config/config_controller.dart';
import '../platform/settings_store.dart';
import 'terminal_style.dart';

final terminalFontSizeProvider = NotifierProvider<TerminalFontSize, double>(
  TerminalFontSize.new,
);

/// ⌘+ / ⌘− / ⌘0 (spec criterion 2, UI §1.3). A9 D12: a `font-size` in the
/// configuration sets the size at load and whenever that value changes
/// (another edit keeps a ⌘+ size), ⌘0 returns to it, and ⌘+/− are then
/// not persisted; without one, today's persisted size (D38).
class TerminalFontSize extends Notifier<double> {
  double? _configured;

  @override
  double build() {
    final configured = _configured = ref.watch(
      shellxConfigProvider.select((s) => s.config.fontSize),
    );
    if (configured != null) return _clamp(configured);
    final stored = ref
        .watch(desktopServicesProvider)
        .settings
        .getInt(SettingKeys.terminalFontSize);
    return _clamp((stored ?? kTerminalFontSizeDefault).toDouble());
  }

  /// [step] points (`increase_font_size:N`, D23).
  void increase([double step = 1]) => _set(state + step);
  void decrease([double step = 1]) => _set(state - step);
  void reset() => _set(_configured ?? kTerminalFontSizeDefault);

  void _set(double value) {
    // With no `font-size` in the file the size is saved as a whole point
    // (A1's int setting), so it is kept whole live too: the next launch
    // shows the same size.
    final next = _configured == null
        ? _clamp(value.roundToDouble())
        : _clamp(value);
    if (next == state) return;
    state = next;
    if (_configured != null) return; // D12: the file owns the size
    final settings = ref.read(desktopServicesProvider).settings;
    unawaited(
      settings
          .setInt(SettingKeys.terminalFontSize, next.round())
          .catchError(
            (Object e) =>
                debugPrint('terminal font size not saved: ${e.runtimeType}'),
          ),
    );
  }

  static double _clamp(double value) =>
      value.clamp(kTerminalFontSizeMin, kTerminalFontSizeMax).toDouble();
}
