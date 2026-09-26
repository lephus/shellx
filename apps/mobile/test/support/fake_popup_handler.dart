import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:toastification/toastification.dart';

/// Records the toasts a controller or page shows instead of drawing them.
/// Register it with `getIt.registerSingleton<PopupHandler>(FakePopupHandler())`.
class FakePopupHandler implements PopupHandler {
  final List<String> errors = [];
  final List<String> successes = [];
  final List<String> infos = [];

  @override
  void showError({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) => errors.add(title);

  @override
  void showSuccess({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) => successes.add(title);

  @override
  void showInfo({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) => infos.add(title);

  @override
  void hide() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
