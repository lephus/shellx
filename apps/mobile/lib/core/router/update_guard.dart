import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_mobile/core/router/app_router.gr.dart';
import 'package:shellx_mobile/core/version/version_gate.dart';

/// Spec §14: an app older than `min_mobile` shows only "Cần cập nhật app".
@injectable
class UpdateGuard extends AutoRouteGuard {
  final VersionGate versionGate;

  UpdateGuard(this.versionGate);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (versionGate.requiredVersion.peek() == null) {
      resolver.next(true);
    } else {
      router.replace(const UpdateRequiredRoute());
      resolver.next(false);
    }
  }
}
