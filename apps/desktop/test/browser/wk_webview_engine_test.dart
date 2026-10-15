import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/wk_webview_engine.dart';
import 'package:shellx_desktop/src/tools/tool_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BrowserLoadErrorKind? kind(String domain, int code) =>
      switch (macErrorEvent(domain, code)) {
        LoadFailed(:final kind) => kind,
        _ => null,
      };

  test('NSURLError codes map to the D13 kinds, ATS included', () {
    const u = 'NSURLErrorDomain';
    expect(kind(u, -1004), BrowserLoadErrorKind.refused);
    expect(kind(u, -1022), BrowserLoadErrorKind.ats);
    expect(kind(u, -1003), BrowserLoadErrorKind.dns);
    expect(kind(u, -1006), BrowserLoadErrorKind.dns);
    expect(kind(u, -1001), BrowserLoadErrorKind.timeout);
    for (final c in [-1009, -1005, -1018, -1020]) {
      expect(kind(u, c), BrowserLoadErrorKind.unreachable, reason: '$c');
    }
    for (final c in [-1200, -1201, -1202, -1203, -1204, -1205, -1206]) {
      expect(kind(u, c), BrowserLoadErrorKind.certificate, reason: '$c');
    }
    expect(kind(u, -1100), BrowserLoadErrorKind.other);
    expect(macErrorEvent(u, -999), isNull, reason: 'a newer navigation');
  });

  test('WebKit 100 is a stopped download, 102 the guard\'s own cancel; a '
      'dead page is crashed', () {
    final url = Uri.parse('http://localhost:4000/export.csv');
    final download = macErrorEvent('WebKitErrorDomain', 100, url: url);
    expect(download, isA<DownloadBlocked>());
    expect((download! as DownloadBlocked).url, url);
    expect(macErrorEvent('WebKitErrorDomain', 102), isNull);
    expect(kind('WebKitErrorDomain', 101), BrowserLoadErrorKind.other);
    expect(switch (macErrorEvent('WKErrorDomain', 2, processTerminated: true)) {
      LoadFailed(:final kind) => kind,
      _ => null,
    }, BrowserLoadErrorKind.crashed);
    expect(kind('SomethingElse', 1), BrowserLoadErrorKind.other);
  });

  test('BrowserNativeMac: outbound calls and inbound events', () async {
    const channel = MethodChannel('test/browser');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final native = BrowserNativeMac(channel);
    final events = <BrowserEngineEvent>[];
    final windows = <Uri?>[];
    await native.attach(7, sink: events.add, newWindow: windows.add);
    await native.setForwardedChords(7, ['super+t']);
    await native.stop(7);
    await native.focus(7);
    await native.blur(7);
    await native.clearAll();
    expect(calls.map((c) => c.method), [
      'attach',
      'setForwardedChords',
      'stop',
      'focus',
      'blur',
      'clearWebsiteData',
    ]);
    expect(calls[1].arguments, {
      'id': 7,
      'chords': ['super+t'],
    });

    Future<void> inbound(String method, Map<String, Object?> args) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await inbound('shortcut', {'id': 7, 'chord': 'super+t'});
    await inbound('pointerDown', {'id': 7});
    await inbound('newWindow', {'id': 7, 'url': 'https://example.com/x'});
    await inbound('newWindow', {'id': 7});
    await inbound('download', {'id': 7, 'url': 'http://h/a.zip'});
    await inbound('shortcut', {'id': 99, 'chord': 'super+t'}); // not ours
    expect(events, hasLength(3));
    expect((events[0] as ShortcutForwarded).chord, 'super+t');
    expect(events[1], isA<ContentClicked>());
    expect((events[2] as DownloadBlocked).url, Uri.parse('http://h/a.zip'));
    expect(windows, [Uri.parse('https://example.com/x'), null]);
    native.detach(7);
    await inbound('pointerDown', {'id': 7});
    expect(events, hasLength(3));
    expect(calls.last.method, 'forget');
  });

  test('events and dialogs never print what the page holds (D24)', () {
    expect(
      UrlChanged(Uri.parse('http://x/secret')).toString(),
      'UrlChanged(…)',
    );
    expect(const TitleChanged('secret').toString(), 'TitleChanged(…)');
    expect(
      OpenOutside(Uri.parse('mailto:a@b.c'), newWindow: false).toString(),
      'OpenOutside(…)',
    );
    expect(
      const BrowserJsDialog(
        kind: BrowserJsDialogKind.prompt,
        message: 'secret',
      ).toString(),
      'BrowserJsDialog(prompt)',
    );
  });

  test('a page URL from WebKit is a URL with a scheme or nothing: no empty '
      'Uri for a load that failed before it committed', () async {
    expect(pageUriOf(null), isNull);
    expect(pageUriOf(''), isNull);
    expect(pageUriOf('not a url'), isNull);
    expect(
      pageUriOf('http://127.0.0.1:5173/x'),
      Uri.parse('http://127.0.0.1:5173/x'),
    );
    expect(pageUriOf('about:blank'), Uri.parse('about:blank'));

    // The native channel's URLs go the same way.
    const channel = MethodChannel('test/browser-urls');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final native = BrowserNativeMac(channel);
    final events = <BrowserEngineEvent>[];
    final windows = <Uri?>[];
    await native.attach(3, sink: events.add, newWindow: windows.add);
    Future<void> inbound(String method, Map<String, Object?> args) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await inbound('newWindow', {'id': 3, 'url': ''});
    await inbound('download', {'id': 3, 'url': ''});
    // A `blob:` or `data:` download link: BrowserNative sends no URL.
    await inbound('download', {'id': 3});
    expect(windows, [null]);
    expect(events.map((e) => (e as DownloadBlocked).url), [null, null]);
  });

  test('a new window (window.open, or a target=_blank link) goes outside '
      'for web, mail and phone, and nowhere else (D9)', () {
    for (final url in [
      'https://docs.example.com/',
      'mailto:a@b.c',
      'tel:+84123',
    ]) {
      final event = newWindowEvent(toolNavigation, Uri.parse(url));
      expect(event, isA<OpenOutside>(), reason: url);
      expect((event as OpenOutside).url, Uri.parse(url));
      expect(event.newWindow, isTrue);
    }
    for (final url in ['javascript:alert(1)', 'file:///x', 'data:,x']) {
      expect(
        newWindowEvent(toolNavigation, Uri.parse(url)),
        isA<NavigationBlocked>(),
        reason: url,
      );
    }
    expect(newWindowEvent(toolNavigation, null), isA<NavigationBlocked>());
  });

  test('the Web Inspector is best effort: below macOS 13.3 the plugin '
      'refuses it and the page still sets up (R28)', () async {
    final asked = <bool>[];
    await enableWebInspector((inspectable) async => asked.add(inspectable));
    expect(asked, [true]);
    await expectLater(
      enableWebInspector(
        (_) async =>
            throw PlatformException(code: 'FWFUnsupportedVersionError'),
      ),
      completes,
    );
  });
}
