import '../agent/agent_state.dart';
import 'window_router.dart';

/// Opens and closes windows when the agent state changes on its own
/// (startup, 4002 sign-out, a phone finishing pairing).
void coordinateWindows(
  AgentViewState? previous,
  AgentViewState next,
  WindowRouter router,
) {
  final before = previous?.phase;
  if (next.phase == AuthPhase.signedOut && before != AuthPhase.signedOut) {
    router.open(const LoginRoute());
  } else if (next.phase == AuthPhase.signedIn && before != AuthPhase.signedIn) {
    if (!next.onboardingDone) {
      router.open(const OnboardingRoute());
    } else if (router.current is LoginRoute) {
      router.close();
    }
  }
  if (previous?.pairing != null &&
      next.pairing == null &&
      router.current is PairingRoute) {
    router.close();
  }
}
