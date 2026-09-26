import 'package:equatable/equatable.dart';

class PageDomain<T extends Equatable> {
  final List<T> elements;
  final String? nextCursor;
  final int limit;
  bool get hasReachedEnd => nextCursor == null || elements.length < limit;

  PageDomain({
    required this.elements,
    required this.nextCursor,
    required this.limit,
  });
}
