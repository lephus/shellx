import '../agent/agent_state.dart';
import 'window_router.dart';

/// Opens and closes dialogs when the agent state changes on its own (a
/// sign-out or 4002 while running, sign-in, a phone finishing pairing, an
/// update becoming required).
/// Startup signed out opens nothing: the signed-out strip invites instead
/// (A1 D11).
void coordinateWindows(
  AgentViewState? previous,
  AgentViewState next,
  WindowRouter router,
) {
  final before = previous?.phase;
  if (next.phase == AuthPhase.signedOut && before == AuthPhase.signedIn) {
    // A sign-out or a 4002 while running: ask to sign in again. At startup
    // the signed-out strip invites instead (A1 D11: the terminal works
    // signed out).
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
  // Contract §5: when the block starts, the window shows why phones can no
  // longer connect ("Update required", WindowContent).
  if (next.updateRequired && !(previous?.updateRequired ?? false)) {
    router.showTerminal();
  }
}
