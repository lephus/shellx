import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../platform/app_reopen.dart' as platform_app;
import '../terminal/terminal_tabs.dart';
import 'theme/shellx_desktop_theme.dart';
import 'window_bounds.dart';
import 'window_router.dart';

/// UI §2: "{tab} — ShellX", or "ShellX" with no tabs.
String windowTitleFor(TerminalTab? selected, AppLocalizations l10n) =>
    selected == null ? 'ShellX' : l10n.windowTitle(selected.label);

/// Keeps the native window title on the selected tab's. Only a different
/// title reaches [WindowHost.setTitle]: the tabs change on every running
/// command, driver or phone change (ruling I3).
void listenForWindowTitle({
  required ProviderContainer container,
  required WindowHost host,
  required AppLocalizations l10n,
  required void Function(Future<void> call) run,
}) {
  container.listen<String>(
    terminalTabsProvider.select((s) => windowTitleFor(s.selected, l10n)),
    (_, title) => run(host.setTitle(title)),
  );
}

abstract interface class WindowHost {
  Future<void> show();
  Future<void> hide();

  /// The window is shown but may be minimized, behind another app or on
  /// another Space: restore it, show it, focus it.
  Future<void> bringToFront();
  Future<void> setTitle(String title);
}

/// Shows/hides the single window to follow the router, and brings it to
/// the front whenever the router asks again ([WindowState.raise]: a tray
/// item, the Dock, a second launch, a dialog opening). Dialogs never
/// resize it (UI §4). Host calls run one after another, so a quick hide →
/// show always ends shown (with the Dock icon), never interleaved.
final class WindowPresenter {
  WindowPresenter(this._host);

  final WindowHost _host;
  bool _visible = false;
  int _raise = 0;
  Future<void> _last = Future<void>.value();

  Future<void> apply(WindowState state) {
    final raise = state.visible && state.raise != _raise;
    _raise = state.raise;
    if (state.visible == _visible) {
      return raise ? _run(_host.bringToFront) : Future<void>.value();
    }
    _visible = state.visible;
    // A first show brings the window forward by itself.
    return _run(state.visible ? _host.show : _host.hide);
  }

  Future<void> _run(Future<void> Function() call) {
    final done = _last.then((_) => call());
    // A failed call is reported to this caller; the next one still runs.
    _last = done.catchError((Object _) {});
    return done;
  }
}

/// The native window calls [WindowManagerHost] makes, behind an interface
/// so its bring-to-front and bounds rules are testable without a window.
abstract interface class NativeWindow {
  Future<bool> isMinimized();
  Future<bool> isMaximized();
  Future<bool> isFullScreen();
  Future<void> restore();
  Future<void> maximize();
  Future<void> show();
  Future<void> hide();
  Future<void> focus();
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);
  Future<void> setSize(Size size);
  Future<void> center();

  /// macOS `NSApp.activate(ignoringOtherApps: true)`: a menu-bar app is
  /// not the active app when its tray menu is used, and focusing the
  /// window alone can leave it behind the frontmost app.
  Future<void> activateApp();

  /// macOS: the Dock icon and app menu (A1 D10).
  Future<void> setDockVisible(bool visible);

  /// Windows: the taskbar button.
  Future<void> setSkipTaskbar(bool skip);
}

/// [NativeWindow] over package window_manager and the app channel.
final class WindowManagerNative implements NativeWindow {
  const WindowManagerNative();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();
  @override
  Future<bool> isMaximized() => windowManager.isMaximized();
  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();
  @override
  Future<void> restore() => windowManager.restore();
  @override
  Future<void> maximize() => windowManager.maximize();
  @override
  Future<void> show() => windowManager.show();
  @override
  Future<void> hide() => windowManager.hide();
  @override
  Future<void> focus() => windowManager.focus();
  @override
  Future<Rect> getBounds() => windowManager.getBounds();
  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);
  @override
  Future<void> setSize(Size size) => windowManager.setSize(size);
  @override
  Future<void> center() => windowManager.center();
  @override
  Future<void> activateApp() => platform_app.activateMacApp();
  @override
  Future<void> setDockVisible(bool visible) =>
      platform_app.setDockVisible(visible);
  @override
  Future<void> setSkipTaskbar(bool skip) => windowManager.setSkipTaskbar(skip);
}

