import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio of two opaque colours: 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [foreground] painted over the opaque [background].
Color compositeOver(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background);

/// The lowest contrast of [text] over [gradient], sampled at [samples]
/// evenly spaced points and interpolated in sRGB as Flutter does; with
/// [overlay] (a hover or pressed shade) painted over the gradient first.
double minContrastOnGradient(
  LinearGradient gradient,
  Color text, {
  int samples = 101,
  Color? overlay,
}) {
  final colors = gradient.colors;
  final stops =
      gradient.stops ??
      [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)];
  Color at(double t) {
    if (t <= stops.first) return colors.first;
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final span = stops[i] - stops[i - 1];
        final local = span == 0 ? 0.0 : (t - stops[i - 1]) / span;
        return Color.lerp(colors[i - 1], colors[i], local)!;
      }
    }
    return colors.last;
  }

  var lowest = double.infinity;
  for (var i = 0; i < samples; i++) {
    var colour = at(i / (samples - 1));
    if (overlay != null) colour = compositeOver(overlay, colour);
    lowest = math.min(lowest, contrastRatio(text, colour));
  }
  return lowest;
}
