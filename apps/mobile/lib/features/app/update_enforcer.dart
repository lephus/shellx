import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/launch.dart';

/// Force update (contract §5): the version gate runs again whenever the app returns to the
/// foreground, 10 minutes apart at least ([VersionGate.recheck]). An app found too old loses every
/// page for "Cần cập nhật app"; a blocked app that no longer is (the admin lowered `min_mobile`)
/// goes on the way launch does: the saved session, then the first page.
@lazySingleton
class UpdateEnforcer {
  UpdateEnforcer({required VersionGate gate, required StackRouter router, required SessionHolder session})
    : _gate = gate,
      _router = router,
      _session = session;

  @factoryMethod
  static UpdateEnforcer create(VersionGate gate, AppRouter router, SessionHolder session) =>
      UpdateEnforcer(gate: gate, router: router, session: session);

  final VersionGate _gate;
  final StackRouter _router;
  final SessionHolder _session;

  /// Never throws. Only a change of the gate's answer navigates: the update page a machine's
  /// `proto_unsupported` opened is left as it is, and an offline check changes nothing.
  Future<void> onForeground() async {
    final wasRequired = _gate.requiredVersion.peek() != null;
    try {
      if (!await _gate.recheck()) return;
      final required = _gate.requiredVersion.peek() != null;
      if (required && !wasRequired) {
        await _router.replaceAll([const UpdateRequiredRoute()]);
      } else if (!required && wasRequired) {
        // A blocked launch never restored the saved session.
        if (!_session.isAuthenticated.peek()) await restoreSession(_session);
        // The launch's first page: its guards pick the machine list or the login page.
        await _router.replaceAll([const MachineListRoute()]);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('UpdateEnforcer error: ${error.runtimeType}');
    }
  }
}
