import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:window_manager/window_manager.dart';

import '../platform/app_reopen.dart';
import 'theme/shellx_desktop_theme.dart';
import 'window_bounds.dart';
import 'window_router.dart';

abstract interface class WindowHost {
  Future<void> show();
  Future<void> hide();
  Future<void> setTitle(String title);
}

/// Shows/hides the single window to follow the router. Dialogs never
/// resize it (UI §4).
final class WindowPresenter {
  WindowPresenter(this._host);

  final WindowHost _host;
  bool _visible = false;

  Future<void> apply(WindowState state) async {
    if (state.visible == _visible) return;
    _visible = state.visible;
    await (state.visible ? _host.show() : _host.hide());
  }
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
  WindowManagerHost({required this.onCloseRequested, required this.bounds});

  final void Function() onCloseRequested;
  final WindowBoundsStore bounds;
  bool _placed = false;
  Timer? _save;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('ShellX');
    await windowManager.setResizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setMinimumSize(ShellxSizes.minWindow);
    if (Platform.isMacOS) {
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
    if (!_placed) {
      // First show: the remembered bounds, else 1100×720 centred (UI §2).
      _placed = true;
      final saved = bounds.read();
      if (saved != null) {
        await windowManager.setBounds(saved);
      } else {
        await windowManager.setSize(ShellxSizes.defaultWindow);
        await windowManager.center();
      }
    }
    // D10: Dock icon, ⌘Tab and the app menu (⌘Q) while visible; Windows: a
    // taskbar button.
    if (Platform.isMacOS) await setDockVisible(true);
    if (Platform.isWindows) await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) await setDockVisible(false);
  }

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  @override
  void onWindowClose() => onCloseRequested();

  @override
  void onWindowResized() => _remember();

  @override
  void onWindowMoved() => _remember();

  /// Debounced: a drag fires many move/resize events.
  void _remember() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () async {
      try {
        await bounds.write(await windowManager.getBounds());
      } catch (error) {
        debugPrint(
          'ShellX: reading the window bounds failed: '
          '${error.runtimeType}',
        );
      }
    });
  }
}
