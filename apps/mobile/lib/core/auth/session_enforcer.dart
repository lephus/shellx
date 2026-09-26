import 'package:shellx_mobile/core/core.dart';

/// Routes on session changes (base pattern: [SessionHolder] emits, this class navigates):
/// a sign-in opens the machine list; a sign-out, a 4002 revocation or a deleted account
/// clears every page — terminal, settings, dialogs — and shows the login page.
abstract class SessionEnforcer {
  void initialize();
  void dispose();
}

@Singleton(as: SessionEnforcer)
class SessionEnforcerImpl implements SessionEnforcer {
  final AuthEventNotifier authEventNotifier;
  final AppRouter router;

  EventDisposer? _disposer;

  SessionEnforcerImpl(this.authEventNotifier, this.router);

  @override
  @postConstruct
  void initialize() {
    _disposer = authEventNotifier.addListener(
      AuthEventKeys.sessionEnforcer,
      (event) => switch (event) {
        SignedInEvent() => router.replaceAll([const MachineListRoute()]),
        SignedOutEvent() => router.replaceAll([const LoginRoute()]),
      },
      priority: EventPriority.high,
    );
  }

  @override
  @disposeMethod
  void dispose() {
    _disposer?.dispose();
  }
}
