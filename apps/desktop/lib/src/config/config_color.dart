import 'dart:math' as math;

import 'package:flutter/painting.dart';

final RegExp _hex = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$');

/// D14: `#RRGGBB`, `RRGGBB` or `#RGB`; anything else (X11 names) is null.
Color? parseConfigColor(String value) {
  final match = _hex.firstMatch(value.trim());
  if (match == null) return null;
  var hex = match.group(1)!;
  if (hex.length == 3) hex = [for (final c in hex.split('')) '$c$c'].join();
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio, 1–21.
double contrastRatio(Color a, Color b) {
  final x = _luminance(a);
  final y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}
