import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';
import 'package:shellx_desktop/src/tools/tool_navigation.dart';

/// V2-3 §9: the real macOS engine in the real Runner, against a small
/// server: load and title, http to 127.0.0.1 (D19), the D9 navigation
/// rules (target=_blank links included), a refused port then the server up
/// (D13), a refused load after a loaded page that never says it finished
/// (the tool page's recovery URL), stopped downloads (a response, a blob:
/// link, a download link to the page's own server), a refused camera, a
/// JavaScript alert through ShellX, and a page that stays loaded when its
/// view leaves the tree and comes back (Review Focus 1). Run only in an
/// isolated build (plan Task 6 recipe): never with the app's real bundle id
/// or HOME.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String base;
  final pages = <String, String>{
    '/': '<title>Tool title</title><p>tool</p>',
    '/blocked': "<script>location.href = 'file:///etc/hosts'</script>",
    '/custom': "<script>location.href = 'shellx-test://x'</script>",
    '/mail': "<script>location.href = 'mailto:x@example.com'</script>",
    '/popup': "<script>window.open('/other', '_blank')</script>",
    '/blank-mail':
        '<a id="a" target="_blank" href="mailto:x@example.com">m</a>'
        "<script>document.getElementById('a').click()</script>",
    '/blank-web':
        '<a id="a" target="_blank" href="/other2">w</a>'
        "<script>document.getElementById('a').click()</script>",
    // The download pages click 2 s after their load: once the test has
    // cleared the events of that load.
    '/blob-download':
        '<script>onload = () => setTimeout(() => {'
        "const a = document.createElement('a'); a.download = 'x.txt'; "
        "a.href = URL.createObjectURL(new Blob(['x'])); "
        'document.body.append(a); a.click()}, 2000)</script>',
    '/csv-download':
        '<a id="a" download href="/report.csv">r</a>'
        '<script>onload = () => setTimeout(() => '
        "document.getElementById('a').click(), 2000)</script>",
    '/camera':
        '<script>(navigator.mediaDevices ? '
        'navigator.mediaDevices.getUserMedia({video: true}) : '
        "Promise.reject()).then(() => location.href = '/granted', "
        "() => location.href = '/denied')</script>",
    '/alert': "<script>alert('hello'); location.href = '/after-alert'</script>",
  };

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) {
      final res = req.response;
      if (req.uri.path == '/file.zip') {
        res.headers.contentType = ContentType('application', 'zip');
        res.headers.set('content-disposition', 'attachment; filename=a.zip');
        res.add([1, 2, 3]);
      } else if (req.uri.path == '/report.csv') {
        // No Content-Disposition: only the link's download attribute makes
        // this a download.
        res.headers.contentType = ContentType('text', 'csv');
        res.write('a,b\n1,2\n');
      } else {
        res.headers.contentType = ContentType.html;
        res.write(
          '<!doctype html><meta charset="utf-8">'
          '${pages[req.uri.path] ?? '<title>${req.uri.path}</title>'}',
        );
      }
      unawaited(res.close());
    });
  });

  tearDownAll(() => server.close(force: true));

  final dialogs = <BrowserJsDialog>[];
  late WkWebViewEngine engine;
  late List<BrowserEngineEvent> events;

  Future<void> show(WidgetTester tester, {bool view = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: view ? engine.buildView() : const SizedBox.shrink(),
            ),
          ),
        ),
      );

  Future<void> until(
    WidgetTester tester,
    bool Function() done,
    String what,
  ) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out: $what');
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  bool urlIs(String path) =>
      events.any((e) => e is UrlChanged && e.url.path == path);

  setUp(() {
    dialogs.clear();
    engine = WkWebViewEngine(
      native: BrowserNativeMac(),
      policy: toolNavigation,
      dialogs: (d) async {
        dialogs.add(d);
        return null;
      },
    );
    events = [];
    engine.events.listen(events.add);
  });

  tearDown(() => engine.dispose());

  testWidgets('loads http://127.0.0.1 (D19) and reads the title', (t) async {
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(
      t,
      () => events.any((e) => e is TitleChanged && e.title == 'Tool title'),
      'title',
    );
    expect(events.whereType<LoadFinished>(), isNotEmpty);
    expect(events.whereType<LoadFailed>(), isEmpty);
  });

  testWidgets('file: is blocked, mailto: and a new window go outside (D9)', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/blocked'));
    await until(t, () => events.any((e) => e is LoadFinished), 'blocked page');
    await t.pump(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      events.whereType<UrlChanged>().where((e) => e.url.scheme == 'file'),
      isEmpty,
    );
    events.clear();
    await engine.load(Uri.parse('$base/custom'));
    await until(
      t,
      () => events.any((e) => e is NavigationBlocked),
      'custom scheme',
    );
    events.clear();
    await engine.load(Uri.parse('$base/mail'));
    await until(
      t,
      () => events.any((e) => e is OpenOutside && e.url.scheme == 'mailto'),
      'mailto',
    );
    events.clear();
    await engine.load(Uri.parse('$base/popup'));
    await until(
      t,
      () => events.any(
        (e) => e is OpenOutside && e.newWindow && e.url.path == '/other',
      ),
      'new window',
    );
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // The new window never loaded in the tool.
    expect(urlIs('/other'), isFalse);
  });

  testWidgets('a refused port, then the server comes up (D13)', (t) async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await show(t);
    final url = Uri.parse('http://127.0.0.1:$port/');
    await engine.load(url);
    await until(
      t,
      () => events.any(
        (e) => e is LoadFailed && e.kind == BrowserLoadErrorKind.refused,
      ),
      'refused',
    );
    final up = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    addTearDown(() => up.close(force: true));
    up.listen((req) {
      req.response.headers.contentType = ContentType.html;
      req.response.write('<title>Up</title>');
      unawaited(req.response.close());
    });
    events.clear();
    await engine.load(url); // what the D13 retry does
    await until(
      t,
      () => events.any((e) => e is TitleChanged && e.title == 'Up'),
      'up',
    );
  });

  testWidgets('a refused load after a loaded page never finishes (D13)', (
    t,
  ) async {
    // The tool page's recovery URL counts on this: until a LoadFinished,
    // a retry loads the URL that failed, not the page that stays.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(t, () => events.any((e) => e is LoadFinished), 'page');
    events.clear();
    await engine.load(Uri.parse('http://127.0.0.1:$port/'));
    await until(
      t,
      () => events.any(
        (e) => e is LoadFailed && e.kind == BrowserLoadErrorKind.refused,
      ),
      'refused',
    );
    await t.pump(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(events.whereType<LoadFinished>(), isEmpty, reason: 'no finish');
  });

  testWidgets('a download is stopped, the page stays (D9)', (t) async {
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(t, () => events.any((e) => e is LoadFinished), 'page');
    events.clear();
    await engine.load(Uri.parse('$base/file.zip'));
    await until(t, () => events.any((e) => e is DownloadBlocked), 'download');
    final blocked = events.whereType<DownloadBlocked>().single;
    expect(blocked.url?.path, '/file.zip');
    expect(events.whereType<LoadFinished>(), isEmpty, reason: 'not shown');
  });

  testWidgets('a target=_blank link goes outside as a new window (D9)', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/blank-mail'));
    await until(
      t,
      () => events.any((e) => e is OpenOutside && e.url.scheme == 'mailto'),
      'target=_blank mailto',
    );
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(events.whereType<OpenOutside>().single.newWindow, isTrue);
    expect(events.whereType<NavigationBlocked>(), isEmpty);
    events.clear();
    await engine.load(Uri.parse('$base/blank-web'));
    await until(
      t,
      () => events.any((e) => e is OpenOutside && e.url.path == '/other2'),
      'target=_blank web link',
    );
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(events.whereType<OpenOutside>().single.newWindow, isTrue);
    // The link never loaded in the tool.
    expect(urlIs('/other2'), isFalse);
  });

  testWidgets('a blob: download link is stopped, the page stays (D9)', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/blob-download'));
    await until(t, () => events.any((e) => e is LoadFinished), 'page');
    events.clear();
    await until(t, () => events.any((e) => e is DownloadBlocked), 'download');
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(events.whereType<DownloadBlocked>().single.url, isNull);
    expect(events.whereType<LoadStarted>(), isEmpty, reason: 'page stays');
    expect(events.whereType<LoadFinished>(), isEmpty, reason: 'page stays');
  });

  testWidgets('a download link to the server is stopped, the page stays', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/csv-download'));
    await until(t, () => events.any((e) => e is LoadFinished), 'page');
    events.clear();
    await until(t, () => events.any((e) => e is DownloadBlocked), 'download');
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(events.whereType<DownloadBlocked>().single.url?.path, '/report.csv');
    expect(events.whereType<LoadStarted>(), isEmpty, reason: 'page stays');
    expect(events.whereType<LoadFinished>(), isEmpty, reason: 'page stays');
  });

  testWidgets('the camera is refused (D9)', (t) async {
    await show(t);
    await engine.load(Uri.parse('$base/camera'));
    await until(t, () => urlIs('/denied'), 'camera refused');
    expect(urlIs('/granted'), isFalse);
  });

  testWidgets('alert() goes through ShellX, then the page goes on (D9)', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/alert'));
    await until(t, () => urlIs('/after-alert'), 'after alert');
    expect(dialogs.single.kind, BrowserJsDialogKind.alert);
    expect(dialogs.single.message, 'hello');
  });

  testWidgets('the page stays loaded when its view leaves and comes back', (
    t,
  ) async {
    await show(t);
    await engine.load(Uri.parse('$base/'));
    await until(t, () => events.any((e) => e is LoadFinished), 'first load');
    events.clear();
    await show(t, view: false);
    await t.pump(const Duration(milliseconds: 300));
    await show(t);
    await t.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 100));
    expect(events.whereType<LoadStarted>(), isEmpty, reason: 'no reload');
    expect(events.whereType<LoadFailed>(), isEmpty);
    // Still live, still on /: only such an engine answers with the title.
    events.clear();
    await engine.reload();
    await until(
      t,
      () => events.any((e) => e is TitleChanged && e.title == 'Tool title'),
      'page still live',
    );
  });
}
