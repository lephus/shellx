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

  testWidgets('jitter around the threshold does not send extra keys or change the direction', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    expect(keys, [ExtraKey.right]);
    // A shaky finger: a few dp up and down, in and out of the 28 dp step.
    for (final dy in [4.0, -4.0, 5.0, -5.0, 4.0]) {
      await g.moveBy(Offset(-3, dy));
      await g.moveBy(Offset(3, -dy));
    }
    await g.moveBy(const Offset(-2, 0));
    await g.moveBy(const Offset(2, 0));
    await t.pump();
    expect(keys, [ExtraKey.right], reason: 'no immediate extra key');
    await t.pump(const Duration(milliseconds: 150));
    expect(keys.toSet(), {ExtraKey.right});
    await g.up();
  });

  testWidgets('a finger hovering just inside 14 dp keeps the arrow it has (dead band)', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(15, 0));
    await t.pump();
    await g.moveBy(const Offset(-3, 0)); // 12 dp: inside the dead band
    await t.pump(const Duration(milliseconds: 600));
    expect(keys.length, greaterThan(1), reason: 'still repeating');
    await g.moveBy(const Offset(-5, 0)); // 7 dp: released
    await t.pump();
    final n = keys.length;
    await t.pump(const Duration(seconds: 1));
    expect(keys.length, n);
    await g.up();
  });

  testWidgets('a diagonal keeps the current direction; a clear turn changes it', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    await g.moveBy(const Offset(0, 33)); // (30, 33): nearly a tie
    await t.pump();
    expect(keys, [ExtraKey.right]);
    await g.moveBy(const Offset(0, 9)); // (30, 42): clearly down
    await t.pump();
    expect(keys.last, ExtraKey.down);
    await g.up();
  });

  testWidgets('the repeat stops when the app leaves the foreground', (t) async {
    await pump(t);
    final g = await t.startGesture(t.getCenter(find.byType(ArrowPadKey)));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final n = keys.length;
    await t.pump(const Duration(seconds: 1));
    expect(keys.length, n);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(seconds: 1));
    expect(keys.length, n, reason: 'it does not restart by itself');
    await g.up();
  });
}
