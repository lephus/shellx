import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../config/config_controller.dart';
import '../config/config_problem.dart';
import '../config/keybind_trigger.dart';
import '../terminal/terminal_tabs.dart';
import '../ui/activation.dart';
import '../ui/window_focus.dart';
import '../ui/window_router.dart';

/// A11 D22: one system-wide shortcut that shows or hides the ShellX window
/// from any app. Behind an interface so the rules (register on start and on
/// change, unregister when removed and on quit, a refusal is a
/// configuration problem) are tested with a fake and the plugin stays a
/// detail.
abstract interface class GlobalHotkey {
  /// Registers [chord] system-wide (replacing an earlier one) and calls
  /// [onPressed] on each press. False when it could not be registered.
  /// Never throws.
  Future<bool> register(KeyChord chord, void Function() onPressed);

  /// Removes the registration, if any. Never throws.
  Future<void> unregister();
}

/// `hotkey_manager` 0.2.3: Carbon `RegisterEventHotKey` on macOS (no
/// permission needed) and `RegisterHotKey` on Windows.
///
/// Limit of the plugin: both native sides answer `true` whatever the system
/// said, so a key that another app already holds is not reported (the
/// shortcut then simply never fires). What it does report, a key it cannot
/// map or a platform error, is `false`.
final class HotkeyManagerHotkey implements GlobalHotkey {
  @override
  Future<bool> register(KeyChord chord, void Function() onPressed) async {
    final key = physicalKeyFor(chord.key);
    if (key == null) return false;
    try {
      // The plugin's registrations live in the native side: a hot restart
      // or an earlier chord must not leave one behind.
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        HotKey(
          key: key,
          modifiers: modifiersOf(chord),
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (_) => onPressed(),
      );
      return true;
    } catch (error) {
      // Never the chord: only what went wrong.
      debugPrint(
        'ShellX: global shortcut not registered: ${error.runtimeType}',
      );
      return false;
    }
  }

  @override
  Future<void> unregister() async {
    try {
      await hotKeyManager.unregisterAll();
    } catch (error) {
      debugPrint(
        'ShellX: global shortcut not unregistered: ${error.runtimeType}',
      );
    }
  }
}

/// The physical key behind a logical one, for the keys a user would pick
/// (letters, digits, F1–F12, space, punctuation, arrows, Enter, Tab, Esc);
/// null for anything else. The plugin needs the physical key: the system
/// shortcut is the key's position, not what the layout prints on it.
PhysicalKeyboardKey? physicalKeyFor(LogicalKeyboardKey key) => _physical[key];

