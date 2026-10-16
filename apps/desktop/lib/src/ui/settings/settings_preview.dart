import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/shellx_config.dart' show TerminalFontWeight;

/// What the Appearance sample shows instead of the saved setting while the
/// user hovers, focuses or drags (A11 D8). Never written to the file and
/// never read by a real pane.
@immutable
final class PreviewState {
  const PreviewState({
    this.theme,
    this.fontSize,
    this.weight,
    this.cellHeightPercent,
    this.families,
  });

  final String? theme;
  final double? fontSize;
  final TerminalFontWeight? weight;
  final double? cellHeightPercent;
  final List<String>? families;

  PreviewState withoutTheme() => PreviewState(
    fontSize: fontSize,
    weight: weight,
    cellHeightPercent: cellHeightPercent,
    families: families,
  );

  bool get isEmpty =>
      theme == null &&
      fontSize == null &&
      weight == null &&
      cellHeightPercent == null &&
      families == null;

  PreviewState merge({
    String? theme,
    double? fontSize,
    TerminalFontWeight? weight,
    double? cellHeightPercent,
    List<String>? families,
  }) => PreviewState(
    theme: theme ?? this.theme,
    fontSize: fontSize ?? this.fontSize,
    weight: weight ?? this.weight,
    cellHeightPercent: cellHeightPercent ?? this.cellHeightPercent,
    families: families ?? this.families,
  );

  @override
  bool operator ==(Object other) =>
      other is PreviewState &&
      other.theme == theme &&
      other.fontSize == fontSize &&
      other.weight == weight &&
      other.cellHeightPercent == cellHeightPercent &&
      listEquals(other.families, families);

  @override
  int get hashCode => Object.hash(
    theme,
    fontSize,
    weight,
    cellHeightPercent,
    Object.hashAll(families ?? const []),
  );

  /// A value is the user's: never in a log.
  @override
  String toString() => '…';
}

final settingsPreviewProvider =
    NotifierProvider<SettingsPreview, PreviewState?>(SettingsPreview.new);

class SettingsPreview extends Notifier<PreviewState?> {
  @override
  PreviewState? build() => null;

  /// Shows these values in the sample; what was previewed before and is not
  /// named here stays.
  void preview({
    String? theme,
    double? fontSize,
    TerminalFontWeight? weight,
    double? cellHeightPercent,
    List<String>? families,
  }) {
    state = (state ?? const PreviewState()).merge(
      theme: theme,
      fontSize: fontSize,
      weight: weight,
      cellHeightPercent: cellHeightPercent,
      families: families,
    );
  }

  /// The pointer left the theme list and no row has the keyboard.
  void clearTheme() {
    final current = state;
    if (current == null || current.theme == null) return;
    final next = current.withoutTheme();
    state = next.isEmpty ? null : next;
  }

  void clear() {
    if (state != null) state = null;
  }
}