/// [WindowHost] over package window_manager: the resizable terminal window
/// (A1 D9, UI §2). The close button hides the window through
/// [onCloseRequested] instead of quitting; every shell keeps running.
///
/// This relies on window_manager's `setPreventClose(true)` fully intercepting
/// the native WM_CLOSE / performClose before the OS default handler runs, so
/// it always wins over Windows' `Win32Window::SetQuitOnClose(true)` (plan 04
/// Task 1): window_manager 0.5.2's Windows plugin returns early from the
/// top-level WindowProc for WM_CLOSE when prevent-close is on, so
/// `DestroyWindow`/`WM_DESTROY` (and therefore `PostQuitMessage`) is never
/// reached. `windows/runner/main.cpp` is left unchanged.
final class WindowManagerHost with WindowListener implements WindowHost {
  WindowManagerHost({
    required this.onCloseRequested,
    required this.bounds,
    this.onFocusChanged,
    Future<List<Rect>> Function()? displays,
    NativeWindow native = const WindowManagerNative(),
    bool? macos,
    bool? windows,
  }) : _displays = displays ?? _visibleDisplays,
       _native = native,
       _macos = macos ?? Platform.isMacOS,
       _windows = windows ?? Platform.isWindows;

  final void Function() onCloseRequested;

  /// A4 D25: the window gained (true) or lost the focus.
  final void Function(bool focused)? onFocusChanged;
  final WindowBoundsStore bounds;
  final Future<List<Rect>> Function() _displays;
  final NativeWindow _native;
  final bool _macos;
  final bool _windows;
  bool _placed = false;
  Timer? _save;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('ShellX');
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setMinimumSize(ShellxSizes.minWindow);
    if (_macos) {
      // UI §2.1: transparent title bar, traffic lights over the sidebar.
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: true,
      );
    } else {
      // UI §2.1: native title bar, dark.
      await windowManager.setBrightness(Brightness.dark);
    }
    windowManager.addListener(this);
  }

  @override
  Future<void> show() async {
    var maximize = false;
    if (!_placed) {
      // First show: the remembered bounds, else 1100×720 centred (UI §2);
      // maximized again if it was (over the last normal bounds, which
      // un-maximizing returns to).
      _placed = true;
      final saved = restorableBounds(bounds.read(), await _safeDisplays());
      if (saved != null) {
        await _native.setBounds(saved);
      } else {
        await _native.setSize(ShellxSizes.defaultWindow);
        await _native.center();
      }
      maximize = bounds.readMaximized();
    }
    // D10: Dock icon, ⌘Tab and the app menu (⌘Q) while visible; Windows: a
    // taskbar button.
    if (_macos) await _native.setDockVisible(true);
    if (_windows) await _native.setSkipTaskbar(false);
    await bringToFront();
    if (maximize) await _native.maximize();
  }

  @override
  Future<void> hide() async {
    await _native.hide();
    if (_macos) await _native.setDockVisible(false);
  }

  @override
  Future<void> bringToFront() async {
    // window_manager's show() restores a minimized window on its own, but
    // checking first keeps the order explicit (restore → show → focus).
    if (await _native.isMinimized()) await _native.restore();
    await _native.show();
    await _native.focus();
    if (_macos) await _native.activateApp();
  }

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  @override
  void onWindowClose() => onCloseRequested();

  @override
  void onWindowFocus() => onFocusChanged?.call(true);

  @override
  void onWindowBlur() => onFocusChanged?.call(false);

  @override
  void onWindowResized() => _remember();

  @override
  void onWindowMoved() => _remember();

  @override
  void onWindowMaximize() => _remember();

  @override
  void onWindowUnmaximize() => _remember();

  @override
  void onWindowEnterFullScreen() => _remember();

  @override
  void onWindowLeaveFullScreen() => _remember();

  /// Empty when the displays cannot be read (the saved bounds are kept).
  Future<List<Rect>> _safeDisplays() async {
    try {
      return await _displays();
    } catch (error) {
      debugPrint('ShellX: reading the displays failed: ${error.runtimeType}');
      return const [];
    }
  }

  static Future<List<Rect>> _visibleDisplays() async => [
    for (final display in await screenRetriever.getAllDisplays())
      (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size),
  ];

  /// Debounced: a drag fires many move/resize events.
  void _remember() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), saveBounds);
  }

  /// Maximized or full screen: only that is remembered; the bounds keep
  /// the last normal window, so the next launch (and un-maximizing) is not
  /// a window the size of the screen.
  @visibleForTesting
  Future<void> saveBounds() async {
    try {
      final maximized =
          await _native.isMaximized() || await _native.isFullScreen();
      await bounds.writeMaximized(maximized);
      if (!maximized) await bounds.write(await _native.getBounds());
    } catch (error) {
      debugPrint(
        'ShellX: reading the window bounds failed: '
        '${error.runtimeType}',
      );
    }
  }
}
