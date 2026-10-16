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

  ToolPage page(ToolEntry t, {DateTime Function()? now, ToolKnock? knock}) =>
      ToolPage(
        tool: t,
        engine: (d) {
          dialogs = d;
          return engine = FakeBrowserEngine();
        },
        knock:
            knock ??
            (host, port) async {
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

  test('a URL the app newly asks for — an edit, "Back to tool" — restarts '
      'the retries at 1 s, then 2 s; an edit made while hidden retries 1 s '
      'after it shows (D13, D23, D9)', () {
    fakeAsync((async) {
      // Not on this computer: no knock between the reloads.
      final p = page(tool('https://example.com/'));
      void refuse() =>
          engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      // Refused for 15 s: the schedule is at 10 s.
      void climb() {
        for (final wait in [1, 2, 4, 8]) {
          async.elapse(Duration(seconds: wait));
          refuse();
        }
      }

      void expectRetriesAt(List<int> waits, String why) {
        for (final wait in waits) {
          final loads = engine.loads.length;
          async.elapse(
            Duration(seconds: wait) - const Duration(milliseconds: 1),
          );
          expect(engine.loads, hasLength(loads), reason: '$why: not yet');
          async.elapse(const Duration(milliseconds: 1));
          expect(engine.loads, hasLength(loads + 1), reason: '$why: $wait s');
          refuse();
        }
      }

      p.setShown(true);
      refuse();
      climb();
      p.retarget(p.tool.copyWith(url: 'https://example.org/'));
      expect(engine.loads.last, Uri.parse('https://example.org/'));
      refuse();
      expectRetriesAt([1, 2], 'the edit');
      climb();
      unawaited(p.backToTool());
      expect(engine.loads.last, Uri.parse('https://example.org/'));
      refuse();
      expectRetriesAt([1, 2], 'Back to tool');
      climb();
      p.setShown(false);
      p.retarget(p.tool.copyWith(url: 'https://example.net/'));
      refuse();
      async.elapse(const Duration(seconds: 30));
      final loads = engine.loads.length;
      p.setShown(true);
      expectRetriesAt([1, 2], 'the edit made while hidden');
      expect(engine.loads.sublist(loads), [
        Uri.parse('https://example.net/'),
        Uri.parse('https://example.net/'),
      ]);
      p.dispose();
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

  test('toolKnockHost: localhost for *.localhost, 127.0.0.1 for 0.0.0.0, '
      'any other host unchanged (ruling R9, D11)', () {
    expect(toolKnockHost('app.localhost'), 'localhost');
    expect(toolKnockHost('a.b.localhost'), 'localhost');
    expect(toolKnockHost('App.LocalHost'), 'localhost');
    expect(toolKnockHost('0.0.0.0'), '127.0.0.1');
    for (final same in [
      'localhost',
      '127.0.0.1',
      '127.8.9.10',
      '::1',
      'nas.lan',
      'localhost.example.com',
      'notlocalhost',
    ]) {
      expect(toolKnockHost(same), same);
    }
  });

  test('the knock dials loopback for a tool at a *.localhost name or at '
      '0.0.0.0; any other host as it is (ruling R9, D11)', () {
    fakeAsync((async) {
      for (final (url, dialed) in [
        ('app.localhost:5173', 'localhost:5173'),
        ('api.dev.localhost:8000', 'localhost:8000'),
        ('0.0.0.0:8080', '127.0.0.1:8080'),
        ('127.0.0.2:3000', '127.0.0.2:3000'),
        ('[::1]:3000', '::1:3000'),
      ]) {
        final p = page(tool(url));
        p.setShown(true);
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
        async.elapse(const Duration(seconds: 1)); // the 1 s reload
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
        knocks.clear();
        async.elapse(const Duration(seconds: 1));
        expect(knocks, [dialed], reason: url);
        p.dispose();
      }
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

  test('after an edit to a URL that is not up yet, every recovery loads it: '
      'the retry, the knock, Reload, a crash (D23, ruling)', () {
    fakeAsync((async) {
      final b = Uri.parse('http://localhost:5174/');
      final p = page(tool('localhost:5173'));
      p.setShown(true);
      engine.emit(UrlChanged(Uri.parse('http://localhost:5173/')));
      engine.emit(const LoadFinished());
      p.retarget(p.tool.copyWith(url: 'http://localhost:5174/'));
      // WebKit may report the page left behind as the address again.
      engine.emit(UrlChanged(Uri.parse('http://localhost:5173/')));
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      var loads = engine.loads.length;
      async.elapse(const Duration(seconds: 1));
      expect(engine.loads.sublist(loads), [b], reason: 'the retry');
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      knocks.clear();
      async.elapse(const Duration(seconds: 1));
      expect(knocks, ['localhost:5174'], reason: "the new URL's port");
      loads = engine.loads.length;
      unawaited(p.reload());
      engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
      expect(engine.loads.sublist(loads), [b, b], reason: 'Reload, a crash');
    });
  });

  test('a knock still out for a URL edited away loads nothing when its port '
      'answers (D23, ruling)', () {
    fakeAsync((async) {
      final oldPort = Completer<bool>();
      final p = page(
        tool('localhost:5173'),
        knock: (host, port) {
          knocks.add('$host:$port');
          return port == 5173 ? oldPort.future : Future.value(false);
        },
      );
      p.setShown(true);
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      async.elapse(const Duration(seconds: 1));
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      async.elapse(const Duration(seconds: 1));
      expect(knocks, ['localhost:5173'], reason: 'out, no answer yet');
      p.retarget(p.tool.copyWith(url: 'http://localhost:5174/'));
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      final loads = engine.loads.length;
      oldPort.complete(true);
      async.flushMicrotasks();
      expect(engine.loads, hasLength(loads), reason: 'the old URL stays');
    });
  });

  test('refused after "Back to tool", the retry loads the tool; refused on '
      "the page's own link, the page it was on (D9, D13, ruling)", () {
    fakeAsync((async) {
      final t = Uri.parse('http://localhost:4000/');
      final p = page(tool('localhost:4000'));
      p.setShown(true);
      engine.emit(UrlChanged(Uri.parse('https://sso.example.com/login')));
      engine.emit(const LoadFinished());
      unawaited(p.backToTool());
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      var loads = engine.loads.length;
      async.elapse(const Duration(seconds: 1));
      expect(engine.loads.sublist(loads), [t], reason: 'the tool, not SSO');
      // Up again at /deep; then a link of the page's own is refused.
      final deep = Uri.parse('http://localhost:4000/deep');
      engine.emit(UrlChanged(deep));
      engine.emit(const LoadFinished());
      engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
      loads = engine.loads.length;
      async.elapse(const Duration(seconds: 1));
      expect(engine.loads.sublist(loads), [deep], reason: 'the page it was on');
    });
  });

  test('a crash reloads once by itself; the next one shows "stopped" '
      '(D13)', () {
    final p = page(tool('localhost:5173'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('http://localhost:5173/deep')));
    engine.emit(const LoadFinished());
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

  test('an edited URL and "Back to tool" get their own crash reload (D13, '
      'D23, D9)', () {
    final p = page(tool('localhost:5173'));
    p.setShown(true);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, BrowserLoadErrorKind.crashed, reason: 'used up');
    p.retarget(p.tool.copyWith(url: 'http://localhost:5174/'));
    var loads = engine.loads.length;
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, isNull, reason: 'the edit: reloaded by itself');
    expect(engine.loads.sublist(loads), [Uri.parse('http://localhost:5174/')]);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, BrowserLoadErrorKind.crashed);
    unawaited(p.backToTool());
    loads = engine.loads.length;
    engine.emit(const LoadFailed(BrowserLoadErrorKind.crashed));
    expect(p.state.error, isNull, reason: 'Back to tool: reloaded by itself');
    expect(engine.loads.sublist(loads), [Uri.parse('http://localhost:5174/')]);
  });

  test('✕ ends the loading state; ↻ after ✕ of the first load loads the '
      'tool, never a native reload of about:blank (D17, R25)', () {
    final t = Uri.parse('http://localhost:4000/');
    final p = page(tool('localhost:4000'));
    p.setShown(true);
    expect(p.state.loading, isTrue);
    unawaited(p.stop());
    expect(engine.calls, ['stop']);
    expect(p.state.loading, isFalse, reason: '✕ turns back into ↻');
    unawaited(p.reload());
    expect(engine.loads, [t, t]);
    expect(engine.calls, ['stop'], reason: 'no engine.reload()');
  });

  test('↻ after ✕ of an edit loads the new URL; once a page finished '
      'loading, ↻ reloads it natively (D17, D23)', () {
    final b = Uri.parse('http://localhost:4001/');
    final p = page(tool('localhost:4000'));
    p.setShown(true);
    engine.emit(UrlChanged(Uri.parse('http://localhost:4000/')));
    engine.emit(const LoadFinished());
    p.retarget(p.tool.copyWith(url: 'http://localhost:4001/'));
    unawaited(p.stop());
    var loads = engine.loads.length;
    unawaited(p.reload());
    expect(engine.loads.sublist(loads), [b], reason: 'what was asked');
    engine.emit(UrlChanged(b));
    engine.emit(const LoadFinished());
    loads = engine.loads.length;
    unawaited(p.reload());
    expect(engine.calls.last, 'reload', reason: 'nothing pending');
    expect(engine.loads, hasLength(loads));
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
