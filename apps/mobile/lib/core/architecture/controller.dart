import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';

abstract class Controller {
  PopupHandler get popupHandler {
    _popupHandler ??= getIt<PopupHandler>();
    return _popupHandler!;
  }

  PopupHandler? _popupHandler;

  ErrorFactory get errorFactory {
    _errorFactory ??= ErrorFactory();
    return _errorFactory!;
  }

  ErrorFactory? _errorFactory;

  Future<void> mainStateGuard<T extends Equatable>(
    Future<T> Function() func, {
    required StateSignal<T> state,
    bool showError = false,
    String Function(AppError)? computeErrorMessage,
  }) async {
    try {
      state.loading();
      await batch(() async {
        final result = await func();
        state.complete(result);
      });
    } catch (e, stackTrace) {
      final error = _mapToAppError(e, stackTrace);
      _handleError(
        error,
        showError: showError,
        computeErrorMessage: computeErrorMessage,
      );
      state.failure(error);
    }
  }

  Future guard(
    Future Function() func, {
    bool showError = true,
    String Function(AppError)? computeErrorMessage,
  }) async {
    try {
      await func();
    } catch (e, stackTrace) {
      final error = _mapToAppError(e, stackTrace);
      _handleError(
        error,
        showError: showError,
        computeErrorMessage: computeErrorMessage,
      );
    }
  }

  void _handleError(
    AppError error, {
    required bool showError,
    String Function(AppError)? computeErrorMessage,
  }) {
    // Only the type: an API or relay failure may carry request details, and payloads, tokens and
    // passwords are never logged (overview §2).
    if (kDebugMode) debugPrint('Guard error: ${(error.originalError ?? error).runtimeType}');
    if (!showError) return;
    popupHandler.showError(
      title: computeErrorMessage?.call(error) ?? error.title,
      description: error.description,
    );
  }

  AppError _mapToAppError(Object e, StackTrace stackTrace) {
    if (e is AppError) return e;
    return errorFactory.fromException(e, stackTrace: stackTrace);
  }
}
