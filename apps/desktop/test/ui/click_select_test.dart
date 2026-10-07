import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/click_select.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('ClickCounter (D12)', () {
    test('counts clicks close in time and place; the third is a triple', () {
      final c = ClickCounter();
      expect(c.register(const Offset(10, 10), Duration.zero), 1);
      expect(
        c.register(const Offset(11, 10), const Duration(milliseconds: 150)),
        2,
      );
      expect(
        c.register(const Offset(11, 11), const Duration(milliseconds: 300)),
        3,
      );
      expect(
        c.register(const Offset(11, 11), const Duration(milliseconds: 450)),
        1,
        reason: 'a fourth click starts over',
      );
    });

    test('too slow or too far starts over', () {
      final c = ClickCounter();
      c.register(Offset.zero, Duration.zero);
      expect(c.register(Offset.zero, const Duration(seconds: 2)), 1);
      expect(
        c.register(
          const Offset(300, 0),
          const Duration(seconds: 2, milliseconds: 100),
        ),
        1,
      );
    });
  });

  group('logicalLineRange', () {
    Terminal term(String text, {int cols = 10}) {
      final t = Terminal(maxLines: 100)..resize(cols, 5);
      t.write(text);
      return t;
    }

    test('a wrapped line is one logical line', () {
      final t = term('abcdefghijklmnopqrstuvwxyz\r\nnext'); // 3 rows + next
      final b = t.buffer;
      expect(logicalLineRange(b, 1), (first: 0, last: 2));
      expect(logicalLineRange(b, 0), (first: 0, last: 2));
      expect(logicalLineRange(b, 3), (first: 3, last: 3));
    });

    test('an empty row is its own line', () {
      final t = term('a\r\n\r\nb');
      expect(logicalLineRange(t.buffer, 1), (first: 1, last: 1));
    });
  });

  group('ClickSelectLayer', () {
    late Terminal terminal;
    late TerminalController controller;
    final viewKey = GlobalKey<TerminalViewState>();

    Future<void> pump(WidgetTester t, String text) async {
      terminal = Terminal(maxLines: 100);
      controller = TerminalController();
      terminal.write(text);
      await t.pumpWidget(
        MaterialApp(
          home: ClickSelectLayer(
            terminal: terminal,
            controller: controller,
            viewKey: viewKey,
            child: TerminalView(terminal, key: viewKey, controller: controller),
          ),
        ),
      );
      await t.pump();
    }

    Offset onText(WidgetTester t, {int col = 2, int row = 0}) {
      final render = viewKey.currentState!.renderTerminal;
      final origin = render.localToGlobal(Offset.zero);
      final cell = render.cellSize;
      return origin +
          Offset(cell.width * (col + 0.5), cell.height * (row + 0.5));
    }

    testWidgets('three quick clicks select the whole logical line', (t) async {
      await pump(t, 'hello world foo');
      final p = onText(t);
      await t.tapAt(p, kind: PointerDeviceKind.mouse);
      await t.tapAt(p, kind: PointerDeviceKind.mouse);
      expect(controller.selection, isNotNull, reason: 'double-click: a word');
      await t.tapAt(p, kind: PointerDeviceKind.mouse);
      await t.pump();
      expect(
        terminal.buffer.getText(controller.selection!).trimRight(),
        'hello world foo',
      );
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets('Alt-drag selects a rectangle, a plain drag a stream', (
      t,
    ) async {
      await pump(t, 'abcdefgh\r\nijklmnop\r\nqrstuvwx');
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final g = await t.startGesture(
        onText(t, col: 1, row: 0),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveTo(onText(t, col: 3, row: 2));
      await g.up();
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(controller.selectionMode, SelectionMode.block);
      expect(terminal.buffer.getText(controller.selection!), 'bcd\njkl\nrst');

      final plain = await t.startGesture(
        onText(t, col: 1, row: 0),
        kind: PointerDeviceKind.mouse,
      );
      await plain.moveTo(onText(t, col: 3, row: 1));
      await plain.up();
      await t.pump();
      expect(controller.selectionMode, SelectionMode.line);
      await t.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
      '⌘-clicks (links, A10) are not a triple-click',
      (t) async {
        await pump(t, 'hello world foo');
        final p = onText(t);
        await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        for (var i = 0; i < 3; i++) {
          await t.tapAt(p, kind: PointerDeviceKind.mouse);
        }
        await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await t.pump();
        expect(
          controller.selection == null ||
              terminal.buffer.getText(controller.selection!).trimRight() !=
                  'hello world foo',
          isTrue,
        );
        await t.pump(const Duration(milliseconds: 400));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('a program that has the mouse keeps it (no Alt)', (t) async {
      await pump(t, 'hello world foo\x1b[?1000h');
      final p = onText(t);
      await t.tapAt(p, kind: PointerDeviceKind.mouse);
      await t.tapAt(p, kind: PointerDeviceKind.mouse);
      await t.tapAt(p, kind: PointerDeviceKind.mouse);
      await t.pump();
      expect(controller.selection, isNull);
      await t.pump(const Duration(milliseconds: 400));
    });
  });
}
