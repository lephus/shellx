import 'package:shellx_mobile/core/architecture/domain.dart';

abstract class BaseDto {
  final String id;

  const BaseDto({
    required this.id,
  });

  BaseDomain toDomain() {
    throw UnimplementedError();
  }
}
