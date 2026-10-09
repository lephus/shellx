import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';

/// A6 Task 7 smoke: the real WkWebViewEngine in the real Runner — load,
/// title through getTitle, a blocked scheme, a blocked download.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WkWebViewEngine loads, reads the title, blocks mailto and '
      'downloads', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final res = req.response;
      if (req.uri.path == '/file.zip') {
        res.headers.contentType = ContentType('application', 'zip');
        res.headers.set('content-disposition', 'attachment; filename=a.zip');
        res.add([1, 2, 3]);
      } else {
        res.headers.contentType = ContentType.html;
        res.write(
          '<!doctype html><title>Smoke title</title><body>'
          '<a id="m" href="mailto:x@y.z">m</a></body>',
        );
      }
      res.close();
    });

    final engine = WkWebViewEngine(native: BrowserNativeMac(), bootstrap: '');
    addTearDown(engine.dispose);
    final events = <BrowserEngineEvent>[];
    engine.events.listen(events.add);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 600, height: 400, child: engine.buildView()),
      ),
    );

    Future<void> until(bool Function() test, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (!test()) {
        if (DateTime.now().isAfter(end)) fail('timed out: $what');
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    final base = 'http://127.0.0.1:${server.port}';
    await engine.load(Uri.parse('$base/'));
    await until(
      () => events.any((e) => e is TitleChanged && e.title == 'Smoke title'),
      'title',
    );
    expect(events.whereType<LoadFinished>(), isNotEmpty);

    // Top-level navigation to a scheme a pane may not show.
    events.clear();
    await engine.runScript("location.href = 'mailto:x@y.z'");
    await until(() => events.any((e) => e is NavigationBlocked), 'mailto');

    // A download is cancelled, not saved.
    events.clear();
    await engine.load(Uri.parse('$base/file.zip'));
    await until(() => events.any((e) => e is DownloadBlocked), 'download');
  });
}
