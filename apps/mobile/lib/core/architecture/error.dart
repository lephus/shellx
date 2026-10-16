import 'package:shellx_mobile/shared/shared.dart';

class AppError extends Error {
  final String title;
  final String? description;
  final Object? originalError;
  @override
  final StackTrace? stackTrace;

  AppError({
    required this.title,
    this.description,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => title;
}

class ForbiddenError extends AppError {
  ForbiddenError({
    String? title,
    super.description,
    super.originalError,
    super.stackTrace,
  }) : super(title: title ?? S.current.forbiddenTitle);
}

class NetworkError extends AppError {
  NetworkError({
    String? title,
    super.description,
    super.originalError,
    super.stackTrace,
  }) : super(title: title ?? S.current.networkError);
}

class NotFoundError extends AppError {
  NotFoundError({
    String? title,
    super.description,
    super.originalError,
    super.stackTrace,
  }) : super(title: title ?? S.current.notFound);
}

class UnauthorizedError extends AppError {
  UnauthorizedError({
    String? title,
    super.description,
    super.originalError,
    super.stackTrace,
  }) : super(title: title ?? S.current.unauthorized);
}

class UnknownError extends AppError {
  UnknownError({
    String? title,
    super.description,
    super.originalError,
    super.stackTrace,
  }) : super(title: title ?? S.current.unknownError);
}
