import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

/// Everything between dependency injection and the first route.
Future<void> prepareLaunch() async {
  // Spec §5.6: locked when the app opens (if enabled).
  final lock = getIt<AppLockController>();
  await lock.detectKind();
  lock.lockOnLaunch();
}
