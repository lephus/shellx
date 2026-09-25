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

/// A yes/no question shown in the window on top of whatever route is open.
final class ConfirmRequest {
  ConfirmRequest({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get result => _completer.future;

  void complete(bool value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}

@immutable
final class WindowState {
  const WindowState({this.route, this.confirm});

  final WindowRoute? route;
  final ConfirmRequest? confirm;

  /// The single app window is shown only while something is open.
  bool get visible => route != null || confirm != null;
}

final windowRouterProvider = NotifierProvider<WindowRouter, WindowState>(
  WindowRouter.new,
);

/// Decides what the single Flutter window shows; hidden when nothing is open.
class WindowRouter extends Notifier<WindowState> {
  @override
  WindowState build() => const WindowState();

  WindowRoute? get current => state.route;

  void open(WindowRoute route) {
    final leaving = state.route;
    state = WindowState(route: route, confirm: state.confirm);
    _leave(leaving, next: route);
  }

  /// The window's close button, Escape, or a page that is done.
  void close() {
    final confirm = state.confirm;
    if (confirm != null) {
      confirm.complete(false);
      state = WindowState(route: state.route);
      return;
    }
    final leaving = state.route;
    state = const WindowState();
    _leave(leaving, next: null);
  }

  Future<bool> confirm(ConfirmRequest request) async {
    state.confirm?.complete(false);
    state = WindowState(route: state.route, confirm: request);
    final result = await request.result;
    if (ref.mounted && identical(state.confirm, request)) {
      state = WindowState(route: state.route);
    }
    return result;
  }

  void _leave(WindowRoute? current, {required WindowRoute? next}) {
    final agent = ref.read(agentControllerProvider.notifier);
    if (current is PairingRoute && next is! PairingRoute) {
      // Closing the QR window invalidates the pairing code (spec §5.3).
      agent.cancelPairing();
    }
    if (current is OnboardingRoute &&
        next is! OnboardingRoute &&
        !ref.read(agentControllerProvider).onboardingDone) {
      unawaited(agent.completeOnboarding());
    }
  }
}
