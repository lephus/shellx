import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scrolls the Appearance page until the widget with [key] (a row below the
/// sample and the theme list) is built and on screen.
Future<void> revealOnAppearance(WidgetTester t, String key) async {
  final list = find.byKey(const Key('settings.appearance.list'));
  for (var i = 0; i < 12 && find.byKey(Key(key)).evaluate().isEmpty; i++) {
    // Drag on the padding strip above the nested theme list.
    await t.dragFrom(
      t.getTopLeft(list) + const Offset(4, 150),
      const Offset(0, -150),
    );
    await t.pump();
  }
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pump();
}
