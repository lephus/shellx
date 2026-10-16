import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  Widget frame(Widget child, {Brightness brightness = Brightness.dark}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(child: SizedBox(width: 200, height: 100, child: child)),
        ),
      );

  group('ShellxWedge (A30)', () {
    test('the triangle sits in its corner: 45 % across, 70 % down', () {
      const size = Size(200, 100);
      expect(
        const ShellxWedgePainter(
          corner: ShellxWedgeCorner.topRight,
          widthFactor: 0.45,
          heightFactor: 0.7,
        ).points(size),
        const [Offset(110, 0), Offset(200, 0), Offset(200, 70)],
      );
      expect(
        const ShellxWedgePainter(
          corner: ShellxWedgeCorner.bottomLeft,
          widthFactor: 0.45,
          heightFactor: 0.7,
        ).points(size),
        const [Offset(90, 100), Offset(0, 100), Offset(0, 30)],
      );
    });

    testWidgets('paints the wedge gradient; no semantics, no taps', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        frame(
          Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => tapped++,
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
              const Positioned.fill(child: ShellxWedge()),
            ],
          ),
        ),
      );
      final wedge = find.byType(ShellxWedge);
      expect(
        find.descendant(of: wedge, matching: find.byType(CustomPaint)),
        paints..path(
          includes: const [Offset(190, 10)],
          excludes: const [Offset(10, 90), Offset(120, 60)],
        ),
      );
      expect(
        find.descendant(of: wedge, matching: find.byType(RepaintBoundary)),
        findsOneWidget,
      );
      await tester.tapAt(tester.getTopRight(wedge) + const Offset(-5, 5));
      expect(tapped, 1, reason: 'the tap went through');
      final semantics = tester.ensureSemantics();
      expect(
        find.descendant(of: wedge, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('ShellxGlass (A29)', () {
    testWidgets('blurs only when asked', (tester) async {
      await tester.pumpWidget(frame(const ShellxGlass(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.pumpWidget(
        frame(const ShellxGlass(blur: false, child: Text('x'))),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('fill and border follow the brightness', (tester) async {
      Color fill() =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byType(ShellxGlass),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      await tester.pumpWidget(
        frame(const ShellxGlass(blur: false, child: Text('x'))),
      );
      expect(fill(), ShellxPalette.glassFill);
      await tester.pumpWidget(
        frame(
          const ShellxGlass(blur: false, child: Text('x')),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle(); // MaterialApp animates a theme change.
      expect(fill(), ShellxLightPalette.glassFill);
      expect(ShellxGlass.sigma, 16);
    });
  });

  group('ShellxInsetBox (A28)', () {
    testWidgets('paints the fill, then each inner shadow, then the border', (
      tester,
    ) async {
      await tester.pumpWidget(
        frame(
          ShellxInsetBox(
            color: ShellxPalette.navy900,
            shadow: ShellxElevation.dark.inset,
            borderRadius: BorderRadius.circular(16),
            border: const BorderSide(color: ShellxPalette.fieldOutline),
            child: const SizedBox.expand(),
          ),
        ),
      );
      final box = find.descendant(
        of: find.byType(ShellxInsetBox),
        matching: find.byType(CustomPaint),
      );
      expect(
        box,
        paints
          ..rrect(color: ShellxPalette.navy900)
          ..save()
          ..clipRRect()
          ..path(color: const Color(0x73000000))
          ..path(color: const Color(0x0DFFFFFF))
          ..restore()
          ..rrect(
            color: ShellxPalette.fieldOutline,
            style: PaintingStyle.stroke,
          ),
      );
    });

    test('repaints only when its look changes', () {
      final a = ShellxInsetPainter(
        color: ShellxPalette.navy900,
        shadow: ShellxElevation.dark.inset,
        borderRadius: BorderRadius.circular(16),
      );
      final b = ShellxInsetPainter(
        color: ShellxPalette.navy900,
        shadow: ShellxElevation.dark.inset,
        borderRadius: BorderRadius.circular(16),
      );
      final c = ShellxInsetPainter(
        color: ShellxPalette.navy850,
        shadow: ShellxElevation.dark.inset,
        borderRadius: BorderRadius.circular(16),
      );
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });
  });

  group('ShellxSlantBorder', () {
    test('the top edge rises 4 px from left to right, corners rounded 10', () {
      const border = ShellxSlantBorder();
      final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 56, 36));
      expect(
        path.contains(const Offset(28, 1.5)),
        isFalse,
        reason: 'above the slope',
      );
      expect(path.contains(const Offset(28, 3)), isTrue);
      expect(path.contains(const Offset(28, 35)), isTrue);
      expect(
        path.contains(const Offset(0.5, 0.5)),
        isFalse,
        reason: 'a rounded corner',
      );
      expect(path.contains(const Offset(55.5, 35.5)), isFalse);
      expect(border.radius, 10);
      expect(border.slant, 4);
      expect(border.copyWith(side: const BorderSide(width: 2)).side.width, 2);
      expect(border.scale(2).radius, 20);
    });
  });

  group('shellxGradientLayer (A38)', () {
    final radius = BorderRadius.circular(10);
    final builder = shellxGradientLayer(
      gradient: ShellxGradients.accentStrong,
      borderRadius: radius,
      disabledOpacity: 0.38,
    );

    Future<(BoxDecoration, BoxDecoration)> layers(
      WidgetTester tester,
      Set<WidgetState> states,
    ) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) =>
              builder(context, states, const SizedBox(width: 80, height: 32)),
        ),
      );
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .toList();
      return (
        boxes[0].decoration as BoxDecoration,
        boxes[1].decoration as BoxDecoration,
      );
    }

    testWidgets('idle: the gradient, rounded, no shade', (tester) async {
      final (back, shade) = await layers(tester, {});
      expect(back.gradient, ShellxGradients.accentStrong);
      expect(back.borderRadius, radius);
      expect(shade.color, const Color(0x00000000));
      expect(shade.borderRadius, radius);
    });

    testWidgets('hovered: black 8 %; pressed: black 16 %', (tester) async {
      expect(
        (await layers(tester, {WidgetState.hovered})).$2.color,
        const Color(0x14000000),
      );
      expect(
        (await layers(tester, {WidgetState.pressed})).$2.color,
        const Color(0x29000000),
      );
      expect(
        (await layers(tester, {
          WidgetState.hovered,
          WidgetState.pressed,
        })).$2.color,
        const Color(0x29000000),
      );
    });

    testWidgets('disabled: the gradient faded, no shade', (tester) async {
      final (back, shade) = await layers(tester, {
        WidgetState.disabled,
        WidgetState.hovered,
      });
      final faded = back.gradient! as LinearGradient;
      expect(faded.colors.first.a, closeTo(0.38, 0.01));
      expect(faded.colors.last.a, closeTo(0.38, 0.01));
      expect(shade.color, const Color(0x00000000));
    });
  });
}
