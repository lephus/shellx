/// A11 D31: how far the terminal is moved up so the cursor row stays above the keyboard.
///
/// [cursorBottom]: where the cursor row ends, from the top of the terminal area. [viewportHeight]: the
/// area's height. [keyboardInset]: how much of its bottom the keyboard (and the bars carried up with it)
/// covers. The row keeps [margin] of air above what covers it; the shift is never negative and never
/// more than [keyboardInset] (the view is not moved further than what is covered).
double cursorShift({
  required double cursorBottom,
  required double viewportHeight,
  required double keyboardInset,
  double margin = 8,
}) {
  final visibleBottom = viewportHeight - keyboardInset;
  final need = cursorBottom - (visibleBottom - margin);
  return need.clamp(0, keyboardInset).toDouble();
}
