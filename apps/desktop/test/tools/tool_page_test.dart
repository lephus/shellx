import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';
import 'package:shellx_desktop/src/tools/tool_page.dart';

import '../support/fake_browser_engine.dart';

ToolEntry tool(String url) => ToolEntry(
  id: 'abcde12345',
  ws: 'default',
  name: 'Board',
  url: (parseToolUrl(url) as ToolUrlOk).url,
);

void main() {
  late FakeBrowserEngine engine;
  late BrowserDialogPresenter dialogs;
  final knocks = <String>[];
  var portUp = false;

  ToolPage page(ToolEntry t, {DateTime Function()? now}) => ToolPage(
    tool: t,
    engine: (d) {
      dialogs = d;
      return engine = FakeBrowserEngine();
    },
    knock: (host, port) async {
      knocks.add('$host:$port');
      return portUp;
    },
    now: now ?? DateTime.now,
  );

  setUp(() {
    knocks.clear();
    portUp = false;
  });

  test('nothing loads before the first show; the first show loads the '
      'tool (D14)', () {
    final p = page(tool('localhost:5173/board'));
    expect(engine.loads, isEmpty);
    p.setShown(true);
    expect(engine.loads, [Uri.parse('http://localhost:5173/board')]);
    expect(p.state.started, isTrue);
    p.setShown(false);
    p.setShown(true);
    expect(engine.loads, hasLength(1), reason: 'never reloaded by a show');
  });

  test('refused: retries after 1, 2, 4, 8 then every 10 s, only while '
      'shown; the page shows once the server is up (D13, Review Focus 3)', () {
    fakeAsync((async) {
      final p = page(tool('https://example.com/'));
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      expect(p.state.error, BrowserLoadErrorKind.refused);
      var loads = engine.loads.length;
      for (final wait in [1, 2, 4, 8, 10, 10]) {
        async.elapse(Duration(seconds: wait) - const Duration(milliseconds: 1));
        expect(engine.loads, hasLength(loads), reason: 'not before $wait s');
        async.elapse(const Duration(milliseconds: 1));
        expect(engine.loads, hasLength(++loads), reason: 'at $wait s');
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      }
      p.setShown(false);
      async.elapse(const Duration(seconds: 60));
      expect(engine.loads, hasLength(loads), reason: 'hidden: no retry');
      p.setShown(true);
      async.elapse(const Duration(seconds: 10));
      expect(engine.loads, hasLength(loads + 1));
      engine.emit(const LoadStarted());
      engine.emit(const LoadFinished());
      expect(p.state.error, isNull);
      async.elapse(const Duration(seconds: 60));
      expect(engine.loads, hasLength(loads + 1), reason: 'up: no retry');
    });
  });

  test('between slow reloads a local tool is knocked on every second; once '
      'its port answers the page loads at once (ruling R9, criterion 5)', () {
    fakeAsync((async) {
      page(tool('localhost:5173')).setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      for (final wait in [1, 2, 4, 8]) {
        async.elapse(Duration(seconds: wait));
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      }
      // The next reload is 10 s away now.
      final before = engine.loads.length;
      knocks.clear();
      async.elapse(const Duration(seconds: 3));
      expect(knocks, ['localhost:5173', 'localhost:5173', 'localhost:5173']);
      expect(engine.loads, hasLength(before));
      portUp = true;
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(engine.loads, hasLength(before + 1));
    });
  });

  test('no knock for a tool that is not on this computer', () {
    fakeAsync((async) {
      page(tool('nas.lan:8080')).setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      async.elapse(const Duration(seconds: 5));
      expect(knocks, isEmpty);
      expect(engine.loads, hasLength(2), reason: 'the 1 s reload only');
    });
  });

  test('a crash reloads once by itself; the next one shows "stopped" '
      '(D13)', () {
    final p = page(tool('localhost:5173'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('http://localhost:5173/deep')));
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(engine.loads.last, Uri.parse('http://localhost:5173/deep'));
    expect(p.state.error, isNull);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, BrowserLoadErrorKind.crashed);
    final loads = engine.loads.length;
    unawaited(p.reload());
    expect(engine.loads, hasLength(loads + 1), reason: 'user reload');
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, isNull, reason: 'a user reload starts over');
  });

  test('other errors show their panel and do not retry (D13)', () {
    fakeAsync((async) {
      final p = page(tool('localhost:5173'));
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.ats));
      async.elapse(const Duration(seconds: 30));
      expect(p.state.error, BrowserLoadErrorKind.ats);
      expect(engine.loads, hasLength(1));
    });
  });

  test('away from the tool, and back (D9)', () {
    final p = page(tool('localhost:4000'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('https://sso.example.com/login')));
    expect(p.state.awayFrom(p.tool), isTrue);
    unawaited(p.backToTool());
    expect(engine.loads.last, Uri.parse('http://localhost:4000/'));
    engine.emit(UrlChanged(Uri.parse('http://localhost:4000/x')));
    expect(p.state.awayFrom(p.tool), isFalse);
  });

  test('outside links, downloads, keys and clicks reach the window (D9, '
      'D10)', () {
    final p = page(tool('localhost:4000'));
    final outside = <Uri>[];
    final chords = <String>[];
    var clicks = 0;
    p.onOpenOutside = outside.add;
    p.onShortcut = chords.add;
    p.onContentClicked = () => clicks++;
    p.setShown(true);
    engine.emit(OpenOutside(Uri.parse('mailto:a@b.c'), newWindow: false));
    engine.emit(const ShortcutForwarded('super+t'));
    engine.emit(const ContentClicked());
    engine.emit(const NavigationBlocked());
    engine.emit(DownloadBlocked(url: Uri.parse('http://localhost:4000/a.zip')));
    expect(outside, [Uri.parse('mailto:a@b.c')]);
    expect(chords, ['super+t']);
    expect(clicks, 1);
    expect(p.state.download, Uri.parse('http://localhost:4000/a.zip'));
    p.dismissDownload();
    expect(p.state.download, isNull);
  });

  test('five outside opens per 10 s reach the window, the rest go; '
      'dialogs count apart (D9, ruling on R10)', () async {
    var now = DateTime(2026, 10, 15, 9);
    final p = page(tool('localhost:4000'), now: () => now);
    final outside = <Uri>[];
    var shown = 0;
    p.onOpenOutside = outside.add;
    p.presenter = (d) async {
      shown++;
      return null;
    };
    final popup = OpenOutside(Uri.parse('https://a.test/'), newWindow: true);
    for (var i = 0; i < kToolDialogBurst; i++) {
      engine.emit(popup);
      now = now.add(const Duration(seconds: 1));
    }
    expect(outside, hasLength(kToolDialogBurst), reason: 'five in 5 s');
    engine.emit(popup);
    expect(outside, hasLength(kToolDialogBurst), reason: 'the sixth goes');
    const alert = BrowserJsDialog(
      kind: BrowserJsDialogKind.alert,
      message: 'Hi',
    );
    for (var i = 0; i < kToolDialogBurst; i++) {
      await dialogs(alert);
    }
    expect(shown, kToolDialogBurst, reason: 'dialogs count apart');
    now = now.add(kToolDialogWindow + const Duration(seconds: 1));
    engine.emit(popup);
    expect(outside, hasLength(kToolDialogBurst + 1), reason: 'calm again');
  });

  test('a new URL reloads the page there; a new name does not (D23)', () {
    final p = page(tool('localhost:4000'));
    p.setShown(true);
    p.retarget(p.tool.copyWith(name: 'Other'));
    expect(engine.loads, hasLength(1));
    p.retarget(p.tool.copyWith(url: 'http://localhost:4001/'));
    expect(engine.loads.last, Uri.parse('http://localhost:4001/'));
  });

  test('dialogs: shown while presented, default answers otherwise, and a '
      'flood is answered by itself (ruling R10)', () async {
    var now = DateTime(2026, 10, 15, 9);
    final p = page(tool('localhost:4000'), now: () => now);
    const confirm = BrowserJsDialog(
      kind: BrowserJsDialogKind.confirm,
      message: 'Delete?',
    );
    expect(await dialogs(confirm), isFalse, reason: 'no presenter');
    var shown = 0;
    p.presenter = (d) async {
      shown++;
      return true;
    };
    for (var i = 0; i < kToolDialogBurst - 1; i++) {
      expect(await dialogs(confirm), isTrue);
    }
    expect(await dialogs(confirm), isFalse, reason: 'flood');
    expect(shown, kToolDialogBurst - 1);
    now = now.add(kToolDialogWindow + const Duration(seconds: 1));
    expect(await dialogs(confirm), isTrue, reason: 'calm again');
  });

  test('a disposed page shows no dialog: each kind gets its default '
      'answer (ruling)', () async {
    final p = page(tool('localhost:4000'));
    var shown = 0;
    p.presenter = (d) async {
      shown++;
      return d.kind == BrowserJsDialogKind.prompt ? 'typed' : true;
    };
    BrowserJsDialog of(BrowserJsDialogKind kind) =>
        BrowserJsDialog(kind: kind, message: 'Still there?');
    expect(await dialogs(of(BrowserJsDialogKind.confirm)), isTrue);
    p.dispose();
    expect(await dialogs(of(BrowserJsDialogKind.alert)), isNull);
    expect(await dialogs(of(BrowserJsDialogKind.confirm)), isFalse);
    expect(await dialogs(of(BrowserJsDialogKind.prompt)), isNull);
    expect(shown, 1, reason: 'the presenter is never called once disposed');
  });

  test('dispose stops retries and disposes the engine', () {
    fakeAsync((async) {
      final p = page(tool('localhost:5173'));
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      p.dispose();
      async.elapse(const Duration(seconds: 30));
      expect(engine.loads, hasLength(1));
      expect(engine.disposed, isTrue);
      expect(knocks, isEmpty);
    });
  });

  test('retry delays are 1, 2, 4, 8, then 10 s', () {
    expect(
      [for (var i = 0; i < 7; i++) toolRetryDelay(i).inSeconds],
      [1, 2, 4, 8, 10, 10, 10],
    );
  });

  test('toString never shows the URL or the name (D24)', () {
    final p = page(tool('localhost:4000/secret'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('http://localhost:4000/secret/deep')));
    engine.emit(DownloadBlocked(url: Uri.parse('http://localhost:4000/a.zip')));
    expect(p.state.toString(), 'ToolPageState(…)');
    expect(p.toString(), 'ToolPage(…)');
  });
}
