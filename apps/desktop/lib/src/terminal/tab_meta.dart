import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// A11 D18: the longest tab description, in user-perceived characters.
const int kTabDescriptionMaxLength = 120;

/// The user's mark on a tab's progress. The wire names are what
/// `layout.json` stores; an unknown one reads as [none].
enum TabStatus {
  none('none'),
  inProgress('in_progress'),
  review('review'),
  blocked('blocked'),
  done('done');

  const TabStatus(this.wire);
  final String wire;

  static TabStatus fromWire(Object? text) {
    for (final s in values) {
      if (s.wire == text) return s;
    }
    return none;
  }
}

/// Line breaks and tabs become one space; everything that could repaint
/// or reorder the sidebar does not survive: C0/C1 controls, line and
/// paragraph separators, and the bidirectional marks and isolates (same
/// set as `cleanServerText`, which lives in the UI layer).
final RegExp _breaks = RegExp(r'[\r\n\t]+');
final RegExp _unsafe = RegExp(
  r'[\x00-\x1f\x7f-\x9f\u2028\u2029\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]',
);

/// Pin, description and status of one tab (A11 D18). The description is
/// the user's own text: never logged, so [toString] hides everything.
@immutable
final class TabMeta {
  const TabMeta({
    this.pinned = false,
    this.description = '',
    this.status = TabStatus.none,
  });

  static const TabMeta empty = TabMeta();

  final bool pinned;
  final String description;
  final TabStatus status;

  bool get isEmpty =>
      !pinned && description.isEmpty && status == TabStatus.none;

  TabMeta copyWith({bool? pinned, String? description, TabStatus? status}) =>
      TabMeta(
        pinned: pinned ?? this.pinned,
        description: description ?? this.description,
        status: status ?? this.status,
      );

  /// One line of at most [kTabDescriptionMaxLength] graphemes, trimmed,
  /// without control or bidirectional characters. Blank gives ''.
  static String cleanDescription(String raw) => raw
      .replaceAll(_breaks, ' ')
      .replaceAll(_unsafe, '')
      .trim()
      .characters
      .take(kTabDescriptionMaxLength)
      .toString()
      .trim();

  @override
  bool operator ==(Object other) =>
      other is TabMeta &&
      other.pinned == pinned &&
      other.description == description &&
      other.status == status;

  @override
  int get hashCode => Object.hash(pinned, description, status);

  @override
  String toString() => '…';
}

/// [ids] with the pinned ones first; the order inside each group stays.
List<int> sortPinnedFirst(List<int> ids, bool Function(int id) pinned) => [
  ...ids.where(pinned),
  ...ids.where((id) => !pinned(id)),
];
