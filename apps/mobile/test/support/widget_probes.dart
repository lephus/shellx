import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// How many times each kind of widget is rebuilt (first builds included) from now on, until the test
/// ends. It is what a phone pays for a frame: a rebuild of an unchanged item is wasted work.
Map<Type, int> trackRebuilds() {
  final counts = <Type, int>{};
  debugOnRebuildDirtyWidget = (element, builtOnce) =>
      counts.update(element.widget.runtimeType, (n) => n + 1, ifAbsent: () => 1);
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  return counts;
}

Iterable<String> _laidOutTexts(WidgetTester tester) sync* {
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    yield w.text.toPlainText();
  }
  for (final w in tester.widgetList<EditableText>(find.byType(EditableText))) {
    yield w.controller.text;
  }
}

/// The length of the longest text any widget on screen lays out (what a one-line megabyte would cost).
int longestText(WidgetTester tester) {
  var longest = 0;
  for (final text in _laidOutTexts(tester)) {
    if (text.length > longest) longest = text.length;
  }
  return longest;
}

/// The most lines any text on screen lays out.
int mostLines(WidgetTester tester) {
  var most = 0;
  for (final text in _laidOutTexts(tester)) {
    final lines = '\n'.allMatches(text).length + 1;
    if (lines > most) most = lines;
  }
  return most;
}
