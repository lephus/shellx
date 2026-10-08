import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/arrow_pad.dart';

import '../../support/app_harness.dart';

void main() {
  test('the dominant axis wins beyond 14 dp, nothing below', () {
    expect(padDirection(const Offset(10, 5)), isNull);
    expect(padDirection(const Offset(20, 5)), PadDirection.right);
    expect(padDirection(const Offset(-20, 5)), PadDirection.left);
    expect(padDirection(const Offset(5, 30)), PadDirection.down);
    expect(padDirection(const Offset(5, -30)), PadDirection.up);
    expect(padDirection(const Offset(20, 20)), PadDirection.right, reason: 'tie → horizontal');
    expect(padDirection(const Offset(10, 10)), isNull, reason: 'a diagonal of 14 dp is 10 on each axis');
  });

  test('speed grows with distance: 4, 10 then 20 keys a second', () {
    expect(padInterval(10), isNull);
    expect(padInterval(20), const Duration(milliseconds: 250));
    expect(padInterval(40), const Duration(milliseconds: 100));
    expect(padInterval(80), const Duration(milliseconds: 50));
  });

  late List<ExtraKey> keys;

  setUp(() => keys = []);

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(
      localized(
        Scaffold(
          body: Center(child: ArrowPadKey(onKey: keys.add)),
        ),
      ),
    );
  }

  testWidgets('dragging right and holding repeats the key; releasing stops it', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    expect(keys, [ExtraKey.right], reason: 'one at once');
    await t.pump(const Duration(milliseconds: 520));
    expect(keys.length, greaterThanOrEqualTo(3));
    expect(keys.toSet(), {ExtraKey.right});
    await g.up();
    final n = keys.length;
    await t.pump(const Duration(seconds: 1));
    expect(keys.length, n);
  });

  testWidgets('dragging further repeats faster', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(0, -20));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1000));
    final slow = keys.length;
    expect(slow, inInclusiveRange(4, 6), reason: '4 a second');
    keys.clear();
    await g.moveBy(const Offset(0, -40));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1000));
    expect(keys.length, greaterThan(slow * 2), reason: 'the further, the faster');
    expect(keys.length, lessThan(60), reason: 'bounded');
    await g.up();
  });

  testWidgets('changing direction while held changes the key', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    await g.moveBy(const Offset(-60, 0));
    await t.pump();
    expect(keys, [ExtraKey.right, ExtraKey.left]);
    await t.pump(const Duration(milliseconds: 300));
    expect(keys.last, ExtraKey.left);
    await g.up();
  });

  testWidgets('moving back to the middle stops the repeat', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    await g.moveBy(const Offset(-30, 0));
    await t.pump();
    final n = keys.length;
    await t.pump(const Duration(seconds: 1));
    expect(keys.length, n);
    await g.up();
  });

  testWidgets('a tap sends nothing', (t) async {
    await pump(t);
    await t.tap(find.byType(ArrowPadKey));
    await t.pump(const Duration(seconds: 1));
    expect(keys, isEmpty);
  });

  testWidgets('removing the pad while held stops the timer', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    final n = keys.length;
    await t.pump(const Duration(seconds: 1));
    expect(keys.length, n);
    await g.up();
  });

  testWidgets('screen readers get four actions that each send one arrow', (t) async {
    final handle = t.ensureSemantics();
    await pump(t);
    final node = t.getSemantics(find.bySemanticsLabel('Bàn xoay mũi tên. Kéo để di chuyển con trỏ.'));
    final data = node.getSemanticsData();
    final actions = data.customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .whereType<CustomSemanticsAction>();
    expect(actions.map((a) => a.label), ['Lên', 'Xuống', 'Trái', 'Phải']);
    for (final action in actions) {
      t.semantics.performAction(
        find.semantics.byLabel('Bàn xoay mũi tên. Kéo để di chuyển con trỏ.'),
        SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(action),
      );
    }
    expect(keys, [ExtraKey.up, ExtraKey.down, ExtraKey.left, ExtraKey.right]);
    handle.dispose();
  });
}
