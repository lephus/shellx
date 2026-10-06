import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_controller.dart';

sealed class WindowRoute {
  const WindowRoute();
}

final class LoginRoute extends WindowRoute {
  const LoginRoute();
}

final class OnboardingRoute extends WindowRoute {
  const OnboardingRoute();
}

final class PairingRoute extends WindowRoute {
  const PairingRoute();
}

final class ChangePasswordRoute extends WindowRoute {
  const ChangePasswordRoute();
}

/// A yes/no question shown as a dialog on top of whatever route is open.
final class ConfirmRequest {
  ConfirmRequest({
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.long = false,
    this.destructive = true,
  });

  final String title;
  final String body;
  final String confirmLabel;

  /// A body of several paragraphs (a list of files): a wider dialog whose
  /// body scrolls (UI §4).
  final bool long;

  /// The confirm button is styled as dangerous (closing sessions, signing
  /// out); false for "Turn on".
  final bool destructive;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get result => _completer.future;

  void complete(bool value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}

@immutable
final class WindowState {
  const WindowState({this.route, this.confirm, this.terminal = false});

  final WindowRoute? route;
  final ConfirmRequest? confirm;

  /// The terminal window is shown (A1 D9). Closing it only hides it.
  final bool terminal;

  /// A legacy page or a confirm is shown as a dialog over the terminal.
  bool get dialogOpen => route != null || confirm != null;

  bool get visible => terminal || dialogOpen;
}

final windowRouterProvider = NotifierProvider<WindowRouter, WindowState>(
  WindowRouter.new,
);

/// What the window shows: always the terminal workspace, with at most one
/// dialog (a legacy route, and a confirm on top of it) over it.
class WindowRouter extends Notifier<WindowState> {
  @override
  WindowState build() => const WindowState();

  WindowRoute? get current => state.route;

  /// D11: launch, Dock, second launch, tray "Mở cửa sổ terminal".
  void showTerminal() => state = WindowState(
    route: state.route,
    confirm: state.confirm,
    terminal: true,
  );

  /// Opens [route] as a dialog (replacing the open one); the window shows
  /// first if it was hidden (UI §4).
  void open(WindowRoute route) {
    final leaving = state.route;
    state = WindowState(route: route, confirm: state.confirm, terminal: true);
    _leave(leaving, next: route);
  }

  /// Escape, Cancel, or a page that is done: closes the dialog on top. The
  /// window stays.
  void close() {
    final confirm = state.confirm;
    if (confirm != null) {
      confirm.complete(false);
      state = WindowState(route: state.route, terminal: state.terminal);
      return;
    }
    final leaving = state.route;
    state = WindowState(terminal: state.terminal);
    _leave(leaving, next: null);
  }

  /// The window's close button (A1 D9): the window hides, dialogs are
  /// cancelled, every shell keeps running.
  void hideWindow() {
    state.confirm?.complete(false);
    final leaving = state.route;
    state = const WindowState();
    _leave(leaving, next: null);
  }

  /// Shows [request] as a dialog (the window shows first if hidden). A
  /// confirm already open is answered "no" and replaced.
  Future<bool> confirm(ConfirmRequest request) async {
    state.confirm?.complete(false);
    state = WindowState(route: state.route, confirm: request, terminal: true);
    final result = await request.result;
    if (ref.mounted && identical(state.confirm, request)) {
      state = WindowState(route: state.route, terminal: state.terminal);
    }
    return result;
  }

  void _leave(WindowRoute? current, {required WindowRoute? next}) {
    final agent = ref.read(agentControllerProvider.notifier);
    if (current is PairingRoute && next is! PairingRoute) {
      // Closing the QR dialog invalidates the pairing code (spec §5.3).
      agent.cancelPairing();
    }
    if (current is OnboardingRoute &&
        next is! OnboardingRoute &&
        !ref.read(agentControllerProvider).onboardingDone) {
      unawaited(agent.completeOnboarding()); // Never throws.
    }
  }
}
