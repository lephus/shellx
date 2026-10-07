import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:xterm/xterm.dart';

Future<void> _load(String family, Map<String, int> files) async {
  final loader = FontLoader(family);
  for (final f in files.keys) {
    loader.addFont(
      Future.value(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
      ),
    );
  }
  await loader.load();
}

/// Sum of (255 - luminance) over the image on a white background, i.e. ink.
Future<double> _ink(WidgetTester tester, GlobalKey key) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData())!;
    var sum = 0.0;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      sum += 255 - bytes.getUint8(i);
    }
    return sum;
  }))!;
}

void main() {
  const text = 'llll||||IIII';

  Future<double> terminalInk(WidgetTester tester, TerminalStyle style) async {
    final key = GlobalKey();
    final terminal = Terminal()..write(text);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 300,
              height: 40,
              child: TerminalView(
                terminal,
                textStyle: style,
                theme: const TerminalTheme(
                  cursor: Color(0x00000000),
                  selection: Color(0x00000000),
                  foreground: Color(0xFF000000),
                  background: Color(0xFFFFFFFF),
                  black: Color(0xFF000000),
                  red: Color(0xFF000000),
                  green: Color(0xFF000000),
                  yellow: Color(0xFF000000),
                  blue: Color(0xFF000000),
                  magenta: Color(0xFF000000),
                  cyan: Color(0xFF000000),
                  white: Color(0xFF000000),
                  brightBlack: Color(0xFF000000),
                  brightRed: Color(0xFF000000),
                  brightGreen: Color(0xFF000000),
                  brightYellow: Color(0xFF000000),
                  brightBlue: Color(0xFF000000),
                  brightMagenta: Color(0xFF000000),
                  brightCyan: Color(0xFF000000),
                  brightWhite: Color(0xFF000000),
                  searchHitBackground: Color(0x00000000),
                  searchHitBackgroundCurrent: Color(0x00000000),
                  searchHitForeground: Color(0x00000000),
                ),
                cursorType: TerminalCursorType.block,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return _ink(tester, key);
  }

  Future<double> plainInk(WidgetTester tester, FontWeight w) async {
    final key = GlobalKey();
    final style = desktopTerminalStyle(
      13,
      thicken: true,
    ).toTextStyle(color: const Color(0xFF000000));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFFFFFFFF),
              width: 300,
              height: 40,
              child: Text(text, style: style.copyWith(fontWeight: w)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return _ink(tester, key);
  }

  // Why the default is the Light face: with the Regular face a normal
  // terminal cell is drawn at exactly weight 400 (the first expectation),
  // yet Flutter's grayscale antialiasing looks heavier than Ghostty's
  // CoreText rendering of the same face (font-thicken off). The default
  // therefore draws normal cells with JetBrains Mono Light, registered as
  // its own family so cells keep asking for plain `normal` / `bold`.
  testWidgets('normal cells use the Light face unless font-thicken; bold '
      'stays Bold', (tester) async {
    await tester.runAsync(() async {
      await _load('JetBrainsMono', {
        'JetBrainsMono-Regular.ttf': 400,
        'JetBrainsMono-Bold.ttf': 700,
      });
      await _load('JetBrainsMonoLight', {
        'JetBrainsMono-Light.ttf': 400,
        'JetBrainsMono-Bold.ttf': 700,
      });
    });
    final regular = await terminalInk(
      tester,
      desktopTerminalStyle(13, thicken: true),
    );
    final w400 = await plainInk(tester, FontWeight.w400);
    final w700 = await plainInk(tester, FontWeight.w700);
    final light = await terminalInk(tester, desktopTerminalStyle(13));
    // ignore: avoid_print
    print('ink regular=$regular w400=$w400 w700=$w700 light=$light');
    expect(w700, greaterThan(w400 * 1.1), reason: 'faces must differ');
    expect(regular, closeTo(w400, w400 * 0.05));
    expect(light, lessThan(regular * 0.9));
    expect(light, greaterThan(regular * 0.5));
  });
}
