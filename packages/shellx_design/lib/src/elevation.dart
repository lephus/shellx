import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Inner shadows (A28): [BoxShadow] has no inset, so [ShellxInsetBox] paints
/// these inside its shape.
@immutable
final class ShellxInsetShadow {
  const ShellxInsetShadow(this.shadows);

  final List<BoxShadow> shadows;
}

/// V2-5a A28, §5.8: soft neumorphism. Raised = a dark shadow bottom-right
/// and a light one top-left; pressed loses both. Alpha values, so they
/// work on every navy layer. Each list is also a `static const` of its
/// own, for the desktop's `static const` tokens.
@immutable
final class ShellxElevation {
  const ShellxElevation._({
    required this.raised,
    required this.raisedSmall,
    required this.float1,
    required this.float2,
    required this.cta,
    required this.inset,
  });

  /// The phone's raised elements.
  final List<BoxShadow> raised;

  /// The desktop's raised elements; a selected segment.
  final List<BoxShadow> raisedSmall;

  /// Menus, toasts, tooltips.
  final List<BoxShadow> float1;

  /// Dialogs, sheets.
  final List<BoxShadow> float2;

  /// The phone's main button: one per screen.
  final List<BoxShadow> cta;

  /// The phone's fields, segmented tracks, slider tracks.
  final ShellxInsetShadow inset;

  static const ShellxElevation dark = ShellxElevation._(
    raised: darkRaised,
    raisedSmall: darkRaisedSmall,
    float1: darkFloat1,
    float2: darkFloat2,
    cta: darkCta,
    inset: ShellxInsetShadow(darkInset),
  );

  static const ShellxElevation light = ShellxElevation._(
    raised: lightRaised,
    raisedSmall: lightRaisedSmall,
    float1: lightFloat1,
    float2: lightFloat2,
    cta: lightCta,
    inset: ShellxInsetShadow(lightInset),
  );

  static const List<BoxShadow> darkRaised = [
    BoxShadow(offset: Offset(4, 4), blurRadius: 12, color: Color(0x59000000)),
    BoxShadow(offset: Offset(-3, -3), blurRadius: 10, color: Color(0x0FFFFFFF)),
  ];
  static const List<BoxShadow> darkRaisedSmall = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x59000000)),
    BoxShadow(offset: Offset(-1, -1), blurRadius: 4, color: Color(0x0DFFFFFF)),
  ];
  static const List<BoxShadow> darkInset = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x73000000)),
    BoxShadow(offset: Offset(-1, -1), blurRadius: 3, color: Color(0x0DFFFFFF)),
  ];

  /// The desktop's old `e1`.
  static const List<BoxShadow> darkFloat1 = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x73000000)),
  ];

  /// The desktop's old `e2`.
  static const List<BoxShadow> darkFloat2 = [
    BoxShadow(offset: Offset(0, 16), blurRadius: 48, color: Color(0x8C000000)),
  ];
  static const List<BoxShadow> darkCta = [
    BoxShadow(offset: Offset(0, 8), blurRadius: 20, color: Color(0x664E4AF2)),
  ];

  static const List<BoxShadow> lightRaised = [
    BoxShadow(offset: Offset(4, 4), blurRadius: 12, color: Color(0x40566A8C)),
    BoxShadow(offset: Offset(-4, -4), blurRadius: 12, color: Color(0xFFFFFFFF)),
  ];
  static const List<BoxShadow> lightRaisedSmall = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x33566A8C)),
    BoxShadow(offset: Offset(-2, -2), blurRadius: 6, color: Color(0xFFFFFFFF)),
  ];
  static const List<BoxShadow> lightInset = [
    BoxShadow(offset: Offset(2, 2), blurRadius: 6, color: Color(0x33566A8C)),
    BoxShadow(offset: Offset(-1, -1), blurRadius: 3, color: Color(0xCCFFFFFF)),
  ];
  static const List<BoxShadow> lightFloat1 = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x1F141A26)),
  ];
  static const List<BoxShadow> lightFloat2 = [
    BoxShadow(offset: Offset(0, 12), blurRadius: 32, color: Color(0x29141A26)),
  ];
  static const List<BoxShadow> lightCta = [
    BoxShadow(offset: Offset(0, 6), blurRadius: 16, color: Color(0x404E4AF2)),
  ];

  /// The desktop's `e1Elevation`: [darkFloat1] for Material surfaces that
  /// only take an elevation (the menu of `showMenu`).
  static const double float1Elevation = 8;

  /// The colour of [darkFloat1].
  static const Color float1ShadowColor = Color(0x73000000);
}
