import 'package:flutter/widgets.dart';

/// V2-5a §5.8. Use [of] so reduced motion turns every duration to zero.
abstract final class ShellxDurations {
  /// Hover, colour.
  static const Duration fast = Duration(milliseconds: 80);

  /// The phone's press.
  static const Duration press = Duration(milliseconds: 100);
  static const Duration exit = Duration(milliseconds: 120);

  /// A dialog coming in, a fade.
  static const Duration base = Duration(milliseconds: 150);
  static const Duration toastIn = Duration(milliseconds: 160);

  /// A segment's tile, the bottom bar's active tile.
  static const Duration slide = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 250);

  /// How long a desktop toast stays: 4 s, an error 6 s.
  static const Duration toastVisible = Duration(seconds: 4);
  static const Duration toastVisibleError = Duration(seconds: 6);

  /// How long a phone toast stays.
  static const Duration toastVisiblePhone = Duration(seconds: 3);
  static const Duration tooltipWait = Duration(milliseconds: 500);
  static const Duration scrollbarFade = Duration(milliseconds: 800);

  /// Hovering a dragged tab over a collapsed header expands it.
  static const Duration dragExpandDelay = Duration(milliseconds: 600);

  /// [duration], or zero when the platform asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// V2-5a §5.8: the curves that go with [ShellxDurations].
abstract final class ShellxCurves {
  static const Curve fast = Curves.easeOut;
  static const Curve press = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
  static const Curve base = Curves.easeOutCubic;
  static const Curve slide = Curves.easeOutCubic;
}
