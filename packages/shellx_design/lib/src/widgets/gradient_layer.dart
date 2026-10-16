import 'package:flutter/material.dart';

import '../gradients.dart';

/// V2-5a A38: a `ButtonStyle.backgroundBuilder` that paints [gradient]
/// behind a button's label. The widget stays a [FilledButton] (tests find
/// them by key); Material's ink would sit under the opaque gradient, so the
/// layer shades itself — black 8 % hovered, 16 % pressed — and rounds its
/// own corners. Disabled: the gradient at [disabledOpacity].
ButtonLayerBuilder shellxGradientLayer({
  required LinearGradient gradient,
  required BorderRadius borderRadius,
  required double disabledOpacity,
}) => (context, states, child) {
  final disabled = states.contains(WidgetState.disabled);
  final shade = disabled
      ? null
      : states.contains(WidgetState.pressed)
      ? ShellxGradients.pressedShade
      : states.contains(WidgetState.hovered)
      ? ShellxGradients.hoverShade
      : null;
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: disabled ? gradient.scale(disabledOpacity) : gradient,
      borderRadius: borderRadius,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: shade ?? const Color(0x00000000),
        borderRadius: borderRadius,
      ),
      child: child,
    ),
  );
};