final Map<LogicalKeyboardKey, PhysicalKeyboardKey> _physical = {
  LogicalKeyboardKey.keyA: PhysicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyB: PhysicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyC: PhysicalKeyboardKey.keyC,
  LogicalKeyboardKey.keyD: PhysicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyE: PhysicalKeyboardKey.keyE,
  LogicalKeyboardKey.keyF: PhysicalKeyboardKey.keyF,
  LogicalKeyboardKey.keyG: PhysicalKeyboardKey.keyG,
  LogicalKeyboardKey.keyH: PhysicalKeyboardKey.keyH,
  LogicalKeyboardKey.keyI: PhysicalKeyboardKey.keyI,
  LogicalKeyboardKey.keyJ: PhysicalKeyboardKey.keyJ,
  LogicalKeyboardKey.keyK: PhysicalKeyboardKey.keyK,
  LogicalKeyboardKey.keyL: PhysicalKeyboardKey.keyL,
  LogicalKeyboardKey.keyM: PhysicalKeyboardKey.keyM,
  LogicalKeyboardKey.keyN: PhysicalKeyboardKey.keyN,
  LogicalKeyboardKey.keyO: PhysicalKeyboardKey.keyO,
  LogicalKeyboardKey.keyP: PhysicalKeyboardKey.keyP,
  LogicalKeyboardKey.keyQ: PhysicalKeyboardKey.keyQ,
  LogicalKeyboardKey.keyR: PhysicalKeyboardKey.keyR,
  LogicalKeyboardKey.keyS: PhysicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyT: PhysicalKeyboardKey.keyT,
  LogicalKeyboardKey.keyU: PhysicalKeyboardKey.keyU,
  LogicalKeyboardKey.keyV: PhysicalKeyboardKey.keyV,
  LogicalKeyboardKey.keyW: PhysicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyX: PhysicalKeyboardKey.keyX,
  LogicalKeyboardKey.keyY: PhysicalKeyboardKey.keyY,
  LogicalKeyboardKey.keyZ: PhysicalKeyboardKey.keyZ,
  LogicalKeyboardKey.digit0: PhysicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1: PhysicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2: PhysicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3: PhysicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4: PhysicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5: PhysicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6: PhysicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7: PhysicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8: PhysicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9: PhysicalKeyboardKey.digit9,
  LogicalKeyboardKey.f1: PhysicalKeyboardKey.f1,
  LogicalKeyboardKey.f2: PhysicalKeyboardKey.f2,
  LogicalKeyboardKey.f3: PhysicalKeyboardKey.f3,
  LogicalKeyboardKey.f4: PhysicalKeyboardKey.f4,
  LogicalKeyboardKey.f5: PhysicalKeyboardKey.f5,
  LogicalKeyboardKey.f6: PhysicalKeyboardKey.f6,
  LogicalKeyboardKey.f7: PhysicalKeyboardKey.f7,
  LogicalKeyboardKey.f8: PhysicalKeyboardKey.f8,
  LogicalKeyboardKey.f9: PhysicalKeyboardKey.f9,
  LogicalKeyboardKey.f10: PhysicalKeyboardKey.f10,
  LogicalKeyboardKey.f11: PhysicalKeyboardKey.f11,
  LogicalKeyboardKey.f12: PhysicalKeyboardKey.f12,
  LogicalKeyboardKey.space: PhysicalKeyboardKey.space,
  LogicalKeyboardKey.comma: PhysicalKeyboardKey.comma,
  LogicalKeyboardKey.period: PhysicalKeyboardKey.period,
  LogicalKeyboardKey.slash: PhysicalKeyboardKey.slash,
  LogicalKeyboardKey.semicolon: PhysicalKeyboardKey.semicolon,
  LogicalKeyboardKey.quote: PhysicalKeyboardKey.quote,
  LogicalKeyboardKey.bracketLeft: PhysicalKeyboardKey.bracketLeft,
  LogicalKeyboardKey.bracketRight: PhysicalKeyboardKey.bracketRight,
  LogicalKeyboardKey.minus: PhysicalKeyboardKey.minus,
  LogicalKeyboardKey.equal: PhysicalKeyboardKey.equal,
  LogicalKeyboardKey.backquote: PhysicalKeyboardKey.backquote,
  LogicalKeyboardKey.backslash: PhysicalKeyboardKey.backslash,
  LogicalKeyboardKey.arrowLeft: PhysicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight: PhysicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp: PhysicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown: PhysicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.enter: PhysicalKeyboardKey.enter,
  LogicalKeyboardKey.tab: PhysicalKeyboardKey.tab,
  LogicalKeyboardKey.escape: PhysicalKeyboardKey.escape,
};

/// The plugin's modifiers for [chord] (⌘ / Win is `meta`).
List<HotKeyModifier> modifiersOf(KeyChord chord) => [
  if (chord.control) HotKeyModifier.control,
  if (chord.alt) HotKeyModifier.alt,
  if (chord.shift) HotKeyModifier.shift,
  if (chord.meta) HotKeyModifier.meta,
];

/// The one platform registration; a test overrides it with a fake.
final globalHotkeyProvider = Provider<GlobalHotkey>(
  (ref) => HotkeyManagerHotkey(),
);

/// Wall clock for the key-repeat guard; a test overrides it.
final globalHotkeyClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Read once at startup by the UI process, after the first configuration
/// load. Never in the background service (it has no window).
final globalHotkeyBinderProvider = Provider<GlobalHotkeyBinder>((ref) {
  final binder = GlobalHotkeyBinder(
    ref,
    ref.watch(globalHotkeyProvider),
    ref.watch(globalHotkeyClockProvider),
  )..start();
  ref.onDispose(binder.release);
  return binder;
});

