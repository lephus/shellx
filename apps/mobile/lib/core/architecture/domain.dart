import 'package:equatable/equatable.dart';

abstract class BaseDomain extends Equatable {
  final String id;

  const BaseDomain({required this.id});

  bool get isDummy => id.isEmpty;
  bool get isReal => id.isNotEmpty;
}
