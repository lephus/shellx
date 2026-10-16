import 'package:shellx_mobile/core/core.dart';

/// Why the app went back to the login screen; the login page explains the last two.
enum SignOutReason { loggedOut, revoked, accountDeleted }

// Events
sealed class AuthEvent {
  const AuthEvent();
}

/// A login or registration succeeded (not emitted when a saved session is restored at launch).
final class SignedInEvent extends AuthEvent {
  const SignedInEvent();
}

final class SignedOutEvent extends AuthEvent {
  const SignedOutEvent(this.reason);
  final SignOutReason reason;
}

// Event keys (constants to avoid magic strings)
class AuthEventKeys {
  static const sessionEnforcer = 'session_enforcer';
}

// Event Notifier
@lazySingleton
class AuthEventNotifier extends EventNotifier<AuthEvent> {}