/// Keeps the registration equal to `global-hotkey` in the configuration:
/// registers at start and when the value changes, removes it when the key
/// goes, and tells the user (a configuration problem, once) when it could
/// not be registered. A press toggles the window.
final class GlobalHotkeyBinder {
  GlobalHotkeyBinder(this._ref, this._hotkey, this._now);

  final Ref _ref;
  final GlobalHotkey _hotkey;
  final DateTime Function() _now;

  Future<void> _chain = Future.value();
  KeyChord? _wanted;

  /// The chord whose last registration failed (null: none failed).
  KeyChord? _failed;
  DateTime? _lastPress;
  bool _released = false;

  /// Presses closer than this are one hold: Windows sends WM_HOTKEY again
  /// while the keys stay down.
  static const Duration repeatGuard = Duration(milliseconds: 300);

  void start() {
    _ref.listen(
      shellxConfigProvider.select((s) => s.config.globalHotkey),
      (_, chord) {
        _wanted = chord;
        _enqueue(chord);
      },
      fireImmediately: true,
    );
    // A reload drops the runtime problems of the old configuration: a
    // chord that still cannot be registered is told again.
    _ref.listen(shellxConfigProvider.select((s) => s.generation), (_, _) {
      if (_failed != null && _failed == _wanted) _report(failed: true);
    });
  }

  void _enqueue(KeyChord? chord) {
    _chain = _chain.then((_) => _apply(chord)).catchError((Object error) {
      debugPrint('ShellX: global shortcut failed: ${error.runtimeType}');
    });
  }

  Future<void> _apply(KeyChord? chord) async {
    if (_released) return;
    if (chord == null) {
      _failed = null;
      await _hotkey.unregister();
      _report(failed: false);
      return;
    }
    bool ok;
    try {
      ok = await _hotkey.register(chord, _onPressed);
    } catch (error) {
      debugPrint('ShellX: global shortcut failed: ${error.runtimeType}');
      ok = false;
    }
    if (_released) {
      await _hotkey.unregister();
      return;
    }
    _failed = ok ? null : chord;
    _report(failed: !ok);
  }

  /// The problem sits on the line of the key, like the font probe's.
  void _report({required bool failed}) {
    if (!_ref.mounted) return;
    final state = _ref.read(shellxConfigProvider);
    final origin = state.config.origins['global-hotkey'];
    _ref
        .read(shellxConfigProvider.notifier)
        .reportRuntimeProblems(
          state.generation,
          const {ConfigProblemCode.unsupportedValue},
          [
            if (failed)
              ConfigProblem(
                file: origin?.file ?? '',
                line: origin?.line ?? 0,
                severity: ConfigSeverity.warning,
                code: ConfigProblemCode.unsupportedValue,
                key: 'global-hotkey',
              ),
          ],
        );
  }

  /// The window is shown and has the keyboard: hide it (to the tray, like
  /// its close button). Otherwise (hidden, minimized, behind another app)
  /// show it in front, opening a tab when there is none: the same path as
  /// the tray's "Open terminal window".
  void _onPressed() {
    if (_released || !_ref.mounted) return;
    final now = _now();
    final last = _lastPress;
    _lastPress = now;
    if (last != null && now.difference(last) < repeatGuard) return;
    final router = _ref.read(windowRouterProvider.notifier);
    if (readWindowActive(_ref.read)) {
      router.hideWindow();
      return;
    }
    unawaited(
      openTerminalWindow(
        router: router,
        tabs: _ref.read(terminalTabsProvider.notifier),
      ),
    );
  }

  /// Quit, or the provider going away: the registration goes with the
  /// process, but the plugin is told anyway.
  Future<void> dispose() async {
    _released = true;
    await _chain;
    await _hotkey.unregister();
  }

  /// Without waiting: the provider's own dispose.
  void release() {
    _released = true;
    unawaited(_hotkey.unregister());
  }
}
