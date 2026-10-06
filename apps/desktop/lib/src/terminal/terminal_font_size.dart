import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/desktop_services.dart';
import '../platform/settings_store.dart';
import 'terminal_style.dart';

final terminalFontSizeProvider = NotifierProvider<TerminalFontSize, double>(
  TerminalFontSize.new,
);

/// ⌘+ / ⌘− / ⌘0 (spec criterion 2, UI §1.3), persisted in the settings.
class TerminalFontSize extends Notifier<double> {
  @override
  double build() {
    final stored = ref
        .watch(desktopServicesProvider)
        .settings
        .getInt(SettingKeys.terminalFontSize);
    return _clamp((stored ?? kTerminalFontSizeDefault).toDouble());
  }

  void increase() => _set(state + 1);
  void decrease() => _set(state - 1);
  void reset() => _set(kTerminalFontSizeDefault);

  void _set(double value) {
    final next = _clamp(value);
    if (next == state) return;
    state = next;
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
