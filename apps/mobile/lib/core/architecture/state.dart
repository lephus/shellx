import 'package:shellx_mobile/core/architecture/error.dart';

sealed class IState {
  final bool isLoading;
  final bool hasError;

  const IState({required this.isLoading, required this.hasError});

  bool get available => !isLoading && !hasError && ((this is InitState) == false);

  AppError? get error => null;
}

class InitState extends IState {
  const InitState() : super(isLoading: false, hasError: false);
}

class LoadingState extends IState {
  LoadingState() : super(isLoading: true, hasError: false);
}

class ErrorState extends IState {
  @override
  final AppError error;

  ErrorState(this.error) : super(isLoading: false, hasError: true);

  String get message => error.toString();
}

class SuccessState extends IState {
  SuccessState() : super(isLoading: false, hasError: false);
}
