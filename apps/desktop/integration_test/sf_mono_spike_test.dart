import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §6.3, the SF Mono spike: its five pass criteria on a real Apple
/// platform, through the runner's channel and [ShellxSystemFont.load] only.
/// It never runs the app's `main()`: no settings, no Keychain, no relay.
/// macOS: only in the isolated build of plan Task 1 (bundle id
/// pro.shellx.desktop.itest, a temporary HOME). iOS: a simulator or device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SF Mono spike: bytes, coverage, width, weights, no files', (
    tester,
  ) async {
    final root = _appRoot();
    final before = _files(root);

    // 1. The upright and the italic, each over 100 KB, within 150 ms.
    final watch = Stopwatch()..start();
    final answer = await ShellxSystemFont.channel
        .invokeMapMethod<String, Object?>('monospaced');
    final ms = watch.elapsedMilliseconds;
    final regular = answer!['regular']! as Uint8List;
    final italic = answer['italic']! as Uint8List;
    // 2. A glyph for each of the 134 letters and the 5 combining marks.
    final missing = answer['missing']! as List<Object?>;

    final status = await ShellxSystemFont.load();

    // 3. Drawn with the loaded family: SF Mono is 0.618 em a cell.
    final sfMono = _width(ShellxFonts.systemMono);
    final jetBrains = _width(ShellxFonts.bundledMono);

    // 4. More ink at each heavier weight; the italic is not the upright.
    final ink = <double, double>{};
    for (final weight in [300.0, 400.0, 600.0, 700.0]) {
      ink[weight] = _ink(await _draw(tester, weight: weight));
    }
    final upright = await _draw(tester, weight: 400);
    final slanted = await _draw(tester, weight: 400, italic: true);

    // 5. Nothing new in the app's folders.
    final added = _files(root).difference(before);

    debugPrint(
      'SF Mono spike: regular=${regular.length} italic=${italic.length} '
      'ms=$ms missing=${missing.length} status=${status.isLoaded} '
      'width=${sfMono.toStringAsFixed(1)} '
      'jetbrains=${jetBrains.toStringAsFixed(1)} '
      'ink=${ink.values.map((v) => v.round()).join('<')} '
      'italicDiffers=${!listEquals(upright, slanted)} added=${added.length}',
    );

    expect(regular.length, greaterThan(100 * 1024));
    expect(italic.length, greaterThan(100 * 1024));
    expect(ms, lessThanOrEqualTo(150));
    expect(missing, isEmpty);
    expect(status, const ShellxFontStatus.loaded());
    expect(sfMono, closeTo(618, 2));
    expect(jetBrains, closeTo(600, 2));
    expect(ink[400]!, greaterThan(ink[300]!));
    expect(ink[600]!, greaterThan(ink[400]!));
    expect(ink[700]!, greaterThan(ink[600]!));
    expect(listEquals(upright, slanted), isFalse);
    expect(added, isEmpty);
  });
}

/// Where this app may write: macOS, the recipe's temporary HOME; iOS, the
/// app's container.
Directory _appRoot() => Platform.isIOS
    ? Directory.systemTemp.parent
    : Directory(Platform.environment['HOME']!);

Set<String> _files(Directory root) {
  final found = <String>{};
  try {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      found.add(entity.path);
    }
  } on FileSystemException {
    // A folder the OS keeps closed: nothing of ours is in it.
  }
  return found;
}

double _width(String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'mmmmmmmmmm',
      style: TextStyle(
        fontFamily: family,
        fontSize: 100,
        fontWeight: FontWeight.w400,
        fontVariations: const [FontVariation('wght', 400)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The RGBA pixels of a line of SF Mono at [weight], black on white.
Future<Uint8List> _draw(
  WidgetTester tester, {
  required double weight,
  bool italic = false,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFFFFFFF),
            padding: const EdgeInsets.all(4),
            child: Text(
              'Đăng nhập ShellX llll|||| mmmm',
              style: TextStyle(
                fontFamily: ShellxFonts.systemMono,
                fontSize: 32,
                color: const Color(0xFF000000),
                fontWeight: FontWeight.values[(weight ~/ 100) - 1],
                fontVariations: [FontVariation('wght', weight)],
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData())!;
    image.dispose();
    return bytes.buffer.asUint8List();
  }))!;
}

/// Sum of (255 − red) over the pixels: how much ink.
double _ink(Uint8List rgba) {
  var sum = 0.0;
  for (var i = 0; i < rgba.length; i += 4) {
    sum += 255 - rgba[i];
  }
  return sum;
}
