import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'window_router.dart';

/// The native window has the keyboard focus (A4 D25), from window_manager's
/// focus/blur events (`main.dart`).
final windowFocusProvider = NotifierProvider<WindowFocus, bool>(
  WindowFocus.new,
);

class WindowFocus extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool focused) {
    if (state != focused) state = focused;
  }
}

/// The user can be looking at the window: shown and focused (A4 D7, D10,
/// D14). Minimized or hidden is never active.
final windowActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(windowFocusProvider) && ref.watch(windowRouterProvider).visible,
);

/// Bumped when something outside the page (a notification click, the
/// panel, next unread) wants the keyboard in the selected tab's terminal;
/// `TerminalWorkspacePage` listens.
final terminalFocusRequestProvider = NotifierProvider<FocusRequest, int>(
  FocusRequest.new,
);

class FocusRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}
