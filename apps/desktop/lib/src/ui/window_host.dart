import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'window_router.dart';

abstract interface class WindowHost {
  Future<void> show(Size size);
  Future<void> hide();
}

Size windowSizeFor(WindowState state) {
  if (state.confirm != null) return const Size(440, 260);
  return switch (state.route) {
    LoginRoute() => const Size(440, 620),
    OnboardingRoute() => const Size(520, 660),
    PairingRoute() => const Size(440, 660),
    ChangePasswordRoute() => const Size(440, 480),
    null => const Size(440, 260),
  };
}

/// Shows/hides the single window to follow the router.
final class WindowPresenter {
  WindowPresenter(this._host);

  final WindowHost _host;
  bool _visible = false;
  Size? _size;

  Future<void> apply(WindowState state) async {
    if (!state.visible) {
      if (_visible) await _host.hide();
      _visible = false;
      return;
    }
    final size = windowSizeFor(state);
    if (_visible && size == _size) return;
    _visible = true;
    _size = size;
    await _host.show(size);
  }
}

/// [WindowHost] over package window_manager. The native close button hides
/// the window through [onCloseRequested] instead of quitting the app.
///
/// This relies on window_manager's `setPreventClose(true)` fully intercepting
/// the native WM_CLOSE / performClose before the OS default handler runs, so
/// it always wins over Windows' `Win32Window::SetQuitOnClose(true)` (Task 1):
/// confirmed by reading window_manager 0.5.2's Windows plugin — it returns
/// early from the top-level WindowProc for WM_CLOSE when prevent-close is on,
/// so `DestroyWindow`/`WM_DESTROY` (and therefore `PostQuitMessage`) is never
/// reached. `windows/runner/main.cpp` is left unchanged.
final class WindowManagerHost with WindowListener implements WindowHost {
  WindowManagerHost({required this.onCloseRequested});

  final void Function() onCloseRequested;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('ShellX');
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    windowManager.addListener(this);
  }

  @override
  Future<void> show(Size size) async {
    await windowManager.setSize(size);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  void onWindowClose() => onCloseRequested();
}
